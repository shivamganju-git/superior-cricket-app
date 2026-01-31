import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/youtube_config.dart';
import '../config/supabase_config.dart';

/// YouTube Data API v3 Service
/// Used to check if a channel is currently live streaming
class YouTubeApiService {
  static const String _baseUrl = YouTubeConfig.apiBaseUrl;

  /// Get the channel ID from a channel handle (e.g., @PITCH-POINT)
  /// Returns channel ID or null if not found
  static Future<String?> getChannelIdFromHandle(String handle) async {
    try {
      // Remove @ if present
      final cleanHandle = handle.replaceFirst('@', '');
      
      final url = Uri.parse(
        '$_baseUrl/search?part=snippet&q=$cleanHandle&type=channel&key=${YouTubeConfig.apiKey}&maxResults=1'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] != null && data['items'].isNotEmpty) {
          final channelId = data['items'][0]['snippet']['channelId'] as String;
          print('✅ Found channel ID: $channelId for handle: $handle');
          return channelId;
        } else {
          print('⚠️ No channel found for handle: $handle');
        }
      } else {
        print('❌ API Error: ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      print('❌ Error getting channel ID: $e');
      return null;
    }
  }

  /// Check if a channel is currently live streaming
  /// Returns the live video ID if live, null otherwise
  /// Uses exact API format: GET /search?part=id&channelId=CHANNEL_ID&eventType=live&type=video&key=API_KEY
  static Future<String?> getActiveLiveVideoId(String channelId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/search?part=id&channelId=$channelId&eventType=live&type=video&key=${YouTubeConfig.apiKey}&maxResults=1'
      );
      
      print('🔍 Checking for live stream on channel: $channelId');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['items'] != null && data['items'].isNotEmpty) {
          // Extract items[0].id.videoId as LIVE_VIDEO_ID
          final videoId = data['items'][0]['id']['videoId'] as String;
          print('✅ Found live stream! Video ID: $videoId');
          return videoId;
        } else {
          print('⚠️ No live stream found for channel: $channelId');
        }
      } else {
        print('❌ API Error: ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      print('❌ Error checking live status: $e');
      return null;
    }
  }

  /// Get live video ID directly from channel handle
  /// This is a convenience method that combines getChannelIdFromHandle and getActiveLiveVideoId
  static Future<String?> getLiveVideoIdFromChannelHandle(String handle) async {
    final channelId = await getChannelIdFromHandle(handle);
    if (channelId == null) return null;
    return await getActiveLiveVideoId(channelId);
  }

  /// Get live video ID from channel ID
  /// Use this if you already have the channel ID
  static Future<String?> getLiveVideoIdFromChannelId(String channelId) async {
    return await getActiveLiveVideoId(channelId);
  }

  /// Create a new Live Broadcast
  /// Requires OAuth 2.0 Access Token
  static Future<Map<String, dynamic>> createLiveBroadcast({
    required String accessToken,
    required String title,
    required String description,
    required DateTime scheduledStartTime,
    String privacyStatus = 'unlisted', // 'public', 'unlisted', or 'private'
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/liveBroadcasts?part=snippet,status,contentDetails');
      
      final body = {
        'snippet': {
          'title': title,
          'description': description,
          'scheduledStartTime': scheduledStartTime.toUtc().toIso8601String(),
        },
        'status': {
          'privacyStatus': privacyStatus,
          'selfDeclaredMadeForKids': false,
        },
        'contentDetails': {
          'enableAutoStart': true,
          'enableAutoStop': true,
          'monitorStream': {
            'enableMonitorStream': false,
          },
        }
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create broadcast: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error creating broadcast: $e');
      rethrow;
    }
  }

  /// Create a new Live Stream (or get existing settings)
  /// Requires OAuth 2.0 Access Token
  static Future<Map<String, dynamic>> createLiveStream({
    required String accessToken,
    required String title,
    String frameRate = '30fps',
    String ingestionType = 'rtmp',
    String resolution = '720p',
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/liveStreams?part=snippet,cdn,status');
      
      final body = {
        'snippet': {
          'title': title,
        },
        'cdn': {
          'frameRate': frameRate,
          'ingestionType': ingestionType,
          'resolution': resolution,
        }
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create stream: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error creating stream: $e');
      rethrow;
    }
  }

  /// Bind a Live Broadcast to a Live Stream
  /// Requires OAuth 2.0 Access Token
  static Future<Map<String, dynamic>> bindBroadcast({
    required String accessToken,
    required String broadcastId,
    required String streamId,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/liveBroadcasts/bind?id=$broadcastId&part=id,contentDetails&streamId=$streamId'
      );

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to bind broadcast: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error binding broadcast: $e');
      rethrow;
    }
  }

  /// Transition Live Broadcast Status
  /// Requires OAuth 2.0 Access Token
  /// [status] can be 'testing', 'live', or 'complete'
  static Future<Map<String, dynamic>> transitionBroadcast({
    required String accessToken,
    required String broadcastId,
    required String status,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/liveBroadcasts/transition?id=$broadcastId&broadcastStatus=$status&part=id,status'
      );

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to transition broadcast: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error transitioning broadcast: $e');
      rethrow;
    }
  }

  /// Refresh YouTube Access Token using Refresh Token
  static Future<String> refreshAccessToken(String refreshToken) async {
    try {
      final url = Uri.parse('https://oauth2.googleapis.com/token');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': YouTubeConfig.clientId,
          'client_secret': YouTubeConfig.clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['access_token'];
      } else {
        throw Exception('Failed to refresh access token: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error refreshing token: $e');
      rethrow;
    }
  }

  /// Assign a free channel from the pool for a match
  /// Returns a map with channel details including fresh access token
  static Future<Map<String, dynamic>> assignChannel(String matchId) async {
    try {
      final response = await SupabaseConfig.client.rpc(
        'get_free_youtube_channel',
        params: {'p_match_id': matchId},
      );

      if (response == null || response['error'] != null) {
        throw Exception(response?['error'] ?? 'No free YouTube channels available');
      }

      // Refresh the access token before returning
      final refreshToken = response['refresh_token'] as String;
      final accessToken = await refreshAccessToken(refreshToken);

      return {
          'id': response['id'],
          'channel_id': response['channel_id'],
          'access_token': accessToken,
          'stream_key': response['stream_key'],
      };
    } catch (e) {
      print('❌ Error assigning YouTube channel: $e');
      rethrow;
    }
  }

  /// Get the channel currently assigned to this match
  static Future<Map<String, dynamic>> getAssignedChannel(String matchId) async {
    try {
      final response = await SupabaseConfig.client.rpc(
        'get_assigned_youtube_channel',
        params: {'p_match_id': matchId},
      );

      if (response == null || response['error'] != null) {
        throw Exception(response?['error'] ?? 'No channel assigned to this match');
      }

      final refreshToken = response['refresh_token'] as String;
      final accessToken = await refreshAccessToken(refreshToken);

      return {
          'id': response['id'],
          'channel_id': response['channel_id'],
          'access_token': accessToken,
          'stream_key': response['stream_key'],
      };
    } catch (e) {
      print('❌ Error getting assigned YouTube channel: $e');
      rethrow;
    }
  }

  /// Release a channel back to the pool
  static Future<void> releaseChannel(String matchId) async {
    try {
      await SupabaseConfig.client.rpc(
        'release_youtube_channel',
        params: {'p_match_id': matchId},
      );
      print('✅ YouTube channel released for match: $matchId');
    } catch (e) {
      print('❌ Error releasing YouTube channel: $e');
    }
  }

  /// Save match video replay info
  static Future<void> saveMatchVideo({
      required String matchId,
      required String videoId,
      String? replayUrl,
  }) async {
    try {
      await SupabaseConfig.client.from('match_videos').insert({
        'match_id': matchId,
        'video_id': videoId,
        'replay_url': replayUrl ?? 'https://www.youtube.com/watch?v=$videoId',
        'status': 'archived',
      });
      print('✅ Match video saved: $videoId');
    } catch (e) {
      print('❌ Error saving match video: $e');
    }
  }
}


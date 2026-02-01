import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/services/mux_service.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:rtmp_broadcaster/camera.dart';
import '../../../../core/services/youtube_api_service.dart';


/// Go Live Screen
/// Allows user to start live streaming from their camera
class GoLiveScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String matchTitle;
  final bool isDraft; // If true, match hasn't been created yet
  
  const GoLiveScreen({
    super.key,
    required this.matchId,
    required this.matchTitle,
    this.isDraft = false,
  });

  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  CameraController? _cameraController;
  final GlobalKey _scoreboardKey = GlobalKey();
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isLoading = false;
  String _userPlan = 'loading';
  String? _errorMessage;
  String? _muxStreamId;
  String? _rtmpUrl;
  String? _hlsPlaybackUrl;
  Timer? _statusCheckTimer;
  Timer? _overlayUpdateTimer;
  String? _youtubeBroadcastId;
  String? _youtubeStreamId;
  String? _youtubeStreamKey;

  
  // Live Scoreboard Data
  Map<String, dynamic>? _liveScorecard;
  String? _team1Name;
  String? _team2Name;
  String? _tossWinner;
  String? _tossDecision;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _fetchUserPlan();
    _subscribeToLiveScorecard();
  }

  Future<void> _fetchUserPlan() async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        final profile = await ref.read(profileRepositoryProvider).getProfileById(userId);
        if (mounted) {
          setState(() {
            _userPlan = profile?.subscriptionPlan ?? 'basic';
          });
        }
      } else {
         setState(() {
            _userPlan = 'basic';
          });
      }
    } catch (e) {
      print('Error fetching plan: $e');
      if (mounted) {
        setState(() {
          _userPlan = 'basic'; // Default
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _statusCheckTimer?.cancel();
    _scorecardPollTimer?.cancel();
    _overlayUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        setState(() {
          _errorMessage = 'Camera permission is required to go live';
        });
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        return;
      }

      // Initialize camera (use back camera by default)
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Lowered from high for latency
        enableAudio: true,
        androidUseOpenGL: true, // Enable OpenGL for potential filter support
      );

      await _cameraController!.initialize();
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing camera: $e';
      });
    }
  }

  Future<void> _startStreaming() async {
    if (!_isInitialized || _cameraController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not initialized')),
      );
      return;
    }

    // Check Plan Logic
    bool shouldRecord = false;
    
    // Refresh plan just in case
    await _fetchUserPlan();

    if (_userPlan != 'pro') {
         // Show Upgrade Dialog for Basic users
         final continueBasic = await _showUpgradeDialog();
         
         // If continueBasic is null, user cancelled (tapped outside or back)
         if (continueBasic == null) return;
         
         // If continueBasic is false, user chose "Upgrade to Pro"
         if (!continueBasic) {
           if (mounted) {
             final upgraded = await context.push<bool>('/subscription');
             if (upgraded == true) {
                await _fetchUserPlan(); // Refresh after upgrade
                await ref.read(authStateProvider.notifier).refreshAuth(); // Refresh global user state
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are now Pro! Tap Go Live again.')),
                  );
                }
             }
           }
           return;
         }
         
         // User chose "Continue as Basic" - Disable recording
         shouldRecord = false;
      } else {
        // Pro User - Enable recording
        shouldRecord = true;
      }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Assign a Pitch Point YouTube Channel from the pool
      String? accessToken;
      try {
        final channelData = await YouTubeApiService.assignChannel(widget.matchId);
        accessToken = channelData['access_token'];
        _youtubeStreamKey = channelData['stream_key'];
        
        print('✅ Assigned Pitch Point Channel: ${channelData['channel_id']}');
      } catch (poolError) {
        print('❌ Channel Pool assignment failed: $poolError');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('YouTube Assignment Failed: ${poolError.toString().replaceFirst('Exception: ', '')}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        setState(() => _isLoading = false);
        return; // BLOCK ACTION
      }
      
      if (accessToken != null) {
        try {
            // 2. Create YouTube Broadcast on assigned channel
            final broadcast = await YouTubeApiService.createLiveBroadcast(
                accessToken: accessToken,
                title: widget.matchTitle,
                description: 'Live cricket match: ${widget.matchTitle}',
                scheduledStartTime: DateTime.now(),
                privacyStatus: 'public',
            );
            _youtubeBroadcastId = broadcast['id'];
            
            // 3. Get/Create Live Stream settings
            // If the assigned channel has a persistent stream_key, we use that.
            // Otherwise we create a new temporary one.
            if (_youtubeStreamKey == null) {
                final stream = await YouTubeApiService.createLiveStream(
                    accessToken: accessToken,
                    title: 'PitchPoint Stream - ${widget.matchId}',
                );
                _youtubeStreamId = stream['id'];
                _youtubeStreamKey = stream['cdn']['ingestionInfo']['streamName'];
                
                // Bind Broadcast to Stream
                await YouTubeApiService.bindBroadcast(
                    accessToken: accessToken,
                    broadcastId: _youtubeBroadcastId!,
                    streamId: _youtubeStreamId!,
                );
            }
            
            print('✅ YouTube Broadcast created: $_youtubeBroadcastId');
        } catch (ytError) {
            print('⚠️ YouTube Integration failed (proceeding without yt): $ytError');
            // We'll proceed with just Mux if YouTube fails
        }
      }

      // Get YouTube stream key from backend (secure) - optional
      // Priority: 1. Locally generated (from OAuth), 2. Backend provided
      String? youtubeStreamKey = _youtubeStreamKey;
      if (youtubeStreamKey == null) {
        try {
            youtubeStreamKey = await _getYouTubeStreamKey();
        } catch (e) {
            print('YouTube stream key not available from backend: $e');
        }
      }
      
      MuxLiveStreamResponse? muxResponse;
      try {
        muxResponse = await MuxService.createLiveStream(
          matchId: widget.matchId,
          matchTitle: widget.matchTitle,
          youtubeStreamKey: youtubeStreamKey,
          shouldRecord: shouldRecord,
        );

        setState(() {
          _muxStreamId = muxResponse!.id;
          _rtmpUrl = muxResponse.rtmpUrl;
          _hlsPlaybackUrl = muxResponse.hlsPlaybackUrl;
        });
      } catch (muxError) {
        print('⚠️ Mux creation failed: $muxError');
        
        // CHECK FOR FALLBACK: If Mux fails but we have a YouTube stream key, 
        // we can stream DIRECTLY to YouTube (bypassing Mux).
        if (youtubeStreamKey != null && youtubeStreamKey.isNotEmpty) {
          print('🚀 Using Direct YouTube Fallback...');
          setState(() {
            _muxStreamId = 'youtube-fallback';
            _rtmpUrl = 'rtmp://a.rtmp.youtube.com/live2/$youtubeStreamKey';
            _hlsPlaybackUrl = 'https://www.youtube.com/watch?v=$_youtubeBroadcastId';
          });
          
          // Create a mock response for _saveStreamInfo
          muxResponse = MuxLiveStreamResponse(
            id: 'youtube-fallback',
            status: 'active',
            rtmpUrl: _rtmpUrl,
            hlsPlaybackUrl: _hlsPlaybackUrl,
          );
        } else {
          // If no YouTube fallback possible, rethrow to global catch
          rethrow;
        }
      }

      // Save stream info to database
      if (muxResponse != null) {
        await _saveStreamInfo(muxResponse);
      }

      // Signal Mux that stream is active (BYPASS FOR TESTING)
      // await MuxService.signalStreamActive(muxResponse.id);

      // If YouTube was created, transition it to 'live' after stream starts
      if (accessToken != null && _youtubeBroadcastId != null) {
          // Note: Standard workflow is testing -> live
          // But with enableAutoStart=true, it might start automatically
          // We'll transition to live just in case
          try {
              await YouTubeApiService.transitionBroadcast(
                  accessToken: accessToken,
                  broadcastId: _youtubeBroadcastId!,
                  status: 'live',
              );
              
              // Save video info for later replay
              await YouTubeApiService.saveMatchVideo(
                matchId: widget.matchId,
                videoId: _youtubeBroadcastId!,
              );
          } catch (e) {
              print('Error transitioning to live: $e');
          }
      }

      // Start RTMP streaming
      if (_rtmpUrl != null) {
        await _startRTMPStream(_rtmpUrl!);
      }

      // If YouTube was created, transition it to 'live' after stream starts
      if (accessToken != null && _youtubeBroadcastId != null) {
          // Note: Standard workflow is testing -> live
          // But with enableAutoStart=true, it might start automatically
          // We'll transition to live just in case
          try {
              await YouTubeApiService.transitionBroadcast(
                  accessToken: accessToken,
                  broadcastId: _youtubeBroadcastId!,
                  status: 'live',
              );
          } catch (e) {
              print('Error transitioning to live: $e');
          }
      }

      setState(() {
        _isStreaming = true;
        _isLoading = false;
      });

      // Start periodic status check
      _startStatusCheck();
      
      // Start scorecard polling if not already started
      if (_scorecardPollTimer == null || !_scorecardPollTimer!.isActive) {
        _subscribeToLiveScorecard();
      }
      
      // Start periodic overlay updates to ensure it stays in sync
      _overlayUpdateTimer?.cancel();
      _overlayUpdateTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (mounted && _isStreaming) {
          _updateStreamOverlay();
        } else {
          timer.cancel();
        }
      });
      
      // Initial overlay update after stream starts
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isStreaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateStreamOverlay();
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live stream started! Broadcasting to YouTube...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Error starting stream: $e';
      
      // Handle specific Mux errors
      if (e.toString().contains('unavailable on the free plan')) {
        errorMessage = 'System Config Error: The DEVELOPER Mux account is on a free tier which does not support live streaming. This is not related to your App Subscription.';
      } else if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        errorMessage = 'Mux authentication failed. Please check your Mux credentials in mux_config.dart';
      } else if (e.toString().contains('400')) {
        errorMessage = 'Invalid Mux request. Please check your Mux account settings.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _stopStreaming() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Stop RTMP stream
      if (_cameraController != null && _isStreaming) {
        await _cameraController!.stopVideoStreaming();
      }
      
      // Transition YouTube broadcast to complete
      if (_youtubeBroadcastId != null) {
          try {
              // Get assigned channel credentials to transition status
              final channelData = await YouTubeApiService.getAssignedChannel(widget.matchId);
              final accessToken = channelData['access_token'];
              
              await YouTubeApiService.transitionBroadcast(
                  accessToken: accessToken,
                  broadcastId: _youtubeBroadcastId!,
                  status: 'complete',
              );
          } catch (e) {
              print('Error completing YouTube broadcast: $e');
          } finally {
              // RELEASE CHANNEL
              await YouTubeApiService.releaseChannel(widget.matchId);
          }
      }

      // Delete Mux live stream (BYPASS FOR TESTING)
      // if (_muxStreamId != null) {
      //   await MuxService.deleteLiveStream(_muxStreamId!);
      // }

      // Update database
      await _updateStreamStatus('ended');

      _statusCheckTimer?.cancel();
      _scorecardPollTimer?.cancel();
      _overlayUpdateTimer?.cancel();

      setState(() {
        _isStreaming = false;
        _isLoading = false;
        _muxStreamId = null;
        _rtmpUrl = null;
        _hlsPlaybackUrl = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live stream ended'),
            backgroundColor: Colors.orange,
          ),
        );
        context.pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error stopping stream: $e';
        _isLoading = false;
      });
    }
  }

  Future<String?> _getYouTubeStreamKey() async {
    // Call backend API to get YouTube stream key securely
    // This should be a Supabase Edge Function or your backend API
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'get-youtube-stream-key',
        body: {'match_id': widget.matchId},
      );
      
      if (response.status == 200 && response.data != null) {
        return response.data['stream_key'] as String?;
      }
      return null;
    } catch (e) {
      print('Error getting YouTube stream key: $e');
      // Continue without YouTube restreaming if key is not available
      return null;
    }
  }

  Future<void> _saveStreamInfo(MuxLiveStreamResponse muxResponse) async {
    try {
      await SupabaseConfig.client.from('match_live_streams').upsert({
        'match_id': widget.matchId,
        'mux_stream_id': muxResponse.id,
        'rtmp_url': muxResponse.rtmpUrl,
        'hls_playback_url': muxResponse.hlsPlaybackUrl,
        'status': 'active',
        'started_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving stream info: $e');
    }
  }

  Future<void> _updateStreamStatus(String status) async {
    try {
      await SupabaseConfig.client
          .from('match_live_streams')
          .update({'status': status, 'ended_at': DateTime.now().toIso8601String()})
          .eq('match_id', widget.matchId);
    } catch (e) {
      print('Error updating stream status: $e');
    }
  }

  Future<void> _startRTMPStream(String rtmpUrl) async {
    if (_cameraController == null) return;

    try {
      print('🚀 Starting RTMP Stream (800kbps) to: $rtmpUrl');
      await _cameraController!.startVideoStreaming(
        rtmpUrl,
        bitrate: 800 * 1024, // Optimized from 1200kbps
      );
      print('✅ RTMP Stream started successfully');
    } catch (e) {
      print('❌ Error starting RTMP stream: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start video stream: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  void _startStatusCheck() {
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_muxStreamId != null) {
        try {
          final stream = await MuxService.getLiveStream(_muxStreamId!);
          if (stream.status == 'disconnected' && _isStreaming) {
            // Stream disconnected, stop streaming
            _stopStreaming();
          }
        } catch (e) {
          print('Error checking stream status: $e');
        }
      }
    });
  }

  Timer? _scorecardPollTimer;

  // Subscribe to live scorecard updates (using polling)
  void _subscribeToLiveScorecard() {
    // Fetch initial scorecard
    _fetchInitialScorecard();
    
    // Poll for updates every 2 seconds
    _scorecardPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && _isStreaming) {
        _fetchInitialScorecard();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _fetchInitialScorecard() async {
    try {
      final response = await SupabaseConfig.client
          .from('matches')
          .select('scorecard, team1_name, team2_name, toss_winner, toss_decision')
          .eq('id', widget.matchId)
          .single();
      
      if (mounted && response != null) {
        final previousScorecard = _liveScorecard;
        
        setState(() {
          _liveScorecard = response['scorecard'];
          _team1Name = response['team1_name'];
          _team2Name = response['team2_name'];
          _tossWinner = response['toss_winner'];
          _tossDecision = response['toss_decision'];
        });

        // Trigger overlay refresh for RTMP stream - update whenever scorecard changes
        if (_isStreaming) {
          // Check if scorecard actually changed
          final scorecardChanged = previousScorecard != _liveScorecard;
          
          if (scorecardChanged) {
            print('📊 Scorecard updated - refreshing overlay');
          }
          
          // Always update overlay after a short delay to ensure UI is rendered
          // The periodic timer will also update it, but this ensures immediate updates on changes
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _isStreaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateStreamOverlay();
              });
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching initial scorecard: $e');
    }
  }

// REAL DATA SCOREBOARD - Replace _buildLiveScoreboardOverlay
  Widget _buildLiveScoreboardOverlay() {
    return RepaintBoundary(
      key: _scoreboardKey,
      child: _buildScoreboardContent(),
    );
  }

  Widget _buildScoreboardContent() {
    // Use Mock Data if null to ensure visibility
    Map<String, dynamic> card = (_liveScorecard != null && _liveScorecard!.isNotEmpty) 
        ? _liveScorecard! 
        : {
            'striker': 'Demo Batsman', 'striker_runs': 24, 'striker_balls': 12,
            'non_striker': 'Non Striker', 'non_striker_runs': 10, 'non_striker_balls': 8,
            'bowler': 'Demo Bowler', 'bowler_wickets': 1, 'bowler_runs': 18, 'bowler_overs': 2.1,
            'team1_score': {'runs': 50, 'wickets': 1, 'overs': 4.2},
            'current_over_balls': ['1', '4', 'W', '0', '6', '1'],
            'current_innings': 1,
            'team1_name': 'Team A',
            'team2_name': 'Team B',
          };

    // Extract data from scorecard
    final striker = card['striker'] ?? 'Batsman 1';
    final nonStriker = card['non_striker'] ?? 'Batsman 2';
    final bowler = card['bowler'] ?? 'Bowler';
    
    final strikerRuns = card['striker_runs'] ?? 0;
    final strikerBalls = card['striker_balls'] ?? 0;
    final nonStrikerRuns = card['non_striker_runs'] ?? 0;
    final nonStrikerBalls = card['non_striker_balls'] ?? 0;
    
    final bowlerRuns = card['bowler_runs'] ?? 0;
    final bowlerWickets = card['bowler_wickets'] ?? 0;
    final bowlerOvers = card['bowler_overs'] ?? 0;
    
    final currentOverBalls = card['current_over_balls'] ?? [];
    final currentInnings = card['current_innings'] ?? 1;
    
    // Get team names with fallback
    final team1Name = _team1Name ?? 'Team 1';
    final team2Name = _team2Name ?? 'Team 2';
    
    // Determine Batting vs Bowling Team based on innings (Default)
    final battingTeamName = currentInnings == 1 ? team1Name : team2Name;
    final bowlingTeamName = currentInnings == 1 ? team2Name : team1Name;
    
    // Get team scores
    final team1Score = card['team1_score'] ?? {};
    final team2Score = card['team2_score'] ?? {};
    
    final battingScore = currentInnings == 1 ? team1Score : team2Score;
    final runs = battingScore['runs'] ?? 0;
    final wickets = battingScore['wickets'] ?? 0;
    final overs = battingScore['overs'] ?? 0.0;
    
    // Format overs (e.g., 1.2 overs)
    final oversInt = overs.floor();
    final balls = ((overs - oversInt) * 6).round();
    final oversDisplay = '$oversInt.$balls';

    return Positioned(
      bottom: 120, // Positioned ABOVE the Stop Streaming button with more space
      left: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // PITCHPOINT LOGO
            Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Row(
                    children: [
                        const Icon(Icons.sports_cricket, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                            "PitchPoint",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12, 
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: Colors.black, blurRadius: 2)]
                            ),
                        ),
                    ],
                ),
            ),
            
            // SCOREBOARD CARD
            Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias, // Ensure child doesn't bleed
        child: Column(
          children: [
            // Top Bar: Batting Team vs Bowling Team & Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFF57C00)], // Orange Gradient
                ),
              ),
              child: Row(
                children: [
                   // Team Names (Batting vs Bowling)
                   Expanded(
                     flex: 3,
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(
                           battingTeamName.toUpperCase(),
                           style: const TextStyle(
                             color: Colors.white,
                             fontWeight: FontWeight.w900,
                             fontSize: 15,
                           ),
                           maxLines: 1, 
                           overflow: TextOverflow.ellipsis,
                         ),
                         Row(
                           children: [
                               Text(
                                   'vs ',
                                   style: TextStyle(
                                     color: Colors.white.withOpacity(0.8),
                                     fontSize: 11,
                                   ),
                               ),
                               Expanded(
                                   child: Text(
                                     bowlingTeamName,
                                     style: const TextStyle(
                                       color: Colors.white,
                                       fontWeight: FontWeight.w600,
                                       fontSize: 12,
                                     ),
                                     maxLines: 1,
                                     overflow: TextOverflow.ellipsis,
                                   ),
                               ),
                           ],
                         )
                       ],
                     ),
                   ),
                   
                   // Score & Overs
                   Expanded(
                     flex: 2,
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.end,
                       children: [
                         Text(
                           '$runs/$wickets',
                           style: const TextStyle(
                             color: Colors.white,
                             fontWeight: FontWeight.w900,
                             fontSize: 24,
                             height: 1.0,
                           ),
                         ),
                         Container(
                           margin: const EdgeInsets.only(top: 2),
                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                           decoration: BoxDecoration(
                               color: Colors.black.withOpacity(0.2),
                               borderRadius: BorderRadius.circular(4)
                           ),
                           child: Text(
                             '$oversDisplay Overs',
                             style: const TextStyle(
                               color: Colors.white,
                               fontWeight: FontWeight.bold,
                               fontSize: 11,
                             ),
                           ),
                         ),
                       ],
                     ),
                   ),
                ],
              ),
            ),
            
            // Bottom Section: Batsmen, Bowler, This Over
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              color: Colors.white,
              child: IntrinsicHeight(
              child: Row(
                children: [
                  // Batsmen (Left)
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBatsmanRow(striker, strikerRuns, strikerBalls, isStriker: true),
                        const SizedBox(height: 4),
                        _buildBatsmanRow(nonStriker, nonStrikerRuns, nonStrikerBalls, isStriker: false),
                      ],
                    ),
                  ),
                  
                  // Divider
                  VerticalDivider(width: 16, thickness: 1, color: Colors.grey.shade300),
                  
                  // Bowler (Middle)
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          bowler,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$bowlerWickets-$bowlerRuns ($bowlerOvers)',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  VerticalDivider(width: 16, thickness: 1, color: Colors.grey.shade300),

                  // This Over (Right)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('THIS OVER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 2,
                          alignment: WrapAlignment.end,
                          runSpacing: 2,
                          children: [
                            for (var ball in currentOverBalls.take(6))
                              _buildBallIndicator(ball),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
      ),
      ],
      ),
    );
  }

  Widget _buildBatsmanRow(String name, int runs, int balls, {required bool isStriker}) {
    return Row(
      children: [
        if (isStriker) 
            const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.play_arrow, size: 10, color: Colors.orange)),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isStriker ? FontWeight.bold : FontWeight.w600,
              color: isStriker ? Colors.black : Colors.black87,
            ),
            maxLines: 1, 
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('$runs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isStriker ? Colors.black : Colors.black87)),
        Text('($balls)', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBallIndicator(String ball) {
    Color bg = Colors.grey.shade200;
    Color fg = Colors.black;
    String text = ball;
    
    if (['4','6'].contains(ball)) { bg = Colors.black; fg = Colors.white; }
    if (['W','w'].contains(ball)) { bg = Colors.red; fg = Colors.white; }
    if (ball == '0') { text = '•'; fg = Colors.grey; }
    
    return Container(
      width: 14, height: 14,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 8, color: fg, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
             const Text('Go Live'),
             const SizedBox(width: 12),
             if (_userPlan != 'loading')
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                 decoration: BoxDecoration(
                   color: _userPlan == 'pro' ? AppColors.primary : Colors.grey,
                   borderRadius: BorderRadius.circular(4),
                 ),
                 child: Text(
                   _userPlan.toUpperCase(),
                   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                 ),
               ),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Debug: Reset Plan Button
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.orange),
            tooltip: 'Debug: Reset to Basic Plan',
            onPressed: () async {
              final userId = SupabaseConfig.client.auth.currentUser?.id;
              if (userId != null) {
                await ref.read(profileRepositoryProvider).updateSubscriptionPlan(userId, 'basic');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Debug: Reset to Basic Plan')),
                  );
                }
                await _fetchUserPlan();
              }
            },
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (_isStreaming) {
              _showStopStreamDialog();
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _errorMessage!.contains('free plan') 
                          ? Icons.info_outline 
                          : Icons.error_outline,
                      size: 64,
                      color: _errorMessage!.contains('free plan') 
                          ? Colors.orange 
                          : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!.contains('free plan')
                          ? 'Mux Plan Upgrade Required'
                          : 'Error',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage!.contains('free plan')) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          // Open Mux upgrade page
                          // You can use url_launcher here if needed
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Upgrade Mux Plan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                        if (!_errorMessage!.contains('free plan')) {
                          _initializeCamera();
                        }
                      },
                      child: Text(_errorMessage!.contains('free plan') 
                          ? 'Go Back' 
                          : 'Retry'),
                    ),
                  ],
                ),
              ),
            )
          : !_isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _errorMessage != null && _errorMessage!.contains('free plan')
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 64,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Mux Plan Upgrade Required',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                // Open Mux upgrade page
                                // You can use url_launcher to open browser
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Upgrade Mux Plan'),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _errorMessage = null;
                                });
                              },
                              child: const Text(
                                'Dismiss',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                  children: [
                    // Camera Preview
                    SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _cameraController != null
                          ? CameraPreview(_cameraController!)
                          : const Center(
                              child: Text(
                                'Camera not available',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),),
                    
                    // Live Scoreboard Overlay
                    if (_isStreaming && (_liveScorecard != null || true)) // Alway show for now to ensure visibility
                      _buildLiveScoreboardOverlay(),
                    
                    // Top Right Live Indicator - Animated
                    if (_isStreaming)
                      Positioned(
                        top: 40,
                        right: 16,
                        child: _LiveIndicator(),
                      ),
                    
                    // Floating Stop Button - Always visible when streaming
                    if (_isStreaming)
                      Positioned(
                        top: 40,
                        left: 16,
                        child: SafeArea(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _stopStreaming,
                              borderRadius: BorderRadius.circular(30),
                        child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                          ),
                                child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                    const Icon(Icons.stop_circle, size: 20, color: Colors.white),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'STOP',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                            ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    // Overlay Controls
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Streaming Status
                            
                            
                            // Start/Stop Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : (_isStreaming ? _stopStreaming : _startStreaming),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isStreaming ? Colors.red : AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        _isStreaming ? 'STOP STREAMING' : 'GO LIVE',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<bool?> _showUpgradeDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Upgrade to Pro?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pro Plan Features:',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildFeatureItem('Run Live Stream Recording (VOD)'),
            _buildFeatureItem('Scorecard Overlays'),
            _buildFeatureItem('PDF/CSV Export'),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text(
              'Basic Plan: Live Only (No Recording)',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Continue as Basic
            child: const Text('Continue as Basic', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, false), // Upgrade
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _updateStreamOverlay() async {
    if (!_isStreaming || _cameraController == null) return;

    try {
      // Wait a bit for the widget to render
      await Future.delayed(const Duration(milliseconds: 100));
      
      final boundary = _scoreboardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        print('⚠️ Overlay boundary not found - retrying...');
        // Retry after a short delay
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _isStreaming) {
            _updateStreamOverlay();
          }
        });
        return;
      }

      // Capture with higher pixel ratio for better quality on stream
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        print('✅ Pushing overlay to stream: ${bytes.length} bytes');
        await _cameraController!.setOverlay(bytes);
        print('✅ Overlay updated successfully on stream');
      } else {
        print('⚠️ Failed to convert overlay to bytes');
      }
    } catch (e) {
      print('❌ Error updating stream overlay: $e');
      // Don't throw - just log the error so streaming continues
    }
  }

  void _showStopStreamDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Stop Streaming?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to stop the live stream?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopStreaming();
            },
            child: const Text('Stop', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Animated Live Indicator Widget
class _LiveIndicator extends StatefulWidget {
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(_animation.value * 0.5),
                blurRadius: 8 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record, size: 12, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


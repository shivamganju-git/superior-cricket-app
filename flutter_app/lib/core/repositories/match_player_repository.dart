import '../config/supabase_config.dart';

class MatchPlayerRepository {
  final _supabase = SupabaseConfig.client;

  /// Add a player to a match team
  /// This will trigger the notification automatically via database trigger
  Future<void> addPlayerToMatch({
    required String matchId,
    required String playerId,
    required String teamType, // 'team1' or 'team2'
    String? role,
    bool isCaptain = false,
    bool isWicketKeeper = false,
    String? addedBy,
  }) async {
    try {
      await _supabase.from('match_players').insert({
        'match_id': matchId,
        'player_id': playerId,
        'team_type': teamType,
        'role': role,
        'is_captain': isCaptain,
        'is_wicket_keeper': isWicketKeeper,
        'added_by': addedBy,
      });
      print('MatchPlayer: Added player $playerId to match $matchId (team: $teamType)');
    } catch (e) {
      print('Error adding player to match: $e');
      rethrow;
    }
  }

  /// Add multiple players to a match team
  /// Accepts either List<Map> (from squad pages) or List<String> (player names)
  Future<void> addPlayersToMatch({
    required String matchId,
    required dynamic players, // Can be List<Map> or List<String>
    required String teamType,
    String? addedBy,
  }) async {
    try {
      print('MatchPlayer: addPlayersToMatch called - matchId: $matchId, teamType: $teamType, players count: ${players is List ? (players as List).length : "N/A"}');
      
      List<Map<String, dynamic>> playersData = [];
      
      if (players is List<Map<String, dynamic>>) {
        print('MatchPlayer: Processing ${players.length} players from List<Map>');
        // Players from squad pages (should have id, role, etc.)
        for (var player in players) {
          final playerId = player['id'] as String?;
          final playerName = player['name'] as String? ?? 'Unknown';
          
          if (playerId == null || playerId.isEmpty) {
            print('MatchPlayer: ⚠️ Skipping player "$playerName" - missing ID. Player data: $player');
            continue; // Skip players without IDs
          }
          
          // Validate UUID format (prevents crashing on demo-1, demo-2, etc.)
          final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
          if (!uuidRegex.hasMatch(playerId)) {
            print('MatchPlayer: ⚠️ Skipping player "$playerName" - invalid UUID format: $playerId');
            continue;
          }
          
          final playerData = {
            'match_id': matchId,
            'player_id': playerId,
            'team_type': teamType,
            'role': player['role'] as String?,
            'is_captain': player['isCaptain'] as bool? ?? false,
            'is_wicket_keeper': player['isWicketKeeper'] as bool? ?? false,
            'added_by': addedBy,
          };
          
          playersData.add(playerData);
          print('MatchPlayer: ✓ Added player "$playerName" (ID: $playerId) to $teamType');
        }
      } else if (players is List<String>) {
        // Just player names - need to look up by username/name
        // For now, skip these as we need profile IDs
        print('MatchPlayer: ⚠️ Cannot add players by name only. Need profile IDs.');
        return;
      } else {
        print('MatchPlayer: ⚠️ Invalid players type: ${players.runtimeType}');
        return;
      }
      
      if (playersData.isEmpty) {
        print('MatchPlayer: ⚠️ No valid players to add after processing');
        return;
      }

      print('MatchPlayer: Inserting ${playersData.length} players into match_players table...');
      await _supabase.from('match_players').insert(playersData);
      print('MatchPlayer: ✅ Successfully added ${playersData.length} players to match $matchId (team: $teamType)');
    } catch (e, stackTrace) {
      print('MatchPlayer: ❌ Error adding players to match: $e');
      print('MatchPlayer: Stack trace: $stackTrace');
      // Don't rethrow - allow match creation to continue even if player saving fails
    }
  }

  /// Get all players for a match
  Future<List<Map<String, dynamic>>> getMatchPlayers(String matchId) async {
    try {
      print('MatchPlayer: Fetching players for match: $matchId');
      
      // First, get all match_players records
      final matchPlayersResponse = await _supabase
          .from('match_players')
          .select('*')
          .eq('match_id', matchId);

      print('MatchPlayer: Found ${(matchPlayersResponse as List).length} match_players records');
      
      if ((matchPlayersResponse as List).isEmpty) {
        return [];
      }

      final matchPlayers = (matchPlayersResponse as List).cast<Map<String, dynamic>>();
      
      // Get all unique player IDs
      final playerIds = matchPlayers
          .map((mp) => mp['player_id'] as String)
          .whereType<String>()
          .toSet()
          .toList();
      
      print('MatchPlayer: Fetching profiles for ${playerIds.length} players');
      
      // Fetch profiles for all players using OR query
      List<Map<String, dynamic>> profiles = [];
      if (playerIds.isNotEmpty) {
        // Select all columns from profiles (Supabase will only return existing ones)
        // This avoids errors if columns don't exist
        // The UI code handles both name/full_name and avatar_url/profile_image_url as fallbacks
        dynamic query = _supabase
            .from('profiles')
            .select();
        
        if (playerIds.length == 1) {
          query = query.eq('id', playerIds[0]);
        } else {
          // Build OR condition: id = id1 OR id = id2 OR ...
          final orConditions = playerIds.map((id) => 'id.eq.$id').join(',');
          query = query.or(orConditions);
        }
        
        final profilesResponse = await query;
        profiles = (profilesResponse as List).cast<Map<String, dynamic>>();
      }
      final profilesMap = {
        for (var profile in profiles)
          profile['id'] as String: profile
      };
      
      print('MatchPlayer: Found ${profiles.length} profiles');
      
      // Combine match_players with profiles
      final result = matchPlayers.map((mp) {
        final playerId = mp['player_id'] as String;
        final profile = profilesMap[playerId];
        
        return {
          ...mp,
          'profiles': profile,
        };
      }).toList();
      
      // Debug: Print player data structure
      for (var player in result) {
        print('MatchPlayer: Player data - team_type: ${player['team_type']}, player_id: ${player['player_id']}');
        print('MatchPlayer: Has profile: ${player['profiles'] != null}');
      }
      
      return result;
    } catch (e, stackTrace) {
      print('Error fetching match players: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get matches for a player
  Future<List<Map<String, dynamic>>> getPlayerMatches(String playerId) async {
    try {
      final response = await _supabase
          .from('match_players')
          .select('''
            *,
            matches:match_id (
              id,
              team1_name,
              team2_name,
              status,
              scheduled_at,
              created_at
            )
          ''')
          .eq('player_id', playerId)
          .order('added_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching player matches: $e');
      return [];
    }
  }

  /// Remove a player from a match
  Future<void> removePlayerFromMatch({
    required String matchId,
    required String playerId,
    required String teamType,
  }) async {
    try {
      await _supabase
          .from('match_players')
          .delete()
          .eq('match_id', matchId)
          .eq('player_id', playerId)
          .eq('team_type', teamType);
    } catch (e) {
      print('Error removing player from match: $e');
      rethrow;
    }
  }
}


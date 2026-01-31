import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/models/match_model.dart';
import '../../../../core/repositories/match_repository.dart';
import '../../../../core/repositories/match_player_repository.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import 'commentary_page.dart';
import '../../../live/presentation/pages/go_live_screen.dart';
import '../widgets/assign_scorer_dialog.dart';
import '../widgets/mvp_award_card.dart';
import '../widgets/match_analytics_widgets.dart';
import '../../../../core/models/mvp_model.dart';
import '../../../../core/cricket_engine/models/delivery_model.dart';
import '../../../../core/cricket_engine/models/scorecard_model.dart';
import '../../../../core/cricket_engine/engine/scorecard_engine.dart';
import '../../../../core/cricket_engine/adapter/scorecard_adapter.dart';

/// Provider for match data
final matchDetailProvider = StreamProvider.autoDispose.family<MatchModel?, String>((ref, matchId) {
  final repository = ref.watch(matchRepositoryProvider);
  return repository.streamMatchById(matchId);
});

/// Provider for match players
final matchPlayersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
  final repository = ref.watch(matchPlayerRepositoryProvider);
  return await repository.getMatchPlayers(matchId);
});

// MVP data provider - Changed to StreamProvider for real-time updates
final matchMvpProvider = StreamProvider.autoDispose.family<List<PlayerMvpModel>, String>((ref, matchId) {
  final repository = ref.watch(mvpRepositoryProvider);
  return repository.streamMatchMvpData(matchId);
});

class MatchDetailPageComprehensive extends ConsumerStatefulWidget {
  final String matchId;

  const MatchDetailPageComprehensive({
    super.key,
    required this.matchId,
  });

  @override
  ConsumerState<MatchDetailPageComprehensive> createState() => _MatchDetailPageComprehensiveState();
}

class _MatchDetailPageComprehensiveState extends ConsumerState<MatchDetailPageComprehensive>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRefreshing = false;
  String? _expandedTeam; // Track expanded squad team

  Map<String, dynamic> _getBalancedScores(Map<String, dynamic> scorecard) {
    if (scorecard.isEmpty) return {};
    
    // Initialize with stored values as fallback
    final team1Score = scorecard['team1_score'] ?? {};
    final team2Score = scorecard['team2_score'] ?? {};
    
    int t1Runs = (team1Score['runs'] as num?)?.toInt() ?? 0;
    int t1Wickets = (team1Score['wickets'] as num?)?.toInt() ?? 0;
    double t1OversRaw = 0.0; // Will be recalculated from deliveries
    
    int t2Runs = (team2Score['runs'] as num?)?.toInt() ?? 0;
    int t2Wickets = (team2Score['wickets'] as num?)?.toInt() ?? 0;
    double t2OversRaw = 0.0; // Will be recalculated from deliveries

    // SELF-HEALING: If deliveries exist, recalculate from the source of truth
    final currentInnings = (scorecard['current_innings'] as num?)?.toInt() ?? 1;
    
    // Recalculate first innings from first_innings_deliveries (only if second innings has started)
    if (currentInnings == 2) {
      final firstInningsDeliveries = scorecard['first_innings_deliveries'] as List<dynamic>?;
      if (firstInningsDeliveries != null && firstInningsDeliveries.isNotEmpty) {
      int calcRuns = 0;
      int calcWickets = 0;
      int calcLegalBalls = 0;
      
        // CRITICAL: Deduplicate deliveries by deliveryNumber to avoid double-counting
        final seenDeliveryNumbers = <int>{};
        final validDeliveries = <Map<String, dynamic>>[];
        
        for (final json in firstInningsDeliveries) {
        final d = json as Map<String, dynamic>;
          final deliveryNumber = (d['deliveryNumber'] as num?)?.toInt();
          final striker = d['striker'] as String? ?? '';
          
          // Skip invalid deliveries
          if (striker.isEmpty) {
            debugPrint('WARNING: Found delivery with empty striker in first innings - skipping');
            continue;
          }
          
          // Skip duplicates (same deliveryNumber)
          if (deliveryNumber != null) {
            if (seenDeliveryNumbers.contains(deliveryNumber)) {
              debugPrint('WARNING: Found duplicate delivery #$deliveryNumber in first innings - skipping');
              continue;
            }
            seenDeliveryNumbers.add(deliveryNumber);
          }
          
          validDeliveries.add(d);
        }
        
        for (final d in validDeliveries) {
          final striker = d['striker'] as String? ?? '';
        int ballRuns = 0;
        final extraType = d['extraType'] as String?;
        final r = (d['runs'] as num?)?.toInt() ?? 0;
        final er = (d['extraRuns'] as num?)?.toInt() ?? 0;
        
        // Correct team run calculation per delivery
        if (extraType == 'WD' || extraType == 'NB') {
          ballRuns = er; // For Wides/NB, extraRuns contains total team runs
        } else {
          ballRuns = r + er; // For others (B, LB, regular), it's bat runs + extras
        }
        
        calcRuns += ballRuns;
        if (d['wicketType'] != null) calcWickets++;
          // CRITICAL: Only count legal balls with valid striker (matches batting stats calculation)
          if (d['isLegalBall'] == true && striker.isNotEmpty) calcLegalBalls++;
      }
      
        // Calculate overs correctly: legalBalls / 6.0 (e.g., 17 legal balls = 2.833, displays as 2.5)
        t1Runs = calcRuns;
        t1Wickets = calcWickets;
        t1OversRaw = calcLegalBalls / 6.0;
      } else {
        // Fallback to stored values if deliveries not available
        if (scorecard.containsKey('first_innings_runs')) {
          t1Runs = (scorecard['first_innings_runs'] as num?)?.toInt() ?? t1Runs;
          t1Wickets = (scorecard['first_innings_wickets'] as num?)?.toInt() ?? t1Wickets;
          t1OversRaw = (scorecard['first_innings_overs'] as num?)?.toDouble() ?? t1OversRaw;
        }
      }
    }
    
    // Recalculate current innings from deliveries (which only contains current innings deliveries)
    final deliveries = scorecard['deliveries'] as List<dynamic>?;
    if (deliveries != null && deliveries.isNotEmpty) {
      // CRITICAL: Deduplicate deliveries by deliveryNumber to avoid double-counting
      final seenDeliveryNumbers = <int>{};
      final validDeliveries = <Map<String, dynamic>>[];
      
      for (final json in deliveries) {
        final d = json as Map<String, dynamic>;
        final deliveryNumber = (d['deliveryNumber'] as num?)?.toInt();
        final striker = d['striker'] as String? ?? '';
        
        // Skip invalid deliveries
        if (striker.isEmpty) {
          debugPrint('WARNING: Found delivery with empty striker in current innings - skipping');
          continue;
        }
        
        // Skip duplicates (same deliveryNumber)
        if (deliveryNumber != null) {
          if (seenDeliveryNumbers.contains(deliveryNumber)) {
            debugPrint('WARNING: Found duplicate delivery #$deliveryNumber - skipping');
            continue;
          }
          seenDeliveryNumbers.add(deliveryNumber);
        }
        
        validDeliveries.add(d);
      }
      
      int calcRuns = 0;
      int calcWickets = 0;
      int calcLegalBalls = 0;
      
      for (final d in validDeliveries) {
        final striker = d['striker'] as String? ?? '';
        int ballRuns = 0;
        final extraType = d['extraType'] as String?;
        final r = (d['runs'] as num?)?.toInt() ?? 0;
        final er = (d['extraRuns'] as num?)?.toInt() ?? 0;
        
        // Correct team run calculation per delivery
        if (extraType == 'WD' || extraType == 'NB') {
          ballRuns = er; // For Wides/NB, extraRuns contains total team runs
        } else {
          ballRuns = r + er; // For others (B, LB, regular), it's bat runs + extras
        }
        
        calcRuns += ballRuns;
        if (d['wicketType'] != null) calcWickets++;
        // CRITICAL: Only count legal balls with valid striker (matches batting stats calculation)
        if (d['isLegalBall'] == true && striker.isNotEmpty) calcLegalBalls++;
      }
      
      // Calculate overs correctly: legalBalls / 6.0 (e.g., 10 legal balls = 1.667, displays as 1.4)
      if (currentInnings == 1) {
        t1Runs = calcRuns;
        t1Wickets = calcWickets;
        t1OversRaw = calcLegalBalls / 6.0;
      } else {
        t2Runs = calcRuns;
        t2Wickets = calcWickets;
        t2OversRaw = calcLegalBalls / 6.0;
      }
    }

    // SECONDARY SELF-HEALING: Ensure team total is at least the sum of batsman runs
    // This addresses discrepancies where player stats are updated but deliveries/total might be stale
    final playerStats1 = scorecard['player_stats_map'] as Map<String, dynamic>?;
    final firstInningsPlayerStats = scorecard['first_innings_player_stats'] as Map<String, dynamic>?;
    // Note: currentInnings is already declared above (line 70)

    // Check Current Innings (usually team 1 if 1st, team 2 if 2nd)
    final activeStats = playerStats1;
    if (activeStats != null && activeStats.isNotEmpty) {
      int activePlayerSum = 0;
      activeStats.forEach((_, s) {
        activePlayerSum += ((s as Map)['runs'] as num?)?.toInt() ?? 0;
      });
      
      // Also add extras if available
      int extras = 0;
      final extrasMap = scorecard['extras_map'] as Map<String, dynamic>?;
      if (extrasMap != null) {
        extrasMap.forEach((_, e) => extras += (e as num).toInt());
      }

      final teamTotal = activePlayerSum + extras;
      if (currentInnings == 1) {
        if (teamTotal > t1Runs) t1Runs = teamTotal;
      } else {
        if (teamTotal > t2Runs) t2Runs = teamTotal;
      }
    }

    // Check First Innings if we are in second innings
    if (currentInnings == 2 && firstInningsPlayerStats != null && firstInningsPlayerStats.isNotEmpty) {
      int prevPlayerSum = 0;
      firstInningsPlayerStats.forEach((_, s) {
        prevPlayerSum += ((s as Map)['runs'] as num?)?.toInt() ?? 0;
      });
      
      int prevExtras = 0;
      final prevExtrasMap = scorecard['first_innings_extras'] as Map<String, dynamic>?;
      if (prevExtrasMap != null) {
        prevExtrasMap.forEach((_, e) => prevExtras += (e as num).toInt());
      }

      final prevTotal = prevPlayerSum + prevExtras;
      if (prevTotal > t1Runs) t1Runs = prevTotal;
    }

    // Fallback: If no deliveries available or recalculation failed, use stored overs (legacy support)
    if (t1OversRaw == 0.0) {
      final firstInningsDeliveries = scorecard['first_innings_deliveries'] as List<dynamic>?;
      if (firstInningsDeliveries == null || firstInningsDeliveries.isEmpty) {
        t1OversRaw = (team1Score['overs'] as num?)?.toDouble() ?? 0.0;
      }
    }
    if (t2OversRaw == 0.0) {
      final deliveries = scorecard['deliveries'] as List<dynamic>?;
      if (deliveries == null || deliveries.isEmpty) {
        t2OversRaw = (team2Score['overs'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return {
      'team1Runs': t1Runs,
      'team1Wickets': t1Wickets,
      'team1Overs': t1OversRaw,
      'team2Runs': t2Runs,
      'team2Wickets': t2Wickets,
      'team2Overs': t2OversRaw,
    };
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this); // Added Analytics tab
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchAsync = ref.watch(matchDetailProvider(widget.matchId));
    final playersAsync = ref.watch(matchPlayersProvider(widget.matchId));
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.user?.id;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Match Details',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        actions: [
          // Refresh Button with Animation
          AnimatedRotation(
            turns: _isRefreshing ? 1 : 0,
            duration: const Duration(milliseconds: 500),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh',
              onPressed: _isRefreshing
                  ? null
                  : () async {
                      setState(() {
                        _isRefreshing = true;
                      });

                      // Invalidate providers to refresh data
                      ref.invalidate(matchDetailProvider(widget.matchId));
                      ref.invalidate(matchPlayersProvider(widget.matchId));

                      // Wait a bit for the animation and data refresh
                      await Future.delayed(const Duration(milliseconds: 500));

                      if (mounted) {
                        setState(() {
                          _isRefreshing = false;
                        });

                        // Show success message
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text('Match data refreshed'),
                              ],
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
            ),
          ),
          // DLS Calculator (Removed)
          // Share Button
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share',
            onPressed: () async {
              final matchAsync = ref.read(matchDetailProvider(widget.matchId));
              matchAsync.whenData((match) {
                if (match != null) {
                  final team1 = match.team1Name ?? 'Team 1';
                  final team2 = match.team2Name ?? 'Team 2';
                  final status = match.status.toUpperCase();
                  
                  String shareText = '🏏 $team1 vs $team2\n';
                  shareText += '📊 Status: $status\n';
                  
                  // Add score if available
                  final scorecard = match.scorecard;
                  if (scorecard != null && scorecard.isNotEmpty) {
                    final team1Score = scorecard['team1_score'] as Map<String, dynamic>? ?? {};
                    final team2Score = scorecard['team2_score'] as Map<String, dynamic>? ?? {};
                    
                    if (team1Score.isNotEmpty) {
                      final runs = team1Score['runs'] ?? 0;
                      final wickets = team1Score['wickets'] ?? 0;
                      final overs = team1Score['overs'] ?? 0.0;
                      shareText += '$team1: $runs/$wickets (${_formatOvers(overs)} Ov)\n';
                    }
                    
                    if (team2Score.isNotEmpty) {
                      final runs = team2Score['runs'] ?? 0;
                      final wickets = team2Score['wickets'] ?? 0;
                      final overs = team2Score['overs'] ?? 0.0;
                      shareText += '$team2: $runs/$wickets (${_formatOvers(overs)} Ov)\n';
                    }
                  }
                  
                  shareText += '\n⚡ Format: ${match.overs} Overs\n';
                  shareText += '📍 Ground: ${match.groundType}\n';
                  
                  if (match.winnerId != null) {
                    final winner = _getTeamName(match, match.winnerId!);
                    shareText += '🏆 Winner: $winner\n';
                  }
                  
                  shareText += '\nShared from Superior Cricket App';
                  
                  // Share the text
                  Share.share(
                    shareText,
                    subject: '$team1 vs $team2 - Match Details',
                  );
                }
              });
            },
          ),
          // Assign Scorer Button (only for match creator)
          matchAsync.when(
            data: (match) {
              if (match != null && currentUserId != null && match.createdBy == currentUserId) {
                return IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.white),
                  tooltip: 'Assign Scorer',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AssignScorerDialog(
                        matchId: widget.matchId,
                        currentScorerId: match.currentScorerId,
                      ),
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: matchAsync.when(
        data: (match) {
          if (match == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Match not found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                // Match Header Card
                SliverToBoxAdapter(
                  child: _buildMatchHeader(match, currentUserId),
                ),
                
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primary,
                      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 13),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                      tabs: const [
                        Tab(text: 'Info'),
                        Tab(text: 'Summary'),
                        Tab(text: 'Squads'),
                        Tab(text: 'Scorecard'),
                        Tab(text: 'Comms'),
                        Tab(text: 'Analytics'),
                        Tab(text: 'MVP'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(match),
                _buildSummaryTab(match),
                _buildSquadsTab(match, playersAsync),
                _buildScorecardTab(match, playersAsync),
                _buildCommentaryTab(match),
                _buildAnalyticsTab(match),
                _buildMvpTab(match),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading match',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(matchDetailProvider(widget.matchId));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchHeader(MatchModel match, String? currentUserId) {
    return AspectRatio(
      aspectRatio: 2.5 / 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/cricket_stadium_bg.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.3),
              BlendMode.darken,
            ),
          ),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  child: currentUserId != null && match.createdBy == currentUserId
                      ? _buildGlassmorphicGoLiveButton(match)
                      : Container(), // Empty container if not the creator
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassmorphicGoLiveButton(MatchModel match) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              context.push(
                '/go-live',
                extra: {
                  'matchId': match.id,
                  'matchTitle': '${match.team1Name ?? 'Team 1'} vs ${match.team2Name ?? 'Team 2'}',
                },
              );
            },
            child: const Text(
              'Go Live',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return Colors.red;
      case 'completed':
        return Colors.green;
      case 'upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMvpBreakdownRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSec)),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'S': return const Color(0xFFFFD700);
      case 'A': return const Color(0xFF00D9FF);
      case 'B': return const Color(0xFF00FF88);
      case 'C': return const Color(0xFFFFA500);
      default: return AppColors.textMeta;
    }
  }

  Widget _buildSummaryTab(MatchModel match) {
    final scorecard = match.scorecard;
    
    if (scorecard == null || scorecard.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.scoreboard_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Match summary not available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              match.status == 'upcoming'
                  ? 'Match has not started yet'
                  : 'Summary will appear here once the match starts',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Extract data from scorecard
    final balanced = _getBalancedScores(scorecard);
    final team1Runs = (balanced['team1Runs'] as num?)?.toInt() ?? 0;
    final team1Wickets = (balanced['team1Wickets'] as num?)?.toInt() ?? 0;
    final team1Overs = (balanced['team1Overs'] as num?)?.toDouble() ?? 0.0;
    final team2Runs = (balanced['team2Runs'] as num?)?.toInt() ?? 0;
    final team2Wickets = (balanced['team2Wickets'] as num?)?.toInt() ?? 0;
    final team2Overs = (balanced['team2Overs'] as num?)?.toDouble() ?? 0.0;

    final currentInnings = scorecard['current_innings'] as int? ?? 1;
    final crr = (scorecard['crr'] as num?)?.toDouble() ?? 0.0;
    final projected = scorecard['projected'] as int? ?? 0;
    
    // Current batting team data
    final currentRuns = currentInnings == 1 ? team1Runs : team2Runs;
    final currentWickets = currentInnings == 1 ? team1Wickets : team2Wickets;
    final currentOvers = currentInnings == 1 ? team1Overs : team2Overs;
    
    // Previous innings data
    final previousRuns = currentInnings == 2 ? team1Runs : null;
    
    // Team names
    final currentBattingTeam = currentInnings == 1 ? (match.team1Name ?? 'Team 1') : (match.team2Name ?? 'Team 2');
    
    // Current batsmen
    final striker = scorecard['striker'] as String? ?? '';
    final nonStriker = scorecard['non_striker'] as String? ?? '';
    final strikerRuns = scorecard['striker_runs'] as int? ?? 0;
    final strikerBalls = scorecard['striker_balls'] as int? ?? 0;
    final nonStrikerRuns = scorecard['non_striker_runs'] as int? ?? 0;
    final nonStrikerBalls = scorecard['non_striker_balls'] as int? ?? 0;
    
    // Current bowler
    final bowler = scorecard['bowler'] as String? ?? '';
    final bowlerOvers = (scorecard['bowler_overs'] as num?)?.toDouble() ?? 0.0;
    final bowlerRuns = scorecard['bowler_runs'] as int? ?? 0;
    final bowlerWickets = (scorecard['bowler_wickets'] as num?)?.toInt() ?? 0;
    
    // Get player stats from map
    final playerStatsMap = scorecard['player_stats_map'] as Map<String, dynamic>? ?? {};
    final strikerStats = playerStatsMap[striker] as Map<String, dynamic>? ?? {};
    final nonStrikerStats = playerStatsMap[nonStriker] as Map<String, dynamic>? ?? {};
    
    final strikerFours = (strikerStats['fours'] as num?)?.toInt() ?? 0;
    final strikerSixes = (strikerStats['sixes'] as num?)?.toInt() ?? 0;
    final nonStrikerFours = (nonStrikerStats['fours'] as num?)?.toInt() ?? 0;
    final nonStrikerSixes = (nonStrikerStats['sixes'] as num?)?.toInt() ?? 0;
    
    // Calculate strike rates
    final strikerSR = strikerBalls > 0 ? (strikerRuns / strikerBalls) * 100 : 0.0;
    final nonStrikerSR = nonStrikerBalls > 0 ? (nonStrikerRuns / nonStrikerBalls) * 100 : 0.0;
    
    // Calculate partnership
    final partnershipRuns = strikerRuns + nonStrikerRuns;
    final partnershipBalls = strikerBalls + nonStrikerBalls;
    
    // Calculate bowler economy
    final bowlerEconomy = bowlerOvers > 0 ? bowlerRuns / bowlerOvers : 0.0;
    
    // Get bowler stats from map
    final bowlerStatsMap = scorecard['bowler_stats_map'] as Map<String, dynamic>? ?? {};
    final bowlerStats = bowlerStatsMap[bowler] as Map<String, dynamic>? ?? {};
    final bowlerMaidens = (bowlerStats['maidens'] as num?)?.toInt() ?? 0;
    
    // Calculate target info for second innings
    int? runsRequired;
    int? ballsRemaining;
    double? requiredRunRate;
    if (currentInnings == 2 && previousRuns != null) {
      runsRequired = (previousRuns + 1) - currentRuns;
      final totalBalls = match.overs * 6;
      final ballsPlayed = (currentOvers * 6).round();
      ballsRemaining = totalBalls - ballsPlayed;
      requiredRunRate = ballsRemaining > 0 ? (runsRequired / (ballsRemaining / 6.0)) : 0.0;
    }

    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Team Name Header - Simple text
            // Team Name Header - Simple text with Super Over Badge
            Row(
              children: [
                Text(
                  currentBattingTeam,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                  ),
                ),
                if (scorecard['is_super_over'] == true) ...[
                   const SizedBox(width: 12),
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     decoration: BoxDecoration(
                       color: AppColors.urgent,
                       borderRadius: BorderRadius.circular(4),
                     ),
                     child: const Text(
                       'SUPER OVER',
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: 10,
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                   ),
                ]
              ],
            ),
            const SizedBox(height: 20),
            
            // Score and Overs - Reduced size
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$currentRuns',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    height: 1.0,
                  ),
                ),
                Text(
                  '/$currentWickets',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '(${_formatOvers(currentOvers)} Ov)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          
          // CRR and REQ - Enhanced with better visual separation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                _buildMetricItem('CRR', crr.toStringAsFixed(2)),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  color: Colors.grey[300],
                ),
                _buildMetricItem(
                  requiredRunRate != null ? 'REQ' : 'Proj',
                  requiredRunRate != null 
                      ? requiredRunRate.toStringAsFixed(2)
                      : projected.toString(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Target Info - Simple text, left-aligned
          // Target Info or Match Result
          if (match.status == 'completed') ...[
            Builder(
              builder: (context) {
                String resultText = 'Match Completed'; // Default fallback
                
                // Calculate result based on scores
                if (runsRequired != null) {
                  if (runsRequired! <= 0) {
                     // Chasing team won
                     final wicketsLeft = 10 - currentWickets;
                     resultText = '$currentBattingTeam won by $wicketsLeft wickets';
                  } else {
                     // Chasing team lost -> Defending team won
                     // The total target was previousRuns + 1. Scored currentRuns.
                     // The margin is runsRequired - 1 (since runsRequired includes the +1 for win)
                     // Actually simplest is: target = prev + 1. margin = target - 1 - current. 
                     // Or just: margin = previousRuns - currentRuns.
                     // checks:
                     // target 150. prev 149. current 140. runsReq = 10. margin = 9 runs.
                     // runsReq = (149 + 1) - 140 = 10.
                     // margin = 149 - 140 = 9. 
                     // correct margin = runsRequired - 1.
                     
                     final runMargin = runsRequired! - 1;
                     
                     // We need the defending team name.
                     final defendingTeam = currentBattingTeam == match.team1Name ? match.team2Name : match.team1Name;
                     resultText = '${defendingTeam ?? "Defending Team"} won by $runMargin runs';
                  }
                } 
                // Fallback using winnerId if runsRequired calculation failed (e.g. first innings only?)
                else if (match.winnerId != null) {
                   // Fallback logic if needed, but the above should cover completed 2nd innings matches
                   // If match is completed but runsRequired is null, it might be a weird state or 1st innings washout?
                   // For now, keep the default 'Match Completed' or try to use winnerId
                   final winnerName = match.winnerId == match.team1Id ? match.team1Name : match.team2Name;
                   resultText = '$winnerName won';
                }
                
                return Text(
                  resultText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                );
              }
            ),
            const SizedBox(height: 24),
          ] else if (runsRequired != null && ballsRemaining != null) ...[
            Text(
              '$currentBattingTeam require $runsRequired runs in $ballsRemaining balls',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // Divider with better styling
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey[200]!,
                  Colors.grey[300]!,
                  Colors.grey[200]!,
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Batsmen Section - Enhanced
          if (striker.isNotEmpty || nonStriker.isNotEmpty) ...[
            _buildBatsmenTableCompact(
              striker: striker,
              strikerRuns: strikerRuns,
              strikerBalls: strikerBalls,
              strikerFours: strikerFours,
              strikerSixes: strikerSixes,
              strikerSR: strikerSR,
              nonStriker: nonStriker,
              nonStrikerRuns: nonStrikerRuns,
              nonStrikerBalls: nonStrikerBalls,
              nonStrikerFours: nonStrikerFours,
              nonStrikerSixes: nonStrikerSixes,
              nonStrikerSR: nonStrikerSR,
            ),
            const SizedBox(height: 16),
            
            // Partnership - Enhanced with better styling
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.handshake_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Partnership',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '$partnershipRuns($partnershipBalls)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      'More',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // Bowlers Section - Enhanced
          if (bowler.isNotEmpty) ...[
            _buildBowlersTableCompact(
              bowler: bowler,
              overs: bowlerOvers,
              maidens: bowlerMaidens,
              runs: bowlerRuns,
              wickets: bowlerWickets,
              economy: bowlerEconomy,
            ),
          ],
          
          // MVP SECTION - NEW!
          const SizedBox(height: 32),
          Consumer(
            builder: (context, ref, child) {
              final mvpAsync = ref.watch(matchMvpProvider(widget.matchId));
              
              return mvpAsync.when(
                data: (mvpData) {
                  if (mvpData.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  final potm = mvpData.firstWhere(
                    (p) => p.isPlayerOfTheMatch == true,
                    orElse: () => mvpData.first,
                  );
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // MVP Header
                      Row(
                        children: [
                          const Icon(Icons.emoji_events, color: AppColors.primary, size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Top Performers',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textMain,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Player of the Match Card
                      MvpAwardCard(
                        mvpData: potm,
                        isPlayerOfTheMatch: true,
                        onTap: () {},
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Best Batsman & Best Bowler Cards
                      Builder(
                        builder: (context) {
                          // Filter candidates
                          final batsmen = mvpData.where((p) => p.runsScored > 0 || p.battingMvp > 0).toList();
                          final bowlers = mvpData.where((p) => p.ballsBowled > 0 || p.wicketsTaken > 0 || p.bowlingMvp > 0).toList();
                          
                          PlayerMvpModel? bestBatsman;
                          if (batsmen.isNotEmpty) {
                            batsmen.sort((a, b) {
                              final mvpComp = b.battingMvp.compareTo(a.battingMvp);
                              if (mvpComp != 0) return mvpComp;
                              final runsComp = b.runsScored.compareTo(a.runsScored);
                              if (runsComp != 0) return runsComp;
                              return (b.strikeRate ?? 0).compareTo(a.strikeRate ?? 0);
                            });
                            bestBatsman = batsmen.first;
                          }
                          
                          PlayerMvpModel? bestBowler;
                          if (bowlers.isNotEmpty) {
                            bowlers.sort((a, b) {
                              final mvpComp = b.bowlingMvp.compareTo(a.bowlingMvp);
                              if (mvpComp != 0) return mvpComp;
                              final wicketsComp = b.wicketsTaken.compareTo(a.wicketsTaken);
                              if (wicketsComp != 0) return wicketsComp;
                              final ecoA = a.bowlingEconomy ?? 999.0;
                              final ecoB = b.bowlingEconomy ?? 999.0;
                              return ecoA.compareTo(ecoB);
                            });
                            bestBowler = bowlers.first;
                          }

                          if (bestBatsman == null && bestBowler == null) {
                            return const SizedBox.shrink();
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Slot 1: BEST BATSMAN
                              if (bestBatsman != null)
                                Expanded(
                                  child: MvpAwardCard(
                                    mvpData: bestBatsman,
                                    isPlayerOfTheMatch: false,
                                    isCompact: true,
                                    customBadgeText: 'BEST BATSMAN',
                                    statDisplayMode: MvpStatDisplayMode.battingOnly,
                                    onTap: () {},
                                  ),
                                ),
                              
                              if (bestBatsman != null && bestBowler != null)
                                const SizedBox(width: 8),
                                    
                              // Slot 2: BEST BOWLER
                              if (bestBowler != null)
                                Expanded(
                                  child: MvpAwardCard(
                                    mvpData: bestBowler,
                                    isPlayerOfTheMatch: false,
                                    isCompact: true,
                                    customBadgeText: 'BEST BOWLER',
                                    statDisplayMode: MvpStatDisplayMode.bowlingOnly,
                                    onTap: () {},
                                  ),
                                ),
                            ],
                          );
                        }
                      ),
                      
                      const SizedBox(height: 16),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTab(MatchModel match) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'Match Information',
            [
              _buildInfoRow('Status', match.status.toUpperCase()),
              _buildInfoRow('Format', '${match.overs} Overs'),
              _buildInfoRow('Ground Type', match.groundType),
              _buildInfoRow('Ball Type', match.ballType),
              if (match.scheduledAt != null)
                _buildInfoRow('Scheduled', _formatDateTime(match.scheduledAt!)),
              if (match.startedAt != null)
                _buildInfoRow('Started', _formatDateTime(match.startedAt!)),
              if (match.completedAt != null)
                _buildInfoRow('Completed', _formatDateTime(match.completedAt!)),
            ],
          ),
          const SizedBox(height: 16),
          if (match.tossWinnerId != null || match.tossDecision != null)
            _buildInfoCard(
              'Toss',
              [
                if (match.tossWinnerId != null)
                  _buildInfoRow('Winner', _getTeamName(match, match.tossWinnerId!)),
                if (match.tossDecision != null)
                  _buildInfoRow('Decision', match.tossDecision!.toUpperCase()),
              ],
            ),
          const SizedBox(height: 16),
          if (match.winnerId != null)
            _buildInfoCard(
              'Result',
              [
                _buildInfoRow('Winner', _getTeamName(match, match.winnerId!)),
              ],
            ),
          const SizedBox(height: 16),
          if (match.youtubeVideoId != null)
            _buildInfoCard(
              'Live Stream',
              [
                ListTile(
                  leading: const Icon(Icons.live_tv, color: Colors.red),
                  title: const Text('Watch Live'),
                  subtitle: const Text('YouTube Live Stream'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.push('/live?videoId=${match.youtubeVideoId}');
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSquadsTab(MatchModel match, AsyncValue<List<Map<String, dynamic>>> playersAsync) {
    return playersAsync.when(
      data: (players) {
        final team1Players = players.where((p) => p['team_type'] == 'team1').toList();
        final team2Players = players.where((p) => p['team_type'] == 'team2').toList();

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Team 1 Squad
            _buildSquadSection(
              match.team1Name ?? 'Team 1',
              team1Players,
              AppColors.primary,
              _expandedTeam == (match.team1Name ?? 'Team 1'),
              (isExpanded) {
                setState(() {
                  _expandedTeam = isExpanded ? (match.team1Name ?? 'Team 1') : null;
                });
              },
            ),
            const SizedBox(height: 12),
            // Team 2 Squad
            _buildSquadSection(
              match.team2Name ?? 'Team 2',
              team2Players,
              Colors.blue,
              _expandedTeam == (match.team2Name ?? 'Team 2'),
              (isExpanded) {
                 setState(() {
                  _expandedTeam = isExpanded ? (match.team2Name ?? 'Team 2') : null;
                });
              },
            ),
          ],
        ),
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => Center(
      child: Text('Error loading players: $error'),
    ),
  );
}

  Widget _buildSquadSection(
    String teamName, 
    List<Map<String, dynamic>> players, 
    Color teamColor,
    bool isExpanded,
    Function(bool) onExpansionChanged,
  ) {
    return Card(
      elevation: 0,
      color: isExpanded ? Colors.white : const Color(0xFFF9F9F9), // Off-white when collapsed
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded ? teamColor.withOpacity(0.5) : Colors.grey[200]!, // Highlight border when expanded
          width: isExpanded ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key(teamName),
          initiallyExpanded: isExpanded,
          onExpansionChanged: onExpansionChanged,
          backgroundColor: Colors.white,
          collapsedBackgroundColor: const Color(0xFFF9F9F9),
          shape: const Border(), // Remove default border
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.all(16),
          title: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: isExpanded ? teamColor : Colors.grey[400], // Grey accent when not selected
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                teamName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isExpanded ? teamColor : Colors.grey[700], // Grey text when not selected
                ),
              ),
              const Spacer(),
              Text(
                '${players.length} Players',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          children: [
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    'No players added yet',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ...players.map((player) => _buildPlayerCard(player)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> playerData) {
    final profile = playerData['profiles'] as Map<String, dynamic>?;
    final playerName = profile?['full_name'] as String? ?? 
                      profile?['username'] as String? ?? 
                      'Unknown Player';
    final avatarUrl = profile?['avatar_url'] as String?;
    final role = playerData['role'] as String? ?? 'Player';
    final isCaptain = playerData['is_captain'] as bool? ?? false;
    final isWicketKeeper = playerData['is_wicket_keeper'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarInitials(playerName),
                    ),
                  )
                : _buildAvatarInitials(playerName),
          ),
          const SizedBox(width: 12),
          // Player Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        playerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (isCaptain)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'C',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (isWicketKeeper)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'WK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarInitials(String name) {
    final initials = name
        .split(' ')
        .take(2)
        .map((n) => n.isNotEmpty ? n[0].toUpperCase() : '')
        .join();
    
    return Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildScorecardTab(MatchModel match, AsyncValue<List<Map<String, dynamic>>> playersAsync) {
    final scorecard = match.scorecard;
    
    if (scorecard == null || scorecard.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.scoreboard_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Scorecard not available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              match.status == 'upcoming'
                  ? 'Match has not started yet'
                  : 'Scorecard will appear here once the match starts',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return playersAsync.when(
      data: (players) {
        // Extract innings data from balanced scorecard
    final balanced = _getBalancedScores(scorecard);
    final team1Runs = (balanced['team1Runs'] as num?)?.toInt() ?? 0;
    final team1Wickets = (balanced['team1Wickets'] as num?)?.toInt() ?? 0;
    final team1Overs = (balanced['team1Overs'] as num?)?.toDouble() ?? 0.0;
    final team2Runs = (balanced['team2Runs'] as num?)?.toInt() ?? 0;
    final team2Wickets = (balanced['team2Wickets'] as num?)?.toInt() ?? 0;
    final team2Overs = (balanced['team2Overs'] as num?)?.toDouble() ?? 0.0;

    final currentInnings = scorecard['current_innings'] as int? ?? 1;
    
    // Determine team names
    final team1Name = match.team1Name ?? 'Team 1';
    final team2Name = match.team2Name ?? 'Team 2';
    
    // Determine which team batted first (based on current innings)
    final firstInningsTeam = currentInnings == 2 ? team1Name : team2Name;
    final secondInningsTeam = currentInnings == 2 ? team2Name : team1Name;
    
    // Mapping for Innings Widget
    final firstInningsRuns = currentInnings == 2 ? team1Runs : 0;
    final firstInningsWickets = currentInnings == 2 ? team1Wickets : 0;
    final firstInningsOvers = currentInnings == 2 ? team1Overs : 0.0;

    final currentRuns = currentInnings == 1 ? team1Runs : team2Runs;
    final currentWickets = currentInnings == 1 ? team1Wickets : team2Wickets;
    final currentOvers = currentInnings == 1 ? team1Overs : team2Overs;

    // Extras
    final extras1 = scorecard['first_innings_extras'] as Map<String, dynamic>? ?? {};
    final extras2 = scorecard['extras_map'] as Map<String, dynamic>? ?? {};

    int extras1Total = 0;
    extras1.forEach((_, v) => extras1Total += (v as num).toInt());
    int extras2Total = 0;
    extras2.forEach((_, v) => extras2Total += (v as num).toInt());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show first innings if second innings has started
          if (currentInnings == 2)
            _InningsScorecardWidget(
              teamName: firstInningsTeam,
              runs: firstInningsRuns,
              wickets: firstInningsWickets,
              overs: firstInningsOvers,
              isCurrentInnings: false,
              battingStats: _buildBattingStatsFromScorecard(scorecard, firstInningsTeam),
              bowlingStats: _buildBowlingStatsFromScorecard(scorecard, firstInningsTeam),
              extras: extras1Total,
              extrasMap: extras1,
              didNotBat: _getDidNotBatPlayers(
                players,
                currentInnings == 2 ? 'team1' : 'team2', // Team that batted first
                _buildBattingStatsFromScorecard(scorecard, firstInningsTeam),
              ),
            ),
          // Show current innings
          _InningsScorecardWidget(
            teamName: secondInningsTeam,
            runs: currentRuns,
            wickets: currentWickets,
            overs: currentOvers,
            isCurrentInnings: true,
            isMatchCompleted: match.status == 'completed',
            battingStats: _buildBattingStatsFromScorecard(scorecard, secondInningsTeam, isCurrent: true),
            bowlingStats: _buildBowlingStatsFromScorecard(scorecard, secondInningsTeam, isCurrent: true),
            extras: extras2Total,
            extrasMap: extras2,
            didNotBat: _getDidNotBatPlayers(
              players,
              currentInnings == 1 ? 'team1' : 'team2', // Current batting team
              _buildBattingStatsFromScorecard(scorecard, secondInningsTeam, isCurrent: true),
            ),
          ),
        ],
      ),
    );
  },
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (error, _) => Center(child: Text('Error loading players: $error')),
);
}

List<String> _getDidNotBatPlayers(
  List<Map<String, dynamic>> allPlayers,
  String teamType,
  List<_PlayerBattingStat> battingStats,
) {
  final teamPlayers = allPlayers.where((p) => p['team_type'] == teamType).toList();
  final batterNames = battingStats.map((s) => s.playerName).toSet();
  
  return teamPlayers
      .where((p) => !batterNames.contains(p['name']))
      .map((p) => (p['name'] as String? ?? ''))
      .where((name) => name.isNotEmpty)
      .toList();
}

  Widget _buildCommentaryTab(MatchModel match) {
    return Stack(
      children: [
        // Commentary content
        CommentaryPage(matchId: match.id),
        // View Full Commentary button at bottom-right
        Positioned(
          bottom: 20,
          right: 20,
          child: TextButton(
            onPressed: () {
              context.push('/commentary/${match.id}');
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Full Commentary',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsTab(MatchModel match) {
    final scorecard = match.scorecard ?? {};
    final deliveriesJson = scorecard['deliveries'] as List<dynamic>? ?? [];
    final firstInningsDeliveriesJson = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
    
    // Convert to DeliveryModel
    final team1Deliveries = ScorecardAdapter.deliveriesFromJson(firstInningsDeliveriesJson);
    final team2Deliveries = ScorecardAdapter.deliveriesFromJson(deliveriesJson);
    
    // Get team names
    final team1Name = match.team1Name ?? 'Team 1';
    final team2Name = match.team2Name ?? 'Team 2';
    final maxOvers = match.overs?.toInt() ?? 20;
    
    if (team1Deliveries.isEmpty && team2Deliveries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No analytics data available for this match',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Manhattan Chart
          MatchAnalyticsWidgets.buildManhattanChart(
            team1Deliveries: team1Deliveries,
            team2Deliveries: team2Deliveries,
            team1Name: team1Name,
            team2Name: team2Name,
            maxOvers: maxOvers,
          ),
          
          const SizedBox(height: 24),
          
          // Wagon Wheel - Team 1
          if (team1Deliveries.isNotEmpty)
            MatchAnalyticsWidgets.buildWagonWheel(
              deliveries: team1Deliveries,
              teamName: team1Name,
            ),
          
          if (team1Deliveries.isNotEmpty) const SizedBox(height: 24),
          
          // Wagon Wheel - Team 2
          if (team2Deliveries.isNotEmpty)
            MatchAnalyticsWidgets.buildWagonWheel(
              deliveries: team2Deliveries,
              teamName: team2Name,
            ),
          
          if (team2Deliveries.isNotEmpty) const SizedBox(height: 24),
          
          // Worm Chart
          MatchAnalyticsWidgets.buildWormChart(
            team1Deliveries: team1Deliveries,
            team2Deliveries: team2Deliveries,
            team1Name: team1Name,
            team2Name: team2Name,
            maxOvers: maxOvers,
          ),
          
          const SizedBox(height: 24),
          
          // Run Rate Chart
          MatchAnalyticsWidgets.buildRunRateChart(
            team1Deliveries: team1Deliveries,
            team2Deliveries: team2Deliveries,
            team1Name: team1Name,
            team2Name: team2Name,
            maxOvers: maxOvers,
          ),
          
          const SizedBox(height: 24),
          
          // Partnership Chart - Team 1
          if (team1Deliveries.isNotEmpty)
            MatchAnalyticsWidgets.buildPartnershipChart(
              deliveries: team1Deliveries,
              teamName: team1Name,
            ),
          
          if (team1Deliveries.isNotEmpty) const SizedBox(height: 24),
          
          // Partnership Chart - Team 2
          if (team2Deliveries.isNotEmpty)
            MatchAnalyticsWidgets.buildPartnershipChart(
              deliveries: team2Deliveries,
              teamName: team2Name,
            ),
          
          if (team2Deliveries.isNotEmpty) const SizedBox(height: 24),
          
          // Types of Runs Chart
          MatchAnalyticsWidgets.buildTypesOfRunsChart(
            team1Deliveries: team1Deliveries,
            team2Deliveries: team2Deliveries,
            team1Name: team1Name,
            team2Name: team2Name,
          ),
          
          const SizedBox(height: 24),
          
          // Wickets Chart
          MatchAnalyticsWidgets.buildWicketsChart(
            team1Deliveries: team1Deliveries,
            team2Deliveries: team2Deliveries,
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMvpTab(MatchModel match) {
    final mvpAsync = ref.watch(matchMvpProvider(match.id));

    return mvpAsync.when(
      data: (players) {
        if (players.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'MVP data not available',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        // Find Player of the Match
        final potm = players.firstWhere(
          (p) => p.isPlayerOfTheMatch == true,
          orElse: () => players.first,
        );

        // Find Best Batsman and Best Bowler
        final batsmen = players.where((p) => p.runsScored > 0 || p.battingMvp > 0).toList();
        final bowlers = players.where((p) => p.ballsBowled > 0 || p.wicketsTaken > 0 || p.bowlingMvp > 0).toList();
        
        batsmen.sort((a, b) {
          final mvpComp = b.battingMvp.compareTo(a.battingMvp);
          if (mvpComp != 0) return mvpComp;
          final runsComp = b.runsScored.compareTo(a.runsScored);
          if (runsComp != 0) return runsComp;
          return (b.strikeRate ?? 0).compareTo(a.strikeRate ?? 0);
        });
        
        bowlers.sort((a, b) {
          final mvpComp = b.bowlingMvp.compareTo(a.bowlingMvp);
          if (mvpComp != 0) return mvpComp;
          final wicketsComp = b.wicketsTaken.compareTo(a.wicketsTaken);
          if (wicketsComp != 0) return wicketsComp;
          final ecoA = a.bowlingEconomy ?? 999.0;
          final ecoB = b.bowlingEconomy ?? 999.0;
          return ecoA.compareTo(ecoB);
        });

        final bestBatsman = batsmen.isNotEmpty ? batsmen.first : null;
        final bestBowler = bowlers.isNotEmpty ? bowlers.first : null;

        return Column(
          children: [
            // Calculation Link
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 12, bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'How is Most Valuable Players Calculated?',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.teal[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            // Player List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                itemCount: players.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                itemBuilder: (context, index) {
                  return _buildExpandableMvpRow(players[index], index + 1);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildExpandableMvpRow(PlayerMvpModel player, int rank) {
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 80,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rank
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[100],
                border: rank <= 3 ? Border.all(color: Colors.red, width: 1.5) : null,
              ),
              child: ClipOval(
                child: player.playerAvatar != null
                    ? Image.network(player.playerAvatar!, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          player.playerName[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: rank <= 3 ? Colors.red : Colors.grey, 
                            fontSize: 18,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            player.playerName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            player.teamName.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: Colors.grey[500],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      trailing: Text(
        player.totalMvp.toStringAsFixed(3),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          color: Colors.grey[50],
          child: Column(
            children: [
              const Divider(),
              const SizedBox(height: 8),
              // Breakdown String
              Text(
                'Batting: ${player.battingMvp.toStringAsFixed(3)} + Bowling: ${player.bowlingMvp.toStringAsFixed(3)} + Fielding: ${player.fieldingMvp.toStringAsFixed(3)} = ${player.totalMvp.toStringAsFixed(3)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.teal[700],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Detailed Stat Boxes
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildMiniStatBox('Batting', [
                    _miniStat('R', '${player.runsScored}'),
                    _miniStat('B', '${player.ballsFaced}'),
                    _miniStat('SR', player.strikeRate?.toStringAsFixed(1) ?? '-'),
                  ])),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMiniStatBox('Bowling', [
                    _miniStat('W', '${player.wicketsTaken}'),
                    _miniStat('R', '${player.runsConceded}'),
                    _miniStat('EC', player.bowlingEconomy?.toStringAsFixed(1) ?? '-'),
                  ])),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMiniStatBox('Fielding', [
                    _miniStat('C', '${player.catches}'),
                    _miniStat('RO', '${player.runOuts}'),
                    _miniStat('ST', '${player.stumpings}'),
                  ])),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatBox(String title, List<Widget> stats) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 8),
          ...stats,
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatsmenTable({
    required String striker,
    required int strikerRuns,
    required int strikerBalls,
    required int strikerFours,
    required int strikerSixes,
    required double strikerSR,
    required String nonStriker,
    required int nonStrikerRuns,
    required int nonStrikerBalls,
    required int nonStrikerFours,
    required int nonStrikerSixes,
    required double nonStrikerSR,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Batsman',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildTableHeader('R'),
                _buildTableHeader('B'),
                _buildTableHeader('4s'),
                _buildTableHeader('6s'),
                _buildTableHeader('SR'),
              ],
            ),
          ),
          // Striker Row
          if (striker.isNotEmpty)
            _buildBatsmanRow(
              name: striker,
              runs: strikerRuns,
              balls: strikerBalls,
              fours: strikerFours,
              sixes: strikerSixes,
              sr: strikerSR,
              isStriker: true,
            ),
          // Non-Striker Row
          if (nonStriker.isNotEmpty)
            _buildBatsmanRow(
              name: nonStriker,
              runs: nonStrikerRuns,
              balls: nonStrikerBalls,
              fours: nonStrikerFours,
              sixes: nonStrikerSixes,
              sr: nonStrikerSR,
              isStriker: false,
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildBatsmanRow({
    required String name,
    required int runs,
    required int balls,
    required int fours,
    required int sixes,
    required double sr,
    required bool isStriker,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: isStriker ? AppColors.primary.withOpacity(0.05) : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isStriker ? FontWeight.bold : FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isStriker)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '*',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildTableCell(runs.toString()),
          _buildTableCell(balls.toString()),
          _buildTableCell(fours.toString()),
          _buildTableCell(sixes.toString()),
          _buildTableCell(sr.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildBowlerTable({
    required String bowler,
    required double overs,
    required int maidens,
    required int runs,
    required int wickets,
    required double economy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Bowler',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildTableHeader('O'),
                _buildTableHeader('M'),
                _buildTableHeader('R'),
                _buildTableHeader('W'),
                _buildTableHeader('Eco'),
              ],
            ),
          ),
          // Bowler Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    bowler,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildTableCell(_formatOvers(overs)),
                _buildTableCell(maidens.toString()),
                _buildTableCell(runs.toString()),
                _buildTableCell(wickets.toString()),
                _buildTableCell(economy.toStringAsFixed(2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatsmenTableCompact({
    required String striker,
    required int strikerRuns,
    required int strikerBalls,
    required int strikerFours,
    required int strikerSixes,
    required double strikerSR,
    required String nonStriker,
    required int nonStrikerRuns,
    required int nonStrikerBalls,
    required int nonStrikerFours,
    required int nonStrikerSixes,
    required double nonStrikerSR,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header Row
          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text(
                  'Batters',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _buildCompactHeaderCell('R'),
              _buildCompactHeaderCell('B'),
              _buildCompactHeaderCell('4s'),
              _buildCompactHeaderCell('6s'),
              _buildCompactHeaderCell('SR'),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 12),
          // Striker Row
          if (striker.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            striker,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '*',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildCompactDataCell(strikerRuns.toString(), isBold: true),
                  _buildCompactDataCell(strikerBalls.toString()),
                  _buildCompactDataCell(strikerFours.toString()),
                  _buildCompactDataCell(strikerSixes.toString()),
                  _buildCompactDataCell(strikerSR.toStringAsFixed(1)),
                ],
              ),
            ),
          // Non-Striker Row
          if (nonStriker.isNotEmpty)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    nonStriker,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMain,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildCompactDataCell(nonStrikerRuns.toString()),
                _buildCompactDataCell(nonStrikerBalls.toString()),
                _buildCompactDataCell(nonStrikerFours.toString()),
                _buildCompactDataCell(nonStrikerSixes.toString()),
                _buildCompactDataCell(nonStrikerSR.toStringAsFixed(1)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBowlersTableCompact({
    required String bowler,
    required double overs,
    required int maidens,
    required int runs,
    required int wickets,
    required double economy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header Row
          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text(
                  'Bowlers',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _buildCompactHeaderCell('O'),
              _buildCompactHeaderCell('M'),
              _buildCompactHeaderCell('R'),
              _buildCompactHeaderCell('W'),
              _buildCompactHeaderCell('Eco'),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 12),
          // Bowler Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  bowler,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildCompactDataCell(_formatOvers(overs)),
              _buildCompactDataCell(maidens.toString()),
              _buildCompactDataCell(runs.toString(), isBold: true),
              _buildCompactDataCell(wickets.toString(), isBold: true),
              _buildCompactDataCell(economy.toStringAsFixed(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeaderCell(String text) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildCompactDataCell(String text, {bool isBold = false}) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
          color: AppColors.textMain,
        ),
      ),
    );
  }

  String _formatOvers(double overs) {
    final wholeOvers = overs.floor();
    final balls = ((overs - wholeOvers) * 6).round();
    if (balls == 6) {
      return '${wholeOvers + 1}.0';
    }
    return '$wholeOvers.$balls';
  }

  String _getTeamName(MatchModel match, String teamId) {
    if (match.team1Id == teamId) {
      return match.team1Name ?? 'Team 1';
    } else if (match.team2Id == teamId) {
      return match.team2Name ?? 'Team 2';
    }
    return 'Unknown Team';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Build batting stats from scorecard data
  // PRODUCTION: Uses new ScorecardEngine for accurate calculations
  List<_PlayerBattingStat> _buildBattingStatsFromScorecard(
    Map<String, dynamic> scorecard,
    String teamName, {
    bool isCurrent = false,
  }) {
    final stats = <_PlayerBattingStat>[];
    
    // Get deliveries for the appropriate innings (source of truth)
    List<dynamic> deliveriesJson;
    if (isCurrent) {
      deliveriesJson = scorecard['deliveries'] as List<dynamic>? ?? [];
    } else {
      deliveriesJson = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
    }
    
    // PRODUCTION: Use new ScorecardEngine if deliveries are available
    if (deliveriesJson.isNotEmpty) {
      try {
        // Convert to DeliveryModel and use engine
        final deliveries = ScorecardAdapter.deliveriesFromJson(deliveriesJson);
        if (deliveries.isNotEmpty) {
          final currentInnings = (scorecard['current_innings'] as num?)?.toInt() ?? 1;
          final isSuperOver = scorecard['is_super_over'] as bool? ?? false;
          final superOverNumber = (scorecard['super_over_number'] as num?)?.toInt();
          
          final scorecardModel = ScorecardEngine.calculateScorecard(
            deliveries: deliveries,
            teamName: teamName,
            isSuperOver: isSuperOver,
            superOverNumber: superOverNumber,
          );
          
          // Convert engine output to UI format
          for (final battingStat in scorecardModel.battingStats) {
            stats.add(_PlayerBattingStat(
              playerName: battingStat.playerName,
              runs: battingStat.runs,
              balls: battingStat.balls,
              fours: battingStat.fours,
              sixes: battingStat.sixes,
              strikeRate: battingStat.strikeRate,
              minutes: battingStat.minutes ?? 0,
              dismissal: battingStat.dismissalType,
              isNotOut: battingStat.isNotOut,
            ));
          }
          
          // Return early if engine calculation succeeded
          return stats;
        }
      } catch (e) {
        debugPrint('WARNING: ScorecardEngine calculation failed, falling back to manual calculation: $e');
        // Fall through to manual calculation
      }
    }
    
    // FALLBACK: Manual calculation from deliveries (legacy support)
    final dismissalTypes = scorecard['dismissal_types'] as Map<String, dynamic>? ?? {};
    List<String> dismissedPlayers;
    
    if (isCurrent) {
      dismissedPlayers = (scorecard['dismissed_players'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    } else {
      dismissedPlayers = [];
      final firstInningsDeliveries = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
      for (final json in firstInningsDeliveries) {
        final d = json as Map<String, dynamic>;
        final wicketType = d['wicketType'] as String?;
        final striker = d['striker'] as String? ?? '';
        if (wicketType != null && striker.isNotEmpty && !dismissedPlayers.contains(striker)) {
          dismissedPlayers.add(striker);
        }
      }
      final storedDismissed = (scorecard['dismissed_players'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      for (final player in storedDismissed) {
        if (!dismissedPlayers.contains(player)) {
          dismissedPlayers.add(player);
        }
      }
    }
    
    List<dynamic> deliveries;
    if (isCurrent) {
      deliveries = scorecard['deliveries'] as List<dynamic>? ?? [];
    } else {
      deliveries = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
    }
    
    if (deliveries.isNotEmpty) {
      // CRITICAL: Deduplicate deliveries by deliveryNumber to avoid double-counting
      final seenDeliveryNumbers = <int>{};
      final validDeliveries = <Map<String, dynamic>>[];
      
      for (final json in deliveries) {
        final d = json as Map<String, dynamic>;
        final deliveryNumber = (d['deliveryNumber'] as num?)?.toInt();
        final striker = d['striker'] as String? ?? '';
        
        // Skip invalid deliveries
        if (striker.isEmpty) {
          final isLegalBall = d['isLegalBall'] as bool? ?? true;
          if (isLegalBall) {
            debugPrint('WARNING: Found legal ball delivery with empty striker in ${isCurrent ? "current" : "first"} innings - skipping');
          }
          continue;
        }
        
        // Skip duplicates (same deliveryNumber)
        if (deliveryNumber != null) {
          if (seenDeliveryNumbers.contains(deliveryNumber)) {
            debugPrint('WARNING: Found duplicate delivery #$deliveryNumber in ${isCurrent ? "current" : "first"} innings - skipping');
            continue;
          }
          seenDeliveryNumbers.add(deliveryNumber);
        }
        
        validDeliveries.add(d);
      }
      
      // Recalculate player stats from valid deliveries only
      final playerStatsMap = <String, Map<String, int>>{}; // player -> {runs, balls, fours, sixes}
      
      for (final d in validDeliveries) {
        final striker = d['striker'] as String? ?? '';
        
        // Initialize player stats if needed
        if (!playerStatsMap.containsKey(striker)) {
          playerStatsMap[striker] = {
            'runs': 0,
            'balls': 0,
            'fours': 0,
            'sixes': 0,
          };
        }
        
        final playerStats = playerStatsMap[striker]!;
        final isLegalBall = d['isLegalBall'] as bool? ?? true;
        final extraType = d['extraType'] as String?;
        final runs = (d['runs'] as num?)?.toInt() ?? 0;
        
        // Count runs (off bat only)
        if (extraType == null) {
          playerStats['runs'] = playerStats['runs']! + runs;
        } else if (extraType == 'NB') {
          playerStats['runs'] = playerStats['runs']! + runs; // Runs off bat on NB count
        }
        
        // Count balls faced (legal only) - CRITICAL: Only count if striker is valid
        if (isLegalBall && striker.isNotEmpty) {
          playerStats['balls'] = playerStats['balls']! + 1;
        }
        
        // Count boundaries (only if runs are off the bat)
        if (extraType == null || extraType == 'NB') {
          if (runs == 4) playerStats['fours'] = playerStats['fours']! + 1;
          if (runs == 6) playerStats['sixes'] = playerStats['sixes']! + 1;
        }
      }
      
      // Convert to _PlayerBattingStat list
      for (final entry in playerStatsMap.entries) {
        final player = entry.key;
        final playerStats = entry.value;
        final runs = playerStats['runs']!;
        final balls = playerStats['balls']!;
        final fours = playerStats['fours']!;
        final sixes = playerStats['sixes']!;
        final strikeRate = balls > 0 ? (runs / balls) * 100 : 0.0;
        
        final isDismissed = dismissedPlayers.contains(player);
        final dismissal = isDismissed ? (dismissalTypes[player] as String?) : null;
        
        stats.add(_PlayerBattingStat(
          playerName: player,
          runs: runs,
          balls: balls,
          fours: fours,
          sixes: sixes,
          strikeRate: strikeRate,
          minutes: 0,
          dismissal: dismissal,
          isNotOut: !isDismissed,
        ));
      }
    } else {
      // Fallback: Use stored maps if deliveries are not available (legacy support)
      Map<String, dynamic>? statsMap;
    
    if (isCurrent) {
      statsMap = scorecard['player_stats_map'] as Map<String, dynamic>?;
    } else {
      statsMap = scorecard['first_innings_player_stats'] as Map<String, dynamic>?;
    }
    
    if (statsMap != null && statsMap.isNotEmpty) {
      final players = statsMap.keys.toList();
      
      for (final player in players) {
        final playerStats = statsMap[player] as Map<String, dynamic>;
        
        int runs = (playerStats['runs'] as num?)?.toInt() ?? 0;
        int balls = (playerStats['balls'] as num?)?.toInt() ?? 0;
        int fours = (playerStats['fours'] as num?)?.toInt() ?? 0;
        int sixes = (playerStats['sixes'] as num?)?.toInt() ?? 0;
        
        final strikeRate = balls > 0 ? (runs / balls) * 100 : 0.0;
        
        final isDismissed = dismissedPlayers.contains(player) || (playerStats['dismissal'] != null);
        final dismissal = (playerStats['dismissal'] as String?) ?? (isDismissed ? dismissalTypes[player] as String? : null);
        
        stats.add(_PlayerBattingStat(
          playerName: player,
          runs: runs,
          balls: balls,
          fours: fours,
          sixes: sixes,
          strikeRate: strikeRate,
          minutes: 0,
          dismissal: dismissal,
          isNotOut: !isDismissed,
        ));
        }
      }
      
      // Also add striker/non-striker if they are missing from stats map (shouldn't happen but safe fallback)
      if (isCurrent) {
        final striker = scorecard['striker'] as String? ?? '';
        final nonStriker = scorecard['non_striker'] as String? ?? '';
        
        if (striker.isNotEmpty && !stats.any((s) => s.playerName == striker)) {
           // Fallback for striker if somehow missing
           final strikerRuns = (scorecard['striker_runs'] as num?)?.toInt() ?? 0;
           final strikerBalls = (scorecard['striker_balls'] as num?)?.toInt() ?? 0;
           stats.add(_PlayerBattingStat(
             playerName: striker,
             runs: strikerRuns,
             balls: strikerBalls,
             fours: 0, sixes: 0,
             strikeRate: strikerBalls > 0 ? (strikerRuns / strikerBalls) * 100 : 0.0,
             minutes: 0,
             isNotOut: true
           ));
        }
        if (nonStriker.isNotEmpty && !stats.any((s) => s.playerName == nonStriker)) {
           // Fallback for non-striker
           final nonStrikerRuns = (scorecard['non_striker_runs'] as num?)?.toInt() ?? 0;
           final nonStrikerBalls = (scorecard['non_striker_balls'] as num?)?.toInt() ?? 0;
           stats.add(_PlayerBattingStat(
             playerName: nonStriker,
             runs: nonStrikerRuns,
             balls: nonStrikerBalls,
             fours: 0, sixes: 0,
             strikeRate: nonStrikerBalls > 0 ? (nonStrikerRuns / nonStrikerBalls) * 100 : 0.0,
             minutes: 0,
             isNotOut: true
           ));
        }
      }
      
      }
      
      return stats;
    }
    
  // Build bowling stats from scorecard data
  // PRODUCTION: Uses new ScorecardEngine for accurate calculations
  List<_PlayerBowlingStat> _buildBowlingStatsFromScorecard(
    Map<String, dynamic> scorecard,
    String teamName, {
    bool isCurrent = false,
  }) {
    final stats = <_PlayerBowlingStat>[];
    
    // Get deliveries for the appropriate innings (source of truth)
    List<dynamic> deliveriesJson;
    if (isCurrent) {
      deliveriesJson = scorecard['deliveries'] as List<dynamic>? ?? [];
    } else {
      deliveriesJson = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
    }
    
    // PRODUCTION: Use new ScorecardEngine if deliveries are available
    if (deliveriesJson.isNotEmpty) {
      try {
        // Convert to DeliveryModel and use engine
        final deliveries = ScorecardAdapter.deliveriesFromJson(deliveriesJson);
        if (deliveries.isNotEmpty) {
          final currentInnings = (scorecard['current_innings'] as num?)?.toInt() ?? 1;
          final isSuperOver = scorecard['is_super_over'] as bool? ?? false;
          final superOverNumber = (scorecard['super_over_number'] as num?)?.toInt();
          
          final scorecardModel = ScorecardEngine.calculateScorecard(
            deliveries: deliveries,
            teamName: teamName,
            isSuperOver: isSuperOver,
            superOverNumber: superOverNumber,
          );
          
          // Convert engine output to UI format
          for (final bowlingStat in scorecardModel.bowlingStats) {
            stats.add(_PlayerBowlingStat(
              bowlerName: bowlingStat.bowlerName,
              overs: bowlingStat.overs,
              maidens: bowlingStat.maidens,
              runs: bowlingStat.runs,
              wickets: bowlingStat.wickets,
              economy: bowlingStat.economy,
            ));
          }
          
          // Sort by overs (descending)
          stats.sort((a, b) => b.overs.compareTo(a.overs));
          
          // Return early if engine calculation succeeded
          return stats;
        }
      } catch (e) {
        debugPrint('WARNING: ScorecardEngine calculation failed, falling back to manual calculation: $e');
        // Fall through to manual calculation
      }
    }
    
    // FALLBACK: Manual calculation from deliveries (legacy support)
    List<dynamic> deliveries;
    if (isCurrent) {
      deliveries = scorecard['deliveries'] as List<dynamic>? ?? [];
    } else {
      deliveries = scorecard['first_innings_deliveries'] as List<dynamic>? ?? [];
    }
    
    if (deliveries.isNotEmpty) {
      // CRITICAL: Deduplicate deliveries by deliveryNumber to avoid double-counting
      final seenDeliveryNumbers = <int>{};
      final validDeliveries = <Map<String, dynamic>>[];
      
      for (final json in deliveries) {
        final d = json as Map<String, dynamic>;
        final deliveryNumber = (d['deliveryNumber'] as num?)?.toInt();
        final bowler = d['bowler'] as String? ?? '';
        final striker = d['striker'] as String? ?? '';
        
        // CRITICAL: For bowler stats, we MUST count legal balls even if striker is empty
        // The ball was bowled and should count for the bowler regardless of striker
        // Only skip if bowler is empty (invalid delivery)
        if (bowler.isEmpty) {
          debugPrint('WARNING: Found delivery with empty bowler in ${isCurrent ? "current" : "first"} innings bowling stats - skipping');
          continue;
        }
        
        // If striker is empty but it's a legal ball, we still count it for bowler
        // This handles edge cases like last wicket where striker might be cleared
        if (striker.isEmpty) {
          final isLegalBall = d['isLegalBall'] as bool? ?? true;
          if (isLegalBall) {
            debugPrint('WARNING: Found legal ball delivery with empty striker in ${isCurrent ? "current" : "first"} innings - will count for bowler stats');
          }
        }
        
        // Skip duplicates (same deliveryNumber)
        if (deliveryNumber != null) {
          if (seenDeliveryNumbers.contains(deliveryNumber)) {
            debugPrint('WARNING: Found duplicate delivery #$deliveryNumber in ${isCurrent ? "current" : "first"} innings bowling stats - skipping');
            continue;
          }
          seenDeliveryNumbers.add(deliveryNumber);
        }
        
        validDeliveries.add(d);
      }
      
      // Recalculate bowler stats from valid deliveries only
      final bowlerStatsMap = <String, Map<String, int>>{}; // bowler -> {legalBalls, runs, wickets, maidens}
      final overRuns = <int, int>{}; // over -> runs conceded
      final overLegalBalls = <int, int>{}; // over -> legal balls
      final overBowler = <int, String>{}; // over -> bowler
      
      for (final d in validDeliveries) {
        final bowler = d['bowler'] as String? ?? '';
        if (bowler.isEmpty) continue;
        
        // Initialize bowler stats if needed
        if (!bowlerStatsMap.containsKey(bowler)) {
          bowlerStatsMap[bowler] = {
            'legalBalls': 0,
            'runs': 0,
            'wickets': 0,
            'maidens': 0,
          };
        }
        
        final bowlerStats = bowlerStatsMap[bowler]!;
        final over = (d['over'] as num?)?.toInt() ?? 0;
        final isLegalBall = d['isLegalBall'] as bool? ?? true;
        final striker = d['striker'] as String? ?? '';
        final extraType = d['extraType'] as String?;
        final runs = (d['runs'] as num?)?.toInt() ?? 0;
        final extraRuns = (d['extraRuns'] as num?)?.toInt() ?? 0;
        final wicketType = d['wicketType'] as String?;
        
        // CRITICAL: Count legal balls for bowler - the ball was bowled, so it counts
        // Even if striker is empty (edge case: last wicket), the ball still counts for bowler
        // This ensures bowler overs match team total overs
        if (isLegalBall) {
          bowlerStats['legalBalls'] = bowlerStats['legalBalls']! + 1;
        }
        
        // Count runs conceded
        if (extraType == 'WD' || extraType == 'NB') {
          bowlerStats['runs'] = bowlerStats['runs']! + extraRuns;
        } else {
          bowlerStats['runs'] = bowlerStats['runs']! + runs;
        }
        
        // Count wickets (only credited wickets)
        if (wicketType != null) {
          const creditToBowler = ['Bowled', 'Caught', 'LBW', 'Stumped', 'Hit Wicket'];
          bool isCredited = false;
          for (final type in creditToBowler) {
            if (wicketType.contains(type)) {
              isCredited = true;
              break;
            }
          }
          if (isCredited) {
            bowlerStats['wickets'] = bowlerStats['wickets']! + 1;
          }
        }
        
        // Track over data for maiden calculation
        overBowler[over] = bowler;
        int incrementalRuns = 0;
        if (extraType == 'WD' || extraType == 'NB') {
          incrementalRuns = extraRuns;
        } else {
          incrementalRuns = runs;
        }
        overRuns[over] = (overRuns[over] ?? 0) + incrementalRuns;
        // CRITICAL: Count legal balls for maiden calculation - ball counts even if striker empty
        if (isLegalBall) {
          overLegalBalls[over] = (overLegalBalls[over] ?? 0) + 1;
        }
      }
      
      // Calculate maidens (6 legal balls, 0 runs)
      for (final overNum in overBowler.keys) {
        final bowlerName = overBowler[overNum]!;
        final runsConceded = overRuns[overNum] ?? 0;
        final legalBalls = overLegalBalls[overNum] ?? 0;
        
        if (legalBalls == 6 && runsConceded == 0 && bowlerStatsMap.containsKey(bowlerName)) {
          bowlerStatsMap[bowlerName]!['maidens'] = bowlerStatsMap[bowlerName]!['maidens']! + 1;
        }
      }
      
      // Convert to _PlayerBowlingStat list
      for (final entry in bowlerStatsMap.entries) {
        final bowler = entry.key;
        final bowlerStats = entry.value;
        final legalBalls = bowlerStats['legalBalls']!;
        final completeOvers = legalBalls ~/ 6;
        final remainingBalls = legalBalls % 6;
        final overs = completeOvers + (remainingBalls / 10.0);
        final economy = legalBalls > 0 ? (bowlerStats['runs']! / legalBalls) * 6 : 0.0;
        
        stats.add(_PlayerBowlingStat(
          bowlerName: bowler,
          overs: overs,
          maidens: bowlerStats['maidens']!,
          runs: bowlerStats['runs']!,
          wickets: bowlerStats['wickets']!,
          economy: economy,
        ));
      }
    } else {
      // Fallback: Use stored maps if deliveries are not available (legacy support)
    Map<String, dynamic>? statsMap;
    
    if (isCurrent) {
      statsMap = scorecard['bowler_stats_map'] as Map<String, dynamic>?;
    } else {
      statsMap = scorecard['first_innings_bowler_stats'] as Map<String, dynamic>?;
    }
    
    if (statsMap != null && statsMap.isNotEmpty) {
      final bowlers = statsMap.keys.toList();

      for (final bowler in bowlers) {
        final bowlerStats = statsMap[bowler] as Map<String, dynamic>;
        
        final legalBalls = (bowlerStats['legalBalls'] as num?)?.toInt() ?? 0;
        final completeOvers = legalBalls ~/ 6;
        final remainingBalls = legalBalls % 6;
        final overs = completeOvers + (remainingBalls / 10.0);
        
        int maidens = (bowlerStats['maidens'] as num?)?.toInt() ?? 0;
        int runs = (bowlerStats['runs'] as num?)?.toInt() ?? 0;
        int wickets = (bowlerStats['wickets'] as num?)?.toInt() ?? 0;
        
        final economy = legalBalls > 0 ? (runs / legalBalls) * 6 : 0.0;
        
        stats.add(_PlayerBowlingStat(
          bowlerName: bowler,
          overs: overs,
          maidens: maidens,
          runs: runs,
          wickets: wickets,
          economy: economy,
        ));
        }
      }
    }
    
    // Sort by overs (descending)
    stats.sort((a, b) => b.overs.compareTo(a.overs));
    
    return stats;
  }
}

// Delegate for the pinned TabBar in NestedScrollView
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

// Player batting statistics
class _PlayerBattingStat {
  final String playerName;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final double strikeRate;
  final int minutes;
  final String? dismissal;
  final bool isNotOut;

  _PlayerBattingStat({
    required this.playerName,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    required this.minutes,
    this.dismissal,
    this.isNotOut = false,
  });
}

// Player bowling statistics
class _PlayerBowlingStat {
  final String bowlerName;
  final double overs;
  final int maidens;
  final int runs;
  final int wickets;
  final double economy;

  _PlayerBowlingStat({
    required this.bowlerName,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });
}

// Expandable Innings Scorecard Widget
class _InningsScorecardWidget extends StatefulWidget {
  final String teamName;
  final int runs;
  final int wickets;
  final double overs;
  final bool isCurrentInnings;
  final bool isMatchCompleted;
  final List<_PlayerBattingStat> battingStats;
  final List<_PlayerBowlingStat> bowlingStats;
  final int extras;
  final Map<String, dynamic> extrasMap;
  final List<String> didNotBat;

  const _InningsScorecardWidget({
    required this.teamName,
    required this.runs,
    required this.wickets,
    required this.overs,
    required this.isCurrentInnings,
    this.isMatchCompleted = false,
    required this.battingStats,
    required this.bowlingStats,
    this.extras = 0,
    this.extrasMap = const {},
    this.didNotBat = const [],
  });

  @override
  State<_InningsScorecardWidget> createState() => _InningsScorecardWidgetState();
}

class _InningsScorecardWidgetState extends State<_InningsScorecardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    // Current innings starts expanded, previous starts collapsed
    _isExpanded = widget.isCurrentInnings;
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _formatOvers(double overs) {
    final wholeOvers = overs.floor();
    final balls = ((overs - wholeOvers) * 6).round();
    if (balls == 6) {
      return '${wholeOvers + 1}.0';
    }
    return '$wholeOvers.$balls';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isCurrentInnings
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.borderLight.withOpacity(0.5),
          width: widget.isCurrentInnings ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
          if (widget.isCurrentInnings)
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 1),
              spreadRadius: 0,
            ),
        ],
      ),
      child: Column(
        children: [
          // Innings Header (Always Visible)
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
                if (_isExpanded) {
                  _animationController.forward();
                } else {
                  _animationController.reverse();
                }
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: widget.isCurrentInnings
                    ? AppColors.primary.withOpacity(0.04)
                    : AppColors.elevated.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.isCurrentInnings 
                                  ? (widget.isMatchCompleted ? 'SECOND INNINGS' : 'CURRENT INNINGS') 
                                  : 'FIRST INNINGS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: widget.isCurrentInnings
                                    ? AppColors.primary
                                    : AppColors.textSec.withOpacity(0.7),
                                letterSpacing: 1.5,
                                fontFamily: 'Inter',
                              ),
                            ),
                            if (widget.isCurrentInnings && !widget.isMatchCompleted) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.urgent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontFamily: 'Inter',
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.teamName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textMain,
                            fontFamily: 'Inter',
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Score section - right-aligned
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${widget.runs}',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: widget.isCurrentInnings
                                  ? AppColors.primary
                                  : AppColors.textMain,
                              fontFamily: 'Inter',
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          Text(
                            '/${widget.wickets}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSec.withOpacity(0.8),
                              fontFamily: 'Inter',
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatOvers(widget.overs)} Ov',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSec.withOpacity(0.7),
                          fontFamily: 'Inter',
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Expand/collapse arrow
                  RotationTransition(
                    turns: Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnimation),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSec.withOpacity(0.6),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable Content
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              children: [
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderLight.withOpacity(0.3),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BattingScorecardTable(
                    battingStats: widget.battingStats,
                    extras: widget.extras,
                    extrasMap: widget.extrasMap,
                    totalRuns: widget.runs,
                    totalWickets: widget.wickets,
                    totalOvers: widget.overs,
                  ),
                ),
                if (widget.didNotBat.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildDidNotBatSection(widget.didNotBat),
                  ),
                ],
                if (widget.bowlingStats.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _BowlingScorecardTable(
                      bowlingStats: widget.bowlingStats,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDidNotBatSection(List<String> players) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.elevated.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderLight.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Did Not Bat',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSec.withOpacity(0.8),
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            players.join(', '),
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMain.withOpacity(0.9),
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Bowling Scorecard Table Widget
class _BowlingScorecardTable extends StatelessWidget {
  final List<_PlayerBowlingStat> bowlingStats;

  const _BowlingScorecardTable({required this.bowlingStats});

  // Fixed column widths
  static const double _statColumnWidth = 45.0; 

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderLight.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.elevated.withOpacity(0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bowlers',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSec.withOpacity(0.8),
                      fontFamily: 'Inter',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('O'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('M'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('R'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('W'),
                ),
                SizedBox(
                  width: 50,
                  child: _buildHeaderCell('Eco'),
                ),
              ],
            ),
          ),
          // Table Rows
          ...bowlingStats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            final isLast = index == bowlingStats.length - 1;
            return _buildBowlingRow(stat, isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSec.withOpacity(0.8),
        fontFamily: 'Inter',
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildBowlingRow(_PlayerBowlingStat stat, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.bowlerName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
                fontFamily: 'Inter',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(_formatOvers(stat.overs)),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.maidens.toString()),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.runs.toString(), isBold: true),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.wickets.toString(), isBold: true),
          ),
          SizedBox(
            width: 50,
            child: _buildDataCell(stat.economy.toStringAsFixed(1)),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCell(String text, {bool isBold = false}) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
        color: AppColors.textMain,
        fontFamily: 'Inter',
      ),
    );
  }

  String _formatOvers(double overs) {
    final wholeOvers = overs.floor();
    final balls = ((overs - wholeOvers) * 6).round();
    if (balls == 6) {
      return '${wholeOvers + 1}.0';
    }
    return '$wholeOvers.$balls';
  }
}


// Batting Scorecard Table Widget
class _BattingScorecardTable extends StatelessWidget {
  final List<_PlayerBattingStat> battingStats;
  final int extras;
  final Map<String, dynamic> extrasMap;
  final int totalRuns;
  final int totalWickets;
  final double totalOvers;

  const _BattingScorecardTable({
    required this.battingStats,
    this.extras = 0,
    this.extrasMap = const {},
    this.totalRuns = 0,
    this.totalWickets = 0,
    this.totalOvers = 0.0,
  });

  // Fixed column widths for perfect alignment
  static const double _statColumnWidth = 32.0; // Fixed width for R, B, 4s, 6s
  static const double _srColumnWidth = 42.0; // Slightly wider for SR

  @override
  Widget build(BuildContext context) {
    if (battingStats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            'No batting data available',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSec,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderLight.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header - Perfect alignment with fixed widths
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.elevated.withOpacity(0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // Batter name column - flexible
                Expanded(
                  child: Text(
                    'Batters',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSec.withOpacity(0.8),
                      fontFamily: 'Inter',
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Fixed-width stat columns
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('R'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('B'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('4s'),
                ),
                SizedBox(
                  width: _statColumnWidth,
                  child: _buildHeaderCell('6s'),
                ),
                SizedBox(
                  width: _srColumnWidth,
                  child: _buildHeaderCell('SR'),
                ),
              ],
            ),
          ),
          // Table Rows
          ...battingStats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            return _buildBattingRow(stat, false); // No longer checking isLast here
          }),
          
          // Extras Row
          _buildExtrasRow(),
          
          // Total Row
          _buildTotalRow(),
        ],
      ),
    );
  }

  Widget _buildExtrasRow() {
    final List<String> details = [];
    if ((extrasMap['WD'] as num? ?? 0) > 0) details.add('wd ${extrasMap['WD']}');
    if ((extrasMap['NB'] as num? ?? 0) > 0) details.add('nb ${extrasMap['NB']}');
    if ((extrasMap['B'] as num? ?? 0) > 0) details.add('b ${extrasMap['B']}');
    if ((extrasMap['LB'] as num? ?? 0) > 0) details.add('lb ${extrasMap['LB']}');
    if ((extrasMap['P'] as num? ?? 0) > 0) details.add('p ${extrasMap['P']}');
    
    final detailsStr = details.isNotEmpty ? '(${details.join(', ')})' : '';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.elevated.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  'Extras',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain.withOpacity(0.8),
                    fontFamily: 'Inter',
                  ),
                ),
                if (detailsStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    detailsStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSec.withOpacity(0.6),
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Text(
            extras.toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Text(
            'Total',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          Text(
            '$totalRuns/$totalWickets (${_formatOvers(totalOvers)})',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  String _formatOvers(double overs) {
      final wholeOvers = overs.floor();
      final balls = ((overs - wholeOvers) * 6).round();
      if (balls == 6) {
        return '${wholeOvers + 1}.0';
      }
      return '$wholeOvers.$balls';
    }

  Widget _buildHeaderCell(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSec.withOpacity(0.8),
        fontFamily: 'Inter',
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildBattingRow(_PlayerBattingStat stat, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.borderLight.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Batter name column - flexible, left-aligned
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stat.playerName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                    fontFamily: 'Inter',
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (stat.dismissal != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    stat.dismissal!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSec.withOpacity(0.75),
                      fontFamily: 'Inter',
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (stat.isNotOut) ...[
                  const SizedBox(height: 5),
                  Text(
                    'not out',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.success.withOpacity(0.8),
                      fontFamily: 'Inter',
                      fontStyle: FontStyle.italic,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Fixed-width stat columns - center-aligned
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(
              stat.runs.toString(),
              isHighlight: true,
            ),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.balls.toString()),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.fours.toString()),
          ),
          SizedBox(
            width: _statColumnWidth,
            child: _buildDataCell(stat.sixes.toString()),
          ),
          SizedBox(
            width: _srColumnWidth,
            child: _buildDataCell(
              stat.strikeRate.toStringAsFixed(1),
              isStrikeRate: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCell(String text, {bool isHighlight = false, bool isStrikeRate = false}) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
        color: isStrikeRate
            ? AppColors.primary.withOpacity(0.8)
            : isHighlight
                ? AppColors.textMain
                : AppColors.textSec,
        fontFamily: 'Inter',
        height: 1.3,
      ),
    );
  }
}

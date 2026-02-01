import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/models/commentary_model.dart';
import '../../../../core/repositories/commentary_repository.dart';
import '../../../../core/repositories/match_repository.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/app_colors.dart';
import 'dart:async';

/// Provider for commentary stream with initial data and real-time updates
final commentaryStreamProvider = StreamProvider.family<List<CommentaryModel>, String>((ref, matchId) async* {
  final repository = ref.watch(commentaryRepositoryProvider);
  
  // First, fetch all existing commentary
  print('Commentary: Provider - Starting for matchId=$matchId');
  final initialCommentary = await repository.getCommentaryByMatchId(matchId);
  print('Commentary: Provider - Initial fetch got ${initialCommentary.length} entries');
  yield initialCommentary;
  
  // Then stream updates - polling every 2 seconds for new balls
  print('Commentary: Provider - Starting stream for matchId=$matchId');
  yield* repository.streamCommentary(matchId);
});

class NewCommentaryPage extends ConsumerStatefulWidget {
  final String matchId;
  final bool showAppBar;
  final String? matchStatus;
  final String? team1Name;
  final String? team2Name;

  const NewCommentaryPage({
    super.key,
    required this.matchId,
    this.showAppBar = false,
    this.matchStatus,
    this.team1Name,
    this.team2Name,
  });

  @override
  ConsumerState<NewCommentaryPage> createState() => _NewCommentaryPageState();
}

class _NewCommentaryPageState extends ConsumerState<NewCommentaryPage> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;
  int _previousCommentaryCount = 0;
  String? _fetchedMatchStatus;
  int _selectedInnings = 2; // 1 for first innings, 2 for second innings
  bool _hasInitializedInnings = false;
  int? _currentInningsFromScorecard; // Get from match scorecard
  bool _hasSecondInningsStarted = false; // Based on scorecard data
  
  @override
  void initState() {
    super.initState();
    if (widget.matchStatus == null) {
      _fetchMatchStatus();
    }
    _fetchMatchScorecard();
    // Auto-scroll to latest when new commentary arrives (only for live matches)
    if (widget.matchStatus == 'live') {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (mounted) {
          final currentStatus = widget.matchStatus ?? _fetchedMatchStatus;
          if (currentStatus != 'live') {
            timer.cancel();
            return;
          }
          ref.read(commentaryStreamProvider(widget.matchId).stream).listen((commentaryList) {
            if (commentaryList.length > _previousCommentaryCount) {
              _previousCommentaryCount = commentaryList.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          });
        }
      });
    }
  }
  
  Future<void> _fetchMatchStatus() async {
    try {
      final response = await SupabaseConfig.client
          .from('matches')
          .select('status')
          .eq('id', widget.matchId)
          .maybeSingle();
      
      if (mounted && response != null) {
        setState(() {
          _fetchedMatchStatus = response['status'] as String?;
        });
      }
    } catch (e) {
      print('Error fetching match status: $e');
    }
  }

  Future<void> _fetchMatchScorecard() async {
    try {
      final response = await SupabaseConfig.client
          .from('matches')
          .select('scorecard')
          .eq('id', widget.matchId)
          .maybeSingle();
      
      if (mounted && response != null) {
        final scorecard = response['scorecard'] as Map<String, dynamic>?;
        if (scorecard != null) {
          final currentInnings = scorecard['current_innings'] as int? ?? 1;
          final firstInningsRuns = scorecard['first_innings_runs'] as int? ?? 0;
          
          setState(() {
            _currentInningsFromScorecard = currentInnings;
            // Second innings has started if current_innings == 2 OR first_innings_runs > 0
            _hasSecondInningsStarted = currentInnings == 2 || firstInningsRuns > 0;
          });
          
          print('Commentary: Scorecard - currentInnings=$currentInnings, firstInningsRuns=$firstInningsRuns, hasSecondInningsStarted=$_hasSecondInningsStarted');
        }
      }
    } catch (e) {
      print('Error fetching match scorecard: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentaryAsync = ref.watch(commentaryStreamProvider(widget.matchId));

    final content = commentaryAsync.when(
      data: (commentaryList) {
        _previousCommentaryCount = commentaryList.length;
        
        if (commentaryList.isEmpty) {
          return _buildEmptyState();
        }

        final sortedList = List<CommentaryModel>.from(commentaryList)
          ..sort((a, b) {
            final timeCompare = b.timestamp.compareTo(a.timestamp); // Latest first
            if (timeCompare != 0) return timeCompare;
            return b.over.compareTo(a.over);
          });
        
        final inningsData = _splitCommentaryByInnings(sortedList);
        final inn1List = inningsData['inn1']!;
        final inn2List = inningsData['inn2']!;
        
        // Sort both innings lists the same way as the original sortedList (latest first)
        // This ensures consistent processing for both innings
        final inn1Sorted = List<CommentaryModel>.from(inn1List)
          ..sort((a, b) {
            final timeCompare = b.timestamp.compareTo(a.timestamp); // Latest first
            if (timeCompare != 0) return timeCompare;
            return b.over.compareTo(a.over);
          });
        final inn2Sorted = List<CommentaryModel>.from(inn2List)
          ..sort((a, b) {
            final timeCompare = b.timestamp.compareTo(a.timestamp); // Latest first
            if (timeCompare != 0) return timeCompare;
            return b.over.compareTo(a.over);
          });
        
        // Group both innings using the same logic
        print('Commentary: Grouping inn1 with ${inn1Sorted.length} entries (sorted latest first)');
        final inn1Grouped = _groupCommentaryWithSummaries(inn1Sorted);
        print('Commentary: Grouped inn1 into ${inn1Grouped.length} items');
        
        print('Commentary: Grouping inn2 with ${inn2Sorted.length} entries (sorted latest first)');
        final inn2Grouped = _groupCommentaryWithSummaries(inn2Sorted);
        print('Commentary: Grouped inn2 into ${inn2Grouped.length} items');

        // Determine if both innings have data
        final hasInn1 = inn1List.isNotEmpty;
        final hasInn2 = inn2List.isNotEmpty;
        
        // Use scorecard data to determine if second innings has started
        // If scorecard says second innings has started, we should show toggle even if detection didn't work
        final bothInningsExist = (hasInn1 && hasInn2) || _hasSecondInningsStarted;
        
        // Debug: Print innings status
        print('Commentary: hasInn1=$hasInn1 (${inn1List.length} entries), hasInn2=$hasInn2 (${inn2List.length} entries), hasSecondInningsStarted=$_hasSecondInningsStarted, bothInningsExist=$bothInningsExist');
        
        // Get match status
        final matchStatus = widget.matchStatus ?? _fetchedMatchStatus;
        final isMatchCompleted = matchStatus == 'completed';
        
        // Show toggle when:
        // 1. Both innings have commentary data detected, OR
        // 2. Scorecard indicates second innings has started (even if detection didn't work)
        final shouldShowToggle = bothInningsExist;

        // Initialize selected innings based on which has the latest/most recent data
        if (!_hasInitializedInnings) {
          // If scorecard says we're in second innings, default to second innings
          if (_hasSecondInningsStarted && _currentInningsFromScorecard == 2) {
            _selectedInnings = 2;
          } else if (hasInn2 && hasInn1) {
            // If both innings exist, check which has more recent data
            // Since sortedList is sorted with latest first, we need to find the latest in each innings
            final inn1Latest = inn1List.isNotEmpty 
                ? inn1List.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b).timestamp 
                : DateTime(1970);
            final inn2Latest = inn2List.isNotEmpty 
                ? inn2List.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b).timestamp 
                : DateTime(1970);
            _selectedInnings = inn2Latest.isAfter(inn1Latest) ? 2 : 1;
          } else if (hasInn1) {
            _selectedInnings = 1;
          } else if (hasInn2) {
            _selectedInnings = 2;
          } else {
            // Default based on scorecard
            _selectedInnings = _currentInningsFromScorecard ?? 1;
          }
          _hasInitializedInnings = true;
        }

        // Get selected innings commentary based on toggle
        // If second innings has started but no data detected yet, show empty state for second innings
        final selectedInningsList = _selectedInnings == 1 
            ? inn1Grouped 
            : (inn2Grouped.isNotEmpty ? inn2Grouped : <Map<String, dynamic>>[]);

        if (widget.showAppBar) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text(
                'Match Commentary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              centerTitle: true,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              automaticallyImplyLeading: true, // Show single back button
            ),
            body: Column(
              children: [
                // Innings Toggle Switch - ALWAYS show when both innings exist
                if (bothInningsExist)
                  _buildInningsToggle(hasInn1, hasInn2),
                // Commentary List - show only selected innings
                Expanded(
                  child: _buildCommentaryList(selectedInningsList),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Innings Toggle Switch - ALWAYS show when both innings exist
            if (bothInningsExist)
              _buildInningsToggle(hasInn1, hasInn2),
            // Commentary List - show only selected innings
            Expanded(
              child: _buildCommentaryList(selectedInningsList),
            ),
          ],
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 3,
        ),
      ),
      error: (error, stack) => _buildErrorState(error),
    );

    // Don't wrap in another Scaffold - the content already handles showAppBar
    return content;
  }

  Widget _buildInningsToggle(bool hasInn1, bool hasInn2) {
    final team1Name = widget.team1Name ?? 'Team 1';
    final team2Name = widget.team2Name ?? 'Team 2';
    
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, left: 16, right: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Row(
        children: [
          _buildInningsToggleButton(
            label: '$team1Name 1st Inns',
            isSelected: _selectedInnings == 1,
            onTap: () {
              setState(() {
                _selectedInnings = 1;
              });
            },
          ),
          const SizedBox(width: 4),
          _buildInningsToggleButton(
            label: '$team2Name 2nd Inns',
            isSelected: _selectedInnings == 2,
            onTap: () {
              setState(() {
                _selectedInnings = 2;
              });
            },
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 400.ms)
      .slideY(begin: -0.2, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildInningsToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        )
          .animate(target: isSelected ? 1 : 0)
          .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.05, 1.05), duration: 200.ms)
          .then()
          .scale(begin: const Offset(1.05, 1.05), end: const Offset(1.0, 1.0), duration: 200.ms),
      ),
    );
  }

  Widget _buildCommentaryList(List<Map<String, dynamic>> groupedItems) {
    final matchStatus = widget.matchStatus ?? _fetchedMatchStatus;
    final isMatchLive = matchStatus == 'live';
    
    if (groupedItems.isEmpty) {
      return _buildEmptyState();
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      reverse: true, // Latest at top
      itemCount: groupedItems.length,
      itemBuilder: (context, index) {
        final item = groupedItems[index];
        final isLatest = index == 0 && isMatchLive;
        
        if (item['type'] == 'overSummary') {
          return OverSummaryBar(
            summaryText: item['text'] as String,
            isLatest: isLatest,
          );
        } else if (item['type'] == 'inningsBreak') {
          return const InningsBreakCard();
        } else {
          final commentary = item['commentary'] as CommentaryModel;
          if (commentary.ballType == 'newBatsman') {
            return NewBatsmanCard(
              batsmanName: commentary.strikerName,
              isLatest: isLatest,
            );
          }
          return BallByBallCard(
            commentary: commentary,
            isLatest: isLatest,
            isFirst: index == groupedItems.length - 1,
            isLast: index == 0,
          );
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.comment_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No commentary available',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Commentary will appear here once the match starts',
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

  Widget _buildErrorState(dynamic error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.urgent,
            )
              .animate()
              .shake(duration: 600.ms)
              .then()
              .fadeIn(),
            const SizedBox(height: 24),
            Text(
              'Couldn\'t load commentary',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textMain,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.toString(),
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSec,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<CommentaryModel>> _splitCommentaryByInnings(List<CommentaryModel> list) {
    final List<CommentaryModel> inn1 = [];
    final List<CommentaryModel> inn2 = [];
    final List<CommentaryModel> summaries = []; // Collect summaries separately
    
    if (list.isEmpty) {
      return {'inn1': inn1, 'inn2': inn2};
    }
    
    // Sort by timestamp (ascending) to get chronological order
    // This ensures we see 1st innings entries before 2nd innings entries
    final sortedByTime = List<CommentaryModel>.from(list)
      ..sort((a, b) {
        final timeCompare = a.timestamp.compareTo(b.timestamp);
        if (timeCompare != 0) return timeCompare;
        // If same timestamp, sort by over
        return a.over.compareTo(b.over);
      });
    
    // First pass: Detect innings break using only non-summary entries
    double? lastOver = null;
    DateTime? inningsBreakTimestamp = null;
    double? maxOverInInn1 = null;

    for (final item in sortedByTime) {
      // Skip over summaries for detection - collect them separately
      if (item.ballType == 'overSummary') {
        summaries.add(item);
        continue;
      }
      
      // Detect innings break: 
      // 1. If we've seen a high over (>= 1.0) in 1st innings and now see a low over (< 1.0), it's likely 2nd innings
      // 2. If over decreases significantly (more than 3 overs), it's a new innings
      // 3. If we go from a high over (>= 5) back to 0.1, it's definitely a new innings
      bool isInningsBreakDetected = false;
      if (lastOver != null && inningsBreakTimestamp == null) {
        final overDifference = lastOver - item.over;
        
        // Key detection: If we've seen overs >= 1.0 and now see 0.1-0.6, it's likely 2nd innings
        // Also check if we've built up a significant max over in inn1
        final isResetToLowOver = (maxOverInInn1 != null && maxOverInInn1 >= 1.0 && item.over < 1.0);
        final isSignificantDecrease = overDifference > 3.0;
        final isHighToLowReset = (lastOver >= 5.0 && item.over < 1.0);
        
        if (isResetToLowOver || isSignificantDecrease || isHighToLowReset) {
          // Set break timestamp to this item's timestamp
          // This item and all subsequent items will go to inn2
          inningsBreakTimestamp = item.timestamp;
          isInningsBreakDetected = true;
          print('Commentary: Innings break detected at timestamp ${item.timestamp} - lastOver=$lastOver, currentOver=${item.over}, maxOverInInn1=$maxOverInInn1, difference=$overDifference');
        }
      }
      
      // Assign to innings based on innings break timestamp
      // Use >= comparison to include items at the break timestamp (first ball of inn2)
      if (inningsBreakTimestamp != null && item.timestamp.compareTo(inningsBreakTimestamp) >= 0) {
        inn2.add(item);
        if (isInningsBreakDetected) {
          print('Commentary: First ball of inn2 - ${item.over} at ${item.timestamp}');
        }
      } else {
        inn1.add(item);
        // Track max over for 1st innings
        if (maxOverInInn1 == null || item.over > maxOverInInn1) {
          maxOverInInn1 = item.over;
        }
      }
      lastOver = item.over;
    }
    
    // Second pass: Assign summaries based on innings break timestamp
    // Use >= comparison to include summaries at or after the break timestamp
    for (final summary in summaries) {
      if (inningsBreakTimestamp != null && summary.timestamp.compareTo(inningsBreakTimestamp) >= 0) {
        inn2.add(summary);
        print('Commentary: Assigned summary at ${summary.over} (timestamp ${summary.timestamp}) to inn2');
      } else {
        inn1.add(summary);
        print('Commentary: Assigned summary at ${summary.over} (timestamp ${summary.timestamp}) to inn1');
      }
    }
    
    // Debug: Print innings split results
    print('Commentary: Split innings - inn1: ${inn1.length} entries, inn2: ${inn2.length} entries');
    if (inn1.isNotEmpty) {
      final inn1Sorted = List<CommentaryModel>.from(inn1)..sort((a, b) => a.over.compareTo(b.over));
      print('Commentary: inn1 range - ${inn1Sorted.first.over} to ${inn1Sorted.last.over}');
    }
    if (inn2.isNotEmpty) {
      final inn2Sorted = List<CommentaryModel>.from(inn2)..sort((a, b) => a.over.compareTo(b.over));
      print('Commentary: inn2 range - ${inn2Sorted.first.over} to ${inn2Sorted.last.over}');
    }
    
    return {'inn1': inn1, 'inn2': inn2};
  }

  /// Group commentary entries and insert over summaries
  /// Over summaries should appear AFTER all balls of an over (e.g., after 0.6, after 1.6, etc.)
  List<Map<String, dynamic>> _groupCommentaryWithSummaries(List<CommentaryModel> commentaryList) {
    if (commentaryList.isEmpty) return [];
    
    final List<Map<String, dynamic>> grouped = [];
    final Map<int, Map<String, dynamic>> overSummaries = {};
    
    // First pass: collect over summaries
    // Over summaries are stored with over = overNumber + 0.7 (e.g., 0.7 for over 0, 1.7 for over 1)
    // We match by the integer part of commentary.over, not by parsing the text
    // Per ICC/BCCI rules: Over 0 displays as "OVER 1", Over 1 displays as "OVER 2", etc.
    for (final commentary in commentaryList) {
      if (commentary.ballType == 'overSummary') {
        // Get the actual over number from commentary.over (0.7 -> 0, 1.7 -> 1)
        final overNum = commentary.over.toInt();
        // Extract display number from text to verify
        final textMatch = RegExp(r'OVER (\d+)').firstMatch(commentary.commentaryText);
        final displayNum = textMatch != null ? int.parse(textMatch.group(1)!) : null;
        overSummaries[overNum] = {
          'type': 'overSummary',
          'text': commentary.commentaryText,
          'over': overNum,
          'timestamp': commentary.timestamp,
        };
        print('OverSummary: Collected summary - stored over=$overNum, display text="OVER ${displayNum ?? '?'}", stored at ${commentary.over}');
        // Verify: overNum + 1 should equal displayNum (per ICC/BCCI rules)
        if (displayNum != null && displayNum != overNum + 1) {
          print('OverSummary: WARNING - Display number ($displayNum) does not match expected (${overNum + 1})');
        }
      }
    }
    
    // Group commentary by over number
    final Map<int, List<CommentaryModel>> overGroups = {};
    for (final commentary in commentaryList) {
      if (commentary.ballType == 'overSummary') continue;
      
      final overNum = commentary.over.toInt();
      if (!overGroups.containsKey(overNum)) {
        overGroups[overNum] = [];
      }
      overGroups[overNum]!.add(commentary);
    }
    
    // Sort over numbers (highest first, since we want latest first)
    final sortedOverNumbers = overGroups.keys.toList()..sort((a, b) => b.compareTo(a));
    
    // Process each over: add summary first, then all balls
    // Since ListView has reverse: true, adding summary first ensures it appears AFTER balls when displayed
    for (final overNum in sortedOverNumbers) {
      final balls = overGroups[overNum]!;
      // Sort balls within over by over value (descending - latest first: 0.6, 0.5, ..., 0.1)
      // When ListView reverses, they display as 0.1, 0.2, ..., 0.6 (correct order)
      balls.sort((a, b) => b.over.compareTo(a.over));
      
      // Add over summary FIRST (so it appears AFTER balls when ListView reverses)
      // Per ICC/BCCI rules: Over 0 displays as "OVER 1", Over 1 displays as "OVER 2", etc.
      if (overSummaries.containsKey(overNum)) {
        final summary = overSummaries[overNum]!;
        final textMatch = RegExp(r'OVER (\d+)').firstMatch(summary['text'] as String);
        final displayNum = textMatch != null ? int.parse(textMatch.group(1)!) : null;
        final ballValues = summary['text'].toString().split('\n');
        final ballIndicators = ballValues.length > 1 ? ballValues[1] : 'N/A';
        print('OverSummary: Adding summary for stored over=$overNum (displays as "OVER ${displayNum ?? '?'}") with balls: $ballIndicators, before ${balls.length} balls (will appear after when reversed)');
        grouped.add(summary);
        overSummaries.remove(overNum);
      } else {
        print('OverSummary: WARNING - No summary found for over $overNum (available summaries: ${overSummaries.keys.toList()})');
        print('OverSummary: Balls in this over: ${balls.map((b) => b.over).toList()}');
      }
      
      // Add all balls for this over (in descending order: 0.6, 0.5, ..., 0.1)
      // When ListView reverses, they display as 0.1, 0.2, ..., 0.6 (correct chronological order)
      for (final commentary in balls) {
        grouped.add({
          'type': 'commentary',
          'commentary': commentary,
          'over': overNum,
        });
      }
    }
    
    return grouped;
  }
}

/// Over Summary Bar - Horizontal bar with ball indicators (exact screenshot format)
class OverSummaryBar extends StatelessWidget {
  final String summaryText;
  final bool isLatest;

  const OverSummaryBar({
    super.key,
    required this.summaryText,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = summaryText.split('\n');
    // Extract over title - summary text is already in correct 1-based format per ICC/BCCI rules
    // Over 0 is stored as "OVER 1", Over 1 is stored as "OVER 2", etc.
    // This matches cricket standards where the first over is called "Over 1"
    String overTitle = lines.isNotEmpty ? lines[0].trim() : '';
    
    // Verify the format is correct (should already be 1-based)
    if (overTitle.startsWith('OVER ')) {
      final overMatch = RegExp(r'OVER (\d+)').firstMatch(overTitle);
      if (overMatch != null) {
        final overNum = int.parse(overMatch.group(1)!);
        // Summary text is generated with overNumber + 1, so it's already 1-based
        // Over 0 -> "OVER 1", Over 1 -> "OVER 2", etc. (per ICC/BCCI rules)
        // Just use it as-is - no conversion needed
        overTitle = 'OVER $overNum';
        print('OverSummaryBar: Displaying $overTitle (already in correct 1-based format per ICC/BCCI rules)');
      }
    }
    final ballRuns = lines.length > 1 ? lines[1].trim() : '';
    final summary = lines.length > 2 ? lines[2].trim() : '';

    // Extract runs and wickets from the summary line (e.g., "13 Runs | 1 Wkt | 95/3")
    // This is the accurate value calculated during over summary generation
    int runsInOver = 0;
    int wicketsInOver = 0;
    
    if (summary.isNotEmpty) {
      print('OverSummaryBar: Parsing summary line: "$summary"');
      // Parse "13 Runs | 1 Wkt | 95/3" format
      final runsMatch = RegExp(r'(\d+)\s+Runs?').firstMatch(summary);
      if (runsMatch != null) {
        runsInOver = int.parse(runsMatch.group(1)!);
        print('OverSummaryBar: Extracted runs: $runsInOver');
      } else {
        print('OverSummaryBar: No runs match found in summary line');
      }
      
      final wicketsMatch = RegExp(r'(\d+)\s+Wkt').firstMatch(summary);
      if (wicketsMatch != null) {
        wicketsInOver = int.parse(wicketsMatch.group(1)!);
        print('OverSummaryBar: Extracted wickets: $wicketsInOver');
      } else {
        print('OverSummaryBar: No wickets match found in summary line');
      }
    } else {
      print('OverSummaryBar: Summary line is empty, using fallback');
    }
    
    // Fallback: If summary parsing fails, calculate from ball values (shouldn't happen)
    if (runsInOver == 0 && wicketsInOver == 0 && ballRuns.isNotEmpty) {
      print('OverSummaryBar: Using fallback calculation from ball values: "$ballRuns"');
      final ballValues = ballRuns.split(' ').where((s) => s.isNotEmpty).toList();
      for (final value in ballValues) {
        if (value.toUpperCase().contains('W') || value.toUpperCase().contains('RO')) {
          wicketsInOver++;
        } else {
          final numericMatch = RegExp(r'\d+').firstMatch(value);
          if (numericMatch != null) {
            runsInOver += int.parse(numericMatch.group(0)!);
          }
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50], // Light colored div box
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Over title
          Text(
            overTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          // Ball indicators (6 circles)
          ..._buildBallIndicators(ballRuns),
          const SizedBox(width: 12),
          // Over score
          Text(
            '$runsInOver/$wicketsInOver',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 500.ms, curve: Curves.easeOut)
      .slideX(begin: -0.1, end: 0, duration: 500.ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.98, 0.98), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOut);
  }

  List<Widget> _buildBallIndicators(String ballRuns) {
    final ballValues = ballRuns.split(' ').where((s) => s.isNotEmpty).take(6).toList();
    final indicators = <Widget>[];
    
    for (int i = 0; i < 6; i++) {
      final value = i < ballValues.length ? ballValues[i] : '';
      if (value.isEmpty) {
        indicators.add(
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(color: Colors.grey[300]!, width: 1.5),
            ),
          ),
        );
        continue;
      }
      
      String displayValue = value;
      if (value.toUpperCase() == 'W') {
        displayValue = 'W';
      } else if (value.toUpperCase().contains('RO')) {
        displayValue = 'RO';
      } else if (value.toUpperCase().startsWith('B')) {
        final numMatch = RegExp(r'\d+').firstMatch(value);
        displayValue = numMatch != null ? numMatch.group(0)! : 'B';
      } else if (value.toUpperCase().startsWith('LB')) {
        final numMatch = RegExp(r'\d+').firstMatch(value);
        displayValue = numMatch != null ? numMatch.group(0)! : 'LB';
      }
      
      final isBoundary = value == '4' || value == '6';
      final isWicket = value.toUpperCase().contains('W') || value.toUpperCase().contains('RO');
      
      indicators.add(
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isBoundary 
                ? const Color(0xFF2196F3) // Blue for boundaries
                : isWicket
                    ? Colors.red
                    : Colors.white,
            border: Border.all(
              color: isBoundary 
                  ? const Color(0xFF2196F3)
                  : isWicket
                      ? Colors.red
                      : Colors.grey[300]!,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              displayValue,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isBoundary || isWicket ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      );
    }
    
    return indicators;
  }
}

/// Ball-by-Ball Card - Exact screenshot format with timeline
class BallByBallCard extends StatelessWidget {
  final CommentaryModel commentary;
  final bool isLatest;
  final bool isFirst;
  final bool isLast;

  const BallByBallCard({
    super.key,
    required this.commentary,
    this.isLatest = false,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isWicket = commentary.ballType == 'wicket';
    final isBoundary = commentary.runs == 4 || commentary.runs == 6;
    final isFour = commentary.runs == 4;
    final isSix = commentary.runs == 6;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50], // Light colored div box
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator (red dot with vertical line)
          SizedBox(
            width: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 8,
                    color: Colors.grey[300],
                  ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLatest 
                        ? const Color(0xFFDC2626) // Red for latest
                        : Colors.grey[400],
                    border: Border.all(
                      color: isLatest 
                          ? const Color(0xFFDC2626)
                          : Colors.grey[500]!,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 100, // Fixed height instead of Expanded
                    color: Colors.grey[300],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Ball number and runs indicator
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ball number circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[300]!, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    commentary.overDisplay,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Runs circle
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isBoundary 
                      ? const Color(0xFF2196F3) // Blue for boundaries
                      : isWicket
                          ? Colors.red
                          : Colors.white,
                  border: Border.all(
                    color: isBoundary 
                        ? const Color(0xFF2196F3)
                        : isWicket
                            ? Colors.red
                            : Colors.grey[300]!,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    isWicket ? 'W' : commentary.runs.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isBoundary || isWicket ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Commentary text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  commentary.commentaryText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: isLatest || isWicket || isBoundary 
                        ? FontWeight.w600 
                        : FontWeight.w400,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                // Player names
                Text(
                  '${commentary.strikerName} • ${commentary.bowlerName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 600.ms, curve: Curves.easeOut)
      .slideX(begin: 0.2, end: 0, duration: 600.ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.easeOut);
  }
}

/// Innings Break Card - Clear visible marker between innings
class InningsBreakCard extends StatelessWidget {
  const InningsBreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.15),
            AppColors.primary.withOpacity(0.08),
            AppColors.primary.withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sports_cricket,
              color: AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'INNINGS BREAK',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 600.ms)
      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.elasticOut)
      .shimmer(delay: 400.ms, duration: 1500.ms, color: AppColors.primary.withOpacity(0.3));
  }
}

/// New Batsman Card
class NewBatsmanCard extends StatelessWidget {
  final String batsmanName;
  final bool isLatest;

  const NewBatsmanCard({
    super.key,
    required this.batsmanName,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50], // Light colored div box
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_add_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'New batsman: $batsmanName',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textMain,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 600.ms, curve: Curves.easeOut)
      .slideX(begin: 0.2, end: 0, duration: 600.ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.easeOut);
  }
}


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

class CommentaryPage extends ConsumerStatefulWidget {
  final String matchId;
  final bool showAppBar;
  final String? matchStatus; // 'upcoming', 'live', 'completed'

  const CommentaryPage({
    super.key,
    required this.matchId,
    this.showAppBar = false,
    this.matchStatus,
  });

  @override
  ConsumerState<CommentaryPage> createState() => _CommentaryPageState();
}

class _CommentaryPageState extends ConsumerState<CommentaryPage> with SingleTickerProviderStateMixin {
  bool _isInnings1Expanded = false;
  bool _isInnings2Expanded = true;
  bool _hasInitializedExpansion = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _refreshTimer;
  int _previousCommentaryCount = 0;
  String? _fetchedMatchStatus;
  
  @override
  void initState() {
    super.initState();
    // Fetch match status if not provided
    if (widget.matchStatus == null) {
      _fetchMatchStatus();
    }
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
        final inn1Grouped = _groupCommentaryWithSummaries(inningsData['inn1']!);
        final inn2Grouped = _groupCommentaryWithSummaries(inningsData['inn2']!);

        // Initialize expansion state once we have data
        if (!_hasInitializedExpansion) {
          if (inn2Grouped.isNotEmpty) {
            _isInnings1Expanded = false;
            _isInnings2Expanded = true;
          } else {
            _isInnings1Expanded = true;
            _isInnings2Expanded = false;
          }
          _hasInitializedExpansion = true;
        }

        if (widget.showAppBar) {
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (inn2Grouped.isNotEmpty) ...[
                _buildInningsHeader(
                  title: 'Second Innings',
                  isExpanded: _isInnings2Expanded,
                  onTap: () => setState(() => _isInnings2Expanded = !_isInnings2Expanded),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
                if (_isInnings2Expanded) ...[
                  // Add innings break at the start of second innings
                  const InningsBreakCard()
                    .animate()
                    .fadeIn(delay: 50.ms, duration: 500.ms)
                    .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
                  ...inn2Grouped.asMap().entries.map((entry) => 
                    _buildCommentaryItem(entry.value, entry.key == 0)
                      .animate()
                      .fadeIn(delay: ((entry.key + 1) * 50).ms, duration: 500.ms)
                      .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
                      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), delay: ((entry.key + 1) * 50).ms, duration: 500.ms, curve: Curves.easeOutCubic)
                  ),
                ],
                const SizedBox(height: 16),
              ],
              _buildInningsHeader(
                title: 'First Innings',
                isExpanded: _isInnings1Expanded,
                onTap: () => setState(() => _isInnings1Expanded = !_isInnings1Expanded),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0),
              if (_isInnings1Expanded)
                ...inn1Grouped.asMap().entries.map((entry) => 
                  _buildCommentaryItem(entry.value, entry.key == 0 && inn2Grouped.isEmpty)
                    .animate()
                    .fadeIn(delay: (entry.key * 50).ms, duration: 500.ms)
                    .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
                    .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), delay: (entry.key * 50).ms, duration: 500.ms, curve: Curves.easeOutCubic)
                ),
            ],
          );
        }

        // Inline view (e.g. in tabs) - show all grouped (latest first)
        var allGrouped = _groupCommentaryWithSummaries(sortedList);
        
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: allGrouped.length,
          itemBuilder: (context, index) => _buildCommentaryItem(allGrouped[index], index == 0)
            .animate()
            .fadeIn(delay: (index * 40).ms, duration: 500.ms)
            .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
            .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), delay: (index * 40).ms, duration: 500.ms, curve: Curves.easeOutCubic),
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
        ),
        body: content,
      );
    }
    return content;
  }

  Widget _buildInningsHeader({required String title, required bool isExpanded, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isExpanded 
                ? [AppColors.primary, AppColors.primary.withOpacity(0.8)]
                : [AppColors.surface, AppColors.elevated],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded 
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.borderLight,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isExpanded 
                  ? AppColors.primary.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 24,
              decoration: BoxDecoration(
                color: isExpanded ? Colors.white : AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isExpanded ? Colors.white : AppColors.textMain,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isExpanded 
                    ? Colors.white.withOpacity(0.2)
                    : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: isExpanded ? Colors.white : AppColors.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentaryItem(Map<String, dynamic> item, bool isLatest) {
    // Use provided status or fetched status
    final matchStatus = widget.matchStatus ?? _fetchedMatchStatus;
    final isMatchLive = matchStatus == 'live';
    final shouldShowLatest = isLatest && isMatchLive; // Only show latest indicator for live matches
    
    if (item['type'] == 'overSummary') {
      return OverSummaryCard(
        summaryText: item['text'] as String,
        isLatest: shouldShowLatest,
      );
    } else if (item['type'] == 'inningsBreak') {
      return const InningsBreakCard();
    } else {
      final commentary = item['commentary'] as CommentaryModel;
      if (commentary.ballType == 'newBatsman') {
        return NewBatsmanCard(
          batsmanName: commentary.strikerName,
          isLatest: shouldShowLatest,
        );
      }
      return CommentaryCard(
        commentary: commentary,
        isLatest: shouldShowLatest,
      );
    }
  }

  Map<String, List<CommentaryModel>> _splitCommentaryByInnings(List<CommentaryModel> list) {
    final List<CommentaryModel> inn1 = [];
    final List<CommentaryModel> inn2 = [];
    
    double? lastOver = -1.0;
    bool inInnings2 = false;

    for (final item in list) {
      if (lastOver != -1.0 && item.over < lastOver!) {
        inInnings2 = true;
      }
      
      if (inInnings2) {
        inn2.add(item);
      } else {
        inn1.add(item);
      }
      lastOver = item.over;
    }
    
    return {'inn1': inn1, 'inn2': inn2};
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_cricket_outlined,
            size: 80,
            color: AppColors.textMeta.withOpacity(0.5),
          )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(delay: 1000.ms, duration: 1500.ms, color: AppColors.primary.withOpacity(0.3))
            .then()
            .fadeIn(duration: 600.ms),
          const SizedBox(height: 24),
          Text(
            'No commentary yet',
            style: TextStyle(
              fontSize: 20,
              color: AppColors.textMain,
              fontWeight: FontWeight.bold,
            ),
          )
            .animate()
            .fadeIn(delay: 200.ms, duration: 400.ms)
            .slideY(begin: 0.2, end: 0),
          const SizedBox(height: 12),
          Text(
            'Commentary will appear as the match progresses',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSec,
            ),
            textAlign: TextAlign.center,
          )
            .animate()
            .fadeIn(delay: 400.ms, duration: 400.ms)
            .slideY(begin: 0.2, end: 0),
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

  /// Group commentary entries and insert over summaries and innings breaks
  List<Map<String, dynamic>> _groupCommentaryWithSummaries(List<CommentaryModel> commentaryList) {
    if (commentaryList.isEmpty) return [];
    
    final List<Map<String, dynamic>> grouped = [];
    final Map<int, Map<String, dynamic>> overSummaries = {};
    
    // First pass: collect over summaries
    for (final commentary in commentaryList) {
      if (commentary.ballType == 'overSummary') {
        final match = RegExp(r'OVER (\d+)').firstMatch(commentary.commentaryText);
        if (match != null) {
          final overNum = int.parse(match.group(1)!);
          overSummaries[overNum] = {
            'type': 'overSummary',
            'text': commentary.commentaryText,
            'over': overNum,
            'timestamp': commentary.timestamp,
          };
        }
      }
    }
    
    // Determine innings break point by finding where over resets significantly
    // An innings break occurs when we go from a high over (e.g., 20.6) to a low over (e.g., 0.1)
    // We'll detect this by checking if the over decreases by more than 5 (indicating new innings)
    int? currentOverInt = -1;
    double? lastOverDouble = -1.0;
    bool inningsBreakAdded = false;
    double? lastInningsOver = -1.0;
    
    for (final commentary in commentaryList) {
      if (commentary.ballType == 'overSummary') continue;
      
      final overNumInt = commentary.over.toInt();
      final currentOverDouble = commentary.over;
      
      // Detect innings break: if over decreases significantly (more than 5 overs difference)
      // This indicates we've moved from one innings to another
      if (lastOverDouble != -1.0 && currentOverDouble < lastOverDouble!) {
        final overDifference = lastOverDouble! - currentOverDouble;
        
        // Only add innings break if:
        // 1. The over difference is significant (more than 5 overs, indicating new innings)
        // 2. We haven't already added an innings break for this transition
        // 3. The last over was reasonably high (at least 5, indicating end of an innings)
        if (overDifference > 5.0 && !inningsBreakAdded && lastOverDouble! >= 5.0) {
          // Add over summary for previous over if exists
          if (currentOverInt != -1 && overSummaries.containsKey(currentOverInt)) {
            grouped.add(overSummaries[currentOverInt]!);
            overSummaries.remove(currentOverInt);
          }
          
          // Add innings break only once
          grouped.add({
            'type': 'inningsBreak', 
            'text': 'Innings Break',
            'timestamp': commentary.timestamp,
          });
          inningsBreakAdded = true;
          lastInningsOver = lastOverDouble;
          currentOverInt = -1;
        }
      } else {
        // Reset innings break flag when we're in a new innings
        if (lastInningsOver != -1.0 && currentOverDouble > lastInningsOver!) {
          inningsBreakAdded = false;
          lastInningsOver = -1.0;
        }
      }
      
      // Add over summary when moving to a new over
      if (currentOverInt != -1 && overNumInt != currentOverInt) {
        if (overSummaries.containsKey(currentOverInt)) {
          grouped.add(overSummaries[currentOverInt]!);
          overSummaries.remove(currentOverInt);
        }
      }
      
      // Add commentary entry
      grouped.add({
        'type': 'commentary',
        'commentary': commentary,
        'over': overNumInt,
      });
      
      currentOverInt = overNumInt;
      lastOverDouble = currentOverDouble;
    }
    
    // Add final over summary if exists
    if (currentOverInt != -1 && overSummaries.containsKey(currentOverInt)) {
      grouped.add(overSummaries[currentOverInt]!);
    }
    
    return grouped;
  }
}

class InningsBreakCard extends StatelessWidget {
  const InningsBreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative background with gradient
          Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.accent.withOpacity(0.05),
                  AppColors.primary.withOpacity(0.1),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
                width: 1.5,
              ),
            ),
          ),
          // Central badge with icon and text
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sports_cricket_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'INNINGS BREAK',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 600.ms)
      .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.elasticOut)
      .slideY(begin: -0.1, end: 0, duration: 600.ms)
      .shimmer(delay: 400.ms, duration: 1200.ms, color: AppColors.primary.withOpacity(0.3));
  }
}

/// New Batsman Card Widget
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withOpacity(0.15),
            AppColors.success.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
      ),
    )
      .animate()
      .fadeIn(duration: 500.ms)
      .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 500.ms);
  }
}

/// Over Summary Card Widget
class OverSummaryCard extends StatelessWidget {
  final String summaryText;
  final bool isLatest;

  const OverSummaryCard({
    super.key,
    required this.summaryText,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = summaryText.split('\n');
    // Clean up over title - remove extra spaces and format nicely
    final overTitle = lines.isNotEmpty ? lines[0].trim().replaceAll(RegExp(r'\s+'), ' ') : '';
    final ballRuns = lines.length > 1 ? lines[1].trim() : '';
    final summary = lines.length > 2 ? lines[2].trim() : '';
    final battingPair = lines.length > 3 ? lines[3].trim() : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLatest
              ? [AppColors.primary.withOpacity(0.15), AppColors.primary.withOpacity(0.08)]
              : [AppColors.accent.withOpacity(0.1), AppColors.accent.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLatest 
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.accent.withOpacity(0.3),
          width: isLatest ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLatest ? AppColors.primary : AppColors.accent).withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Over Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    overTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (isLatest) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.urgent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, size: 8, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // Ball Runs (6 legal ball outcomes)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Text(
                ballRuns,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                  letterSpacing: 2,
                  height: 1.3,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Summary (Runs | Wickets | Match Score)
            Text(
              summary,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMain,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            // Batting Pair Stats
            if (battingPair.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Text(
                  battingPair,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSec,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    )
      .animate()
      .fadeIn(duration: 600.ms)
      .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), curve: Curves.easeOutCubic)
      .slideY(begin: -0.1, end: 0, duration: 600.ms)
      .shimmer(delay: 300.ms, duration: 800.ms, color: AppColors.primary.withOpacity(0.3));
  }
}

class CommentaryCard extends StatelessWidget {
  final CommentaryModel commentary;
  final bool isLatest;

  const CommentaryCard({
    super.key,
    required this.commentary,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    final isWicket = commentary.ballType == 'wicket';
    final isBoundary = commentary.runs == 4 || commentary.runs == 6;
    final isFour = commentary.runs == 4;
    final isSix = commentary.runs == 6;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: isLatest 
            ? LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.08),
                  AppColors.primary.withOpacity(0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : isWicket 
                ? LinearGradient(
                    colors: [
                      AppColors.urgent.withOpacity(0.12),
                      AppColors.urgent.withOpacity(0.05),
                    ],
                  )
                : isBoundary
                    ? LinearGradient(
                        colors: [
                          AppColors.accent.withOpacity(0.1),
                          AppColors.accent.withOpacity(0.05),
                        ],
                      )
                    : null,
        color: isLatest || isWicket || isBoundary ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLatest 
              ? AppColors.primary.withOpacity(0.4)
              : isWicket
                  ? AppColors.urgent.withOpacity(0.3)
                  : isBoundary
                      ? AppColors.accent.withOpacity(0.3)
                      : AppColors.borderLight,
          width: isLatest ? 2 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLatest 
                ? AppColors.primary
                : isWicket
                    ? AppColors.urgent
                    : isBoundary
                        ? AppColors.accent
                        : Colors.black).withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Over and Ball Type
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _getBallTypeGradient(commentary.ballType),
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _getBallTypeColor(commentary.ballType).withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    commentary.overDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (isLatest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.urgent, AppColors.urgent.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.urgent.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, size: 8, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08), duration: 800.ms, curve: Curves.easeInOut)
                    .then()
                    .scale(begin: const Offset(1.08, 1.08), end: const Offset(1, 1), duration: 800.ms, curve: Curves.easeInOut)
                    .shimmer(delay: 400.ms, duration: 1200.ms, color: Colors.white.withOpacity(0.5)),
                const Spacer(),
                if (commentary.isExtra)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.warning, AppColors.warning.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      commentary.extraType ?? 'EXTRA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isFour || isSix) ...[
                  const SizedBox(width: 8),
                  Icon(
                    isSix ? Icons.emoji_events : Icons.star,
                    color: isSix ? AppColors.warning : AppColors.accent,
                    size: 20,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Commentary Text
            Text(
              commentary.commentaryText,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textMain,
                fontWeight: isLatest || isWicket || isBoundary 
                    ? FontWeight.w600 
                    : FontWeight.w400,
                height: 1.5,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 12),
            // Runs and Players Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (commentary.runs > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _getRunsGradient(commentary.runs),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _getRunsColor(commentary.runs).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getRunsIcon(commentary.runs),
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${commentary.runs} run${commentary.runs > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (commentary.runs > 0) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${commentary.strikerName} • ${commentary.bowlerName}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSec,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Timestamp
                Text(
                  _formatTimestamp(commentary.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMeta,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    )
      .animate()
      .fadeIn(duration: 500.ms)
      .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 500.ms, curve: Curves.easeOutCubic)
      .then(delay: 200.ms)
      .shimmer(duration: 1000.ms, color: AppColors.primary.withOpacity(0.2));
  }

  List<Color> _getBallTypeGradient(String ballType) {
    switch (ballType) {
      case 'wicket':
        return [AppColors.urgent, AppColors.urgent.withOpacity(0.8)];
      case 'wide':
      case 'noBall':
        return [AppColors.warning, AppColors.warning.withOpacity(0.8)];
      default:
        return [AppColors.primary, AppColors.primary.withOpacity(0.8)];
    }
  }

  Color _getBallTypeColor(String ballType) {
    switch (ballType) {
      case 'wicket':
        return AppColors.urgent;
      case 'wide':
      case 'noBall':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  List<Color> _getRunsGradient(int runs) {
    if (runs == 6) return [AppColors.warning, AppColors.warning.withOpacity(0.8)];
    if (runs == 4) return [AppColors.accent, AppColors.accent.withOpacity(0.8)];
    if (runs >= 1) return [AppColors.success, AppColors.success.withOpacity(0.8)];
    return [AppColors.textMeta, AppColors.textMeta.withOpacity(0.8)];
  }

  Color _getRunsColor(int runs) {
    if (runs == 6) return AppColors.warning;
    if (runs == 4) return AppColors.accent;
    if (runs >= 1) return AppColors.success;
    return AppColors.textMeta;
  }

  IconData _getRunsIcon(int runs) {
    if (runs == 6) return Icons.emoji_events;
    if (runs == 4) return Icons.star;
    return Icons.directions_run;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatOverDisplay(String overDisplay) {
    // Clean up over display - ensure consistent formatting
    // e.g., "5.3" stays "5.3", "5.0" becomes "5"
    if (overDisplay.endsWith('.0')) {
      return overDisplay.replaceAll('.0', '');
    }
    return overDisplay;
  }
}

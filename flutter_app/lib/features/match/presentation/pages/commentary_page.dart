import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/commentary_model.dart';
import '../../../../core/repositories/commentary_repository.dart';
import '../../../../core/providers/repository_providers.dart';
import 'new_commentary_page.dart';

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
  final String? team1Name;
  final String? team2Name;

  const CommentaryPage({
    super.key,
    required this.matchId,
    this.showAppBar = false,
    this.matchStatus,
    this.team1Name,
    this.team2Name,
  });

  @override
  ConsumerState<CommentaryPage> createState() => _CommentaryPageState();
}

// Redirect to new commentary page
class _CommentaryPageState extends ConsumerState<CommentaryPage> {
  @override
  Widget build(BuildContext context) {
    return NewCommentaryPage(
      matchId: widget.matchId,
      showAppBar: widget.showAppBar,
      matchStatus: widget.matchStatus,
      team1Name: widget.team1Name,
      team2Name: widget.team2Name,
    );
  }
}

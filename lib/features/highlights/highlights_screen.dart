import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/highlight_repository.dart';

class HighlightsScreen extends ConsumerWidget {
  final String bookId;
  final ValueChanged<Highlight> onHighlightTap;

  const HighlightsScreen({
    super.key,
    required this.bookId,
    required this.onHighlightTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsStream = ref
        .watch(highlightRepoProvider)
        .getHighlightsForBook(bookId);
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return Scaffold(
      backgroundColor: readerTheme.pageBackground,
      appBar: AppBar(
        title: const Text('Highlights'),
        leading: const CloseButton(),
      ),
      body: StreamBuilder<List<Highlight>>(
        stream: highlightsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final highlights = snapshot.data ?? [];

          if (highlights.isEmpty) {
            return Center(
              child: Text(
                'No highlights yet.\nSelect text to create highlights.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: highlights.length,
            itemBuilder: (context, index) {
              final highlight = highlights[index];
              return Dismissible(
                key: Key(highlight.id),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  ref.read(highlightRepoProvider).deleteHighlight(highlight.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Highlight deleted')),
                  );
                },
                background: Container(
                  color: const Color(0xFFB3261E),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: _HighlightListItem(
                  highlight: highlight,
                  onTap: () {
                    onHighlightTap(highlight);
                  },
                  onDelete: () {
                    ref
                        .read(highlightRepoProvider)
                        .deleteHighlight(highlight.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HighlightListItem extends StatelessWidget {
  final Highlight highlight;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HighlightListItem({
    required this.highlight,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    final colorDot = _getColorWidget(highlight.color);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showOptionsSheet(context),
      child: Container(
        decoration: BoxDecoration(
          color: readerTheme.pageBackground,
          border: Border(bottom: BorderSide(color: readerTheme.divider)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: colorDot,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highlight.content.length > 80
                        ? '${highlight.content.substring(0, 80)}...'
                        : highlight.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chapter ${highlight.chapterIndex + 1} • ${_formatDate(highlight.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: readerTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getColorWidget(String color) {
    final colorMap = {
      'yellow': Colors.yellow[200] ?? Colors.yellow,
      'blue': const Color(0xFFBFD7FF),
      'pink': Colors.pink[100] ?? Colors.pink,
      'orange': const Color(0xFFF6D1A5),
    };
    final c = colorMap[color.toLowerCase()] ?? Colors.yellow;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: c,
        border: Border.all(color: Colors.grey[400]!, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  void _showOptionsSheet(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          color: readerTheme.chromeBackground,
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete highlight'),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

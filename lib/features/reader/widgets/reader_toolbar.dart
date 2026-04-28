import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/preferences.dart';

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class ReaderTopBar extends ConsumerWidget implements PreferredSizeWidget {
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback? onToc;
  final VoidCallback? onHighlights;
  final VoidCallback? onBookmarks;
  final VoidCallback? onToggleBookmark;
  final bool isBookmarked;

  const ReaderTopBar({
    super.key,
    required this.chapterTitle,
    required this.onBack,
    this.onToc,
    this.onHighlights,
    this.onBookmarks,
    this.onToggleBookmark,
    this.isBookmarked = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSizeAsync = ref.watch(sharedPreferencesProvider);

    return AppBar(
      backgroundColor:
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
        tooltip: 'Back',
      ),
      title: Text(
        chapterTitle,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        // Font size toggle (14, 17, 20)
        fontSizeAsync.when(
          data: (prefs) {
            final currentSize = prefs.getDouble('font_size') ?? 17.0;
            return PopupMenuButton<double>(
              initialValue: currentSize,
              icon: const Icon(Icons.text_fields),
              tooltip: 'Font size',
              onSelected: (size) async {
                await prefs.setDouble('font_size', size);
              },
              itemBuilder: (BuildContext context) {
                return const [
                  PopupMenuItem(value: 14.0, child: Text('Small (14)')),
                  PopupMenuItem(value: 17.0, child: Text('Medium (17)')),
                  PopupMenuItem(value: 20.0, child: Text('Large (20)')),
                ];
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (Object e, StackTrace st) => const SizedBox.shrink(),
        ),
        if (onToc != null)
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: onToc,
            tooltip: 'Table of contents',
          ),
        if (onHighlights != null)
          IconButton(
            icon: const Icon(Icons.highlight),
            onPressed: onHighlights,
            tooltip: 'Highlights',
          ),
        if (onBookmarks != null)
          IconButton(
            icon: const Icon(Icons.collections_bookmark_outlined),
            onPressed: onBookmarks,
            tooltip: 'Bookmarks',
          ),
        if (onToggleBookmark != null)
          IconButton(
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: isBookmarked ? Colors.amber : null,
            ),
            onPressed: onToggleBookmark,
            tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class ReaderBottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int chapterIndex;
  final int totalChapters;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.chapterIndex,
    required this.totalChapters,
    this.onPreviousChapter,
    this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final progressPercent =
        totalPages > 1 ? (currentPage + 1) / totalPages : 1.0;

    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thin progress bar across full width
            LinearProgressIndicator(
              value: progressPercent,
              minHeight: 2,
              backgroundColor: Colors.grey[300],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: onPreviousChapter,
                    tooltip: 'Previous chapter',
                    iconSize: 22,
                  ),
                  Text(
                    'Ch ${chapterIndex + 1}/$totalChapters  ·  ${currentPage + 1}/$totalPages',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: onNextChapter,
                    tooltip: 'Next chapter',
                    iconSize: 22,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

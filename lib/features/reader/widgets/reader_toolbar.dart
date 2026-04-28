import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class ReaderTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback? onToc; // Phase 4 — pass null to disable

  const ReaderTopBar({
    super.key,
    required this.chapterTitle,
    required this.onBack,
    this.onToc,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
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
        if (onToc != null)
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: onToc,
            tooltip: 'Table of contents',
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

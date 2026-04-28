import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class ReaderTopBar extends ConsumerWidget implements PreferredSizeWidget {
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback? onTypography;
  final ValueChanged<String>? onMenuAction;
  final VoidCallback? onToggleBookmark;
  final bool isBookmarked;

  const ReaderTopBar({
    super.key,
    required this.chapterTitle,
    required this.onBack,
    this.onTypography,
    this.onMenuAction,
    this.onToggleBookmark,
    this.isBookmarked = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final readerTheme = theme.extension<ReaderTheme>()!;
    final iconColor = readerTheme.pageText.withValues(alpha: 0.88);

    return Container(
      height: preferredSize.height,
      decoration: BoxDecoration(
        color: readerTheme.chromeBackground,
        border: Border(bottom: BorderSide(color: readerTheme.divider, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: iconColor, size: 20),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              chapterTitle,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: ReaderTypography.bookerly,
                fontFamilyFallback: ReaderTypography.serifFallbacks,
                fontSize: 16,
                color: readerTheme.pageText,
              ),
            ),
          ),
          if (onTypography != null)
            IconButton(
              icon: Icon(Icons.text_fields, color: iconColor, size: 20),
              onPressed: onTypography,
              tooltip: 'Typography',
            ),
          if (onToggleBookmark != null)
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: isBookmarked ? readerTheme.accent : iconColor,
                size: 20,
              ),
              onPressed: onToggleBookmark,
              tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
            ),
          if (onMenuAction != null)
            PopupMenuButton<String>(
              tooltip: 'Menu',
              onSelected: onMenuAction,
              icon: Icon(Icons.menu, color: iconColor, size: 20),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'contents', child: Text('Contents')),
                PopupMenuItem(value: 'highlights', child: Text('Notes & Highlights')),
                PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(AppDimensions.chromeTopHeight);
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class ReaderBottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int globalPage;
  final int globalTotalPages;
  final int chapterIndex;
  final int totalChapters;
  final ValueChanged<double>? onSeek;
  final String locationLabel;

  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.globalPage,
    required this.globalTotalPages,
    required this.chapterIndex,
    required this.totalChapters,
    required this.locationLabel,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readerTheme = theme.extension<ReaderTheme>()!;

    return Container(
      decoration: BoxDecoration(
        color: readerTheme.chromeBackground,
        border: Border(top: BorderSide(color: readerTheme.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: AppDimensions.progressHeight,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: readerTheme.accent,
              inactiveTrackColor: readerTheme.divider,
              thumbColor: readerTheme.accent,
            ),
            child: Slider(
              value: totalPages > 1 ? currentPage.toDouble() : 0,
              min: 0,
              max: totalPages > 1 ? (totalPages - 1).toDouble() : 1,
              onChanged: onSeek,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              locationLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: readerTheme.secondaryText,
                fontSize: AppFontSizes.secondaryLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReaderStatusStrip extends StatelessWidget {
  final String text;

  const ReaderStatusStrip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    return Container(
      height: readerTheme.statusStripHeight,
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: AppFontSizes.status,
              color: readerTheme.secondaryText,
            ),
      ),
    );
  }
}

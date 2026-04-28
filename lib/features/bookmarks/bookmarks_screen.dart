import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/services/epub_service.dart';

class BookmarksScreen extends ConsumerWidget {
  final String bookId;
  final List<ChapterContent> chapters;

  /// Called with (chapterIndex, pageInChapter) when the user taps a bookmark.
  final void Function(int chapterIndex, int pageInChapter) onBookmarkTap;

  const BookmarksScreen({
    super.key,
    required this.bookId,
    required this.chapters,
    required this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(_bookmarksProvider(bookId));
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return Scaffold(
      backgroundColor: readerTheme.pageBackground,
      appBar: AppBar(
        title: const Text('Bookmarks'),
        leading: const CloseButton(),
      ),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: readerTheme.secondaryText),
                  const SizedBox(height: 12),
                  Text('No bookmarks yet', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Tap the bookmark icon while reading to save a page.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.bookmark, color: readerTheme.accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${bookmarks.length} bookmark${bookmarks.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: readerTheme.divider),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: bookmarks.length,
                  itemBuilder: (context, i) => _BookmarkTile(
                    bookmark: bookmarks[i],
                    chapterTitle: _chapterTitle(bookmarks[i].chapterIndex),
                    onTap: () => onBookmarkTap(
                        bookmarks[i].chapterIndex, bookmarks[i].pageInChapter),
                    onDelete: () => ref
                        .read(bookmarkRepoProvider)
                        .deleteBookmark(bookmarks[i].id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _chapterTitle(int idx) {
    if (idx < 0 || idx >= chapters.length) return 'Chapter ${idx + 1}';
    final t = chapters[idx].title;
    return t.isEmpty ? 'Chapter ${idx + 1}' : t;
  }
}

final _bookmarksProvider =
    StreamProvider.family<List<Bookmark>, String>((ref, bookId) {
  return ref.watch(bookmarkRepoProvider).getBookmarksForBook(bookId);
});

// ---------------------------------------------------------------------------

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final String chapterTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkTile({
    required this.bookmark,
    required this.chapterTitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFFB3261E),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: readerTheme.divider),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(Icons.bookmark, color: readerTheme.accent, size: 18),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.snippet.isEmpty ? chapterTitle : bookmark.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$chapterTitle · Page ${bookmark.pageInChapter + 1} · ${_formatDate(bookmark.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.chevron_right, color: readerTheme.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

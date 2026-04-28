import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final bookmarksAsync =
        ref.watch(_bookmarksProvider(bookId));

    return bookmarksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('No bookmarks yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 6),
                Text('Tap the bookmark icon while reading to save a page.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.bookmark, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text('${bookmarks.length} bookmark${bookmarks.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
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
    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.bookmark, color: Colors.amber, size: 28),
        title: Text(
          bookmark.snippet.isEmpty ? chapterTitle : bookmark.snippet,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$chapterTitle · Page ${bookmark.pageInChapter + 1} · ${_formatDate(bookmark.createdAt)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final bookmarkRepoProvider = Provider<BookmarkRepository>(
    (ref) => BookmarkRepository(ref.watch(databaseProvider)));

/// Watches whether a specific (bookId, chapter, page) is bookmarked.
final pageBookmarkedProvider =
    StreamProvider.family<bool, (String, int, int)>((ref, args) {
  final (bookId, chapterIndex, pageInChapter) = args;
  return ref
      .watch(bookmarkRepoProvider)
      .watchPageBookmarked(bookId, chapterIndex, pageInChapter);
});

class BookmarkRepository {
  final AppDatabase db;
  BookmarkRepository(this.db);

  Future<void> addBookmark(BookmarksCompanion bookmark) =>
      db.into(db.bookmarks).insert(bookmark, mode: InsertMode.insertOrReplace);

  Stream<List<Bookmark>> getBookmarksForBook(String bookId) {
    return (db.select(db.bookmarks)
          ..where((b) => b.bookId.equals(bookId))
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .watch();
  }

  Future<void> deleteBookmark(String id) =>
      (db.delete(db.bookmarks)..where((b) => b.id.equals(id))).go();

  Future<void> deleteBookmarkForPage(
      String bookId, int chapterIndex, int pageInChapter) {
    return (db.delete(db.bookmarks)
          ..where((b) =>
              b.bookId.equals(bookId) &
              b.chapterIndex.equals(chapterIndex) &
              b.pageInChapter.equals(pageInChapter)))
        .go();
  }

  Stream<bool> watchPageBookmarked(
      String bookId, int chapterIndex, int pageInChapter) {
    return (db.select(db.bookmarks)
          ..where((b) =>
              b.bookId.equals(bookId) &
              b.chapterIndex.equals(chapterIndex) &
              b.pageInChapter.equals(pageInChapter)))
        .watch()
        .map((rows) => rows.isNotEmpty);
  }

  Future<bool> isPageBookmarked(
      String bookId, int chapterIndex, int pageInChapter) async {
    final query = db.select(db.bookmarks)
      ..where((b) => b.bookId.equals(bookId))
      ..where((b) => b.chapterIndex.equals(chapterIndex))
      ..where((b) => b.pageInChapter.equals(pageInChapter));
    final count = await query.get();
    return count.isNotEmpty;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final bookmarkRepoProvider = Provider<BookmarkRepository>((ref) => BookmarkRepository(ref.watch(databaseProvider)));

class BookmarkRepository {
  final AppDatabase db;
  BookmarkRepository(this.db);

  Future<void> addBookmark(BookmarksCompanion bookmark) => db.into(db.bookmarks).insert(bookmark);

  Stream<List<Bookmark>> getBookmarksForBook(String bookId) {
    return (db.select(db.bookmarks)..where((b) => b.bookId.equals(bookId))).watch();
  }

  Future<void> deleteBookmark(String id) => (db.delete(db.bookmarks)..where((b) => b.id.equals(id))).go();

  Future<bool> isPageBookmarked(String bookId, int chapterIndex, int pageInChapter) async {
    final query = db.select(db.bookmarks)
      ..where((b) => b.bookId.equals(bookId))
      ..where((b) => b.chapterIndex.equals(chapterIndex))
      ..where((b) => b.pageInChapter.equals(pageInChapter));
    final count = await query.get();
    return count.isNotEmpty;
  }
}

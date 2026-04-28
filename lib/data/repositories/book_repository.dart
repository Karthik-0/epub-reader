import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final bookRepoProvider = Provider<BookRepository>((ref) => BookRepository(ref.watch(databaseProvider)));

class BookRepository {
  final AppDatabase db;
  BookRepository(this.db);

  Future<void> addBook(BooksCompanion book) => db.into(db.books).insert(book);
  
  Stream<List<Book>> getAllBooks() => db.select(db.books).watch();
  
  Future<Book> getBookById(String id) => (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
  
  Future<void> updateLastPosition(String bookId, int chapterIndex, int pageInChapter, double progressPercent) {
    return (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        lastChapterIndex: Value(chapterIndex),
        lastPageInChapter: Value(pageInChapter),
        progressPercent: Value(progressPercent),
        lastOpenedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteBook(String id) => (db.delete(db.books)..where((b) => b.id.equals(id))).go();
}

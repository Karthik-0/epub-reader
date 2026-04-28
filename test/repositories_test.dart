import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:epub_reader_poc/data/db/database.dart';
import 'package:epub_reader_poc/data/repositories/book_repository.dart';
import 'package:epub_reader_poc/data/repositories/highlight_repository.dart';
import 'package:epub_reader_poc/data/repositories/bookmark_repository.dart';
import 'package:drift/drift.dart';

void main() {
  late AppDatabase database;
  late BookRepository bookRepo;
  late HighlightRepository highlightRepo;
  late BookmarkRepository bookmarkRepo;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    bookRepo = BookRepository(database);
    highlightRepo = HighlightRepository(database);
    bookmarkRepo = BookmarkRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('BookRepository - add and get book', () async {
    final book = BooksCompanion(
      id: const Value('book1'),
      title: const Value('Test Book'),
      filePath: const Value('/path/to/book.epub'),
      addedAt: Value(DateTime.now()),
    );
    await bookRepo.addBook(book);

    final fetchedBook = await bookRepo.getBookById('book1');
    expect(fetchedBook.title, 'Test Book');
  });

  test('HighlightRepository - add and get highlights', () async {
    final book = BooksCompanion(
      id: const Value('book1'),
      title: const Value('Test Book'),
      filePath: const Value('/path/to/book.epub'),
      addedAt: Value(DateTime.now()),
    );
    await bookRepo.addBook(book);

    final highlight = HighlightsCompanion(
      id: const Value('highlight1'),
      bookId: const Value('book1'),
      chapterIndex: const Value(0),
      startOffset: const Value(10),
      endOffset: const Value(20),
      content: const Value('highlighted text'),
      color: const Value('yellow'),
      createdAt: Value(DateTime.now()),
    );
    await highlightRepo.addHighlight(highlight);

    final highlights = await highlightRepo.getHighlightsForChapter('book1', 0);
    expect(highlights.length, 1);
    expect(highlights.first.content, 'highlighted text');
  });

  test('BookmarkRepository - add and check bookmark', () async {
    final book = BooksCompanion(
      id: const Value('book1'),
      title: const Value('Test Book'),
      filePath: const Value('/path/to/book.epub'),
      addedAt: Value(DateTime.now()),
    );
    await bookRepo.addBook(book);

    final bookmark = BookmarksCompanion(
      id: const Value('bookmark1'),
      bookId: const Value('book1'),
      chapterIndex: const Value(0),
      pageInChapter: const Value(1),
      snippet: const Value('bookmark snippet'),
      createdAt: Value(DateTime.now()),
    );
    await bookmarkRepo.addBookmark(bookmark);

    final isBookmarked = await bookmarkRepo.isPageBookmarked('book1', 0, 1);
    expect(isBookmarked, true);
  });
}

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final highlightRepoProvider = Provider<HighlightRepository>((ref) => HighlightRepository(ref.watch(databaseProvider)));

/// Provider for watching highlights for a specific chapter (bookId, chapterIndex)
final chapterHighlightsProvider = StreamProvider.family<List<Highlight>, (String, int)>((ref, args) {
  final (bookId, chapterIndex) = args;
  return ref.watch(highlightRepoProvider).watchHighlightsForChapter(bookId, chapterIndex);
});

class HighlightRepository {
  final AppDatabase db;
  HighlightRepository(this.db);

  Future<void> addHighlight(HighlightsCompanion highlight) => db.into(db.highlights).insert(highlight);

  Stream<List<Highlight>> getHighlightsForBook(String bookId) {
    return (db.select(db.highlights)..where((h) => h.bookId.equals(bookId))).watch();
  }

  Stream<List<Highlight>> watchHighlightsForChapter(String bookId, int chapterIndex) {
    return (db.select(db.highlights)
          ..where((h) => h.bookId.equals(bookId))
          ..where((h) => h.chapterIndex.equals(chapterIndex)))
        .watch();
  }

  Future<List<Highlight>> getHighlightsForChapter(String bookId, int chapterIndex) {
    return (db.select(db.highlights)
      ..where((h) => h.bookId.equals(bookId))
      ..where((h) => h.chapterIndex.equals(chapterIndex))
    ).get();
  }

  Future<void> deleteHighlight(String id) => (db.delete(db.highlights)..where((h) => h.id.equals(id))).go();

  Future<void> updateHighlightColor(String id, String color) {
    return (db.update(db.highlights)..where((h) => h.id.equals(id)))
        .write(HighlightsCompanion(color: Value(color)));
  }
}

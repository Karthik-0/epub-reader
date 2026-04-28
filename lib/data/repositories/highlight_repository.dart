import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final highlightRepoProvider = Provider<HighlightRepository>((ref) => HighlightRepository(ref.watch(databaseProvider)));

class HighlightRepository {
  final AppDatabase db;
  HighlightRepository(this.db);

  Future<void> addHighlight(HighlightsCompanion highlight) => db.into(db.highlights).insert(highlight);
  
  Stream<List<Highlight>> getHighlightsForBook(String bookId) {
    return (db.select(db.highlights)..where((h) => h.bookId.equals(bookId))).watch();
  }

  Future<List<Highlight>> getHighlightsForChapter(String bookId, int chapterIndex) {
    return (db.select(db.highlights)
      ..where((h) => h.bookId.equals(bookId))
      ..where((h) => h.chapterIndex.equals(chapterIndex))
    ).get();
  }

  Future<void> deleteHighlight(String id) => (db.delete(db.highlights)..where((h) => h.id.equals(id))).go();
}

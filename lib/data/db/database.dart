import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()();                          // uuid
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverPath => text().nullable()();        // path inside app dir
  TextColumn get filePath => text()();                    // path to .epub copy
  IntColumn get lastChapterIndex => integer().withDefault(const Constant(0))();
  IntColumn get lastPageInChapter => integer().withDefault(const Constant(0))();
  RealColumn get progressPercent => real().withDefault(const Constant(0.0))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get startOffset => integer()();               // char offset in plain text
  IntColumn get endOffset => integer()();
  TextColumn get content => text()();                        // the highlighted text itself
  TextColumn get color => text()();                       // 'yellow' | 'green' | 'pink'
  RealColumn get progressPercent => real().nullable()();
  TextColumn get locatorJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get pageInChapter => integer()();
  TextColumn get snippet => text()();                     // first ~80 chars of page
  RealColumn get progressPercent => real().nullable()();
  TextColumn get locatorJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Books, Highlights, Bookmarks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'epub_reader'));

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement(
          'ALTER TABLE highlights ADD COLUMN progress_percent REAL NULL',
        );
        await customStatement(
          'ALTER TABLE highlights ADD COLUMN locator_json TEXT NULL',
        );
        await customStatement(
          'ALTER TABLE bookmarks ADD COLUMN progress_percent REAL NULL',
        );
        await customStatement(
          'ALTER TABLE bookmarks ADD COLUMN locator_json TEXT NULL',
        );
      }
    },
  );
}

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

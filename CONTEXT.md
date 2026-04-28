# Flutter EPUB Reader POC — AI Handoff Context

**Date:** 2026-04-28 | **Last commit:** `fbfe5f2` | **Branch:** `main`  
**Project root:** `/Users/karthik/workspace/reader`  
**Flutter:** 3.24+ | **Dart:** stable | **Platform target:** Android (API 24+) + iOS 13+

---

## STATUS: Phases 0–7 complete. Phase 8 (Deliverables) is next.

### Git log (recent)
```
fbfe5f2  Phase 7: dark mode toggle, context-aware HTML styles, animated page transitions, release APK
3b48974  Phase 6: bookmarks — toggle icon, ribbon overlay, BookmarksScreen, swipe-to-delete
e7b7450  Fix: proper selection toolbar (AdaptiveTextSelectionToolbar) + TapGestureRecognizer
8792700  Phase 5: tappable highlights — DOM injection, mark extension, delete/change-color
b73c9f9  Fix: move SelectionArea inside PageView itemBuilder
5a073c4  Phase 5: highlights — SelectionArea, color picker, HighlightsScreen
46117d3  Phase 4: font size toggle (14/17/20), TOC screen
a297d58  Fix: check EPUB file exists before reading
b9666a5  Fix: handle missing cover files gracefully
c627caa  Phase 3: reader core — pagination, position persistence, tap/swipe navigation
```

---

## Tech Stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.24+ |
| State | Riverpod 2.x (`StateNotifierProvider`, `StreamProvider`, `AsyncNotifier`) |
| EPUB parsing | `epubx: ^4.0.0` |
| HTML rendering | `flutter_html: ^3.0.0-beta.2` |
| DB | `drift: ^2.18.0` + `drift_flutter: ^0.2.0` |
| File picker | `file_picker: ^8.x` |
| Preferences | `shared_preferences` (font size, dark mode) |
| Storage | `path_provider: ^2.x` + `path: ^1.9.0` |

---

## File Tree

```
lib/
├── main.dart                               # ProviderScope → MyApp
├── app.dart                                # MaterialApp, watches themeModeProvider
├── core/
│   ├── constants.dart                      # AppColors, AppFontSizes, AppDimensions
│   ├── preferences.dart                    # sharedPreferencesProvider, ThemeModeNotifier, themeModeProvider
│   └── theme.dart                          # AppTheme.lightTheme / darkTheme
├── data/
│   ├── db/
│   │   ├── database.dart                   # Drift tables: Books, Highlights, Bookmarks; databaseProvider
│   │   └── database.g.dart                 # generated (do not edit)
│   ├── repositories/
│   │   ├── book_repository.dart            # bookRepoProvider, BookRepository
│   │   ├── highlight_repository.dart       # highlightRepoProvider, chapterHighlightsProvider
│   │   └── bookmark_repository.dart        # bookmarkRepoProvider, pageBookmarkedProvider
│   └── services/
│       ├── epub_service.dart               # epubServiceProvider, EpubService, ParsedBook, ChapterContent, TocEntry
│       └── highlight_service.dart          # HighlightService.injectHighlights, extractPlainText, colorToHex
├── features/
│   ├── library/
│   │   ├── library_screen.dart             # LibraryScreen (GridView + FAB import)
│   │   ├── library_controller.dart         # libraryStreamProvider
│   │   └── widgets/book_tile.dart          # BookTile (tap→reader, long-press→delete)
│   ├── reader/
│   │   ├── reader_screen.dart              # ReaderScreen (main reading UI)
│   │   ├── reader_controller.dart          # ReaderState, ReaderController, readerControllerProvider
│   │   ├── pagination_engine.dart          # PaginationEngine, HtmlHeightMeasurer
│   │   └── widgets/
│   │       ├── page_view_widget.dart       # ChapterPageWidget (clipped/translated HTML page)
│   │       ├── reader_toolbar.dart         # ReaderTopBar, ReaderBottomBar
│   │       └── highlight_toolbar.dart      # HighlightToolbar (legacy, not used in main flow)
│   ├── highlights/
│   │   └── highlights_screen.dart          # HighlightsScreen (list + swipe-delete)
│   ├── bookmarks/
│   │   └── bookmarks_screen.dart           # BookmarksScreen (list + swipe-delete)
│   └── toc/
│       └── toc_screen.dart                 # TocScreen (chapter list)
```

---

## Key Architecture Patterns

### Pagination
- `HtmlHeightMeasurer` renders chapter HTML offscreen (via `Offstage`) to measure total height.
- `PaginationEngine.computePageCount(totalHeight, pageHeight)` → page count.
- `ChapterPageWidget` clips+translates the full rendered HTML to show page slice: `offset = -(pageIndex * pageHeight)`.
- `PageView.builder` with `SelectionArea` per item (each page has its own selection context — prevents index assertion crash).

### Highlights
- Stored as `(bookId, chapterIndex, startOffset=0, endOffset=text.length, content, color)`.
- Injected into HTML via `HighlightService.injectHighlights` which wraps matching plain-text in `<mark data-highlight-id="..." data-color="...">`.
- Rendered via `TagExtension.inline` in `ChapterPageWidget` using `TextSpan` + `TapGestureRecognizer` (NOT `GestureDetector` — swallowed by SelectionArea).
- Tap on highlight → bottom sheet: delete or change color.

### Bookmarks
- Keyed by `(bookId, chapterIndex, pageInChapter)`.
- `pageBookmarkedProvider` is a `StreamProvider.family<bool, (String, int, int)>`.
- Toggle: `isPageBookmarked` check → `deleteBookmarkForPage` or `addBookmark(InsertMode.insertOrReplace)`.
- Visual: amber bookmark icon in toolbar + `_BookmarkRibbon` (CustomPainter) on page top-right.

### Dark mode
- `ThemeModeNotifier extends AsyncNotifier<ThemeMode>` in `preferences.dart`.
- Persisted as `bool` in SharedPreferences key `'dark_mode'`.
- `themeModeProvider` watched in `app.dart` → `MaterialApp.themeMode`.
- Toggle button in `ReaderTopBar` (sun/moon icon).
- `ChapterPageWidget` reads `Theme.of(context).brightness` for text/code colors.

### Position persistence
- Debounced 500ms timer in `ReaderController._scheduleSave()`.
- Saves `(chapterIndex, currentPage, progressPercent)` to `Books` row.
- On open: `_pendingSavedPage` holds restored page, applied after first measurement.

---

## Drift Schema

```dart
// Books
id TEXT PK, title TEXT, author TEXT?, coverPath TEXT?, filePath TEXT,
lastChapterIndex INT default 0, lastPageInChapter INT default 0,
progressPercent REAL default 0.0, addedAt DATETIME, lastOpenedAt DATETIME?

// Highlights
id TEXT PK, bookId TEXT→Books, chapterIndex INT,
startOffset INT, endOffset INT, content TEXT, color TEXT, createdAt DATETIME

// Bookmarks
id TEXT PK, bookId TEXT→Books, chapterIndex INT,
pageInChapter INT, snippet TEXT, createdAt DATETIME

schemaVersion = 1
```

---

## Provider Map

```dart
databaseProvider           Provider<AppDatabase>
bookRepoProvider           Provider<BookRepository>
highlightRepoProvider      Provider<HighlightRepository>
bookmarkRepoProvider       Provider<BookmarkRepository>
epubServiceProvider        Provider<EpubService>
sharedPreferencesProvider  FutureProvider<SharedPreferences>
themeModeProvider          AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>
libraryStreamProvider      StreamProvider<List<Book>>
readerControllerProvider   StateNotifierProvider.family<ReaderController, ReaderState, String>
chapterHighlightsProvider  StreamProvider.family<List<Highlight>, (String, int)>
pageBookmarkedProvider     StreamProvider.family<bool, (String, int, int)>
```

---

## Phase 8 — Deliverables (NEXT — not started)

```
- [ ] Write README.md: setup, build commands, known limitations
- [ ] Write DECISIONS.md: pagination approach, position-tracking trade-off,
      EPUB edge cases encountered, what to change for V1
- [ ] Record 2-minute demo video: import→read→highlight→bookmark→close→reopen
- [ ] git commit, git tag poc-v1
```

### README.md should cover
- `flutter pub get` then `flutter run`
- Build: `flutter build apk --release` (APK already at `build/app/outputs/flutter-apk/app-release.apk`, 62 MB)
- iOS: `flutter build ios --release` (requires Mac with Xcode)
- Known limitations: pagination is scroll-as-pages approximation (not true reflow), highlight offset is char-count based (startOffset always 0 for now), TOC fragment hrefs not fully resolved

### DECISIONS.md key points to write up
- Pagination: offscreen measure + clip/translate vs true reflow. Trade-off: fast, simple, but page breaks can split mid-word.
- Position tracking: `(chapterIndex, pageInChapter)` not CFI. Robust to font-size change via remeasure.
- Highlights: Option A (pre-process HTML, inject `<mark>`) not Option B (HtmlExtension per char offset). Works for most cases; fails if same text appears multiple times in chapter.
- SelectionArea must be per-page (inside PageView itemBuilder), not wrapping the whole PageView — avoids index assertion crash.
- `TapGestureRecognizer` inside `TextSpan` (not `GestureDetector`) for highlight taps inside SelectionArea.
- EPUB cover: EPUB2 `<meta name="cover">` → EPUB3 `properties="cover-image"` → filename heuristic fallback.

---

## Source Code Snapshot

### lib/main.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
void main() { runApp(const ProviderScope(child: MyApp())); }
```

### lib/app.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/preferences.dart';
import 'core/theme.dart';
import 'features/library/library_screen.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    return MaterialApp(
      title: 'EPUB Reader POC',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const LibraryScreen(),
    );
  }
}
```

### lib/core/constants.dart
```dart
import 'package:flutter/material.dart';
class AppColors {
  static const Color readingBackground = Color(0xFFFBF6E9);
  static const Color readingText = Color(0xFF2A2A2A);
  static const Color readingBackgroundDark = Color(0xFF1A1A1A);
  static const Color readingTextDark = Color(0xFFD8D4CC);
  static const Color highlightYellow = Color(0xFFFFF59D);
  static const Color highlightGreen = Color(0xFFC5E1A5);
  static const Color highlightPink = Color(0xFFF8BBD0);
}
class AppFontSizes { static const double small=14.0, medium=17.0, large=20.0; }
class AppDimensions { static const double pageHorizontalPadding=16.0, pageVerticalPadding=16.0; }
```

### lib/core/preferences.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async =>
    SharedPreferences.getInstance());

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  static const _key = 'dark_mode';
  @override
  Future<ThemeMode> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final saved = prefs.getBool(_key);
    if (saved == null) return ThemeMode.system;
    return saved ? ThemeMode.dark : ThemeMode.light;
  }
  Future<void> toggle() async {
    final current = state.valueOrNull ?? ThemeMode.system;
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_key, next == ThemeMode.dark);
    state = AsyncData(next);
  }
}
final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
```

### lib/data/db/database.dart (schema only)
```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get filePath => text()();
  IntColumn get lastChapterIndex => integer().withDefault(const Constant(0))();
  IntColumn get lastPageInChapter => integer().withDefault(const Constant(0))();
  RealColumn get progressPercent => real().withDefault(const Constant(0.0))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();
  TextColumn get content => text()();
  TextColumn get color => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get pageInChapter => integer()();
  TextColumn get snippet => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}
@DriftDatabase(tables: [Books, Highlights, Bookmarks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'epub_reader'));
  AppDatabase.forTesting(super.e);
  @override int get schemaVersion => 1;
}
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
```

### lib/data/repositories/bookmark_repository.dart
```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final bookmarkRepoProvider = Provider<BookmarkRepository>(
    (ref) => BookmarkRepository(ref.watch(databaseProvider)));

final pageBookmarkedProvider =
    StreamProvider.family<bool, (String, int, int)>((ref, args) {
  final (bookId, chapterIndex, pageInChapter) = args;
  return ref.watch(bookmarkRepoProvider).watchPageBookmarked(bookId, chapterIndex, pageInChapter);
});

class BookmarkRepository {
  final AppDatabase db;
  BookmarkRepository(this.db);
  Future<void> addBookmark(BookmarksCompanion bookmark) =>
      db.into(db.bookmarks).insert(bookmark, mode: InsertMode.insertOrReplace);
  Stream<List<Bookmark>> getBookmarksForBook(String bookId) =>
      (db.select(db.bookmarks)
        ..where((b) => b.bookId.equals(bookId))
        ..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).watch();
  Future<void> deleteBookmark(String id) =>
      (db.delete(db.bookmarks)..where((b) => b.id.equals(id))).go();
  Future<void> deleteBookmarkForPage(String bookId, int chapterIndex, int pageInChapter) =>
      (db.delete(db.bookmarks)..where((b) =>
          b.bookId.equals(bookId) & b.chapterIndex.equals(chapterIndex) &
          b.pageInChapter.equals(pageInChapter))).go();
  Stream<bool> watchPageBookmarked(String bookId, int chapterIndex, int pageInChapter) =>
      (db.select(db.bookmarks)..where((b) =>
          b.bookId.equals(bookId) & b.chapterIndex.equals(chapterIndex) &
          b.pageInChapter.equals(pageInChapter))).watch().map((rows) => rows.isNotEmpty);
  Future<bool> isPageBookmarked(String bookId, int chapterIndex, int pageInChapter) async {
    final rows = await (db.select(db.bookmarks)..where((b) =>
        b.bookId.equals(bookId) & b.chapterIndex.equals(chapterIndex) &
        b.pageInChapter.equals(pageInChapter))).get();
    return rows.isNotEmpty;
  }
}
```

### lib/data/repositories/highlight_repository.dart
```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final highlightRepoProvider = Provider<HighlightRepository>(
    (ref) => HighlightRepository(ref.watch(databaseProvider)));

final chapterHighlightsProvider =
    StreamProvider.family<List<Highlight>, (String, int)>((ref, args) {
  final (bookId, chapterIndex) = args;
  return ref.watch(highlightRepoProvider).watchHighlightsForChapter(bookId, chapterIndex);
});

class HighlightRepository {
  final AppDatabase db;
  HighlightRepository(this.db);
  Future<void> addHighlight(HighlightsCompanion h) => db.into(db.highlights).insert(h);
  Stream<List<Highlight>> getHighlightsForBook(String bookId) =>
      (db.select(db.highlights)..where((h) => h.bookId.equals(bookId))).watch();
  Stream<List<Highlight>> watchHighlightsForChapter(String bookId, int chapterIndex) =>
      (db.select(db.highlights)
        ..where((h) => h.bookId.equals(bookId))
        ..where((h) => h.chapterIndex.equals(chapterIndex))).watch();
  Future<void> deleteHighlight(String id) =>
      (db.delete(db.highlights)..where((h) => h.id.equals(id))).go();
  Future<void> updateHighlightColor(String id, String color) =>
      (db.update(db.highlights)..where((h) => h.id.equals(id)))
          .write(HighlightsCompanion(color: Value(color)));
}
```

### lib/features/reader/reader_controller.dart
```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/services/epub_service.dart';

class ReaderState {
  final AsyncValue<ParsedBook> bookAsync;
  final int chapterIndex, currentPage, totalPages;
  final bool showToolbars, pendingLastPage;
  const ReaderState({
    this.bookAsync = const AsyncValue.loading(),
    this.chapterIndex = 0, this.currentPage = 0, this.totalPages = 1,
    this.showToolbars = true, this.pendingLastPage = false,
  });
  ReaderState copyWith({AsyncValue<ParsedBook>? bookAsync, int? chapterIndex,
      int? currentPage, int? totalPages, bool? showToolbars, bool? pendingLastPage}) =>
      ReaderState(
        bookAsync: bookAsync ?? this.bookAsync,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        showToolbars: showToolbars ?? this.showToolbars,
        pendingLastPage: pendingLastPage ?? this.pendingLastPage,
      );
}

class ReaderController extends StateNotifier<ReaderState> {
  final Ref _ref;
  final String bookId;
  Timer? _saveTimer;
  int? _pendingSavedPage;

  ReaderController(this._ref, this.bookId) : super(const ReaderState()) { _load(); }

  Future<void> _load() async {
    try {
      final dbBook = await _ref.read(bookRepoProvider).getBookById(bookId);
      final parsedBook = await _ref.read(epubServiceProvider).reparseFromDisk(dbBook);
      _pendingSavedPage = dbBook.lastPageInChapter;
      state = state.copyWith(
        bookAsync: AsyncValue.data(parsedBook),
        chapterIndex: dbBook.lastChapterIndex, currentPage: 0);
    } catch (e, st) { state = state.copyWith(bookAsync: AsyncValue.error(e, st)); }
  }

  void onTotalPagesMeasured(int total) {
    int targetPage = 0;
    if (_pendingSavedPage != null) {
      targetPage = _pendingSavedPage!.clamp(0, total - 1);
      _pendingSavedPage = null;
    } else if (state.pendingLastPage) {
      targetPage = total - 1;
    } else {
      targetPage = state.currentPage.clamp(0, total - 1);
    }
    state = state.copyWith(totalPages: total, currentPage: targetPage, pendingLastPage: false);
  }

  void goToPage(int page) { if (page == state.currentPage) return; state = state.copyWith(currentPage: page); _scheduleSave(); }
  void goToChapter(int chapterIndex, {bool lastPage = false}) {
    state = state.copyWith(chapterIndex: chapterIndex, currentPage: 0, totalPages: 1, pendingLastPage: lastPage);
    _scheduleSave();
  }
  void nextPage() {
    final book = state.bookAsync.valueOrNull; if (book == null) return;
    if (state.currentPage < state.totalPages - 1) goToPage(state.currentPage + 1);
    else if (state.chapterIndex < book.chapters.length - 1) goToChapter(state.chapterIndex + 1);
  }
  void previousPage() {
    if (state.currentPage > 0) goToPage(state.currentPage - 1);
    else if (state.chapterIndex > 0) goToChapter(state.chapterIndex - 1, lastPage: true);
  }
  void toggleToolbars() => state = state.copyWith(showToolbars: !state.showToolbars);

  void _scheduleSave() { _saveTimer?.cancel(); _saveTimer = Timer(const Duration(milliseconds: 500), _savePosition); }
  Future<void> _savePosition() async {
    final book = state.bookAsync.valueOrNull; if (book == null) return;
    final totalChars = book.chapters.fold<int>(0, (s, ch) => s + ch.htmlContent.length);
    final charsRead = book.chapters.take(state.chapterIndex).fold<int>(0, (s, ch) => s + ch.htmlContent.length);
    final progress = totalChars > 0 ? (charsRead / totalChars) * 100.0 : 0.0;
    await _ref.read(bookRepoProvider).updateLastPosition(bookId, state.chapterIndex, state.currentPage, progress);
  }
  @override void dispose() { _saveTimer?.cancel(); _savePosition(); super.dispose(); }
}

final readerControllerProvider = StateNotifierProvider.family<ReaderController, ReaderState, String>(
    (ref, bookId) => ReaderController(ref, bookId));
```

### lib/features/reader/pagination_engine.dart (key parts)
```dart
// PaginationEngine.computePageCount(totalHeight, pageHeight) → ceil(total/page).clamp(1,100000)
// HtmlHeightMeasurer: StatefulWidget, renders HTML in Offstage with GlobalKey,
// fires onHeightMeasured(double) in addPostFrameCallback after layout.
// Key it with ValueKey('${chapterIdx}_${fontSize}_$measureWidth') for auto-remeasure.
```

### ChapterPageWidget render pattern (page_view_widget.dart)
```dart
// Clip + translate full HTML to show page slice:
ClipRect(
  child: SizedBox(height: pageHeight, width: pageWidth,
    child: OverflowBox(alignment: Alignment.topLeft, maxHeight: double.infinity, maxWidth: pageWidth,
      child: Transform.translate(
        offset: Offset(0, -(pageIndex * pageHeight)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),  // AppDimensions.pageHorizontalPadding
          child: Html(data: htmlContent, style: _buildStyle(...), extensions: [_buildMarkExtension(...)]),
        ),
      ),
    ),
  ),
)
// Mark extension: TagExtension.inline tagsToExtend: {'mark'}
// Returns TextSpan with TapGestureRecognizer (NOT GestureDetector — swallowed by SelectionArea)
```

### reader_screen.dart — key structure
```dart
// ReaderScreen(bookId) → ConsumerStatefulWidget
// _buildReader → Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor)
//   body: LayoutBuilder → Stack [
//     HtmlHeightMeasurer (off-screen, keyed by chapterIdx_fontSize_width),
//     Column [
//       SizedBox(topPadding),
//       AnimatedCrossFade → ReaderTopBar (onBack, onToc, onHighlights, onBookmarks, onToggleBookmark, isBookmarked),
//       Expanded → GestureDetector(onTapUp: left→_animateToPreviousPage, right→_animateToNextPage, center→toggleToolbars)
//         → PageView.builder(
//             itemBuilder: (ctx, pageIndex) => Stack [
//               SelectionArea(contextMenuBuilder: AdaptiveTextSelectionToolbar 🟡🟢🩷 Cancel)
//                 → ChapterPageWidget(htmlContent, pageIndex, pageHeight, pageWidth, fontSize, onHighlightTap),
//               if (pageIsBookmarked) Positioned(top:0, right:16) → _BookmarkRibbon(),
//             ]
//           ),
//       AnimatedCrossFade → ReaderBottomBar,
//       SizedBox(bottomPadding),
//     ]
//   ]
//
// _animateToNextPage: pageController.animateToPage(+1, 300ms, Curves.easeInOut)
// _toggleBookmark: isPageBookmarked → deleteBookmarkForPage OR addBookmark(snippet from plainText)
// _showBookmarksDialog: showModalBottomSheet → BookmarksScreen(onBookmarkTap: goToChapter + goToPage)
// _showHighlightsDialog: showModalBottomSheet → HighlightsScreen
// _showTocDialog: showModalBottomSheet → TocScreen
// _showHighlightOptionsSheet: bottom sheet with color swatches + delete
```

### ReaderTopBar actions (reader_toolbar.dart)
```
PopupMenuButton: font 14/17/20 → prefs.setDouble('font_size', size)
Icons.list → onToc
Icons.highlight → onHighlights
Icons.collections_bookmark_outlined → onBookmarks
Icons.bookmark / Icons.bookmark_border (amber) → onToggleBookmark
Consumer → Icons.dark_mode / Icons.light_mode → themeModeProvider.notifier.toggle()
```

---

## Known Limitations / Technical Debt

1. **Pagination approximation**: scroll-as-pages (clip+translate), not true reflow. Page breaks can split mid-paragraph.
2. **Highlight offsets**: `startOffset` always stored as 0. Injection matches by plain text string (not by char offset). Fails if same text appears twice in chapter.
3. **TOC fragments**: `chap1.xhtml#section2` → only filename matched, fragment ignored.
4. **SelectionArea per page**: avoids crash but means selection can't span page boundary.
5. **Bookmark page jump**: `goToChapter` then `addPostFrameCallback(goToPage)` — may miss on slow devices if measurement isn't done yet.
6. **No search** feature.
7. **No reading timer** / statistics.

---

## Build Commands

```bash
# Run
flutter run

# Analyze
flutter analyze --no-fatal-infos

# Tests
flutter test test/repositories_test.dart

# Release APK (already built at build/app/outputs/flutter-apk/app-release.apk, 62MB)
flutter build apk --release

# iOS
flutter build ios --release

# Regenerate Drift (if schema changes)
dart run build_runner build --delete-conflicting-outputs
```

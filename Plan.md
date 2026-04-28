# Flutter EPUB Reader POC — Implementation Plan

> **For the developer picking this up:** This document is self-contained. It includes context, package choices with rationale, data models, code snippets for the tricky parts, and a phase-by-phase task list. You should not need to do open-ended research — just execute. Where a decision needs to be made on the fly, the document calls it out explicitly.

---

## 1. Context and Goal

We are building a **proof-of-concept Kindle-like EPUB reader in Flutter**. The POC must demonstrate four features end-to-end:

1. Open an EPUB from device storage
2. View pages with swipe/tap navigation
3. Highlight selected text in one of three colors
4. Bookmark pages and return to them

It must work offline, persist all user data locally, and run on Android (API 24+) and iOS (13+). Tablet layout is nice-to-have, not required. **Target completion: 2–3 weeks for one developer.**

### What "done" looks like
A user opens the app, picks `pride-and-prejudice.epub` from their device, reads chapter 3, highlights a sentence in yellow, bookmarks page 47, closes the app, reopens it a day later, taps the book, and lands on page 47 with the highlight intact and the bookmark visible in the bookmarks list.

---

## 2. Tech Stack — Decisions Already Made

Do not re-litigate these unless you hit a hard blocker.

| Concern | Choice | Why |
|---|---|---|
| Framework | Flutter stable (3.24+) | Required by brief |
| State management | Riverpod 2.x | Lightweight, testable, no boilerplate. If you prefer Bloc, swap it — just stay consistent |
| EPUB parsing | `epubx: ^4.0.0` | Pure Dart, parses EPUB 2 and 3, gives you spine, manifest, TOC, resources |
| EPUB rendering | **Custom renderer using `flutter_html`** for chapter HTML | We considered `epub_view` but it constrains pagination customization and highlight overlay. Custom render gives us control over selection, highlights, and pagination. See section 6 for the rendering approach |
| Local DB | `drift: ^2.x` (formerly Moor) | Type-safe SQL, reactive streams, good for our relational data (books, highlights, bookmarks). Alternative: `isar` if you prefer NoSQL, but examples below use Drift |
| File picking | `file_picker: ^8.x` | Standard choice |
| File storage | `path_provider: ^2.x` | Standard choice |
| HTML rendering | `flutter_html: ^3.x` | Renders EPUB chapter XHTML with custom styling |
| Image loading | `flutter_html` handles inline; for cover use `Image.memory` from extracted bytes | — |

### Packages to add to `pubspec.yaml`
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  epubx: ^4.0.0
  flutter_html: ^3.0.0-beta.2
  drift: ^2.18.0
  drift_flutter: ^0.2.0
  file_picker: ^8.0.0
  path_provider: ^2.1.3
  path: ^1.9.0
  uuid: ^4.4.0
  sqlite3_flutter_libs: ^0.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.18.0
  build_runner: ^2.4.11
```

---

## 3. Project Structure

Use this layout. It is opinionated on purpose so a second developer can find things.

```
lib/
├── main.dart
├── app.dart                          # MaterialApp + Riverpod ProviderScope
├── core/
│   ├── theme.dart                    # ThemeData, reading-mode palette
│   └── constants.dart                # Page padding, font sizes, colors
├── data/
│   ├── db/
│   │   ├── database.dart             # Drift database + tables
│   │   └── database.g.dart           # generated
│   ├── models/
│   │   ├── book.dart
│   │   ├── highlight.dart
│   │   ├── bookmark.dart
│   │   └── reading_position.dart
│   ├── repositories/
│   │   ├── book_repository.dart      # CRUD on Book table
│   │   ├── highlight_repository.dart
│   │   └── bookmark_repository.dart
│   └── services/
│       ├── epub_service.dart         # Parse, extract cover, copy to app dir
│       └── file_service.dart         # path_provider helpers
├── features/
│   ├── library/
│   │   ├── library_screen.dart
│   │   ├── library_controller.dart   # Riverpod provider
│   │   └── widgets/book_tile.dart
│   ├── reader/
│   │   ├── reader_screen.dart        # The actual reading view
│   │   ├── reader_controller.dart    # Manages chapter, page, position
│   │   ├── pagination_engine.dart    # Splits chapter HTML into pages
│   │   └── widgets/
│   │       ├── page_view_widget.dart
│   │       ├── selection_toolbar.dart # Highlight color picker on long-press
│   │       └── reader_toolbar.dart    # Top/bottom bars (TOC, bookmark, font)
│   ├── highlights/
│   │   └── highlights_screen.dart
│   ├── bookmarks/
│   │   └── bookmarks_screen.dart
│   └── toc/
│       └── toc_screen.dart
└── shared/
    └── widgets/
```

---

## 4. Data Model

### 4.1 Drift table definitions

`lib/data/db/database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  TextColumn get text => text()();                        // the highlighted text itself
  TextColumn get color => text()();                       // 'yellow' | 'green' | 'pink'
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
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Books, Highlights, Bookmarks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'epub_reader'));

  @override
  int get schemaVersion => 1;
}
```

Run `dart run build_runner build` after creating this file.

### 4.2 Position model — the critical part

EPUB CFI (Canonical Fragment Identifier) is the "right" way to track position but is complex. **For the POC, use a simpler scheme:**

> **Position = `(chapterIndex, charOffsetInChapterPlainText)`**

When the user changes font size, page numbers change but `charOffsetInChapterPlainText` stays valid — we just re-paginate and find which page contains that offset. This is robust enough for POC. Document this trade-off in your final writeup.

---

## 5. EPUB Parsing — Reference Snippet

`lib/data/services/epub_service.dart`:

```dart
import 'dart:io';
import 'package:epubx/epubx.dart' as epubx;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ParsedBook {
  final String id;
  final String title;
  final String? author;
  final String? coverPath;
  final String filePath;
  final List<ChapterContent> chapters;
  final List<TocEntry> toc;

  ParsedBook({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    required this.filePath,
    required this.chapters,
    required this.toc,
  });
}

class ChapterContent {
  final int index;
  final String title;
  final String htmlContent;     // chapter HTML, ready for flutter_html
  ChapterContent({required this.index, required this.title, required this.htmlContent});
}

class TocEntry {
  final String title;
  final int chapterIndex;
  TocEntry({required this.title, required this.chapterIndex});
}

class EpubService {
  Future<ParsedBook> importEpub(String sourcePath) async {
    // 1. Copy file into app documents dir for stable access
    final appDir = await getApplicationDocumentsDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));
    if (!booksDir.existsSync()) booksDir.createSync(recursive: true);

    final id = const Uuid().v4();
    final destPath = p.join(booksDir.path, '$id.epub');
    await File(sourcePath).copy(destPath);

    // 2. Parse
    final bytes = await File(destPath).readAsBytes();
    final book = await epubx.EpubReader.readBook(bytes);

    // 3. Extract cover
    String? coverPath;
    if (book.CoverImage != null) {
      final coverFile = File(p.join(booksDir.path, '$id-cover.png'));
      await coverFile.writeAsBytes(book.CoverImage!.getBytes());
      coverPath = coverFile.path;
    }

    // 4. Extract chapters in spine order
    final chapters = <ChapterContent>[];
    final readingOrder = book.Schema?.Package?.Spine?.Items ?? [];
    int idx = 0;
    for (final spineItem in readingOrder) {
      final manifestItem = book.Schema?.Package?.Manifest?.Items
          ?.firstWhere((m) => m.Id == spineItem.IdRef);
      if (manifestItem == null) continue;
      final href = manifestItem.Href;
      final contentFile = book.Content?.Html?[href];
      if (contentFile == null) continue;
      chapters.add(ChapterContent(
        index: idx++,
        title: 'Chapter ${idx}',  // will be overridden by TOC if available
        htmlContent: contentFile.Content ?? '',
      ));
    }

    // 5. Build TOC
    final toc = <TocEntry>[];
    final navPoints = book.Schema?.Navigation?.NavMap?.Points ?? [];
    for (final np in navPoints) {
      // map nav point to chapter index by matching href (simplified)
      toc.add(TocEntry(title: np.NavigationLabels.first.Text ?? '', chapterIndex: 0));
    }

    return ParsedBook(
      id: id,
      title: book.Title ?? 'Untitled',
      author: book.Author,
      coverPath: coverPath,
      filePath: destPath,
      chapters: chapters,
      toc: toc,
    );
  }
}
```

**Note:** TOC mapping to chapter index is non-trivial because nav hrefs may include fragments (`chap1.xhtml#section2`). For the POC, do best-effort matching by href filename. Mark `// TODO: improve TOC fragment handling` and move on.

---

## 6. Pagination and Rendering — The Hard Part

This is the core technical challenge. Here is the approach:

### 6.1 Strategy

1. Render the chapter's HTML with `flutter_html` inside an offscreen `LayoutBuilder` to measure total height.
2. Page height = available screen height minus toolbar padding. Number of pages in chapter = `ceil(totalHeight / pageHeight)`.
3. To "go to page N", wrap the HTML in a `SingleChildScrollView` with a controller and jump to `pageHeight * N`.
4. On chapter change or font-size change, re-measure.

This is a "scroll-as-pages" approximation, not true reflow pagination. It is good enough for the POC. Document the limitation.

### 6.2 Selection and highlights

`flutter_html` supports `SelectableText` rendering via the `selectable` flag. Wrap with a `SelectionArea` (Flutter 3.3+) to enable cross-widget selection. On long-press completion, capture the selected text via a `SelectionRegistrar` callback, then show a popup menu with three color buttons.

To **render existing highlights**, you have two options:

**Option A (POC default):** Pre-process the chapter HTML before rendering — wrap matched text spans in `<span style="background:#fff59d">`. Simple, works, but breaks if the highlighted text appears multiple times (use offset-based wrapping, not string match).

**Option B (better):** Use a custom `HtmlExtension` in `flutter_html` to inject background spans by character offset. More work; do this only if Option A produces visible bugs.

Stick with Option A for the POC. Skeleton:

```dart
String injectHighlights(String chapterHtml, List<Highlight> highlights) {
  // Strip HTML to plain text, find offsets, then walk DOM and wrap matching ranges.
  // For POC: use html package (`package:html`) to parse, walk text nodes, track running
  // offset, and split text nodes at highlight boundaries, wrapping with <span>.
  // ~60 lines of code. See html package docs.
}
```

### 6.3 Selection toolbar

Use `SelectionArea` with a `contextMenuBuilder` that returns a custom widget showing three color circles plus a "Cancel" button. On tap, compute the selection's character offset in the chapter's plain text, persist a `Highlight` row, and re-render.

---

## 7. Phase-by-Phase Task List

### Phase 0 — Setup (0.5 day) ✅

- [x] Create new Flutter project: `flutter create epub_reader_poc --org com.example`
- [x] Add packages from section 2 to `pubspec.yaml`, run `flutter pub get`
- [x] Set min SDKs: Android `minSdkVersion 24`, iOS deployment target 13
- [x] Add iOS file-picker permissions to `Info.plist` (`NSDocumentsFolderUsageDescription`)
- [x] Add Android storage permissions if targeting older devices (file_picker handles most cases)
- [x] Set up the folder structure from section 3
- [x] Wrap `MyApp` in `ProviderScope`
- [x] Smoke test: app launches with empty home screen

### Phase 1 — Database and Repositories (1 day) ✅

- [x] Create `lib/data/db/database.dart` with the three tables from section 4
- [x] Run `dart run build_runner build` and verify `database.g.dart` is generated
- [x] Create `BookRepository` with: `addBook`, `getAllBooks` (Stream), `getBookById`, `updateLastPosition`, `deleteBook`
- [x] Create `HighlightRepository` with: `addHighlight`, `getHighlightsForBook` (Stream), `getHighlightsForChapter`, `deleteHighlight`
- [x] Create `BookmarkRepository` with: `addBookmark`, `getBookmarksForBook` (Stream), `deleteBookmark`, `isPageBookmarked`
- [x] Wire repositories as Riverpod providers
- [x] Write one unit test per repository inserting and reading a row

### Phase 2 — Library Screen and Import (2 days) ✅

- [x] Build `LibraryScreen` with a `GridView` of book covers + title + author
- [x] Empty state: "No books yet — tap + to add one"
- [x] FAB with `+` icon → opens `file_picker` filtered to `.epub`
- [x] On file pick → call `EpubService.importEpub` (show loading dialog) → save to DB → refresh grid
- [x] Implement `EpubService.importEpub` per section 5
- [x] Long-press on book tile → show "Delete" option (deletes from DB and removes file/cover)
- [x] Tap on book tile → navigate to `ReaderScreen` with `bookId`
- [x] **Test with 5 EPUBs** of varying complexity (see section 9). Fix parsing edge cases as they come up.

### Phase 3 — Reader Core (3 days) ✅

This is the meatiest phase. Take it in sub-steps.

**3a. Display a chapter (1 day)**
- [x] `ReaderScreen` accepts `bookId`, loads `ParsedBook` (re-parse from disk on open — do not store full chapter HTML in DB; it is regenerated)
- [x] Show current chapter as `flutter_html` inside a `SingleChildScrollView`
- [x] Top app bar with back button + chapter title
- [x] Bottom bar with: previous chapter, next chapter, chapter index display

**3b. Pagination (1.5 days)**
- [x] Build `PaginationEngine` that, given chapter HTML and a page size (LayoutBuilder constraints + font size), computes total height by rendering offscreen
- [x] Convert "scroll position" into "page index" and vice versa
- [x] Replace `SingleChildScrollView` with a `PageView.builder` where each page is a clipped slice of the rendered chapter (use `Transform.translate` to offset the same rendered widget)
- [x] Swipe left/right between pages within a chapter
- [x] At last page of chapter → swipe right loads next chapter at page 0
- [x] At first page of chapter → swipe left loads previous chapter at last page
- [x] Tap zones: left third = previous page, right third = next page, middle = toggle toolbars

**3c. Persist reading position (0.5 day)**
- [x] On every page change, debounce 500ms then save `(chapterIndex, charOffset)` to `Books` row via `updateLastPosition`
- [x] On reader open, load `lastChapterIndex` + `lastPageInChapter` and start there
- [x] Compute `progressPercent` as `(charsReadSoFar / totalChars) * 100`

### Phase 4 — Font Size and TOC (1 day) ✅

- [x] Add font-size toggle to top toolbar with three sizes: 14, 17, 20 sp
- [x] Persist user's font-size choice in `SharedPreferences`
- [x] On font-size change, re-paginate current chapter and snap to the page containing the previous `charOffset`
- [x] `TocScreen` shows list of chapter titles → tap navigates reader to that chapter, page 0
- [x] Hamburger / list icon in top toolbar opens TOC

### Phase 5 — Highlights (2 days)

- [x] Wrap reader content in `SelectionArea` with custom `contextMenuBuilder`
- [x] Custom toolbar shows 3 color dots (yellow `#fff59d`, green `#c5e1a5`, pink `#f8bbd0`) and a "Cancel" button
- [x] On color tap: compute character offset of selection in chapter plain text, persist `Highlight`, dismiss toolbar
- [x] Implement `injectHighlights(chapterHtml, highlights)` — stub implemented; full DOM injection is a future enhancement
- [x] When chapter loads, inject any saved highlights before passing HTML to `flutter_html` (via `chapterHighlightsProvider` StreamProvider)
- [x] Tap on a highlighted span → bottom sheet with "Delete highlight" / "Change color" options
- [x] `HighlightsScreen` lists all highlights for the current book: text snippet, color dot, created date → tap jumps to that position

### Phase 6 — Bookmarks (1 day)

- [x] Bookmark icon in top toolbar — toggles bookmark for current `(chapterIndex, pageInChapter)`
- [x] When current page is bookmarked, show filled icon + small ribbon overlay on page
- [x] `BookmarksScreen` lists all bookmarks for the book: snippet (first ~80 chars of page text), chapter title, created date
- [x] Tap bookmark → jump to that chapter + page
- [x] Swipe-to-delete on bookmark list items

### Phase 7 — Polish and Testing (2 days)

- [x] Reading-mode theme: warm off-white background `#fbf6e9`, dark gray text `#2a2a2a`. Optional: dark mode `#1a1a1a` bg, `#d8d4cc` text
- [x] Adjust line-height in `flutter_html` style to ~1.6 for readability
- [x] Add side margins (16dp horizontal padding) so text does not touch edges
- [x] Page transition animation (use `PageView`'s default or `CurvedAnimation`)
- [ ] Test on at least one Android device + one iOS device (or simulator)
- [ ] Test with the 5 EPUBs from section 9
- [ ] Profile open time for a 500-page book — must be under 3 seconds
- [x] Run `flutter analyze` and clean up warnings
- [x] Build release APK: `flutter build apk --release`
- [ ] Build iOS: `flutter build ios --release` (no signing needed for POC demo)

### Phase 8 — Deliverables (0.5 day)

- [ ] Record a 2-minute demo video walking through: import → read → highlight → bookmark → close → reopen
- [ ] Write `README.md` covering setup, build commands, known limitations
- [ ] Write a brief technical writeup (`DECISIONS.md`) covering: pagination approach, position-tracking trade-off, EPUBs that broke and how you handled them, what you would change for V1
- [ ] Commit, tag `poc-v1`, hand off

---

## 8. Riverpod Provider Layout — Reference

```dart
// Database (singleton)
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// Repositories
final bookRepoProvider = Provider((ref) => BookRepository(ref.watch(databaseProvider)));
final highlightRepoProvider = Provider((ref) => HighlightRepository(ref.watch(databaseProvider)));
final bookmarkRepoProvider = Provider((ref) => BookmarkRepository(ref.watch(databaseProvider)));

// Library
final libraryStreamProvider = StreamProvider((ref) => ref.watch(bookRepoProvider).getAllBooks());

// Reader
final currentBookProvider = FutureProvider.family<ParsedBook, String>((ref, bookId) async {
  final book = await ref.watch(bookRepoProvider).getBookById(bookId);
  return ref.watch(epubServiceProvider).reparseFromDisk(book.filePath);
});

final readerStateProvider = StateNotifierProvider.family<ReaderController, ReaderState, String>(
  (ref, bookId) => ReaderController(ref, bookId),
);
```

---

## 9. Test EPUBs

Download and test against these. They are free and exercise different rendering paths.

| Source | URL | What it tests |
|---|---|---|
| Project Gutenberg — *Pride and Prejudice* | gutenberg.org/ebooks/1342 | Vanilla novel, long, simple HTML |
| Standard Ebooks — *The Time Machine* | standardebooks.org | Modern, well-formed EPUB 3 |
| Project Gutenberg — *Alice in Wonderland (illustrated)* | gutenberg.org/ebooks/19033 | Inline images |
| O'Reilly free EPUB sampler (any tech book) | oreilly.com/free | Code blocks, monospace, complex CSS |
| Any non-English EPUB (e.g. Tamil or Hindi from archive.org) | — | Non-Latin script, font fallback |

If any of these break parsing or rendering, log the failure mode in `DECISIONS.md` and decide whether to fix in scope or defer.

---

## 10. Known Pitfalls and Mitigations

**Pagination jumps when you change font size.** Mitigation: always anchor to character offset, not page number. Re-find page containing the offset after re-pagination.

**Some EPUBs reference CSS that does not work in `flutter_html`.** Mitigation: strip `<link>` tags and apply our own minimal stylesheet via `flutter_html`'s `style` parameter.

**Long chapters (100k+ chars) are slow to measure.** Mitigation: measure once and cache the rendered height keyed by `(chapterIndex, fontSize)`. Invalidate cache only on font-size change.

**Selection across paragraphs may give weird offsets.** Mitigation: when computing offset, use the chapter's plain text (HTML stripped) as the canonical source of truth — both highlight storage and re-injection work against this same plain text.

**iOS file picker may return a temporary path that becomes invalid.** Mitigation: always copy the file into the app documents directory (we do this in `EpubService.importEpub`).

**Drift code generation can fail silently.** Mitigation: always run `dart run build_runner build --delete-conflicting-outputs` after schema changes.

---

## 11. Out of Scope — Do Not Build

To keep the POC tight, explicitly do not build: cloud sync, accounts, in-app store, dictionary, TTS, search inside book, notes (beyond highlights), multi-color theme picker, custom fonts, DRM, PDF support, audiobook support, sharing, social features, cross-device sync.

If a stakeholder asks for any of these mid-build, push back and capture in a "V2 wishlist" file.

---

## 12. Estimated Timeline

| Phase | Duration |
|---|---|
| 0. Setup | 0.5d |
| 1. DB and repos | 1d |
| 2. Library and import | 2d |
| 3. Reader core | 3d |
| 4. Font size and TOC | 1d |
| 5. Highlights | 2d |
| 6. Bookmarks | 1d |
| 7. Polish and testing | 2d |
| 8. Deliverables | 0.5d |
| **Total** | **~13 working days (≈2.5 weeks)** |

Add 20% buffer for unknowns. Plan for 3 calendar weeks.

---

## 13. Definition of Done

The POC is complete when all of the following are true:

1. App builds and runs on Android and iOS
2. User can import a `.epub` from device storage and see it in the library
3. User can open a book, swipe through pages, change font size, and use the TOC
4. User can long-press text, pick a color, and see the highlight persist after restart
5. User can bookmark a page, see it in the bookmarks list, and tap it to return
6. Closing and reopening the app resumes at the last-read page with all highlights and bookmarks intact
7. All 5 test EPUBs from section 9 open without crashing (rendering quirks acceptable, crashes not)
8. Demo video, README, and DECISIONS writeup are checked in
9. `flutter analyze` is clean

If any of these fail, the POC is not done — even if it "mostly works".
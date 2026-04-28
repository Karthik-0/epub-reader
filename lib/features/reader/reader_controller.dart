import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/services/epub_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ReaderState {
  final AsyncValue<ParsedBook> bookAsync;
  final int chapterIndex;
  final int currentPage;
  final int totalPages;
  final bool showToolbars;
  /// When true, jump to the last page of the chapter after measurement.
  final bool pendingLastPage;

  const ReaderState({
    this.bookAsync = const AsyncValue.loading(),
    this.chapterIndex = 0,
    this.currentPage = 0,
    this.totalPages = 1,
    this.showToolbars = true,
    this.pendingLastPage = false,
  });

  ReaderState copyWith({
    AsyncValue<ParsedBook>? bookAsync,
    int? chapterIndex,
    int? currentPage,
    int? totalPages,
    bool? showToolbars,
    bool? pendingLastPage,
  }) =>
      ReaderState(
        bookAsync: bookAsync ?? this.bookAsync,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        showToolbars: showToolbars ?? this.showToolbars,
        pendingLastPage: pendingLastPage ?? this.pendingLastPage,
      );
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class ReaderController extends StateNotifier<ReaderState> {
  final Ref _ref;
  final String bookId;
  Timer? _saveTimer;

  /// Page to restore once measurement is available (avoids PageView assertion
  /// when itemCount is still 1 but saved page is > 0).
  int? _pendingSavedPage;

  ReaderController(this._ref, this.bookId) : super(const ReaderState()) {
    _load();
  }

  // ---- Loading ------------------------------------------------------------

  Future<void> _load() async {
    try {
      final dbBook = await _ref.read(bookRepoProvider).getBookById(bookId);
      final parsedBook =
          await _ref.read(epubServiceProvider).reparseFromDisk(dbBook);

      // Store the saved page so we can apply it after measurement.
      _pendingSavedPage = dbBook.lastPageInChapter;

      state = state.copyWith(
        bookAsync: AsyncValue.data(parsedBook),
        chapterIndex: dbBook.lastChapterIndex,
        currentPage: 0, // will jump after measurement
      );
    } catch (e, st) {
      state = state.copyWith(bookAsync: AsyncValue.error(e, st));
    }
  }

  // ---- Measurement callback -----------------------------------------------

  /// Called by the off-screen measurer when the chapter HTML is fully laid out.
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

    state = state.copyWith(
      totalPages: total,
      currentPage: targetPage,
      pendingLastPage: false,
    );
  }

  // ---- Navigation ---------------------------------------------------------

  void goToPage(int page) {
    if (page == state.currentPage) return;
    state = state.copyWith(currentPage: page);
    _scheduleSave();
  }

  void goToChapter(int chapterIndex, {bool lastPage = false}) {
    state = state.copyWith(
      chapterIndex: chapterIndex,
      currentPage: 0,
      totalPages: 1,
      pendingLastPage: lastPage,
    );
    _scheduleSave();
  }

  void nextPage() {
    final book = state.bookAsync.valueOrNull;
    if (book == null) return;
    if (state.currentPage < state.totalPages - 1) {
      goToPage(state.currentPage + 1);
    } else if (state.chapterIndex < book.chapters.length - 1) {
      goToChapter(state.chapterIndex + 1);
    }
  }

  void previousPage() {
    if (state.currentPage > 0) {
      goToPage(state.currentPage - 1);
    } else if (state.chapterIndex > 0) {
      goToChapter(state.chapterIndex - 1, lastPage: true);
    }
  }

  void toggleToolbars() {
    state = state.copyWith(showToolbars: !state.showToolbars);
  }

  // ---- Persistence --------------------------------------------------------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer =
        Timer(const Duration(milliseconds: 500), _savePosition);
  }

  Future<void> _savePosition() async {
    final book = state.bookAsync.valueOrNull;
    if (book == null) return;

    final totalChars = book.chapters
        .fold<int>(0, (sum, ch) => sum + ch.htmlContent.length);
    final charsRead = book.chapters
        .take(state.chapterIndex)
        .fold<int>(0, (sum, ch) => sum + ch.htmlContent.length);
    final progress =
        totalChars > 0 ? (charsRead / totalChars) * 100.0 : 0.0;

    await _ref.read(bookRepoProvider).updateLastPosition(
          bookId,
          state.chapterIndex,
          state.currentPage,
          progress,
        );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition(); // persist on close
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final readerControllerProvider = StateNotifierProvider.family<
    ReaderController, ReaderState, String>(
  (ref, bookId) => ReaderController(ref, bookId),
);

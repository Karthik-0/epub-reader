import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/services/epub_service.dart';

class ReaderState {
  final AsyncValue<ParsedBook> bookAsync;
  final int chapterIndex;
  final int currentPage;
  final int totalPages;
  final bool showToolbars;
  final bool pendingLastPage;
  final Map<int, int> chapterPageCounts;

  const ReaderState({
    this.bookAsync = const AsyncValue.loading(),
    this.chapterIndex = 0,
    this.currentPage = 0,
    this.totalPages = 1,
    this.showToolbars = false,
    this.pendingLastPage = false,
    this.chapterPageCounts = const {},
  });

  ReaderState copyWith({
    AsyncValue<ParsedBook>? bookAsync,
    int? chapterIndex,
    int? currentPage,
    int? totalPages,
    bool? showToolbars,
    bool? pendingLastPage,
    Map<int, int>? chapterPageCounts,
  }) =>
      ReaderState(
        bookAsync: bookAsync ?? this.bookAsync,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        showToolbars: showToolbars ?? this.showToolbars,
        pendingLastPage: pendingLastPage ?? this.pendingLastPage,
        chapterPageCounts: chapterPageCounts ?? this.chapterPageCounts,
      );

  int globalPage(int chapterIdx, int page) {
    int offset = 0;
    for (int i = 0; i < chapterIdx; i++) {
      offset += chapterPageCounts[i] ?? 0;
    }
    return offset + page + 1;
  }
}

class ReaderController extends StateNotifier<ReaderState> {
  final Ref _ref;
  final String bookId;
  Timer? _saveTimer;
  int? _pendingSavedPage;

  ReaderController(this._ref, this.bookId) : super(const ReaderState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final dbBook = await _ref.read(bookRepoProvider).getBookById(bookId);
      final parsedBook = await _ref.read(epubServiceProvider).reparseFromDisk(dbBook);
      _pendingSavedPage = dbBook.lastPageInChapter;
      state = state.copyWith(
        bookAsync: AsyncValue.data(parsedBook),
        chapterIndex: dbBook.lastChapterIndex,
        currentPage: 0,
      );
    } catch (e, st) {
      state = state.copyWith(bookAsync: AsyncValue.error(e, st));
    }
  }

  void onTotalPagesMeasured(int total, {required int chapterIndex}) {
    int targetPage = 0;
    if (_pendingSavedPage != null && chapterIndex == state.chapterIndex) {
      targetPage = _pendingSavedPage!.clamp(0, total - 1);
      _pendingSavedPage = null;
    } else if (state.pendingLastPage && chapterIndex == state.chapterIndex) {
      targetPage = total - 1;
    } else if (chapterIndex == state.chapterIndex) {
      targetPage = state.currentPage.clamp(0, total - 1);
    }

    final newCounts = Map<int, int>.from(state.chapterPageCounts)
      ..[chapterIndex] = total;

    if (chapterIndex == state.chapterIndex) {
      state = state.copyWith(
        totalPages: total,
        currentPage: targetPage,
        pendingLastPage: false,
        chapterPageCounts: newCounts,
      );
    } else {
      state = state.copyWith(chapterPageCounts: newCounts);
    }
  }

  void goToPage(int page) {
    final targetPage = page.clamp(0, state.totalPages - 1);
    if (targetPage == state.currentPage) return;
    state = state.copyWith(currentPage: targetPage);
    _scheduleSave();
  }

  void goToChapter(int chapterIndex, {bool lastPage = false}) {
    final book = state.bookAsync.valueOrNull;
    final maxChapterIndex = (book?.chapters.length ?? 1) - 1;
    final targetChapter = chapterIndex.clamp(0, maxChapterIndex);
    final cachedTotal = state.chapterPageCounts[targetChapter];
    final targetPage = lastPage && cachedTotal != null
        ? (cachedTotal - 1).clamp(0, cachedTotal - 1)
        : 0;

    state = state.copyWith(
      chapterIndex: targetChapter,
      currentPage: targetPage,
      totalPages: cachedTotal ?? 1,
      pendingLastPage: lastPage && cachedTotal == null,
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

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _savePosition);
  }

  Future<void> _savePosition() async {
    final book = state.bookAsync.valueOrNull;
    if (book == null) return;
    final totalChars = book.chapters.fold<int>(0, (sum, ch) => sum + ch.htmlContent.length);
    final charsRead = book.chapters.take(state.chapterIndex).fold<int>(0, (sum, ch) => sum + ch.htmlContent.length);
    final progress = totalChars > 0 ? (charsRead / totalChars) * 100.0 : 0.0;
    await _ref.read(bookRepoProvider).updateLastPosition(bookId, state.chapterIndex, state.currentPage, progress);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    super.dispose();
  }
}

final readerControllerProvider = StateNotifierProvider.family<ReaderController, ReaderState, String>(
  (ref, bookId) => ReaderController(ref, bookId),
);
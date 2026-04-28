import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/preferences.dart';
import '../../data/db/database.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/highlight_repository.dart';
import '../../data/services/epub_service.dart';
import '../../data/services/highlight_service.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../highlights/highlights_screen.dart';
import '../toc/toc_screen.dart';
import 'pagination_engine.dart';
import 'reader_controller.dart';
import 'widgets/page_view_widget.dart';
import 'widgets/reader_toolbar.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final String bookId;
  const ReaderScreen({super.key, required this.bookId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late PageController _pageController;
  String? _selectedText;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onHeightMeasured(
    double height,
    double pageHeight,
    ReaderController notifier,
    ReaderState state,
  ) {
    if (pageHeight <= 0) return;
    final total = PaginationEngine.computePageCount(height, pageHeight);
    notifier.onTotalPagesMeasured(total);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider(widget.bookId));
    final notifier =
        ref.read(readerControllerProvider(widget.bookId).notifier);

    // ---- Side-effects via ref.listen ----------------------------------------

    ref.listen<ReaderState>(
      readerControllerProvider(widget.bookId),
      (prev, curr) {
        if (prev == null) return;

        // Chapter changed → fresh PageController (must defer to avoid build-time setState)
        if (prev.chapterIndex != curr.chapterIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _pageController.dispose();
              _pageController = PageController();
            });
          });
          return;
        }

        // Page changed externally (restored position / pendingLastPage resolved)
        if (prev.currentPage != curr.currentPage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            _pageController.jumpToPage(curr.currentPage);
          });
        }
      },
    );

    // ---- Render -------------------------------------------------------------

    return state.bookAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error loading book',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (book) => _buildReader(context, state, notifier, book),
    );
  }

  Widget _buildReader(
    BuildContext context,
    ReaderState state,
    ReaderController notifier,
    ParsedBook book,
  ) {
    // Watch font size changes (invalidates key, triggers remeasure)
    final fontSizeAsync = ref.watch(sharedPreferencesProvider);
    final fontSize = fontSizeAsync.when(
      data: (prefs) => prefs.getDouble('font_size') ?? 17.0,
      loading: () => 17.0,
      error: (Object error, StackTrace st) => 17.0,
    );

    if (book.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(book.title),
          leading: const BackButton(),
        ),
        body: const Center(child: Text('No chapters found in this EPUB.')),
      );
    }

    final chapterIdx =
        state.chapterIndex.clamp(0, book.chapters.length - 1);
    final chapter = book.chapters[chapterIdx];

    // Watch highlights for the current chapter (reactive stream)
    final chapterHighlightsAsync = ref.watch(
        chapterHighlightsProvider((book.id, chapterIdx)));

    // Watch whether the current page is bookmarked
    final isBookmarked = ref
        .watch(pageBookmarkedProvider((book.id, chapterIdx, state.currentPage)))
        .valueOrNull ?? false;

    // Inject highlights into HTML before rendering
    final htmlContent = chapterHighlightsAsync.when(
      data: (highlights) =>
          HighlightService.injectHighlights(chapter.htmlContent, highlights),
      loading: () => chapter.htmlContent,
      error: (Object e, StackTrace st) => chapter.htmlContent,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mq = MediaQuery.of(context);
          final topPadding = mq.padding.top;
          final bottomPadding = mq.padding.bottom;

          const topBarHeight = kToolbarHeight;
          const bottomBarHeight = 56.0; // progress line + row

          final pageHeight = constraints.maxHeight -
              topPadding -
              bottomPadding -
              (state.showToolbars ? topBarHeight + bottomBarHeight : 0);
          final pageWidth = constraints.maxWidth;
          final measureWidth =
              pageWidth - AppDimensions.pageHorizontalPadding * 2;

          return Stack(
            children: [
              // ---- Off-screen height measurer (keyed by fontSize for remeasure) ----
              HtmlHeightMeasurer(
                key: ValueKey(
                    '${chapterIdx}_${fontSize}_$measureWidth'),
                htmlContent: chapter.htmlContent,
                width: measureWidth,
                fontSize: fontSize,
                onHeightMeasured: (h) =>
                    _onHeightMeasured(h, pageHeight, notifier, state),
              ),

              // ---- Main layout ---------------------------------------------
              Column(
                children: [
                  // Top safe-area spacer (always)
                  SizedBox(height: topPadding),

                  // Animated top toolbar
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: state.showToolbars
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: ReaderTopBar(
                      chapterTitle: chapter.title,
                      onBack: () => Navigator.of(context).pop(),
                      onToc: () => _showTocDialog(context, book, notifier),
                      onHighlights: () =>
                          _showHighlightsDialog(context, book, notifier),
                      onBookmarks: () =>
                          _showBookmarksDialog(context, book, notifier),
                      isBookmarked: isBookmarked,
                      onToggleBookmark: () =>
                          _toggleBookmark(book, chapterIdx, state, chapter),
                    ),
                    secondChild: const SizedBox.shrink(),
                  ),

                  // ---- Page view -------------------------------------------
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        final w = constraints.maxWidth;
                        final x = details.localPosition.dx;
                        if (x < w * 0.3) {
                          _animateToPreviousPage(state, notifier);
                        } else if (x > w * 0.7) {
                          _animateToNextPage(state, notifier);
                        } else {
                          notifier.toggleToolbars();
                        }
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: state.totalPages,
                        onPageChanged: (page) => notifier.goToPage(page),
                        itemBuilder: (context, pageIndex) {
                          final pageIsBookmarked =
                              pageIndex == state.currentPage && isBookmarked;
                          return Stack(
                            children: [
                              SelectionArea(
                                onSelectionChanged: (value) {
                                  setState(() => _selectedText = value?.plainText);
                                },
                                contextMenuBuilder: (ctx, selectableRegionState) {
                                  final text = _selectedText ?? '';
                                  return AdaptiveTextSelectionToolbar.buttonItems(
                                    anchors: selectableRegionState.contextMenuAnchors,
                                    buttonItems: [
                                      for (final (label, colorName) in [
                                        ('🟡 Yellow', 'yellow'),
                                        ('🟢 Green', 'green'),
                                        ('🩷 Pink', 'pink'),
                                      ])
                                        ContextMenuButtonItem(
                                          label: label,
                                          onPressed: () async {
                                            if (text.isNotEmpty) {
                                              await _createHighlight(
                                                  colorName, text, chapterIdx, book);
                                            }
                                            selectableRegionState.hideToolbar();
                                          },
                                        ),
                                      ContextMenuButtonItem(
                                        label: 'Cancel',
                                        onPressed: selectableRegionState.hideToolbar,
                                      ),
                                    ],
                                  );
                                },
                                child: ChapterPageWidget(
                                  htmlContent: htmlContent,
                                  pageIndex: pageIndex,
                                  pageHeight: pageHeight,
                                  pageWidth: pageWidth,
                                  fontSize: fontSize,
                                  onHighlightTap: (id) =>
                                      _showHighlightOptionsSheet(context, id),
                                ),
                              ),
                              if (pageIsBookmarked)
                                const Positioned(
                                  top: 0,
                                  right: 16,
                                  child: _BookmarkRibbon(),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: state.showToolbars
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: ReaderBottomBar(
                      currentPage: state.currentPage,
                      totalPages: state.totalPages,
                      chapterIndex: chapterIdx,
                      totalChapters: book.chapters.length,
                      onPreviousChapter: chapterIdx > 0
                          ? () => notifier.goToChapter(chapterIdx - 1)
                          : null,
                      onNextChapter: chapterIdx < book.chapters.length - 1
                          ? () => notifier.goToChapter(chapterIdx + 1)
                          : null,
                    ),
                    secondChild: const SizedBox.shrink(),
                  ),

                  // Bottom safe-area spacer
                  SizedBox(height: bottomPadding),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Animated page navigation (tap-zone)
  // ---------------------------------------------------------------------------

  void _animateToNextPage(ReaderState state, ReaderController notifier) {
    if (!_pageController.hasClients) return;
    final currentPage = state.currentPage;
    final totalPages = state.totalPages;
    if (currentPage < totalPages - 1) {
      _pageController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      notifier.nextPage(); // triggers chapter advance
    }
  }

  void _animateToPreviousPage(ReaderState state, ReaderController notifier) {
    if (!_pageController.hasClients) return;
    final currentPage = state.currentPage;
    if (currentPage > 0) {
      _pageController.animateToPage(
        currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      notifier.previousPage(); // triggers chapter retreat
    }
  }

  /// Show TOC as a modal
  void _showTocDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) => TocScreen(
        book: book,
        onChapterSelected: (chapterIndex) {
          notifier.goToChapter(chapterIndex);
        },
      ),
      isScrollControlled: true,
      useSafeArea: true,
    );
  }

  void _showHighlightsDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HighlightsScreen(
        bookId: book.id,
        onHighlightTap: (chapterIndex) {
          notifier.goToChapter(chapterIndex);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Shows a bottom sheet for an existing highlight (identified by [highlightId])
  /// with options to delete or change color.
  void _showHighlightOptionsSheet(BuildContext context, String highlightId) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Change color row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Change color',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final entry in [
                        ('yellow', const Color(0xFFFFF59D)),
                        ('green', const Color(0xFFC5E1A5)),
                        ('pink', const Color(0xFFF8BBD0)),
                      ]) ...[
                        GestureDetector(
                          onTap: () async {
                            await ref
                                .read(highlightRepoProvider)
                                .updateHighlightColor(highlightId, entry.$1);
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: entry.$2,
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Delete highlight', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await ref.read(highlightRepoProvider).deleteHighlight(highlightId);
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _createHighlight(
    String color,
    String text,
    int chapterIdx,
    ParsedBook book,
  ) async {
    if (text.isEmpty) return;
    final companion = HighlightsCompanion.insert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: book.id,
      chapterIndex: chapterIdx,
      startOffset: 0,
      endOffset: text.length,
      content: text,
      color: color,
      createdAt: DateTime.now(),
    );
    await ref.read(highlightRepoProvider).addHighlight(companion);
  }

  Future<void> _toggleBookmark(
    ParsedBook book,
    int chapterIdx,
    ReaderState state,
    ChapterContent chapter,
  ) async {
    final repo = ref.read(bookmarkRepoProvider);
    final alreadyBookmarked = await repo.isPageBookmarked(
        book.id, chapterIdx, state.currentPage);

    if (alreadyBookmarked) {
      await repo.deleteBookmarkForPage(book.id, chapterIdx, state.currentPage);
    } else {
      // Build a text snippet: proportional slice of chapter plain text
      final plainText = HighlightService.extractPlainText(chapter.htmlContent);
      final startChar = state.totalPages > 1
          ? ((state.currentPage / state.totalPages) * plainText.length).round()
          : 0;
      final snippet = plainText
          .substring(startChar.clamp(0, plainText.length))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final trimmed =
          snippet.length > 80 ? snippet.substring(0, 80) : snippet;

      await repo.addBookmark(BookmarksCompanion.insert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bookId: book.id,
        chapterIndex: chapterIdx,
        pageInChapter: state.currentPage,
        snippet: trimmed,
        createdAt: DateTime.now(),
      ));
    }
  }

  void _showBookmarksDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BookmarksScreen(
        bookId: book.id,
        chapters: book.chapters,
        onBookmarkTap: (chapterIndex, pageInChapter) {
          notifier.goToChapter(chapterIndex);
          // After chapter loads, jump to the saved page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifier.goToPage(pageInChapter);
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookmark ribbon widget
// ---------------------------------------------------------------------------

class _BookmarkRibbon extends StatelessWidget {
  const _BookmarkRibbon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 40),
      painter: _RibbonPainter(),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.amber.shade600;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 10)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => false;
}

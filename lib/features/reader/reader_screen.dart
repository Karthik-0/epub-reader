import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/preferences.dart';
import '../../data/db/database.dart';
import '../../data/repositories/highlight_repository.dart';
import '../../data/services/epub_service.dart';
import '../../data/services/highlight_service.dart';
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

    // Inject highlights into HTML before rendering
    final htmlContent = chapterHighlightsAsync.when(
      data: (highlights) =>
          HighlightService.injectHighlights(chapter.htmlContent, highlights),
      loading: () => chapter.htmlContent,
      error: (Object e, StackTrace st) => chapter.htmlContent,
    );

    return Scaffold(
      backgroundColor: AppColors.readingBackground,
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
                          notifier.previousPage();
                        } else if (x > w * 0.7) {
                          notifier.nextPage();
                        } else {
                          notifier.toggleToolbars();
                        }
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: state.totalPages,
                        onPageChanged: (page) => notifier.goToPage(page),
                        itemBuilder: (context, pageIndex) => SelectionArea(
                          onSelectionChanged: (value) {
                            setState(() => _selectedText = value?.plainText);
                          },
                          contextMenuBuilder: (ctx, selectableRegionState) {
                            final text = _selectedText ?? '';
                            return Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[900],
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildColorDot(
                                      const Color(0xFFFFF59D),
                                      text,
                                      'yellow',
                                      chapterIdx,
                                      book,
                                      selectableRegionState,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildColorDot(
                                      const Color(0xFFC5E1A5),
                                      text,
                                      'green',
                                      chapterIdx,
                                      book,
                                      selectableRegionState,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildColorDot(
                                      const Color(0xFFF8BBD0),
                                      text,
                                      'pink',
                                      chapterIdx,
                                      book,
                                      selectableRegionState,
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: selectableRegionState.hideToolbar,
                                      child: const Text(
                                        '✕',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

  Widget _buildColorDot(
    Color color,
    String text,
    String colorName,
    int chapterIdx,
    ParsedBook book,
    SelectableRegionState selectableRegionState,
  ) {
    return GestureDetector(
      onTap: () async {
        if (text.isNotEmpty) {
          await _createHighlight(colorName, text, chapterIdx, book);
        }
        selectableRegionState.hideToolbar();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(4),
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
}


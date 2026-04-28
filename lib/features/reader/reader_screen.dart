import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../data/services/epub_service.dart';
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

  /// Called when the off-screen measurer has determined the chapter's total height.
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
        body: Center(child: Text('Error loading book: $e')),
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
              // ---- Off-screen height measurer ------------------------------
              HtmlHeightMeasurer(
                key: ValueKey(
                    '${chapterIdx}_${AppFontSizes.medium}_$measureWidth'),
                htmlContent: chapter.htmlContent,
                width: measureWidth,
                fontSize: AppFontSizes.medium,
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
                      onToc: null, // wired in Phase 4
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
                        itemBuilder: (_, pageIndex) => ChapterPageWidget(
                          htmlContent: chapter.htmlContent,
                          pageIndex: pageIndex,
                          pageHeight: pageHeight,
                          pageWidth: pageWidth,
                          fontSize: AppFontSizes.medium,
                        ),
                      ),
                    ),
                  ),

                  // Animated bottom toolbar
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
}


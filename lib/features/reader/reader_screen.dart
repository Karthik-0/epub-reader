import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../core/constants.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
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
import 'widgets/highlight_toolbar.dart';
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
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  Timer? _chapterTransitionTimer;
  bool _chapterTransitionGuard = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _chapterTransitionTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onHeightMeasured(
    double height,
    double pageHeight,
    double contentStep,
    int chapterIndex,
    ReaderController notifier,
  ) {
    if (pageHeight <= 0 || contentStep <= 0) return;
    final total = PaginationEngine.computePageCount(height, contentStep);
    notifier.onTotalPagesMeasured(total, chapterIndex: chapterIndex);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider(widget.bookId));
    final notifier = ref.read(readerControllerProvider(widget.bookId).notifier);

    ref.listen<ReaderState>(readerControllerProvider(widget.bookId), (
      prev,
      curr,
    ) {
      if (prev == null) return;

      // Chapter changed → fresh PageController starting at page 0
      if (prev.chapterIndex != curr.chapterIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _pageController.dispose();
            _pageController = PageController(initialPage: curr.currentPage);
          });
          _releaseChapterTransitionGuard();
        });
        return;
      }

      // Page changed externally (restored position / pendingLastPage resolved)
      if (prev.currentPage != curr.currentPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          final page = _pageController.page ?? curr.currentPage.toDouble();
          final diff = (curr.currentPage - page).abs();
          if (diff > 1) {
            _pageController.jumpToPage(curr.currentPage);
          }
        });
      }
    });

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

  void _markChapterTransitionStarted() {
    _chapterTransitionGuard = true;
    _chapterTransitionTimer?.cancel();
  }

  void _releaseChapterTransitionGuard() {
    _chapterTransitionTimer?.cancel();
    _chapterTransitionTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _chapterTransitionGuard = false;
    });
  }

  void _handleReaderPointerUp(
    PointerUpEvent event,
    ReaderState state,
    ReaderController notifier,
    ParsedBook book,
  ) {
    final down = _pointerDownPosition;
    final downAt = _pointerDownAt;
    _pointerDownPosition = null;
    _pointerDownAt = null;
    if (down == null || downAt == null) return;

    final delta = event.localPosition - down;
    final isHorizontalSwipe =
        delta.dx.abs() > 48 && delta.dx.abs() > delta.dy.abs() * 1.25;

    if (isHorizontalSwipe && !_chapterTransitionGuard) {
      final chapterIdx = state.chapterIndex.clamp(0, book.chapters.length - 1);
      final swipedForward = delta.dx < 0;
      final swipedBackward = delta.dx > 0;
      final atLastPage = state.currentPage >= state.totalPages - 1;
      final atFirstPage = state.currentPage <= 0;

      if (swipedForward &&
          atLastPage &&
          chapterIdx < book.chapters.length - 1) {
        _markChapterTransitionStarted();
        notifier.goToChapter(chapterIdx + 1);
        return;
      }

      if (swipedBackward && atFirstPage && chapterIdx > 0) {
        _markChapterTransitionStarted();
        notifier.goToChapter(chapterIdx - 1, lastPage: true);
        return;
      }
    }
  }

  Widget _buildReader(
    BuildContext context,
    ReaderState state,
    ReaderController notifier,
    ParsedBook book,
  ) {
    final fontSizeAsync = ref.watch(sharedPreferencesProvider);
    final fontFamily =
        ref.watch(readerFontFamilyProvider).valueOrNull ??
        ReaderTypography.bookerly;
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    final fontSize = fontSizeAsync.when(
      data: (prefs) => prefs.getDouble('font_size') ?? 17.0,
      loading: () => 17.0,
      error: (Object error, StackTrace st) => 17.0,
    );

    if (book.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(book.title), leading: const BackButton()),
        body: const Center(child: Text('No chapters found in this EPUB.')),
      );
    }

    final chapterIdx = state.chapterIndex.clamp(0, book.chapters.length - 1);
    final chapter = book.chapters[chapterIdx];

    final chapterHighlightsAsync = ref.watch(
      chapterHighlightsProvider((book.id, chapterIdx)),
    );
    final isBookmarked =
        ref
            .watch(
              pageBookmarkedProvider((book.id, chapterIdx, state.currentPage)),
            )
            .valueOrNull ??
        false;

    final htmlContent = chapterHighlightsAsync.when(
      data: (highlights) =>
          HighlightService.injectHighlights(chapter.htmlContent, highlights),
      loading: () => chapter.htmlContent,
      error: (Object e, StackTrace st) => chapter.htmlContent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readerTheme.overlayStyle.copyWith(
        statusBarColor: readerTheme.pageBackground,
        systemNavigationBarColor: readerTheme.pageBackground,
      ),
      child: Scaffold(
        backgroundColor: readerTheme.pageBackground,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pageWidth = constraints.maxWidth;
              final pageHeight =
                  constraints.maxHeight -
                  readerTheme.statusStripHeight -
                  AppDimensions.readingAreaTopPadding -
                  AppDimensions.readingAreaBottomPadding;
              final verticalBleed = ChapterPageWidget.pageVerticalBleed(
                fontSize,
                readerTheme.lineHeight,
              );
              final contentStep = ChapterPageWidget.effectiveContentStep(
                pageHeight,
                verticalBleed,
                fontSize,
                readerTheme.lineHeight,
              );

              return Stack(
                children: [
                  HtmlHeightMeasurer(
                    key: ValueKey('${chapterIdx}_${fontSize}_$pageWidth'),
                    htmlContent: chapter.htmlContent,
                    width: pageWidth,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                    lineHeight: readerTheme.lineHeight,
                    pageWidth: pageWidth,
                    readerTheme: readerTheme,
                    onHeightMeasured: (h) => _onHeightMeasured(
                      h,
                      pageHeight,
                      contentStep,
                      chapterIdx,
                      notifier,
                    ),
                  ),
                  Column(
                    children: [
                      const SizedBox(
                        height: AppDimensions.readingAreaTopPadding,
                      ),
                      Expanded(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            _pointerDownPosition = event.localPosition;
                            _pointerDownAt = DateTime.now();
                          },
                          onPointerUp: (event) {
                            _handleReaderPointerUp(
                              event,
                              state,
                              notifier,
                              book,
                            );
                          },
                          child: PageView.builder(
                            key: ValueKey('pv-${state.chapterIndex}'),
                            controller: _pageController,
                            itemCount: state.totalPages,
                            onPageChanged: (page) {
                              if (_chapterTransitionGuard) return;
                              notifier.goToPage(page);
                            },
                            itemBuilder: (context, pageIndex) {
                              final pageIsBookmarked =
                                  pageIndex == state.currentPage &&
                                  isBookmarked;
                              return Stack(
                                children: [
                                  SelectionArea(
                                    onSelectionChanged: (value) {
                                      _selectedText = value?.plainText.trim();
                                    },
                                    contextMenuBuilder: (ctx, selectableRegionState) {
                                      final selectedText = (_selectedText ?? '')
                                          .trim();
                                      TextSelectionToolbarAnchors anchors;
                                      try {
                                        anchors = selectableRegionState
                                            .contextMenuAnchors;
                                      } catch (_) {
                                        anchors =
                                            const TextSelectionToolbarAnchors(
                                              primaryAnchor: Offset.zero,
                                              secondaryAnchor: Offset.zero,
                                            );
                                      }
                                      return TextSelectionToolbar(
                                        anchorAbove: anchors.primaryAnchor,
                                        anchorBelow:
                                            anchors.secondaryAnchor ??
                                            anchors.primaryAnchor,
                                        children: [
                                          HighlightToolbar(
                                            enabled: selectedText.isNotEmpty,
                                            onHighlight: (color) =>
                                                _createHighlight(
                                                  color,
                                                  selectedText,
                                                  chapterIdx,
                                                  book,
                                                  state,
                                                ),
                                            onCancel: selectableRegionState
                                                .hideToolbar,
                                            onNote: () {
                                              selectableRegionState
                                                  .hideToolbar();
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Notes are not implemented yet.',
                                                  ),
                                                ),
                                              );
                                            },
                                            onShare: () {
                                              selectableRegionState
                                                  .hideToolbar();
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Share is not implemented yet.',
                                                  ),
                                                ),
                                              );
                                            },
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
                                      fontFamily: fontFamily,
                                      onHighlightTap: (id) =>
                                          _showHighlightOptionsSheet(
                                            context,
                                            id,
                                          ),
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
                      const SizedBox(
                        height: AppDimensions.readingAreaBottomPadding,
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ReaderTopBar(
                      chapterTitle: chapter.title,
                      onBack: () => Navigator.of(context).pop(),
                      onTypography: () => _showTypographySheet(context),
                      onMenuAction: (action) =>
                          _handleMenuAction(context, action, book, notifier),
                      isBookmarked: isBookmarked,
                      onToggleBookmark: () =>
                          _toggleBookmark(book, chapterIdx, state, chapter),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    ParsedBook book,
    ReaderController notifier,
  ) {
    switch (action) {
      case 'contents':
        _showTocDialog(context, book, notifier);
        break;
      case 'highlights':
        _showHighlightsDialog(context, book, notifier);
        break;
      case 'bookmarks':
        _showBookmarksDialog(context, book, notifier);
        break;
    }
  }

  void _showTypographySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
          final selectedMode =
              ref.watch(readerColorModeProvider).valueOrNull ??
              ReaderColorMode.sepia;
          final selectedFont =
              ref.watch(readerFontFamilyProvider).valueOrNull ??
              ReaderTypography.bookerly;
          final selectedSize =
              ref
                  .watch(sharedPreferencesProvider)
                  .valueOrNull
                  ?.getDouble('font_size') ??
              AppFontSizes.medium;

          return Container(
            height: MediaQuery.of(context).size.height * 0.4,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            color: readerTheme.chromeBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Typography',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: AppFontSizes.options.map((size) {
                    final selected = selectedSize == size;
                    return GestureDetector(
                      onTap: () async {
                        final prefs = await ref.read(
                          sharedPreferencesProvider.future,
                        );
                        await prefs.setDouble('font_size', size);
                        if (context.mounted) Navigator.of(sheetContext).pop();
                      },
                      child: Column(
                        children: [
                          Text(
                            'A',
                            style: TextStyle(
                              fontSize: size,
                              color: readerTheme.pageText,
                              fontFamily: ReaderTypography.bookerly,
                              fontFamilyFallback:
                                  ReaderTypography.serifFallbacks,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 24,
                            height: 1.5,
                            color: selected
                                ? readerTheme.accent
                                : Colors.transparent,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: ReaderColorMode.values.map((mode) {
                    final selected = mode == selectedMode;
                    final color = switch (mode) {
                      ReaderColorMode.sepia => ReaderColors.sepiaBackground,
                      ReaderColorMode.white => ReaderColors.whiteBackground,
                      ReaderColorMode.dark => ReaderColors.darkBackground,
                    };
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(readerColorModeProvider.notifier)
                            .setMode(mode),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? readerTheme.accent
                                  : readerTheme.divider,
                              width: selected ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: ReaderTypography.pickerOptions.map((font) {
                      final selected = font == selectedFont;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          font,
                          style: TextStyle(
                            fontFamily: font,
                            fontFamilyFallback: ReaderTypography.serifFallbacks,
                            color: readerTheme.pageText,
                          ),
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color: readerTheme.accent,
                                size: 18,
                              )
                            : null,
                        onTap: () => ref
                            .read(readerFontFamilyProvider.notifier)
                            .setFontFamily(font),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTocDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (routeContext, animation, secondaryAnimation) => TocScreen(
          book: book,
          onChapterSelected: (chapterIndex) =>
              notifier.goToChapter(chapterIndex),
        ),
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    ),
                child: child,
              );
            },
      ),
    );
  }

  void _showHighlightsDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (routeContext, animation, secondaryAnimation) =>
            HighlightsScreen(
              bookId: book.id,
              onHighlightTap: (highlight) {
                _goToHighlight(highlight, book, notifier);
                Navigator.of(routeContext).pop();
              },
            ),
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    ),
                child: child,
              );
            },
      ),
    );
  }

  void _goToHighlight(
    Highlight highlight,
    ParsedBook book,
    ReaderController notifier,
  ) {
    final chapterIndex = highlight.chapterIndex.clamp(
      0,
      book.chapters.length - 1,
    );
    final plainText = HighlightService.extractPlainText(
      book.chapters[chapterIndex].htmlContent,
    );

    var offset = highlight.startOffset;
    if (offset <= 0 && highlight.content.trim().isNotEmpty) {
      final foundIndex = plainText.indexOf(highlight.content.trim());
      if (foundIndex >= 0) offset = foundIndex;
    }

    final fraction = plainText.isEmpty
        ? 0.0
        : offset.clamp(0, plainText.length) / plainText.length;
    notifier.goToChapterFraction(chapterIndex, fraction);
  }

  void _showHighlightOptionsSheet(BuildContext context, String highlightId) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change color',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final entry in [
                        ('yellow', readerTheme.highlightYellow),
                        ('blue', readerTheme.highlightBlue),
                        ('pink', readerTheme.highlightPink),
                        ('orange', readerTheme.highlightOrange),
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
              title: const Text(
                'Delete highlight',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                await ref
                    .read(highlightRepoProvider)
                    .deleteHighlight(highlightId);
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
    ReaderState state,
  ) async {
    if (text.isEmpty) return;
    final plainText = HighlightService.extractPlainText(
      book.chapters[chapterIdx].htmlContent,
    );
    final pageStart = state.totalPages > 0
        ? ((state.currentPage / state.totalPages) * plainText.length).round()
        : 0;
    var startOffset = plainText.indexOf(text, pageStart);
    if (startOffset < 0) startOffset = plainText.indexOf(text);
    if (startOffset < 0) startOffset = pageStart.clamp(0, plainText.length);

    final companion = HighlightsCompanion.insert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookId: book.id,
      chapterIndex: chapterIdx,
      startOffset: startOffset,
      endOffset: (startOffset + text.length).clamp(0, plainText.length),
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
      book.id,
      chapterIdx,
      state.currentPage,
    );
    if (alreadyBookmarked) {
      await repo.deleteBookmarkForPage(book.id, chapterIdx, state.currentPage);
    } else {
      final plainText = HighlightService.extractPlainText(chapter.htmlContent);
      final startChar = state.totalPages > 1
          ? ((state.currentPage / state.totalPages) * plainText.length).round()
          : 0;
      final snippet = plainText
          .substring(startChar.clamp(0, plainText.length))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final trimmed = snippet.length > 80 ? snippet.substring(0, 80) : snippet;
      await repo.addBookmark(
        BookmarksCompanion.insert(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          bookId: book.id,
          chapterIndex: chapterIdx,
          pageInChapter: state.currentPage,
          snippet: trimmed,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  void _showBookmarksDialog(
    BuildContext context,
    ParsedBook book,
    ReaderController notifier,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (routeContext, animation, secondaryAnimation) =>
            BookmarksScreen(
              bookId: book.id,
              chapters: book.chapters,
              onBookmarkTap: (chapterIndex, pageInChapter) {
                notifier.goToChapter(chapterIndex);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  notifier.goToPage(pageInChapter);
                });
                Navigator.of(routeContext).pop();
              },
            ),
        transitionsBuilder:
            (routeContext, animation, secondaryAnimation, child) {
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    ),
                child: child,
              );
            },
      ),
    );
  }
}

class _BookmarkRibbon extends StatelessWidget {
  const _BookmarkRibbon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(24, 40), painter: _RibbonPainter());
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

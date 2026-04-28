import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/preferences.dart';
import '../../data/db/database.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/repositories/highlight_repository.dart';
import '../../data/services/epub_service.dart';
import '../../data/services/highlight_service.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../highlights/highlights_screen.dart';
import '../../core/theme.dart';

class ReadiumReaderScreen extends ConsumerStatefulWidget {
  const ReadiumReaderScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.filePath,
    required this.initialChapterIndex,
    required this.initialPageInChapter,
    required this.initialProgressPercent,
  });

  final String bookId;
  final String bookTitle;
  final String filePath;
  final int initialChapterIndex;
  final int initialPageInChapter;
  final double initialProgressPercent;

  @override
  ConsumerState<ReadiumReaderScreen> createState() => _ReadiumReaderScreenState();
}

class _ReadiumReaderScreenState extends ConsumerState<ReadiumReaderScreen> {
  static const _channel = MethodChannel('com.example.epub_reader_poc/readium');

  bool _launching = true;
  String? _error;
  late int _chapterIndex;
  late int _pageInChapter;
  late double _progressPercent;

  ParsedBook? _cachedParsedBook;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.initialChapterIndex;
    _pageInChapter = widget.initialPageInChapter;
    _progressPercent = widget.initialProgressPercent;
    _channel.setMethodCallHandler(_handleNativeMethodCall);
    _openReadiumAtCurrentPosition();
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != 'onReadiumPositionChanged' &&
        call.method != 'onReadiumToolbarAction' &&
        call.method != 'onReadiumHighlightCreated') {
      return;
    }

    final args = Map<String, dynamic>.from(call.arguments as Map<dynamic, dynamic>);
    final payloadBookId = (args['bookId'] as String?) ?? '';
    if (payloadBookId != widget.bookId) return;

    final chapterIndex = (args['chapterIndex'] as num?)?.toInt() ?? 0;
    final pageInChapter = (args['pageInChapter'] as num?)?.toInt() ?? 0;
    final progressPercent = (args['progressPercent'] as num?)?.toDouble() ?? 0.0;

    _chapterIndex = chapterIndex;
    _pageInChapter = pageInChapter;
    _progressPercent = progressPercent;

    if (call.method == 'onReadiumHighlightCreated') {
      await _addHighlightFromNative(args);
      return;
    }

    if (call.method == 'onReadiumToolbarAction') {
      final action = (args['action'] as String?) ?? '';
      await _handleToolbarAction(action);
      return;
    }

    await ref
        .read(bookRepoProvider)
        .updateLastPosition(widget.bookId, chapterIndex, pageInChapter, progressPercent);
  }

  Future<void> _addHighlightFromNative(Map<String, dynamic> args) async {
    final chapterIndex = (args['chapterIndex'] as num?)?.toInt() ?? _chapterIndex;
    final color = ((args['color'] as String?) ?? 'yellow').toLowerCase();
    final text = (args['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return;

    final nowId = DateTime.now().millisecondsSinceEpoch.toString();
    await ref.read(highlightRepoProvider).addHighlight(
      HighlightsCompanion.insert(
        id: nowId,
        bookId: widget.bookId,
        chapterIndex: chapterIndex,
        startOffset: 0,
        endOffset: text.length,
        content: text,
        color: color,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _handleToolbarAction(String action) async {
    switch (action) {
      case 'bookmark':
        await _toggleBookmark();
        break;
      case 'bookmark_add':
        await _ensureBookmarkPresent();
        break;
      case 'bookmark_remove':
        await _ensureBookmarkRemoved();
        break;
      case 'bookmarks':
        _runAfterNativeDismiss(_showBookmarksDialog);
        break;
      case 'highlights':
        _runAfterNativeDismiss(_showHighlightsDialog);
        break;
      case 'display':
        _runAfterNativeDismiss(_showTypographySheet);
        break;
      default:
        break;
    }
  }

  void _runAfterNativeDismiss(Future<void> Function() action) {
    Future<void>.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      await action();
    });
  }

  Future<ParsedBook> _loadParsedBook() async {
    if (_cachedParsedBook != null) return _cachedParsedBook!;
    final dbBook = await ref.read(bookRepoProvider).getBookById(widget.bookId);
    final parsed = await ref.read(epubServiceProvider).reparseFromDisk(dbBook);
    _cachedParsedBook = parsed;
    return parsed;
  }

  Future<void> _ensureBookmarkPresent() async {
    final chapterIdx = _chapterIndex;
    final page = _pageInChapter;
    final alreadyBookmarked = await ref
        .read(bookmarkRepoProvider)
        .isPageBookmarked(widget.bookId, chapterIdx, page);
    if (alreadyBookmarked) return;

    final parsed = await _loadParsedBook();
    final chapterIdxSafe = chapterIdx.clamp(0, parsed.chapters.length - 1);
    final chapter = parsed.chapters[chapterIdxSafe];
    final plainText = HighlightService.extractPlainText(chapter.htmlContent);
    final snippet = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final trimmed = snippet.isEmpty
        ? 'Chapter ${chapterIdxSafe + 1}'
        : (snippet.length > 80 ? snippet.substring(0, 80) : snippet);

    await ref.read(bookmarkRepoProvider).addBookmark(
      BookmarksCompanion.insert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bookId: widget.bookId,
        chapterIndex: chapterIdx,
        pageInChapter: page,
        snippet: trimmed,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _ensureBookmarkRemoved() async {
    await ref
        .read(bookmarkRepoProvider)
        .deleteBookmarkForPage(widget.bookId, _chapterIndex, _pageInChapter);
  }

  Future<void> _toggleBookmark() async {
    final alreadyBookmarked = await ref
        .read(bookmarkRepoProvider)
        .isPageBookmarked(widget.bookId, _chapterIndex, _pageInChapter);
    if (alreadyBookmarked) {
      await _ensureBookmarkRemoved();
      return;
    }
    await _ensureBookmarkPresent();
  }

  Future<void> _showBookmarksDialog() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FutureBuilder<ParsedBook>(
          future: _loadParsedBook(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Scaffold(
                appBar: AppBar(leading: const CloseButton()),
                body: Center(child: Text('Could not load bookmarks: ${snapshot.error}')),
              );
            }

            final book = snapshot.data!;
            return BookmarksScreen(
              bookId: widget.bookId,
              chapters: book.chapters,
              onBookmarkTap: (chapterIndex, pageInChapter) {
                Navigator.of(context).pop();
                _chapterIndex = chapterIndex;
                _pageInChapter = pageInChapter;
              },
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    await _openReadiumAtCurrentPosition();
  }

  Future<void> _showHighlightsDialog() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HighlightsScreen(
          bookId: widget.bookId,
          onHighlightTap: (highlight) {
            Navigator.of(context).pop();
            _chapterIndex = highlight.chapterIndex;
            _pageInChapter = 0;
          },
        ),
      ),
    );
    if (!mounted) return;
    await _openReadiumAtCurrentPosition();
  }

  Future<void> _showTypographySheet() async {
    await showModalBottomSheet<void>(
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
            height: MediaQuery.of(context).size.height * 0.45,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            color: readerTheme.chromeBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Display',
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
    if (!mounted) return;
    await _openReadiumAtCurrentPosition();
  }

  Future<void> _openReadiumAtCurrentPosition() async {
    if (!mounted) return;
    setState(() {
      _launching = true;
      _error = null;
    });

    final isMobileTarget =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobileTarget) {
      setState(() {
        _launching = false;
        _error = 'Readium native reader is available only on Android and iOS.';
      });
      return;
    }

    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final fontSize = prefs.getDouble('font_size') ?? AppFontSizes.medium;
      final colorMode =
          ref.read(readerColorModeProvider).valueOrNull ?? ReaderColorMode.sepia;
      final fontFamily =
          ref.read(readerFontFamilyProvider).valueOrNull ?? ReaderTypography.bookerly;

      await _channel.invokeMethod<void>('openReadium', {
        'bookId': widget.bookId,
        'title': widget.bookTitle,
        'filePath': widget.filePath,
        'initialChapterIndex': _chapterIndex,
        'initialPageInChapter': _pageInChapter,
        'initialProgressPercent': _progressPercent,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'colorMode': colorMode.name,
      });
      if (!mounted) return;
      setState(() {
        _launching = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.message ?? 'Could not open the native Readium reader.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = 'Could not open the native Readium reader.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return Scaffold(
      backgroundColor: readerTheme.pageBackground,
      appBar: AppBar(title: Text(widget.bookTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _launching
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Opening Readium reader...'),
                  ],
                )
              : _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new, size: 36),
                    const SizedBox(height: 12),
                    const Text(
                      'Readium reader opened natively.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use native menu for bookmark, highlights, and display settings.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                  ],
                ),
        ),
      ),
    );
  }
}

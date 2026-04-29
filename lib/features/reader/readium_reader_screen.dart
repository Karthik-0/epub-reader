import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
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
  double? _chapterFraction;
  String? _initialLocatorJson;
  String? _currentLocatorJson;
  String? _nativeBookmarkSnippet;

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
    _currentLocatorJson = args['locatorJson'] as String?;

    _chapterIndex = chapterIndex;
    _pageInChapter = pageInChapter;
    _progressPercent = progressPercent;

    if (call.method == 'onReadiumHighlightCreated') {
      await _addHighlightFromNative(args);
      return;
    }

    if (call.method == 'onReadiumToolbarAction') {
      final action = (args['action'] as String?) ?? '';
      // Cache the native snippet captured from the WebView at bookmark time
      if (action == 'bookmark' || action == 'bookmark_add') {
        _nativeBookmarkSnippet = (args['snippetText'] as String?)?.trim();
      }
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
    final text = (args['text'] as String?)?.trim() ?? 'Highlighted text';
    final content = text.isEmpty ? 'Highlighted text' : text;

    int startOffset = 0;
    int endOffset = text.length;
    try {
      final parsed = await _loadParsedBook();
      final chapterIdx = chapterIndex.clamp(0, parsed.chapters.length - 1);
      final chapterPlain = HighlightService.extractPlainText(
        parsed.chapters[chapterIdx].htmlContent,
      );
      final found = chapterPlain.indexOf(content);
      if (found >= 0) {
        startOffset = found;
        endOffset = (found + content.length).clamp(0, chapterPlain.length);
      }
    } catch (_) {
      // Keep defaults if we fail to parse chapter text.
    }

    final nowId = DateTime.now().millisecondsSinceEpoch.toString();
    final repo = ref.read(highlightRepoProvider);
    try {
      await repo.addHighlight(
        HighlightsCompanion.insert(
          id: nowId,
          bookId: widget.bookId,
          chapterIndex: chapterIndex,
          startOffset: startOffset,
          endOffset: endOffset,
          content: content,
          color: color,
          progressPercent: Value((args['progressPercent'] as num?)?.toDouble()),
          locatorJson: Value(args['locatorJson'] as String?),
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      await repo.addHighlight(
        HighlightsCompanion.insert(
          id: nowId,
          bookId: widget.bookId,
          chapterIndex: chapterIndex,
          startOffset: startOffset,
          endOffset: endOffset,
          content: content,
          color: color,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<String> _buildHighlightsJson() async {
    final parsed = await _loadParsedBook();
    final highlights = await ref
        .read(highlightRepoProvider)
        .getHighlightsForBookOnce(widget.bookId);

    final payload = <Map<String, dynamic>>[];
    for (final h in highlights) {
      final chapterIndex = h.chapterIndex.clamp(0, parsed.chapters.length - 1);
      final plainText = HighlightService.extractPlainText(
        parsed.chapters[chapterIndex].htmlContent,
      );

      int offset = h.startOffset;
      if (offset <= 0 && h.content.trim().isNotEmpty) {
        final found = plainText.indexOf(h.content.trim());
        if (found >= 0) {
          offset = found;
        }
      }
      final fraction = plainText.isEmpty
          ? 0.0
          : (offset.clamp(0, plainText.length) / plainText.length)
                .toDouble()
                .clamp(0.0, 1.0);

      payload.add({
        'id': h.id,
        'chapterIndex': chapterIndex,
        'fraction': fraction,
        'color': h.color,
        'locatorJson': h.locatorJson,
      });
    }

    return jsonEncode(payload);
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

    var trimmed = 'Chapter ${chapterIdx + 1}';
    try {
      // 1. Use snippet captured directly from native WebView (most accurate)
      final nativeSnippet = _sanitizeSnippet(_nativeBookmarkSnippet ?? '');
      if (nativeSnippet.isNotEmpty) {
        trimmed = nativeSnippet;
      } else {
        // 2. Fall back to locator text context (populated for selection-based positions)
        final fromLocator = _extractSnippetFromLocatorJson(_currentLocatorJson);
        if (fromLocator != null && fromLocator.isNotEmpty) {
          trimmed = fromLocator;
        } else {
          // 3. Last resort: chapter text with progression offset
          final parsed = await _loadParsedBook();
          final chapterIdxSafe = chapterIdx.clamp(0, parsed.chapters.length - 1);
          final chapter = parsed.chapters[chapterIdxSafe];
          final chapterText = _extractReadableTextFromHtml(chapter.htmlContent);
          final chapterProgression = _extractChapterProgressionFromLocatorJson(
            _currentLocatorJson,
          );
          final sanitized = chapterProgression == null
              ? _sanitizeSnippet(chapterText)
              : _snippetAroundProgression(chapterText, chapterProgression);
          trimmed = sanitized.isEmpty ? 'Chapter ${chapterIdxSafe + 1}' : sanitized;
        }
      }
    } catch (_) {
      // Keep fallback chapter snippet if parsing fails.
    } finally {
      _nativeBookmarkSnippet = null;
    }

    final repo = ref.read(bookmarkRepoProvider);
    final nowId = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await repo.addBookmark(
        BookmarksCompanion.insert(
          id: nowId,
          bookId: widget.bookId,
          chapterIndex: chapterIdx,
          pageInChapter: page,
          snippet: trimmed,
          progressPercent: Value(_progressPercent),
          locatorJson: Value(_currentLocatorJson),
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      await repo.addBookmark(
        BookmarksCompanion.insert(
          id: nowId,
          bookId: widget.bookId,
          chapterIndex: chapterIdx,
          pageInChapter: page,
          snippet: trimmed,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  String? _extractSnippetFromLocatorJson(String? locatorJson) {
    if (locatorJson == null || locatorJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(locatorJson);
      if (decoded is! Map) return null;
      final text = decoded['text'];
      if (text is! Map) return null;

      final after = _sanitizeSnippet((text['after'] as String?) ?? '');
      if (after.isNotEmpty) return after;

      final highlight = _sanitizeSnippet((text['highlight'] as String?) ?? '');
      if (highlight.isNotEmpty) return highlight;

      final before = (text['before'] as String?) ?? '';
      if (before.isNotEmpty) {
        final beforeParts = before.split(RegExp(r'[.!?]\s+'));
        final tail = beforeParts.isEmpty ? before : beforeParts.last;
        final sanitizedTail = _sanitizeSnippet(tail);
        if (sanitizedTail.isNotEmpty) return sanitizedTail;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _extractReadableTextFromHtml(String html) {
    final headTag = RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true);
    final styleTag = RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true);
    final scriptTag = RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true);
    final htmlTag = RegExp(r'<[^>]+>', caseSensitive: false, dotAll: true);
    return html
      .replaceAll(headTag, ' ')
      .replaceAll(styleTag, ' ')
      .replaceAll(scriptTag, ' ')
      .replaceAll(htmlTag, ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  String _sanitizeSnippet(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '';

    final chunks = normalized.split(RegExp(r'(?<=[.!?])\s+|;'));
    for (final raw in chunks) {
      final chunk = raw.trim();
      if (chunk.isEmpty) continue;
      final lower = chunk.toLowerCase();
      final looksLikeCss = RegExp(
        r'^(@page|@media|@font-face|margin\b|padding\b|font\b|line-height\b|body\s*\{|\{|\})',
      ).hasMatch(lower);
      if (looksLikeCss) continue;
      return chunk.length > 120 ? '${chunk.substring(0, 120).trimRight()}…' : chunk;
    }

    return normalized.length > 120
        ? '${normalized.substring(0, 120).trimRight()}…'
        : normalized;
  }

  double? _extractChapterProgressionFromLocatorJson(String? locatorJson) {
    if (locatorJson == null || locatorJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(locatorJson);
      if (decoded is! Map) return null;
      final locations = decoded['locations'];
      if (locations is! Map) return null;
      final progression = locations['progression'];
      if (progression is num) {
        return progression.toDouble().clamp(0.0, 1.0);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _snippetAroundProgression(String chapterText, double progression) {
    final normalized = chapterText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '';

    // progression is the chapter-fraction at the START of the current page,
    // so we extract text starting from that position forwards only.
    final start = (normalized.length * progression)
        .round()
        .clamp(0, normalized.length - 1);

    // Find the first word boundary at or after `start` to avoid mid-word cuts.
    int wordStart = start;
    while (wordStart < normalized.length && normalized[wordStart] == ' ') {
      wordStart++;
    }

    final end = (wordStart + 260).clamp(0, normalized.length);
    final segment = normalized.substring(wordStart, end);
    return _sanitizeSnippet(segment);
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
              onBookmarkSelected: (bookmark) {
                _progressPercent = bookmark.progressPercent ?? _progressPercent;
                _initialLocatorJson = bookmark.locatorJson;
              },
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
    final parsed = await _loadParsedBook();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HighlightsScreen(
          bookId: widget.bookId,
          onHighlightTap: (highlight) {
            Navigator.of(context).pop();
            _chapterIndex = highlight.chapterIndex.clamp(
              0,
              parsed.chapters.length - 1,
            );
            _pageInChapter = 0;
            _progressPercent = highlight.progressPercent ?? _progressPercent;
            _initialLocatorJson = highlight.locatorJson;
            _chapterFraction = _computeChapterFraction(highlight, parsed);
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
        final highlightsJson = await _buildHighlightsJson();

      await _channel.invokeMethod<void>('openReadium', {
        'bookId': widget.bookId,
        'title': widget.bookTitle,
        'filePath': widget.filePath,
        'initialChapterIndex': _chapterIndex,
        'initialPageInChapter': _pageInChapter,
        'initialProgressPercent': _progressPercent,
        'initialChapterFraction': _chapterFraction,
        'initialLocatorJson': _initialLocatorJson,
        'highlightsJson': highlightsJson,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'colorMode': colorMode.name,
      });
      _chapterFraction = null;
      _initialLocatorJson = null;
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
      _chapterFraction = null;
      _initialLocatorJson = null;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = 'Could not open the native Readium reader.';
      });
      _chapterFraction = null;
      _initialLocatorJson = null;
    }
  }

  double _computeChapterFraction(Highlight highlight, ParsedBook book) {
    final chapterIndex = highlight.chapterIndex.clamp(0, book.chapters.length - 1);
    final plainText = HighlightService.extractPlainText(
      book.chapters[chapterIndex].htmlContent,
    );

    var offset = highlight.startOffset;
    if (offset <= 0 && highlight.content.trim().isNotEmpty) {
      final foundIndex = plainText.indexOf(highlight.content.trim());
      if (foundIndex >= 0) {
        offset = foundIndex;
      }
    }

    if (plainText.isEmpty) return 0.0;
    return (offset.clamp(0, plainText.length) / plainText.length)
        .toDouble()
        .clamp(0.0, 1.0);
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

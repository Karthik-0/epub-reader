import 'dart:io';
import 'package:epubx/epubx.dart' as epubx;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final epubServiceProvider = Provider((ref) => EpubService());

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
  final String htmlContent;
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

    // 3. Extract cover using raw bytes from content (preserves original format)
    final coverPath = await _extractCover(book, booksDir.path, id);

    // 4. Pre-compute href → chapter index map (needed for TOC mapping)
    final readingOrder = book.Schema?.Package?.Spine?.Items ?? [];
    final hrefToIndex = _buildHrefToIndexMap(book, readingOrder);

    // 5. Extract chapters in spine order
    final chapters = _extractChapters(book, readingOrder);

    // 6. Build TOC with correct chapter indices
    final toc = _buildToc(book, hrefToIndex);

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

  /// Re-parse an already-imported EPUB from disk, using the DB record for metadata.
  Future<ParsedBook> reparseFromDisk(Book dbBook) async {
    final file = File(dbBook.filePath);
    if (!file.existsSync()) {
      throw Exception(
          'EPUB file not found: ${dbBook.filePath}\n\n'
          'The file may have been deleted or moved. '
          'Try reimporting the book.');
    }
    final bytes = await file.readAsBytes();
    final book = await epubx.EpubReader.readBook(bytes);

    final readingOrder = book.Schema?.Package?.Spine?.Items ?? [];
    final hrefToIndex = _buildHrefToIndexMap(book, readingOrder);
    final chapters = _extractChapters(book, readingOrder);
    final toc = _buildToc(book, hrefToIndex);

    return ParsedBook(
      id: dbBook.id,
      title: book.Title ?? dbBook.title,
      author: book.Author ?? dbBook.author,
      coverPath: dbBook.coverPath,
      filePath: dbBook.filePath,
      chapters: chapters,
      toc: toc,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts cover using raw bytes — EPUB2 meta → EPUB3 properties → filename fallback.
  Future<String?> _extractCover(
      epubx.EpubBook book, String dirPath, String id) async {
    try {
      String? coverItemId;

      // EPUB2: <meta name="cover" content="item-id"/>
      final metaItems = book.Schema?.Package?.Metadata?.MetaItems;
      if (metaItems != null) {
        for (final meta in metaItems) {
          if (meta.Name?.toLowerCase() == 'cover') {
            coverItemId = meta.Content;
            break;
          }
        }
      }

      // EPUB3: <item properties="cover-image"/>
      if (coverItemId == null) {
        final manifestItems = book.Schema?.Package?.Manifest?.Items;
        if (manifestItems != null) {
          for (final item in manifestItems) {
            if (item.Properties?.contains('cover-image') == true) {
              coverItemId = item.Id;
              break;
            }
          }
        }
      }

      // Resolve item ID → href
      String? coverHref;
      if (coverItemId != null) {
        final manifestItems = book.Schema?.Package?.Manifest?.Items;
        if (manifestItems != null) {
          for (final item in manifestItems) {
            if (item.Id == coverItemId) {
              coverHref = item.Href;
              break;
            }
          }
        }
      }

      if (coverHref != null) {
        final result = await _writeCoverBytes(book, coverHref, dirPath, id);
        if (result != null) return result;
      }

      // Fallback: search images by filename containing "cover"
      final images = book.Content?.Images;
      if (images != null) {
        for (final entry in images.entries) {
          if (entry.key.toLowerCase().contains('cover')) {
            final result = await _writeCoverBytes(book, entry.key, dirPath, id);
            if (result != null) return result;
          }
        }
      }
    } catch (_) {
      // Cover extraction is best-effort; continue without one
    }
    return null;
  }

  Future<String?> _writeCoverBytes(
      epubx.EpubBook book, String href, String dirPath, String id) async {
    final bytes = book.Content?.Images?[href]?.Content;
    if (bytes == null || bytes.isEmpty) return null;
    final lowerHref = href.toLowerCase();
    final ext = (lowerHref.endsWith('.jpg') || lowerHref.endsWith('.jpeg'))
        ? 'jpg'
        : 'png';
    final coverFile = File(p.join(dirPath, '$id-cover.$ext'));
    await coverFile.writeAsBytes(bytes);
    return coverFile.path;
  }

  /// Builds a map of spine href filename (without fragment) → chapter index.
  Map<String, int> _buildHrefToIndexMap(
      epubx.EpubBook book, List<epubx.EpubSpineItemRef> readingOrder) {
    final map = <String, int>{};
    int idx = 0;
    for (final spineItem in readingOrder) {
      final manifestItem = book.Schema?.Package?.Manifest?.Items?.firstWhere(
        (m) => m.Id == spineItem.IdRef,
        orElse: () => epubx.EpubManifestItem(),
      );
      final href = manifestItem?.Href;
      if (href != null) {
        final filename = p.basename(href.split('#').first);
        map[filename] = idx++;
      }
    }
    return map;
  }

  List<ChapterContent> _extractChapters(
      epubx.EpubBook book, List<epubx.EpubSpineItemRef> readingOrder) {
    final chapters = <ChapterContent>[];
    int idx = 0;
    for (final spineItem in readingOrder) {
      final manifestItem = book.Schema?.Package?.Manifest?.Items?.firstWhere(
        (m) => m.Id == spineItem.IdRef,
        orElse: () => epubx.EpubManifestItem(),
      );
      if (manifestItem == null || manifestItem.Id == null) continue;
      final href = manifestItem.Href;
      final contentFile = book.Content?.Html?[href];
      if (contentFile == null) continue;
      chapters.add(ChapterContent(
        index: idx++,
        title: 'Chapter $idx',
        htmlContent: contentFile.Content ?? '',
      ));
    }
    return chapters;
  }

  List<TocEntry> _buildToc(
      epubx.EpubBook book, Map<String, int> hrefToIndex) {
    final toc = <TocEntry>[];
    final navPoints = book.Schema?.Navigation?.NavMap?.Points ?? [];
    for (final np in navPoints) {
      final label = np.NavigationLabels?.isNotEmpty == true
          ? np.NavigationLabels!.first.Text ?? ''
          : '';
      final source = np.Content?.Source ?? '';
      // TODO: improve TOC fragment handling for section-level nav
      final filename = p.basename(source.split('#').first);
      final chapterIndex = hrefToIndex[filename] ?? 0;
      toc.add(TocEntry(title: label, chapterIndex: chapterIndex));
    }
    return toc;
  }
}

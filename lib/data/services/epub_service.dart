import 'dart:io';
import 'package:epubx/epubx.dart' as epubx;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          ?.firstWhere((m) => m.Id == spineItem.IdRef, orElse: () => epubx.EpubManifestItem());
      if (manifestItem == null || manifestItem.Id == null) continue;
      final href = manifestItem.Href;
      final contentFile = book.Content?.Html?[href];
      if (contentFile == null) continue;
      chapters.add(ChapterContent(
        index: idx++,
        title: 'Chapter $idx',  // will be overridden by TOC if available
        htmlContent: contentFile.Content ?? '',
      ));
    }

    // 5. Build TOC
    final toc = <TocEntry>[];
    final navPoints = book.Schema?.Navigation?.NavMap?.Points ?? [];
    for (final np in navPoints) {
      // map nav point to chapter index by matching href (simplified)
      final label = np.NavigationLabels?.isNotEmpty == true ? np.NavigationLabels!.first.Text ?? '' : '';
      toc.add(TocEntry(title: label, chapterIndex: 0));
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

  Future<ParsedBook> reparseFromDisk(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final book = await epubx.EpubReader.readBook(bytes);

    final chapters = <ChapterContent>[];
    final readingOrder = book.Schema?.Package?.Spine?.Items ?? [];
    int idx = 0;
    for (final spineItem in readingOrder) {
      final manifestItem = book.Schema?.Package?.Manifest?.Items
          ?.firstWhere((m) => m.Id == spineItem.IdRef, orElse: () => epubx.EpubManifestItem());
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

    final toc = <TocEntry>[];
    final navPoints = book.Schema?.Navigation?.NavMap?.Points ?? [];
    for (final np in navPoints) {
      final label = np.NavigationLabels?.isNotEmpty == true ? np.NavigationLabels!.first.Text ?? '' : '';
      toc.add(TocEntry(title: label, chapterIndex: 0));
    }

    return ParsedBook(
      id: p.basenameWithoutExtension(filePath),
      title: book.Title ?? 'Untitled',
      author: book.Author,
      filePath: filePath,
      chapters: chapters,
      toc: toc,
    );
  }
}

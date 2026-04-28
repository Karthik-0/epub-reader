import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/book_repository.dart';
import '../../reader/readium_reader_screen.dart';

class BookTile extends ConsumerWidget {
  final Book book;
  const BookTile({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return GestureDetector(
      onLongPress: () => _showDeleteDialog(context, ref),
      onTap: () async {
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (c) => ReadiumReaderScreen(
              bookId: book.id,
              bookTitle: book.title,
              filePath: book.filePath,
              initialChapterIndex: book.lastChapterIndex,
              initialPageInChapter: book.lastPageInChapter,
              initialProgressPercent: book.progressPercent,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: ReaderColors.libraryShadow,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: book.coverPath != null && File(book.coverPath!).existsSync()
                  ? Image.file(
                      File(book.coverPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, Object error, StackTrace? st) => Container(
                        color: readerTheme.divider,
                        child: Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: readerTheme.secondaryText,
                        ),
                      ),
                    )
                  : Container(
                      color: readerTheme.divider,
                      child: Icon(
                        Icons.menu_book_outlined,
                        size: 48,
                        color: readerTheme.secondaryText,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 14,
                        color: readerTheme.pageText,
                      ),
                ),
                if (book.author != null)
                  Text(
                    book.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: readerTheme.secondaryText,
                        ),
                  ),
                if (book.progressPercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(
                      value: book.progressPercent / 100,
                      minHeight: 2,
                      backgroundColor:
                          readerTheme.divider.withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        readerTheme.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Book'),
        content: Text('Are you sure you want to delete "${book.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(bookRepoProvider).deleteBook(book.id);
              if (book.coverPath != null && File(book.coverPath!).existsSync()) {
                File(book.coverPath!).deleteSync();
              }
              if (File(book.filePath).existsSync()) {
                File(book.filePath).deleteSync();
              }
              Navigator.pop(c);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
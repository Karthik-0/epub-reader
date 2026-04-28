import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/book_repository.dart';
import '../../reader/reader_screen.dart';

class BookTile extends ConsumerWidget {
  final Book book;
  const BookTile({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: () => _showDeleteDialog(context, ref),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (c) => ReaderScreen(bookId: book.id),
        ));
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: book.coverPath != null
                  ? Image.file(File(book.coverPath!), fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(Icons.book, size: 50, color: Colors.grey),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (book.author != null)
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (book.progressPercent > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(
                        value: book.progressPercent / 100,
                        minHeight: 3,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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

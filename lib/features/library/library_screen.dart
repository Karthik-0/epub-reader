import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'library_controller.dart';
import '../../data/services/epub_service.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/db/database.dart';
import '../reader/reader_screen.dart';
import 'dart:io';
import 'package:drift/drift.dart' as drift;

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsyncValue = ref.watch(libraryStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: booksAsyncValue.when(
        data: (books) {
          if (books.isEmpty) {
            return const Center(child: Text('No books yet — tap + to add one'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return BookTile(book: book);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndImportEpub(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _pickAndImportEpub(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      
      // Show loading dialog
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        final service = ref.read(epubServiceProvider);
        final parsedBook = await service.importEpub(path);
        
        final bookRepo = ref.read(bookRepoProvider);
        await bookRepo.addBook(BooksCompanion(
          id: drift.Value(parsedBook.id),
          title: drift.Value(parsedBook.title),
          author: drift.Value(parsedBook.author),
          coverPath: drift.Value(parsedBook.coverPath),
          filePath: drift.Value(parsedBook.filePath),
          addedAt: drift.Value(DateTime.now()),
        ));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importing: $e')));
        }
      } finally {
        if (context.mounted) {
          Navigator.of(context).pop(); // dismiss dialog
        }
      }
    }
  }
}

class BookTile extends ConsumerWidget {
  final Book book;
  const BookTile({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: () {
        // Show delete option
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete Book'),
            content: Text('Are you sure you want to delete ${book.title}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
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
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onTap: () {
        // Navigate to ReaderScreen
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
              child: book.coverPath != null
                  ? Image.file(File(book.coverPath!), fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey[300],
                      child: const Center(child: Icon(Icons.book, size: 50, color: Colors.grey)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (book.author != null) Text(book.author!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

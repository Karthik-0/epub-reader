import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/services/epub_service.dart';
import 'library_controller.dart';
import 'widgets/book_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsyncValue = ref.watch(libraryStreamProvider);
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 900 ? 4 : 2;

    return Scaffold(
      backgroundColor: readerTheme.pageBackground,
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'Library',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search is not implemented yet.')),
              );
            },
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: () => _pickAndImportEpub(context, ref),
            icon: const Icon(Icons.add),
            tooltip: 'Add book',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add') {
                _pickAndImportEpub(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'add',
                child: Text('Add Book'),
              ),
            ],
          ),
        ],
      ),
      body: booksAsyncValue.when(
        data: (books) {
          if (books.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No books yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add an EPUB from the top bar to start reading.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
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


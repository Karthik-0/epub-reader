import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'library_controller.dart';
import '../../data/services/epub_service.dart';
import '../../data/repositories/book_repository.dart';
import '../../data/db/database.dart';
import 'widgets/book_tile.dart';
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


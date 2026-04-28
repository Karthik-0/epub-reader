import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/database.dart';
import '../../data/repositories/book_repository.dart';

final libraryStreamProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(bookRepoProvider).getAllBooks();
});

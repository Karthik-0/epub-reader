import 'package:flutter/material.dart';
import '../../data/services/epub_service.dart';

class TocScreen extends StatelessWidget {
  final ParsedBook book;
  final Function(int chapterIndex) onChapterSelected;

  const TocScreen({
    super.key,
    required this.book,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Table of Contents'),
        leading: const CloseButton(),
      ),
      body: book.toc.isEmpty
          ? const Center(child: Text('No chapters found'))
          : ListView.builder(
              itemCount: book.toc.length,
              itemBuilder: (context, index) {
                final entry = book.toc[index];
                return ListTile(
                  title: Text(entry.title),
                  subtitle: Text('Chapter ${entry.chapterIndex + 1}'),
                  onTap: () {
                    onChapterSelected(entry.chapterIndex);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }
}

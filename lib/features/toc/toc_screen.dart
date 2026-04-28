import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
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
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return Scaffold(
      backgroundColor: readerTheme.pageBackground,
      appBar: AppBar(
        title: const Text('Contents'),
        leading: const CloseButton(),
      ),
      body: book.toc.isEmpty
          ? Center(
              child: Text(
                'No chapters found',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: book.toc.length,
                separatorBuilder: (context, index) =>
                  Divider(color: readerTheme.divider, height: 1),
              itemBuilder: (context, index) {
                final entry = book.toc[index];
                return InkWell(
                  onTap: () {
                    onChapterSelected(entry.chapterIndex);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'Chapter ${entry.chapterIndex + 1}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontFamily: ReaderTypography.bookerly,
                                  fontFamilyFallback: ReaderTypography.serifFallbacks,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

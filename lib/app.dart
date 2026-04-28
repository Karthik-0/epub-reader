import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants.dart';
import 'core/preferences.dart';
import 'core/theme.dart';
import 'features/library/library_screen.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerMode =
        ref.watch(readerColorModeProvider).valueOrNull ?? ReaderColorMode.sepia;
    return MaterialApp(
      title: 'EPUB Reader POC',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(readerMode),
      home: const LibraryScreen(),
    );
  }
}

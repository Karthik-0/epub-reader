import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/library/library_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPUB Reader POC',
      theme: AppTheme.lightTheme,
      home: const LibraryScreen(),
    );
  }
}

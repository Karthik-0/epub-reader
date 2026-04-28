import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  final String bookId;
  const ReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: Center(child: Text('Reading $bookId')),
    );
  }
}

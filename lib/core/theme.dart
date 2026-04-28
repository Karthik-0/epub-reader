import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: AppColors.readingBackground,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            color: AppColors.readingText,
            fontSize: AppFontSizes.medium,
            height: 1.6,
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.readingBackgroundDark,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            color: AppColors.readingTextDark,
            fontSize: AppFontSizes.medium,
            height: 1.6,
          ),
        ),
      );
}

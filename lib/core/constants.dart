import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Reading mode — light
  static const Color readingBackground = Color(0xFFFBF6E9);
  static const Color readingText = Color(0xFF2A2A2A);

  // Reading mode — dark
  static const Color readingBackgroundDark = Color(0xFF1A1A1A);
  static const Color readingTextDark = Color(0xFFD8D4CC);

  // Highlight colors
  static const Color highlightYellow = Color(0xFFFFF59D);
  static const Color highlightGreen = Color(0xFFC5E1A5);
  static const Color highlightPink = Color(0xFFF8BBD0);
}

class AppFontSizes {
  AppFontSizes._();

  static const double small = 14.0;
  static const double medium = 17.0;
  static const double large = 20.0;
}

class AppDimensions {
  AppDimensions._();

  static const double pageHorizontalPadding = 16.0;
  static const double pageVerticalPadding = 16.0;
}

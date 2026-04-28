import 'package:flutter/material.dart';

enum ReaderColorMode { sepia, white, dark }

class ReaderColors {
  ReaderColors._();

  static const Color sepiaBackground = Color(0xFFFBF0D9);
  static const Color sepiaText = Color(0xFF3A2E1F);
  static const Color sepiaSecondary = Color(0xFF7A6A53);
  static const Color sepiaDivider = Color(0xFFE8DCC0);
  static const Color sepiaChrome = Color(0xFFF5E9D0);
  static const Color sepiaAccent = Color(0xFF1A1A1A);

  static const Color whiteBackground = Color(0xFFFFFFFF);
  static const Color whiteText = Color(0xFF1A1A1A);
  static const Color whiteSecondary = Color(0xFF6B6B6B);
  static const Color whiteDivider = Color(0xFFE7E1D8);
  static const Color whiteChrome = Color(0xFFF7F3ED);
  static const Color whiteAccent = Color(0xFF1A1A1A);

  static const Color darkBackground = Color(0xFF1A1A1A);
  static const Color darkText = Color(0xFFD8D4CC);
  static const Color darkSecondary = Color(0xFF8A8680);
  static const Color darkDivider = Color(0xFF2F2C27);
  static const Color darkChrome = Color(0xFF24211D);
  static const Color darkAccent = Color(0xFFD4B97C);

  static const Color highlightYellow = Color(0xFFFFE9A8);
  static const Color highlightBlue = Color(0xFFBFD7FF);
  static const Color highlightPink = Color(0xFFF4C0D9);
  static const Color highlightOrange = Color(0xFFF6D1A5);

  static const Color libraryShadow = Color(0x26000000);
}

class ReaderTypography {
  ReaderTypography._();

  static const String bookerly = 'Bookerly';
  static const String georgia = 'Georgia';
  static const List<String> serifFallbacks = <String>[
    'Georgia',
    'Times New Roman',
    'Times',
    'Noto Serif',
  ];
  static const List<String> pickerOptions = <String>[
    'Bookerly',
    'Georgia',
    'Times New Roman',
    'Noto Serif',
  ];
}

class AppFontSizes {
  AppFontSizes._();

  static const double small = 14.0;
  static const double medium = 17.0;
  static const double large = 20.0;
  static const double extraLarge = 23.0;
  static const List<double> options = <double>[14.0, 17.0, 20.0, 23.0];

  static const double chapterTitle = 28.0;
  static const double libraryTitle = 20.0;
  static const double uiLabel = 14.0;
  static const double secondaryLabel = 12.0;
  static const double status = 11.0;
}

class AppDimensions {
  AppDimensions._();

  static const double phonePageHorizontalPadding = 24.0;
  static const double tabletPageHorizontalPadding = 64.0;
  static const double pageTopMargin = 28.0;
  static const double pageBottomMargin = 20.0;
  static const double readingAreaTopPadding = 32.0;
  static const double readingAreaBottomPadding = 16.0;

  static const double chromeTopHeight = 56.0;
  static const double chromeBottomHeight = 74.0;
  static const double statusStripHeight = 24.0;
  static const double progressHeight = 2.0;

  static const double libraryGutter = 16.0;
  static const double libraryGridPhoneColumns = 2.0;
  static const double libraryGridTabletColumns = 4.0;

  static double readerHorizontalPadding(double width) {
    return width >= 700
        ? tabletPageHorizontalPadding
        : phonePageHorizontalPadding;
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';

@immutable
class ReaderTheme extends ThemeExtension<ReaderTheme> {
  final ReaderColorMode mode;
  final Color pageBackground;
  final Color pageText;
  final Color secondaryText;
  final Color divider;
  final Color accent;
  final Color chromeBackground;
  final Color highlightYellow;
  final Color highlightBlue;
  final Color highlightPink;
  final Color highlightOrange;
  final double lineHeight;
  final double chapterTopMargin;
  final double chapterTitleSize;
  final double statusStripHeight;
  final SystemUiOverlayStyle overlayStyle;

  const ReaderTheme({
    required this.mode,
    required this.pageBackground,
    required this.pageText,
    required this.secondaryText,
    required this.divider,
    required this.accent,
    required this.chromeBackground,
    required this.highlightYellow,
    required this.highlightBlue,
    required this.highlightPink,
    required this.highlightOrange,
    required this.lineHeight,
    required this.chapterTopMargin,
    required this.chapterTitleSize,
    required this.statusStripHeight,
    required this.overlayStyle,
  });

  bool get isDark => mode == ReaderColorMode.dark;

  double horizontalPageMargin(double width) {
    return AppDimensions.readerHorizontalPadding(width);
  }

  @override
  ReaderTheme copyWith({
    ReaderColorMode? mode,
    Color? pageBackground,
    Color? pageText,
    Color? secondaryText,
    Color? divider,
    Color? accent,
    Color? chromeBackground,
    Color? highlightYellow,
    Color? highlightBlue,
    Color? highlightPink,
    Color? highlightOrange,
    double? lineHeight,
    double? chapterTopMargin,
    double? chapterTitleSize,
    double? statusStripHeight,
    SystemUiOverlayStyle? overlayStyle,
  }) {
    return ReaderTheme(
      mode: mode ?? this.mode,
      pageBackground: pageBackground ?? this.pageBackground,
      pageText: pageText ?? this.pageText,
      secondaryText: secondaryText ?? this.secondaryText,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      chromeBackground: chromeBackground ?? this.chromeBackground,
      highlightYellow: highlightYellow ?? this.highlightYellow,
      highlightBlue: highlightBlue ?? this.highlightBlue,
      highlightPink: highlightPink ?? this.highlightPink,
      highlightOrange: highlightOrange ?? this.highlightOrange,
      lineHeight: lineHeight ?? this.lineHeight,
      chapterTopMargin: chapterTopMargin ?? this.chapterTopMargin,
      chapterTitleSize: chapterTitleSize ?? this.chapterTitleSize,
      statusStripHeight: statusStripHeight ?? this.statusStripHeight,
      overlayStyle: overlayStyle ?? this.overlayStyle,
    );
  }

  @override
  ReaderTheme lerp(covariant ThemeExtension<ReaderTheme>? other, double t) {
    if (other is! ReaderTheme) return this;
    return ReaderTheme(
      mode: t < 0.5 ? mode : other.mode,
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      pageText: Color.lerp(pageText, other.pageText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      chromeBackground: Color.lerp(chromeBackground, other.chromeBackground, t)!,
      highlightYellow: Color.lerp(highlightYellow, other.highlightYellow, t)!,
      highlightBlue: Color.lerp(highlightBlue, other.highlightBlue, t)!,
      highlightPink: Color.lerp(highlightPink, other.highlightPink, t)!,
      highlightOrange: Color.lerp(highlightOrange, other.highlightOrange, t)!,
      lineHeight: lerpDouble(lineHeight, other.lineHeight, t)!,
      chapterTopMargin: lerpDouble(chapterTopMargin, other.chapterTopMargin, t)!,
      chapterTitleSize: lerpDouble(chapterTitleSize, other.chapterTitleSize, t)!,
      statusStripHeight: lerpDouble(statusStripHeight, other.statusStripHeight, t)!,
      overlayStyle: t < 0.5 ? overlayStyle : other.overlayStyle,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData themeFor(ReaderColorMode mode) {
    final readerTheme = _readerThemeFor(mode);
    final isDark = readerTheme.isDark;
    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: readerTheme.accent,
      onPrimary: readerTheme.pageBackground,
      secondary: readerTheme.accent,
      onSecondary: readerTheme.pageBackground,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      surface: readerTheme.chromeBackground,
      onSurface: readerTheme.pageText,
      tertiary: readerTheme.secondaryText,
      onTertiary: readerTheme.pageBackground,
      surfaceContainerHighest: readerTheme.chromeBackground,
      onSurfaceVariant: readerTheme.secondaryText,
      outline: readerTheme.divider,
      shadow: ReaderColors.libraryShadow,
      scrim: Colors.black26,
      inverseSurface: readerTheme.pageText,
      onInverseSurface: readerTheme.pageBackground,
      inversePrimary: readerTheme.accent,
    );

    final baseBody = TextStyle(
      color: readerTheme.pageText,
      fontSize: AppFontSizes.medium,
      height: readerTheme.lineHeight,
      fontFamily: ReaderTypography.bookerly,
      fontFamilyFallback: ReaderTypography.serifFallbacks,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: readerTheme.pageBackground,
      dividerColor: readerTheme.divider,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: readerTheme.accent,
        selectionColor: readerTheme.accent.withValues(alpha: 0.18),
        selectionHandleColor: readerTheme.secondaryText,
      ),
      textTheme: TextTheme(
        bodyMedium: baseBody,
        bodyLarge: baseBody.copyWith(fontSize: AppFontSizes.large),
        bodySmall: TextStyle(
          color: readerTheme.secondaryText,
          fontSize: AppFontSizes.secondaryLabel,
          height: 1.35,
        ),
        titleLarge: baseBody.copyWith(
          fontSize: AppFontSizes.libraryTitle,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseBody.copyWith(
          fontSize: AppFontSizes.chapterTitle,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          color: readerTheme.pageText,
          fontSize: AppFontSizes.uiLabel,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: readerTheme.secondaryText,
          fontSize: AppFontSizes.uiLabel,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconTheme: IconThemeData(color: readerTheme.pageText),
      appBarTheme: AppBarTheme(
        backgroundColor: readerTheme.chromeBackground,
        foregroundColor: readerTheme.pageText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: readerTheme.pageText,
          fontSize: AppFontSizes.libraryTitle,
          fontWeight: FontWeight.w600,
          fontFamily: ReaderTypography.bookerly,
          fontFamilyFallback: ReaderTypography.serifFallbacks,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: readerTheme.chromeBackground,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(
          color: readerTheme.pageText,
          fontSize: AppFontSizes.uiLabel,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: readerTheme.chromeBackground,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: readerTheme.chromeBackground,
        surfaceTintColor: Colors.transparent,
      ),
      extensions: <ThemeExtension<dynamic>>[readerTheme],
    );
  }

  static ReaderTheme _readerThemeFor(ReaderColorMode mode) {
    switch (mode) {
      case ReaderColorMode.white:
        return const ReaderTheme(
          mode: ReaderColorMode.white,
          pageBackground: ReaderColors.whiteBackground,
          pageText: ReaderColors.whiteText,
          secondaryText: ReaderColors.whiteSecondary,
          divider: ReaderColors.whiteDivider,
          accent: ReaderColors.whiteAccent,
          chromeBackground: ReaderColors.whiteChrome,
          highlightYellow: ReaderColors.highlightYellow,
          highlightBlue: ReaderColors.highlightBlue,
          highlightPink: ReaderColors.highlightPink,
          highlightOrange: ReaderColors.highlightOrange,
          lineHeight: 1.55,
          chapterTopMargin: AppDimensions.pageTopMargin,
          chapterTitleSize: AppFontSizes.chapterTitle,
          statusStripHeight: AppDimensions.statusStripHeight,
          overlayStyle: SystemUiOverlayStyle.dark,
        );
      case ReaderColorMode.dark:
        return const ReaderTheme(
          mode: ReaderColorMode.dark,
          pageBackground: ReaderColors.darkBackground,
          pageText: ReaderColors.darkText,
          secondaryText: ReaderColors.darkSecondary,
          divider: ReaderColors.darkDivider,
          accent: ReaderColors.darkAccent,
          chromeBackground: ReaderColors.darkChrome,
          highlightYellow: ReaderColors.highlightYellow,
          highlightBlue: ReaderColors.highlightBlue,
          highlightPink: ReaderColors.highlightPink,
          highlightOrange: ReaderColors.highlightOrange,
          lineHeight: 1.55,
          chapterTopMargin: AppDimensions.pageTopMargin,
          chapterTitleSize: AppFontSizes.chapterTitle,
          statusStripHeight: AppDimensions.statusStripHeight,
          overlayStyle: SystemUiOverlayStyle.light,
        );
      case ReaderColorMode.sepia:
        return const ReaderTheme(
          mode: ReaderColorMode.sepia,
          pageBackground: ReaderColors.sepiaBackground,
          pageText: ReaderColors.sepiaText,
          secondaryText: ReaderColors.sepiaSecondary,
          divider: ReaderColors.sepiaDivider,
          accent: ReaderColors.sepiaAccent,
          chromeBackground: ReaderColors.sepiaChrome,
          highlightYellow: ReaderColors.highlightYellow,
          highlightBlue: ReaderColors.highlightBlue,
          highlightPink: ReaderColors.highlightPink,
          highlightOrange: ReaderColors.highlightOrange,
          lineHeight: 1.55,
          chapterTopMargin: AppDimensions.pageTopMargin,
          chapterTitleSize: AppFontSizes.chapterTitle,
          statusStripHeight: AppDimensions.statusStripHeight,
          overlayStyle: SystemUiOverlayStyle.dark,
        );
    }
  }
}

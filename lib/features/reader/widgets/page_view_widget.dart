import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/services/highlight_service.dart';

/// Renders a single page of a chapter by clipping and translating the
/// full chapter HTML to the correct vertical slice.
///
/// Page [pageIndex] shows the region:
///   [pageIndex * pageHeight, (pageIndex + 1) * pageHeight]
class ChapterPageWidget extends StatelessWidget {
  final String htmlContent;
  final int pageIndex;
  final double pageHeight;
  final double pageWidth;
  final double fontSize;
  final String fontFamily;

  /// Called when the user taps a highlighted span. The argument is the
  /// highlight's database id.
  final void Function(String highlightId)? onHighlightTap;

  const ChapterPageWidget({
    super.key,
    required this.htmlContent,
    required this.pageIndex,
    required this.pageHeight,
    required this.pageWidth,
    required this.fontSize,
    required this.fontFamily,
    this.onHighlightTap,
  });

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    final verticalBleed = pageVerticalBleed(fontSize, readerTheme.lineHeight);
    final contentStep = effectiveContentStep(
      pageHeight,
      verticalBleed,
      fontSize,
      readerTheme.lineHeight,
    );

    return ClipRect(
      child: SizedBox(
        height: pageHeight,
        width: pageWidth,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalBleed),
          child: SizedBox(
            height: contentStep,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              maxWidth: pageWidth,
              child: Transform.translate(
                offset: Offset(0, -(pageIndex * contentStep)),
                child: Padding(
                  padding: pagePaddingFor(readerTheme, pageWidth),
                  child: Html(
                    data: htmlContent,
                    style: buildHtmlStyle(
                      textColor: readerTheme.pageText,
                      codeBackground: readerTheme.chromeBackground,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
                      lineHeight: readerTheme.lineHeight,
                    ),
                    extensions: [
                      _buildMarkExtension(textColor: readerTheme.pageText),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Custom extension that renders `<mark data-highlight-id="..." data-color="...">` as
  /// a colored, tappable inline text span.
  ///
  /// Using [TagExtension.inline] with a [TextSpan] + [TapGestureRecognizer] so the
  /// tap fires correctly even inside a [SelectionArea] (GestureDetector children
  /// inside SelectionArea are swallowed by the selection machinery, but text-level
  /// recognizers are handled by the RichText layout independently).
  TagExtension _buildMarkExtension({required Color textColor}) {
    return TagExtension.inline(
      tagsToExtend: {'mark'},
      builder: (extContext) {
        final id = extContext.attributes['data-highlight-id'] ?? '';
        final colorName = extContext.attributes['data-color'] ?? 'yellow';
        final text = extContext.element?.text ?? '';
        final bgColor = Color(
          HighlightService.hexToColorInt(
            HighlightService.colorToHex(colorName),
          ),
        );

        return TextSpan(
          text: text,
          recognizer: (id.isNotEmpty && onHighlightTap != null)
              ? (TapGestureRecognizer()..onTap = () => onHighlightTap!.call(id))
              : null,
          style: TextStyle(
            backgroundColor: bgColor,
            fontSize: fontSize,
            fontFamily: fontFamily,
            fontFamilyFallback: ReaderTypography.serifFallbacks,
            color: textColor,
            height: 1.55,
          ),
        );
      },
    );
  }

  static EdgeInsets pagePaddingFor(ReaderTheme readerTheme, double pageWidth) {
    final horizontalPadding = readerTheme.horizontalPageMargin(pageWidth);
    return EdgeInsets.fromLTRB(
      horizontalPadding,
      readerTheme.chapterTopMargin,
      horizontalPadding,
      AppDimensions.pageBottomMargin,
    );
  }

  static double pageVerticalBleed(double fontSize, double lineHeight) {
    final linePixels = fontSize * lineHeight;
    return (linePixels * 0.22).clamp(4.0, 10.0);
  }

  static double effectiveContentStep(
    double pageHeight,
    double verticalBleed,
    double fontSize,
    double lineHeight,
  ) {
    final availableHeight = (pageHeight - (verticalBleed * 2)).clamp(
      1.0,
      double.infinity,
    );
    final linePixels = (fontSize * lineHeight).clamp(1.0, double.infinity);
    final fullLines = (availableHeight / linePixels).floor();
    if (fullLines <= 0) return availableHeight;
    return fullLines * linePixels;
  }

  static Map<String, Style> buildHtmlStyle({
    required Color textColor,
    required Color codeBackground,
    required double fontSize,
    required String fontFamily,
    required double lineHeight,
  }) => {
    'body': Style(
      fontSize: FontSize(fontSize),
      lineHeight: LineHeight(lineHeight),
      color: textColor,
      textAlign: TextAlign.justify,
      fontFamily: fontFamily,
      margin: Margins.zero,
      padding: HtmlPaddings.zero,
    ),
    'p': Style(
      margin: Margins.zero,
      textAlign: TextAlign.justify,
      fontFamily: fontFamily,
    ),
    'h1': Style(
      fontSize: FontSize(AppFontSizes.chapterTitle),
      fontWeight: FontWeight.bold,
      textAlign: TextAlign.center,
      margin: Margins.only(bottom: 24),
      fontFamily: fontFamily,
      color: textColor,
    ),
    'h2': Style(
      fontSize: FontSize(fontSize * 1.2),
      fontWeight: FontWeight.bold,
      fontFamily: fontFamily,
      color: textColor,
    ),
    'h3': Style(
      fontSize: FontSize(fontSize * 1.1),
      fontWeight: FontWeight.bold,
      fontFamily: fontFamily,
      color: textColor,
    ),
    'img': Style(display: Display.block, width: Width.auto()),
    'pre': Style(
      fontSize: FontSize(fontSize * 0.8),
      backgroundColor: codeBackground,
      padding: HtmlPaddings.all(8),
    ),
    'code': Style(
      fontSize: FontSize(fontSize * 0.85),
      backgroundColor: codeBackground,
    ),
    'a': Style(color: const Color(0xFF1565C0)),
  };
}

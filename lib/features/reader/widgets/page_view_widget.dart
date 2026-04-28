import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../../core/constants.dart';
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
    this.onHighlightTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.readingTextDark : AppColors.readingText;
    final codeBackground = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEEEEEE);
    return ClipRect(
      child: SizedBox(
        height: pageHeight,
        width: pageWidth,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          maxWidth: pageWidth,
          child: Transform.translate(
            offset: Offset(0, -(pageIndex * pageHeight)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.pageHorizontalPadding),
              child: Html(
                data: htmlContent,
                style: _buildStyle(textColor: textColor, codeBackground: codeBackground),
                extensions: [
                  _buildMarkExtension(textColor: textColor),
                ],
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
            HighlightService.hexToColorInt(HighlightService.colorToHex(colorName)));

        return TextSpan(
          text: text,
          recognizer: (id.isNotEmpty && onHighlightTap != null)
              ? (TapGestureRecognizer()..onTap = () => onHighlightTap!.call(id))
              : null,
          style: TextStyle(
            backgroundColor: bgColor,
            fontSize: fontSize,
            color: textColor,
            height: 1.6,
          ),
        );
      },
    );
  }

  Map<String, Style> _buildStyle({
    required Color textColor,
    required Color codeBackground,
  }) =>
      {
        'body': Style(
          fontSize: FontSize(fontSize),
          lineHeight: LineHeight(1.6),
          color: textColor,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'p': Style(margin: Margins.only(bottom: 12)),
        'h1': Style(
            fontSize: FontSize(fontSize * 1.4),
            fontWeight: FontWeight.bold,
            color: textColor),
        'h2': Style(
            fontSize: FontSize(fontSize * 1.2),
            fontWeight: FontWeight.bold,
            color: textColor),
        'h3': Style(
            fontSize: FontSize(fontSize * 1.1),
            fontWeight: FontWeight.bold,
            color: textColor),
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

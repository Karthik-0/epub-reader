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
                style: _buildStyle(),
                extensions: [
                  _buildMarkExtension(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Custom extension that renders `<mark data-highlight-id="..." data-color="...">` as
  /// a colored, tappable inline widget.
  TagExtension _buildMarkExtension() {
    return TagExtension(
      tagsToExtend: {'mark'},
      builder: (extContext) {
        final id = extContext.attributes['data-highlight-id'] ?? '';
        final colorName = extContext.attributes['data-color'] ?? 'yellow';
        final text = extContext.element?.text ?? '';
        final bgColor =
            Color(HighlightService.hexToColorInt(HighlightService.colorToHex(colorName)));

        return GestureDetector(
          onTap: id.isNotEmpty ? () => onHighlightTap?.call(id) : null,
          child: Container(
            color: bgColor,
            child: Text(
              text,
              style: TextStyle(
                fontSize: fontSize,
                color: AppColors.readingText,
                height: 1.6,
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, Style> _buildStyle() => {
        'body': Style(
          fontSize: FontSize(fontSize),
          lineHeight: LineHeight(1.6),
          color: AppColors.readingText,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'p': Style(margin: Margins.only(bottom: 12)),
        'h1': Style(fontSize: FontSize(fontSize * 1.4), fontWeight: FontWeight.bold),
        'h2': Style(fontSize: FontSize(fontSize * 1.2), fontWeight: FontWeight.bold),
        'h3': Style(fontSize: FontSize(fontSize * 1.1), fontWeight: FontWeight.bold),
        'img': Style(display: Display.block, width: Width.auto()),
        'pre': Style(
          fontSize: FontSize(fontSize * 0.8),
          backgroundColor: const Color(0xFFEEEEEE),
          padding: HtmlPaddings.all(8),
        ),
        'code': Style(
          fontSize: FontSize(fontSize * 0.85),
          backgroundColor: const Color(0xFFEEEEEE),
        ),
        // Strip link styles that don't apply in offline context
        'a': Style(color: const Color(0xFF1565C0)),
      };
}

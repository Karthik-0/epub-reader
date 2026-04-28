import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// Static helpers for page count calculation.
class PaginationEngine {
  PaginationEngine._();

  /// Returns the number of pages a chapter occupies.
  static int computePageCount(double totalHeight, double pageHeight) {
    if (pageHeight <= 0 || totalHeight <= 0) return 1;
    return (totalHeight / pageHeight).ceil().clamp(1, 100000);
  }
}

// ---------------------------------------------------------------------------
// Off-screen measurer
// ---------------------------------------------------------------------------

/// Renders [htmlContent] off-screen at [width] to measure its natural height,
/// then fires [onHeightMeasured] with the result.
///
/// Give this widget a [ValueKey] keyed on chapter index + font size so Flutter
/// fully rebuilds it (and re-fires measurement) when either changes.
class HtmlHeightMeasurer extends StatefulWidget {
  final String htmlContent;
  final double width;
  final double fontSize;
  final void Function(double height) onHeightMeasured;

  const HtmlHeightMeasurer({
    super.key,
    required this.htmlContent,
    required this.width,
    required this.fontSize,
    required this.onHeightMeasured,
  });

  @override
  State<HtmlHeightMeasurer> createState() => _HtmlHeightMeasurerState();
}

class _HtmlHeightMeasurerState extends State<HtmlHeightMeasurer> {
  final _key = GlobalKey();
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void didUpdateWidget(HtmlHeightMeasurer old) {
    super.didUpdateWidget(old);
    if (old.htmlContent != widget.htmlContent ||
        old.fontSize != widget.fontSize ||
        old.width != widget.width) {
      _measured = false;
      WidgetsBinding.instance.addPostFrameCallback(_measure);
    }
  }

  void _measure(Duration _) {
    if (_measured || !mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _measured = true;
      widget.onHeightMeasured(box.size.height);
    } else {
      // Layout not ready yet — retry next frame
      WidgetsBinding.instance.addPostFrameCallback(_measure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      child: SizedBox(
        key: _key,
        width: widget.width,
        child: Html(
          data: widget.htmlContent,
          style: _htmlStyle(widget.fontSize),
        ),
      ),
    );
  }

  static Map<String, Style> _htmlStyle(double fontSize) => {
        'body': Style(
          fontSize: FontSize(fontSize),
          lineHeight: LineHeight(1.6),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'p': Style(margin: Margins.only(bottom: 12)),
        'img': Style(display: Display.block, width: Width.auto()),
        'pre': Style(
          fontSize: FontSize(fontSize * 0.8),
          padding: HtmlPaddings.all(8),
        ),
      };
}

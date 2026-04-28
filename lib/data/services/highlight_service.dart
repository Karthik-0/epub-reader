import '../db/database.dart';

class HighlightService {
  /// Simple highlight injection - for now, just return the HTML as-is.
  /// The highlights will be tracked in the database and displayed separately.
  /// A full implementation would need sophisticated DOM manipulation.
  static String injectHighlights(
    String chapterHtml,
    List<Highlight> highlights,
  ) {
    if (highlights.isEmpty) return chapterHtml;
    // TODO: Implement sophisticated highlight injection using package:html
    // For now, highlights are tracked in DB and shown via UI overlays
    return chapterHtml;
  }

  /// Extracts plain text from HTML (for computing offsets during selection)
  static String extractPlainText(String htmlContent) {
    try {
      // Simple regex to remove HTML tags
      return htmlContent.replaceAll(RegExp(r'<[^>]*>'), '');
    } catch (e) {
      return htmlContent;
    }
  }

  /// Converts color name to hex code for future HTML injection
  static String colorToHex(String color) {
    switch (color.toLowerCase()) {
      case 'yellow':
        return '#fff59d';
      case 'green':
        return '#c5e1a5';
      case 'pink':
        return '#f8bbd0';
      default:
        return '#fff59d';
    }
  }
}

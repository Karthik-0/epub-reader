import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../db/database.dart';

class HighlightService {
  /// Injects highlight spans into chapter HTML.
  ///
  /// For each [Highlight] whose content is found as a text run in the DOM,
  /// the text node is split and wrapped in a `<mark>` element:
  ///   `<mark data-highlight-id="{id}" data-color="{color}">text</mark>`
  ///
  /// The [ChapterPageWidget] renders `<mark>` via a custom [TagExtension]
  /// that applies the background color and calls [onHighlightTap] on tap.
  static String injectHighlights(
    String chapterHtml,
    List<Highlight> highlights,
  ) {
    if (highlights.isEmpty) return chapterHtml;

    final document = html_parser.parse(chapterHtml);
    final body = document.body;
    if (body == null) return chapterHtml;

    for (final highlight in highlights) {
      _injectIntoNode(body, highlight);
    }

    return document.outerHtml;
  }

  /// Walks [node]'s children looking for a text node containing
  /// [highlight.content]. Returns true when the injection succeeds so we
  /// stop after the first match (avoids double-highlighting).
  static bool _injectIntoNode(dom.Node node, Highlight highlight) {
    final children = node.nodes.toList(); // snapshot — we mutate during walk
    for (final child in children) {
      if (child is dom.Text) {
        final text = child.text;
        final idx = text.indexOf(highlight.content);
        if (idx < 0) continue;

        // Build replacement nodes: [before?, <mark>, after?]
        final before = text.substring(0, idx);
        final after = text.substring(idx + highlight.content.length);

        final mark = dom.Element.tag('mark');
        mark.attributes['data-highlight-id'] = highlight.id;
        mark.attributes['data-color'] = highlight.color;
        mark.append(dom.Text(highlight.content));

        final parent = child.parent!;
        final nodeIdx = parent.nodes.indexOf(child);
        parent.nodes.removeAt(nodeIdx);
        // Insert in reverse order so indices stay valid
        if (after.isNotEmpty) parent.nodes.insert(nodeIdx, dom.Text(after));
        parent.nodes.insert(nodeIdx, mark);
        if (before.isNotEmpty) parent.nodes.insert(nodeIdx, dom.Text(before));

        return true; // done for this highlight
      } else if (child is dom.Element) {
        final tag = child.localName ?? '';
        if (tag == 'script' || tag == 'style' || tag == 'mark') continue;
        if (_injectIntoNode(child, highlight)) return true;
      }
    }
    return false;
  }

  /// Extracts plain text from HTML (strips all tags).
  static String extractPlainText(String htmlContent) {
    return htmlContent.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Maps a color name to its highlight hex code.
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

  /// Parses a CSS hex color string (e.g. `#fff59d`) into a Dart [Color] int.
  static int hexToColorInt(String hex) {
    final clean = hex.replaceFirst('#', '');
    return int.parse('FF$clean', radix: 16);
  }
}

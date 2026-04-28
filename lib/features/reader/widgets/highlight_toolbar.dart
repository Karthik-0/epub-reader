import 'package:flutter/material.dart';

import '../../../core/theme.dart';

typedef HighlightColorCallback = Future<void> Function(String color);

class HighlightToolbar extends StatelessWidget {
  final HighlightColorCallback onHighlight;
  final VoidCallback onCancel;
  final VoidCallback? onNote;
  final VoidCallback? onShare;

  const HighlightToolbar({
    super.key,
    required this.onHighlight,
    required this.onCancel,
    this.onNote,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: readerTheme.chromeBackground,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final color in [
              ('yellow', readerTheme.highlightYellow),
              ('blue', readerTheme.highlightBlue),
              ('pink', readerTheme.highlightPink),
              ('orange', readerTheme.highlightOrange),
            ]) ...[
              _ColorButton(
                color: color.$2,
                onTap: () => _handleColorTap(color.$1),
              ),
              const SizedBox(width: 8),
            ],
            _ActionButton(
              icon: Icons.sticky_note_2_outlined,
              onTap: onNote,
            ),
            const SizedBox(width: 6),
            _ActionButton(
              icon: Icons.share_outlined,
              onTap: onShare,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleColorTap(String color) async {
    await onHighlight(color);
    onCancel();
  }
}

class _ColorButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: const Color(0x14000000), width: 1),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final readerTheme = Theme.of(context).extension<ReaderTheme>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: readerTheme.secondaryText),
      ),
    );
  }
}

import 'package:flutter/material.dart';

typedef HighlightColorCallback = Future<void> Function(String color);

class HighlightToolbar extends StatelessWidget {
  final String selectedText;
  final HighlightColorCallback onYellow;
  final HighlightColorCallback onGreen;
  final HighlightColorCallback onPink;
  final VoidCallback onCancel;

  const HighlightToolbar({
    super.key,
    required this.selectedText,
    required this.onYellow,
    required this.onGreen,
    required this.onPink,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected text preview (truncated)
            Text(
              selectedText.length > 50
                  ? '${selectedText.substring(0, 50)}...'
                  : selectedText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            // Color buttons and cancel
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ColorButton(
                  color: Colors.yellow[200]!,
                  onTap: () => _handleColorTap(onYellow, context),
                ),
                const SizedBox(width: 8),
                _ColorButton(
                  color: Colors.green[200]!,
                  onTap: () => _handleColorTap(onGreen, context),
                ),
                const SizedBox(width: 8),
                _ColorButton(
                  color: Colors.pink[100]!,
                  onTap: () => _handleColorTap(onPink, context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleColorTap(HighlightColorCallback callback, BuildContext context) async {
    await callback(selectedText);
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

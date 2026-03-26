import 'package:flutter/material.dart';

/// A single instrument display showing label, value, and unit.
class InstrumentTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const InstrumentTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.red.shade900 : Colors.blueGrey.shade200,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.red.shade300 : Colors.blueGrey,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: isDark ? Colors.red.shade100 : Colors.black87,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.red.shade400 : Colors.blueGrey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bus Color Picker Widget (P10.1.14)
///
/// Simple color selector for visual bus organization.
/// Provides 12 preset colors plus custom color option.

import 'package:flutter/material.dart';

/// Preset colors for buses (matches Logic Pro / Cubase style)
const busColorPresets = [
  Color(0xFF4A9EFF), // Blue
  Color(0xFF40C8FF), // Cyan
  Color(0xFF40FF90), // Green
  Color(0xFF8BC34A), // Light Green
  Color(0xFFFFD93D), // Yellow
  Color(0xFFFF9040), // Orange
  Color(0xFFFF6B6B), // Red
  Color(0xFFE91E63), // Pink
  Color(0xFF9B59B6), // Purple
  Color(0xFF673AB7), // Deep Purple
  Color(0xFF607D8B), // Blue Grey
  Color(0xFF795548), // Brown
];

/// A compact color picker for bus/channel colors
class BusColorPicker extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final bool showLabel;
  final double iconSize;

  const BusColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.showLabel = false,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Color>(
      tooltip: 'Channel Color',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
      offset: const Offset(0, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Colors.grey[500],
            ),
          ],
        ],
      ),
      itemBuilder: (context) => [
        PopupMenuItem<Color>(
          enabled: false,
          padding: const EdgeInsets.all(12),
          child: _ColorGrid(
            currentColor: currentColor,
            onColorSelected: (color) {
              onColorChanged(color);
              Navigator.pop(context);
            },
          ),
        ),
      ],
    );
  }
}

/// Grid of color swatches
class _ColorGrid extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  const _ColorGrid({
    required this.currentColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Color',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 200,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: busColorPresets.map((color) {
              final isSelected = _colorsMatch(currentColor, color);
              return _ColorSwatch(
                color: color,
                isSelected: isSelected,
                onTap: () => onColorSelected(color),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  bool _colorsMatch(Color a, Color b) {
    return a.value == b.value;
  }
}

/// Individual color swatch button
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Inline color picker for compact spaces (row of small swatches)
class BusColorPickerInline extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  final int maxColors;

  const BusColorPickerInline({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
    this.maxColors = 6,
  });

  @override
  Widget build(BuildContext context) {
    final displayColors = busColorPresets.take(maxColors).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...displayColors.map((color) {
          final isSelected = currentColor.value == color.value;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () => onColorChanged(color),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 1.5)
                      : null,
                ),
              ),
            ),
          );
        }),
        if (busColorPresets.length > maxColors)
          BusColorPicker(
            currentColor: currentColor,
            onColorChanged: onColorChanged,
            iconSize: 14,
          ),
      ],
    );
  }
}

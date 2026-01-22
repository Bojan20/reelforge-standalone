/// Shared Spatial Widgets — Reusable components for spatial UI
///
/// Components:
/// - SpatialSlider — Compact slider with label
/// - SpatialDropdown — Compact dropdown with label
/// - SpatialToggle — Toggle switch with label
/// - SpatialTextField — Text input with label

import 'package:flutter/material.dart';

/// Compact slider with label
class SpatialSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const SpatialSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white54 : Colors.white24,
                  fontSize: 9,
                ),
              ),
              const Spacer(),
              Text(
                _formatValue(value),
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white38,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor:
                  enabled ? const Color(0xFF4a9eff) : Colors.white24,
              inactiveTrackColor: const Color(0xFF2a2a35),
              thumbColor: enabled ? const Color(0xFF4a9eff) : Colors.white38,
              overlayColor: const Color(0xFF4a9eff).withValues(alpha: 0.2),
              disabledActiveTrackColor: Colors.white24,
              disabledInactiveTrackColor: const Color(0xFF1a1a20),
              disabledThumbColor: Colors.white24,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(double v) {
    if (max >= 100) {
      return v.toStringAsFixed(0);
    } else if (max >= 10) {
      return v.toStringAsFixed(1);
    } else {
      return v.toStringAsFixed(2);
    }
  }
}

/// Compact dropdown with label
class SpatialDropdown<T extends Enum> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;

  const SpatialDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
          const SizedBox(height: 4),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3a3a4a)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: const Color(0xFF242430),
                style: const TextStyle(color: Colors.white70, fontSize: 10),
                icon: const Icon(Icons.arrow_drop_down,
                    color: Colors.white38, size: 16),
                items: items.map((item) {
                  return DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      _formatEnumName(item.name),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatEnumName(String name) {
    // Convert camelCase to Title Case
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      if (i > 0 && name[i].toUpperCase() == name[i]) {
        buffer.write(' ');
      }
      buffer.write(i == 0 ? name[i].toUpperCase() : name[i]);
    }
    return buffer.toString();
  }
}

/// Toggle switch with label
class SpatialToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SpatialToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF40ff90).withValues(alpha: 0.15)
              : const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? const Color(0xFF40ff90).withValues(alpha: 0.3)
                : const Color(0xFF3a3a4a),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF40ff90) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: value ? const Color(0xFF40ff90) : Colors.white38,
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 8, color: Color(0xFF121216))
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: value ? const Color(0xFF40ff90) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text input with label
class SpatialTextField extends StatefulWidget {
  final String label;
  final String value;
  final String? hint;
  final ValueChanged<String> onChanged;

  const SpatialTextField({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    required this.onChanged,
  });

  @override
  State<SpatialTextField> createState() => _SpatialTextFieldState();
}

class _SpatialTextFieldState extends State<SpatialTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(SpatialTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                filled: true,
                fillColor: const Color(0xFF121216),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF3a3a4a)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF3a3a4a)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF4a9eff)),
                ),
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal meter/bar
class SpatialMeter extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final Color? backgroundColor;

  const SpatialMeter({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.color = const Color(0xFF4a9eff),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: backgroundColor ?? const Color(0xFF121216),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalizedValue,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bipolar meter (centered, goes left or right)
class SpatialPanMeter extends StatelessWidget {
  final String label;
  final double value; // -1 to +1

  const SpatialPanMeter({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(-1.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
              const Spacer(),
              Text(
                clampedValue < -0.01
                    ? 'L ${(-clampedValue * 100).toStringAsFixed(0)}%'
                    : clampedValue > 0.01
                        ? 'R ${(clampedValue * 100).toStringAsFixed(0)}%'
                        : 'C',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(3),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final centerX = constraints.maxWidth / 2;
                final barWidth = (clampedValue.abs() * centerX);
                final barLeft = clampedValue < 0 ? centerX - barWidth : centerX;

                return Stack(
                  children: [
                    // Center line
                    Positioned(
                      left: centerX - 0.5,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: Colors.white24,
                      ),
                    ),
                    // Value bar
                    Positioned(
                      left: barLeft,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: barWidth,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4a9eff),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header for grouping
class SpatialSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  const SpatialSectionHeader({
    super.key,
    required this.title,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white38, size: 12),
            const SizedBox(width: 6),
          ],
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: const Color(0xFF2a2a35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Info badge
class SpatialBadge extends StatelessWidget {
  final String label;
  final Color color;

  const SpatialBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

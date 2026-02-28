import 'package:flutter/material.dart';
import 'aurexis_theme.dart';

/// Compact horizontal slider for AUREXIS behavior parameters.
///
/// Shows: label ═══════●═══ value
/// Supports double-click reset, color-coded by group.
class AurexisBehaviorSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  final Color color;
  final double min;
  final double max;
  final String? valueFormat;

  const AurexisBehaviorSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onReset,
    this.color = AurexisColors.accent,
    this.min = 0.0,
    this.max = 1.0,
    this.valueFormat,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormat ?? value.toStringAsFixed(2);

    return SizedBox(
      height: AurexisDimens.paramRowHeight,
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 70,
            child: GestureDetector(
              onDoubleTap: onReset,
              child: Text(
                label,
                style: AurexisTextStyles.paramLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.0,
                activeTrackColor: color,
                inactiveTrackColor: AurexisColors.bgSlider,
                thumbColor: color,
                overlayColor: color.withValues(alpha: 0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          // Value
          SizedBox(
            width: 34,
            child: Text(
              displayValue,
              style: AurexisTextStyles.paramValue.copyWith(color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

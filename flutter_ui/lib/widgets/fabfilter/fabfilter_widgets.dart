/// FabFilter Shared Widgets — extracted from gate, limiter, reverb, compressor panels.
/// Eliminates ~400 LOC of duplication across 5 panels.
library;

import 'package:flutter/material.dart';
import 'fabfilter_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MINI BUTTON — 20×20 labeled toggle (A/B, Expert, etc.)
// ═══════════════════════════════════════════════════════════════════════════

class FabMiniButton extends StatelessWidget {
  const FabMiniButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.accentColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: active ? accentColor.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? accentColor : FabFilterColors.border),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: active ? accentColor : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        ))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TINY BUTTON — 20×16 smaller variant (enum selectors)
// ═══════════════════════════════════════════════════════════════════════════

class FabTinyButton extends StatelessWidget {
  const FabTinyButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 16,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.border),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: active ? color : FabFilterColors.textTertiary,
          fontSize: 7, fontWeight: FontWeight.bold,
        ))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT A/B TOGGLE — paired A/B buttons
// ═══════════════════════════════════════════════════════════════════════════

class FabCompactAB extends StatelessWidget {
  const FabCompactAB({
    super.key,
    required this.isStateB,
    required this.onToggle,
    required this.accentColor,
  });

  final bool isStateB;
  final VoidCallback onToggle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FabMiniButton(label: 'A', active: !isStateB, onTap: () { if (isStateB) onToggle(); }, accentColor: accentColor),
        const SizedBox(width: 2),
        FabMiniButton(label: 'B', active: isStateB, onTap: () { if (!isStateB) onToggle(); }, accentColor: accentColor),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT BYPASS — BYP toggle button
// ═══════════════════════════════════════════════════════════════════════════

class FabCompactBypass extends StatelessWidget {
  const FabCompactBypass({
    super.key,
    required this.bypassed,
    required this.onToggle,
  });

  final bool bypassed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bypassed ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: bypassed ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text('BYP', style: TextStyle(
          color: bypassed ? FabFilterColors.orange : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        )),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT TOGGLE — generic label toggle (SC, Freeze, etc.)
// ═══════════════════════════════════════════════════════════════════════════

class FabCompactToggle extends StatelessWidget {
  const FabCompactToggle({
    super.key,
    required this.label,
    required this.active,
    required this.onToggle,
    required this.color,
  });

  final String label;
  final bool active;
  final VoidCallback onToggle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          color: active ? color : FabFilterColors.textTertiary,
          fontSize: 9, fontWeight: FontWeight.bold,
        )),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OPTION ROW — checkbox toggle row (sidechain, audition, etc.)
// ═══════════════════════════════════════════════════════════════════════════

class FabOptionRow extends StatelessWidget {
  const FabOptionRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.accentColor,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: value ? accentColor.withValues(alpha: 0.15) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? accentColor.withValues(alpha: 0.5) : FabFilterColors.border),
        ),
        child: Row(
          children: [
            Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 9)),
            const Spacer(),
            Icon(value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: value ? accentColor : FabFilterColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI SLIDER — compact slider with label + value display
// ═══════════════════════════════════════════════════════════════════════════

class FabMiniSlider extends StatelessWidget {
  const FabMiniSlider({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    this.activeColor = FabFilterColors.cyan,
    this.labelWidth = 24,
    this.displayWidth = 24,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onChanged;
  final Color activeColor;
  final double labelWidth;
  final double displayWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: labelWidth, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: activeColor,
                inactiveTrackColor: FabFilterColors.bgVoid,
                thumbColor: activeColor,
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
          SizedBox(width: displayWidth, child: Text(display,
            style: FabFilterText.paramLabel.copyWith(fontSize: 8), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ENUM SELECTOR — tiny button row for selecting from options
// ═══════════════════════════════════════════════════════════════════════════

class FabEnumSelector extends StatelessWidget {
  const FabEnumSelector({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.color = FabFilterColors.cyan,
  });

  final String label;
  final int value;
  final List<String> options;
  final ValueChanged<int> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 8))),
          const SizedBox(width: 2),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(options.length, (i) => FabTinyButton(
                label: options[i],
                active: value == i,
                color: color,
                onTap: () => onChanged(i),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT HEADER ROW — panel title + A/B + Bypass + Expert + Close
// ═══════════════════════════════════════════════════════════════════════════

class FabCompactHeader extends StatelessWidget {
  const FabCompactHeader({
    super.key,
    required this.title,
    required this.accentColor,
    required this.isStateB,
    required this.onToggleAB,
    required this.bypassed,
    required this.onToggleBypass,
    required this.showExpert,
    required this.onToggleExpert,
    required this.onClose,
    this.statusWidget,
  });

  final String title;
  final Color accentColor;
  final bool isStateB;
  final VoidCallback onToggleAB;
  final bool bypassed;
  final VoidCallback onToggleBypass;
  final bool showExpert;
  final VoidCallback onToggleExpert;
  final VoidCallback onClose;
  final Widget? statusWidget;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(bottom: BorderSide(color: accentColor.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // Title
          Text(title, style: FabFilterText.sectionHeader.copyWith(
            color: accentColor, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 8),
          // Status (gate state, GR meter, etc.)
          if (statusWidget != null) ...[statusWidget!, const SizedBox(width: 8)],
          const Spacer(),
          // A/B toggle
          FabCompactAB(isStateB: isStateB, onToggle: onToggleAB, accentColor: accentColor),
          const SizedBox(width: 6),
          // Expert mode
          FabMiniButton(label: 'E', active: showExpert, onTap: onToggleExpert, accentColor: accentColor),
          const SizedBox(width: 6),
          // Bypass
          FabCompactBypass(bypassed: bypassed, onToggle: onToggleBypass),
          const SizedBox(width: 6),
          // Close
          GestureDetector(
            onTap: onClose,
            child: Icon(Icons.close, size: 14, color: FabFilterColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HORIZONTAL METER BAR — generic level/GR meter
// ═══════════════════════════════════════════════════════════════════════════

class FabHorizontalMeter extends StatelessWidget {
  const FabHorizontalMeter({
    super.key,
    required this.label,
    required this.value,
    this.maxValue = 1.0,
    this.color = FabFilterColors.cyan,
    this.warningColor = FabFilterColors.orange,
    this.clipColor = FabFilterColors.red,
    this.warningThreshold = 0.75,
    this.clipThreshold = 0.95,
    this.height = 12,
    this.showLabel = true,
    this.displayText,
    this.inverted = false,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final Color warningColor;
  final Color clipColor;
  final double warningThreshold;
  final double clipThreshold;
  final double height;
  final bool showLabel;
  final String? displayText;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final normalized = (value / maxValue).clamp(0.0, 1.0);
    final barColor = normalized >= clipThreshold ? clipColor
        : normalized >= warningThreshold ? warningColor
        : color;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (showLabel)
            SizedBox(width: 18, child: Text(label, style: FabFilterText.paramLabel.copyWith(fontSize: 7))),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: FabFilterColors.bgVoid,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: inverted ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: normalized,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          if (displayText != null)
            SizedBox(width: 30, child: Text(displayText!,
              style: FabFilterText.paramLabel.copyWith(fontSize: 7), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION LABEL — thin section header in options columns
// ═══════════════════════════════════════════════════════════════════════════

class FabSectionLabel extends StatelessWidget {
  const FabSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: FabFilterText.paramLabel.copyWith(
        fontSize: 7, color: color ?? FabFilterColors.textTertiary, letterSpacing: 0.8,
      )),
    );
  }
}

/// Glass Widgets Library
///
/// Reusable Liquid Glass UI components for FluxForge Studio.
/// All components follow macOS Tahoe glassmorphism design language.

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';

// ==============================================================================
// GLASS CONTAINER
// ==============================================================================

/// A frosted glass container with blur, tint, and specular highlights
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blurAmount;
  final double tintOpacity;
  final Color? tintColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showSpecular;
  final List<BoxShadow>? customShadow;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = LiquidGlassTheme.radiusLarge,
    this.blurAmount = LiquidGlassTheme.blurAmount,
    this.tintOpacity = 0.08,
    this.tintColor,
    this.padding,
    this.margin,
    this.showSpecular = true,
    this.customShadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTintColor = tintColor ?? Colors.white;

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: customShadow ?? LiquidGlassTheme.glassShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  effectiveTintColor.withValues(alpha: tintOpacity + 0.04),
                  effectiveTintColor.withValues(alpha: tintOpacity),
                  effectiveTintColor.withValues(alpha: (tintOpacity - 0.02).clamp(0, 1)),
                ],
              ),
              border: border ?? LiquidGlassTheme.glassBorder,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Stack(
              children: [
                // Specular highlight at top
                if (showSpecular)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.3),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Content
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS PANEL (Full panel with header)
// ==============================================================================

/// A glass panel with optional header section
class GlassPanel extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final List<Widget>? actions;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? contentPadding;

  const GlassPanel({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.actions,
    this.width,
    this.height,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: LiquidGlassTheme.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title!.toUpperCase(),
                    style: const TextStyle(
                      color: LiquidGlassTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
            Divider(
              height: 1,
              color: LiquidGlassTheme.borderLight,
            ),
          ],
          Expanded(
            child: Padding(
              padding: contentPadding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// GLASS BUTTON
// ==============================================================================

/// A glass-styled button with optional glow
class GlassButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final double? width;
  final double? height;
  final bool compact;

  const GlassButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
    this.width,
    this.height,
    this.compact = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? LiquidGlassTheme.accentBlue;
    final isActive = widget.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          width: widget.width,
          height: widget.height ?? (widget.compact ? 28 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 14,
            vertical: widget.compact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.25)
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.08),
            borderRadius: LiquidGlassTheme.borderRadiusSmall,
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.5)
                  : LiquidGlassTheme.borderLight,
            ),
            boxShadow: isActive ? LiquidGlassTheme.activeGlow(color) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null)
                Icon(
                  widget.icon,
                  size: widget.compact ? 14 : 16,
                  color: isActive ? color : LiquidGlassTheme.textSecondary,
                ),
              if (widget.icon != null && widget.label != null)
                SizedBox(width: widget.compact ? 4 : 6),
              if (widget.label != null)
                Text(
                  widget.label!,
                  style: TextStyle(
                    color: isActive ? color : LiquidGlassTheme.textPrimary,
                    fontSize: widget.compact ? 11 : 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS ICON BUTTON
// ==============================================================================

/// Circular glass icon button
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final double size;
  final String? tooltip;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
    this.size = 36,
    this.tooltip,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? LiquidGlassTheme.accentBlue;
    final isActive = widget.isActive;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.25)
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(widget.size / 4),
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.5)
                  : LiquidGlassTheme.borderLight,
            ),
            boxShadow: isActive ? LiquidGlassTheme.activeGlow(color) : null,
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.5,
            color: isActive ? color : LiquidGlassTheme.textSecondary,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }
    return button;
  }
}

// ==============================================================================
// GLASS TOGGLE
// ==============================================================================

/// Toggle switch with glass styling
class GlassToggle extends StatelessWidget {
  final String label;
  final bool isOn;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  const GlassToggle({
    super.key,
    required this.label,
    required this.isOn,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? LiquidGlassTheme.accentBlue;

    return GestureDetector(
      onTap: () => onChanged?.call(!isOn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isOn
              ? color.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: LiquidGlassTheme.borderRadiusSmall,
          border: Border.all(
            color: isOn
                ? color.withValues(alpha: 0.5)
                : LiquidGlassTheme.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isOn ? color : LiquidGlassTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS METER
// ==============================================================================

/// Vertical level meter with glass styling
class GlassMeter extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final double? peak;
  final double width;
  final bool showPeak;

  const GlassMeter({
    super.key,
    required this.value,
    this.peak,
    this.width = 8,
    this.showPeak = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(width / 4),
        border: Border.all(color: LiquidGlassTheme.borderLight),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Meter fill
              AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                height: constraints.maxHeight * value.clamp(0, 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width / 4 - 1),
                  gradient: LiquidGlassTheme.meterGradient,
                ),
              ),
              // Peak indicator
              if (showPeak && peak != null)
                Positioned(
                  bottom: constraints.maxHeight * peak!.clamp(0, 1) - 1,
                  child: Container(
                    width: width - 2,
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================================
// GLASS KNOB
// ==============================================================================

/// Rotary knob with glass styling
class GlassKnob extends StatefulWidget {
  final double value; // 0.0 - 1.0
  final ValueChanged<double>? onChanged;
  final double size;
  final String? label;
  final Color? color;
  final bool bipolar; // Center at 0.5

  const GlassKnob({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 48,
    this.label,
    this.color,
    this.bipolar = false,
  });

  @override
  State<GlassKnob> createState() => _GlassKnobState();
}

class _GlassKnobState extends State<GlassKnob> {
  double _startY = 0;
  double _startValue = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragStart: (details) {
            _startY = details.localPosition.dy;
            _startValue = widget.value;
          },
          onVerticalDragUpdate: (details) {
            if (widget.onChanged != null) {
              final delta = (_startY - details.localPosition.dy) / 100;
              final newValue = (_startValue + delta).clamp(0.0, 1.0);
              widget.onChanged!(newValue);
            }
          },
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(
                color: LiquidGlassTheme.borderMedium,
              ),
              boxShadow: LiquidGlassTheme.glassInnerShadow,
            ),
            child: CustomPaint(
              painter: _KnobPainter(
                value: widget.value,
                color: widget.color ?? LiquidGlassTheme.accentBlue,
                bipolar: widget.bipolar,
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.label!,
            style: const TextStyle(
              color: LiquidGlassTheme.textTertiary,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool bipolar;

  _KnobPainter({
    required this.value,
    required this.color,
    this.bipolar = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Arc track
    const startAngle = 2.4; // ~135 degrees
    const sweepRange = 4.3; // ~245 degrees

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepRange,
      false,
      trackPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (bipolar) {
      final midAngle = startAngle + sweepRange / 2;
      final valueAngle = (value - 0.5) * sweepRange;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        midAngle,
        valueAngle,
        false,
        valuePaint,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepRange * value,
        false,
        valuePaint,
      );
    }

    // Indicator line
    final angle = startAngle + sweepRange * value;
    final indicatorPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final start = Offset(
      center.dx + (radius * 0.4) * -math.sin(angle),
      center.dy + (radius * 0.4) * math.cos(angle),
    );
    final end = Offset(
      center.dx + radius * -math.sin(angle),
      center.dy + radius * math.cos(angle),
    );

    canvas.drawLine(start, end, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

// ==============================================================================
// GLASS FADER
// ==============================================================================

/// Vertical fader with glass styling
class GlassFader extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final ValueChanged<double>? onChanged;
  final double width;
  final double height;
  final Color? color;
  final String? topLabel;
  final String? bottomLabel;

  const GlassFader({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 40,
    this.height = 200,
    this.color,
    this.topLabel,
    this.bottomLabel,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? LiquidGlassTheme.accentBlue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              topLabel!,
              style: const TextStyle(
                color: LiquidGlassTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(width / 4),
            border: Border.all(color: LiquidGlassTheme.borderLight),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (onChanged != null) {
                    final newValue =
                        1 - (details.localPosition.dy / constraints.maxHeight);
                    onChanged!(newValue.clamp(0.0, 1.0));
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Track fill
                    Container(
                      width: 4,
                      height: constraints.maxHeight * value,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Thumb
                    Positioned(
                      bottom: constraints.maxHeight * value - 12,
                      child: Container(
                        width: width - 8,
                        height: 24,
                        decoration: BoxDecoration(
                          color: effectiveColor,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: width - 16,
                            height: 2,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (bottomLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              bottomLabel!,
              style: const TextStyle(
                color: LiquidGlassTheme.textTertiary,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}

// ==============================================================================
// GLASS TAB BAR
// ==============================================================================

/// Tab bar with glass styling
class GlassTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int>? onTap;
  final Color? activeColor;

  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? LiquidGlassTheme.accentBlue;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: LiquidGlassTheme.borderRadiusSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onTap?.call(index),
            child: AnimatedContainer(
              duration: LiquidGlassTheme.animFast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: LiquidGlassTheme.borderRadiusSmall,
                border: isSelected
                    ? Border.all(color: color.withValues(alpha: 0.4))
                    : null,
              ),
              child: Text(
                tabs[index],
                style: TextStyle(
                  color: isSelected ? color : LiquidGlassTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ==============================================================================
// GLASS DROPDOWN
// ==============================================================================

/// Dropdown selector with glass styling
class GlassDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String Function(T) labelBuilder;
  final double? width;

  const GlassDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    required this.labelBuilder,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: LiquidGlassTheme.borderRadiusSmall,
        border: Border.all(color: LiquidGlassTheme.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      labelBuilder(item),
                      style: const TextStyle(
                        color: LiquidGlassTheme.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          dropdownColor: const Color(0xFF1a1a2e),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: LiquidGlassTheme.textSecondary,
            size: 18,
          ),
          isDense: true,
          style: const TextStyle(
            color: LiquidGlassTheme.textPrimary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS TEXT FIELD
// ==============================================================================

/// Text input with glass styling
class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final TextAlign textAlign;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      readOnly: readOnly,
      textAlign: textAlign,
      style: const TextStyle(
        color: LiquidGlassTheme.textPrimary,
        fontSize: 13,
      ),
      decoration: LiquidGlassTheme.glassInputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

// ==============================================================================
// GLASS DIVIDER
// ==============================================================================

/// Subtle divider for glass panels
class GlassDivider extends StatelessWidget {
  final bool vertical;
  final double thickness;
  final double? length;
  final EdgeInsetsGeometry? margin;

  const GlassDivider({
    super.key,
    this.vertical = false,
    this.thickness = 1,
    this.length,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? thickness : length,
      height: vertical ? length : thickness,
      margin: margin,
      color: LiquidGlassTheme.borderLight,
    );
  }
}

// ==============================================================================
// GLASS CHIP
// ==============================================================================

/// Small label chip with glass styling
class GlassChip extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final bool selected;

  const GlassChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? LiquidGlassTheme.accentBlue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? effectiveColor.withValues(alpha: 0.5)
                : LiquidGlassTheme.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? effectiveColor : LiquidGlassTheme.textSecondary,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// COLOR ORB (Background decoration)
// ==============================================================================

/// Ambient color orb for background decoration
class ColorOrb extends StatelessWidget {
  final Color color;
  final double size;

  const ColorOrb({
    super.key,
    required this.color,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

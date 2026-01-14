/// Glass DSP Components
///
/// Professional Liquid Glass styled DSP control components:
/// - GlassDSPKnob: Rotary knob with arc indicator
/// - GlassDSPFader: Vertical/horizontal fader
/// - GlassDSPMeter: Level meter with gradient
/// - GlassDSPSection: Collapsible panel section
/// - GlassDSPButton: Toggle/momentary button
/// - GlassDSPPanelWrapper: Wrapper for existing DSP panels

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP PANEL WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wraps any DSP panel with Glass styling when in Glass mode
class GlassDSPPanelWrapper extends StatelessWidget {
  final Widget child;
  final String? title;
  final IconData? icon;
  final Color? accentColor;
  final bool bypassed;
  final VoidCallback? onBypassToggle;
  final List<Widget>? headerActions;

  const GlassDSPPanelWrapper({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.accentColor,
    this.bypassed = false,
    this.onBypassToggle,
    this.headerActions,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = accentColor ?? LiquidGlassTheme.accentBlue;

    if (!isGlassMode) {
      return child;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: bypassed
                  ? Colors.white.withValues(alpha: 0.1)
                  : color.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: -5,
              ),
              if (!bypassed)
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: -10,
                ),
            ],
          ),
          child: Stack(
            children: [
              // Specular highlight
              Positioned(
                top: 0,
                left: 12,
                right: 12,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  if (title != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Icon(
                              icon,
                              size: 18,
                              color: bypassed
                                  ? LiquidGlassTheme.textTertiary
                                  : color,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            title!.toUpperCase(),
                            style: TextStyle(
                              color: bypassed
                                  ? LiquidGlassTheme.textTertiary
                                  : LiquidGlassTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          if (headerActions != null) ...headerActions!,
                          if (onBypassToggle != null)
                            GlassDSPButton(
                              label: 'BYP',
                              active: bypassed,
                              activeColor: LiquidGlassTheme.accentOrange,
                              onTap: onBypassToggle,
                              compact: true,
                            ),
                        ],
                      ),
                    ),

                  // Body
                  Opacity(
                    opacity: bypassed ? 0.5 : 1.0,
                    child: child,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP KNOB
// ═══════════════════════════════════════════════════════════════════════════

/// Professional Glass-styled rotary knob with arc indicator
class GlassDSPKnob extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String Function(double)? formatValue;
  final ValueChanged<double>? onChanged;
  final Color? color;
  final double size;
  final bool bipolar;
  final bool disabled;

  const GlassDSPKnob({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.defaultValue = 0,
    this.formatValue,
    this.onChanged,
    this.color,
    this.size = 56,
    this.bipolar = false,
    this.disabled = false,
  });

  @override
  State<GlassDSPKnob> createState() => _GlassDSPKnobState();
}

class _GlassDSPKnobState extends State<GlassDSPKnob> {
  bool _isDragging = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  double get _normalizedValue {
    if (widget.max == widget.min) return 0;
    return (widget.value - widget.min) / (widget.max - widget.min);
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _isDragging = true;
      _dragStartY = details.localPosition.dy;
      _dragStartValue = widget.value;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.disabled || !_isDragging) return;

    final deltaY = _dragStartY - details.localPosition.dy;
    final sensitivity = (widget.max - widget.min) / 200;
    final newValue = (_dragStartValue + deltaY * sensitivity)
        .clamp(widget.min, widget.max);

    widget.onChanged?.call(newValue);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? LiquidGlassTheme.accentBlue;
    final effectiveColor = widget.disabled
        ? LiquidGlassTheme.textTertiary
        : color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Knob
        GestureDetector(
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: _handleDragEnd,
          onDoubleTap: widget.disabled
              ? null
              : () => widget.onChanged?.call(widget.defaultValue),
          child: MouseRegion(
            cursor: widget.disabled
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.click,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _GlassKnobPainter(
                  normalizedValue: _normalizedValue,
                  color: effectiveColor,
                  isDragging: _isDragging,
                  bipolar: widget.bipolar,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        // Value
        Text(
          widget.formatValue?.call(widget.value) ??
              widget.value.toStringAsFixed(1),
          style: TextStyle(
            color: effectiveColor,
            fontSize: 10,
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 2),

        // Label
        Text(
          widget.label,
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _GlassKnobPainter extends CustomPainter {
  final double normalizedValue;
  final Color color;
  final bool isDragging;
  final bool bipolar;

  _GlassKnobPainter({
    required this.normalizedValue,
    required this.color,
    required this.isDragging,
    required this.bipolar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Arc angles
    const startAngle = 135 * math.pi / 180;
    const sweepAngle = 270 * math.pi / 180;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valueSweep = normalizedValue * sweepAngle;
    final startSweep = bipolar ? sweepAngle / 2 : 0;
    final actualSweep = bipolar
        ? (normalizedValue - 0.5) * sweepAngle
        : valueSweep;

    final valuePaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          color.withValues(alpha: 0.5),
          color,
        ],
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      bipolar ? startAngle + startSweep : startAngle,
      actualSweep,
      false,
      valuePaint,
    );

    // Knob body (glass effect)
    final knobRadius = radius - 6;

    // Outer ring
    final ringPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: knobRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, knobRadius, ringPaint);

    // Inner circle
    final innerPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.2,
        colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.black.withValues(alpha: 0.3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: knobRadius - 2))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, knobRadius - 2, innerPaint);

    // Pointer line
    final pointerAngle = startAngle + normalizedValue * sweepAngle;
    final pointerStart = Offset(
      center.dx + (knobRadius - 10) * math.cos(pointerAngle),
      center.dy + (knobRadius - 10) * math.sin(pointerAngle),
    );
    final pointerEnd = Offset(
      center.dx + (knobRadius - 4) * math.cos(pointerAngle),
      center.dy + (knobRadius - 4) * math.sin(pointerAngle),
    );

    final pointerPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(pointerStart, pointerEnd, pointerPaint);

    // Glow when dragging
    if (isDragging) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, knobRadius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlassKnobPainter oldDelegate) {
    return normalizedValue != oldDelegate.normalizedValue ||
        color != oldDelegate.color ||
        isDragging != oldDelegate.isDragging;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP FADER
// ═══════════════════════════════════════════════════════════════════════════

/// Professional Glass-styled linear fader
class GlassDSPFader extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String Function(double)? formatValue;
  final ValueChanged<double>? onChanged;
  final Color? color;
  final double width;
  final double height;
  final bool horizontal;
  final bool showValue;
  final bool disabled;

  const GlassDSPFader({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.defaultValue = 0,
    this.formatValue,
    this.onChanged,
    this.color,
    this.width = 40,
    this.height = 120,
    this.horizontal = false,
    this.showValue = true,
    this.disabled = false,
  });

  @override
  State<GlassDSPFader> createState() => _GlassDSPFaderState();
}

class _GlassDSPFaderState extends State<GlassDSPFader> {
  bool _isDragging = false;

  double get _normalizedValue {
    if (widget.max == widget.min) return 0;
    return (widget.value - widget.min) / (widget.max - widget.min);
  }

  void _handleDrag(DragUpdateDetails details, BoxConstraints constraints) {
    if (widget.disabled) return;

    double normalized;
    if (widget.horizontal) {
      normalized = (details.localPosition.dx / constraints.maxWidth)
          .clamp(0.0, 1.0);
    } else {
      normalized = 1.0 -
          (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    }

    final newValue = widget.min + normalized * (widget.max - widget.min);
    widget.onChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? LiquidGlassTheme.accentBlue;
    final effectiveColor = widget.disabled
        ? LiquidGlassTheme.textTertiary
        : color;

    Widget fader = LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onVerticalDragStart: widget.horizontal
              ? null
              : (_) => setState(() => _isDragging = true),
          onVerticalDragUpdate: widget.horizontal
              ? null
              : (d) => _handleDrag(d, constraints),
          onVerticalDragEnd: widget.horizontal
              ? null
              : (_) => setState(() => _isDragging = false),
          onHorizontalDragStart: widget.horizontal
              ? (_) => setState(() => _isDragging = true)
              : null,
          onHorizontalDragUpdate: widget.horizontal
              ? (d) => _handleDrag(d, constraints)
              : null,
          onHorizontalDragEnd: widget.horizontal
              ? (_) => setState(() => _isDragging = false)
              : null,
          onDoubleTap: widget.disabled
              ? null
              : () => widget.onChanged?.call(widget.defaultValue),
          child: Container(
            width: widget.horizontal ? null : widget.width,
            height: widget.horizontal ? widget.width : widget.height,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isDragging
                    ? effectiveColor.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Stack(
              children: [
                // Fill
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: widget.horizontal
                        ? FractionallySizedBox(
                            widthFactor: _normalizedValue,
                            alignment: Alignment.centerLeft,
                            child: _buildFill(effectiveColor),
                          )
                        : FractionallySizedBox(
                            heightFactor: _normalizedValue,
                            alignment: Alignment.bottomCenter,
                            child: _buildFill(effectiveColor),
                          ),
                  ),
                ),

                // Handle
                Positioned(
                  left: widget.horizontal
                      ? constraints.maxWidth * _normalizedValue - 6
                      : 0,
                  right: widget.horizontal ? null : 0,
                  top: widget.horizontal
                      ? 0
                      : constraints.maxHeight * (1 - _normalizedValue) - 6,
                  bottom: widget.horizontal ? 0 : null,
                  child: Container(
                    width: widget.horizontal ? 12 : null,
                    height: widget.horizontal ? null : 12,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: effectiveColor.withValues(alpha: 0.5),
                          blurRadius: _isDragging ? 8 : 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.horizontal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: LiquidGlassTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (widget.showValue)
                Text(
                  widget.formatValue?.call(widget.value) ??
                      widget.value.toStringAsFixed(1),
                  style: TextStyle(
                    color: effectiveColor,
                    fontSize: 10,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          fader,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        fader,
        const SizedBox(height: 4),
        if (widget.showValue)
          Text(
            widget.formatValue?.call(widget.value) ??
                widget.value.toStringAsFixed(1),
            style: TextStyle(
              color: effectiveColor,
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        const SizedBox(height: 2),
        Text(
          widget.label,
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFill(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: widget.horizontal
              ? Alignment.centerLeft
              : Alignment.bottomCenter,
          end: widget.horizontal ? Alignment.centerRight : Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.4),
            color.withValues(alpha: 0.8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP METER
// ═══════════════════════════════════════════════════════════════════════════

/// Professional Glass-styled level meter
class GlassDSPMeter extends StatelessWidget {
  final double level;
  final double peak;
  final double min;
  final double max;
  final double width;
  final double height;
  final bool horizontal;
  final bool showPeak;
  final bool showScale;
  final String? label;

  const GlassDSPMeter({
    super.key,
    required this.level,
    this.peak = 0,
    this.min = -60,
    this.max = 0,
    this.width = 8,
    this.height = 120,
    this.horizontal = false,
    this.showPeak = true,
    this.showScale = false,
    this.label,
  });

  double get _normalizedLevel {
    if (max == min) return 0;
    return ((level - min) / (max - min)).clamp(0.0, 1.0);
  }

  double get _normalizedPeak {
    if (max == min) return 0;
    return ((peak - min) / (max - min)).clamp(0.0, 1.0);
  }

  Color _getGradientColor(double position) {
    if (position > 0.9) return LiquidGlassTheme.accentRed;
    if (position > 0.7) return LiquidGlassTheme.accentYellow;
    return LiquidGlassTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    Widget meter = Container(
      width: horizontal ? null : width,
      height: horizontal ? width : height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Stack(
        children: [
          // Level fill
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: horizontal
                ? FractionallySizedBox(
                    widthFactor: _normalizedLevel,
                    alignment: Alignment.centerLeft,
                    child: _buildGradientFill(),
                  )
                : FractionallySizedBox(
                    heightFactor: _normalizedLevel,
                    alignment: Alignment.bottomCenter,
                    child: _buildGradientFill(),
                  ),
          ),

          // Peak indicator
          if (showPeak && _normalizedPeak > 0)
            Positioned(
              left: horizontal ? null : 0,
              right: horizontal ? null : 0,
              top: horizontal ? 0 : null,
              bottom: horizontal ? 0 : null,
              child: horizontal
                  ? Align(
                      alignment: Alignment(
                        _normalizedPeak * 2 - 1,
                        0,
                      ),
                      child: _buildPeakIndicator(),
                    )
                  : Align(
                      alignment: Alignment(
                        0,
                        1 - _normalizedPeak * 2,
                      ),
                      child: _buildPeakIndicator(),
                    ),
            ),
        ],
      ),
    );

    if (label != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          meter,
          const SizedBox(height: 4),
          Text(
            label!,
            style: TextStyle(
              color: LiquidGlassTheme.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return meter;
  }

  Widget _buildGradientFill() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: horizontal ? Alignment.centerLeft : Alignment.bottomCenter,
          end: horizontal ? Alignment.centerRight : Alignment.topCenter,
          colors: const [
            LiquidGlassTheme.accentGreen,
            LiquidGlassTheme.accentYellow,
            LiquidGlassTheme.accentRed,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
    );
  }

  Widget _buildPeakIndicator() {
    return Container(
      width: horizontal ? 2 : null,
      height: horizontal ? null : 2,
      color: _normalizedPeak > 0.9
          ? LiquidGlassTheme.accentRed
          : LiquidGlassTheme.accentYellow,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Professional Glass-styled toggle button
class GlassDSPButton extends StatefulWidget {
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback? onTap;
  final bool compact;
  final IconData? icon;
  final bool disabled;

  const GlassDSPButton({
    super.key,
    required this.label,
    required this.active,
    this.activeColor,
    this.onTap,
    this.compact = false,
    this.icon,
    this.disabled = false,
  });

  @override
  State<GlassDSPButton> createState() => _GlassDSPButtonState();
}

class _GlassDSPButtonState extends State<GlassDSPButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? LiquidGlassTheme.accentBlue;
    final showActive = _isPressed ? !widget.active : widget.active;
    final effectiveColor = widget.disabled
        ? LiquidGlassTheme.textTertiary
        : color;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: widget.disabled ? null : (_) => setState(() => _isPressed = true),
        onTapUp: widget.disabled
            ? null
            : (_) {
                setState(() => _isPressed = false);
                widget.onTap?.call();
              },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: widget.compact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: showActive
                ? effectiveColor.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: showActive
                  ? effectiveColor.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: _isHovered ? 0.2 : 0.1),
              width: showActive ? 1.5 : 1,
            ),
            boxShadow: showActive
                ? [
                    BoxShadow(
                      color: effectiveColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.compact ? 12 : 16,
                  color: showActive
                      ? effectiveColor
                      : LiquidGlassTheme.textSecondary,
                ),
                SizedBox(width: widget.compact ? 4 : 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: showActive
                      ? effectiveColor
                      : LiquidGlassTheme.textSecondary,
                  fontSize: widget.compact ? 10 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP SECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Collapsible section for DSP panels
class GlassDSPSection extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final Color? accentColor;

  const GlassDSPSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.accentColor,
  });

  @override
  State<GlassDSPSection> createState() => _GlassDSPSectionState();
}

class _GlassDSPSectionState extends State<GlassDSPSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? LiquidGlassTheme.accentBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title.toUpperCase(),
                  style: TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: LiquidGlassTheme.animFast,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: LiquidGlassTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content
        AnimatedCrossFade(
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: widget.child,
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: LiquidGlassTheme.animFast,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS DSP GAIN REDUCTION METER
// ═══════════════════════════════════════════════════════════════════════════

/// Specialized meter for gain reduction display
class GlassDSPGainReductionMeter extends StatelessWidget {
  final double gainReduction;
  final double width;
  final double height;

  const GlassDSPGainReductionMeter({
    super.key,
    required this.gainReduction,
    this.width = 200,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = (gainReduction.abs() / 30).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'GR',
              style: TextStyle(
                color: LiquidGlassTheme.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '${gainReduction.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: normalized > 0.5
                    ? LiquidGlassTheme.accentOrange
                    : LiquidGlassTheme.textSecondary,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              // GR fill (from right to left)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: FractionallySizedBox(
                  widthFactor: normalized,
                  alignment: Alignment.centerRight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          LiquidGlassTheme.accentYellow.withValues(alpha: 0.6),
                          LiquidGlassTheme.accentOrange,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 0 dB mark (center)
              Positioned(
                left: width / 2 - 0.5,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

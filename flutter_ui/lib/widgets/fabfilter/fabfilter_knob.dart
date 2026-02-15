/// FabFilter-Style Knob Widget
///
/// Professional rotary knob with:
/// - Outer modulation ring
/// - Value display integration
/// - Fine control (Alt/Shift)
/// - Double-click reset
/// - Scroll wheel support

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fabfilter_theme.dart';

/// FabFilter-style knob with professional features
class FabFilterKnob extends StatefulWidget {
  /// Current value (0.0 - 1.0)
  final double value;

  /// Label text below knob
  final String label;

  /// Display text (formatted value)
  final String display;

  /// Accent color for the knob
  final Color color;

  /// Size of the knob
  final double size;

  /// Callback when value changes
  final ValueChanged<double> onChanged;

  /// Default value for double-click reset
  final double defaultValue;

  /// Whether the knob is enabled
  final bool enabled;

  /// Optional modulation amount (-1.0 to 1.0)
  final double? modulation;

  const FabFilterKnob({
    super.key,
    required this.value,
    required this.label,
    required this.display,
    required this.onChanged,
    this.color = FabFilterColors.blue,
    this.size = 60,
    this.defaultValue = 0.5,
    this.enabled = true,
    this.modulation,
  });

  @override
  State<FabFilterKnob> createState() => _FabFilterKnobState();
}

class _FabFilterKnobState extends State<FabFilterKnob>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _isHovering = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  // Floating value tooltip overlay
  OverlayEntry? _tooltipOverlay;
  final GlobalKey _knobKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _removeTooltip();
    _glowController.dispose();
    super.dispose();
  }

  void _showTooltip() {
    _removeTooltip();
    final overlay = Overlay.of(context);
    _tooltipOverlay = OverlayEntry(builder: (_) => _buildTooltip());
    overlay.insert(_tooltipOverlay!);
  }

  void _updateTooltip() {
    _tooltipOverlay?.markNeedsBuild();
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  Widget _buildTooltip() {
    final box = _knobKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const SizedBox.shrink();
    final pos = box.localToGlobal(Offset(box.size.width / 2, 0));

    return Positioned(
      left: pos.dx - 36,
      top: pos.dy - 28,
      child: IgnorePointer(
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: FabFilterColors.bgElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.color.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            widget.display,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    setState(() {
      _isDragging = true;
      _dragStartY = details.globalPosition.dy;
      _dragStartValue = widget.value;
    });
    _glowController.forward();
    _showTooltip();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_isDragging) return;

    // Check for fine control modifier
    final isFine = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isAltPressed;
    final sensitivity = isFine ? 0.001 : 0.005;

    final delta = (_dragStartY - details.globalPosition.dy) * sensitivity;
    final newValue = (_dragStartValue + delta).clamp(0.0, 1.0);

    widget.onChanged(newValue);
    _updateTooltip();
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    _glowController.reverse();
    _removeTooltip();
  }

  void _handleDoubleTap() {
    if (!widget.enabled) return;
    widget.onChanged(widget.defaultValue);
  }

  void _handleScroll(PointerScrollEvent event) {
    if (!widget.enabled) return;

    final isFine = HardwareKeyboard.instance.isShiftPressed;
    final step = isFine ? 0.005 : 0.02;
    final delta = event.scrollDelta.dy > 0 ? -step : step;
    final newValue = (widget.value + delta).clamp(0.0, 1.0);

    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) _handleScroll(event);
        },
        child: GestureDetector(
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: _handleDragEnd,
          onDoubleTap: _handleDoubleTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildKnob(),
              const SizedBox(height: 4),
              _buildLabel(),
              _buildDisplay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKnob() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          key: _knobKey,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              if (_isHovering || _isDragging)
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.3 * _glowAnimation.value + 0.1),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: CustomPaint(
            painter: _KnobPainter(
              value: widget.value,
              color: widget.color,
              modulation: widget.modulation,
              isActive: _isDragging || _isHovering,
              enabled: widget.enabled,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabel() {
    return Text(
      widget.label,
      style: FabFilterText.paramLabel.copyWith(
        color: widget.enabled
            ? FabFilterColors.textTertiary
            : FabFilterColors.textDisabled,
      ),
    );
  }

  Widget _buildDisplay() {
    return Text(
      widget.display,
      style: FabFilterText.paramValue(
        widget.enabled ? widget.color : FabFilterColors.textDisabled,
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final Color color;
  final double? modulation;
  final bool isActive;
  final bool enabled;

  _KnobPainter({
    required this.value,
    required this.color,
    this.modulation,
    required this.isActive,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Arc parameters
    const startAngle = 135 * math.pi / 180; // 7 o'clock
    const sweepAngle = 270 * math.pi / 180; // to 5 o'clock
    final valueAngle = startAngle + (value * sweepAngle);

    // ═══════════════════════════════════════════════════════════════════════
    // OUTER MODULATION RING
    // ═══════════════════════════════════════════════════════════════════════
    if (modulation != null && modulation!.abs() > 0.001) {
      final modStart = valueAngle;
      final modSweep = modulation! * sweepAngle * 0.5;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        modStart,
        modSweep,
        false,
        Paint()
          ..color = FabFilterColors.yellow.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRACK (background arc)
    // ═══════════════════════════════════════════════════════════════════════
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = FabFilterColors.borderSubtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // ═══════════════════════════════════════════════════════════════════════
    // VALUE ARC
    // ═══════════════════════════════════════════════════════════════════════
    if (value > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 6),
        startAngle,
        value * sweepAngle,
        false,
        Paint()
          ..color = enabled ? color : FabFilterColors.textDisabled
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // KNOB BODY
    // ═══════════════════════════════════════════════════════════════════════
    final bodyRadius = radius - 12;

    // Outer ring
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..color = isActive
            ? FabFilterColors.bgElevated
            : FabFilterColors.bgSurface
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..color = isActive ? color : FabFilterColors.borderMedium
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ═══════════════════════════════════════════════════════════════════════
    // POINTER
    // ═══════════════════════════════════════════════════════════════════════
    final pointerLength = bodyRadius - 6;
    final pointerEnd = Offset(
      center.dx + math.cos(valueAngle) * pointerLength,
      center.dy + math.sin(valueAngle) * pointerLength,
    );

    canvas.drawLine(
      center,
      pointerEnd,
      Paint()
        ..color = enabled ? color : FabFilterColors.textDisabled
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Center dot
    canvas.drawCircle(
      center,
      3,
      Paint()..color = enabled ? color : FabFilterColors.textDisabled,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) {
    return value != old.value ||
        color != old.color ||
        modulation != old.modulation ||
        isActive != old.isActive ||
        enabled != old.enabled;
  }
}

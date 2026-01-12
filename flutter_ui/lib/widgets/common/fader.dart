/// Unified Audio Fader Widget
///
/// Professional DAW-quality fader combining best of both implementations:
/// - GPU-accelerated Canvas rendering (60fps)
/// - Optional dual stereo meter with peak hold
/// - Clip detection with flash animation
/// - dB scale with major/minor ticks
/// - Fine control with Shift key
/// - Double-click reset to unity
/// - Horizontal variant for inline use

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ============ Types ============

enum FaderStyle { cubase, protools, minimal }
enum FaderOrientation { vertical, horizontal }

// ============ Constants ============

const _faderThumbHeight = 24.0;
// ignore: unused_element
const _faderThumbWidth = 16.0;
const _meterGap = 2.0;
const _scaleWidth = 24.0;
const _peakHoldTime = 1500; // ms
const _peakDecayRate = 0.003;

const _meterColors = (
  green: FluxForgeTheme.accentGreen,
  greenDark: Color(0xFF287048), // Darker variant of accentGreen
  yellow: FluxForgeTheme.accentYellow,
  orange: FluxForgeTheme.accentOrange,
  red: FluxForgeTheme.accentRed,
  clip: FluxForgeTheme.clipRed,
);

const _scaleMarks = [12.0, 6.0, 3.0, 0.0, -3.0, -6.0, -12.0, -18.0, -24.0, -36.0, -48.0, -60.0];
const _minorMarks = [9.0, -9.0, -15.0, -21.0, -30.0, -42.0, -54.0];

// ============ Main Widget ============

class Fader extends StatefulWidget {
  /// Current value in dB
  final double value;

  /// Minimum dB value
  final double min;

  /// Maximum dB value
  final double max;

  /// Default value for double-tap reset (typically 0 dB)
  final double defaultValue;

  /// Called when value changes during drag
  final ValueChanged<double>? onChanged;

  /// Called when drag ends
  final ValueChanged<double>? onChangeEnd;

  /// Left channel meter level (0-1)
  final double? meterL;

  /// Right channel meter level (0-1)
  final double? meterR;

  /// Left channel peak level (0-1)
  final double? peakL;

  /// Right channel peak level (0-1)
  final double? peakR;

  /// Gain reduction in dB (negative values)
  final double? gainReduction;

  /// Fader width
  final double width;

  /// Fader height
  final double height;

  /// Visual style
  final FaderStyle style;

  /// Orientation
  final FaderOrientation orientation;

  /// Show dB scale labels
  final bool showScale;

  /// Show meters (requires meterL/meterR)
  final bool showMeters;

  /// Stereo meters or mono
  final bool stereo;

  /// Accent color
  final Color? accentColor;

  /// Optional label below fader
  final String? label;

  /// Disabled state
  final bool disabled;

  const Fader({
    super.key,
    required this.value,
    this.min = -60,
    this.max = 12,
    this.defaultValue = 0,
    this.onChanged,
    this.onChangeEnd,
    this.meterL,
    this.meterR,
    this.peakL,
    this.peakR,
    this.gainReduction,
    this.width = 60,
    this.height = 200,
    this.style = FaderStyle.cubase,
    this.orientation = FaderOrientation.vertical,
    this.showScale = true,
    this.showMeters = false,
    this.stereo = true,
    this.accentColor,
    this.label,
    this.disabled = false,
  });

  /// Simple vertical fader without meters
  const Fader.simple({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.min = -60,
    this.max = 12,
    this.defaultValue = 0,
    this.width = 40,
    this.height = 150,
    this.accentColor,
    this.disabled = false,
  }) : meterL = null,
       meterR = null,
       peakL = null,
       peakR = null,
       gainReduction = null,
       style = FaderStyle.minimal,
       orientation = FaderOrientation.vertical,
       showScale = true,
       showMeters = false,
       stereo = false,
       label = null;

  /// Horizontal fader for inline use
  const Fader.horizontal({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.min = -60,
    this.max = 6,
    this.defaultValue = 0,
    this.width = 100,
    this.height = 20,
    this.accentColor,
    this.disabled = false,
  }) : meterL = null,
       meterR = null,
       peakL = null,
       peakR = null,
       gainReduction = null,
       style = FaderStyle.minimal,
       orientation = FaderOrientation.horizontal,
       showScale = false,
       showMeters = false,
       stereo = false,
       label = null;

  @override
  State<Fader> createState() => _FaderState();
}

class _FaderState extends State<Fader> with TickerProviderStateMixin {
  late AnimationController _meterController;
  late AnimationController _smoothController;
  late Animation<double> _smoothAnimation;

  bool _isDragging = false;
  double _dragStartPos = 0;
  double _dragStartValue = 0;
  double _targetValue = 0;

  // Peak hold state
  double _peakHoldL = 0;
  double _peakHoldR = 0;
  DateTime _peakHoldTimeL = DateTime.now();
  DateTime _peakHoldTimeR = DateTime.now();

  // Clip detection
  bool _isClippingL = false;
  bool _isClippingR = false;
  DateTime _clipTimeL = DateTime.now();
  DateTime _clipTimeR = DateTime.now();

  @override
  void initState() {
    super.initState();
    _targetValue = widget.value;

    // Meter animation controller
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.showMeters) {
      _meterController.repeat();
    }

    // Smooth value animation controller
    _smoothController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    );
    _smoothAnimation = Tween<double>(begin: widget.value, end: widget.value)
        .animate(CurvedAnimation(parent: _smoothController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _meterController.dispose();
    _smoothController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Fader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showMeters && !_meterController.isAnimating) {
      _meterController.repeat();
    } else if (!widget.showMeters && _meterController.isAnimating) {
      _meterController.stop();
    }
    if (widget.showMeters) {
      _updatePeakHold();
    }
  }

  void _updatePeakHold() {
    final now = DateTime.now();
    final peakL = widget.peakL ?? 0;
    final peakR = widget.peakR ?? 0;

    // Left channel
    if (peakL > _peakHoldL) {
      _peakHoldL = peakL;
      _peakHoldTimeL = now.add(const Duration(milliseconds: _peakHoldTime));
    } else if (now.isAfter(_peakHoldTimeL)) {
      _peakHoldL = math.max(0, _peakHoldL - _peakDecayRate);
    }

    // Right channel
    if (peakR > _peakHoldR) {
      _peakHoldR = peakR;
      _peakHoldTimeR = now.add(const Duration(milliseconds: _peakHoldTime));
    } else if (now.isAfter(_peakHoldTimeR)) {
      _peakHoldR = math.max(0, _peakHoldR - _peakDecayRate);
    }

    // Clip detection
    if (peakL >= 1.0 && !_isClippingL) {
      _isClippingL = true;
      _clipTimeL = now.add(const Duration(seconds: 2));
    } else if (_isClippingL && now.isAfter(_clipTimeL)) {
      _isClippingL = false;
    }

    if (peakR >= 1.0 && !_isClippingR) {
      _isClippingR = true;
      _clipTimeR = now.add(const Duration(seconds: 2));
    } else if (_isClippingR && now.isAfter(_clipTimeR)) {
      _isClippingR = false;
    }
  }

  double _dbToNormalized(double db) {
    if (db <= widget.min) return 0;
    if (db >= widget.max) return 1;

    // Use logarithmic-like curve for better feel
    // Unity gain (0dB) at ~75% position
    const unityPos = 0.75;

    if (db <= 0) {
      final range = 0 - widget.min;
      final normalized = (db - widget.min) / range;
      return math.pow(normalized, 0.7) * unityPos;
    } else {
      final range = widget.max - 0;
      final normalized = db / range;
      return unityPos + normalized * (1 - unityPos);
    }
  }

  // ignore: unused_element
  double _normalizedToDb(double normalized) {
    if (normalized <= 0) return widget.min;
    if (normalized >= 1) return widget.max;

    const unityPos = 0.75;

    if (normalized <= unityPos) {
      final scaled = normalized / unityPos;
      final curved = math.pow(scaled, 1 / 0.7);
      return widget.min + curved * (0 - widget.min);
    } else {
      final scaled = (normalized - unityPos) / (1 - unityPos);
      return scaled * widget.max;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _isDragging = true;
      _dragStartPos = widget.orientation == FaderOrientation.vertical
          ? details.localPosition.dy
          : details.localPosition.dx;
      _dragStartValue = widget.value;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || widget.disabled) return;

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final sensitivity = isShiftHeld ? 0.1 : 0.5;

    double delta;
    double size;

    if (widget.orientation == FaderOrientation.vertical) {
      delta = _dragStartPos - details.localPosition.dy;
      size = widget.height - 20;
    } else {
      delta = details.localPosition.dx - _dragStartPos;
      size = widget.width - 10;
    }

    final deltaDb = (delta / size) * (widget.max - widget.min) * sensitivity;
    final newValue = (_dragStartValue + deltaDb).clamp(widget.min, widget.max);
    widget.onChanged?.call(newValue);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    widget.onChangeEnd?.call(widget.value);
  }

  void _onDoubleTap() {
    if (widget.disabled) return;
    widget.onChanged?.call(widget.defaultValue);
    widget.onChangeEnd?.call(widget.defaultValue);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (widget.disabled) return;
    if (event is PointerScrollEvent) {
      final isVertical = widget.orientation == FaderOrientation.vertical;
      final scrollDelta = isVertical ? event.scrollDelta.dy : -event.scrollDelta.dx;
      // SMOOTH SCROLL: scale by scroll magnitude for trackpad support
      final scrollMagnitude = scrollDelta.abs();
      final delta = scrollDelta > 0 ? -1.0 : 1.0;
      final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
      // Variable step based on scroll speed
      final baseStep = isShiftHeld ? 0.1 : 0.5;
      final step = baseStep * (1.0 + (scrollMagnitude / 50.0).clamp(0.0, 2.0));
      final newValue = (widget.value + delta * step).clamp(widget.min, widget.max);
      widget.onChanged?.call(newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orientation == FaderOrientation.horizontal) {
      return _buildHorizontalFader();
    }

    return GestureDetector(
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onDoubleTap: _onDoubleTap,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: widget.showMeters
            ? AnimatedBuilder(
                animation: _meterController,
                builder: (context, _) {
                  _updatePeakHold();
                  return _buildVerticalFader();
                },
              )
            : _buildVerticalFader(),
      ),
    );
  }

  Widget _buildVerticalFader() {
    final normalized = _dbToNormalized(widget.value);
    final accentColor = widget.accentColor ?? FluxForgeTheme.accentBlue;
    // ignore: unused_local_variable
    final trackHeight = widget.height - 40;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: _VerticalFaderPainter(
            normalized: normalized,
            min: widget.min,
            max: widget.max,
            value: widget.value,
            meterL: widget.meterL ?? 0,
            meterR: widget.meterR ?? 0,
            peakHoldL: _peakHoldL,
            peakHoldR: _peakHoldR,
            gainReduction: widget.gainReduction ?? 0,
            showScale: widget.showScale,
            showMeters: widget.showMeters,
            stereo: widget.stereo,
            isClippingL: _isClippingL,
            isClippingR: _isClippingR,
            isDragging: _isDragging,
            accentColor: accentColor,
            label: widget.label,
            style: widget.style,
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalFader() {
    final normalized = _dbToNormalized(widget.value);
    final accentColor = widget.accentColor ?? FluxForgeTheme.accentBlue;

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onDoubleTap: _onDoubleTap,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Stack(
          children: [
            // Fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              width: widget.width * normalized,
              height: widget.height,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Cap
            Positioned(
              left: (widget.width - 8) * normalized,
              top: 2,
              child: Container(
                width: 6,
                height: widget.height - 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: _isDragging
                      ? FluxForgeTheme.glowShadow(accentColor)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ Painter ============

class _VerticalFaderPainter extends CustomPainter {
  final double normalized;
  final double min;
  final double max;
  final double value;
  final double meterL;
  final double meterR;
  final double peakHoldL;
  final double peakHoldR;
  final double gainReduction;
  final bool showScale;
  final bool showMeters;
  final bool stereo;
  final bool isClippingL;
  final bool isClippingR;
  final bool isDragging;
  final Color accentColor;
  final String? label;
  final FaderStyle style;

  _VerticalFaderPainter({
    required this.normalized,
    required this.min,
    required this.max,
    required this.value,
    required this.meterL,
    required this.meterR,
    required this.peakHoldL,
    required this.peakHoldR,
    required this.gainReduction,
    required this.showScale,
    required this.showMeters,
    required this.stereo,
    required this.isClippingL,
    required this.isClippingR,
    required this.isDragging,
    required this.accentColor,
    required this.label,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleW = showScale ? _scaleWidth : 0.0;
    final faderH = size.height - 20;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = FluxForgeTheme.bgMid,
    );

    // Draw scale
    if (showScale) {
      _drawScale(canvas, size, faderH);
    }

    if (showMeters) {
      final meterW = stereo
          ? (size.width - scaleW - _meterGap * 2) / 2
          : size.width - scaleW - _meterGap;
      final meterX = scaleW + _meterGap;

      // Meter backgrounds
      canvas.drawRect(
        Rect.fromLTWH(meterX, 0, meterW, faderH),
        Paint()..color = FluxForgeTheme.bgDeepest,
      );
      if (stereo) {
        canvas.drawRect(
          Rect.fromLTWH(meterX + meterW + _meterGap, 0, meterW, faderH),
          Paint()..color = FluxForgeTheme.bgDeepest,
        );
      }

      // Meter fills
      _drawMeterFill(canvas, meterX, meterL, peakHoldL, isClippingL, meterW, faderH);
      if (stereo) {
        _drawMeterFill(canvas, meterX + meterW + _meterGap, meterR, peakHoldR, isClippingR, meterW, faderH);
      }

      // Gain reduction
      if (gainReduction < -0.1) {
        final grNorm = (gainReduction.abs() / 20).clamp(0.0, 1.0);
        final grHeight = grNorm * faderH;
        canvas.drawRect(
          Rect.fromLTWH(meterX, 0, stereo ? meterW * 2 + _meterGap : meterW, grHeight),
          Paint()..color = _meterColors.orange.withValues(alpha: 0.4),
        );
      }
    }

    // Fader track
    final trackX = showScale ? scaleW + 4 : 4.0;
    final trackW = showMeters ? 0.0 : 6.0;

    if (!showMeters) {
      canvas.drawRect(
        Rect.fromLTWH(trackX + (size.width - scaleW - 8) / 2 - 3, 0, trackW, faderH),
        Paint()..color = FluxForgeTheme.bgDeepest,
      );

      // Fill
      final fillH = faderH * normalized;
      canvas.drawRect(
        Rect.fromLTWH(trackX + (size.width - scaleW - 8) / 2 - 2, faderH - fillH, 4, fillH),
        Paint()..color = accentColor.withValues(alpha: 0.5),
      );
    }

    // Unity line (0dB)
    final unityNorm = (0 - min) / (max - min);
    final unityY = faderH - unityNorm * faderH;
    canvas.drawLine(
      Offset(scaleW, unityY),
      Offset(size.width, unityY),
      Paint()..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.5)..strokeWidth = 1,
    );

    // Fader thumb
    final thumbY = faderH * (1 - normalized);
    final thumbW = size.width - scaleW - 4;
    _drawThumb(canvas, scaleW + 2, thumbY - _faderThumbHeight / 2, thumbW, _faderThumbHeight);

    // Value display
    final textPainter = TextPainter(
      text: TextSpan(
        text: _formatDb(value),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: FluxForgeTheme.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width / 2 - textPainter.width / 2, faderH + 4),
    );
  }

  void _drawScale(Canvas canvas, Size size, double faderH) {
    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    for (final mark in _scaleMarks) {
      final norm = (mark - min) / (max - min);
      final y = faderH - norm * faderH;

      canvas.drawRect(
        Rect.fromLTWH(_scaleWidth - 8, y - 0.5, 6, 1),
        Paint()..color = mark == 0 ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
      );

      textPainter.text = TextSpan(
        text: mark == 0 ? '0' : (mark > 0 ? '+${mark.toInt()}' : '${mark.toInt()}'),
        style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(_scaleWidth - 10 - textPainter.width, y - textPainter.height / 2));
    }

    for (final mark in _minorMarks) {
      final norm = (mark - min) / (max - min);
      final y = faderH - norm * faderH;
      canvas.drawRect(
        Rect.fromLTWH(_scaleWidth - 4, y - 0.5, 3, 1),
        Paint()..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
      );
    }
  }

  void _drawMeterFill(Canvas canvas, double x, double level, double peak, bool clipping, double meterW, double faderH) {
    final meterHeight = level * faderH;
    final y = faderH - meterHeight;

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [_meterColors.greenDark, _meterColors.green, _meterColors.yellow, _meterColors.orange, _meterColors.red],
      stops: const [0, 0.6, 0.75, 0.88, 1],
    );

    canvas.drawRect(
      Rect.fromLTWH(x, y, meterW, meterHeight),
      Paint()..shader = gradient.createShader(Rect.fromLTWH(x, 0, meterW, faderH)),
    );

    // Peak hold
    final peakY = faderH - peak * faderH;
    canvas.drawRect(
      Rect.fromLTWH(x, peakY - 1, meterW, 2),
      Paint()..color = peak > 0.95 ? _meterColors.red : _meterColors.yellow,
    );

    // Clip indicator
    if (clipping) {
      canvas.drawRect(Rect.fromLTWH(x, 0, meterW, 4), Paint()..color = _meterColors.clip);
    }
  }

  void _drawThumb(Canvas canvas, double x, double y, double w, double h) {
    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y + 2, w, h), const Radius.circular(4)),
      Paint()..color = FluxForgeTheme.bgVoid.withValues(alpha: 0.6),
    );

    // Body
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        FluxForgeTheme.bgElevated,
        FluxForgeTheme.bgMid,
        FluxForgeTheme.bgDeep,
      ],
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4)),
      Paint()..shader = gradient.createShader(Rect.fromLTWH(x, y, w, h)),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = isDragging ? accentColor : FluxForgeTheme.borderMedium
        ..strokeWidth = isDragging ? 2 : 1,
    );

    // Center grip lines
    final lineY = y + h / 2;
    for (int i = -1; i <= 1; i++) {
      canvas.drawLine(
        Offset(x + 4, lineY + i * 3),
        Offset(x + w - 4, lineY + i * 3),
        Paint()..color = FluxForgeTheme.textTertiary..strokeWidth = 1,
      );
    }
  }

  String _formatDb(double db) {
    if (db <= min) return '-∞';
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_VerticalFaderPainter oldDelegate) =>
      normalized != oldDelegate.normalized ||
      meterL != oldDelegate.meterL ||
      meterR != oldDelegate.meterR ||
      peakHoldL != oldDelegate.peakHoldL ||
      peakHoldR != oldDelegate.peakHoldR ||
      isClippingL != oldDelegate.isClippingL ||
      isClippingR != oldDelegate.isClippingR ||
      isDragging != oldDelegate.isDragging;
}

/// Theme-Aware Audio Controls
///
/// Unified audio controls that automatically switch between
/// Classic (FluxForge) and Glass (Liquid Glass) themes.
///
/// Usage:
/// ```dart
/// // Instead of: Fader(value: db, ...)
/// ThemeAwareFader(value: db, ...)
///
/// // Instead of: Meter(levelDb: -12, ...)
/// ThemeAwareMeter(levelDb: -12, ...)
/// ```

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../theme/liquid_glass_theme.dart';
import 'fader.dart';
import 'meter.dart';

// ════════════════════════════════════════════════════════════════════════════
// THEME-AWARE FADER
// ════════════════════════════════════════════════════════════════════════════

/// Theme-aware fader that switches between Classic and Glass styles
class ThemeAwareFader extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double? meterL;
  final double? meterR;
  final double? peakL;
  final double? peakR;
  final double? gainReduction;
  final double width;
  final double height;
  final FaderStyle style;
  final FaderOrientation orientation;
  final bool showScale;
  final bool showMeters;
  final bool stereo;
  final Color? accentColor;
  final String? label;
  final bool disabled;

  const ThemeAwareFader({
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
  const ThemeAwareFader.simple({
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
  })  : meterL = null,
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
  const ThemeAwareFader.horizontal({
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
  })  : meterL = null,
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
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassFader(
        value: value,
        min: min,
        max: max,
        defaultValue: defaultValue,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        meterL: meterL,
        meterR: meterR,
        peakL: peakL,
        peakR: peakR,
        gainReduction: gainReduction,
        width: width,
        height: height,
        orientation: orientation,
        showScale: showScale,
        showMeters: showMeters,
        stereo: stereo,
        accentColor: accentColor ?? LiquidGlassTheme.accentBlue,
        label: label,
        disabled: disabled,
      );
    }

    return Fader(
      value: value,
      min: min,
      max: max,
      defaultValue: defaultValue,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      meterL: meterL,
      meterR: meterR,
      peakL: peakL,
      peakR: peakR,
      gainReduction: gainReduction,
      width: width,
      height: height,
      style: style,
      orientation: orientation,
      showScale: showScale,
      showMeters: showMeters,
      stereo: stereo,
      accentColor: accentColor,
      label: label,
      disabled: disabled,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS FADER
// ════════════════════════════════════════════════════════════════════════════

/// Liquid Glass styled fader with frosted glass effects
class GlassFader extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double? meterL;
  final double? meterR;
  final double? peakL;
  final double? peakR;
  final double? gainReduction;
  final double width;
  final double height;
  final FaderOrientation orientation;
  final bool showScale;
  final bool showMeters;
  final bool stereo;
  final Color accentColor;
  final String? label;
  final bool disabled;

  const GlassFader({
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
    this.orientation = FaderOrientation.vertical,
    this.showScale = true,
    this.showMeters = false,
    this.stereo = true,
    this.accentColor = const Color(0xFF4A9EFF),
    this.label,
    this.disabled = false,
  });

  @override
  State<GlassFader> createState() => _GlassFaderState();
}

class _GlassFaderState extends State<GlassFader>
    with TickerProviderStateMixin {
  late AnimationController _meterController;

  bool _isDragging = false;
  double _dragStartPos = 0;
  double _dragStartNorm = 0;

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
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    if (widget.showMeters) {
      _meterController.repeat();
    }
  }

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassFader oldWidget) {
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
      _peakHoldTimeL = now.add(const Duration(milliseconds: 1500));
    } else if (now.isAfter(_peakHoldTimeL)) {
      _peakHoldL = math.max(0, _peakHoldL - 0.003);
    }

    // Right channel
    if (peakR > _peakHoldR) {
      _peakHoldR = peakR;
      _peakHoldTimeR = now.add(const Duration(milliseconds: 1500));
    } else if (now.isAfter(_peakHoldTimeR)) {
      _peakHoldR = math.max(0, _peakHoldR - 0.003);
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
    return (db - widget.min) / (widget.max - widget.min);
  }

  double _normalizedToDb(double normalized) {
    if (normalized <= 0) return widget.min;
    if (normalized >= 1) return widget.max;
    return widget.min + (normalized * (widget.max - widget.min));
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _isDragging = true;
      _dragStartPos = widget.orientation == FaderOrientation.vertical
          ? details.localPosition.dy
          : details.localPosition.dx;
      _dragStartNorm = _dbToNormalized(widget.value);
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || widget.disabled) return;

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final sensitivity = isShiftHeld ? 0.2 : 1.0;

    double delta;
    double size;

    if (widget.orientation == FaderOrientation.vertical) {
      delta = _dragStartPos - details.localPosition.dy;
      size = widget.height - 20;
    } else {
      delta = details.localPosition.dx - _dragStartPos;
      size = widget.width - 10;
    }

    final deltaNorm = (delta / size) * sensitivity;
    final newNorm = (_dragStartNorm + deltaNorm).clamp(0.0, 1.0);
    final newValue = _normalizedToDb(newNorm);
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
      final scrollDelta =
          isVertical ? event.scrollDelta.dy : -event.scrollDelta.dx;
      final scrollMagnitude = scrollDelta.abs();
      final delta = scrollDelta > 0 ? -1.0 : 1.0;
      final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
      final baseStep = isShiftHeld ? 0.1 : 0.5;
      final step = baseStep * (1.0 + (scrollMagnitude / 50.0).clamp(0.0, 2.0));
      final newValue =
          (widget.value + delta * step).clamp(widget.min, widget.max);
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurLight,
          sigmaY: LiquidGlassTheme.blurLight,
        ),
        child: RepaintBoundary(
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: CustomPaint(
              painter: _GlassFaderPainter(
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
                accentColor: widget.accentColor,
                label: widget.label,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalFader() {
    final normalized = _dbToNormalized(widget.value);

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onDoubleTap: _onDoubleTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Stack(
              children: [
                // Fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  width: widget.width * normalized,
                  height: widget.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.accentColor.withValues(alpha: 0.4),
                        widget.accentColor.withValues(alpha: 0.2),
                      ],
                    ),
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
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.white.withValues(alpha: 0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: _isDragging
                          ? [
                              BoxShadow(
                                color: widget.accentColor.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: -2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS FADER PAINTER
// ════════════════════════════════════════════════════════════════════════════

class _GlassFaderPainter extends CustomPainter {
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

  static const _scaleWidth = 24.0;
  static const _meterGap = 2.0;
  static const _thumbHeight = 24.0;
  static const _scaleMarks = [
    12.0,
    6.0,
    3.0,
    0.0,
    -3.0,
    -6.0,
    -12.0,
    -18.0,
    -24.0,
    -36.0,
    -48.0,
    -60.0
  ];
  static const _minorMarks = [
    9.0,
    -9.0,
    -15.0,
    -21.0,
    -30.0,
    -42.0,
    -54.0
  ];

  _GlassFaderPainter({
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleW = showScale ? _scaleWidth : 0.0;
    final faderH = size.height - 20;

    // Glass background
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.06),
        Colors.black.withValues(alpha: 0.15),
      ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()..shader = bgGradient.createShader(bgRect),
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
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(meterX, 0, meterW, faderH),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.4),
      );
      if (stereo) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(meterX + meterW + _meterGap, 0, meterW, faderH),
            const Radius.circular(2),
          ),
          Paint()..color = Colors.black.withValues(alpha: 0.4),
        );
      }

      // Meter fills
      _drawMeterFill(
          canvas, meterX, meterL, peakHoldL, isClippingL, meterW, faderH);
      if (stereo) {
        _drawMeterFill(canvas, meterX + meterW + _meterGap, meterR, peakHoldR,
            isClippingR, meterW, faderH);
      }

      // Gain reduction overlay
      if (gainReduction < -0.1) {
        final grNorm = (gainReduction.abs() / 20).clamp(0.0, 1.0);
        final grHeight = grNorm * faderH;
        canvas.drawRect(
          Rect.fromLTWH(
              meterX, 0, stereo ? meterW * 2 + _meterGap : meterW, grHeight),
          Paint()..color = LiquidGlassTheme.accentOrange.withValues(alpha: 0.4),
        );
      }
    }

    // Fader track (when no meters)
    if (!showMeters) {
      final trackX = showScale ? scaleW + 4 : 4.0;
      final trackW = 6.0;

      // Track background
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              trackX + (size.width - scaleW - 8) / 2 - 3, 0, trackW, faderH),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );

      // Fill
      final fillH = faderH * normalized;
      final fillGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          accentColor.withValues(alpha: 0.6),
          accentColor.withValues(alpha: 0.3),
        ],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackX + (size.width - scaleW - 8) / 2 - 2,
              faderH - fillH, 4, fillH),
          const Radius.circular(2),
        ),
        Paint()..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, 4, faderH)),
      );
    }

    // Unity line (0dB)
    final unityNorm = (0 - min) / (max - min);
    final unityY = faderH - unityNorm * faderH;
    canvas.drawLine(
      Offset(scaleW, unityY),
      Offset(size.width, unityY),
      Paint()
        ..color = LiquidGlassTheme.accentGreen.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );

    // Fader thumb
    final thumbY = faderH * (1 - normalized);
    final thumbW = size.width - scaleW - 4;
    _drawGlassThumb(
        canvas, scaleW + 2, thumbY - _thumbHeight / 2, thumbW, _thumbHeight);

    // Value display
    final textPainter = TextPainter(
      text: TextSpan(
        text: _formatDb(value),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: LiquidGlassTheme.textPrimary,
          fontFamily: 'JetBrains Mono',
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
        Paint()
          ..color = mark == 0
              ? LiquidGlassTheme.accentGreen
              : LiquidGlassTheme.textTertiary,
      );

      textPainter.text = TextSpan(
        text: mark == 0 ? '0' : (mark > 0 ? '+${mark.toInt()}' : '${mark.toInt()}'),
        style: TextStyle(
          fontSize: 9,
          color: LiquidGlassTheme.textTertiary,
          fontFamily: 'JetBrains Mono',
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(_scaleWidth - 10 - textPainter.width, y - textPainter.height / 2));
    }

    for (final mark in _minorMarks) {
      final norm = (mark - min) / (max - min);
      final y = faderH - norm * faderH;
      canvas.drawRect(
        Rect.fromLTWH(_scaleWidth - 4, y - 0.5, 3, 1),
        Paint()..color = LiquidGlassTheme.textTertiary.withValues(alpha: 0.5),
      );
    }
  }

  void _drawMeterFill(Canvas canvas, double x, double level, double peak,
      bool clipping, double meterW, double faderH) {
    final meterHeight = level * faderH;
    final y = faderH - meterHeight;

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        LiquidGlassTheme.accentCyan,
        LiquidGlassTheme.accentGreen,
        LiquidGlassTheme.accentYellow,
        LiquidGlassTheme.accentOrange,
        LiquidGlassTheme.accentRed,
      ],
      stops: const [0.0, 0.5, 0.7, 0.85, 1.0],
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, meterW, meterHeight),
        const Radius.circular(1),
      ),
      Paint()..shader = gradient.createShader(Rect.fromLTWH(x, 0, meterW, faderH)),
    );

    // Peak hold
    final peakY = faderH - peak * faderH;
    canvas.drawRect(
      Rect.fromLTWH(x, peakY - 1, meterW, 2),
      Paint()
        ..color = peak > 0.95 ? LiquidGlassTheme.accentRed : LiquidGlassTheme.accentYellow,
    );

    // Clip indicator
    if (clipping) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, meterW, 4),
          const Radius.circular(1),
        ),
        Paint()..color = LiquidGlassTheme.accentRed,
      );
      // Glow
      canvas.drawRect(
        Rect.fromLTWH(x, 0, meterW, 6),
        Paint()
          ..color = LiquidGlassTheme.accentRed.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _drawGlassThumb(Canvas canvas, double x, double y, double w, double h) {
    final rect = Rect.fromLTWH(x, y, w, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y + 2, w, h),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Glass body gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: 0.25),
        Colors.white.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.1),
      ],
    );

    canvas.drawRRect(
      rrect,
      Paint()..shader = gradient.createShader(rect),
    );

    // Border
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = isDragging
            ? accentColor
            : Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = isDragging ? 2 : 1,
    );

    // Specular highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2, y + 1, w - 4, 1),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );

    // Center grip lines
    final lineY = y + h / 2;
    for (int i = -1; i <= 1; i++) {
      canvas.drawLine(
        Offset(x + 6, lineY + i * 3),
        Offset(x + w - 6, lineY + i * 3),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
    }

    // Glow when dragging
    if (isDragging) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = accentColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  String _formatDb(double db) {
    if (db <= min) return '-∞';
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_GlassFaderPainter oldDelegate) =>
      normalized != oldDelegate.normalized ||
      meterL != oldDelegate.meterL ||
      meterR != oldDelegate.meterR ||
      peakHoldL != oldDelegate.peakHoldL ||
      peakHoldR != oldDelegate.peakHoldR ||
      isClippingL != oldDelegate.isClippingL ||
      isClippingR != oldDelegate.isClippingR ||
      isDragging != oldDelegate.isDragging;
}

// ════════════════════════════════════════════════════════════════════════════
// THEME-AWARE METER
// ════════════════════════════════════════════════════════════════════════════

/// Theme-aware meter that switches between Classic and Glass styles
class ThemeAwareMeter extends StatelessWidget {
  final double? levelDb;
  final AudioLevels? levels;
  final double? peakHoldDb;
  final bool isClipping;
  final Axis orientation;
  final MeterStyle style;
  final MeterMode mode;
  final bool stereo;
  final double? rightLevelDb;
  final double width;
  final double height;
  final double minDb;
  final double maxDb;
  final int segments;
  final bool showScale;
  final double peakHoldTime;
  final double peakDecayRate;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const ThemeAwareMeter({
    super.key,
    this.levelDb,
    this.levels,
    this.peakHoldDb,
    this.isClipping = false,
    this.orientation = Axis.vertical,
    this.style = MeterStyle.smooth,
    this.mode = MeterMode.peak,
    this.stereo = false,
    this.rightLevelDb,
    this.width = 8,
    this.height = 120,
    this.minDb = -60,
    this.maxDb = 6,
    this.segments = 30,
    this.showScale = false,
    this.peakHoldTime = 1500,
    this.peakDecayRate = 0.5,
    this.backgroundColor,
    this.onTap,
  });

  /// Simple vertical meter
  const ThemeAwareMeter.simple({
    super.key,
    required double level,
    double? peakHold,
    bool clipping = false,
    double thickness = 8,
    double height = 100,
  })  : levelDb = level,
        levels = null,
        peakHoldDb = peakHold,
        isClipping = clipping,
        orientation = Axis.vertical,
        style = MeterStyle.smooth,
        mode = MeterMode.peak,
        stereo = false,
        rightLevelDb = null,
        width = thickness,
        this.height = height,
        minDb = -60,
        maxDb = 6,
        segments = 30,
        showScale = false,
        peakHoldTime = 1500,
        peakDecayRate = 0.5,
        backgroundColor = null,
        onTap = null;

  /// Stereo meter pair
  const ThemeAwareMeter.stereo({
    super.key,
    required double leftDb,
    required double rightDb,
    double? leftPeak,
    bool leftClip = false,
    double width = 24,
    double height = 120,
    bool showLabels = true,
  })  : levelDb = leftDb,
        levels = null,
        peakHoldDb = leftPeak,
        isClipping = leftClip,
        orientation = Axis.vertical,
        style = MeterStyle.smooth,
        mode = MeterMode.peak,
        stereo = true,
        rightLevelDb = rightDb,
        this.width = width,
        this.height = height,
        minDb = -60,
        maxDb = 6,
        segments = 30,
        showScale = showLabels,
        peakHoldTime = 1500,
        peakDecayRate = 0.5,
        backgroundColor = null,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassMeter(
        levelDb: levelDb,
        levels: levels,
        peakHoldDb: peakHoldDb,
        isClipping: isClipping,
        orientation: orientation,
        style: style,
        mode: mode,
        stereo: stereo,
        rightLevelDb: rightLevelDb,
        width: width,
        height: height,
        minDb: minDb,
        maxDb: maxDb,
        segments: segments,
        showScale: showScale,
        peakHoldTime: peakHoldTime,
        peakDecayRate: peakDecayRate,
        onTap: onTap,
      );
    }

    return Meter(
      levelDb: levelDb,
      levels: levels,
      peakHoldDb: peakHoldDb,
      isClipping: isClipping,
      orientation: orientation,
      style: style,
      mode: mode,
      stereo: stereo,
      rightLevelDb: rightLevelDb,
      width: width,
      height: height,
      minDb: minDb,
      maxDb: maxDb,
      segments: segments,
      showScale: showScale,
      peakHoldTime: peakHoldTime,
      peakDecayRate: peakDecayRate,
      backgroundColor: backgroundColor,
      onTap: onTap,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS METER
// ════════════════════════════════════════════════════════════════════════════

/// Liquid Glass styled audio level meter
class GlassMeter extends StatefulWidget {
  final double? levelDb;
  final AudioLevels? levels;
  final double? peakHoldDb;
  final bool isClipping;
  final Axis orientation;
  final MeterStyle style;
  final MeterMode mode;
  final bool stereo;
  final double? rightLevelDb;
  final double width;
  final double height;
  final double minDb;
  final double maxDb;
  final int segments;
  final bool showScale;
  final double peakHoldTime;
  final double peakDecayRate;
  final VoidCallback? onTap;

  const GlassMeter({
    super.key,
    this.levelDb,
    this.levels,
    this.peakHoldDb,
    this.isClipping = false,
    this.orientation = Axis.vertical,
    this.style = MeterStyle.smooth,
    this.mode = MeterMode.peak,
    this.stereo = false,
    this.rightLevelDb,
    this.width = 8,
    this.height = 120,
    this.minDb = -60,
    this.maxDb = 6,
    this.segments = 30,
    this.showScale = false,
    this.peakHoldTime = 1500,
    this.peakDecayRate = 0.5,
    this.onTap,
  });

  @override
  State<GlassMeter> createState() => _GlassMeterState();
}

class _GlassMeterState extends State<GlassMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _peakHoldL = -60;
  double _peakHoldR = -60;
  DateTime _peakHoldTimeL = DateTime.now();
  DateTime _peakHoldTimeR = DateTime.now();
  bool _clipL = false;
  bool _clipR = false;
  DateTime _clipTimeL = DateTime.now();
  DateTime _clipTimeR = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getCurrentLevelDb() {
    if (widget.levels != null) {
      return widget.mode == MeterMode.rms
          ? widget.levels!.rmsDb
          : widget.levels!.peakDb;
    }
    return widget.levelDb ?? widget.minDb;
  }

  double _getCurrentRightDb() {
    if (widget.levels?.peakR != null) {
      final peakR = widget.levels!.peakR!;
      return peakR > 0 ? 20 * math.log(peakR) / math.ln10 : widget.minDb;
    }
    return widget.rightLevelDb ?? _getCurrentLevelDb();
  }

  void _updatePeakHold() {
    final now = DateTime.now();
    final levelDbL = _getCurrentLevelDb();
    final levelDbR = _getCurrentRightDb();

    // Left channel peak hold
    if (widget.peakHoldDb != null) {
      _peakHoldL = widget.peakHoldDb!;
    } else {
      if (levelDbL > _peakHoldL) {
        _peakHoldL = levelDbL;
        _peakHoldTimeL = now;
      } else if (now.difference(_peakHoldTimeL).inMilliseconds >
          widget.peakHoldTime) {
        _peakHoldL = math.max(widget.minDb, _peakHoldL - widget.peakDecayRate);
      }
    }

    // Right channel peak hold
    if (widget.stereo) {
      if (levelDbR > _peakHoldR) {
        _peakHoldR = levelDbR;
        _peakHoldTimeR = now;
      } else if (now.difference(_peakHoldTimeR).inMilliseconds >
          widget.peakHoldTime) {
        _peakHoldR = math.max(widget.minDb, _peakHoldR - widget.peakDecayRate);
      }
    }

    // Clip detection
    if (widget.isClipping || levelDbL >= widget.maxDb - 0.1) {
      _clipL = true;
      _clipTimeL = now;
    } else if (now.difference(_clipTimeL).inMilliseconds > 2000) {
      _clipL = false;
    }

    if (widget.stereo && (levelDbR >= widget.maxDb - 0.1)) {
      _clipR = true;
      _clipTimeR = now;
    } else if (now.difference(_clipTimeR).inMilliseconds > 2000) {
      _clipR = false;
    }
  }

  double _dbToNormalized(double db) {
    return ((db - widget.minDb) / (widget.maxDb - widget.minDb))
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        setState(() {
          _peakHoldL = widget.minDb;
          _peakHoldR = widget.minDb;
          _clipL = false;
          _clipR = false;
        });
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _updatePeakHold();

          if (widget.stereo) {
            return _buildStereoMeter();
          }

          return _buildSingleMeter(
            _dbToNormalized(_getCurrentLevelDb()),
            _dbToNormalized(_peakHoldL),
            _clipL,
          );
        },
      ),
    );
  }

  Widget _buildSingleMeter(double level, double peakHold, bool isClipping) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _GlassMeterPainter(
              level: level,
              rmsLevel: widget.mode == MeterMode.both && widget.levels != null
                  ? _dbToNormalized(widget.levels!.rmsDb)
                  : null,
              peakHold: peakHold,
              isClipping: isClipping,
              orientation: widget.orientation,
              style: widget.style,
              segments: widget.segments,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStereoMeter() {
    final isVertical = widget.orientation == Axis.vertical;
    final meterThickness =
        isVertical ? (widget.width - 4) / 2 : (widget.height - 4) / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              if (widget.showScale && isVertical)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('L',
                          style: TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          )),
                      Text('R',
                          style: TextStyle(
                            color: LiquidGlassTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size(meterThickness, double.infinity),
                        painter: _GlassMeterPainter(
                          level: _dbToNormalized(_getCurrentLevelDb()),
                          peakHold: _dbToNormalized(_peakHoldL),
                          isClipping: _clipL,
                          orientation: widget.orientation,
                          style: widget.style,
                          segments: widget.segments,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: CustomPaint(
                        size: Size(meterThickness, double.infinity),
                        painter: _GlassMeterPainter(
                          level: _dbToNormalized(_getCurrentRightDb()),
                          peakHold: _dbToNormalized(_peakHoldR),
                          isClipping: _clipR,
                          orientation: widget.orientation,
                          style: widget.style,
                          segments: widget.segments,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS METER PAINTER
// ════════════════════════════════════════════════════════════════════════════

class _GlassMeterPainter extends CustomPainter {
  final double level;
  final double? rmsLevel;
  final double peakHold;
  final bool isClipping;
  final Axis orientation;
  final MeterStyle style;
  final int segments;

  _GlassMeterPainter({
    required this.level,
    this.rmsLevel,
    required this.peakHold,
    required this.isClipping,
    required this.orientation,
    required this.style,
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isVertical = orientation == Axis.vertical;
    final rect = Offset.zero & size;

    // Glass background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    // Choose rendering style
    switch (style) {
      case MeterStyle.smooth:
        _drawSmoothMeter(canvas, size, isVertical);
        break;
      case MeterStyle.segmented:
      case MeterStyle.vu:
        _drawSegmentedMeter(canvas, size, isVertical);
        break;
    }

    // Peak hold indicator
    if (peakHold > 0.01) {
      _drawPeakHold(canvas, size, isVertical);
    }

    // Clip indicator
    if (isClipping) {
      _drawClipIndicator(canvas, size, isVertical);
    }
  }

  void _drawSmoothMeter(Canvas canvas, Size size, bool isVertical) {
    if (level <= 0) return;

    final gradient = _createGradient(isVertical);

    final levelRect = isVertical
        ? Rect.fromLTWH(
            1, size.height * (1 - level), size.width - 2, size.height * level)
        : Rect.fromLTWH(0, 1, size.width * level, size.height - 2);

    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(levelRect, const Radius.circular(1)),
      paint,
    );

    // Glow at top
    final glowColor = _getColorForLevel(level);
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    if (isVertical) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * (1 - level), size.width, 4),
        glowPaint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(size.width * level - 4, 0, 4, size.height),
        glowPaint,
      );
    }

    // RMS overlay
    if (rmsLevel != null && rmsLevel! > 0) {
      final rmsRect = isVertical
          ? Rect.fromLTWH(
              size.width * 0.25,
              size.height * (1 - rmsLevel!),
              size.width * 0.5,
              size.height * rmsLevel!,
            )
          : Rect.fromLTWH(
              0,
              size.height * 0.25,
              size.width * rmsLevel!,
              size.height * 0.5,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rmsRect, const Radius.circular(1)),
        Paint()..color = LiquidGlassTheme.accentBlue.withValues(alpha: 0.7),
      );
    }
  }

  void _drawSegmentedMeter(Canvas canvas, Size size, bool isVertical) {
    const gap = 1.0;
    final segmentSize = isVertical
        ? (size.height - gap * (segments - 1)) / segments
        : (size.width - gap * (segments - 1)) / segments;

    final activeSegments = (level * segments).ceil();

    for (int i = 0; i < segments; i++) {
      final isActive = i < activeSegments;
      final segmentLevel = i / segments;
      final color = _getColorForLevel(segmentLevel);

      final paint = Paint()
        ..color = isActive ? color : color.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      final segmentRect = isVertical
          ? Rect.fromLTWH(
              1,
              size.height - (i + 1) * (segmentSize + gap) + gap,
              size.width - 2,
              segmentSize,
            )
          : Rect.fromLTWH(
              i * (segmentSize + gap),
              1,
              segmentSize,
              size.height - 2,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, const Radius.circular(1)),
        paint,
      );
    }
  }

  void _drawPeakHold(Canvas canvas, Size size, bool isVertical) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (isVertical) {
      final y = size.height * (1 - peakHold);
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), paint);
    } else {
      final x = size.width * peakHold;
      canvas.drawLine(Offset(x, 1), Offset(x, size.height - 1), paint);
    }
  }

  void _drawClipIndicator(Canvas canvas, Size size, bool isVertical) {
    final clipRect = isVertical
        ? Rect.fromLTWH(1, 1, size.width - 2, 4)
        : Rect.fromLTWH(size.width - 5, 1, 4, size.height - 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(clipRect, const Radius.circular(1)),
      Paint()..color = LiquidGlassTheme.accentRed,
    );

    // Glow
    canvas.drawRect(
      clipRect,
      Paint()
        ..color = LiquidGlassTheme.accentRed.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  LinearGradient _createGradient(bool isVertical) {
    final colors = [
      LiquidGlassTheme.accentCyan,
      LiquidGlassTheme.accentGreen,
      LiquidGlassTheme.accentYellow,
      LiquidGlassTheme.accentOrange,
      LiquidGlassTheme.accentRed,
    ];
    const stops = [0.0, 0.5, 0.7, 0.85, 1.0];

    return isVertical
        ? LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: colors,
            stops: stops,
          )
        : LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
            stops: stops,
          );
  }

  Color _getColorForLevel(double lvl) {
    if (lvl < 0.5) {
      return Color.lerp(
          LiquidGlassTheme.accentCyan, LiquidGlassTheme.accentGreen, lvl * 2)!;
    } else if (lvl < 0.7) {
      return Color.lerp(LiquidGlassTheme.accentGreen,
          LiquidGlassTheme.accentYellow, (lvl - 0.5) * 5)!;
    } else if (lvl < 0.85) {
      return Color.lerp(LiquidGlassTheme.accentYellow,
          LiquidGlassTheme.accentOrange, (lvl - 0.7) * 6.67)!;
    } else {
      return Color.lerp(LiquidGlassTheme.accentOrange,
          LiquidGlassTheme.accentRed, (lvl - 0.85) * 6.67)!;
    }
  }

  @override
  bool shouldRepaint(_GlassMeterPainter oldDelegate) =>
      level != oldDelegate.level ||
      rmsLevel != oldDelegate.rmsLevel ||
      peakHold != oldDelegate.peakHold ||
      isClipping != oldDelegate.isClipping;
}

// ════════════════════════════════════════════════════════════════════════════
// THEME-AWARE KNOB
// ════════════════════════════════════════════════════════════════════════════

/// Theme-aware rotary knob that switches between Classic and Glass styles
class ThemeAwareKnob extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double size;
  final String? label;
  final String? valueLabel;
  final Color? accentColor;
  final bool bipolar;
  final bool disabled;

  const ThemeAwareKnob({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.defaultValue = 0.5,
    this.onChanged,
    this.onChangeEnd,
    this.size = 48,
    this.label,
    this.valueLabel,
    this.accentColor,
    this.bipolar = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassKnob(
        value: value,
        min: min,
        max: max,
        defaultValue: defaultValue,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        size: size,
        label: label,
        valueLabel: valueLabel,
        accentColor: accentColor ?? LiquidGlassTheme.accentBlue,
        bipolar: bipolar,
        disabled: disabled,
      );
    }

    // Classic knob - use existing or simple implementation
    return _ClassicKnob(
      value: value,
      min: min,
      max: max,
      defaultValue: defaultValue,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      size: size,
      label: label,
      valueLabel: valueLabel,
      accentColor: accentColor ?? FluxForgeTheme.accentBlue,
      bipolar: bipolar,
      disabled: disabled,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS KNOB
// ════════════════════════════════════════════════════════════════════════════

/// Liquid Glass styled rotary knob
class GlassKnob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double size;
  final String? label;
  final String? valueLabel;
  final Color accentColor;
  final bool bipolar;
  final bool disabled;

  const GlassKnob({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.defaultValue = 0.5,
    this.onChanged,
    this.onChangeEnd,
    this.size = 48,
    this.label,
    this.valueLabel,
    this.accentColor = const Color(0xFF4A9EFF),
    this.bipolar = false,
    this.disabled = false,
  });

  @override
  State<GlassKnob> createState() => _GlassKnobState();
}

class _GlassKnobState extends State<GlassKnob> {
  bool _isDragging = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  double get _normalized =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _onPanStart(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _isDragging = true;
      _dragStartY = details.localPosition.dy;
      _dragStartValue = widget.value;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || widget.disabled) return;

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final sensitivity = isShiftHeld ? 0.002 : 0.01;

    final delta = (_dragStartY - details.localPosition.dy) * sensitivity;
    final range = widget.max - widget.min;
    final newValue = (_dragStartValue + delta * range).clamp(widget.min, widget.max);

    widget.onChanged?.call(newValue);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    widget.onChangeEnd?.call(widget.value);
  }

  void _onDoubleTap() {
    if (widget.disabled) return;
    widget.onChanged?.call(widget.defaultValue);
    widget.onChangeEnd?.call(widget.defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.label!,
              style: TextStyle(
                color: LiquidGlassTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onDoubleTap: _onDoubleTap,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _GlassKnobPainter(
                  normalized: _normalized,
                  isDragging: _isDragging,
                  accentColor: widget.accentColor,
                  bipolar: widget.bipolar,
                ),
              ),
            ),
          ),
        ),
        if (widget.valueLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.valueLabel!,
              style: TextStyle(
                color: LiquidGlassTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GLASS KNOB PAINTER
// ════════════════════════════════════════════════════════════════════════════

class _GlassKnobPainter extends CustomPainter {
  final double normalized;
  final bool isDragging;
  final Color accentColor;
  final bool bipolar;

  static const _startAngle = 2.35619; // 135 degrees
  static const _sweepAngle = 4.71239; // 270 degrees

  _GlassKnobPainter({
    required this.normalized,
    required this.isDragging,
    required this.accentColor,
    required this.bipolar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer ring (glass effect)
    final outerGradient = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: 0.15),
        Colors.white.withValues(alpha: 0.05),
        Colors.black.withValues(alpha: 0.2),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = outerGradient.createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Track background
    final trackRect = Rect.fromCircle(center: center, radius: radius - 4);
    canvas.drawArc(
      trackRect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.3),
    );

    // Value arc
    double valueSweep;
    double valueStart;

    if (bipolar) {
      final centerNorm = 0.5;
      if (normalized >= centerNorm) {
        valueStart = _startAngle + _sweepAngle * centerNorm;
        valueSweep = _sweepAngle * (normalized - centerNorm);
      } else {
        valueSweep = _sweepAngle * (centerNorm - normalized);
        valueStart = _startAngle + _sweepAngle * normalized;
      }
    } else {
      valueStart = _startAngle;
      valueSweep = _sweepAngle * normalized;
    }

    canvas.drawArc(
      trackRect,
      valueStart,
      valueSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accentColor,
    );

    // Inner knob
    final innerRadius = radius - 8;
    final innerGradient = RadialGradient(
      colors: [
        Colors.white.withValues(alpha: 0.2),
        Colors.white.withValues(alpha: 0.08),
        Colors.black.withValues(alpha: 0.15),
      ],
      stops: const [0.0, 0.6, 1.0],
    );

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..shader = innerGradient.createShader(Rect.fromCircle(center: center, radius: innerRadius)),
    );

    // Inner border
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: isDragging ? 0.4 : 0.2),
    );

    // Indicator line
    final indicatorAngle = _startAngle + _sweepAngle * normalized;
    final indicatorStart = center + Offset(
      math.cos(indicatorAngle) * (innerRadius - 8),
      math.sin(indicatorAngle) * (innerRadius - 8),
    );
    final indicatorEnd = center + Offset(
      math.cos(indicatorAngle) * (innerRadius - 2),
      math.sin(indicatorAngle) * (innerRadius - 2),
    );

    canvas.drawLine(
      indicatorStart,
      indicatorEnd,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );

    // Glow when dragging
    if (isDragging) {
      canvas.drawCircle(
        center,
        radius + 2,
        Paint()
          ..color = accentColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassKnobPainter oldDelegate) =>
      normalized != oldDelegate.normalized ||
      isDragging != oldDelegate.isDragging ||
      accentColor != oldDelegate.accentColor;
}

// ════════════════════════════════════════════════════════════════════════════
// CLASSIC KNOB (FALLBACK)
// ════════════════════════════════════════════════════════════════════════════

class _ClassicKnob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double size;
  final String? label;
  final String? valueLabel;
  final Color accentColor;
  final bool bipolar;
  final bool disabled;

  const _ClassicKnob({
    required this.value,
    this.min = 0,
    this.max = 1,
    this.defaultValue = 0.5,
    this.onChanged,
    this.onChangeEnd,
    this.size = 48,
    this.label,
    this.valueLabel,
    required this.accentColor,
    this.bipolar = false,
    this.disabled = false,
  });

  @override
  State<_ClassicKnob> createState() => _ClassicKnobState();
}

class _ClassicKnobState extends State<_ClassicKnob> {
  bool _isDragging = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  double get _normalized =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _onPanStart(DragStartDetails details) {
    if (widget.disabled) return;
    setState(() {
      _isDragging = true;
      _dragStartY = details.localPosition.dy;
      _dragStartValue = widget.value;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || widget.disabled) return;

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
    final sensitivity = isShiftHeld ? 0.002 : 0.01;

    final delta = (_dragStartY - details.localPosition.dy) * sensitivity;
    final range = widget.max - widget.min;
    final newValue = (_dragStartValue + delta * range).clamp(widget.min, widget.max);

    widget.onChanged?.call(newValue);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    widget.onChangeEnd?.call(widget.value);
  }

  void _onDoubleTap() {
    if (widget.disabled) return;
    widget.onChanged?.call(widget.defaultValue);
    widget.onChangeEnd?.call(widget.defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.label!,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onDoubleTap: _onDoubleTap,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _ClassicKnobPainter(
              normalized: _normalized,
              isDragging: _isDragging,
              accentColor: widget.accentColor,
              bipolar: widget.bipolar,
            ),
          ),
        ),
        if (widget.valueLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.valueLabel!,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
      ],
    );
  }
}

class _ClassicKnobPainter extends CustomPainter {
  final double normalized;
  final bool isDragging;
  final Color accentColor;
  final bool bipolar;

  static const _startAngle = 2.35619;
  static const _sweepAngle = 4.71239;

  _ClassicKnobPainter({
    required this.normalized,
    required this.isDragging,
    required this.accentColor,
    required this.bipolar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer ring
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = FluxForgeTheme.bgMid,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = FluxForgeTheme.borderSubtle,
    );

    // Track background
    final trackRect = Rect.fromCircle(center: center, radius: radius - 4);
    canvas.drawArc(
      trackRect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = FluxForgeTheme.bgDeepest,
    );

    // Value arc
    double valueSweep;
    double valueStart;

    if (bipolar) {
      final centerNorm = 0.5;
      if (normalized >= centerNorm) {
        valueStart = _startAngle + _sweepAngle * centerNorm;
        valueSweep = _sweepAngle * (normalized - centerNorm);
      } else {
        valueSweep = _sweepAngle * (centerNorm - normalized);
        valueStart = _startAngle + _sweepAngle * normalized;
      }
    } else {
      valueStart = _startAngle;
      valueSweep = _sweepAngle * normalized;
    }

    canvas.drawArc(
      trackRect,
      valueStart,
      valueSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accentColor,
    );

    // Inner knob
    final innerRadius = radius - 8;
    final innerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        FluxForgeTheme.bgElevated,
        FluxForgeTheme.bgMid,
        FluxForgeTheme.bgDeep,
      ],
    );

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..shader = innerGradient.createShader(Rect.fromCircle(center: center, radius: innerRadius)),
    );

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = isDragging ? accentColor : FluxForgeTheme.borderMedium,
    );

    // Indicator line
    final indicatorAngle = _startAngle + _sweepAngle * normalized;
    final indicatorStart = center + Offset(
      math.cos(indicatorAngle) * (innerRadius - 6),
      math.sin(indicatorAngle) * (innerRadius - 6),
    );
    final indicatorEnd = center + Offset(
      math.cos(indicatorAngle) * (innerRadius - 2),
      math.sin(indicatorAngle) * (innerRadius - 2),
    );

    canvas.drawLine(
      indicatorStart,
      indicatorEnd,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = FluxForgeTheme.textPrimary,
    );
  }

  @override
  bool shouldRepaint(_ClassicKnobPainter oldDelegate) =>
      normalized != oldDelegate.normalized ||
      isDragging != oldDelegate.isDragging ||
      accentColor != oldDelegate.accentColor;
}

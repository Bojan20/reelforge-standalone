/// Drag Smoothing Utilities
///
/// Professional DAW-style drag with:
/// - Velocity tracking for momentum
/// - Easing for smooth transitions
/// - Snap feedback
/// - Inertia for natural feel

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/timeline_models.dart' show gridIntervalSeconds;

// =============================================================================
// VELOCITY TRACKER
// =============================================================================

/// Tracks drag velocity for momentum calculations
class DragVelocityTracker {
  final List<_VelocitySample> _samples = [];
  static const int _maxSamples = 8;
  static const Duration _maxAge = Duration(milliseconds: 100);

  /// Add a position sample
  void addSample(Offset position, DateTime timestamp) {
    _samples.add(_VelocitySample(position, timestamp));

    // Remove old samples
    final cutoff = timestamp.subtract(_maxAge);
    _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));

    // Keep max samples
    while (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Get current velocity in pixels/second
  Offset get velocity {
    if (_samples.length < 2) return Offset.zero;

    final first = _samples.first;
    final last = _samples.last;
    final dt = last.timestamp.difference(first.timestamp).inMicroseconds / 1000000;

    if (dt <= 0) return Offset.zero;

    return Offset(
      (last.position.dx - first.position.dx) / dt,
      (last.position.dy - first.position.dy) / dt,
    );
  }

  /// Get velocity magnitude
  double get speed => velocity.distance;

  /// Clear all samples
  void clear() => _samples.clear();
}

class _VelocitySample {
  final Offset position;
  final DateTime timestamp;

  _VelocitySample(this.position, this.timestamp);
}

// =============================================================================
// SMOOTHED DRAG STATE
// =============================================================================

/// Maintains smoothed drag state with easing
class SmoothedDragState {
  Offset _targetPosition = Offset.zero;
  Offset _currentPosition = Offset.zero;
  Offset _startPosition = Offset.zero;
  double _smoothingFactor;
  final DragVelocityTracker _velocityTracker = DragVelocityTracker();

  SmoothedDragState({double smoothingFactor = 0.3})
      : _smoothingFactor = smoothingFactor;

  /// Start a new drag
  void start(Offset position) {
    _startPosition = position;
    _currentPosition = position;
    _targetPosition = position;
    _velocityTracker.clear();
    _velocityTracker.addSample(position, DateTime.now());
  }

  /// Update drag with new target position
  void update(Offset targetPosition) {
    _targetPosition = targetPosition;
    _velocityTracker.addSample(targetPosition, DateTime.now());

    // Apply exponential smoothing (lerp towards target)
    _currentPosition = Offset.lerp(_currentPosition, _targetPosition, _smoothingFactor)!;
  }

  /// Tick for animation frame - returns true if still animating
  bool tick() {
    final dx = _targetPosition.dx - _currentPosition.dx;
    final dy = _targetPosition.dy - _currentPosition.dy;

    if (dx.abs() < 0.5 && dy.abs() < 0.5) {
      _currentPosition = _targetPosition;
      return false;
    }

    _currentPosition = Offset.lerp(_currentPosition, _targetPosition, _smoothingFactor)!;
    return true;
  }

  /// Get current smoothed position
  Offset get position => _currentPosition;

  /// Get target position (unsmoothed)
  Offset get targetPosition => _targetPosition;

  /// Get start position
  Offset get startPosition => _startPosition;

  /// Get total delta from start
  Offset get totalDelta => _currentPosition - _startPosition;

  /// Get current velocity
  Offset get velocity => _velocityTracker.velocity;

  /// Get current speed
  double get speed => _velocityTracker.speed;

  /// Set smoothing factor (0 = instant, 1 = no movement)
  set smoothingFactor(double value) {
    _smoothingFactor = value.clamp(0.05, 0.95);
  }
}

// =============================================================================
// SNAP FEEDBACK STATE
// =============================================================================

/// Manages snap feedback animation
class SnapFeedbackState {
  bool _isSnapped = false;
  double _snapX = 0;
  double _snapStrength = 0;
  DateTime? _snapTime;
  String? _snapType; // 'grid', 'event', 'marker'

  static const Duration _feedbackDuration = Duration(milliseconds: 200);

  /// Notify that snap occurred
  void onSnap(double x, {String type = 'grid'}) {
    _isSnapped = true;
    _snapX = x;
    _snapStrength = 1.0;
    _snapTime = DateTime.now();
    _snapType = type;
  }

  /// Clear snap state
  void clear() {
    _isSnapped = false;
    _snapStrength = 0;
    _snapType = null;
  }

  /// Tick animation - returns true if still animating
  bool tick() {
    if (!_isSnapped || _snapTime == null) return false;

    final elapsed = DateTime.now().difference(_snapTime!);
    if (elapsed > _feedbackDuration) {
      clear();
      return false;
    }

    // Fade out
    _snapStrength = 1.0 - (elapsed.inMilliseconds / _feedbackDuration.inMilliseconds);
    return true;
  }

  /// Is snap feedback active?
  bool get isActive => _isSnapped && _snapStrength > 0;

  /// X position of snap line
  double get snapX => _snapX;

  /// Opacity of snap feedback (0-1)
  double get strength => _snapStrength;

  /// Type of snap
  String? get type => _snapType;
}

// =============================================================================
// EASING CURVES
// =============================================================================

/// Professional easing curves for drag operations
class DragEasing {
  /// Smooth deceleration (ease-out)
  static double easeOut(double t) {
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  /// Smooth acceleration (ease-in)
  static double easeIn(double t) {
    return math.pow(t, 3).toDouble();
  }

  /// Smooth both ends (ease-in-out)
  static double easeInOut(double t) {
    return t < 0.5
        ? 4 * math.pow(t, 3).toDouble()
        : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  }

  /// Spring-like overshoot
  static double spring(double t) {
    const c4 = (2 * math.pi) / 3;
    return t == 0
        ? 0
        : t == 1
            ? 1
            : math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1;
  }

  /// Magnetic snap feel
  static double magnetic(double t, double threshold) {
    if (t < threshold) {
      // Accelerate towards snap point
      return easeIn(t / threshold) * threshold;
    } else {
      // Decelerate after snap
      return threshold + easeOut((t - threshold) / (1 - threshold)) * (1 - threshold);
    }
  }
}

// =============================================================================
// SNAP LINE PAINTER
// =============================================================================

/// Paints visual snap feedback
class SnapLinePainter extends CustomPainter {
  final double snapX;
  final double strength;
  final String? type;
  final Color gridColor;
  final Color eventColor;
  final Color markerColor;

  SnapLinePainter({
    required this.snapX,
    required this.strength,
    this.type,
    this.gridColor = const Color(0xFF4a9eff),
    this.eventColor = const Color(0xFFff9040),
    this.markerColor = const Color(0xFF40ff90),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;

    final color = switch (type) {
      'event' => eventColor,
      'marker' => markerColor,
      _ => gridColor,
    };

    // Main snap line
    final linePaint = Paint()
      ..color = color.withOpacity(strength * 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(snapX, 0),
      Offset(snapX, size.height),
      linePaint,
    );

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(strength * 0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(
      Offset(snapX, 0),
      Offset(snapX, size.height),
      glowPaint,
    );

    // Snap indicator triangle at top
    final indicatorPath = Path()
      ..moveTo(snapX - 6, 0)
      ..lineTo(snapX + 6, 0)
      ..lineTo(snapX, 10)
      ..close();

    final indicatorPaint = Paint()
      ..color = color.withOpacity(strength)
      ..style = PaintingStyle.fill;

    canvas.drawPath(indicatorPath, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant SnapLinePainter oldDelegate) {
    return oldDelegate.snapX != snapX ||
        oldDelegate.strength != strength ||
        oldDelegate.type != type;
  }
}

// =============================================================================
// GRID OVERLAY PAINTER
// =============================================================================

/// Paints grid lines for snap visualization
class GridOverlayPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double snapValue;
  final double tempo;
  final bool showGrid;
  final double opacity;

  GridOverlayPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.snapValue,
    required this.tempo,
    this.showGrid = true,
    this.opacity = 0.15,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid || opacity <= 0) return;

    final gridInterval = gridIntervalSeconds(snapValue, tempo);
    final pixelsPerGrid = gridInterval * zoom;

    // Skip if grid lines would be too dense
    if (pixelsPerGrid < 10) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final majorPaint = Paint()
      ..color = Colors.white.withOpacity(opacity * 2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Calculate visible grid lines
    final startTime = scrollOffset;
    final endTime = scrollOffset + size.width / zoom;
    final startGrid = (startTime / gridInterval).floor();
    final endGrid = (endTime / gridInterval).ceil();

    for (int i = startGrid; i <= endGrid; i++) {
      final gridTime = i * gridInterval;
      final x = (gridTime - scrollOffset) * zoom;

      if (x < 0 || x > size.width) continue;

      // Major lines every 4 beats (bar)
      final isMajor = i % 4 == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorPaint : paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridOverlayPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.snapValue != snapValue ||
        oldDelegate.tempo != tempo ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.opacity != opacity;
  }
}

// =============================================================================
// MAGNETIC SNAP INDICATOR
// =============================================================================

/// Widget that shows magnetic snap zone feedback
class MagneticSnapIndicator extends StatelessWidget {
  final double targetX;
  final double currentX;
  final double snapThreshold;
  final bool isActive;
  final double height;

  const MagneticSnapIndicator({
    super.key,
    required this.targetX,
    required this.currentX,
    required this.snapThreshold,
    required this.isActive,
    this.height = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    final distance = (targetX - currentX).abs();
    final strength = (1 - distance / snapThreshold).clamp(0.0, 1.0);

    if (strength <= 0) return const SizedBox.shrink();

    return Positioned(
      left: targetX - snapThreshold,
      top: 0,
      bottom: 0,
      width: snapThreshold * 2,
      child: CustomPaint(
        painter: _MagneticZonePainter(
          strength: strength,
          centerOffset: snapThreshold,
        ),
      ),
    );
  }
}

class _MagneticZonePainter extends CustomPainter {
  final double strength;
  final double centerOffset;

  _MagneticZonePainter({
    required this.strength,
    required this.centerOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1,
      colors: [
        const Color(0xFF4a9eff).withOpacity(strength * 0.3),
        const Color(0xFF4a9eff).withOpacity(0),
      ],
    );

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..shader = gradient.createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _MagneticZonePainter oldDelegate) {
    return oldDelegate.strength != strength;
  }
}

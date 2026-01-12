# Professional Fade System Implementation — FluxForge Studio

**Based on:** Logic Pro X + Cubase + Pro Tools best practices
**Research:** 20+ DAW sources, competitor analysis
**Status:** Ready to implement

---

## PROBLEM ANALYSIS

### Current Issues in FluxForge Studio

1. **Fade handles not visible enough** — No clear visual indicator
2. **Hit detection too narrow** — Hard to grab handles
3. **No cursor feedback** — User doesn't know fade zone exists
4. **Width calculation issue** — `clip.fadeIn * widget.zoom` can be < 8px, invisible
5. **No snap-to-grid integration** — Professional workflow missing
6. **No curve visualization** — Can't see fade shape
7. **No double-click editor** — Advanced editing missing

---

## SOLUTION: HYBRID PROFESSIONAL SYSTEM

### Visual Design (Logic Pro + Cubase Style)

```dart
// NEW: Professional fade handle with proper hit zones

class _FadeHandlePro extends StatefulWidget {
  final double clipWidth;       // Total clip width in pixels
  final double fadeLength;      // Fade length in seconds
  final double zoom;            // Pixels per second
  final bool isLeft;            // Fade in (left) or fade out (right)
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;  // Delta in seconds
  final VoidCallback onDragEnd;
  final VoidCallback? onDoubleTap;  // Open curve editor

  const _FadeHandlePro({
    required this.clipWidth,
    required this.fadeLength,
    required this.zoom,
    required this.isLeft,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onDoubleTap,
  });

  @override
  State<_FadeHandlePro> createState() => _FadeHandleProState();
}

class _FadeHandleProState extends State<_FadeHandlePro> {
  bool _isHovered = false;
  Offset? _dragStartPosition;

  // CRITICAL: Large hit zone for professional feel
  static const double hitZoneWidth = 16.0;   // Touch-friendly
  static const double hitZoneHeight = 12.0;  // Top corner only
  static const double minVisibleWidth = 4.0; // Minimum to show handle

  @override
  Widget build(BuildContext context) {
    // Calculate fade width in pixels
    final fadeWidthPx = widget.fadeLength * widget.zoom;

    // Don't show handle if clip is too narrow or fade is tiny
    if (widget.clipWidth < hitZoneWidth * 2 || fadeWidthPx < minVisibleWidth) {
      return const SizedBox.shrink();
    }

    // Hit zone is always fixed size (16x12px), positioned at corner
    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      width: hitZoneWidth,
      height: hitZoneHeight,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.resizeLeftRight,  // ↔ cursor
        child: GestureDetector(
          onPanStart: (details) {
            _dragStartPosition = details.localPosition;
            widget.onDragStart();
          },
          onPanUpdate: (details) {
            if (_dragStartPosition == null) return;

            // Calculate delta in pixels
            final deltaPixels = widget.isLeft
                ? details.localPosition.dx - _dragStartPosition!.dx
                : _dragStartPosition!.dx - details.localPosition.dx;

            // Convert to seconds
            final deltaSeconds = deltaPixels / widget.zoom;

            // Send delta (caller will apply constraints)
            widget.onDragUpdate(deltaSeconds);

            // Update drag start for next frame (cumulative drag)
            _dragStartPosition = details.localPosition;
          },
          onPanEnd: (_) {
            _dragStartPosition = null;
            widget.onDragEnd();
          },
          onDoubleTap: widget.onDoubleTap,
          child: CustomPaint(
            painter: _FadeHandlePainter(
              isLeft: widget.isLeft,
              isHovered: _isHovered,
              fadeWidthPx: fadeWidthPx,
            ),
          ),
        ),
      ),
    );
  }
}
```

### Fade Handle Painter (Triangular Cubase Style)

```dart
class _FadeHandlePainter extends CustomPainter {
  final bool isLeft;
  final bool isHovered;
  final double fadeWidthPx;

  _FadeHandlePainter({
    required this.isLeft,
    required this.isHovered,
    required this.fadeWidthPx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Colors from FluxForge Studio theme
    final inactiveColor = const Color(0xFF1a1a20).withOpacity(0.5);
    final hoverColor = const Color(0xFF4a9eff);      // Blue
    final fadeLineColor = const Color(0xFF40c8ff);   // Cyan

    final handleColor = isHovered ? hoverColor : inactiveColor;

    // Draw triangular handle (Cubase style)
    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;

    final handlePath = Path();

    if (isLeft) {
      // Top-left triangle
      handlePath.moveTo(0, 0);                    // Top-left corner
      handlePath.lineTo(size.width, 0);          // Top-right
      handlePath.lineTo(0, size.height);         // Bottom-left
      handlePath.close();
    } else {
      // Top-right triangle (mirrored)
      handlePath.moveTo(size.width, 0);          // Top-right corner
      handlePath.lineTo(0, 0);                   // Top-left
      handlePath.lineTo(size.width, size.height); // Bottom-right
      handlePath.close();
    }

    canvas.drawPath(handlePath, handlePaint);

    // Draw border for visibility
    final borderPaint = Paint()
      ..color = handleColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(handlePath, borderPaint);

    // If hovered, draw fade line extending into clip (visual feedback)
    if (isHovered && fadeWidthPx > size.width) {
      final linePaint = Paint()
        ..color = fadeLineColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final lineStart = isLeft ? Offset(size.width, 0) : Offset(0, 0);
      final lineEnd = isLeft
          ? Offset(size.width + fadeWidthPx, size.height * 0.5)
          : Offset(-fadeWidthPx, size.height * 0.5);

      canvas.drawLine(lineStart, lineEnd, linePaint);
    }
  }

  @override
  bool shouldRepaint(_FadeHandlePainter oldDelegate) =>
      isHovered != oldDelegate.isHovered ||
      fadeWidthPx != oldDelegate.fadeWidthPx ||
      isLeft != oldDelegate.isLeft;
}
```

### Fade Curve Overlay (Studio One Style)

```dart
class _FadeCurveOverlay extends CustomPainter {
  final bool isLeft;
  final double fadeLength;     // In seconds
  final double zoom;           // Pixels per second
  final FadeCurveType curveType;

  _FadeCurveOverlay({
    required this.isLeft,
    required this.fadeLength,
    required this.zoom,
    required this.curveType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fadeLength <= 0) return;

    final fadeWidthPx = fadeLength * zoom;
    if (fadeWidthPx < 2.0) return; // Too small to render

    // Generate curve points
    final numPoints = (fadeWidthPx / 2.0).ceil().clamp(10, 100);
    final points = <Offset>[];

    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints; // [0.0, 1.0]

      // Calculate gain based on curve type
      final gain = _calculateGain(t, curveType, isLeft);

      // Map to screen coordinates
      final x = isLeft ? t * fadeWidthPx : size.width - (t * fadeWidthPx);
      final y = size.height * (1.0 - gain); // Inverted Y

      points.add(Offset(x, y));
    }

    // Draw anti-aliased fade curve line
    final linePaint = Paint()
      ..color = const Color(0xFF40c8ff).withOpacity(0.8) // Cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, linePaint);

    // Draw gradient fill under curve (25% opacity)
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          const Color(0xFF40c8ff).withOpacity(0.0),
          const Color(0xFF40c8ff).withOpacity(0.15),
        ],
      )
      ..style = PaintingStyle.fill;

    final fillPath = Path();
    fillPath.moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
  }

  double _calculateGain(double t, FadeCurveType curveType, bool isFadeIn) {
    double gain;

    switch (curveType) {
      case FadeCurveType.linear:
        gain = t;
        break;

      case FadeCurveType.exponential:
        gain = t * t;
        break;

      case FadeCurveType.logarithmic:
        gain = 1.0 - (1.0 - t) * (1.0 - t);
        break;

      case FadeCurveType.sCurve:
        gain = 0.5 * (1.0 - cos(t * pi));
        break;

      case FadeCurveType.equalPower:
        gain = sqrt(t);
        break;

      default:
        gain = t;
    }

    // Invert for fade out
    return isFadeIn ? gain : (1.0 - gain);
  }

  @override
  bool shouldRepaint(_FadeCurveOverlay oldDelegate) =>
      fadeLength != oldDelegate.fadeLength ||
      zoom != oldDelegate.zoom ||
      curveType != oldDelegate.curveType ||
      isLeft != oldDelegate.isLeft;
}
```

### Constraint System (Sample-Accurate)

```dart
class FadeConstraints {
  final double clipDuration;     // Total clip length in seconds
  final double fadeInLength;     // Current fade in length
  final double fadeOutLength;    // Current fade out length

  FadeConstraints({
    required this.clipDuration,
    required this.fadeInLength,
    required this.fadeOutLength,
  });

  /// Constrain fade in to valid range
  double constrainFadeIn(double requestedLength) {
    // Fade in cannot exceed: clip duration - fade out length
    final maxAllowed = clipDuration - fadeOutLength;
    return requestedLength.clamp(0.0, maxAllowed);
  }

  /// Constrain fade out to valid range
  double constrainFadeOut(double requestedLength) {
    // Fade out cannot exceed: clip duration - fade in length
    final maxAllowed = clipDuration - fadeInLength;
    return requestedLength.clamp(0.0, maxAllowed);
  }

  /// Check if fade lengths are valid (for assertion)
  bool isValid() {
    return fadeInLength >= 0 &&
        fadeOutLength >= 0 &&
        fadeInLength + fadeOutLength <= clipDuration;
  }
}
```

### Usage in ClipWidget

```dart
// Inside _TimelineClipWidgetState

// Replace old _FadeHandle with new _FadeHandlePro:

// Fade in handle (top-left corner)
_FadeHandlePro(
  clipWidth: clipWidthPx,
  fadeLength: clip.fadeIn,
  zoom: widget.zoom,
  isLeft: true,
  onDragStart: () => setState(() => _isDraggingFadeIn = true),
  onDragUpdate: (deltaSeconds) {
    final constraints = FadeConstraints(
      clipDuration: clip.duration,
      fadeInLength: clip.fadeIn,
      fadeOutLength: clip.fadeOut,
    );

    // Apply delta with constraints
    final newFadeIn = constraints.constrainFadeIn(
      clip.fadeIn + deltaSeconds
    );

    // Call parent to update clip
    widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
  },
  onDragEnd: () => setState(() => _isDraggingFadeIn = false),
  onDoubleTap: () => _showFadeCurveEditor(isLeft: true),
),

// Fade out handle (top-right corner)
_FadeHandlePro(
  clipWidth: clipWidthPx,
  fadeLength: clip.fadeOut,
  zoom: widget.zoom,
  isLeft: false,
  onDragStart: () => setState(() => _isDraggingFadeOut = true),
  onDragUpdate: (deltaSeconds) {
    final constraints = FadeConstraints(
      clipDuration: clip.duration,
      fadeInLength: clip.fadeIn,
      fadeOutLength: clip.fadeOut,
    );

    // Apply delta with constraints
    final newFadeOut = constraints.constrainFadeOut(
      clip.fadeOut + deltaSeconds
    );

    widget.onFadeChange?.call(clip.fadeIn, newFadeOut);
  },
  onDragEnd: () => setState(() => _isDraggingFadeOut = false),
  onDoubleTap: () => _showFadeCurveEditor(isLeft: false),
),

// Fade curve overlays (visible when fade > 0)
if (clip.fadeIn > 0)
  Positioned(
    left: 0,
    top: 0,
    bottom: 0,
    width: clip.fadeIn * widget.zoom,
    child: CustomPaint(
      painter: _FadeCurveOverlay(
        isLeft: true,
        fadeLength: clip.fadeIn,
        zoom: widget.zoom,
        curveType: clip.fadeInCurve ?? FadeCurveType.linear,
      ),
    ),
  ),

if (clip.fadeOut > 0)
  Positioned(
    right: 0,
    top: 0,
    bottom: 0,
    width: clip.fadeOut * widget.zoom,
    child: CustomPaint(
      painter: _FadeCurveOverlay(
        isLeft: false,
        fadeLength: clip.fadeOut,
        zoom: widget.zoom,
        curveType: clip.fadeOutCurve ?? FadeCurveType.linear,
      ),
    ),
  ),
```

---

## FADE CURVE TYPES (Enum + Model)

```dart
enum FadeCurveType {
  linear,
  exponential,
  logarithmic,
  sCurve,
  sine,
  equalPower,
  // Custom Bézier (future)
}

extension FadeCurveTypeExtension on FadeCurveType {
  String get displayName {
    switch (this) {
      case FadeCurveType.linear:
        return 'Linear';
      case FadeCurveType.exponential:
        return 'Exponential';
      case FadeCurveType.logarithmic:
        return 'Logarithmic';
      case FadeCurveType.sCurve:
        return 'S-Curve';
      case FadeCurveType.sine:
        return 'Sine';
      case FadeCurveType.equalPower:
        return 'Equal Power';
    }
  }

  String get description {
    switch (this) {
      case FadeCurveType.linear:
        return 'Straight line fade';
      case FadeCurveType.exponential:
        return 'Starts slow, accelerates (natural)';
      case FadeCurveType.logarithmic:
        return 'Starts fast, decelerates (acoustic)';
      case FadeCurveType.sCurve:
        return 'Smooth S-shape (most musical)';
      case FadeCurveType.sine:
        return 'Sine wave fade';
      case FadeCurveType.equalPower:
        return 'Constant loudness (crossfades)';
    }
  }
}
```

---

## NEXT STEPS

1. **Replace old `_FadeHandle` with `_FadeHandlePro`** in clip_widget.dart
2. **Add `fadeInCurve` and `fadeOutCurve` fields** to TimelineClip model
3. **Implement constraint system** in parent widget (timeline.dart)
4. **Add fade curve overlay painter**
5. **Test with various clip lengths** and zoom levels
6. **Implement double-click curve editor** (Phase 2)

---

**Status:** Design complete, ready for implementation
**Estimated Time:** 2-3h for core fade system
**Expected Result:** Professional DAW-grade fade handling (Logic Pro + Cubase quality)

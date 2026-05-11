// FAZA 5.1.5 — Emotional Arc Timeline editor.
//
// Pure-Dart, FluxForge-themed CustomPaint widget that lets the user draw
// the intensity envelope a generative clip will follow. Backed by the
// same `EmotionalArc` / `EmotionalArcPoint` types `GenerativeAudioService`
// already sends to the Rust side, so editor output drops straight into a
// generation request.
//
// Interaction model (slot-DAW grammar, not generic curve editor):
//   - Tap empty area      → add a new point at that (t, intensity).
//   - Drag a point        → move it; t is clamped between its neighbours.
//   - Double-tap a point  → delete (endpoints t=0 / t=1 cannot be deleted).
//   - Preset chip row     → swap to a curated shape (crescendo, dip, etc).
//   - Reset chip          → flat at 0.75 intensity (the natural Mock default).
//
// Why this lives in widgets/ and not slot_lab/: 5.1.4 will mount it inside
// the new "GEN" HELIX MUSIC sub-tab, and 5.2.1 (text-to-SFX preview) will
// embed it as a sub-control. Keep it caller-agnostic.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/generative_audio_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Curated arc shapes. Names are slot-domain (the Stable Audio Open model
/// understands "crescendo" much better than "ramp_up"), and each renders
/// to a small `EmotionalArc` ready to drop into a `GenerationRequest`.
enum EmotionalArcPreset {
  flat,
  crescendo,
  decrescendo,
  spike,
  dip,
  tenseBuildup,
  euphoricPayoff,
  doublePeak;

  String get label {
    switch (this) {
      case flat:
        return 'Flat';
      case crescendo:
        return 'Crescendo';
      case decrescendo:
        return 'Decrescendo';
      case spike:
        return 'Spike';
      case dip:
        return 'Dip';
      case tenseBuildup:
        return 'Tense Buildup';
      case euphoricPayoff:
        return 'Euphoric Payoff';
      case doublePeak:
        return 'Double Peak';
    }
  }

  /// Build the canonical arc for this preset. All shapes pin `t=0` and
  /// `t=1` so endpoints exist (the editor refuses to delete them).
  EmotionalArc build() {
    switch (this) {
      case flat:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.75),
          EmotionalArcPoint(t: 1.0, intensity: 0.75),
        ]);
      case crescendo:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.05),
          EmotionalArcPoint(t: 1.0, intensity: 1.0),
        ]);
      case decrescendo:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 1.0),
          EmotionalArcPoint(t: 1.0, intensity: 0.05),
        ]);
      case spike:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.1),
          EmotionalArcPoint(t: 0.45, intensity: 0.2),
          EmotionalArcPoint(t: 0.5, intensity: 1.0),
          EmotionalArcPoint(t: 0.55, intensity: 0.2),
          EmotionalArcPoint(t: 1.0, intensity: 0.1),
        ]);
      case dip:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.8),
          EmotionalArcPoint(t: 0.5, intensity: 0.15),
          EmotionalArcPoint(t: 1.0, intensity: 0.8),
        ]);
      case tenseBuildup:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.15),
          EmotionalArcPoint(t: 0.7, intensity: 0.45),
          EmotionalArcPoint(t: 0.9, intensity: 0.85),
          EmotionalArcPoint(t: 1.0, intensity: 1.0),
        ]);
      case euphoricPayoff:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.6),
          EmotionalArcPoint(t: 0.1, intensity: 1.0),
          EmotionalArcPoint(t: 0.7, intensity: 0.95),
          EmotionalArcPoint(t: 1.0, intensity: 0.4),
        ]);
      case doublePeak:
        return const EmotionalArc([
          EmotionalArcPoint(t: 0.0, intensity: 0.1),
          EmotionalArcPoint(t: 0.25, intensity: 0.85),
          EmotionalArcPoint(t: 0.5, intensity: 0.3),
          EmotionalArcPoint(t: 0.75, intensity: 1.0),
          EmotionalArcPoint(t: 1.0, intensity: 0.2),
        ]);
    }
  }
}

/// Stateless / pure operations on a list of arc points. Lifted out of the
/// widget so the test suite can exercise them without a WidgetTester.
class EmotionalArcOps {
  /// Ensure the curve starts at `t=0` and ends at `t=1`. If callers pass
  /// in something incomplete, fix it up rather than fail. Endpoints
  /// preserve their existing intensity if possible; otherwise default
  /// to 0.5.
  static List<EmotionalArcPoint> normalize(List<EmotionalArcPoint> input) {
    final cleaned = <EmotionalArcPoint>[];
    for (final p in input) {
      if (!p.t.isFinite || !p.intensity.isFinite) continue;
      cleaned.add(EmotionalArcPoint(
        t: p.t.clamp(0.0, 1.0).toDouble(),
        intensity: p.intensity.clamp(0.0, 1.0).toDouble(),
      ));
    }
    cleaned.sort((a, b) => a.t.compareTo(b.t));
    if (cleaned.isEmpty || cleaned.first.t > 0.0) {
      cleaned.insert(
          0,
          EmotionalArcPoint(
              t: 0.0, intensity: cleaned.isEmpty ? 0.5 : cleaned.first.intensity));
    }
    if (cleaned.last.t < 1.0) {
      cleaned.add(EmotionalArcPoint(t: 1.0, intensity: cleaned.last.intensity));
    }
    return cleaned;
  }

  /// Insert a new point in the right slot to keep `t` monotonic. Refuses
  /// to add a duplicate at the same `t` (within `tEps`) — moves the
  /// existing one instead.
  static List<EmotionalArcPoint> insertPoint(
    List<EmotionalArcPoint> points,
    EmotionalArcPoint p, {
    double tEps = 0.005,
  }) {
    final next = List<EmotionalArcPoint>.from(points);
    final t = p.t.clamp(0.0, 1.0).toDouble();
    final intensity = p.intensity.clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < next.length; i++) {
      if ((next[i].t - t).abs() < tEps) {
        next[i] = EmotionalArcPoint(t: next[i].t, intensity: intensity);
        return next;
      }
    }
    next.add(EmotionalArcPoint(t: t, intensity: intensity));
    next.sort((a, b) => a.t.compareTo(b.t));
    return next;
  }

  /// Move the point at `index` to `(t, intensity)`. Endpoints (index 0
  /// and `points.length - 1`) keep their `t` pinned to 0 / 1 respectively;
  /// only their intensity is editable.
  ///
  /// Interior points have `t` clamped to `(prev.t, next.t)` to keep the
  /// curve monotonic — Rust side `EmotionalArc.validate()` rejects
  /// non-monotonic input.
  static List<EmotionalArcPoint> movePoint(
    List<EmotionalArcPoint> points,
    int index,
    double t,
    double intensity, {
    double tEps = 0.001,
  }) {
    if (index < 0 || index >= points.length) return points;
    final clampedIntensity = intensity.clamp(0.0, 1.0).toDouble();
    double clampedT;
    if (index == 0) {
      clampedT = 0.0;
    } else if (index == points.length - 1) {
      clampedT = 1.0;
    } else {
      final lo = points[index - 1].t + tEps;
      final hi = points[index + 1].t - tEps;
      // If neighbours collapsed (interior pinch), keep the current t.
      clampedT = (hi <= lo) ? points[index].t : t.clamp(lo, hi).toDouble();
    }
    final next = List<EmotionalArcPoint>.from(points);
    next[index] = EmotionalArcPoint(t: clampedT, intensity: clampedIntensity);
    return next;
  }

  /// Delete the point at `index`. Endpoints are protected.
  static List<EmotionalArcPoint> deletePoint(
    List<EmotionalArcPoint> points,
    int index,
  ) {
    if (index <= 0 || index >= points.length - 1) return points;
    final next = List<EmotionalArcPoint>.from(points);
    next.removeAt(index);
    return next;
  }

  /// Find the index of the point closest to `(t, intensity)` within a
  /// pixel-equivalent threshold. Returns -1 if none qualifies.
  ///
  /// `tScale` / `intensityScale` map normalized space to pixel space so
  /// the threshold is consistent across container sizes.
  static int hitTest(
    List<EmotionalArcPoint> points,
    double t,
    double intensity, {
    required double tScale,
    required double intensityScale,
    double thresholdPx = 14.0,
  }) {
    var best = -1;
    var bestSq = thresholdPx * thresholdPx;
    for (var i = 0; i < points.length; i++) {
      final dx = (points[i].t - t) * tScale;
      final dy = (points[i].intensity - intensity) * intensityScale;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestSq) {
        bestSq = d2;
        best = i;
      }
    }
    return best;
  }

  /// Linear interpolation at normalized `t ∈ [0,1]`. Out-of-range clamps
  /// to endpoint intensity. Empty input → 0.0.
  ///
  /// Mirrors the Rust `EmotionalArc::sample` exactly so the editor preview
  /// matches what the backend will produce. Tested for parity.
  static double sample(List<EmotionalArcPoint> points, double t) {
    if (points.isEmpty) return 0.0;
    final c = t.clamp(0.0, 1.0).toDouble();
    if (c <= points.first.t) return points.first.intensity;
    if (c >= points.last.t) return points.last.intensity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (c >= a.t && c <= b.t) {
        final span = (b.t - a.t).abs() < 1e-9 ? 1e-9 : (b.t - a.t);
        final alpha = (c - a.t) / span;
        return a.intensity + (b.intensity - a.intensity) * alpha;
      }
    }
    return points.last.intensity;
  }
}

class EmotionalArcEditor extends StatefulWidget {
  final EmotionalArc initial;
  final ValueChanged<EmotionalArc>? onChanged;
  final double height;

  /// Show / hide the preset chip strip. Off when the editor is embedded in
  /// a tight panel and presets live elsewhere.
  final bool showPresets;

  const EmotionalArcEditor({
    super.key,
    required this.initial,
    this.onChanged,
    this.height = 160,
    this.showPresets = true,
  });

  @override
  State<EmotionalArcEditor> createState() => _EmotionalArcEditorState();
}

class _EmotionalArcEditorState extends State<EmotionalArcEditor> {
  late List<EmotionalArcPoint> _points;
  int? _draggingIndex;
  int? _hoverIndex;

  @override
  void initState() {
    super.initState();
    _points = EmotionalArcOps.normalize(widget.initial.points);
  }

  @override
  void didUpdateWidget(covariant EmotionalArcEditor old) {
    super.didUpdateWidget(old);
    if (!_pointsEqual(old.initial.points, widget.initial.points) &&
        _draggingIndex == null) {
      _points = EmotionalArcOps.normalize(widget.initial.points);
    }
  }

  bool _pointsEqual(List<EmotionalArcPoint> a, List<EmotionalArcPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].t != b[i].t || a[i].intensity != b[i].intensity) return false;
    }
    return true;
  }

  void _commit() {
    widget.onChanged?.call(EmotionalArc(List<EmotionalArcPoint>.from(_points)));
  }

  void _applyPreset(EmotionalArcPreset preset) {
    setState(() {
      _points = EmotionalArcOps.normalize(preset.build().points);
    });
    _commit();
  }

  // Convert local pointer position → normalized (t, intensity).
  ({double t, double intensity}) _toNorm(Offset local, Size canvasSize) {
    final t = (local.dx / canvasSize.width).clamp(0.0, 1.0);
    final intensity = 1.0 - (local.dy / canvasSize.height).clamp(0.0, 1.0);
    return (t: t, intensity: intensity);
  }

  void _onTapUp(TapUpDetails details, Size canvasSize) {
    final norm = _toNorm(details.localPosition, canvasSize);
    final hit = EmotionalArcOps.hitTest(
      _points,
      norm.t,
      norm.intensity,
      tScale: canvasSize.width,
      intensityScale: canvasSize.height,
    );
    if (hit >= 0) {
      // Tap on existing point: select it (visual highlight only).
      setState(() => _hoverIndex = hit);
      return;
    }
    setState(() {
      _points = EmotionalArcOps.insertPoint(
        _points,
        EmotionalArcPoint(t: norm.t, intensity: norm.intensity),
      );
    });
    _commit();
  }

  void _onDoubleTapDown(TapDownDetails details, Size canvasSize) {
    final norm = _toNorm(details.localPosition, canvasSize);
    final hit = EmotionalArcOps.hitTest(
      _points,
      norm.t,
      norm.intensity,
      tScale: canvasSize.width,
      intensityScale: canvasSize.height,
    );
    if (hit < 0) return;
    final removed = EmotionalArcOps.deletePoint(_points, hit);
    if (removed.length == _points.length) return;
    setState(() {
      _points = removed;
      _hoverIndex = null;
    });
    _commit();
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    final norm = _toNorm(details.localPosition, canvasSize);
    final hit = EmotionalArcOps.hitTest(
      _points,
      norm.t,
      norm.intensity,
      tScale: canvasSize.width,
      intensityScale: canvasSize.height,
    );
    if (hit >= 0) {
      setState(() {
        _draggingIndex = hit;
        _hoverIndex = hit;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    final idx = _draggingIndex;
    if (idx == null) return;
    final norm = _toNorm(details.localPosition, canvasSize);
    setState(() {
      _points = EmotionalArcOps.movePoint(
        _points,
        idx,
        norm.t,
        norm.intensity,
      );
    });
    _commit();
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _draggingIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showPresets) _PresetStrip(onPreset: _applyPreset),
        if (widget.showPresets) const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size =
                  Size(constraints.maxWidth, constraints.maxHeight);
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTapUp(d, size),
                  onDoubleTapDown: (d) => _onDoubleTapDown(d, size),
                  onPanStart: (d) => _onPanStart(d, size),
                  onPanUpdate: (d) => _onPanUpdate(d, size),
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    size: size,
                    painter: _ArcPainter(
                      points: _points,
                      draggingIndex: _draggingIndex,
                      hoverIndex: _hoverIndex,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        _Footer(
          pointCount: _points.length,
          peak: _points.fold<double>(
              0, (m, p) => p.intensity > m ? p.intensity : m),
        ),
      ],
    );
  }
}

class _PresetStrip extends StatelessWidget {
  final ValueChanged<EmotionalArcPreset> onPreset;
  const _PresetStrip({required this.onPreset});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in EmotionalArcPreset.values) ...[
            _PresetChip(preset: preset, onTap: () => onPreset(preset)),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _PresetChip extends StatefulWidget {
  final EmotionalArcPreset preset;
  final VoidCallback onTap;
  const _PresetChip({required this.preset, required this.onTap});

  @override
  State<_PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<_PresetChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? FluxForgeTheme.bgHover
                : FluxForgeTheme.glassFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered
                  ? FluxForgeTheme.accentCyan.withValues(alpha: 0.6)
                  : FluxForgeTheme.glassBorder,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.preset.label,
            style: TextStyle(
              color: _hovered
                  ? FluxForgeTheme.textPrimary
                  : FluxForgeTheme.textSecondary,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int pointCount;
  final double peak;
  const _Footer({required this.pointCount, required this.peak});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        color: FluxForgeTheme.textTertiary,
        fontSize: 10,
        letterSpacing: 0.3,
      ),
      // Wrap so narrow containers (<400px) reflow instead of overflowing.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 2,
        children: [
          Text('$pointCount points'),
          Text('peak ${(peak * 100).toStringAsFixed(0)}%'),
          const Text('tap · drag · dbl-tap to delete'),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final List<EmotionalArcPoint> points;
  final int? draggingIndex;
  final int? hoverIndex;

  _ArcPainter({
    required this.points,
    required this.draggingIndex,
    required this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background.
    final bg = Paint()..color = FluxForgeTheme.bgDeep;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      bg,
    );

    // Subtle grid (5 horizontals, 5 verticals).
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final x = size.width * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Border.
    final borderPaint = Paint()
      ..color = FluxForgeTheme.glassBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        const Radius.circular(4),
      ),
      borderPaint,
    );

    if (points.isEmpty) return;

    // Arc fill (gradient under the line).
    final path = Path()..moveTo(0, size.height);
    for (final p in points) {
      path.lineTo(p.t * size.width, (1.0 - p.intensity) * size.height);
    }
    path.lineTo(size.width, size.height);
    path.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          FluxForgeTheme.brandGold.withValues(alpha: 0.35),
          FluxForgeTheme.brandGold.withValues(alpha: 0.04),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fillPaint);

    // Arc stroke.
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points[i].t * size.width;
      final y = (1.0 - points[i].intensity) * size.height;
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    final linePaint = Paint()
      ..color = FluxForgeTheme.brandGoldBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Points (endpoints styled differently so users see they're pinned).
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final c = Offset(p.t * size.width, (1.0 - p.intensity) * size.height);
      final isEndpoint = i == 0 || i == points.length - 1;
      final isActive = i == draggingIndex || i == hoverIndex;
      final radius = isActive ? 6.0 : 4.5;
      // Halo when active.
      if (isActive) {
        canvas.drawCircle(
          c,
          radius + 4,
          Paint()
            ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.25),
        );
      }
      // Body.
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = isEndpoint
              ? FluxForgeTheme.brandGoldDeep
              : FluxForgeTheme.brandGold,
      );
      // Ring.
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = isActive
              ? FluxForgeTheme.accentCyan
              : FluxForgeTheme.bgVoid
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.points != points ||
      old.draggingIndex != draggingIndex ||
      old.hoverIndex != hoverIndex;
}

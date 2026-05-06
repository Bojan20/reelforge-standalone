/// Timeline Grid Overlay Widget
///
/// Draws vertical grid lines on the timeline when snap-to-grid is enabled.
/// Grid interval is controlled by TimelineDragController.
///
/// FLUX_MASTER_TODO 3.3.2 — Snap-to-grid visual feedback u drag.
/// Pre-fix korisnik je video sve grid linije iste, ali nije znao GDE
/// TAČNO će clip snap-ovati kad pusti. Sad se renderuje:
///
///   * grid lines (kao i ranije, slabi tonovi)
///   * **active snap target** — debela brand-gold vertical linija na
///     poziciji `controller.getSnappedAbsolutePosition()` dok je layer
///     ili region drag u toku
///
/// Snap target je live (ne lazy) — kreće se sa kursorom i pokazuje
/// najbližu grid liniju u realnom vremenu.

import 'package:flutter/material.dart';
import '../../controllers/slot_lab/timeline_drag_controller.dart';
import '../../theme/fluxforge_theme.dart';

/// Paints vertical grid lines at regular intervals + active snap target
/// indicator dok je drag aktivan.
class TimelineGridOverlay extends StatelessWidget {
  /// Pixels per second (zoom level)
  final double pixelsPerSecond;

  /// Total duration in seconds to draw grid for
  final double durationSeconds;

  /// The drag controller (for snap state and interval)
  final TimelineDragController dragController;

  /// Height of the grid area
  final double height;

  const TimelineGridOverlay({
    super.key,
    required this.pixelsPerSecond,
    required this.durationSeconds,
    required this.dragController,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dragController,
      builder: (context, _) {
        if (!dragController.snapEnabled) {
          return const SizedBox.shrink();
        }

        // Active snap target — pokaži samo ako je drag stvarno u toku.
        // `isLayerDragActive` je primarni kanal (layer drag je per-layer);
        // `isRegionDragActive` je sekundarni (region drag pomera grupu).
        final double? snapTargetSeconds = _activeSnapTarget();

        return CustomPaint(
          size: Size(durationSeconds * pixelsPerSecond, height),
          painter: _GridPainter(
            pixelsPerSecond: pixelsPerSecond,
            durationSeconds: durationSeconds,
            gridInterval: dragController.gridInterval,
            snapTargetSeconds: snapTargetSeconds,
          ),
        );
      },
    );
  }

  /// Vraća position (sekunde) gde će drag-ovani element snap-ovati,
  /// ili `null` ako nema aktivnog drag-a (snap target je nevidljiv).
  double? _activeSnapTarget() {
    if (dragController.isLayerDragActive) {
      return dragController.getSnappedAbsolutePosition();
    }
    if (dragController.isRegionDragActive) {
      // Region drag — current position + delta, snapped.
      return dragController.snapToGrid(dragController.getRegionCurrentPosition());
    }
    return null;
  }
}

class _GridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double durationSeconds;
  final GridInterval gridInterval;

  /// Position (in seconds) of the active snap target, ili `null` ako nema
  /// aktivnog drag-a. Renderuje se kao debela brand-gold linija + slab
  /// glow halo iznad regular grid lines-a.
  final double? snapTargetSeconds;

  _GridPainter({
    required this.pixelsPerSecond,
    required this.durationSeconds,
    required this.gridInterval,
    this.snapTargetSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intervalSeconds = gridInterval.seconds;
    final intervalPixels = intervalSeconds * pixelsPerSecond;

    // Skip if interval too small to draw (< 4 pixels)
    if (intervalPixels < 4) return;

    final majorPaint = Paint()
      ..color = Colors.white.withAlpha(40)
      ..strokeWidth = 1.0;

    final minorPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..strokeWidth = 0.5;

    // Calculate how many grid lines to draw
    final lineCount = (durationSeconds / intervalSeconds).ceil() + 1;

    for (int i = 0; i < lineCount; i++) {
      final x = i * intervalPixels;
      if (x > size.width) break;

      // Every 10th line is major (bolder)
      final isMajor = i % 10 == 0;
      final paint = isMajor ? majorPaint : minorPaint;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // ── Active snap target — drawn LAST so it sits on top of grid ──
    if (snapTargetSeconds != null) {
      _paintSnapTarget(canvas, size, snapTargetSeconds!);
    }
  }

  void _paintSnapTarget(Canvas canvas, Size size, double snapSeconds) {
    final x = snapSeconds * pixelsPerSecond;
    if (x < 0 || x > size.width) return;

    // Glow halo — soft 6px wide gradient razlivanja oko target linije.
    // Daje "magnetic" feel — kao da snap target privlači.
    final haloRect = Rect.fromLTWH(x - 3, 0, 6, size.height);
    final haloShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        FluxForgeTheme.brandGoldBright.withAlpha(80),
        FluxForgeTheme.brandGoldBright.withAlpha(140),
        FluxForgeTheme.brandGoldBright.withAlpha(80),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
    ).createShader(haloRect);
    canvas.drawRect(haloRect, Paint()..shader = haloShader);

    // Sharp center linija — 2.5px wide, brand gold bright. Najjača
    // vidljivost na timeline scrub-u.
    final centerPaint = Paint()
      ..color = FluxForgeTheme.brandGoldBright
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), centerPaint);

    // Top + bottom caps — male zlatne tačke da snap target ne nestaje
    // u clip horizontal lines kad timeline ima dosta sadržaja.
    final capPaint = Paint()
      ..color = FluxForgeTheme.brandGoldBright
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, 0), 3.0, capPaint);
    canvas.drawCircle(Offset(x, size.height), 3.0, capPaint);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        durationSeconds != oldDelegate.durationSeconds ||
        gridInterval != oldDelegate.gridInterval ||
        snapTargetSeconds != oldDelegate.snapTargetSeconds;
  }
}

/// Timeline Drag Visual Feedback
///
/// Provides enhanced visual feedback during timeline drag operations:
/// - Ghost region showing drag position
/// - Offset tooltip with delta display
/// - Overlap detection and red highlight
/// - Magnetic snap to grid with visual indicator
///
/// Usage: Wraps timeline drag operations with real-time visual feedback
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Drag feedback data during timeline drag operations
class TimelineDragFeedback {
  final double currentOffsetMs;
  final double deltaMs;
  final bool hasOverlap;
  final bool isSnapped;
  final double? snapTargetMs;

  const TimelineDragFeedback({
    required this.currentOffsetMs,
    required this.deltaMs,
    required this.hasOverlap,
    this.isSnapped = false,
    this.snapTargetMs,
  });

  String get deltaString {
    final sign = deltaMs >= 0 ? '↑' : '↓';
    final absVal = deltaMs.abs().toStringAsFixed(0);
    return '$sign${absVal}ms';
  }

  String get offsetString => '${currentOffsetMs.toStringAsFixed(0)}ms';
}

/// Ghost region widget showing drag preview
class GhostRegion extends StatelessWidget {
  final double width;
  final double height;
  final bool hasOverlap;
  final bool isSnapped;
  final String label;

  const GhostRegion({
    super.key,
    required this.width,
    required this.height,
    required this.hasOverlap,
    required this.isSnapped,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = hasOverlap
        ? FluxForgeTheme.errorRed
        : (isSnapped ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.1),
        border: Border.all(
          color: baseColor.withValues(alpha: hasOverlap ? 0.8 : 0.4),
          width: hasOverlap ? 2 : 1,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Diagonal stripes pattern
          CustomPaint(
            size: Size(width, height),
            painter: _StripePainter(
              color: baseColor.withValues(alpha: 0.05),
              spacing: 8,
            ),
          ),

          // Label
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: baseColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: baseColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // Snap indicator
          if (isSnapped)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.grid_on,
                  size: 10,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Diagonal stripes painter for ghost region
class _StripePainter extends CustomPainter {
  final Color color;
  final double spacing;

  _StripePainter({
    required this.color,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final count = ((size.width + size.height) / spacing).ceil();

    for (int i = 0; i < count; i++) {
      final x = i * spacing;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) =>
      color != oldDelegate.color || spacing != oldDelegate.spacing;
}

/// Offset tooltip widget showing current offset and delta
class DragOffsetTooltip extends StatelessWidget {
  final TimelineDragFeedback feedback;
  final Offset position;

  const DragOffsetTooltip({
    super.key,
    required this.feedback,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final tooltipColor = feedback.hasOverlap
        ? FluxForgeTheme.errorRed
        : (feedback.isSnapped ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgSurface);

    return Positioned(
      left: position.dx + 10,
      top: position.dy - 40,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: tooltipColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current offset
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Offset: ',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    feedback.offsetString,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              // Delta
              if (feedback.deltaMs.abs() > 0.1) ...[
                const SizedBox(height: 2),
                Text(
                  feedback.deltaString,
                  style: TextStyle(
                    color: feedback.deltaMs >= 0
                        ? FluxForgeTheme.successGreen
                        : FluxForgeTheme.warningOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],

              // Overlap warning
              if (feedback.hasOverlap) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      size: 10,
                      color: FluxForgeTheme.textPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'OVERLAP',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],

              // Snap indicator
              if (feedback.isSnapped && feedback.snapTargetMs != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.grid_on,
                      size: 10,
                      color: FluxForgeTheme.textPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'SNAP ${feedback.snapTargetMs!.toStringAsFixed(0)}ms',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Snap guide line showing grid snap target with magnetic animation
class SnapGuideLine extends StatefulWidget {
  final double position;
  final double height;
  final bool isVertical;
  final bool isMagnetic;

  const SnapGuideLine({
    super.key,
    required this.position,
    required this.height,
    this.isVertical = true,
    this.isMagnetic = false,
  });

  @override
  State<SnapGuideLine> createState() => _SnapGuideLineState();
}

class _SnapGuideLineState extends State<SnapGuideLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isMagnetic) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SnapGuideLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMagnetic != oldWidget.isMagnetic) {
      if (widget.isMagnetic) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.value = 0.4;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.isVertical ? widget.position : 0,
      top: widget.isVertical ? 0 : widget.position,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            final opacity = widget.isMagnetic ? _pulseAnimation.value : 0.6;
            return Container(
              width: widget.isVertical ? 3 : double.infinity,
              height: widget.isVertical ? widget.height : 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: widget.isVertical ? Alignment.topCenter : Alignment.centerLeft,
                  end: widget.isVertical ? Alignment.bottomCenter : Alignment.centerRight,
                  colors: [
                    FluxForgeTheme.accentBlue.withValues(alpha: 0.0),
                    FluxForgeTheme.accentBlue.withValues(alpha: opacity),
                    FluxForgeTheme.accentBlue.withValues(alpha: 0.0),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: opacity * 0.5),
                    blurRadius: widget.isMagnetic ? 8 : 4,
                    spreadRadius: widget.isMagnetic ? 2 : 0,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Helper functions for snap calculations
class SnapHelper {
  /// Calculate snap target for a given position
  ///
  /// Returns null if no snap target within threshold
  static double? calculateSnapTarget({
    required double currentMs,
    required double gridSizeMs,
    required double snapThresholdMs,
  }) {
    final nearestGrid = (currentMs / gridSizeMs).round() * gridSizeMs;
    final distance = (currentMs - nearestGrid).abs();

    if (distance <= snapThresholdMs) {
      return nearestGrid;
    }

    return null;
  }

  /// Check if position should snap to grid
  static bool shouldSnap({
    required double currentMs,
    required double gridSizeMs,
    required double snapThresholdMs,
  }) {
    return calculateSnapTarget(
      currentMs: currentMs,
      gridSizeMs: gridSizeMs,
      snapThresholdMs: snapThresholdMs,
    ) != null;
  }

  /// Apply snap to position if within threshold
  static double applySnap({
    required double currentMs,
    required double gridSizeMs,
    required double snapThresholdMs,
  }) {
    final snapTarget = calculateSnapTarget(
      currentMs: currentMs,
      gridSizeMs: gridSizeMs,
      snapThresholdMs: snapThresholdMs,
    );

    return snapTarget ?? currentMs;
  }
}

/// Overlap detection helper
class OverlapDetector {
  /// Check if a region overlaps with any existing regions
  static bool hasOverlap({
    required double startMs,
    required double durationMs,
    required List<RegionBounds> existingRegions,
    String? excludeRegionId,
  }) {
    final endMs = startMs + durationMs;

    for (final region in existingRegions) {
      if (region.id == excludeRegionId) continue;

      // Check overlap: (start1 < end2) && (end1 > start2)
      if (startMs < region.endMs && endMs > region.startMs) {
        return true;
      }
    }

    return false;
  }
}

/// Region bounds for overlap detection
class RegionBounds {
  final String id;
  final double startMs;
  final double endMs;

  RegionBounds({
    required this.id,
    required this.startMs,
    required this.endMs,
  });
}

/// Enhanced drag overlay showing all visual feedback at once
class TimelineDragOverlay extends StatelessWidget {
  final TimelineDragFeedback feedback;
  final Offset cursorPosition;
  final double regionWidth;
  final double regionHeight;
  final double timelineHeight;
  final List<double> nearbySnapPoints;
  final String layerLabel;
  final List<OverlapWarning> overlapWarnings;

  const TimelineDragOverlay({
    super.key,
    required this.feedback,
    required this.cursorPosition,
    required this.regionWidth,
    required this.regionHeight,
    required this.timelineHeight,
    this.nearbySnapPoints = const [],
    required this.layerLabel,
    this.overlapWarnings = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Snap guide lines for nearby grid points
        ...nearbySnapPoints.map((snapPoint) => SnapGuideLine(
              position: snapPoint,
              height: timelineHeight,
              isVertical: true,
              isMagnetic: feedback.isSnapped && (feedback.snapTargetMs! - feedback.currentOffsetMs).abs() < 10,
            )),

        // Ghost region at drag position
        Positioned(
          left: cursorPosition.dx,
          top: cursorPosition.dy,
          child: GhostRegion(
            width: regionWidth,
            height: regionHeight,
            hasOverlap: feedback.hasOverlap,
            isSnapped: feedback.isSnapped,
            label: layerLabel,
          ),
        ),

        // Offset tooltip
        DragOffsetTooltip(
          feedback: feedback,
          position: cursorPosition,
        ),

        // Overlap warning indicators
        ...overlapWarnings.map((warning) => _OverlapWarningIndicator(
              warning: warning,
              timelineHeight: timelineHeight,
            )),
      ],
    );
  }
}

/// Overlap warning data
class OverlapWarning {
  final double startMs;
  final double endMs;
  final String conflictingLayerName;

  const OverlapWarning({
    required this.startMs,
    required this.endMs,
    required this.conflictingLayerName,
  });
}

/// Visual indicator for overlap warning
class _OverlapWarningIndicator extends StatelessWidget {
  final OverlapWarning warning;
  final double timelineHeight;

  const _OverlapWarningIndicator({
    required this.warning,
    required this.timelineHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: warning.startMs / 10, // Simplified position calculation
      top: 0,
      child: Container(
        width: (warning.endMs - warning.startMs) / 10,
        height: timelineHeight,
        decoration: BoxDecoration(
          color: FluxForgeTheme.errorRed.withValues(alpha: 0.15),
          border: Border.all(
            color: FluxForgeTheme.errorRed.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.errorRed,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'CONFLICT: ${warning.conflictingLayerName}',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Snap distance indicator showing how far from nearest snap point
class SnapDistanceIndicator extends StatelessWidget {
  final double distanceMs;
  final bool isClose;

  const SnapDistanceIndicator({
    super.key,
    required this.distanceMs,
    required this.isClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = isClose ? FluxForgeTheme.successGreen : FluxForgeTheme.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.straighten,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${distanceMs.abs().toStringAsFixed(0)}ms',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

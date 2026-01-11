/// Zoom Slider Widget
///
/// Professional DAW-style zoom slider with:
/// - Horizontal slider for zoom control
/// - Zoom in/out buttons
/// - Current zoom level display
/// - Scroll wheel support
/// - Double-click to reset

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';

class ZoomSlider extends StatefulWidget {
  /// Current zoom level (pixels per second)
  final double zoom;

  /// Minimum zoom level
  final double minZoom;

  /// Maximum zoom level
  final double maxZoom;

  /// Default zoom for reset
  final double defaultZoom;

  /// Called when zoom changes
  final ValueChanged<double>? onZoomChange;

  /// Width of the slider
  final double width;

  /// Show zoom value label
  final bool showLabel;

  /// Show +/- buttons
  final bool showButtons;

  const ZoomSlider({
    super.key,
    required this.zoom,
    this.minZoom = 5.0,
    this.maxZoom = 500.0,
    this.defaultZoom = 50.0,
    this.onZoomChange,
    this.width = 150,
    this.showLabel = true,
    this.showButtons = true,
  });

  @override
  State<ZoomSlider> createState() => _ZoomSliderState();
}

class _ZoomSliderState extends State<ZoomSlider> {
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartZoom = 0;

  // Use logarithmic scale for more natural zoom feel
  double _zoomToNormalized(double zoom) {
    final logMin = math.log(widget.minZoom);
    final logMax = math.log(widget.maxZoom);
    final logZoom = math.log(zoom.clamp(widget.minZoom, widget.maxZoom));
    return (logZoom - logMin) / (logMax - logMin);
  }

  double _normalizedToZoom(double normalized) {
    final logMin = math.log(widget.minZoom);
    final logMax = math.log(widget.maxZoom);
    final logZoom = logMin + normalized * (logMax - logMin);
    return math.exp(logZoom).clamp(widget.minZoom, widget.maxZoom);
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartX = details.localPosition.dx;
      _dragStartZoom = widget.zoom;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final sliderWidth = widget.width - (widget.showButtons ? 48 : 0);
    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaNormalized = deltaX / sliderWidth;

    final startNormalized = _zoomToNormalized(_dragStartZoom);
    final newNormalized = (startNormalized + deltaNormalized).clamp(0.0, 1.0);
    final newZoom = _normalizedToZoom(newNormalized);

    widget.onZoomChange?.call(newZoom);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  void _handleDoubleTap() {
    widget.onZoomChange?.call(widget.defaultZoom);
  }

  void _handleScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta.dy > 0 ? 0.95 : 1.05;
    final newZoom = (widget.zoom * delta).clamp(widget.minZoom, widget.maxZoom);
    widget.onZoomChange?.call(newZoom);
  }

  void _zoomIn() {
    final newZoom = (widget.zoom * 1.2).clamp(widget.minZoom, widget.maxZoom);
    widget.onZoomChange?.call(newZoom);
  }

  void _zoomOut() {
    final newZoom = (widget.zoom / 1.2).clamp(widget.minZoom, widget.maxZoom);
    widget.onZoomChange?.call(newZoom);
  }

  String _formatZoom(double zoom) {
    if (zoom >= 100) {
      return '${zoom.toStringAsFixed(0)}';
    } else if (zoom >= 10) {
      return '${zoom.toStringAsFixed(1)}';
    } else {
      return '${zoom.toStringAsFixed(2)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _zoomToNormalized(widget.zoom);
    final sliderWidth = widget.width - (widget.showButtons ? 48 : 0);

    return Container(
      width: widget.width,
      height: 24,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Zoom out button
          if (widget.showButtons)
            _ZoomButton(
              icon: Icons.remove,
              onPressed: _zoomOut,
              tooltip: 'Zoom Out (G)',
            ),

          // Slider area
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _handleScroll(event);
                }
              },
              child: GestureDetector(
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                onDoubleTap: _handleDoubleTap,
                child: Container(
                  height: 24,
                  color: Colors.transparent,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Track background
                      Positioned(
                        left: 4,
                        right: 4,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: ReelForgeTheme.bgDeepest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Fill
                      Positioned(
                        left: 4,
                        child: Container(
                          width: (sliderWidth - 8) * normalized,
                          height: 4,
                          decoration: BoxDecoration(
                            color: ReelForgeTheme.accentBlue.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Thumb
                      Positioned(
                        left: 4 + (sliderWidth - 16) * normalized,
                        child: Container(
                          width: 12,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? ReelForgeTheme.accentBlue
                                : ReelForgeTheme.bgElevated,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: _isDragging
                                  ? ReelForgeTheme.accentBlue
                                  : ReelForgeTheme.borderMedium,
                            ),
                            boxShadow: _isDragging
                                ? [
                                    BoxShadow(
                                      color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Container(
                              width: 4,
                              height: 8,
                              decoration: BoxDecoration(
                                color: ReelForgeTheme.textTertiary,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Zoom label overlay
                      if (widget.showLabel && _isDragging)
                        Positioned(
                          left: 4 + (sliderWidth - 16) * normalized - 10,
                          top: -20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: ReelForgeTheme.bgDeepest,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: ReelForgeTheme.accentBlue),
                            ),
                            child: Text(
                              '${_formatZoom(widget.zoom)} px/s',
                              style: ReelForgeTheme.monoSmall.copyWith(
                                color: ReelForgeTheme.accentBlue,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Zoom in button
          if (widget.showButtons)
            _ZoomButton(
              icon: Icons.add,
              onPressed: _zoomIn,
              tooltip: 'Zoom In (H)',
            ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _ZoomButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border(
              right: icon == Icons.remove
                  ? BorderSide(color: ReelForgeTheme.borderSubtle)
                  : BorderSide.none,
              left: icon == Icons.add
                  ? BorderSide(color: ReelForgeTheme.borderSubtle)
                  : BorderSide.none,
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: ReelForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Compact zoom indicator (for status bar)
class ZoomIndicator extends StatelessWidget {
  final double zoom;
  final VoidCallback? onTap;

  const ZoomIndicator({
    super.key,
    required this.zoom,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.zoom_in,
              size: 12,
              color: ReelForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              '${zoom.toStringAsFixed(0)} px/s',
              style: ReelForgeTheme.monoSmall,
            ),
          ],
        ),
      ),
    );
  }
}

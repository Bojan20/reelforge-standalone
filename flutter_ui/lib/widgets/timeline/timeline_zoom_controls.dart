/// Timeline Zoom Controls
///
/// Zoom and view controls for timeline widgets.
/// Integrates with EventZoomService for per-event persistence.
///
/// Features:
/// - Zoom in/out buttons
/// - Zoom slider with percentage display
/// - Fit to window button
/// - Waveform/grid toggles
/// - Mouse wheel zoom support
///
/// Task: P1-03 Waveform Zoom Per-Event

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/event_zoom_settings.dart';
import '../../theme/fluxforge_theme.dart';

class TimelineZoomControls extends StatelessWidget {
  /// Event ID for persistence
  final String eventId;

  /// Current pixels per second
  final double pixelsPerSecond;

  /// Callback when zoom changes
  final ValueChanged<double>? onZoomChanged;

  /// Callback for fit to window
  final VoidCallback? onFitToWindow;

  /// Callback for waveform toggle
  final ValueChanged<bool>? onWaveformsToggled;

  /// Callback for grid toggle
  final ValueChanged<bool>? onGridToggled;

  /// Show waveforms state
  final bool showWaveforms;

  /// Show grid state
  final bool showGrid;

  /// Compact mode (smaller buttons, no labels)
  final bool compact;

  const TimelineZoomControls({
    super.key,
    required this.eventId,
    required this.pixelsPerSecond,
    this.onZoomChanged,
    this.onFitToWindow,
    this.onWaveformsToggled,
    this.onGridToggled,
    this.showWaveforms = true,
    this.showGrid = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final service = EventZoomService.instance;
    final zoomPercentage = (pixelsPerSecond / EventZoomService.kDefaultPixelsPerSecond) * 100;

    if (compact) {
      return _buildCompactControls(context, service, zoomPercentage);
    } else {
      return _buildFullControls(context, service, zoomPercentage);
    }
  }

  Widget _buildFullControls(BuildContext context, EventZoomService service, double zoomPercentage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Zoom label
          const Icon(Icons.zoom_in, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          const Text(
            'Zoom',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 12),

          // Zoom out button
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            tooltip: 'Zoom Out',
            onPressed: () => _zoomOut(service),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            color: Colors.white70,
          ),

          // Zoom slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: pixelsPerSecond,
                min: EventZoomService.kMinPixelsPerSecond,
                max: EventZoomService.kMaxPixelsPerSecond,
                divisions: 50,
                label: '${zoomPercentage.toInt()}%',
                onChanged: onZoomChanged,
                activeColor: FluxForgeTheme.accentBlue,
              ),
            ),
          ),

          // Zoom in button
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Zoom In',
            onPressed: () => _zoomIn(service),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            color: Colors.white70,
          ),

          const SizedBox(width: 12),

          // Zoom percentage display
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${zoomPercentage.toInt()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Fit to window button
          if (onFitToWindow != null)
            TextButton.icon(
              icon: const Icon(Icons.fit_screen, size: 14),
              label: const Text('Fit', style: TextStyle(fontSize: 11)),
              onPressed: onFitToWindow,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

          const SizedBox(width: 8),

          // View toggles
          _buildToggleButton(
            icon: Icons.graphic_eq,
            label: 'Waves',
            isActive: showWaveforms,
            onPressed: () => onWaveformsToggled?.call(!showWaveforms),
            tooltip: 'Toggle Waveforms',
          ),

          const SizedBox(width: 4),

          _buildToggleButton(
            icon: Icons.grid_on,
            label: 'Grid',
            isActive: showGrid,
            onPressed: () => onGridToggled?.call(!showGrid),
            tooltip: 'Toggle Grid',
          ),
        ],
      ),
    );
  }

  Widget _buildCompactControls(BuildContext context, EventZoomService service, double zoomPercentage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 14),
            tooltip: 'Zoom Out',
            onPressed: () => _zoomOut(service),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Colors.white70,
            iconSize: 14,
          ),
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${zoomPercentage.toInt()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: 'Zoom In',
            onPressed: () => _zoomIn(service),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Colors.white70,
            iconSize: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : const Color(0xFF0D0D10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentBlue : Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? FluxForgeTheme.accentBlue : Colors.white54,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? FluxForgeTheme.accentBlue : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoomIn(EventZoomService service) {
    service.zoomIn(eventId, factor: 0.15);
    onZoomChanged?.call(service.getSettings(eventId).pixelsPerSecond);
  }

  void _zoomOut(EventZoomService service) {
    service.zoomOut(eventId, factor: 0.15);
    onZoomChanged?.call(service.getSettings(eventId).pixelsPerSecond);
  }
}

/// Mouse wheel zoom handler wrapper
/// Wraps any widget and adds mouse wheel zoom functionality
class MouseWheelZoom extends StatelessWidget {
  final Widget child;
  final String eventId;
  final ValueChanged<double>? onZoomChanged;

  const MouseWheelZoom({
    super.key,
    required this.child,
    required this.eventId,
    this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Check if Ctrl/Cmd is pressed for zoom
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          if (isCtrlPressed) {
            final service = EventZoomService.instance;
            final settings = service.getSettings(eventId);

            // Scroll up = zoom in, scroll down = zoom out
            final delta = event.scrollDelta.dy;
            final zoomFactor = delta > 0 ? -0.05 : 0.05; // Inverted for natural scroll

            final newZoom = settings.pixelsPerSecond * (1 + zoomFactor);
            final clampedZoom = newZoom.clamp(
              EventZoomService.kMinPixelsPerSecond,
              EventZoomService.kMaxPixelsPerSecond,
            );

            service.setPixelsPerSecond(eventId, clampedZoom);
            onZoomChanged?.call(clampedZoom);
          }
        }
      },
      child: child,
    );
  }
}

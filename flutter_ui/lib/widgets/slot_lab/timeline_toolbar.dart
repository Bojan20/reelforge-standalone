/// Timeline Toolbar Widget
///
/// Compact toolbar for SlotLab timeline with:
/// - Snap-to-grid toggle (magnet icon)
/// - Grid interval dropdown
/// - Zoom controls (slider + buttons)

import 'package:flutter/material.dart';
import '../../controllers/slot_lab/timeline_drag_controller.dart';

/// Available zoom presets
const List<double> _zoomPresets = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0];

/// Compact toolbar for timeline controls
class TimelineToolbar extends StatelessWidget {
  final TimelineDragController dragController;
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;

  const TimelineToolbar({
    super.key,
    required this.dragController,
    required this.zoomLevel,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dragController,
      builder: (context, _) {
        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withAlpha(20),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Snap toggle
              _SnapToggleButton(
                isEnabled: dragController.snapEnabled,
                onToggle: dragController.toggleSnap,
              ),
              const SizedBox(width: 8),

              // Grid interval dropdown (only visible when snap enabled)
              if (dragController.snapEnabled) ...[
                _GridIntervalDropdown(
                  currentInterval: dragController.gridInterval,
                  onChanged: dragController.setGridInterval,
                ),
                const SizedBox(width: 16),
              ],

              // Divider
              Container(
                width: 1,
                height: 16,
                color: Colors.white.withAlpha(30),
              ),
              const SizedBox(width: 12),

              // Zoom controls
              _ZoomControls(
                zoomLevel: zoomLevel,
                onZoomChanged: onZoomChanged,
              ),

              // Spacer
              const Spacer(),

              // Keyboard hints
              Text(
                'S: snap  G/H: zoom  0: reset',
                style: TextStyle(
                  color: Colors.white.withAlpha(80),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Zoom controls with slider and buttons
class _ZoomControls extends StatelessWidget {
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;

  const _ZoomControls({
    required this.zoomLevel,
    required this.onZoomChanged,
  });

  void _zoomIn() {
    final newZoom = (zoomLevel * 1.25).clamp(0.1, 10.0);
    onZoomChanged(newZoom);
  }

  void _zoomOut() {
    final newZoom = (zoomLevel / 1.25).clamp(0.1, 10.0);
    onZoomChanged(newZoom);
  }

  void _resetZoom() {
    onZoomChanged(1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom out button
        _IconButton(
          icon: Icons.remove,
          tooltip: 'Zoom out (G)',
          onPressed: _zoomOut,
        ),
        const SizedBox(width: 4),

        // Zoom slider
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFF4a9eff),
              inactiveTrackColor: Colors.white.withAlpha(30),
              thumbColor: const Color(0xFF4a9eff),
              overlayColor: const Color(0xFF4a9eff).withAlpha(30),
            ),
            child: Slider(
              value: zoomLevel.clamp(0.1, 10.0),
              min: 0.1,
              max: 10.0,
              onChanged: onZoomChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Zoom in button
        _IconButton(
          icon: Icons.add,
          tooltip: 'Zoom in (H)',
          onPressed: _zoomIn,
        ),
        const SizedBox(width: 8),

        // Zoom percentage / reset button
        Tooltip(
          message: 'Reset zoom (Ctrl+0)',
          child: InkWell(
            onTap: _resetZoom,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(zoomLevel * 100).toInt()}%',
                style: TextStyle(
                  color: zoomLevel == 1.0
                      ? Colors.white.withAlpha(100)
                      : const Color(0xFF4a9eff),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small icon button for toolbar
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: Icon(
            icon,
            size: 12,
            color: Colors.white.withAlpha(140),
          ),
        ),
      ),
    );
  }
}

/// Toggle button for snap-to-grid
class _SnapToggleButton extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onToggle;

  const _SnapToggleButton({
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isEnabled ? 'Disable snap (S)' : 'Enable snap (S)',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 24,
          decoration: BoxDecoration(
            color: isEnabled
                ? const Color(0xFF4a9eff).withAlpha(50)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                  ? const Color(0xFF4a9eff)
                  : Colors.white.withAlpha(40),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.grid_on,
            size: 14,
            color: isEnabled ? const Color(0xFF4a9eff) : Colors.white.withAlpha(140),
          ),
        ),
      ),
    );
  }
}

/// Dropdown for grid interval selection
class _GridIntervalDropdown extends StatelessWidget {
  final GridInterval currentInterval;
  final ValueChanged<GridInterval> onChanged;

  const _GridIntervalDropdown({
    required this.currentInterval,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.white.withAlpha(30),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GridInterval>(
          value: currentInterval,
          isDense: true,
          dropdownColor: const Color(0xFF242430),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: Colors.white.withAlpha(140),
          ),
          items: GridInterval.values.map((interval) {
            return DropdownMenuItem<GridInterval>(
              value: interval,
              child: Text(interval.label),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      ),
    );
  }
}

/// Timeline Toolbar Widget
///
/// Compact toolbar for SlotLab timeline with:
/// - Snap-to-grid toggle (magnet icon)
/// - Grid interval dropdown
/// - Zoom controls (future P2.2)

import 'package:flutter/material.dart';
import '../../controllers/slot_lab/timeline_drag_controller.dart';

/// Compact toolbar for timeline controls
class TimelineToolbar extends StatelessWidget {
  final TimelineDragController dragController;

  const TimelineToolbar({
    super.key,
    required this.dragController,
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

              // Spacer
              const Spacer(),

              // Keyboard hint
              if (dragController.snapEnabled)
                Text(
                  'S to toggle snap',
                  style: TextStyle(
                    color: Colors.white.withAlpha(100),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        );
      },
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

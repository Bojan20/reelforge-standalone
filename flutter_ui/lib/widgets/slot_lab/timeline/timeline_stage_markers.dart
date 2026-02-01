// Timeline Stage Markers — SlotLab Stage Visualization
//
// Visual stage markers that sync with SlotLab stage events:
// - SPIN_START, REEL_STOP_0..4, WIN_PRESENT, etc.
// - Color-coded by stage type
// - Click to jump playhead
// - Auto-sync from SlotLabProvider

import 'package:flutter/material.dart';
import '../../../models/timeline/stage_marker.dart';

class TimelineStageMarkersOverlay extends StatelessWidget {
  final List<StageMarker> markers;
  final double duration;
  final double canvasWidth;
  final double zoom;
  final Function(StageMarker marker)? onMarkerClicked;
  final Function(StageMarker marker)? onMarkerRightClicked;

  const TimelineStageMarkersOverlay({
    super.key,
    required this.markers,
    required this.duration,
    required this.canvasWidth,
    this.zoom = 1.0,
    this.onMarkerClicked,
    this.onMarkerRightClicked,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: markers.map((marker) {
        return _buildMarker(marker);
      }).toList(),
    );
  }

  Widget _buildMarker(StageMarker marker) {
    final x = (marker.timeSeconds / duration) * canvasWidth;

    // Label rotation based on zoom
    final shouldRotate = zoom < 2.0; // Rotate when zoomed out

    return Positioned(
      left: x - 1,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () => onMarkerClicked?.call(marker),
        onSecondaryTapDown: (_) => onMarkerRightClicked?.call(marker),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: marker.isMuted
                  ? Colors.white.withOpacity(0.2)
                  : marker.color.withOpacity(0.6),
              boxShadow: marker.isMuted
                  ? null
                  : [
                      BoxShadow(
                        color: marker.color.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.rotate(
                angle: shouldRotate ? -1.5708 : 0, // -90° when rotated
                child: Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: marker.isMuted
                        ? Colors.white.withOpacity(0.3)
                        : marker.color.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    marker.label,
                    style: TextStyle(
                      fontSize: shouldRotate ? 8 : 9,
                      fontWeight: FontWeight.w600,
                      color: marker.isMuted ? Colors.white54 : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stage marker context menu
class StageMarkerContextMenu {
  static Future<StageMarkerAction?> show({
    required BuildContext context,
    required StageMarker marker,
    required Offset position,
  }) async {
    return showMenu<StageMarkerAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 150,
        position.dy + 200,
      ),
      items: [
        PopupMenuItem(
          value: StageMarkerAction.jumpToMarker,
          child: Row(
            children: [
              const Icon(Icons.play_arrow, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Jump to Marker', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),

        PopupMenuItem(
          value: marker.isMuted ? StageMarkerAction.unmute : StageMarkerAction.mute,
          child: Row(
            children: [
              Icon(
                marker.isMuted ? Icons.volume_up : Icons.volume_off,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                marker.isMuted ? 'Unmute Stage' : 'Mute Stage',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),

        const PopupMenuDivider(),

        const PopupMenuItem(
          value: StageMarkerAction.editProperties,
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Edit Properties...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),

        const PopupMenuItem(
          value: StageMarkerAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Color(0xFFFF4060)),
              SizedBox(width: 8),
              Text('Delete Marker', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

enum StageMarkerAction {
  jumpToMarker,
  mute,
  unmute,
  editProperties,
  delete,
}

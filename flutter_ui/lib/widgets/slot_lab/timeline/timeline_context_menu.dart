// Timeline Context Menu — Right-Click Actions
//
// Context menu for timeline regions with Pro Tools-style actions:
// - Split, Delete, Duplicate
// - Normalize, Fade In/Out
// - Trim, Color

import 'package:flutter/material.dart';
import '../../../models/timeline/audio_region.dart';

/// Context menu actions
enum TimelineContextAction {
  split,
  delete,
  duplicate,
  normalize,
  fadeIn,
  fadeOut,
  trimToSelection,
  changeColor,
  muteRegion,
  copyToClipboard,
}

class TimelineContextMenu extends StatelessWidget {
  final AudioRegion region;
  final Offset position;
  final Function(TimelineContextAction action, AudioRegion region)? onActionSelected;

  const TimelineContextMenu({
    super.key,
    required this.region,
    required this.position,
    this.onActionSelected,
  });

  static Future<TimelineContextAction?> show({
    required BuildContext context,
    required AudioRegion region,
    required Offset position,
  }) async {
    final result = await showMenu<TimelineContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 200,
        position.dy + 400,
      ),
      items: [
        // Edit actions
        const PopupMenuItem(
          value: TimelineContextAction.split,
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Split at Playhead', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('S', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuItem(
          value: TimelineContextAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Color(0xFFFF4060)),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('Del', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuItem(
          value: TimelineContextAction.duplicate,
          child: Row(
            children: [
              Icon(Icons.copy, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('⌘D', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuDivider(),

        // Processing actions
        const PopupMenuItem(
          value: TimelineContextAction.normalize,
          child: Row(
            children: [
              Icon(Icons.equalizer, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Normalize', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('⌘N', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuItem(
          value: TimelineContextAction.fadeIn,
          child: Row(
            children: [
              Icon(Icons.trending_up, size: 16, color: Color(0xFF40FF90)),
              SizedBox(width: 8),
              Text('Fade In', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('⌘F', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuItem(
          value: TimelineContextAction.fadeOut,
          child: Row(
            children: [
              Icon(Icons.trending_down, size: 16, color: Color(0xFFFF9040)),
              SizedBox(width: 8),
              Text('Fade Out', style: TextStyle(fontSize: 12)),
              Spacer(),
              Text('⌘⇧F', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ),

        const PopupMenuDivider(),

        // Visual actions
        const PopupMenuItem(
          value: TimelineContextAction.changeColor,
          child: Row(
            children: [
              Icon(Icons.palette, size: 16, color: Colors.white70),
              SizedBox(width: 8),
              Text('Change Color...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),

        PopupMenuItem(
          value: TimelineContextAction.muteRegion,
          child: Row(
            children: [
              Icon(
                region.isMuted ? Icons.volume_up : Icons.volume_off,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                region.isMuted ? 'Unmute Region' : 'Mute Region',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    // This widget is not directly used — use static show() method instead
    return const SizedBox.shrink();
  }
}

/// Fade editor dialog
class FadeEditorDialog extends StatefulWidget {
  final double initialFadeMs;
  final FadeCurve initialCurve;
  final bool isFadeIn;

  const FadeEditorDialog({
    super.key,
    required this.initialFadeMs,
    required this.initialCurve,
    this.isFadeIn = true,
  });

  static Future<({double fadeMs, FadeCurve curve})?> show({
    required BuildContext context,
    required double initialFadeMs,
    required FadeCurve initialCurve,
    required bool isFadeIn,
  }) async {
    return showDialog<({double fadeMs, FadeCurve curve})>(
      context: context,
      builder: (context) => FadeEditorDialog(
        initialFadeMs: initialFadeMs,
        initialCurve: initialCurve,
        isFadeIn: isFadeIn,
      ),
    );
  }

  @override
  State<FadeEditorDialog> createState() => _FadeEditorDialogState();
}

class _FadeEditorDialogState extends State<FadeEditorDialog> {
  late double _fadeMs;
  late FadeCurve _curve;

  @override
  void initState() {
    super.initState();
    _fadeMs = widget.initialFadeMs;
    _curve = widget.initialCurve;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isFadeIn ? 'Fade In' : 'Fade Out'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Duration slider
            Row(
              children: [
                const Text('Duration:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _fadeMs,
                    min: 0,
                    max: 2000,
                    divisions: 40,
                    label: '${_fadeMs.toInt()}ms',
                    onChanged: (value) => setState(() => _fadeMs = value),
                  ),
                ),
                Text('${_fadeMs.toInt()}ms', style: const TextStyle(fontSize: 11)),
              ],
            ),

            const SizedBox(height: 16),

            // Curve selector
            const Text('Curve:', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FadeCurve.values.map((curve) {
                final isSelected = _curve == curve;
                return InkWell(
                  onTap: () => setState(() => _curve = curve),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF4A9EFF) : const Color(0xFF242430),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF4A9EFF) : Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      _curveName(curve),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop((fadeMs: _fadeMs, curve: _curve));
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  String _curveName(FadeCurve curve) {
    switch (curve) {
      case FadeCurve.linear:
        return 'Linear';
      case FadeCurve.exponential:
        return 'Exponential';
      case FadeCurve.logarithmic:
        return 'Logarithmic';
      case FadeCurve.sCurve:
        return 'S-Curve';
      case FadeCurve.equalPower:
        return 'Equal Power';
    }
  }
}

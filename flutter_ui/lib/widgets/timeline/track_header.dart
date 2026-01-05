/// Track Header Widget
///
/// Cubase-style track header with:
/// - Two-row layout (name + controls)
/// - M/S/R buttons
/// - Volume/Pan sliders
/// - Bus routing
/// - Color picker
/// - Freeze/Lock indicators

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class TrackHeader extends StatefulWidget {
  final TimelineTrack track;
  final double height;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onMonitorToggle;
  final VoidCallback? onFreezeToggle;
  final VoidCallback? onLockToggle;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onClick;
  final ValueChanged<Color>? onColorChange;
  final ValueChanged<OutputBus>? onBusChange;
  final ValueChanged<String>? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final void Function(Offset position)? onContextMenu;

  const TrackHeader({
    super.key,
    required this.track,
    required this.height,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onMonitorToggle,
    this.onFreezeToggle,
    this.onLockToggle,
    this.onVolumeChange,
    this.onPanChange,
    this.onClick,
    this.onColorChange,
    this.onBusChange,
    this.onRename,
    this.onDuplicate,
    this.onDelete,
    this.onContextMenu,
  });

  @override
  State<TrackHeader> createState() => _TrackHeaderState();
}

class _TrackHeaderState extends State<TrackHeader> {
  bool _showColorPicker = false;
  bool _isEditing = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditing) {
      _nameController.text = widget.track.name;
    }
  }

  String get _volumeDisplay {
    if (widget.track.volume <= 0) return '-∞';
    final db = 20 * _log10(widget.track.volume);
    return db <= -60 ? '-∞' : db.toStringAsFixed(1);
  }

  String get _panDisplay {
    final pan = widget.track.pan;
    if (pan == 0) return 'C';
    return pan < 0
        ? 'L${(pan.abs() * 100).round()}'
        : 'R${(pan * 100).round()}';
  }

  double _log10(double x) => x > 0 ? (math.log(x) / math.ln10) : double.negativeInfinity;

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _nameController.text = widget.track.name;
    });
    _focusNode.requestFocus();
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.track.name) {
      widget.onRename?.call(trimmed);
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final busInfo = getBusInfo(track.outputBus);

    return GestureDetector(
      onTap: widget.onClick,
      onSecondaryTapDown: (details) {
        if (widget.onContextMenu != null) {
          widget.onContextMenu!(details.globalPosition);
        } else {
          setState(() => _showColorPicker = true);
        }
      },
      child: Container(
        width: 180,
        height: widget.height,
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgMid,
          border: Border(
            left: BorderSide(color: track.color, width: 3),
            bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Name + M/S/R
                  Row(
                    children: [
                      // Name
                      Expanded(
                        child: _isEditing
                            ? TextField(
                                controller: _nameController,
                                focusNode: _focusNode,
                                style: ReelForgeTheme.body.copyWith(
                                  color: ReelForgeTheme.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _submitName(),
                                onEditingComplete: _submitName,
                              )
                            : GestureDetector(
                                onDoubleTap: _startEditing,
                                child: Text(
                                  track.name,
                                  style: ReelForgeTheme.body.copyWith(
                                    color: ReelForgeTheme.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      // M/S/R buttons
                      _TrackButton(
                        label: 'M',
                        isActive: track.muted,
                        activeColor: ReelForgeTheme.accentOrange,
                        onTap: widget.onMuteToggle,
                      ),
                      _TrackButton(
                        label: 'S',
                        isActive: track.soloed,
                        activeColor: ReelForgeTheme.accentYellow,
                        onTap: widget.onSoloToggle,
                      ),
                      _TrackButton(
                        label: 'R',
                        isActive: track.armed,
                        activeColor: ReelForgeTheme.accentRed,
                        onTap: widget.onArmToggle,
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Bottom row: Volume/Pan + Bus
                  Row(
                    children: [
                      // Volume slider
                      Expanded(
                        flex: 2,
                        child: _CompactSlider(
                          value: track.volume,
                          min: 0,
                          max: 1.5,
                          onChanged: widget.onVolumeChange,
                          onDoubleClick: () => widget.onVolumeChange?.call(1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 28,
                        child: Text(
                          _volumeDisplay,
                          style: ReelForgeTheme.monoSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Pan slider
                      Expanded(
                        flex: 2,
                        child: _CompactSlider(
                          value: (track.pan + 1) / 2, // -1..1 to 0..1
                          min: 0,
                          max: 1,
                          onChanged: (v) => widget.onPanChange?.call(v * 2 - 1),
                          onDoubleClick: () => widget.onPanChange?.call(0),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 24,
                        child: Text(
                          _panDisplay,
                          style: ReelForgeTheme.monoSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Bus indicator
                      GestureDetector(
                        onTap: () {
                          // Cycle to next bus
                          final currentIndex = kBusOptions.indexWhere(
                            (b) => b.bus == track.outputBus,
                          );
                          final nextIndex = (currentIndex + 1) % kBusOptions.length;
                          widget.onBusChange?.call(kBusOptions[nextIndex].bus);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: busInfo.color.withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            busInfo.shortName,
                            style: ReelForgeTheme.label.copyWith(
                              color: busInfo.color,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Secondary controls (I, Freeze, Lock) - shown on hover
            Positioned(
              top: 2,
              right: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallButton(
                    icon: 'I',
                    isActive: track.inputMonitor,
                    onTap: widget.onMonitorToggle,
                    tooltip: 'Input Monitor',
                  ),
                  _SmallButton(
                    icon: '❄',
                    isActive: track.frozen,
                    onTap: widget.onFreezeToggle,
                    tooltip: track.frozen ? 'Unfreeze' : 'Freeze',
                  ),
                  _SmallButton(
                    icon: '🔒',
                    isActive: track.locked,
                    onTap: widget.onLockToggle,
                    tooltip: track.locked ? 'Unlock' : 'Lock',
                  ),
                ],
              ),
            ),
            // Frozen/Locked overlays
            if (track.frozen)
              Positioned.fill(
                child: Container(
                  color: ReelForgeTheme.accentCyan.withValues(alpha: 0.1),
                ),
              ),
            if (track.locked)
              Positioned.fill(
                child: Container(
                  color: ReelForgeTheme.textTertiary.withValues(alpha: 0.1),
                ),
              ),
            // Color picker popup
            if (_showColorPicker)
              Positioned(
                top: 0,
                left: 0,
                child: MouseRegion(
                  onExit: (_) => setState(() => _showColorPicker = false),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: ReelForgeTheme.borderMedium),
                    ),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: kTrackColors.map((color) {
                        return GestureDetector(
                          onTap: () {
                            widget.onColorChange?.call(color);
                            setState(() => _showColorPicker = false);
                          },
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                              border: track.color == color
                                  ? Border.all(
                                      color: ReelForgeTheme.textPrimary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _TrackButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 18,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: isActive ? activeColor : ReelForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? ReelForgeTheme.bgDeep
                  : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String icon;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;

  const _SmallButton({
    required this.icon,
    required this.isActive,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              icon,
              style: TextStyle(
                fontSize: 8,
                color: isActive
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onDoubleClick;

  const _CompactSlider({
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.onDoubleClick,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleClick,
      child: SizedBox(
        height: 12,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            activeTrackColor: ReelForgeTheme.accentBlue,
            inactiveTrackColor: ReelForgeTheme.bgDeep,
            thumbColor: ReelForgeTheme.textPrimary,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// Simple Track Header Widget
///
/// Minimalist ReelForge-style track header:
/// - Track number + name
/// - M/S/R buttons
/// - Volume slider (on hover or when expanded)
/// - Subtle color accent
///
/// Designed for clarity over feature density.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class TrackHeaderSimple extends StatefulWidget {
  final TimelineTrack track;
  final double width;
  final double height;
  final int trackNumber;
  final bool isSelected;
  final double signalLevel;

  // Callbacks
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onClick;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<String>? onRename;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<double>? onHeightChange;

  const TrackHeaderSimple({
    super.key,
    required this.track,
    this.width = 160,
    this.height = 56,
    this.trackNumber = 1,
    this.isSelected = false,
    this.signalLevel = 0.0,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onClick,
    this.onVolumeChange,
    this.onRename,
    this.onContextMenu,
    this.onHeightChange,
  });

  @override
  State<TrackHeaderSimple> createState() => _TrackHeaderSimpleState();
}

class _TrackHeaderSimpleState extends State<TrackHeaderSimple> {
  bool _isHovered = false;
  bool _isResizing = false;
  bool _isEditingName = false;
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
  void didUpdateWidget(TrackHeaderSimple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditingName) {
      _nameController.text = widget.track.name;
    }
  }

  bool get _showVolume => _isHovered || widget.height > 50;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onClick,
        onDoubleTap: () => setState(() => _isEditingName = true),
        onSecondaryTapDown: (d) => widget.onContextMenu?.call(d.globalPosition),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? track.color.withValues(alpha: 0.12)
                : (_isHovered ? ReelForgeTheme.bgSurface : ReelForgeTheme.bgMid),
            border: Border(
              left: BorderSide(color: track.color, width: 3),
              bottom: BorderSide(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)),
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Track number + name + M/S/R
                    SizedBox(
                      height: 20,
                      child: Row(
                        children: [
                          // Track number
                          SizedBox(
                            width: 18,
                            child: Text(
                              '${widget.trackNumber}',
                              style: TextStyle(
                                color: ReelForgeTheme.textTertiary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Name
                          Expanded(child: _buildName()),
                          const SizedBox(width: 4),
                          // M/S/R buttons
                          _MiniButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
                          const SizedBox(width: 2),
                          _MiniButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
                          const SizedBox(width: 2),
                          _RecordButton(track.armed, widget.onArmToggle),
                        ],
                      ),
                    ),
                    // Row 2: Volume (if shown and height allows)
                    if (_showVolume && widget.height > 44)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _buildVolumeRow(),
                      ),
                  ],
                ),
              ),

              // Meter bar (right edge)
              Positioned(
                top: 4,
                bottom: 4,
                right: 2,
                width: 3,
                child: _MeterBar(level: widget.signalLevel),
              ),

              // Resize handle
              if (_isHovered || _isResizing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 5,
                  child: _buildResizeHandle(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildName() {
    if (_isEditingName) {
      return TextField(
        controller: _nameController,
        focusNode: _focusNode,
        autofocus: true,
        style: TextStyle(
          color: ReelForgeTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onSubmitted: (_) => _submitName(),
        onTapOutside: (_) => _submitName(),
      );
    }

    return Text(
      widget.track.name,
      style: TextStyle(
        color: widget.track.muted ? ReelForgeTheme.textTertiary : ReelForgeTheme.textPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.track.name) {
      widget.onRename?.call(trimmed);
    }
    setState(() => _isEditingName = false);
  }

  Widget _buildVolumeRow() {
    return Row(
      children: [
        Text('Vol', style: TextStyle(fontSize: 9, color: ReelForgeTheme.textTertiary)),
        const SizedBox(width: 6),
        Expanded(
          child: _VolumeSlider(
            value: widget.track.volume,
            onChanged: widget.onVolumeChange,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          child: Text(
            _formatDb(widget.track.volume),
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'JetBrains Mono',
              color: ReelForgeTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isResizing = true),
        onVerticalDragEnd: (_) => setState(() => _isResizing = false),
        onVerticalDragUpdate: (d) {
          final newHeight = (widget.height + d.delta.dy).clamp(32.0, 160.0);
          widget.onHeightChange?.call(newHeight);
        },
        child: Container(
          color: widget.track.color.withValues(alpha: _isResizing ? 0.4 : 0.2),
        ),
      ),
    );
  }

  String _formatDb(double linear) {
    if (linear <= 0) return '-∞';
    final db = 20 * (math.log(linear) / math.ln10);
    return db <= -60 ? '-∞' : '${db >= 0 ? "+" : ""}${db.toStringAsFixed(0)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _MiniButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _MiniButton(this.label, this.active, this.activeColor, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: active ? activeColor : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool armed;
  final VoidCallback? onTap;

  const _RecordButton(this.armed, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: armed ? ReelForgeTheme.accentRed : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: armed ? ReelForgeTheme.accentRed : ReelForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: armed ? Colors.white : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _VolumeSlider({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final normalized = (value / 1.5).clamp(0.0, 1.0);

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (onChanged != null) {
              final newValue = ((d.localPosition.dx / constraints.maxWidth) * 1.5).clamp(0.0, 1.5);
              onChanged!(newValue);
            }
          },
          onDoubleTap: () => onChanged?.call(1.0),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: normalized,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: ReelForgeTheme.accentGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MeterBar extends StatelessWidget {
  final double level;

  const _MeterBar({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: level.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: const [
                  Color(0xFF40FF90),
                  Color(0xFFFFFF40),
                  Color(0xFFFF4040),
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ultimate Track Header Widget - Pro Audio DAW Style
///
/// Ultra-modern design inspired by the best DAWs:
/// - Ableton Live 12: Ultra-clean, focused, no clutter
/// - Logic Pro X: Elegant gradients, premium feel
/// - Studio One 6: Modern, readable, efficient
/// - Cubase 13: Professional, comprehensive
/// - Pro Tools: Industry standard controls
///
/// Features:
/// - Per-track resizable (vertical + horizontal)
/// - Adaptive layout (Mini/Compact/Standard/Large/XL)
/// - Professional stereo waveform preview
/// - Real-time stereo metering
/// - Glass morphism UI elements
/// - Smooth micro-animations
/// - Grid-synced operations

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

const double kMinTrackHeight = 28;
const double kDefaultTrackHeight = 56;
const double kMaxTrackHeight = 200;
const double kMinHeaderWidth = 140;
const double kDefaultHeaderWidth = 200;
const double kMaxHeaderWidth = 360;

// Layout thresholds
const double kCompactThreshold = 40;
const double kStandardThreshold = 64;
const double kExpandedThreshold = 100;
const double kXLThreshold = 140;

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class TrackHeaderUltimate extends StatefulWidget {
  final TimelineTrack track;
  final double width;
  final double height;
  final double signalLevel;
  final double signalLevelR;
  final bool isEmpty;
  final bool isSelected;
  final Float32List? waveformPreview;
  final Float32List? waveformPreviewR;

  // Callbacks
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onMonitorToggle;
  final VoidCallback? onFreezeToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onAutomationToggle;
  final VoidCallback? onFolderToggle;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onClick;
  final ValueChanged<Color>? onColorChange;
  final ValueChanged<OutputBus>? onBusChange;
  final ValueChanged<String>? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<double>? onHeightChange;
  final ValueChanged<double>? onWidthChange;

  const TrackHeaderUltimate({
    super.key,
    required this.track,
    this.width = kDefaultHeaderWidth,
    this.height = kDefaultTrackHeight,
    this.signalLevel = 0.0,
    this.signalLevelR = 0.0,
    this.isEmpty = false,
    this.isSelected = false,
    this.waveformPreview,
    this.waveformPreviewR,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onMonitorToggle,
    this.onFreezeToggle,
    this.onLockToggle,
    this.onAutomationToggle,
    this.onFolderToggle,
    this.onVolumeChange,
    this.onPanChange,
    this.onClick,
    this.onColorChange,
    this.onBusChange,
    this.onRename,
    this.onDuplicate,
    this.onDelete,
    this.onContextMenu,
    this.onHeightChange,
    this.onWidthChange,
  });

  @override
  State<TrackHeaderUltimate> createState() => _TrackHeaderUltimateState();
}

class _TrackHeaderUltimateState extends State<TrackHeaderUltimate>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isResizingV = false;
  bool _isResizingH = false;
  bool _isEditing = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Peak hold with decay
  double _peakHoldL = 0.0;
  double _peakHoldR = 0.0;
  int _peakHoldCounterL = 0;
  int _peakHoldCounterR = 0;

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
  void didUpdateWidget(TrackHeaderUltimate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditing) {
      _nameController.text = widget.track.name;
    }
    // Peak hold with decay
    if (widget.signalLevel > _peakHoldL) {
      _peakHoldL = widget.signalLevel;
      _peakHoldCounterL = 30; // Hold for ~30 frames
    } else if (_peakHoldCounterL > 0) {
      _peakHoldCounterL--;
    } else {
      _peakHoldL = math.max(0, _peakHoldL - 0.02);
    }

    if (widget.signalLevelR > _peakHoldR) {
      _peakHoldR = widget.signalLevelR;
      _peakHoldCounterR = 30;
    } else if (_peakHoldCounterR > 0) {
      _peakHoldCounterR--;
    } else {
      _peakHoldR = math.max(0, _peakHoldR - 0.02);
    }
  }

  // Layout mode detection
  _LayoutMode get _layoutMode {
    if (widget.height < kCompactThreshold) return _LayoutMode.mini;
    if (widget.height < kStandardThreshold) return _LayoutMode.compact;
    if (widget.height < kExpandedThreshold) return _LayoutMode.standard;
    if (widget.height < kXLThreshold) return _LayoutMode.expanded;
    return _LayoutMode.xl;
  }

  String _volumeToDb(double linear) {
    if (linear <= 0) return '-∞';
    final db = 20 * (math.log(linear) / math.ln10);
    return db <= -60 ? '-∞' : '${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)}';
  }

  String _panDisplay(double pan) {
    if (pan.abs() < 0.01) return 'C';
    return pan < 0 ? 'L${(pan.abs() * 100).round()}' : 'R${(pan * 100).round()}';
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

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onClick,
        onSecondaryTapDown: (d) => widget.onContextMenu?.call(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: _buildBackgroundGradient(),
            border: Border(
              left: BorderSide(
                color: track.color,
                width: widget.isSelected ? 4 : 3,
              ),
              bottom: BorderSide(
                color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
                child: _buildLayout(track),
              ),

              // Stereo meter (always visible, right side)
              Positioned(
                top: 4,
                bottom: 4,
                right: _isHovered ? 8 : 4,
                width: _layoutMode == _LayoutMode.mini ? 4 : 10,
                child: _StereoMeter(
                  levelL: widget.signalLevel,
                  levelR: widget.signalLevelR,
                  peakL: _peakHoldL,
                  peakR: _peakHoldR,
                  compact: _layoutMode == _LayoutMode.mini,
                ),
              ),

              // Resize handles
              if (_isHovered || _isResizingV || _isResizingH) ...[
                _buildVerticalResizeHandle(),
                _buildHorizontalResizeHandle(),
              ],

              // State overlays
              if (track.frozen) _buildFrozenOverlay(),
              if (track.locked) _buildLockedOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _buildBackgroundGradient() {
    Color topColor, bottomColor;

    if (widget.isSelected) {
      topColor = widget.track.color.withValues(alpha: 0.12);
      bottomColor = widget.track.color.withValues(alpha: 0.06);
    } else if (widget.track.armed) {
      topColor = ReelForgeTheme.accentRed.withValues(alpha: 0.08);
      bottomColor = ReelForgeTheme.accentRed.withValues(alpha: 0.04);
    } else if (_isHovered) {
      topColor = ReelForgeTheme.bgSurface;
      bottomColor = ReelForgeTheme.bgMid;
    } else {
      topColor = ReelForgeTheme.bgMid;
      bottomColor = ReelForgeTheme.bgDeep;
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, bottomColor],
    );
  }

  Widget _buildLayout(TimelineTrack track) {
    switch (_layoutMode) {
      case _LayoutMode.mini:
        return _buildMiniLayout(track);
      case _LayoutMode.compact:
        return _buildCompactLayout(track);
      case _LayoutMode.standard:
        return _buildStandardLayout(track);
      case _LayoutMode.expanded:
        return _buildExpandedLayout(track);
      case _LayoutMode.xl:
        return _buildXLLayout(track);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MINI LAYOUT (< 40px) - Just name + M/S
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMiniLayout(TimelineTrack track) {
    return Row(
      children: [
        Expanded(
          child: Text(
            track.name,
            style: TextStyle(
              color: track.muted ? ReelForgeTheme.textTertiary : ReelForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        _PillButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
        const SizedBox(width: 2),
        _PillButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
        const SizedBox(width: 14), // Space for meter
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPACT LAYOUT (40-64px) - Name + M/S/R + mini volume
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactLayout(TimelineTrack track) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 16,
          child: Row(
            children: [
              Expanded(child: _buildTrackName(track, fontSize: 11)),
              _PillButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              const SizedBox(width: 2),
              _PillButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              const SizedBox(width: 2),
              _PillButton('R', track.armed, ReelForgeTheme.accentRed, widget.onArmToggle),
              const SizedBox(width: 16),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Volume bar
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: _GlassSlider(
              value: track.volume,
              max: 1.5,
              color: ReelForgeTheme.accentGreen,
              label: _volumeToDb(track.volume),
              onChanged: widget.onVolumeChange,
              onDoubleTap: () => widget.onVolumeChange?.call(1.0),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDARD LAYOUT (64-100px) - Full controls
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStandardLayout(TimelineTrack track) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + core buttons
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (track.isFolder) _buildFolderToggle(track),
              Expanded(child: _buildTrackName(track, fontSize: 12)),
              _CoreButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              _CoreButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              _CoreButton('R', track.armed, ReelForgeTheme.accentRed, widget.onArmToggle),
              const SizedBox(width: 18),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Row 2: Volume
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Expanded(
                  child: _GlassSlider(
                    value: track.volume,
                    max: 1.5,
                    color: ReelForgeTheme.accentGreen,
                    onChanged: widget.onVolumeChange,
                    onDoubleTap: () => widget.onVolumeChange?.call(1.0),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 28,
                  child: Text(
                    _volumeToDb(track.volume),
                    style: _monoStyle(9),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPANDED LAYOUT (100-140px) - Volume + Pan + Bus
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExpandedLayout(TimelineTrack track) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (track.isFolder) _buildFolderToggle(track),
              Expanded(child: _buildTrackName(track, fontSize: 12)),
              _CoreButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              _CoreButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              _CoreButton('R', track.armed, ReelForgeTheme.accentRed, widget.onArmToggle),
              const SizedBox(width: 18),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Row 2: Volume
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Text('Vol', style: _labelStyle()),
                const SizedBox(width: 4),
                Expanded(
                  child: _GlassSlider(
                    value: track.volume,
                    max: 1.5,
                    color: ReelForgeTheme.accentGreen,
                    onChanged: widget.onVolumeChange,
                    onDoubleTap: () => widget.onVolumeChange?.call(1.0),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  child: Text(_volumeToDb(track.volume), style: _monoStyle(9), textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: Pan + Bus
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Text('Pan', style: _labelStyle()),
                const SizedBox(width: 4),
                Expanded(
                  child: _GlassSlider(
                    value: (track.pan + 1) / 2,
                    color: ReelForgeTheme.accentCyan,
                    showCenter: true,
                    onChanged: (v) => widget.onPanChange?.call(v * 2 - 1),
                    onDoubleTap: () => widget.onPanChange?.call(0),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  child: Text(_panDisplay(track.pan), style: _monoStyle(9), textAlign: TextAlign.center),
                ),
                const SizedBox(width: 4),
                _BusChip(track.outputBus, onTap: _cycleBus),
              ],
            ),
          ),
        ),
        const Spacer(),
        // Row 4: Extra buttons
        SizedBox(
          height: 14,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TinyButton(Icons.auto_graph, track.automationExpanded, ReelForgeTheme.accentPurple, widget.onAutomationToggle, 'Auto'),
                _TinyButton(Icons.ac_unit, track.frozen, ReelForgeTheme.accentCyan, widget.onFreezeToggle, 'Freeze'),
                _TinyButton(Icons.lock_outline, track.locked, ReelForgeTheme.textSecondary, widget.onLockToggle, 'Lock'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // XL LAYOUT (140px+) - Full controls + stereo waveform
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildXLLayout(TimelineTrack track) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (track.isFolder) _buildFolderToggle(track),
              Expanded(child: _buildTrackName(track, fontSize: 12)),
              _CoreButton('M', track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              _CoreButton('S', track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              _CoreButton('R', track.armed, ReelForgeTheme.accentRed, widget.onArmToggle),
              const SizedBox(width: 18),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Row 2: Volume
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('Vol', style: _labelStyle())),
                Expanded(
                  child: _GlassSlider(
                    value: track.volume,
                    max: 1.5,
                    color: ReelForgeTheme.accentGreen,
                    onChanged: widget.onVolumeChange,
                    onDoubleTap: () => widget.onVolumeChange?.call(1.0),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(width: 32, child: Text(_volumeToDb(track.volume), style: _monoStyle(9), textAlign: TextAlign.right)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: Pan + Bus
        SizedBox(
          height: 16,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('Pan', style: _labelStyle())),
                Expanded(
                  child: _GlassSlider(
                    value: (track.pan + 1) / 2,
                    color: ReelForgeTheme.accentCyan,
                    showCenter: true,
                    onChanged: (v) => widget.onPanChange?.call(v * 2 - 1),
                    onDoubleTap: () => widget.onPanChange?.call(0),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(width: 24, child: Text(_panDisplay(track.pan), style: _monoStyle(9), textAlign: TextAlign.center)),
                const SizedBox(width: 4),
                _BusChip(track.outputBus, onTap: _cycleBus),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Stereo Waveform Preview
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, bottom: 2),
            child: _StereoWaveformPreview(
              waveformL: widget.waveformPreview,
              waveformR: widget.waveformPreviewR ?? widget.waveformPreview,
              color: track.color,
              muted: track.muted,
            ),
          ),
        ),
        // Row: Extra buttons
        SizedBox(
          height: 14,
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TinyButton(Icons.auto_graph, track.automationExpanded, ReelForgeTheme.accentPurple, widget.onAutomationToggle, 'Auto'),
                _TinyButton(Icons.ac_unit, track.frozen, ReelForgeTheme.accentCyan, widget.onFreezeToggle, 'Freeze'),
                _TinyButton(Icons.lock_outline, track.locked, ReelForgeTheme.textSecondary, widget.onLockToggle, 'Lock'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFolderToggle(TimelineTrack track) {
    return GestureDetector(
      onTap: widget.onFolderToggle,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(
          track.folderExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
          size: 14,
          color: ReelForgeTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildTrackName(TimelineTrack track, {required double fontSize}) {
    if (_isEditing) {
      return TextField(
        controller: _nameController,
        focusNode: _focusNode,
        style: TextStyle(
          color: ReelForgeTheme.textPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _submitName(),
      );
    }

    return GestureDetector(
      onDoubleTap: () {
        setState(() => _isEditing = true);
        _focusNode.requestFocus();
      },
      child: Text(
        track.name,
        style: TextStyle(
          color: track.muted ? ReelForgeTheme.textTertiary : ReelForgeTheme.textPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  TextStyle _labelStyle() => TextStyle(
    fontSize: 9,
    color: ReelForgeTheme.textTertiary,
    fontWeight: FontWeight.w500,
  );

  TextStyle _monoStyle(double size) => TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: size,
    color: ReelForgeTheme.textSecondary,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // RESIZE HANDLES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVerticalResizeHandle() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 6,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isResizingV = true),
          onVerticalDragUpdate: (d) {
            final newHeight = (widget.height + d.delta.dy).clamp(kMinTrackHeight, kMaxTrackHeight);
            widget.onHeightChange?.call(newHeight);
          },
          onVerticalDragEnd: (_) => setState(() => _isResizingV = false),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  _isResizingV ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5) : ReelForgeTheme.borderMedium.withValues(alpha: 0.3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalResizeHandle() {
    return Positioned(
      top: 0,
      bottom: 6,
      right: 0,
      width: 6,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragStart: (_) => setState(() => _isResizingH = true),
          onHorizontalDragUpdate: (d) {
            final newWidth = (widget.width + d.delta.dx).clamp(kMinHeaderWidth, kMaxHeaderWidth);
            widget.onWidthChange?.call(newWidth);
          },
          onHorizontalDragEnd: (_) => setState(() => _isResizingH = false),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  _isResizingH ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5) : ReelForgeTheme.borderMedium.withValues(alpha: 0.3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE OVERLAYS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFrozenOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ReelForgeTheme.accentCyan.withValues(alpha: 0.06),
                ReelForgeTheme.accentCyan.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.12),
        ),
      ),
    );
  }

  void _cycleBus() {
    final buses = OutputBus.values;
    final idx = buses.indexOf(widget.track.outputBus);
    widget.onBusChange?.call(buses[(idx + 1) % buses.length]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LAYOUT MODE ENUM
// ═══════════════════════════════════════════════════════════════════════════

enum _LayoutMode { mini, compact, standard, expanded, xl }

// ═══════════════════════════════════════════════════════════════════════════
// PILL BUTTON (compact mode)
// ═══════════════════════════════════════════════════════════════════════════

class _PillButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _PillButton(this.label, this.isActive, this.activeColor, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 16,
        height: 14,
        decoration: BoxDecoration(
          color: isActive ? activeColor : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? activeColor : ReelForgeTheme.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isActive ? Colors.black : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CORE BUTTON (M/S/R)
// ═══════════════════════════════════════════════════════════════════════════

class _CoreButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _CoreButton(this.label, this.isActive, this.activeColor, this.onTap);

  @override
  State<_CoreButton> createState() => _CoreButtonState();
}

class _CoreButtonState extends State<_CoreButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 18,
          height: 16,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            gradient: widget.isActive
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [widget.activeColor, widget.activeColor.withValues(alpha: 0.8)],
                  )
                : null,
            color: widget.isActive ? null : (_hover ? ReelForgeTheme.borderMedium : ReelForgeTheme.bgDeepest),
            borderRadius: BorderRadius.circular(3),
            boxShadow: widget.isActive
                ? [BoxShadow(color: widget.activeColor.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: -1)]
                : null,
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: widget.isActive ? Colors.black : ReelForgeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TINY BUTTON (icon based)
// ═══════════════════════════════════════════════════════════════════════════

class _TinyButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;
  final String tooltip;

  const _TinyButton(this.icon, this.isActive, this.activeColor, this.onTap, this.tooltip);

  @override
  State<_TinyButton> createState() => _TinyButtonState();
}

class _TinyButtonState extends State<_TinyButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 20,
            height: 14,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.activeColor.withValues(alpha: 0.2)
                  : (_hover ? ReelForgeTheme.borderSubtle : Colors.transparent),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              widget.icon,
              size: 10,
              color: widget.isActive ? widget.activeColor : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUS CHIP
// ═══════════════════════════════════════════════════════════════════════════

class _BusChip extends StatelessWidget {
  final OutputBus bus;
  final VoidCallback? onTap;

  const _BusChip(this.bus, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = getBusInfo(bus);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: info.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: info.color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text(
          info.shortName,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: info.color,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS SLIDER
// ═══════════════════════════════════════════════════════════════════════════

class _GlassSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final Color color;
  final String? label;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onDoubleTap;
  final bool showCenter;

  const _GlassSlider({
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.color,
    this.label,
    this.onChanged,
    this.onDoubleTap,
    this.showCenter = false,
  });

  @override
  State<_GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<_GlassSlider> {
  bool _dragging = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) {
          if (widget.onChanged == null) return;
          final box = context.findRenderObject() as RenderBox;
          final pos = box.globalToLocal(d.globalPosition);
          final ratio = (pos.dx / box.size.width).clamp(0.0, 1.0);
          widget.onChanged!(widget.min + ratio * (widget.max - widget.min));
        },
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: _hover || _dragging ? widget.color.withValues(alpha: 0.3) : ReelForgeTheme.borderSubtle,
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2.5),
            child: CustomPaint(
              painter: _GlassSliderPainter(
                value: widget.value,
                min: widget.min,
                max: widget.max,
                color: widget.color,
                isDragging: _dragging,
                showCenter: widget.showCenter,
              ),
              child: widget.label != null
                  ? Center(
                      child: Text(
                        widget.label!,
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 9,
                          color: ReelForgeTheme.textPrimary.withValues(alpha: 0.8),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSliderPainter extends CustomPainter {
  final double value, min, max;
  final Color color;
  final bool isDragging, showCenter;

  _GlassSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.isDragging,
    required this.showCenter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final fillW = size.width * ratio;

    // Glass fill gradient
    if (fillW > 0) {
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isDragging ? 0.5 : 0.35),
          color.withValues(alpha: isDragging ? 0.35 : 0.2),
        ],
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillW, size.height),
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, fillW, size.height)),
      );
    }

    // Center line for pan
    if (showCenter) {
      final centerPaint = Paint()
        ..color = ReelForgeTheme.borderMedium.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), centerPaint);
    }

    // Thumb indicator
    if (fillW > 2) {
      final thumbGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0.7)],
      );
      canvas.drawRect(
        Rect.fromLTWH(fillW - 2, 0, 2, size.height),
        Paint()..shader = thumbGradient.createShader(Rect.fromLTWH(fillW - 2, 0, 2, size.height)),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassSliderPainter old) => old.value != value || old.isDragging != isDragging;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO METER
// ═══════════════════════════════════════════════════════════════════════════

class _StereoMeter extends StatelessWidget {
  final double levelL, levelR;
  final double peakL, peakR;
  final bool compact;

  const _StereoMeter({
    required this.levelL,
    required this.levelR,
    required this.peakL,
    required this.peakR,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StereoMeterPainter(
        levelL: levelL,
        levelR: levelR,
        peakL: peakL,
        peakR: peakR,
        compact: compact,
      ),
    );
  }
}

class _StereoMeterPainter extends CustomPainter {
  final double levelL, levelR, peakL, peakR;
  final bool compact;

  _StereoMeterPainter({
    required this.levelL,
    required this.levelR,
    required this.peakL,
    required this.peakR,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = ReelForgeTheme.bgDeepest;

    if (compact) {
      // Single combined meter
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(1)),
        bgPaint,
      );
      _drawMeterBar(canvas, Rect.fromLTWH(0, 0, size.width, size.height), (levelL + levelR) / 2, (peakL + peakR) / 2);
    } else {
      // Stereo meters
      final meterW = (size.width - 2) / 2;

      // Left channel
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, meterW, size.height), const Radius.circular(1)),
        bgPaint,
      );
      _drawMeterBar(canvas, Rect.fromLTWH(0, 0, meterW, size.height), levelL, peakL);

      // Right channel
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(meterW + 2, 0, meterW, size.height), const Radius.circular(1)),
        bgPaint,
      );
      _drawMeterBar(canvas, Rect.fromLTWH(meterW + 2, 0, meterW, size.height), levelR, peakR);
    }
  }

  void _drawMeterBar(Canvas canvas, Rect rect, double level, double peak) {
    final h = rect.height * level.clamp(0.0, 1.0);

    if (h > 0) {
      // Gradient from green to yellow to red
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: const [
          Color(0xFF40FF90), // Green
          Color(0xFF40FF90), // Green
          Color(0xFFFFFF40), // Yellow
          Color(0xFFFF6040), // Orange
          Color(0xFFFF4040), // Red
        ],
        stops: const [0.0, 0.6, 0.75, 0.9, 1.0],
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.bottom - h, rect.width, h),
          const Radius.circular(1),
        ),
        Paint()..shader = gradient.createShader(rect),
      );
    }

    // Peak indicator
    if (peak > 0.01) {
      final peakY = rect.bottom - rect.height * peak.clamp(0.0, 1.0);
      final peakColor = peak > 0.9 ? const Color(0xFFFF4040) : Colors.white;
      canvas.drawLine(
        Offset(rect.left, peakY),
        Offset(rect.right, peakY),
        Paint()..color = peakColor..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_StereoMeterPainter old) =>
      old.levelL != levelL || old.levelR != levelR || old.peakL != peakL || old.peakR != peakR;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WAVEFORM PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

class _StereoWaveformPreview extends StatelessWidget {
  final Float32List? waveformL;
  final Float32List? waveformR;
  final Color color;
  final bool muted;

  const _StereoWaveformPreview({
    this.waveformL,
    this.waveformR,
    required this.color,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3), width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.5),
        child: CustomPaint(
          painter: _StereoWaveformPainter(
            waveformL: waveformL,
            waveformR: waveformR,
            color: muted ? color.withValues(alpha: 0.3) : color,
          ),
        ),
      ),
    );
  }
}

class _StereoWaveformPainter extends CustomPainter {
  final Float32List? waveformL;
  final Float32List? waveformR;
  final Color color;

  _StereoWaveformPainter({
    this.waveformL,
    this.waveformR,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasData = waveformL != null && waveformL!.isNotEmpty;
    final midY = size.height / 2;

    // Center line
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.3),
    );

    if (!hasData) {
      // Placeholder text
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'No Audio',
          style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2));
      return;
    }

    final samplesPerPixel = waveformL!.length / size.width;

    // Draw left channel (top half, brighter)
    _drawChannel(canvas, size, waveformL!, 0, midY, color.withValues(alpha: 0.7), samplesPerPixel, true);

    // Draw right channel (bottom half, slightly dimmer)
    final rightData = waveformR ?? waveformL!;
    _drawChannel(canvas, size, rightData, midY, size.height, color.withValues(alpha: 0.5), samplesPerPixel, false);
  }

  void _drawChannel(Canvas canvas, Size size, Float32List data, double top, double bottom, Color channelColor, double samplesPerPixel, bool isTop) {
    final height = bottom - top;
    final midY = top + height / 2;

    final path = Path();
    path.moveTo(0, midY);

    for (int x = 0; x < size.width.toInt(); x++) {
      final sampleIdx = (x * samplesPerPixel).toInt().clamp(0, data.length - 1);
      final sample = data[sampleIdx].abs().clamp(0.0, 1.0);
      final amplitude = sample * (height / 2) * 0.9;

      if (isTop) {
        path.lineTo(x.toDouble(), midY - amplitude);
      } else {
        path.lineTo(x.toDouble(), midY - amplitude);
      }
    }

    for (int x = size.width.toInt() - 1; x >= 0; x--) {
      final sampleIdx = (x * samplesPerPixel).toInt().clamp(0, data.length - 1);
      final sample = data[sampleIdx].abs().clamp(0.0, 1.0);
      final amplitude = sample * (height / 2) * 0.9;

      if (isTop) {
        path.lineTo(x.toDouble(), midY + amplitude);
      } else {
        path.lineTo(x.toDouble(), midY + amplitude);
      }
    }

    path.close();

    // Fill with gradient
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [channelColor, channelColor.withValues(alpha: channelColor.a * 0.5)],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient.createShader(Rect.fromLTRB(0, top, size.width, bottom))
        ..style = PaintingStyle.fill,
    );

    // Outline
    canvas.drawPath(
      path,
      Paint()
        ..color = channelColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_StereoWaveformPainter old) => old.waveformL != waveformL || old.waveformR != waveformR;
}

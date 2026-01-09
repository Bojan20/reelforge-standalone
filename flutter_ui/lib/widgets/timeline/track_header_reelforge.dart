/// ReelForge Track Header Widget
///
/// Custom ReelForge-style track header with:
/// - Clean, uncluttered design
/// - Dynamic height-based layouts (Mini → Stereo)
/// - Stereo waveform display when expanded
/// - Hide track support
/// - Send quick-access in expanded mode
/// - Smooth animations and transitions
///
/// Layout Modes:
/// - Mini (28-40px): Name + M/S only
/// - Compact (40-56px): Name + M/S/R + Input monitor
/// - Standard (56-80px): + Volume slider
/// - Expanded (80-120px): + Pan + Bus routing
/// - Full (120-160px): + Sends + Hide/Freeze/Lock
/// - Stereo (160px+): + Stereo waveform preview

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS - ReelForge Style
// ═══════════════════════════════════════════════════════════════════════════

const double kRFMinHeight = 28;
const double kRFDefaultHeight = 56;
const double kRFMaxHeight = 220;
const double kRFHeaderWidth = 200;

// Layout thresholds
const double kRFMiniMax = 40;
const double kRFCompactMax = 56;
const double kRFStandardMax = 80;
const double kRFExpandedMax = 120;
const double kRFFullMax = 160;
// Above 160 = Stereo mode

enum _RFLayoutMode { mini, compact, standard, expanded, full, stereo }

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class TrackHeaderReelForge extends StatefulWidget {
  final TimelineTrack track;
  final double width;
  final double height;
  final int trackNumber;
  final bool isSelected;
  final bool isPlaying;

  // Metering
  final double signalLevel;
  final double signalLevelR;

  // Waveform for stereo mode
  final Float32List? waveformL;
  final Float32List? waveformR;

  // Send levels (for quick access)
  final List<double> sendLevels;

  // Display options
  final bool showTrackNumber;

  // Callbacks
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onMonitorToggle;
  final VoidCallback? onHideToggle;
  final VoidCallback? onFreezeToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onAutomationToggle;
  final VoidCallback? onFolderToggle;
  final VoidCallback? onClick;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final ValueChanged<OutputBus>? onBusChange;
  final ValueChanged<String>? onRename;
  final ValueChanged<Color>? onColorChange;
  final void Function(int sendIndex, double level)? onSendLevelChange;
  final void Function(Offset position)? onContextMenu;
  final ValueChanged<double>? onHeightChange;

  const TrackHeaderReelForge({
    super.key,
    required this.track,
    this.width = kRFHeaderWidth,
    this.height = kRFDefaultHeight,
    this.trackNumber = 1,
    this.isSelected = false,
    this.isPlaying = false,
    this.signalLevel = 0.0,
    this.signalLevelR = 0.0,
    this.waveformL,
    this.waveformR,
    this.sendLevels = const [0.0, 0.0, 0.0, 0.0],
    this.showTrackNumber = true,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onMonitorToggle,
    this.onHideToggle,
    this.onFreezeToggle,
    this.onLockToggle,
    this.onAutomationToggle,
    this.onFolderToggle,
    this.onClick,
    this.onVolumeChange,
    this.onPanChange,
    this.onBusChange,
    this.onRename,
    this.onColorChange,
    this.onSendLevelChange,
    this.onContextMenu,
    this.onHeightChange,
  });

  @override
  State<TrackHeaderReelForge> createState() => _TrackHeaderReelForgeState();
}

class _TrackHeaderReelForgeState extends State<TrackHeaderReelForge>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isResizing = false;
  bool _isEditingName = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Peak hold
  double _peakL = 0.0;
  double _peakR = 0.0;
  int _peakHoldL = 0;
  int _peakHoldR = 0;

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
  void didUpdateWidget(TrackHeaderReelForge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditingName) {
      _nameController.text = widget.track.name;
    }
    _updatePeakHold();
  }

  void _updatePeakHold() {
    if (widget.signalLevel > _peakL) {
      _peakL = widget.signalLevel;
      _peakHoldL = 45;
    } else if (_peakHoldL > 0) {
      _peakHoldL--;
    } else {
      _peakL = math.max(0, _peakL - 0.015);
    }

    if (widget.signalLevelR > _peakR) {
      _peakR = widget.signalLevelR;
      _peakHoldR = 45;
    } else if (_peakHoldR > 0) {
      _peakHoldR--;
    } else {
      _peakR = math.max(0, _peakR - 0.015);
    }
  }

  _RFLayoutMode get _layoutMode {
    if (widget.height < kRFMiniMax) return _RFLayoutMode.mini;
    if (widget.height < kRFCompactMax) return _RFLayoutMode.compact;
    if (widget.height < kRFStandardMax) return _RFLayoutMode.standard;
    if (widget.height < kRFExpandedMax) return _RFLayoutMode.expanded;
    if (widget.height < kRFFullMax) return _RFLayoutMode.full;
    return _RFLayoutMode.stereo;
  }

  bool get _isStereoMode => _layoutMode == _RFLayoutMode.stereo;

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: _buildGradient(),
            border: Border(
              left: BorderSide(
                color: track.color,
                width: widget.isSelected ? 4 : 3,
              ),
              bottom: BorderSide(
                color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
                child: _buildContent(),
              ),

              // Right-side meter
              Positioned(
                top: 3,
                bottom: 3,
                right: 3,
                width: _isStereoMode ? 12 : 8,
                child: _RFMeter(
                  levelL: widget.signalLevel,
                  levelR: widget.signalLevelR,
                  peakL: _peakL,
                  peakR: _peakR,
                  stereo: _isStereoMode,
                ),
              ),

              // Resize handle (bottom edge)
              if (_isHovered || _isResizing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: _buildResizeHandle(),
                ),

              // Frozen/Locked overlay
              if (track.frozen) _buildFrozenOverlay(),
              if (track.locked) _buildLockedOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _buildGradient() {
    final track = widget.track;
    Color top, bottom;

    if (widget.isSelected) {
      top = track.color.withValues(alpha: 0.15);
      bottom = track.color.withValues(alpha: 0.08);
    } else if (track.armed) {
      top = ReelForgeTheme.accentRed.withValues(alpha: 0.1);
      bottom = ReelForgeTheme.accentRed.withValues(alpha: 0.05);
    } else if (_isHovered) {
      top = ReelForgeTheme.bgSurface;
      bottom = ReelForgeTheme.bgMid;
    } else {
      top = ReelForgeTheme.bgMid;
      bottom = ReelForgeTheme.bgDeep;
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    );
  }

  Widget _buildContent() {
    switch (_layoutMode) {
      case _RFLayoutMode.mini:
        return _buildMiniLayout();
      case _RFLayoutMode.compact:
        return _buildCompactLayout();
      case _RFLayoutMode.standard:
        return _buildStandardLayout();
      case _RFLayoutMode.expanded:
        return _buildExpandedLayout();
      case _RFLayoutMode.full:
        return _buildFullLayout();
      case _RFLayoutMode.stereo:
        return _buildStereoLayout();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MINI LAYOUT (28-40px) - Name + M/S only
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMiniLayout() {
    return Row(
      children: [
        if (widget.showTrackNumber) _buildTrackNumber(compact: true),
        Expanded(child: _buildName(fontSize: 10)),
        _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle, size: 16),
        const SizedBox(width: 2),
        _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle, size: 16),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPACT LAYOUT (40-56px) - Name + M/S/R + I
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactLayout() {
    return Row(
      children: [
        if (widget.showTrackNumber) _buildTrackNumber(),
        if (widget.track.isFolder) _buildFolderToggle(),
        Expanded(child: _buildName(fontSize: 11)),
        const SizedBox(width: 4),
        _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
        const SizedBox(width: 2),
        _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
        const SizedBox(width: 2),
        _RFRecordButton(widget.track.armed, widget.isPlaying, widget.onArmToggle),
        const SizedBox(width: 2),
        _RFButton('I', widget.track.inputMonitor, ReelForgeTheme.accentGreen, widget.onMonitorToggle),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDARD LAYOUT (56-80px) - + Volume slider
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStandardLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 20,
          child: Row(
            children: [
              if (widget.showTrackNumber) _buildTrackNumber(),
              if (widget.track.isFolder) _buildFolderToggle(),
              Expanded(child: _buildName(fontSize: 11)),
              _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              const SizedBox(width: 2),
              _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              const SizedBox(width: 2),
              _RFRecordButton(widget.track.armed, widget.isPlaying, widget.onArmToggle),
              const SizedBox(width: 2),
              _RFButton('I', widget.track.inputMonitor, ReelForgeTheme.accentGreen, widget.onMonitorToggle),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Volume
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: 2),
              _RFLabel('Vol'),
              const SizedBox(width: 4),
              Expanded(
                child: _RFSlider(
                  value: widget.track.volume,
                  max: 1.5,
                  color: ReelForgeTheme.accentGreen,
                  onChanged: widget.onVolumeChange,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 30,
                child: Text(
                  _dbDisplay(widget.track.volume),
                  style: _monoStyle(8),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPANDED LAYOUT (80-120px) - + Pan + Bus
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExpandedLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 20,
          child: Row(
            children: [
              if (widget.showTrackNumber) _buildTrackNumber(),
              if (widget.track.isFolder) _buildFolderToggle(),
              Expanded(child: _buildName(fontSize: 11)),
              _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              const SizedBox(width: 2),
              _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              const SizedBox(width: 2),
              _RFRecordButton(widget.track.armed, widget.isPlaying, widget.onArmToggle),
              const SizedBox(width: 2),
              _RFButton('I', widget.track.inputMonitor, ReelForgeTheme.accentGreen, widget.onMonitorToggle),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Row 2: Volume
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Vol'),
              const SizedBox(width: 4),
              Expanded(
                child: _RFSlider(
                  value: widget.track.volume,
                  max: 1.5,
                  color: ReelForgeTheme.accentGreen,
                  onChanged: widget.onVolumeChange,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(width: 30, child: Text(_dbDisplay(widget.track.volume), style: _monoStyle(8), textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: Pan + Bus
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Pan'),
              const SizedBox(width: 4),
              Expanded(
                child: _RFSlider(
                  value: (widget.track.pan + 1) / 2,
                  color: ReelForgeTheme.accentCyan,
                  showCenter: true,
                  onChanged: (v) => widget.onPanChange?.call(v * 2 - 1),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(width: 20, child: Text(_panDisplay(widget.track.pan), style: _monoStyle(8), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              _RFBusChip(widget.track.outputBus, _cycleBus),
            ],
          ),
        ),
        const Spacer(),
        // Row 4: Secondary controls
        SizedBox(
          height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _RFTinyIcon(Icons.visibility_off, widget.track.hidden, ReelForgeTheme.textTertiary, widget.onHideToggle, 'Hide'),
              _RFTinyIcon(Icons.auto_graph, widget.track.automationExpanded, ReelForgeTheme.accentPurple, widget.onAutomationToggle, 'Auto'),
              _RFTinyIcon(Icons.ac_unit, widget.track.frozen, ReelForgeTheme.accentCyan, widget.onFreezeToggle, 'Freeze'),
              _RFTinyIcon(Icons.lock_outline, widget.track.locked, ReelForgeTheme.textSecondary, widget.onLockToggle, 'Lock'),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FULL LAYOUT (120-160px) - + Sends
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFullLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (widget.showTrackNumber) _buildTrackNumber(),
              if (widget.track.isFolder) _buildFolderToggle(),
              Expanded(child: _buildName(fontSize: 11)),
              _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              const SizedBox(width: 2),
              _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              const SizedBox(width: 2),
              _RFRecordButton(widget.track.armed, widget.isPlaying, widget.onArmToggle),
              const SizedBox(width: 2),
              _RFButton('I', widget.track.inputMonitor, ReelForgeTheme.accentGreen, widget.onMonitorToggle),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Volume
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Vol'),
              const SizedBox(width: 4),
              Expanded(child: _RFSlider(value: widget.track.volume, max: 1.5, color: ReelForgeTheme.accentGreen, onChanged: widget.onVolumeChange)),
              const SizedBox(width: 4),
              SizedBox(width: 30, child: Text(_dbDisplay(widget.track.volume), style: _monoStyle(8), textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        // Row 3: Pan + Bus
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Pan'),
              const SizedBox(width: 4),
              Expanded(child: _RFSlider(value: (widget.track.pan + 1) / 2, color: ReelForgeTheme.accentCyan, showCenter: true, onChanged: (v) => widget.onPanChange?.call(v * 2 - 1))),
              const SizedBox(width: 4),
              SizedBox(width: 20, child: Text(_panDisplay(widget.track.pan), style: _monoStyle(8), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              _RFBusChip(widget.track.outputBus, _cycleBus),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 4: Sends (mini)
        SizedBox(
          height: 20,
          child: Row(
            children: [
              _RFLabel('Snd'),
              const SizedBox(width: 4),
              ...List.generate(4, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 2 : 0),
                  child: _RFMiniSend(
                    index: i,
                    level: i < widget.sendLevels.length ? widget.sendLevels[i] : 0.0,
                    onChanged: (v) => widget.onSendLevelChange?.call(i, v),
                  ),
                ),
              )),
            ],
          ),
        ),
        const Spacer(),
        // Row 5: Secondary controls
        SizedBox(
          height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _RFTinyIcon(Icons.visibility_off, widget.track.hidden, ReelForgeTheme.textTertiary, widget.onHideToggle, 'Hide'),
              _RFTinyIcon(Icons.auto_graph, widget.track.automationExpanded, ReelForgeTheme.accentPurple, widget.onAutomationToggle, 'Auto'),
              _RFTinyIcon(Icons.ac_unit, widget.track.frozen, ReelForgeTheme.accentCyan, widget.onFreezeToggle, 'Freeze'),
              _RFTinyIcon(Icons.lock_outline, widget.track.locked, ReelForgeTheme.textSecondary, widget.onLockToggle, 'Lock'),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEREO LAYOUT (160px+) - + Stereo waveform
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStereoLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + buttons
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (widget.showTrackNumber) _buildTrackNumber(),
              if (widget.track.isFolder) _buildFolderToggle(),
              Expanded(child: _buildName(fontSize: 11)),
              _RFButton('M', widget.track.muted, ReelForgeTheme.accentOrange, widget.onMuteToggle),
              const SizedBox(width: 2),
              _RFButton('S', widget.track.soloed, ReelForgeTheme.accentYellow, widget.onSoloToggle),
              const SizedBox(width: 2),
              _RFRecordButton(widget.track.armed, widget.isPlaying, widget.onArmToggle),
              const SizedBox(width: 2),
              _RFButton('I', widget.track.inputMonitor, ReelForgeTheme.accentGreen, widget.onMonitorToggle),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 2: Volume
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Vol'),
              const SizedBox(width: 4),
              Expanded(child: _RFSlider(value: widget.track.volume, max: 1.5, color: ReelForgeTheme.accentGreen, onChanged: widget.onVolumeChange)),
              const SizedBox(width: 4),
              SizedBox(width: 30, child: Text(_dbDisplay(widget.track.volume), style: _monoStyle(8), textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        // Row 3: Pan + Bus
        SizedBox(
          height: 14,
          child: Row(
            children: [
              _RFLabel('Pan'),
              const SizedBox(width: 4),
              Expanded(child: _RFSlider(value: (widget.track.pan + 1) / 2, color: ReelForgeTheme.accentCyan, showCenter: true, onChanged: (v) => widget.onPanChange?.call(v * 2 - 1))),
              const SizedBox(width: 4),
              SizedBox(width: 20, child: Text(_panDisplay(widget.track.pan), style: _monoStyle(8), textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              _RFBusChip(widget.track.outputBus, _cycleBus),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 4: Sends
        SizedBox(
          height: 18,
          child: Row(
            children: [
              _RFLabel('Snd'),
              const SizedBox(width: 4),
              ...List.generate(4, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 2 : 0),
                  child: _RFMiniSend(
                    index: i,
                    level: i < widget.sendLevels.length ? widget.sendLevels[i] : 0.0,
                    onChanged: (v) => widget.onSendLevelChange?.call(i, v),
                  ),
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Row 5: Stereo waveform preview
        Expanded(
          child: _RFStereoWaveform(
            waveformL: widget.waveformL,
            waveformR: widget.waveformR,
            color: widget.track.color,
          ),
        ),
        const SizedBox(height: 4),
        // Row 6: Secondary controls
        SizedBox(
          height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _RFTinyIcon(Icons.visibility_off, widget.track.hidden, ReelForgeTheme.textTertiary, widget.onHideToggle, 'Hide'),
              _RFTinyIcon(Icons.auto_graph, widget.track.automationExpanded, ReelForgeTheme.accentPurple, widget.onAutomationToggle, 'Auto'),
              _RFTinyIcon(Icons.ac_unit, widget.track.frozen, ReelForgeTheme.accentCyan, widget.onFreezeToggle, 'Freeze'),
              _RFTinyIcon(Icons.lock_outline, widget.track.locked, ReelForgeTheme.textSecondary, widget.onLockToggle, 'Lock'),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrackNumber({bool compact = false}) {
    return Container(
      width: compact ? 16 : 20,
      margin: const EdgeInsets.only(right: 4),
      alignment: Alignment.center,
      child: Text(
        '${widget.trackNumber}',
        style: TextStyle(
          color: ReelForgeTheme.textTertiary,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildName({required double fontSize}) {
    if (_isEditingName) {
      return TextField(
        controller: _nameController,
        focusNode: _focusNode,
        autofocus: true,
        style: TextStyle(
          color: ReelForgeTheme.textPrimary,
          fontSize: fontSize,
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
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
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

  Widget _buildFolderToggle() {
    return GestureDetector(
      onTap: widget.onFolderToggle,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(
          widget.track.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
          size: 14,
          color: ReelForgeTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isResizing = true),
        onVerticalDragEnd: (_) => setState(() => _isResizing = false),
        onVerticalDragUpdate: (d) {
          final newHeight = (widget.height + d.delta.dy).clamp(kRFMinHeight, kRFMaxHeight);
          widget.onHeightChange?.call(newHeight);
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                widget.track.color.withValues(alpha: _isResizing ? 0.5 : 0.3),
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: 30,
              height: 2,
              decoration: BoxDecoration(
                color: widget.track.color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrozenOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: ReelForgeTheme.accentCyan.withValues(alpha: 0.08),
        ),
        child: Center(
          child: Icon(Icons.ac_unit, size: 20, color: ReelForgeTheme.accentCyan.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  Widget _buildLockedOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
        ),
        child: Center(
          child: Icon(Icons.lock, size: 16, color: ReelForgeTheme.textTertiary.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  void _cycleBus() {
    const buses = OutputBus.values;
    final currentIndex = buses.indexOf(widget.track.outputBus);
    final nextBus = buses[(currentIndex + 1) % buses.length];
    widget.onBusChange?.call(nextBus);
  }

  String _dbDisplay(double linear) {
    if (linear <= 0) return '-∞';
    final db = 20 * (math.log(linear) / math.ln10);
    return db <= -60 ? '-∞' : '${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)}';
  }

  String _panDisplay(double pan) {
    if (pan.abs() < 0.01) return 'C';
    return pan < 0 ? 'L${(pan.abs() * 100).round()}' : 'R${(pan * 100).round()}';
  }

  TextStyle _monoStyle(double size) => TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: size,
    color: ReelForgeTheme.textSecondary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// UI COMPONENTS - ReelForge Style
// ═══════════════════════════════════════════════════════════════════════════

class _RFLabel extends StatelessWidget {
  final String text;
  const _RFLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8,
          color: ReelForgeTheme.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _RFButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;
  final double size;

  const _RFButton(this.label, this.active, this.activeColor, this.onTap, {this.size = 18});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.9) : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.borderSubtle,
            width: 1,
          ),
          boxShadow: active ? [
            BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 4),
          ] : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : ReelForgeTheme.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RFRecordButton extends StatelessWidget {
  final bool armed;
  final bool isPlaying;
  final VoidCallback? onTap;

  const _RFRecordButton(this.armed, this.isPlaying, this.onTap);

  @override
  Widget build(BuildContext context) {
    final shouldPulse = armed && isPlaying;

    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.7, end: shouldPulse ? 1.0 : 0.7),
        duration: Duration(milliseconds: shouldPulse ? 600 : 150),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: armed
                  ? ReelForgeTheme.accentRed.withValues(alpha: value)
                  : ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: armed ? ReelForgeTheme.accentRed : ReelForgeTheme.borderSubtle,
                width: 1,
              ),
              boxShadow: armed ? [
                BoxShadow(
                  color: ReelForgeTheme.accentRed.withValues(alpha: value * 0.4),
                  blurRadius: 6,
                ),
              ] : null,
            ),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: armed ? Colors.white : ReelForgeTheme.textTertiary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RFTinyIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;
  final String tooltip;

  const _RFTinyIcon(this.icon, this.active, this.activeColor, this.onTap, this.tooltip);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 18,
          height: 14,
          margin: const EdgeInsets.only(left: 2),
          child: Icon(
            icon,
            size: 12,
            color: active ? activeColor : ReelForgeTheme.textTertiary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _RFSlider extends StatelessWidget {
  final double value;
  final double max;
  final Color color;
  final bool showCenter;
  final ValueChanged<double>? onChanged;

  const _RFSlider({
    required this.value,
    this.max = 1.0,
    required this.color,
    this.showCenter = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final normalized = (value / max).clamp(0.0, 1.0);

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            if (onChanged != null) {
              final newValue = ((d.localPosition.dx / width) * max).clamp(0.0, max);
              onChanged!(newValue);
            }
          },
          onDoubleTap: () => onChanged?.call(showCenter ? 0.5 * max : 1.0),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.5)),
            ),
            child: Stack(
              children: [
                // Fill
                FractionallySizedBox(
                  widthFactor: normalized,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.6), color],
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // Center line for pan
                if (showCenter)
                  Positioned(
                    left: width / 2 - 0.5,
                    top: 2,
                    bottom: 2,
                    child: Container(width: 1, color: ReelForgeTheme.textTertiary.withValues(alpha: 0.3)),
                  ),
                // Thumb
                Positioned(
                  left: (normalized * width - 4).clamp(0.0, width - 8),
                  top: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 3)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RFBusChip extends StatelessWidget {
  final OutputBus bus;
  final VoidCallback onTap;

  const _RFBusChip(this.bus, this.onTap);

  static const _busColors = {
    OutputBus.master: Color(0xFFFFD700),
    OutputBus.music: Color(0xFF9B59B6),
    OutputBus.sfx: Color(0xFF3498DB),
    OutputBus.ambience: Color(0xFF27AE60),
    OutputBus.voice: Color(0xFFE67E22),
  };

  @override
  Widget build(BuildContext context) {
    final color = _busColors[bus] ?? ReelForgeTheme.textSecondary;
    final name = bus.name.substring(0, 1).toUpperCase() + bus.name.substring(1);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          name.length > 4 ? name.substring(0, 4) : name,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RFMiniSend extends StatelessWidget {
  final int index;
  final double level;
  final ValueChanged<double>? onChanged;

  const _RFMiniSend({required this.index, required this.level, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (onChanged != null) {
          final newLevel = (level - d.delta.dy * 0.01).clamp(0.0, 1.0);
          onChanged!(newLevel);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
        child: Stack(
          children: [
            // Level fill
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: level * 18,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      ReelForgeTheme.accentPurple.withValues(alpha: 0.8),
                      ReelForgeTheme.accentPurple.withValues(alpha: 0.4),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Label
            Center(
              child: Text(
                'S${index + 1}',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: level > 0.3 ? Colors.white : ReelForgeTheme.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RFMeter extends StatelessWidget {
  final double levelL;
  final double levelR;
  final double peakL;
  final double peakR;
  final bool stereo;

  const _RFMeter({
    required this.levelL,
    required this.levelR,
    required this.peakL,
    required this.peakR,
    this.stereo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SingleMeter(level: levelL, peak: peakL)),
        if (stereo) ...[
          const SizedBox(width: 1),
          Expanded(child: _SingleMeter(level: levelR, peak: peakR)),
        ],
      ],
    );
  }
}

class _SingleMeter extends StatelessWidget {
  final double level;
  final double peak;

  const _SingleMeter({required this.level, required this.peak});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          // Level fill
          Align(
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
                      Color(0xFF40FF90),
                      Color(0xFFFFFF40),
                      Color(0xFFFF4040),
                    ],
                    stops: const [0.0, 0.6, 0.85, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Peak hold
          if (peak > 0.01)
            Positioned(
              left: 0,
              right: 0,
              bottom: (peak.clamp(0.0, 1.0) * (context.size?.height ?? 50)) - 1,
              height: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: peak > 0.9 ? ReelForgeTheme.accentRed : ReelForgeTheme.textPrimary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RFStereoWaveform extends StatelessWidget {
  final Float32List? waveformL;
  final Float32List? waveformR;
  final Color color;

  const _RFStereoWaveform({this.waveformL, this.waveformR, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(
          children: [
            // Left channel (top half, inverted)
            Expanded(
              child: CustomPaint(
                painter: _WaveformPainter(
                  waveform: waveformL,
                  color: color.withValues(alpha: 0.7),
                  inverted: true,
                ),
                size: Size.infinite,
              ),
            ),
            // Divider
            Container(height: 1, color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)),
            // Right channel (bottom half)
            Expanded(
              child: CustomPaint(
                painter: _WaveformPainter(
                  waveform: waveformR ?? waveformL,
                  color: color.withValues(alpha: 0.5),
                  inverted: false,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List? waveform;
  final Color color;
  final bool inverted;

  _WaveformPainter({this.waveform, required this.color, this.inverted = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform == null || waveform!.isEmpty) {
      // Draw placeholder line
      final paint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      final y = inverted ? size.height : 0;
      canvas.drawLine(Offset(0, y.toDouble()), Offset(size.width, y.toDouble()), paint);
      return;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final samples = waveform!;
    final samplesPerPixel = samples.length / size.width;

    if (inverted) {
      path.moveTo(0, size.height);
      for (var x = 0; x < size.width; x++) {
        final sampleIndex = (x * samplesPerPixel).floor().clamp(0, samples.length - 1);
        final amplitude = samples[sampleIndex].abs().clamp(0.0, 1.0);
        final y = size.height - (amplitude * size.height);
        path.lineTo(x.toDouble(), y);
      }
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      for (var x = 0; x < size.width; x++) {
        final sampleIndex = (x * samplesPerPixel).floor().clamp(0, samples.length - 1);
        final amplitude = samples[sampleIndex].abs().clamp(0.0, 1.0);
        final y = amplitude * size.height;
        path.lineTo(x.toDouble(), y);
      }
      path.lineTo(size.width, 0);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform || color != oldDelegate.color;
}

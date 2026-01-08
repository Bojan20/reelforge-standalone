/// Professional Track Header Widget
///
/// Hybrid Logic Pro + Cubase style track header with:
/// - Track icon + name (Logic Pro style)
/// - Inline volume meter (Cubase style)
/// - M/S/R buttons with hover states
/// - Volume/Pan sliders with precise readouts
/// - Bus routing with color coding
/// - Settings menu for inserts/sends
/// - Expandable height modes
/// - Drag & drop file zone

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

enum TrackHeaderSize {
  compact(56),  // 3 rows
  medium(80),   // + sends/inserts
  large(120);   // + waveform overview

  final double height;
  const TrackHeaderSize(this.height);
}

class TrackHeaderPro extends StatefulWidget {
  final TimelineTrack track;
  final TrackHeaderSize size;
  final double width;  // Width from timeline (resizable)
  final double signalLevel;  // 0.0 - 1.0 for metering
  final bool isEmpty;  // Show drop zone if true

  // Callbacks
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
  final VoidCallback? onSettingsMenu;
  final VoidCallback? onFileDrop;
  /// Toggle automation lanes visibility
  final VoidCallback? onAutomationToggle;
  /// Toggle folder expanded state (only for folder tracks)
  final VoidCallback? onFolderToggle;

  const TrackHeaderPro({
    super.key,
    required this.track,
    this.size = TrackHeaderSize.compact,
    this.width = 180,
    this.signalLevel = 0.0,
    this.isEmpty = false,
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
    this.onSettingsMenu,
    this.onFileDrop,
    this.onAutomationToggle,
    this.onFolderToggle,
  });

  @override
  State<TrackHeaderPro> createState() => _TrackHeaderProState();
}

class _TrackHeaderProState extends State<TrackHeaderPro> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _showSettings = false;
  bool _isEditing = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;
  late AnimationController _meterAnimController;
  double _peakHold = 0.0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();
    _meterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _meterAnimController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackHeaderPro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && !_isEditing) {
      _nameController.text = widget.track.name;
    }
    // Update peak hold
    if (widget.signalLevel > _peakHold) {
      _peakHold = widget.signalLevel;
      _meterAnimController.forward(from: 0).then((_) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _peakHold = 0);
        });
      });
    }
  }

  String _volumeToDb(double linear) {
    if (linear <= 0) return '-∞';
    final db = 20 * _log10(linear);
    return db <= -60 ? '-∞' : '${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)}';
  }

  String _panDisplay(double pan) {
    if (pan == 0) return 'C';
    return pan < 0
        ? 'L${(pan.abs() * 100).round()}'
        : 'R${(pan * 100).round()}';
  }

  double _log10(double x) => x > 0 ? (math.log(x) / math.ln10) : double.negativeInfinity;

  IconData _getTrackIcon() {
    // Folder tracks get folder icon
    if (widget.track.isFolder) {
      return widget.track.folderExpanded ? Icons.folder_open : Icons.folder;
    }
    // Track type specific icons
    switch (widget.track.trackType) {
      case TrackType.midi:
        return Icons.piano;
      case TrackType.instrument:
        return Icons.music_note;
      case TrackType.bus:
        return Icons.call_split;
      case TrackType.aux:
        return Icons.arrow_forward;
      case TrackType.master:
        return Icons.speaker;
      case TrackType.audio:
      default:
        final name = widget.track.name.toLowerCase();
        if (name.contains('voice') || name.contains('vocal')) return Icons.mic;
        if (name.contains('guitar')) return Icons.music_note;
        if (name.contains('bass')) return Icons.graphic_eq;
        if (name.contains('drum')) return Icons.album;
        if (name.contains('key') || name.contains('piano')) return Icons.piano;
        if (name.contains('synth')) return Icons.waves;
        return Icons.audiotrack;
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final busInfo = _getTrackBusInfo(track.outputBus);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onClick,
        onSecondaryTapDown: (details) {
          widget.onContextMenu?.call(details.globalPosition);
        },
        child: Container(
          width: widget.width,
          height: widget.size.height,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            border: Border(
              left: BorderSide(color: track.color, width: 4),
              bottom: BorderSide(
                color: ReelForgeTheme.borderSubtle,
                width: 1,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Row 1: Icon + Name + M/S/R + Settings
                    _buildTopRow(track),
                    const SizedBox(height: 1),
                    // Row 2: Volume slider + meter
                    _buildVolumeRow(track),
                    const SizedBox(height: 1),
                    // Row 3: Pan slider + Bus
                    _buildPanRow(track, busInfo),
                  ],
                ),
              ),
              // Drop zone overlay (when empty)
              if (widget.isEmpty && _isHovered)
                _buildDropZone(),
              // Frozen/Locked overlays
              if (track.frozen)
                Positioned.fill(
                  child: Container(
                    color: ReelForgeTheme.accentCyan.withValues(alpha: 0.15),
                    child: Center(
                      child: Icon(
                        Icons.ac_unit,
                        color: ReelForgeTheme.accentCyan.withValues(alpha: 0.5),
                        size: 32,
                      ),
                    ),
                  ),
                ),
              if (track.locked)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.2),
                    child: Center(
                      child: Icon(
                        Icons.lock,
                        color: ReelForgeTheme.textTertiary.withValues(alpha: 0.5),
                        size: 32,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow(TimelineTrack track) {
    return Row(
      children: [
        // Indent for nested tracks
        if (track.indentLevel > 0)
          SizedBox(width: track.indentLevel * 12.0),
        // Folder expand/collapse button
        if (track.isFolder)
          GestureDetector(
            onTap: widget.onFolderToggle,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Icon(
                track.folderExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 14,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
        // Track icon
        Icon(
          _getTrackIcon(),
          size: 16,
          color: track.isFolder
              ? ReelForgeTheme.accentYellow.withValues(alpha: 0.8)
              : track.color.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        // Name
        Expanded(
          child: _isEditing
              ? TextField(
                  controller: _nameController,
                  focusNode: _focusNode,
                  style: ReelForgeTheme.body.copyWith(
                    color: ReelForgeTheme.textPrimary,
                    fontSize: 12,
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
                  onDoubleTap: () {
                    setState(() {
                      _isEditing = true;
                      _nameController.text = track.name;
                    });
                    _focusNode.requestFocus();
                  },
                  child: Text(
                    track.name,
                    style: ReelForgeTheme.body.copyWith(
                      color: ReelForgeTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
        const SizedBox(width: 4),
        // M/S/R buttons
        _MSRButton(
          label: 'M',
          isActive: track.muted,
          activeColor: ReelForgeTheme.accentOrange,
          onTap: widget.onMuteToggle,
        ),
        _MSRButton(
          label: 'S',
          isActive: track.soloed,
          activeColor: ReelForgeTheme.accentYellow,
          onTap: widget.onSoloToggle,
        ),
        _MSRButton(
          label: 'R',
          isActive: track.armed,
          activeColor: ReelForgeTheme.accentRed,
          onTap: widget.onArmToggle,
        ),
        const SizedBox(width: 2),
        // Automation toggle button
        _MSRButton(
          label: 'A',
          isActive: track.automationExpanded,
          activeColor: const Color(0xFFFF9040), // Orange for automation
          onTap: widget.onAutomationToggle,
        ),
        const SizedBox(width: 2),
        // Settings button
        GestureDetector(
          onTap: () => setState(() => _showSettings = !_showSettings),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _showSettings
                  ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              Icons.settings,
              size: 14,
              color: _showSettings
                  ? ReelForgeTheme.accentBlue
                  : ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeRow(TimelineTrack track) {
    return Row(
      children: [
        // Volume slider
        Expanded(
          child: GestureDetector(
            onDoubleTap: () => widget.onVolumeChange?.call(1.0),
            child: _ProSlider(
              value: track.volume,
              min: 0,
              max: 1.5,
              onChanged: widget.onVolumeChange,
              color: ReelForgeTheme.accentGreen,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Volume meter (compact)
        SizedBox(
          width: 16,
          height: 12,
          child: CustomPaint(
            painter: _VolumeMeterPainter(
              level: widget.signalLevel,
              peakHold: _peakHold,
            ),
          ),
        ),
        const SizedBox(width: 2),
        // Volume readout (compact)
        SizedBox(
          width: 36,
          child: Text(
            _volumeToDb(track.volume),
            style: ReelForgeTheme.monoSmall.copyWith(fontSize: 9),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildPanRow(TimelineTrack track, _BusInfo busInfo) {
    return Row(
      children: [
        // Pan slider
        Expanded(
          child: GestureDetector(
            onDoubleTap: () => widget.onPanChange?.call(0),
            child: _ProSlider(
              value: (track.pan + 1) / 2,
              min: 0,
              max: 1,
              onChanged: (v) => widget.onPanChange?.call(v * 2 - 1),
              color: ReelForgeTheme.accentCyan,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Pan readout (compact)
        SizedBox(
          width: 22,
          child: Text(
            _panDisplay(track.pan),
            style: ReelForgeTheme.monoSmall.copyWith(fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 4),
        // Bus selector (compact)
        GestureDetector(
          onTap: () {
            final currentIndex = kBusOptions.indexWhere(
              (b) => b.bus == track.outputBus,
            );
            final nextIndex = (currentIndex + 1) % kBusOptions.length;
            widget.onBusChange?.call(kBusOptions[nextIndex].bus);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: busInfo.color.withValues(alpha: 0.15),
              border: Border.all(
                color: busInfo.color.withValues(alpha: 0.4),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              busInfo.shortName,
              style: ReelForgeTheme.label.copyWith(
                color: busInfo.color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropZone() {
    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.1),
          border: Border.all(
            color: ReelForgeTheme.accentBlue.withValues(alpha: 0.5),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: ReelForgeTheme.accentBlue.withValues(alpha: 0.7),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                'Drop audio here',
                style: ReelForgeTheme.label.copyWith(
                  color: ReelForgeTheme.accentBlue.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.track.name) {
      widget.onRename?.call(trimmed);
    }
    setState(() => _isEditing = false);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// M/S/R BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _MSRButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _MSRButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_MSRButton> createState() => _MSRButtonState();
}

class _MSRButtonState extends State<_MSRButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.activeColor
                : (_isHovered
                    ? ReelForgeTheme.borderMedium
                    : ReelForgeTheme.bgDeep),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: widget.isActive
                  ? widget.activeColor.withValues(alpha: 0.5)
                  : ReelForgeTheme.borderMedium,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.isActive
                    ? ReelForgeTheme.bgDeep
                    : ReelForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRO SLIDER
// ═══════════════════════════════════════════════════════════════════════════

class _ProSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final Color color;

  const _ProSlider({
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    required this.color,
  });

  @override
  State<_ProSlider> createState() => _ProSliderState();
}

class _ProSliderState extends State<_ProSlider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          if (widget.onChanged == null) return;
          final RenderBox box = context.findRenderObject() as RenderBox;
          final pos = box.globalToLocal(details.globalPosition);
          final ratio = (pos.dx / box.size.width).clamp(0.0, 1.0);
          final newValue = widget.min + ratio * (widget.max - widget.min);
          widget.onChanged!(newValue);
        },
        child: Container(
          height: 16,
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: _isHovered
                  ? ReelForgeTheme.borderMedium
                  : ReelForgeTheme.borderSubtle,
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: CustomPaint(
              painter: _ProSliderPainter(
                value: widget.value,
                min: widget.min,
                max: widget.max,
                color: widget.color,
                isHovered: _isHovered,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProSliderPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final Color color;
  final bool isHovered;

  _ProSliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.isHovered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final fillWidth = size.width * ratio;

    // Fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: isHovered ? 0.6 : 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fillWidth, size.height),
      fillPaint,
    );

    // Center line (for pan sliders)
    if (min < 0 && max > 0) {
      final centerX = size.width * (0 - min) / (max - min);
      final centerPaint = Paint()
        ..color = ReelForgeTheme.borderMedium
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, size.height),
        centerPaint,
      );
    }

    // Thumb
    final thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(fillWidth - 2, 0, 4, size.height),
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(_ProSliderPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.isHovered != isHovered;
}

// ═══════════════════════════════════════════════════════════════════════════
// VOLUME METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _VolumeMeterPainter extends CustomPainter {
  final double level; // 0.0 - 1.0
  final double peakHold;

  _VolumeMeterPainter({
    required this.level,
    required this.peakHold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = ReelForgeTheme.bgDeep;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Level fill (green → yellow → red gradient)
    final fillHeight = size.height * level;

    if (fillHeight > 0) {
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          ReelForgeTheme.accentGreen,
          ReelForgeTheme.accentYellow,
          ReelForgeTheme.accentRed,
        ],
        stops: const [0.0, 0.7, 1.0],
      );

      final fillPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
        );

      canvas.drawRect(
        Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
        fillPaint,
      );
    }

    // Peak hold indicator
    if (peakHold > 0) {
      final peakY = size.height * (1 - peakHold);
      final peakPaint = Paint()
        ..color = ReelForgeTheme.accentRed
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(0, peakY),
        Offset(size.width, peakY),
        peakPaint,
      );
    }

    // Border
    final borderPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_VolumeMeterPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.peakHold != peakHold;
}

// ═══════════════════════════════════════════════════════════════════════════
// BUS INFO
// ═══════════════════════════════════════════════════════════════════════════

class _BusInfo {
  final OutputBus bus;
  final String name;
  final String shortName;
  final Color color;
  final IconData icon;

  const _BusInfo({
    required this.bus,
    required this.name,
    required this.shortName,
    required this.color,
    required this.icon,
  });
}

_BusInfo _getTrackBusInfo(OutputBus bus) {
  switch (bus) {
    case OutputBus.sfx:
      return _BusInfo(
        bus: bus,
        name: 'SFX',
        shortName: 'SFX',
        color: ReelForgeTheme.accentOrange,
        icon: Icons.graphic_eq,
      );
    case OutputBus.music:
      return _BusInfo(
        bus: bus,
        name: 'Music',
        shortName: 'MUS',
        color: ReelForgeTheme.accentPurple,
        icon: Icons.music_note,
      );
    case OutputBus.voice:
      return _BusInfo(
        bus: bus,
        name: 'Voice',
        shortName: 'VOX',
        color: ReelForgeTheme.accentCyan,
        icon: Icons.mic,
      );
    case OutputBus.ambience:
      return _BusInfo(
        bus: bus,
        name: 'Ambience',
        shortName: 'AMB',
        color: ReelForgeTheme.accentGreen,
        icon: Icons.park,
      );
    case OutputBus.master:
      return _BusInfo(
        bus: bus,
        name: 'Master',
        shortName: 'MST',
        color: ReelForgeTheme.textPrimary,
        icon: Icons.show_chart,
      );
  }
}

// kBusOptions is defined in timeline_models.dart

/// Channel Inspector Panel - ULTIMATE
///
/// Combined panel for:
/// - Track/Channel strip controls (Volume, Pan, M/S, Input Monitor, Arm)
/// - Insert slots (8 slots with EQ, Dynamics, etc.)
/// - Send effects (4 sends with level, pre/post)
/// - Output routing
/// - Selected Clip inspector (Properties, Gain/Fades, FX)
///
/// This replaces both the separate Channel tab and right-side Clip Inspector.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/layout_models.dart';
import '../../models/timeline_models.dart' as timeline;

class ChannelInspectorPanel extends StatefulWidget {
  // Channel data
  final ChannelStripData? channel;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId)? onArmToggle;
  final void Function(String channelId)? onMonitorToggle;
  final void Function(String channelId, int slotIndex)? onInsertClick;
  final void Function(String channelId, int sendIndex)? onSendClick;
  final void Function(String channelId, int sendIndex, double level)? onSendLevelChange;
  final void Function(String channelId)? onOutputClick;
  final void Function(String channelId)? onInputClick;
  final void Function(String channelId)? onEqClick;

  // Clip data
  final timeline.TimelineClip? selectedClip;
  final timeline.TimelineTrack? selectedClipTrack;
  final ValueChanged<timeline.TimelineClip>? onClipChanged;

  const ChannelInspectorPanel({
    super.key,
    this.channel,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onMonitorToggle,
    this.onInsertClick,
    this.onSendClick,
    this.onSendLevelChange,
    this.onOutputClick,
    this.onInputClick,
    this.onEqClick,
    this.selectedClip,
    this.selectedClipTrack,
    this.onClipChanged,
  });

  @override
  State<ChannelInspectorPanel> createState() => _ChannelInspectorPanelState();
}

class _ChannelInspectorPanelState extends State<ChannelInspectorPanel> {
  bool _channelExpanded = true;
  bool _insertsExpanded = true;
  bool _sendsExpanded = false;
  bool _routingExpanded = false;
  bool _clipExpanded = true;
  bool _clipGainExpanded = true;

  @override
  Widget build(BuildContext context) {
    final hasChannel = widget.channel != null;
    final hasClip = widget.selectedClip != null;

    if (!hasChannel && !hasClip) {
      return _buildEmptyState();
    }

    return Container(
      color: ReelForgeTheme.bgDeep,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // Channel Header with meter
          if (hasChannel) _buildChannelHeader(),

          // Channel Controls
          if (hasChannel) ...[
            const SizedBox(height: 6),
            _buildChannelControls(),
          ],

          // Insert Section
          if (hasChannel) ...[
            const SizedBox(height: 6),
            _buildInsertsSection(),
          ],

          // Sends Section
          if (hasChannel) ...[
            const SizedBox(height: 6),
            _buildSendsSection(),
          ],

          // Routing Section
          if (hasChannel) ...[
            const SizedBox(height: 6),
            _buildRoutingSection(),
          ],

          // Divider if both channel and clip
          if (hasChannel && hasClip) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
          ],

          // Clip Section
          if (hasClip) ...[
            _buildClipSection(),
            const SizedBox(height: 6),
            _buildClipGainSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_outlined,
              size: 48,
              color: ReelForgeTheme.textTertiary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Select a track',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'or clip to inspect',
              style: TextStyle(
                fontSize: 11,
                color: ReelForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChannelHeader() {
    final ch = widget.channel!;

    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: ch.color, width: 4),
        ),
      ),
      child: Column(
        children: [
          // Name and type
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ch.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ReelForgeTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        ch.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                          color: ch.color.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                // EQ Quick Access
                _QuickButton(
                  icon: Icons.graphic_eq,
                  label: 'EQ',
                  active: ch.inserts.any((i) => i.name.contains('EQ')),
                  onTap: () => widget.onEqClick?.call(ch.id),
                ),
              ],
            ),
          ),

          // Meter bar
          Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                // Left meter
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomLeft: Radius.circular(3),
                    ),
                    child: _MeterBar(level: ch.peakL),
                  ),
                ),
                Container(width: 1, color: ReelForgeTheme.bgMid),
                // Right meter
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                    child: _MeterBar(level: ch.peakR),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANNEL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChannelControls() {
    final ch = widget.channel!;

    return _Section(
      title: 'Channel',
      expanded: _channelExpanded,
      onToggle: () => setState(() => _channelExpanded = !_channelExpanded),
      child: Column(
        children: [
          // Volume fader
          _FaderRow(
            label: 'Volume',
            value: ch.volume,
            min: -70,
            max: 12,
            defaultValue: 0,
            formatValue: _formatDb,
            color: ReelForgeTheme.accentGreen,
            onChanged: (v) => widget.onVolumeChange?.call(ch.id, v),
          ),
          const SizedBox(height: 10),

          // Pan knob
          _FaderRow(
            label: 'Pan',
            value: ch.pan * 100,
            min: -100,
            max: 100,
            defaultValue: 0,
            formatValue: _formatPan,
            color: ReelForgeTheme.accentCyan,
            onChanged: (v) => widget.onPanChange?.call(ch.id, v / 100),
          ),
          const SizedBox(height: 12),

          // M/S/R/M buttons
          Row(
            children: [
              Expanded(
                child: _StateButton(
                  label: 'M',
                  tooltip: 'Mute',
                  active: ch.mute,
                  activeColor: ReelForgeTheme.accentOrange,
                  onTap: () => widget.onMuteToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'S',
                  tooltip: 'Solo',
                  active: ch.solo,
                  activeColor: ReelForgeTheme.accentYellow,
                  onTap: () => widget.onSoloToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'R',
                  tooltip: 'Record Arm',
                  active: ch.armed,
                  activeColor: ReelForgeTheme.accentRed,
                  onTap: () => widget.onArmToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'I',
                  tooltip: 'Input Monitor',
                  active: ch.inputMonitor,
                  activeColor: ReelForgeTheme.accentBlue,
                  onTap: () => widget.onMonitorToggle?.call(ch.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSERTS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInsertsSection() {
    final ch = widget.channel!;
    final usedCount = ch.inserts.where((i) => !i.isEmpty).length;

    return _Section(
      title: 'Inserts',
      subtitle: '$usedCount/8',
      expanded: _insertsExpanded,
      onToggle: () => setState(() => _insertsExpanded = !_insertsExpanded),
      child: Column(
        children: [
          // Pre-fader inserts (0-3)
          _InsertGroupLabel('Pre-Fader'),
          for (int i = 0; i < 4; i++)
            _InsertSlotRow(
              index: i,
              insert: i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i),
              onTap: () => widget.onInsertClick?.call(ch.id, i),
            ),

          const SizedBox(height: 6),

          // Post-fader inserts (4-7)
          _InsertGroupLabel('Post-Fader'),
          for (int i = 4; i < 8; i++)
            _InsertSlotRow(
              index: i,
              insert: i < ch.inserts.length ? ch.inserts[i] : InsertSlot.empty(i),
              onTap: () => widget.onInsertClick?.call(ch.id, i),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SENDS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSendsSection() {
    final ch = widget.channel!;

    return _Section(
      title: 'Sends',
      subtitle: '4 aux',
      expanded: _sendsExpanded,
      onToggle: () => setState(() => _sendsExpanded = !_sendsExpanded),
      child: Column(
        children: [
          for (int i = 0; i < 4; i++)
            _SendSlotRow(
              index: i,
              send: i < ch.sends.length ? ch.sends[i] : null,
              onTap: () => widget.onSendClick?.call(ch.id, i),
              onLevelChange: (level) => widget.onSendLevelChange?.call(ch.id, i, level),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTING SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRoutingSection() {
    final ch = widget.channel!;

    return _Section(
      title: 'Routing',
      expanded: _routingExpanded,
      onToggle: () => setState(() => _routingExpanded = !_routingExpanded),
      child: Column(
        children: [
          // Input
          _RoutingRow(
            label: 'Input',
            value: ch.input.isNotEmpty ? ch.input : 'None',
            onTap: () => widget.onInputClick?.call(ch.id),
          ),
          const SizedBox(height: 6),
          // Output
          _RoutingRow(
            label: 'Output',
            value: ch.output,
            onTap: () => widget.onOutputClick?.call(ch.id),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClipSection() {
    final clip = widget.selectedClip!;

    return _Section(
      title: clip.name,
      subtitle: 'CLIP',
      color: clip.color ?? const Color(0xFF3A6EA5),
      expanded: _clipExpanded,
      onToggle: () => setState(() => _clipExpanded = !_clipExpanded),
      child: Column(
        children: [
          _InfoRow('Position', _formatTime(clip.startTime)),
          _InfoRow('Duration', _formatTime(clip.duration)),
          _InfoRow('End', _formatTime(clip.startTime + clip.duration)),
          if (clip.sourceFile != null)
            _InfoRow('Source', clip.sourceFile!.split('/').last),
          if (widget.selectedClipTrack != null)
            _InfoRow('Track', widget.selectedClipTrack!.name),
        ],
      ),
    );
  }

  Widget _buildClipGainSection() {
    final clip = widget.selectedClip!;

    return _Section(
      title: 'Gain & Fades',
      expanded: _clipGainExpanded,
      onToggle: () => setState(() => _clipGainExpanded = !_clipGainExpanded),
      child: Column(
        children: [
          // Gain
          _FaderRow(
            label: 'Gain',
            value: _linearToDb(clip.gain),
            min: -24,
            max: 24,
            defaultValue: 0,
            formatValue: _formatDbWithUnit,
            color: ReelForgeTheme.accentCyan,
            onChanged: (v) => widget.onClipChanged?.call(clip.copyWith(gain: _dbToLinear(v))),
          ),
          const SizedBox(height: 10),

          // Fade In
          _FaderRow(
            label: 'Fade In',
            value: clip.fadeIn * 1000, // to ms
            min: 0,
            max: clip.duration * 500, // max 50% of clip
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: ReelForgeTheme.accentGreen,
            onChanged: (v) => widget.onClipChanged?.call(clip.copyWith(fadeIn: v / 1000)),
          ),
          const SizedBox(height: 10),

          // Fade Out
          _FaderRow(
            label: 'Fade Out',
            value: clip.fadeOut * 1000, // to ms
            min: 0,
            max: clip.duration * 500, // max 50% of clip
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: ReelForgeTheme.accentOrange,
            onChanged: (v) => widget.onClipChanged?.call(clip.copyWith(fadeOut: v / 1000)),
          ),
          const SizedBox(height: 12),

          // Mute/Lock buttons
          Row(
            children: [
              Expanded(
                child: _StateButton(
                  label: clip.muted ? 'UNMUTE' : 'MUTE',
                  active: clip.muted,
                  activeColor: ReelForgeTheme.accentRed,
                  onTap: () => widget.onClipChanged?.call(clip.copyWith(muted: !clip.muted)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StateButton(
                  label: clip.locked ? 'UNLOCK' : 'LOCK',
                  active: clip.locked,
                  activeColor: ReelForgeTheme.accentYellow,
                  onTap: () => widget.onClipChanged?.call(clip.copyWith(locked: !clip.locked)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORMATTERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDb(double db) {
    if (db <= -70) return '-∞';
    return db >= 0 ? '+${db.toStringAsFixed(1)}' : db.toStringAsFixed(1);
  }

  String _formatDbWithUnit(double db) {
    if (db <= -70) return '-∞ dB';
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  String _formatPan(double v) {
    if (v.abs() < 1) return 'C';
    return v < 0 ? 'L${v.abs().round()}' : 'R${v.round()}';
  }

  String _formatTime(double seconds) {
    if (seconds < 1) return '${(seconds * 1000).toStringAsFixed(0)}ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(2)}s';
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '$mins:${secs.toStringAsFixed(2).padLeft(5, '0')}';
  }

  double _linearToDb(double linear) {
    if (linear <= 0) return -70;
    return 20 * (math.log(linear) / math.ln10);
  }

  double _dbToLinear(double db) {
    if (db <= -70) return 0;
    return math.pow(10, db / 20).toDouble();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UI COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? color;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _Section({
    required this.title,
    this.subtitle,
    this.color,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: color != null
            ? Border(left: BorderSide(color: color!, width: 3))
            : null,
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ReelForgeTheme.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: ReelForgeTheme.bgDeepest,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'JetBrains Mono',
                                color: ReelForgeTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: ReelForgeTheme.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          // Content
          if (expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _FaderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String Function(double) formatValue;
  final Color color;
  final ValueChanged<double>? onChanged;

  const _FaderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.formatValue,
    required this.color,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: ReelForgeTheme.textSecondary),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (onChanged == null) return;
                final delta = details.delta.dx / constraints.maxWidth;
                final newValue = (value + delta * (max - min)).clamp(min, max);
                onChanged!(newValue);
              },
              onDoubleTap: () => onChanged?.call(defaultValue),
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  children: [
                    // Fill
                    FractionallySizedBox(
                      widthFactor: percentage,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.6),
                              color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 0dB mark for volume faders
                    if (label == 'Volume') ...[
                      Positioned(
                        left: ((0 - min) / (max - min)) * constraints.maxWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: ReelForgeTheme.textTertiary.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                    // Center mark for pan
                    if (label == 'Pan') ...[
                      Positioned(
                        left: constraints.maxWidth / 2 - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: ReelForgeTheme.textTertiary.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            formatValue(value),
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              color: ReelForgeTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _StateButton extends StatelessWidget {
  final String label;
  final String? tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _StateButton({
    required this.label,
    this.tooltip,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.2) : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : ReelForgeTheme.borderSubtle,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? activeColor : ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2) : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? ReelForgeTheme.accentBlue : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: active ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterBar extends StatelessWidget {
  final double level;

  const _MeterBar({required this.level});

  @override
  Widget build(BuildContext context) {
    final clampedLevel = level.clamp(0.0, 1.0);

    return Container(
      color: ReelForgeTheme.bgDeepest,
      child: FractionallySizedBox(
        widthFactor: clampedLevel,
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF40FF90),
                clampedLevel > 0.7 ? const Color(0xFFFFFF40) : const Color(0xFF40FF90),
                clampedLevel > 0.9 ? const Color(0xFFFF4040) : const Color(0xFFFFFF40),
              ],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsertGroupLabel extends StatelessWidget {
  final String label;

  const _InsertGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: ReelForgeTheme.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: ReelForgeTheme.borderSubtle.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsertSlotRow extends StatelessWidget {
  final int index;
  final InsertSlot insert;
  final VoidCallback? onTap;

  const _InsertSlotRow({required this.index, required this.insert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasPlugin = !insert.isEmpty;
    final isEq = insert.name.toLowerCase().contains('eq');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasPlugin ? ReelForgeTheme.bgSurface : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasPlugin && !insert.bypassed
                ? (isEq ? ReelForgeTheme.accentCyan : ReelForgeTheme.accentBlue).withValues(alpha: 0.5)
                : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasPlugin
                    ? (insert.bypassed
                        ? ReelForgeTheme.accentOrange.withValues(alpha: 0.5)
                        : ReelForgeTheme.accentGreen)
                    : ReelForgeTheme.bgMid,
                border: Border.all(
                  color: hasPlugin
                      ? (insert.bypassed ? ReelForgeTheme.accentOrange : ReelForgeTheme.accentGreen)
                      : ReelForgeTheme.borderSubtle,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              child: Text(
                hasPlugin ? insert.name : '+ Insert ${index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: hasPlugin ? FontWeight.w500 : FontWeight.w400,
                  color: hasPlugin
                      ? (insert.bypassed ? ReelForgeTheme.textTertiary : ReelForgeTheme.textPrimary)
                      : ReelForgeTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Icon for EQ
            if (isEq && hasPlugin)
              Icon(
                Icons.graphic_eq,
                size: 12,
                color: ReelForgeTheme.accentCyan,
              ),
          ],
        ),
      ),
    );
  }
}

class _SendSlotRow extends StatelessWidget {
  final int index;
  final SendSlot? send;
  final VoidCallback? onTap;
  final ValueChanged<double>? onLevelChange;

  const _SendSlotRow({
    required this.index,
    this.send,
    this.onTap,
    this.onLevelChange,
  });

  @override
  Widget build(BuildContext context) {
    final hasDestination = send?.destination != null && send!.destination!.isNotEmpty;
    final level = send?.level ?? 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasDestination ? ReelForgeTheme.bgSurface : ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasDestination ? ReelForgeTheme.accentBlue.withValues(alpha: 0.4) : ReelForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Send number
            SizedBox(
              width: 20,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: ReelForgeTheme.textTertiary,
                ),
              ),
            ),
            // Destination
            Expanded(
              child: Text(
                hasDestination ? send!.destination! : 'No Send',
                style: TextStyle(
                  fontSize: 10,
                  color: hasDestination ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Level bar (mini fader)
            if (hasDestination) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    final delta = d.delta.dx / 50;
                    onLevelChange?.call((level + delta).clamp(0.0, 1.0));
                  },
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ReelForgeTheme.accentBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoutingRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _RoutingRow({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: ReelForgeTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: ReelForgeTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: ReelForgeTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
                color: ReelForgeTheme.textSecondary,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

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
import '../../theme/fluxforge_theme.dart';
import '../../models/layout_models.dart';
import '../../models/timeline_models.dart' as timeline;
import '../../src/rust/native_ffi.dart';

class ChannelInspectorPanel extends StatefulWidget {
  // Channel data
  final ChannelStripData? channel;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId, double panRight)? onPanRightChange;
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
  final void Function(String channelId, int slotIndex, bool bypassed)? onInsertBypassToggle;
  final void Function(String channelId, int slotIndex, double wetDry)? onInsertWetDryChange;
  final void Function(String channelId, int oldIndex, int newIndex)? onInsertReorder;

  // Clip data
  final timeline.TimelineClip? selectedClip;
  final timeline.TimelineTrack? selectedClipTrack;
  final ValueChanged<timeline.TimelineClip>? onClipChanged;

  const ChannelInspectorPanel({
    super.key,
    this.channel,
    this.onVolumeChange,
    this.onPanChange,
    this.onPanRightChange,
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
    this.onInsertBypassToggle,
    this.onInsertWetDryChange,
    this.onInsertReorder,
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
  bool _sendsExpanded = true; // Default expanded like inserts
  bool _routingExpanded = false;
  bool _clipExpanded = true;
  bool _clipGainExpanded = true;
  bool _clipTimeStretchExpanded = false;

  @override
  Widget build(BuildContext context) {
    final hasChannel = widget.channel != null;
    final hasClip = widget.selectedClip != null;

    if (!hasChannel && !hasClip) {
      return _buildEmptyState();
    }

    // Use channel color as subtle background tint
    final channelColor = hasChannel ? widget.channel!.color : FluxForgeTheme.bgDeep;

    return Container(
      // Tint the entire panel with the channel's color
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        gradient: hasChannel
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  channelColor.withValues(alpha: 0.15),
                  channelColor.withValues(alpha: 0.05),
                ],
              )
            : null,
      ),
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
            Container(height: 1, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
          ],

          // Clip Section
          if (hasClip) ...[
            _buildClipSection(),
            const SizedBox(height: 6),
            _buildClipGainSection(),
            const SizedBox(height: 6),
            _buildClipTimeStretchSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_outlined,
              size: 48,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Select a track',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'or clip to inspect',
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textTertiary,
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
        color: FluxForgeTheme.bgMid,
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
                          color: FluxForgeTheme.textPrimary,
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
              color: FluxForgeTheme.bgDeepest,
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
                Container(width: 1, color: FluxForgeTheme.bgMid),
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
            color: FluxForgeTheme.accentGreen,
            onChanged: (v) => widget.onVolumeChange?.call(ch.id, v),
          ),
          const SizedBox(height: 12),

          // Pan knob(s) - Pro Tools style dual pan for stereo
          // Stereo: L knob routes LEFT input, R knob routes RIGHT input
          // Default stereo: L=<100 (hard left), R=100> (hard right)
          // Mono: single knob controls position in stereo field
          if (ch.isStereo) ...[
            // Stereo dual pan (Pro Tools style)
            Row(
              children: [
                Tooltip(
                  message: 'Stereo pan: L routes left input, R routes right input',
                  child: SizedBox(
                    width: 48,
                    child: Text(
                      'Pan L/R',
                      style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Left channel pan - controls where LEFT input goes
                      Tooltip(
                        message: 'Left channel routing\nDefault: <100 (hard left)',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ProToolsPanKnob(
                              value: ch.pan,
                              onChanged: (v) => widget.onPanChange?.call(ch.id, v),
                              label: 'L',
                              defaultValue: -1.0, // Hard left for L knob
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatPan(ch.pan * 100),
                              style: TextStyle(
                                fontSize: 8,
                                fontFamily: 'JetBrains Mono',
                                color: FluxForgeTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Right channel pan - controls where RIGHT input goes
                      Tooltip(
                        message: 'Right channel routing\nDefault: 100> (hard right)',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ProToolsPanKnob(
                              value: ch.panRight,
                              onChanged: (v) => widget.onPanRightChange?.call(ch.id, v),
                              label: 'R',
                              defaultValue: 1.0, // Hard right for R knob
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatPan(ch.panRight * 100),
                              style: TextStyle(
                                fontSize: 8,
                                fontFamily: 'JetBrains Mono',
                                color: FluxForgeTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            // Mono single pan
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    'Pan',
                    style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _ProToolsPanKnob(
                      value: ch.pan,
                      onChanged: (v) => widget.onPanChange?.call(ch.id, v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    _formatPan(ch.pan * 100),
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                      color: FluxForgeTheme.textSecondary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // M/S/R/M buttons
          Row(
            children: [
              Expanded(
                child: _StateButton(
                  label: 'M',
                  tooltip: 'Mute',
                  active: ch.mute,
                  activeColor: FluxForgeTheme.accentOrange,
                  onTap: () => widget.onMuteToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'S',
                  tooltip: 'Solo',
                  active: ch.solo,
                  activeColor: FluxForgeTheme.accentYellow,
                  onTap: () => widget.onSoloToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'R',
                  tooltip: 'Record Arm',
                  active: ch.armed,
                  activeColor: FluxForgeTheme.accentRed,
                  onTap: () => widget.onArmToggle?.call(ch.id),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _StateButton(
                  label: 'I',
                  tooltip: 'Input Monitor',
                  active: ch.inputMonitor,
                  activeColor: FluxForgeTheme.accentBlue,
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

    // Dynamic slots: show used + 1 empty per section (pre/post), max 4 each
    // Pre-fader: indices 0-3
    // Post-fader: indices 4-7
    final preInserts = ch.inserts.where((i) => i.isPreFader).toList();
    final postInserts = ch.inserts.where((i) => !i.isPreFader).toList();

    final preUsed = preInserts.where((i) => !i.isEmpty).length;
    final postUsed = postInserts.where((i) => !i.isEmpty).length;

    // Show used + 1 empty, min 1, max 4 per section
    final preVisible = (preUsed + 1).clamp(1, 4);
    final postVisible = (postUsed + 1).clamp(1, 4);

    return _Section(
      title: 'Inserts',
      subtitle: '$usedCount/8',
      expanded: _insertsExpanded,
      onToggle: () => setState(() => _insertsExpanded = !_insertsExpanded),
      child: Column(
        children: [
          // Pre-fader inserts (dynamic) with drag & drop
          _InsertGroupLabel('Pre-Fader'),
          _ReorderableInsertList(
            inserts: List.generate(preVisible, (i) =>
              i < preInserts.length ? preInserts[i] : InsertSlot.empty(i, isPreFader: true)),
            baseIndex: 0,
            onTap: (index) => widget.onInsertClick?.call(ch.id, index),
            onBypassToggle: (index, bypassed) => widget.onInsertBypassToggle?.call(ch.id, index, bypassed),
            onWetDryChange: (index, wetDry) => widget.onInsertWetDryChange?.call(ch.id, index, wetDry),
            onReorder: (oldIndex, newIndex) => widget.onInsertReorder?.call(ch.id, oldIndex, newIndex),
          ),

          const SizedBox(height: 6),

          // Post-fader inserts (dynamic) with drag & drop
          _InsertGroupLabel('Post-Fader'),
          _ReorderableInsertList(
            inserts: List.generate(postVisible, (i) =>
              i < postInserts.length ? postInserts[i] : InsertSlot.empty(i + 4, isPreFader: false)),
            baseIndex: 4,
            onTap: (index) => widget.onInsertClick?.call(ch.id, index),
            onBypassToggle: (index, bypassed) => widget.onInsertBypassToggle?.call(ch.id, index, bypassed),
            onWetDryChange: (index, wetDry) => widget.onInsertWetDryChange?.call(ch.id, index, wetDry),
            onReorder: (oldIndex, newIndex) => widget.onInsertReorder?.call(ch.id, oldIndex + 4, newIndex + 4),
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

    // Dynamic slots: show used + 1 empty, min 1, max 8
    final usedSends = ch.sends.where((s) => s.destination != null && s.destination!.isNotEmpty).length;
    final visibleSends = (usedSends + 1).clamp(1, 8);

    return _Section(
      title: 'Sends',
      subtitle: '$usedSends/8',
      expanded: _sendsExpanded,
      onToggle: () => setState(() => _sendsExpanded = !_sendsExpanded),
      child: Column(
        children: [
          for (int i = 0; i < visibleSends; i++)
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
          // Gain - uses linear slider (0-2) with dB display for Cubase-like feel
          // DISABLED when clip is locked
          _FaderRow(
            label: 'Gain',
            value: clip.gain,
            min: 0,
            max: 2,
            defaultValue: 1,
            formatValue: (v) => _formatDbWithUnit(_linearToDb(v)),
            color: clip.locked ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentCyan,
            onChanged: clip.locked ? null : (v) => widget.onClipChanged?.call(clip.copyWith(gain: v)),
          ),
          const SizedBox(height: 10),

          // Fade In - DISABLED when locked
          _FaderRow(
            label: 'Fade In',
            value: clip.fadeIn * 1000, // to ms
            min: 0,
            max: clip.duration * 500, // max 50% of clip
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: clip.locked ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentGreen,
            onChanged: clip.locked ? null : (v) => widget.onClipChanged?.call(clip.copyWith(fadeIn: v / 1000)),
          ),
          const SizedBox(height: 10),

          // Fade Out - DISABLED when locked
          _FaderRow(
            label: 'Fade Out',
            value: clip.fadeOut * 1000, // to ms
            min: 0,
            max: clip.duration * 500, // max 50% of clip
            defaultValue: 0,
            formatValue: (v) => '${v.toStringAsFixed(0)}ms',
            color: clip.locked ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentOrange,
            onChanged: clip.locked ? null : (v) => widget.onClipChanged?.call(clip.copyWith(fadeOut: v / 1000)),
          ),
          const SizedBox(height: 12),

          // Mute/Lock buttons
          Row(
            children: [
              Expanded(
                child: _StateButton(
                  label: clip.muted ? 'UNMUTE' : 'MUTE',
                  active: clip.muted,
                  activeColor: FluxForgeTheme.accentRed,
                  onTap: () => widget.onClipChanged?.call(clip.copyWith(muted: !clip.muted)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StateButton(
                  label: clip.locked ? 'UNLOCK' : 'LOCK',
                  active: clip.locked,
                  activeColor: FluxForgeTheme.accentYellow,
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

  /// Format pan value Pro Tools style
  /// -100 = full left, 0 = center, +100 = full right
  /// Display: "<100" for full left, "C" for center, "100>" for full right
  String _formatPan(double v) {
    final rounded = v.round();
    if (rounded.abs() < 1) return 'C';
    if (rounded < 0) return '<${rounded.abs()}';
    return '$rounded>';
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

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP TIME STRETCH SECTION (RF-Elastic Pro)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClipTimeStretchSection() {
    final clip = widget.selectedClip!;
    final clipId = int.tryParse(clip.id) ?? 0;

    return _Section(
      title: 'Time Stretch (RF-Elastic Pro)',
      expanded: _clipTimeStretchExpanded,
      onToggle: () => setState(() => _clipTimeStretchExpanded = !_clipTimeStretchExpanded),
      child: _TimeStretchControls(
        clipId: clipId,
        onChanged: () {
          // Notify parent that clip time stretch changed
          // This would trigger waveform redraw in the timeline
          if (widget.onClipChanged != null) {
            widget.onClipChanged!(clip);
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIME STRETCH CONTROLS
// ═══════════════════════════════════════════════════════════════════════════

class _TimeStretchControls extends StatefulWidget {
  final int clipId;
  final VoidCallback? onChanged;

  const _TimeStretchControls({required this.clipId, this.onChanged});

  @override
  State<_TimeStretchControls> createState() => _TimeStretchControlsState();
}

class _TimeStretchControlsState extends State<_TimeStretchControls> {
  double _stretchRatio = 1.0;
  double _pitchShift = 0.0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initProcessor();
  }

  @override
  void dispose() {
    if (_initialized) {
      NativeFFI.instance.elasticRemove(widget.clipId);
    }
    super.dispose();
  }

  void _initProcessor() {
    try {
      final sampleRate = NativeFFI.instance.getSampleRate().toDouble();
      final success = NativeFFI.instance.elasticCreate(widget.clipId, sampleRate);
      if (success) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      // FFI not available or failed
    }
  }

  void _setStretchRatio(double ratio) {
    if (!_initialized) return;
    setState(() => _stretchRatio = ratio);
    NativeFFI.instance.elasticSetRatio(widget.clipId, ratio);
    widget.onChanged?.call();
  }

  void _setPitchShift(double pitch) {
    if (!_initialized) return;
    setState(() => _pitchShift = pitch);
    NativeFFI.instance.elasticSetPitch(widget.clipId, pitch);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: FluxForgeTheme.textTertiary),
            const SizedBox(width: 8),
            Text(
              'Time stretch not available',
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Stretch Ratio
        _FaderRow(
          label: 'Tempo',
          value: _stretchRatio * 100,
          min: 25,
          max: 400,
          defaultValue: 100,
          formatValue: (v) => '${v.toStringAsFixed(0)}%',
          color: FluxForgeTheme.accentBlue,
          onChanged: (v) => _setStretchRatio(v / 100),
        ),
        const SizedBox(height: 10),

        // Pitch Shift
        _FaderRow(
          label: 'Pitch',
          value: _pitchShift,
          min: -12,
          max: 12,
          defaultValue: 0,
          formatValue: (v) {
            if (v == 0) return '0 st';
            return '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} st';
          },
          color: FluxForgeTheme.accentCyan,
          onChanged: _setPitchShift,
        ),
        const SizedBox(height: 12),

        // Quick presets
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PresetButton('50%', 0.5, 0, _stretchRatio, _pitchShift, _setStretchRatio, _setPitchShift),
            _PresetButton('75%', 0.75, 0, _stretchRatio, _pitchShift, _setStretchRatio, _setPitchShift),
            _PresetButton('100%', 1.0, 0, _stretchRatio, _pitchShift, _setStretchRatio, _setPitchShift),
            _PresetButton('150%', 1.5, 0, _stretchRatio, _pitchShift, _setStretchRatio, _setPitchShift),
          ],
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final double targetRatio;
  final double targetPitch;
  final double currentRatio;
  final double currentPitch;
  final ValueChanged<double> onRatioChanged;
  final ValueChanged<double> onPitchChanged;

  const _PresetButton(
    this.label,
    this.targetRatio,
    this.targetPitch,
    this.currentRatio,
    this.currentPitch,
    this.onRatioChanged,
    this.onPitchChanged,
  );

  @override
  Widget build(BuildContext context) {
    final isActive = (currentRatio - targetRatio).abs() < 0.01 && (currentPitch - targetPitch).abs() < 0.01;

    return GestureDetector(
      onTap: () {
        onRatioChanged(targetRatio);
        onPitchChanged(targetPitch);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
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
        color: FluxForgeTheme.bgMid,
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
                            color: FluxForgeTheme.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.bgDeepest,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'JetBrains Mono',
                                color: FluxForgeTheme.textTertiary,
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
                    color: FluxForgeTheme.textTertiary,
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

class _FaderRow extends StatefulWidget {
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
  State<_FaderRow> createState() => _FaderRowState();
}

class _FaderRowState extends State<_FaderRow> {
  // Track drag start position and value for smooth linear dragging
  double _dragStartX = 0;
  double _dragStartNorm = 0;

  // Check if this is a Volume fader
  bool get _isVolumeFader => widget.label == 'Volume';

  // Logic Pro style: linear mapping for all faders
  // dB is already logarithmic, so linear slider = linear dB change
  double _valueToNormalized(double value) {
    if (value <= widget.min) return 0.0;
    if (value >= widget.max) return 1.0;
    return (value - widget.min) / (widget.max - widget.min);
  }

  double _normalizedToValue(double normalized) {
    if (normalized <= 0.0) return widget.min;
    if (normalized >= 1.0) return widget.max;
    return widget.min + (normalized * (widget.max - widget.min));
  }

  void _handleDragStart(DragStartDetails details, double width) {
    _dragStartX = details.localPosition.dx;
    _dragStartNorm = _valueToNormalized(widget.value);
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (widget.onChanged == null) return;

    // Calculate new normalized position based on drag delta
    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaNorm = deltaX / width;
    final newNorm = (_dragStartNorm + deltaNorm).clamp(0.0, 1.0);
    final newValue = _normalizedToValue(newNorm);

    widget.onChanged!(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _valueToNormalized(widget.value);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            widget.label,
            style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _handleDragStart(d, constraints.maxWidth),
              onHorizontalDragUpdate: (d) => _handleDragUpdate(d, constraints.maxWidth),
              onDoubleTap: () => widget.onChanged?.call(widget.defaultValue),
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
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
                              widget.color.withValues(alpha: 0.6),
                              widget.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 0dB mark for volume faders (using Cubase-style curve position)
                    if (_isVolumeFader) ...[
                      Positioned(
                        left: _valueToNormalized(0) * constraints.maxWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                    // Center mark for pan
                    if (widget.label == 'Pan') ...[
                      Positioned(
                        left: constraints.maxWidth / 2 - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
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
            widget.formatValue(widget.value),
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              color: FluxForgeTheme.textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _StateButton extends StatefulWidget {
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
  State<_StateButton> createState() => _StateButtonState();
}

class _StateButtonState extends State<_StateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Show pressed state OR active state for instant feedback
    final showActive = _pressed ? !widget.active : widget.active;

    final button = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: showActive ? widget.activeColor.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: showActive ? widget.activeColor : FluxForgeTheme.borderSubtle,
            width: showActive ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: showActive ? widget.activeColor : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
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
          color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
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
      color: FluxForgeTheme.bgDeepest,
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
              color: FluxForgeTheme.textTertiary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsertSlotRow extends StatefulWidget {
  final int index;
  final InsertSlot insert;
  final bool isDraggable;
  final VoidCallback? onTap;
  final VoidCallback? onBypassToggle;
  final ValueChanged<double>? onWetDryChange;

  const _InsertSlotRow({
    super.key,
    required this.index,
    required this.insert,
    this.isDraggable = false,
    this.onTap,
    this.onBypassToggle,
    this.onWetDryChange,
  });

  @override
  State<_InsertSlotRow> createState() => _InsertSlotRowState();
}

class _InsertSlotRowState extends State<_InsertSlotRow> {
  bool _isHovered = false;
  bool _showWetDry = false;

  @override
  Widget build(BuildContext context) {
    final hasPlugin = !widget.insert.isEmpty;
    final isEq = widget.insert.name.toLowerCase().contains('eq');
    final accentColor = widget.insert.isPreFader
        ? FluxForgeTheme.accentBlue
        : FluxForgeTheme.accentOrange;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _showWetDry = false;
      }),
      child: GestureDetector(
        // Only open plugin picker on tap if empty slot or tap on name area
        onTap: hasPlugin ? null : widget.onTap,
        onSecondaryTap: hasPlugin ? () => setState(() => _showWetDry = !_showWetDry) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasPlugin ? FluxForgeTheme.bgSurface : FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasPlugin && !widget.insert.bypassed
                  ? (isEq ? FluxForgeTheme.accentCyan : accentColor).withValues(alpha: 0.5)
                  : (_isHovered && !hasPlugin ? FluxForgeTheme.borderMedium : FluxForgeTheme.borderSubtle),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main row
              Row(
                children: [
                  // Drag handle (only for plugins)
                  if (hasPlugin && widget.isDraggable) ...[
                    MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 14,
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Bypass toggle indicator - CLICK = TOGGLE BYPASS ONLY (no popup)
                  GestureDetector(
                    onTap: hasPlugin ? widget.onBypassToggle : null,
                    behavior: HitTestBehavior.opaque,
                    child: MouseRegion(
                      cursor: hasPlugin ? SystemMouseCursors.click : SystemMouseCursors.basic,
                      child: Tooltip(
                        message: hasPlugin ? (widget.insert.bypassed ? 'Enable' : 'Bypass') : '',
                        waitDuration: const Duration(milliseconds: 500),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasPlugin
                                ? (widget.insert.bypassed
                                    ? FluxForgeTheme.bgDeepest
                                    : accentColor)
                                : FluxForgeTheme.bgMid,
                            border: Border.all(
                              color: hasPlugin
                                  ? (widget.insert.bypassed
                                      ? FluxForgeTheme.textDisabled
                                      : accentColor)
                                  : FluxForgeTheme.borderSubtle,
                              width: 1.5,
                            ),
                            boxShadow: hasPlugin && !widget.insert.bypassed
                                ? [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: widget.insert.bypassed && hasPlugin
                              ? Center(
                                  child: Container(
                                    width: 6,
                                    height: 1.5,
                                    color: FluxForgeTheme.textDisabled,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name - tap to open plugin picker
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        hasPlugin ? widget.insert.name : '+ Insert ${widget.index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: hasPlugin ? FontWeight.w500 : FontWeight.w400,
                          color: hasPlugin
                              ? (widget.insert.bypassed ? FluxForgeTheme.textTertiary : FluxForgeTheme.textPrimary)
                              : FluxForgeTheme.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Wet/Dry indicator (if not 100%)
                  if (hasPlugin && widget.insert.wetDry < 0.99) ...[
                    Text(
                      '${widget.insert.wetDryPercent}%',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Expand wet/dry on hover
                  if (hasPlugin && _isHovered)
                    GestureDetector(
                      onTap: () => setState(() => _showWetDry = !_showWetDry),
                      child: Icon(
                        _showWetDry ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                  // Icon for EQ
                  if (isEq && hasPlugin)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.graphic_eq,
                        size: 12,
                        color: FluxForgeTheme.accentCyan,
                      ),
                    ),
                ],
              ),
              // Wet/Dry slider (expanded)
              if (_showWetDry && hasPlugin)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text(
                        'D',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: SizedBox(
                          height: 20,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              activeTrackColor: FluxForgeTheme.accentCyan,
                              inactiveTrackColor: FluxForgeTheme.bgDeepest,
                              thumbColor: FluxForgeTheme.accentCyan,
                              overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: widget.insert.wetDry,
                              min: 0.0,
                              max: 1.0,
                              onChanged: widget.onWetDryChange,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'W',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: FluxForgeTheme.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendSlotRow extends StatefulWidget {
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
  State<_SendSlotRow> createState() => _SendSlotRowState();
}

class _SendSlotRowState extends State<_SendSlotRow> {
  double _dragStartX = 0;
  double _dragStartValue = 0;
  static const double _faderWidth = 50.0;

  void _handleDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = widget.send?.level ?? 0.0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onLevelChange == null) return;
    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaPercent = deltaX / _faderWidth;
    final newValue = (_dragStartValue + deltaPercent).clamp(0.0, 1.0);
    widget.onLevelChange!(newValue);
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onLevelChange == null) return;
    final percent = (details.localPosition.dx / _faderWidth).clamp(0.0, 1.0);
    widget.onLevelChange!(percent);
  }

  @override
  Widget build(BuildContext context) {
    final hasDestination = widget.send?.destination != null && widget.send!.destination!.isNotEmpty;
    final level = widget.send?.level ?? 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 28,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hasDestination ? FluxForgeTheme.bgSurface : FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasDestination ? FluxForgeTheme.accentBlue.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Send number
            SizedBox(
              width: 20,
              child: Text(
                '${widget.index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ),
            // Destination
            Expanded(
              child: Text(
                hasDestination ? widget.send!.destination! : 'No Send',
                style: TextStyle(
                  fontSize: 10,
                  color: hasDestination ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Level bar (mini fader)
            if (hasDestination) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: _faderWidth,
                child: GestureDetector(
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onTapDown: _handleTapDown,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: level,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentBlue,
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
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textSecondary),
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
              style: TextStyle(fontSize: 10, color: FluxForgeTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
                color: FluxForgeTheme.textSecondary,
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

// ═══════════════════════════════════════════════════════════════════════════
// PRO TOOLS STYLE PAN KNOB
// ═══════════════════════════════════════════════════════════════════════════

class _ProToolsPanKnob extends StatefulWidget {
  final double value; // -1.0 to 1.0
  final ValueChanged<double>? onChanged;
  final String? label; // Optional label (e.g., 'L' or 'R' for stereo)
  final double defaultValue; // Default value on double-tap reset

  const _ProToolsPanKnob({
    required this.value,
    this.onChanged,
    this.label,
    this.defaultValue = 0.0, // Default: center for mono, override for stereo L/R
  });

  @override
  State<_ProToolsPanKnob> createState() => _ProToolsPanKnobState();
}

class _ProToolsPanKnobState extends State<_ProToolsPanKnob> {
  double _dragStartY = 0;
  double _dragStartValue = 0;

  void _handleDragStart(DragStartDetails details) {
    _dragStartY = details.localPosition.dy;
    _dragStartValue = widget.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onChanged == null) return;
    // Vertical drag: up = right, down = left (Pro Tools style)
    final deltaY = _dragStartY - details.localPosition.dy;
    final sensitivity = 0.01; // Adjust for feel
    final newValue = (_dragStartValue + deltaY * sensitivity).clamp(-1.0, 1.0);
    widget.onChanged!(newValue);
  }

  @override
  Widget build(BuildContext context) {
    // Rotation: -135° to +135° (270° range)
    final rotation = widget.value * 135 * (math.pi / 180);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label above knob (if provided)
        if (widget.label != null)
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
        GestureDetector(
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onDoubleTap: () => widget.onChanged?.call(widget.defaultValue), // Reset to default
          child: SizedBox(
            width: 32,
            height: 32,
            child: CustomPaint(
              painter: _PanKnobPainter(
                value: widget.value,
                rotation: rotation,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanKnobPainter extends CustomPainter {
  final double value;
  final double rotation;

  _PanKnobPainter({required this.value, required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Outer ring (dark)
    final outerPaint = Paint()
      ..color = FluxForgeTheme.bgDeepest
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Track arc (subtle)
    final trackPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final trackRect = Rect.fromCircle(center: center, radius: radius - 4);
    canvas.drawArc(
      trackRect,
      135 * math.pi / 180, // Start at bottom-left
      270 * math.pi / 180, // Sweep 270°
      false,
      trackPaint,
    );

    // Value arc (cyan)
    if (value.abs() > 0.01) {
      final valuePaint = Paint()
        ..color = FluxForgeTheme.accentCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final startAngle = 270 * math.pi / 180; // Top center (12 o'clock)
      final sweepAngle = value * 135 * math.pi / 180;

      canvas.drawArc(
        trackRect,
        startAngle,
        sweepAngle,
        false,
        valuePaint,
      );
    }

    // Inner knob
    final knobPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF3a3a40),
          const Color(0xFF252528),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius - 6));
    canvas.drawCircle(center, radius - 6, knobPaint);

    // Pointer line
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final pointerPaint = Paint()
      ..color = FluxForgeTheme.accentCyan
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(0, -4),
      Offset(0, -(radius - 10)),
      pointerPaint,
    );
    canvas.restore();

    // Center dot
    final dotPaint = Paint()..color = FluxForgeTheme.textTertiary;
    canvas.drawCircle(center, 2, dotPaint);
  }

  @override
  bool shouldRepaint(_PanKnobPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.rotation != rotation;
}

// ═══════════════════════════════════════════════════════════════════════════
// REORDERABLE INSERT LIST (Drag & Drop)
// ═══════════════════════════════════════════════════════════════════════════

class _ReorderableInsertList extends StatefulWidget {
  final List<InsertSlot> inserts;
  final int baseIndex;
  final void Function(int index)? onTap;
  final void Function(int index, bool bypassed)? onBypassToggle;
  final void Function(int index, double wetDry)? onWetDryChange;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const _ReorderableInsertList({
    required this.inserts,
    required this.baseIndex,
    this.onTap,
    this.onBypassToggle,
    this.onWetDryChange,
    this.onReorder,
  });

  @override
  State<_ReorderableInsertList> createState() => _ReorderableInsertListState();
}

class _ReorderableInsertListState extends State<_ReorderableInsertList> {
  @override
  Widget build(BuildContext context) {
    // Only enable reordering for non-empty slots
    final hasPlugins = widget.inserts.any((i) => !i.isEmpty);

    if (!hasPlugins) {
      // No plugins - just show normal list without drag
      return Column(
        children: [
          for (int i = 0; i < widget.inserts.length; i++)
            _InsertSlotRow(
              key: ValueKey('insert_${widget.baseIndex + i}'),
              index: widget.baseIndex + i,
              insert: widget.inserts[i],
              onTap: () => widget.onTap?.call(widget.baseIndex + i),
              onBypassToggle: () {
                final insert = widget.inserts[i];
                widget.onBypassToggle?.call(widget.baseIndex + i, !insert.bypassed);
              },
              onWetDryChange: (v) => widget.onWetDryChange?.call(widget.baseIndex + i, v),
            ),
        ],
      );
    }

    // With plugins - enable drag & drop reordering
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: widget.inserts.length,
      itemBuilder: (context, i) {
        final insert = widget.inserts[i];
        final hasPlugin = !insert.isEmpty;

        return ReorderableDragStartListener(
          key: ValueKey('insert_${widget.baseIndex + i}_${insert.id}'),
          index: i,
          enabled: hasPlugin,
          child: _InsertSlotRow(
            index: widget.baseIndex + i,
            insert: insert,
            isDraggable: hasPlugin,
            onTap: () => widget.onTap?.call(widget.baseIndex + i),
            onBypassToggle: () {
              widget.onBypassToggle?.call(widget.baseIndex + i, !insert.bypassed);
            },
            onWetDryChange: (v) => widget.onWetDryChange?.call(widget.baseIndex + i, v),
          ),
        );
      },
      onReorder: (oldIndex, newIndex) {
        // Only reorder if both slots have plugins
        if (widget.inserts[oldIndex].isEmpty) return;
        if (newIndex > oldIndex) newIndex--;
        if (oldIndex == newIndex) return;
        widget.onReorder?.call(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final scale = 1.0 + 0.05 * animation.value;
            return Transform.scale(
              scale: scale,
              child: Material(
                color: Colors.transparent,
                elevation: 8 * animation.value,
                shadowColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                child: child,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

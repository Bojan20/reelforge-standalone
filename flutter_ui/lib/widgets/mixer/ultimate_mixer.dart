/// Ultimate DAW Mixer - Cubase/Pro Tools Level
///
/// Professional mixing console with:
/// - Channel strips with real stereo metering
/// - 8 Send slots per channel
/// - Bus section (SFX, Music, Voice, Amb, Aux, Master)
/// - VCA faders
/// - Input section (gain, phase, HPF)
/// - Metering bridge (K-System, correlation)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

const int kMaxSends = 8;
const int kMaxInserts = 8;
const double kStripWidthCompact = 70.0;
const double kStripWidthExpanded = 100.0;
const double kMasterStripWidth = 120.0;

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Channel type
enum ChannelType { audio, instrument, bus, aux, vca, master }

/// Send data
class SendData {
  final int index;
  final String? destination;
  final double level;
  final bool preFader;
  final bool muted;

  const SendData({
    required this.index,
    this.destination,
    this.level = 0.0,
    this.preFader = false,
    this.muted = false,
  });

  bool get isEmpty => destination == null;

  SendData copyWith({
    int? index,
    String? destination,
    double? level,
    bool? preFader,
    bool? muted,
  }) => SendData(
    index: index ?? this.index,
    destination: destination ?? this.destination,
    level: level ?? this.level,
    preFader: preFader ?? this.preFader,
    muted: muted ?? this.muted,
  );
}

/// Insert slot data
class InsertData {
  final int index;
  final String? pluginName;
  final bool bypassed;
  final bool isPreFader;

  const InsertData({
    required this.index,
    this.pluginName,
    this.bypassed = false,
    this.isPreFader = true,
  });

  bool get isEmpty => pluginName == null;
}

/// Input section data
class InputSection {
  final double gain; // -20 to +20 dB
  final bool phaseInvert;
  final double hpfFreq; // 0 = off, 20-500 Hz
  final bool hpfEnabled;

  const InputSection({
    this.gain = 0.0,
    this.phaseInvert = false,
    this.hpfFreq = 80.0,
    this.hpfEnabled = false,
  });
}

/// Full channel data
class UltimateMixerChannel {
  final String id;
  final String name;
  final ChannelType type;
  final Color color;
  final double volume; // 0.0 to 1.5 (+6dB)
  final double pan; // -1.0 to 1.0
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool selected;
  final InputSection input;
  final List<InsertData> inserts;
  final List<SendData> sends;
  final String outputBus;
  // Real-time metering from engine
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double correlation;
  // LUFS metering (master only)
  final double lufsShort;
  final double lufsIntegrated;

  const UltimateMixerChannel({
    required this.id,
    required this.name,
    this.type = ChannelType.audio,
    this.color = const Color(0xFF4A9EFF),
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.selected = false,
    this.input = const InputSection(),
    this.inserts = const [],
    this.sends = const [],
    this.outputBus = 'master',
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.correlation = 1.0,
    this.lufsShort = -70.0,
    this.lufsIntegrated = -70.0,
  });

  bool get isMaster => type == ChannelType.master;
  bool get isBus => type == ChannelType.bus;
  bool get isAux => type == ChannelType.aux;
  bool get isVca => type == ChannelType.vca;
}

// ═══════════════════════════════════════════════════════════════════════════
// ULTIMATE MIXER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class UltimateMixer extends StatefulWidget {
  final List<UltimateMixerChannel> channels;
  final List<UltimateMixerChannel> buses;
  final List<UltimateMixerChannel> auxes;
  final List<UltimateMixerChannel> vcas;
  final UltimateMixerChannel master;
  final bool compact;
  final bool showInserts;
  final bool showSends;
  final bool showInput;
  final ValueChanged<String>? onChannelSelect;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId)? onArmToggle;
  final void Function(String channelId, int sendIndex, double level)? onSendLevelChange;
  final void Function(String channelId, int sendIndex, bool muted)? onSendMuteToggle;
  final void Function(String channelId, int sendIndex, bool preFader)? onSendPreFaderToggle;
  final void Function(String channelId, int sendIndex, String? destination)? onSendDestChange;
  final void Function(String channelId, int insertIndex)? onInsertClick;
  final void Function(String channelId, String outputBus)? onOutputChange;

  const UltimateMixer({
    super.key,
    required this.channels,
    required this.buses,
    required this.auxes,
    required this.vcas,
    required this.master,
    this.compact = false,
    this.showInserts = true,
    this.showSends = true,
    this.showInput = false,
    this.onChannelSelect,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
    this.onOutputChange,
  });

  @override
  State<UltimateMixer> createState() => _UltimateMixerState();
}

class _UltimateMixerState extends State<UltimateMixer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stripWidth = widget.compact ? kStripWidthCompact : kStripWidthExpanded;
    final hasSolo = widget.channels.any((c) => c.soloed) ||
                    widget.buses.any((c) => c.soloed) ||
                    widget.auxes.any((c) => c.soloed);

    return Container(
      color: FluxForgeTheme.bgDeepest,
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),
          // Mixer strips
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 4),
                  // Track channels
                  // NOTE: RepaintBoundary isolates meter repaints from affecting other strips
                  if (widget.channels.isNotEmpty) ...[
                    _SectionHeader(label: 'TRACKS', color: FluxForgeTheme.accentBlue),
                    ...widget.channels.map((ch) => RepaintBoundary(
                      key: ValueKey('rb_${ch.id}'),
                      child: _UltimateChannelStrip(
                        key: ValueKey(ch.id),
                        channel: ch,
                        width: stripWidth,
                        compact: widget.compact,
                        showInserts: widget.showInserts,
                        showSends: widget.showSends,
                        showInput: widget.showInput,
                        hasSoloActive: hasSolo,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(ch.id, v),
                        onPanChange: (p) => widget.onPanChange?.call(ch.id, p),
                        onMuteToggle: () => widget.onMuteToggle?.call(ch.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(ch.id),
                        onArmToggle: () => widget.onArmToggle?.call(ch.id),
                        onSelect: () => widget.onChannelSelect?.call(ch.id),
                        onSendLevelChange: (idx, lvl) => widget.onSendLevelChange?.call(ch.id, idx, lvl),
                        onSendMuteToggle: (idx, muted) => widget.onSendMuteToggle?.call(ch.id, idx, muted),
                        onSendPreFaderToggle: (idx, pre) => widget.onSendPreFaderToggle?.call(ch.id, idx, pre),
                        onSendDestChange: (idx, dest) => widget.onSendDestChange?.call(ch.id, idx, dest),
                        onInsertClick: (idx) => widget.onInsertClick?.call(ch.id, idx),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Aux returns
                  if (widget.auxes.isNotEmpty) ...[
                    _SectionHeader(label: 'AUX', color: FluxForgeTheme.accentPurple),
                    ...widget.auxes.map((aux) => RepaintBoundary(
                      key: ValueKey('rb_${aux.id}'),
                      child: _UltimateChannelStrip(
                        key: ValueKey(aux.id),
                        channel: aux,
                        width: stripWidth,
                        compact: widget.compact,
                        showInserts: widget.showInserts,
                        showSends: false,
                        hasSoloActive: hasSolo,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(aux.id, v),
                        onPanChange: (p) => widget.onPanChange?.call(aux.id, p),
                        onMuteToggle: () => widget.onMuteToggle?.call(aux.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(aux.id),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Buses
                  if (widget.buses.isNotEmpty) ...[
                    _SectionHeader(label: 'BUS', color: FluxForgeTheme.accentOrange),
                    ...widget.buses.map((bus) => RepaintBoundary(
                      key: ValueKey('rb_${bus.id}'),
                      child: _UltimateChannelStrip(
                        key: ValueKey(bus.id),
                        channel: bus,
                        width: stripWidth,
                        compact: widget.compact,
                        showInserts: widget.showInserts,
                        showSends: false,
                        hasSoloActive: hasSolo,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(bus.id, v),
                        onPanChange: (p) => widget.onPanChange?.call(bus.id, p),
                        onMuteToggle: () => widget.onMuteToggle?.call(bus.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(bus.id),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // VCAs
                  if (widget.vcas.isNotEmpty) ...[
                    _SectionHeader(label: 'VCA', color: FluxForgeTheme.accentGreen),
                    ...widget.vcas.map((vca) => RepaintBoundary(
                      key: ValueKey('rb_${vca.id}'),
                      child: _VcaStrip(
                        key: ValueKey(vca.id),
                        channel: vca,
                        width: stripWidth,
                        compact: widget.compact,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(vca.id, v),
                        onMuteToggle: () => widget.onMuteToggle?.call(vca.id),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Master
                  _SectionHeader(label: 'MASTER', color: FluxForgeTheme.textPrimary),
                  RepaintBoundary(
                    key: const ValueKey('rb_master'),
                    child: _MasterStrip(
                      channel: widget.master,
                      width: kMasterStripWidth,
                      compact: widget.compact,
                      onVolumeChange: (v) => widget.onVolumeChange?.call(widget.master.id, v),
                      onInsertClick: (idx) => widget.onInsertClick?.call(widget.master.id, idx),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.textPrimary.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          const Text('MIX CONSOLE', style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          )),
          const SizedBox(width: 16),
          _ToolbarToggle(
            label: 'INS',
            active: widget.showInserts,
            onTap: () {},
          ),
          const SizedBox(width: 4),
          _ToolbarToggle(
            label: 'SEND',
            active: widget.showSends,
            onTap: () {},
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: FluxForgeTheme.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {},
            tooltip: 'Add Bus/Aux/VCA',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _UltimateChannelStrip extends StatefulWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final bool showInserts;
  final bool showSends;
  final bool showInput;
  final bool hasSoloActive;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final VoidCallback? onSelect;
  final void Function(int index, double level)? onSendLevelChange;
  final void Function(int index, bool muted)? onSendMuteToggle;
  final void Function(int index, bool preFader)? onSendPreFaderToggle;
  final void Function(int index, String? destination)? onSendDestChange;
  final void Function(int index)? onInsertClick;

  const _UltimateChannelStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.showInserts = true,
    this.showSends = true,
    this.showInput = false,
    this.hasSoloActive = false,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSelect,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
  });

  @override
  State<_UltimateChannelStrip> createState() => _UltimateChannelStripState();
}

class _UltimateChannelStripState extends State<_UltimateChannelStrip> {
  bool _isHovered = false;
  double _peakHoldL = 0.0;
  double _peakHoldR = 0.0;

  @override
  void didUpdateWidget(_UltimateChannelStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update peak hold
    if (widget.channel.peakL > _peakHoldL) _peakHoldL = widget.channel.peakL;
    if (widget.channel.peakR > _peakHoldR) _peakHoldR = widget.channel.peakR;
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isDimmed = widget.hasSoloActive && !ch.soloed && !ch.isMaster;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isDimmed ? 0.4 : 1.0,
          child: Container(
            width: widget.width,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: ch.selected
                  ? FluxForgeTheme.bgMid.withOpacity(0.8)
                  : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: ch.selected
                    ? ch.color.withOpacity(0.6)
                    : FluxForgeTheme.textPrimary.withOpacity(0.05),
              ),
            ),
            child: Column(
              children: [
                // Track color bar
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: ch.color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
                // Insert slots (always shown when enabled)
                if (widget.showInserts)
                  _buildInsertSection(),
                // Send slots (always shown when enabled)
                if (widget.showSends)
                  _buildSendSection(),
                // Pan control
                _buildPanControl(),
                // Fader + Meter section
                Expanded(child: _buildFaderMeter()),
                // M/S/R buttons
                _buildButtons(),
                // Channel name
                _buildNameLabel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsertSection() {
    // Dynamic slots: show used + 1 empty, min 1, max 8
    int lastUsedInsert = -1;
    for (int i = 0; i < widget.channel.inserts.length; i++) {
      if (widget.channel.inserts[i].pluginName != null) lastUsedInsert = i;
    }
    final visibleInserts = (lastUsedInsert + 2).clamp(1, 8);

    return Container(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: List.generate(visibleInserts, (i) {
          final insert = i < widget.channel.inserts.length
              ? widget.channel.inserts[i]
              : InsertData(index: i);
          return _InsertSlot(
            insert: insert,
            onTap: () => widget.onInsertClick?.call(i),
          );
        }),
      ),
    );
  }

  Widget _buildSendSection() {
    // Dynamic slots: show used + 1 empty, min 1, max 8
    int lastUsedSend = -1;
    for (int i = 0; i < widget.channel.sends.length; i++) {
      if (widget.channel.sends[i].destination != null) lastUsedSend = i;
    }
    final visibleSends = (lastUsedSend + 2).clamp(1, 8);

    return Container(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: List.generate(visibleSends, (i) {
          final send = i < widget.channel.sends.length
              ? widget.channel.sends[i]
              : SendData(index: i);
          return _SendSlot(
            send: send,
            onLevelChange: (lvl) => widget.onSendLevelChange?.call(i, lvl),
            onMuteToggle: (muted) => widget.onSendMuteToggle?.call(i, muted),
            onPreFaderToggle: (pre) => widget.onSendPreFaderToggle?.call(i, pre),
            onDestChange: (dest) => widget.onSendDestChange?.call(i, dest),
          );
        }),
      ),
    );
  }

  Widget _buildPanControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: _PanKnob(
        value: widget.channel.pan,
        size: widget.compact ? 24 : 32,
        onChanged: widget.onPanChange,
      ),
    );
  }

  Widget _buildFaderMeter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _FaderWithMeter(
        volume: widget.channel.volume,
        peakL: widget.channel.peakL,
        peakR: widget.channel.peakR,
        peakHoldL: _peakHoldL,
        peakHoldR: _peakHoldR,
        muted: widget.channel.muted,
        onChanged: widget.onVolumeChange,
        onResetPeaks: () => setState(() {
          _peakHoldL = 0;
          _peakHoldR = 0;
        }),
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StripButton(
            label: 'M',
            active: widget.channel.muted,
            activeColor: const Color(0xFFFF6B6B),
            onTap: widget.onMuteToggle,
          ),
          _StripButton(
            label: 'S',
            active: widget.channel.soloed,
            activeColor: const Color(0xFFFFD93D),
            onTap: widget.onSoloToggle,
          ),
          if (widget.channel.type == ChannelType.audio)
            _StripButton(
              label: 'R',
              active: widget.channel.armed,
              activeColor: const Color(0xFFFF4444),
              onTap: widget.onArmToggle,
            ),
        ],
      ),
    );
  }

  Widget _buildNameLabel() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Text(
          widget.channel.name,
          style: TextStyle(
            color: widget.channel.selected
                ? FluxForgeTheme.textPrimary
                : FluxForgeTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FADER WITH INTEGRATED METER
// ═══════════════════════════════════════════════════════════════════════════

class _FaderWithMeter extends StatefulWidget {
  final double volume;
  final double peakL;
  final double peakR;
  final double peakHoldL;
  final double peakHoldR;
  final bool muted;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onResetPeaks;

  const _FaderWithMeter({
    required this.volume,
    this.peakL = 0,
    this.peakR = 0,
    this.peakHoldL = 0,
    this.peakHoldR = 0,
    this.muted = false,
    this.onChanged,
    this.onResetPeaks,
  });

  @override
  State<_FaderWithMeter> createState() => _FaderWithMeterState();
}

class _FaderWithMeterState extends State<_FaderWithMeter> {
  bool _isDragging = false;
  bool _fineMode = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final meterWidth = (width - 20) / 2; // Space for fader cap

        return GestureDetector(
          onTapDown: (_) => setState(() => _isDragging = true),
          onTapUp: (_) => setState(() => _isDragging = false),
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragUpdate: (details) {
            if (widget.onChanged != null) {
              final delta = -details.delta.dy / height;
              final sensitivity = _fineMode ? 0.1 : 1.0;
              final newVolume = (widget.volume + delta * sensitivity * 1.5).clamp(0.0, 1.5);
              widget.onChanged!(newVolume);
            }
          },
          onDoubleTap: () => widget.onChanged?.call(1.0), // Reset to 0dB
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.shift) {
                setState(() => _fineMode = true);
              } else if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.shift) {
                setState(() => _fineMode = false);
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                // Left meter
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: meterWidth,
                  child: _MeterBar(
                    peak: widget.peakL,
                    peakHold: widget.peakHoldL,
                    muted: widget.muted,
                  ),
                ),
                // Right meter
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: meterWidth,
                  child: _MeterBar(
                    peak: widget.peakR,
                    peakHold: widget.peakHoldR,
                    muted: widget.muted,
                  ),
                ),
                // Fader track (center)
                Positioned(
                  left: meterWidth + 2,
                  right: meterWidth + 2,
                  top: 4,
                  bottom: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Fader cap
                Positioned(
                  left: meterWidth - 2,
                  right: meterWidth - 2,
                  top: 4 + (1.0 - widget.volume / 1.5) * (height - 24),
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.grey.shade300,
                          Colors.grey.shade500,
                          Colors.grey.shade400,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: FluxForgeTheme.bgVoid.withOpacity(0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 1,
                        color: FluxForgeTheme.bgVoid.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
                // dB label
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _volumeToDb(widget.volume),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isDragging
                            ? FluxForgeTheme.accentBlue
                            : FluxForgeTheme.textSecondary,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
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

  String _volumeToDb(double volume) {
    if (volume <= 0.001) return '-∞';
    final db = 20 * math.log(volume) / math.ln10;
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METER BAR
// ═══════════════════════════════════════════════════════════════════════════

class _MeterBar extends StatelessWidget {
  final double peak;
  final double peakHold;
  final bool muted;

  const _MeterBar({
    required this.peak,
    this.peakHold = 0,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MeterPainter(
        peak: muted ? 0 : peak,
        peakHold: muted ? 0 : peakHold,
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double peak;
  final double peakHold;

  _MeterPainter({required this.peak, this.peakHold = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0A0C));

    // Meter gradient
    final meterHeight = size.height * peak.clamp(0.0, 1.2);
    if (meterHeight > 0) {
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: const [
          Color(0xFF40C8FF), // Cyan
          Color(0xFF40FF90), // Green
          Color(0xFFFFFF40), // Yellow
          Color(0xFFFF9040), // Orange
          Color(0xFFFF4040), // Red
        ],
        stops: const [0.0, 0.4, 0.7, 0.85, 1.0],
      );

      final meterRect = Rect.fromLTWH(
        1,
        size.height - meterHeight,
        size.width - 2,
        meterHeight,
      );

      canvas.drawRect(
        meterRect,
        Paint()..shader = gradient.createShader(rect),
      );
    }

    // Peak hold line
    if (peakHold > 0.01) {
      final holdY = size.height * (1 - peakHold.clamp(0.0, 1.2));
      final holdColor = peakHold > 1.0
          ? const Color(0xFFFF4040)
          : peakHold > 0.7
              ? const Color(0xFFFFFF40)
              : const Color(0xFF40FF90);
      canvas.drawLine(
        Offset(1, holdY),
        Offset(size.width - 1, holdY),
        Paint()
          ..color = holdColor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      peak != oldDelegate.peak || peakHold != oldDelegate.peakHold;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAN KNOB
// ═══════════════════════════════════════════════════════════════════════════

class _PanKnob extends StatelessWidget {
  final double value;
  final double size;
  final ValueChanged<double>? onChanged;

  const _PanKnob({
    required this.value,
    this.size = 32,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = details.delta.dx / 50;
          final newValue = (value + delta).clamp(-1.0, 1.0);
          onChanged!(newValue);
        }
      },
      onDoubleTap: () => onChanged?.call(0.0),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PanKnobPainter(value: value),
        ),
      ),
    );
  }
}

class _PanKnobPainter extends CustomPainter {
  final double value;

  _PanKnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      Paint()
        ..color = const Color(0xFF2A2A30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Value arc
    final startAngle = math.pi * 1.25; // Center position
    final sweepAngle = value * math.pi * 0.75; // Value determines direction
    if (value.abs() > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = FluxForgeTheme.accentBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center dot
    canvas.drawCircle(center, 2, Paint()..color = FluxForgeTheme.textSecondary);

    // L/R labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: value < -0.01 ? 'L' : value > 0.01 ? 'R' : 'C',
      style: const TextStyle(
        color: FluxForgeTheme.textTertiary,
        fontSize: 7,
        fontWeight: FontWeight.w500,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PanKnobPainter oldDelegate) => value != oldDelegate.value;
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT & SEND SLOTS
// ═══════════════════════════════════════════════════════════════════════════

class _InsertSlot extends StatelessWidget {
  final InsertData insert;
  final VoidCallback? onTap;

  const _InsertSlot({required this.insert, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 16,
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: insert.isEmpty
              ? FluxForgeTheme.bgVoid.withOpacity(0.3)
              : FluxForgeTheme.accentBlue.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: insert.bypassed
                ? Colors.orange.withOpacity(0.5)
                : FluxForgeTheme.textPrimary.withOpacity(0.1),
          ),
        ),
        child: Center(
          child: Text(
            insert.pluginName ?? '—',
            style: TextStyle(
              color: insert.isEmpty
                  ? FluxForgeTheme.textTertiary
                  : FluxForgeTheme.textPrimary,
              fontSize: 7,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _SendSlot extends StatelessWidget {
  final SendData send;
  final ValueChanged<double>? onLevelChange;
  final ValueChanged<bool>? onMuteToggle;
  final ValueChanged<bool>? onPreFaderToggle;
  final ValueChanged<String?>? onDestChange;

  const _SendSlot({
    required this.send,
    this.onLevelChange,
    this.onMuteToggle,
    this.onPreFaderToggle,
    this.onDestChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          // Mute button
          GestureDetector(
            onTap: send.isEmpty ? null : () => onMuteToggle?.call(!send.muted),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: send.muted
                    ? FluxForgeTheme.accentOrange.withOpacity(0.8)
                    : FluxForgeTheme.bgVoid.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: send.muted
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.borderSubtle,
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    fontSize: 6,
                    fontWeight: FontWeight.w700,
                    color: send.muted ? Colors.white : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 1),
          // Send destination (tappable for selection)
          Expanded(
            child: GestureDetector(
              onTap: () => _showDestinationMenu(context),
              child: Container(
                decoration: BoxDecoration(
                  color: send.isEmpty
                      ? FluxForgeTheme.bgVoid.withOpacity(0.3)
                      : send.muted
                          ? FluxForgeTheme.bgVoid.withOpacity(0.5)
                          : FluxForgeTheme.accentPurple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Text(
                    send.destination ?? '—',
                    style: TextStyle(
                      color: send.isEmpty || send.muted
                          ? FluxForgeTheme.textTertiary
                          : FluxForgeTheme.textPrimary,
                      fontSize: 7,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 1),
          // Pre/Post toggle
          GestureDetector(
            onTap: send.isEmpty ? null : () => onPreFaderToggle?.call(!send.preFader),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: send.preFader
                    ? FluxForgeTheme.accentCyan.withOpacity(0.3)
                    : FluxForgeTheme.bgVoid.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: send.preFader
                      ? FluxForgeTheme.accentCyan.withOpacity(0.5)
                      : FluxForgeTheme.borderSubtle,
                  width: 0.5,
                ),
              ),
              child: Text(
                send.preFader ? 'PRE' : 'PST',
                style: TextStyle(
                  fontSize: 5,
                  fontWeight: FontWeight.w600,
                  color: send.preFader
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 1),
          // Send level mini-fader
          SizedBox(
            width: 18,
            child: _MiniSendLevel(
              level: send.level,
              muted: send.muted,
              onChanged: onLevelChange,
            ),
          ),
        ],
      ),
    );
  }

  void _showDestinationMenu(BuildContext context) {
    final fxBuses = [
      ('fx1', 'FX 1', const Color(0xFF9B59B6)),
      ('fx2', 'FX 2', const Color(0xFF3498DB)),
      ('fx3', 'FX 3', const Color(0xFF27AE60)),
      ('fx4', 'FX 4', const Color(0xFFE67E22)),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(0, 0, 0, 0),
      color: FluxForgeTheme.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      items: [
        PopupMenuItem<String>(
          value: '',
          height: 20,
          child: Text('-- None --', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
        ),
        ...fxBuses.map((bus) => PopupMenuItem<String>(
          value: bus.$1,
          height: 20,
          child: Row(
            children: [
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: bus.$3, borderRadius: BorderRadius.circular(1)),
              ),
              Text(bus.$2, style: TextStyle(fontSize: 9, color: FluxForgeTheme.textPrimary)),
            ],
          ),
        )),
      ],
    ).then((value) {
      if (value != null) {
        onDestChange?.call(value.isEmpty ? null : value);
      }
    });
  }
}

class _MiniSendLevel extends StatelessWidget {
  final double level;
  final bool muted;
  final ValueChanged<double>? onChanged;

  const _MiniSendLevel({required this.level, this.muted = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = -details.delta.dy / 50;
          final newLevel = (level + delta).clamp(0.0, 1.0);
          onChanged!(newLevel);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgVoid.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          heightFactor: level,
          child: Container(
            decoration: BoxDecoration(
              color: muted ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentPurple,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STRIP BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _StripButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _StripButton({
    required this.label,
    this.active = false,
    this.activeColor = Colors.blue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 14,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgVoid.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.textPrimary.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? FluxForgeTheme.bgVoid : FluxForgeTheme.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA & MASTER STRIPS
// ═══════════════════════════════════════════════════════════════════════════

class _VcaStrip extends StatelessWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final VoidCallback? onMuteToggle;

  const _VcaStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: channel.color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
          const Spacer(),
          // VCA fader (no meter)
          Expanded(
            flex: 3,
            child: _VcaFader(
              volume: channel.volume,
              onChanged: onVolumeChange,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: _StripButton(
              label: 'M',
              active: channel.muted,
              activeColor: const Color(0xFFFF6B6B),
              onTap: onMuteToggle,
            ),
          ),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Center(
              child: Text(
                channel.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VcaFader extends StatelessWidget {
  final double volume;
  final ValueChanged<double>? onChanged;

  const _VcaFader({required this.volume, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = -details.delta.dy / 100;
          final newVolume = (volume + delta).clamp(0.0, 1.5);
          onChanged!(newVolume);
        }
      },
      onDoubleTap: () => onChanged?.call(1.0),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgVoid.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capY = (1.0 - volume / 1.5) * (constraints.maxHeight - 16);
            return Stack(
              children: [
                Positioned(
                  top: capY,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF60D060), Color(0xFF40A040)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MasterStrip extends StatelessWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final void Function(int index)? onInsertClick;

  const _MasterStrip({
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onInsertClick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FluxForgeTheme.bgMid,
            FluxForgeTheme.bgDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.accentOrange.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9040), Color(0xFFFFD040)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
          // Insert section
          if (!compact)
            Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                children: List.generate(4, (i) {
                  final insert = i < channel.inserts.length
                      ? channel.inserts[i]
                      : InsertData(index: i);
                  return _InsertSlot(
                    insert: insert,
                    onTap: () => onInsertClick?.call(i),
                  );
                }),
              ),
            ),
          // Stereo meter + fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _FaderWithMeter(
                volume: channel.volume,
                peakL: channel.peakL,
                peakR: channel.peakR,
                peakHoldL: channel.peakL,
                peakHoldR: channel.peakR,
                muted: channel.muted,
                onChanged: onVolumeChange,
              ),
            ),
          ),
          // LUFS display
          Container(
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgVoid.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: Text(
                _formatLufs(channel.lufsIntegrated),
                style: TextStyle(
                  color: _getLufsColor(channel.lufsIntegrated),
                  fontSize: 9,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Master label
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: const Center(
              child: Text(
                'STEREO OUT',
                style: TextStyle(
                  color: FluxForgeTheme.warningOrange,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LUFS HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Format LUFS value for display
String _formatLufs(double lufs) {
  if (lufs <= -70.0) return '-∞ LUFS';
  return '${lufs.toStringAsFixed(1)} LUFS';
}

/// Get color based on LUFS value relative to streaming target (-14 LUFS)
Color _getLufsColor(double lufs) {
  if (lufs <= -70.0) return FluxForgeTheme.textMuted;
  if (lufs > -12.0) return FluxForgeTheme.accentRed; // Too loud
  if (lufs > -14.0) return FluxForgeTheme.warningOrange; // Slightly loud
  if (lufs < -16.0) return FluxForgeTheme.accentCyan; // Quiet
  return FluxForgeTheme.accentGreen; // On target (-14 to -16 LUFS)
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      child: RotatedBox(
        quarterTurns: 3,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.textPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolbarToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? FluxForgeTheme.accentBlue.withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textPrimary.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

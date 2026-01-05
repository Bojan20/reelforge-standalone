// DAW Mixer Widget
//
// Professional mixing console integrating:
// - Channel strips with inserts/sends
// - VCA faders with spill mode
// - Professional metering (VU/PPM/LUFS)
// - Master section with LUFS/True Peak
// - Automation integration

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import 'pro_mixer_strip.dart';
import 'vca_strip.dart';
import '../meters/pro_meter.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DAW MIXER DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete DAW mixer state
class DawMixerData {
  final List<ProMixerStripData> tracks;
  final List<ProMixerStripData> buses;
  final ProMixerStripData masterBus;
  final List<VcaData> vcas;
  final MeterReadings? masterMetering;
  final String? selectedTrackId;
  final String? selectedVcaId;
  final bool showVcaSection;
  final bool showMasterMetering;
  final MeterMode masterMeterMode;

  const DawMixerData({
    this.tracks = const [],
    this.buses = const [],
    required this.masterBus,
    this.vcas = const [],
    this.masterMetering,
    this.selectedTrackId,
    this.selectedVcaId,
    this.showVcaSection = true,
    this.showMasterMetering = true,
    this.masterMeterMode = MeterMode.lufs,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// DAW MIXER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Professional DAW Mixer - Cubase/Pro Tools/SSL console
class DawMixer extends StatefulWidget {
  final DawMixerData data;
  final bool compact;

  // Track callbacks
  final void Function(String trackId, double volume)? onTrackVolumeChange;
  final void Function(String trackId, double pan)? onTrackPanChange;
  final void Function(String trackId)? onTrackMuteToggle;
  final void Function(String trackId)? onTrackSoloToggle;
  final void Function(String trackId)? onTrackArmToggle;
  final void Function(String trackId)? onTrackSelect;
  final void Function(String trackId, int slotIndex)? onTrackInsertClick;
  final void Function(String trackId, int sendIndex, double level)? onTrackSendLevelChange;

  // VCA callbacks
  final void Function(int vcaId, double level)? onVcaLevelChange;
  final void Function(int vcaId, bool muted)? onVcaMuteToggle;
  final void Function(int vcaId, bool soloed)? onVcaSoloToggle;
  final void Function(int vcaId, bool spillActive)? onVcaSpillToggle;
  final void Function(int vcaId)? onVcaSelect;
  final VoidCallback? onAddVca;

  // Master callbacks
  final void Function(double volume)? onMasterVolumeChange;
  final void Function(MeterMode mode)? onMasterMeterModeChange;
  final VoidCallback? onResetMetering;

  const DawMixer({
    super.key,
    required this.data,
    this.compact = false,
    this.onTrackVolumeChange,
    this.onTrackPanChange,
    this.onTrackMuteToggle,
    this.onTrackSoloToggle,
    this.onTrackArmToggle,
    this.onTrackSelect,
    this.onTrackInsertClick,
    this.onTrackSendLevelChange,
    this.onVcaLevelChange,
    this.onVcaMuteToggle,
    this.onVcaSoloToggle,
    this.onVcaSpillToggle,
    this.onVcaSelect,
    this.onAddVca,
    this.onMasterVolumeChange,
    this.onMasterMeterModeChange,
    this.onResetMetering,
  });

  @override
  State<DawMixer> createState() => _DawMixerState();
}

class _DawMixerState extends State<DawMixer> {
  final ScrollController _trackScrollController = ScrollController();
  final ScrollController _busScrollController = ScrollController();

  @override
  void dispose() {
    _trackScrollController.dispose();
    _busScrollController.dispose();
    super.dispose();
  }

  /// Filter tracks based on active VCA spill
  List<ProMixerStripData> get _visibleTracks {
    final activeSpillVca = widget.data.vcas.firstWhere(
      (v) => v.spillActive,
      orElse: () => VcaData(id: -1, name: ''),
    );

    if (activeSpillVca.id == -1) {
      return widget.data.tracks;
    }

    // Show only tracks in the spilled VCA
    final memberIds = activeSpillVca.memberTrackIds;
    return widget.data.tracks
        .where((t) => memberIds.contains(int.tryParse(t.id) ?? -1))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Row(
        children: [
          // Tracks section
          Expanded(
            flex: 5,
            child: _buildTracksSection(),
          ),

          // Separator
          _buildSeparator(),

          // Buses section
          if (widget.data.buses.isNotEmpty) ...[
            SizedBox(
              width: widget.data.buses.length * (widget.compact ? 60.0 : 80.0),
              child: _buildBusesSection(),
            ),
            _buildSeparator(),
          ],

          // VCA section
          if (widget.data.showVcaSection && widget.data.vcas.isNotEmpty) ...[
            SizedBox(
              width: widget.data.vcas.length * 88.0 + 40,
              child: _buildVcaSection(),
            ),
            _buildSeparator(),
          ],

          // Master section
          SizedBox(
            width: widget.data.showMasterMetering ? 180 : 100,
            child: _buildMasterSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ReelForgeTheme.borderMedium.withValues(alpha: 0.1),
            ReelForgeTheme.borderMedium,
            ReelForgeTheme.borderMedium.withValues(alpha: 0.1),
          ],
        ),
      ),
    );
  }

  Widget _buildTracksSection() {
    final tracks = _visibleTracks;

    return Column(
      children: [
        // Section header
        _buildSectionHeader(
          'TRACKS',
          Icons.music_note,
          ReelForgeTheme.accentCyan,
          count: tracks.length,
        ),
        // Tracks
        Expanded(
          child: Scrollbar(
            controller: _trackScrollController,
            child: ListView.builder(
              controller: _trackScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ProMixerStrip(
                  data: track,
                  compact: widget.compact,
                  onVolumeChange: (v) =>
                      widget.onTrackVolumeChange?.call(track.id, v),
                  onPanChange: (p) =>
                      widget.onTrackPanChange?.call(track.id, p),
                  onMuteToggle: () => widget.onTrackMuteToggle?.call(track.id),
                  onSoloToggle: () => widget.onTrackSoloToggle?.call(track.id),
                  onArmToggle: () => widget.onTrackArmToggle?.call(track.id),
                  onSelect: () => widget.onTrackSelect?.call(track.id),
                  onInsertClick: (slot) =>
                      widget.onTrackInsertClick?.call(track.id, slot),
                  onSendLevelChange: (idx, level) =>
                      widget.onTrackSendLevelChange?.call(track.id, idx, level),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusesSection() {
    return Column(
      children: [
        _buildSectionHeader(
          'BUSES',
          Icons.alt_route,
          ReelForgeTheme.accentGreen,
          count: widget.data.buses.length,
        ),
        Expanded(
          child: Scrollbar(
            controller: _busScrollController,
            child: ListView.builder(
              controller: _busScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.data.buses.length,
              itemBuilder: (context, index) {
                final bus = widget.data.buses[index];
                return ProMixerStrip(
                  data: bus,
                  compact: widget.compact,
                  onVolumeChange: (v) =>
                      widget.onTrackVolumeChange?.call(bus.id, v),
                  onMuteToggle: () => widget.onTrackMuteToggle?.call(bus.id),
                  onSoloToggle: () => widget.onTrackSoloToggle?.call(bus.id),
                  onSelect: () => widget.onTrackSelect?.call(bus.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVcaSection() {
    return Column(
      children: [
        VcaGroupHeader(
          vcas: widget.data.vcas,
          onAddVca: widget.onAddVca,
        ),
        Expanded(
          child: Row(
            children: widget.data.vcas.map((vca) {
              return VcaFaderStrip(
                vca: vca,
                isSelected: vca.id.toString() == widget.data.selectedVcaId,
                onLevelChanged: (level) =>
                    widget.onVcaLevelChange?.call(vca.id, level),
                onMuteChanged: (muted) =>
                    widget.onVcaMuteToggle?.call(vca.id, muted),
                onSoloChanged: (soloed) =>
                    widget.onVcaSoloToggle?.call(vca.id, soloed),
                onSpillToggled: (active) =>
                    widget.onVcaSpillToggle?.call(vca.id, active),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterSection() {
    return Column(
      children: [
        _buildSectionHeader(
          'MASTER',
          Icons.surround_sound,
          ReelForgeTheme.accentOrange,
          isMaster: true,
        ),
        Expanded(
          child: Row(
            children: [
              // Master fader strip
              ProMixerStrip(
                data: widget.data.masterBus,
                compact: widget.compact,
                onVolumeChange: widget.onMasterVolumeChange,
                onMuteToggle: () =>
                    widget.onTrackMuteToggle?.call(widget.data.masterBus.id),
                onSoloToggle: () =>
                    widget.onTrackSoloToggle?.call(widget.data.masterBus.id),
                onResetPeaks: widget.onResetMetering,
              ),

              // Master metering panel
              if (widget.data.showMasterMetering &&
                  widget.data.masterMetering != null)
                _buildMasterMeteringPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMasterMeteringPanel() {
    return Container(
      width: 90,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        border: Border(
          left: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Meter mode selector
          _buildMeterModeSelector(),
          const SizedBox(height: 4),

          // Main meter
          Expanded(
            child: StereoMeterStrip(
              readings: widget.data.masterMetering!,
              primaryMode: widget.data.masterMeterMode,
              showCorrelation: true,
              showLufs: widget.data.masterMeterMode == MeterMode.lufs,
            ),
          ),

          // LUFS readout
          if (widget.data.masterMeterMode == MeterMode.lufs)
            _buildLufsReadout(),
        ],
      ),
    );
  }

  Widget _buildMeterModeSelector() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _buildModeButton('VU', MeterMode.vu),
          const SizedBox(width: 2),
          _buildModeButton('PPM', MeterMode.ppm),
          const SizedBox(width: 2),
          _buildModeButton('LUFS', MeterMode.lufs),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, MeterMode mode) {
    final isActive = widget.data.masterMeterMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onMasterMeterModeChange?.call(mode),
        child: Container(
          decoration: BoxDecoration(
            color:
                isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color:
                  isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.borderSubtle,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : ReelForgeTheme.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLufsReadout() {
    final readings = widget.data.masterMetering!;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _buildLufsRow('INT', readings.lufsIntegrated, ReelForgeTheme.accentGreen),
          _buildLufsRow('S', readings.lufsShort, ReelForgeTheme.accentCyan),
          _buildLufsRow('TP',
            (readings.truePeakLeft > readings.truePeakRight
                ? readings.truePeakLeft
                : readings.truePeakRight) * 20 - 60, // Convert to dBTP
            readings.truePeakLeft > 0.98 || readings.truePeakRight > 0.98
                ? ReelForgeTheme.accentRed
                : ReelForgeTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildLufsRow(String label, double value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: ReelForgeTheme.textTertiary,
          ),
        ),
        Text(
          value.isFinite ? value.toStringAsFixed(1) : '-∞',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    Color color, {
    int? count,
    bool isMaster = false,
  }) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isMaster
            ? color.withValues(alpha: 0.15)
            : ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(
            color: isMaster ? color.withValues(alpha: 0.5) : ReelForgeTheme.borderSubtle,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
          if (count != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRACK COLORS
// ═══════════════════════════════════════════════════════════════════════════════

/// Standard track color palette
class TrackColors {
  static const List<Color> palette = [
    Color(0xFF5AA8FF), // Blue
    Color(0xFF5DE2A5), // Green
    Color(0xFFFF8A5C), // Orange
    Color(0xFFAA7BDE), // Purple
    Color(0xFFFF6B8A), // Pink
    Color(0xFF5CE2E2), // Cyan
    Color(0xFFFFD55C), // Yellow
    Color(0xFFE25C5C), // Red
    Color(0xFF8AE25C), // Lime
    Color(0xFF5C8AE2), // Indigo
  ];

  static Color forIndex(int index) {
    return palette[index % palette.length];
  }

  static Color forName(String name) {
    final hash = name.hashCode.abs();
    return palette[hash % palette.length];
  }
}

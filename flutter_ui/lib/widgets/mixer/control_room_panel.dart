/// Control Room Panel - Professional Monitor Mixer
///
/// Full control room with:
/// - Monitor source selection (Master, Cue 1-4, External)
/// - Monitor level + Dim + Mono
/// - Speaker selection (up to 4 sets)
/// - Solo modes (SIP, AFL, PFL)
/// - 4 Cue/Headphone mixes
/// - Talkback

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/control_room_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL ROOM PANEL
// ═══════════════════════════════════════════════════════════════════════════

class ControlRoomPanel extends StatefulWidget {
  const ControlRoomPanel({super.key});

  @override
  State<ControlRoomPanel> createState() => _ControlRoomPanelState();
}

class _ControlRoomPanelState extends State<ControlRoomPanel> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Refresh metering at 30 Hz
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) {
        context.read<ControlRoomProvider>().updateMetering();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ControlRoomProvider>(
      builder: (context, controlRoom, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border.all(color: FluxForgeTheme.bgSurface),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(controlRoom),
              Divider(height: 1, color: FluxForgeTheme.bgSurface),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        // Monitor Section
                        _buildMonitorSection(controlRoom),
                        const SizedBox(height: 12),

                        // Speaker Selection
                        _buildSpeakerSection(controlRoom),
                        const SizedBox(height: 12),

                        // Solo Mode
                        _buildSoloSection(controlRoom),
                        const SizedBox(height: 12),

                        // Cue Mixes
                        _buildCueMixesSection(controlRoom),
                        const SizedBox(height: 12),

                        // Talkback
                        _buildTalkbackSection(controlRoom),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ControlRoomProvider controlRoom) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.speaker, size: 16, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 8),
          const Text(
            'CONTROL ROOM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Monitor meter mini
          _buildMiniMeter(controlRoom.monitorPeakL, controlRoom.monitorPeakR),
        ],
      ),
    );
  }

  Widget _buildMiniMeter(double peakL, double peakR) {
    return Row(
      children: [
        _buildMeterBar(peakL, 30, 4),
        const SizedBox(width: 2),
        _buildMeterBar(peakR, 30, 4),
      ],
    );
  }

  Widget _buildMeterBar(double peak, double height, double width) {
    final db = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);

    Color color;
    if (db > -3) {
      color = FluxForgeTheme.accentRed;
    } else if (db > -12) {
      color = FluxForgeTheme.accentOrange;
    } else {
      color = FluxForgeTheme.accentGreen;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: normalized,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MONITOR SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMonitorSection(ControlRoomProvider controlRoom) {
    return _buildSection(
      title: 'MONITOR',
      child: Column(
        children: [
          // Source selector
          Row(
            children: [
              Text('Source:', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary.withOpacity(0.7))),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSourceDropdown(controlRoom),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Level + Dim + Mono
          Row(
            children: [
              // Level knob
              Expanded(
                child: _buildLevelControl(
                  label: 'Level',
                  value: controlRoom.monitorLevelDb,
                  onChanged: (v) => controlRoom.setMonitorLevelDb(v),
                  min: -60,
                  max: 12,
                ),
              ),
              const SizedBox(width: 8),

              // Dim button
              _buildToggleButton(
                label: 'DIM',
                active: controlRoom.dimEnabled,
                activeColor: FluxForgeTheme.accentOrange,
                onTap: () => controlRoom.setDim(!controlRoom.dimEnabled),
              ),
              const SizedBox(width: 4),

              // Mono button
              _buildToggleButton(
                label: 'MONO',
                active: controlRoom.monoEnabled,
                activeColor: FluxForgeTheme.accentBlue,
                onTap: () => controlRoom.setMono(!controlRoom.monoEnabled),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceDropdown(ControlRoomProvider controlRoom) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: FluxForgeTheme.bgSurface),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MonitorSource>(
          value: controlRoom.monitorSource,
          isDense: true,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: const TextStyle(fontSize: 10, color: FluxForgeTheme.textPrimary),
          items: MonitorSource.values.map((s) => DropdownMenuItem(
            value: s,
            child: Text(_sourceLabel(s)),
          )).toList(),
          onChanged: (v) {
            if (v != null) controlRoom.setMonitorSource(v);
          },
        ),
      ),
    );
  }

  String _sourceLabel(MonitorSource source) {
    switch (source) {
      case MonitorSource.master: return 'Master Bus';
      case MonitorSource.cue1: return 'Cue 1';
      case MonitorSource.cue2: return 'Cue 2';
      case MonitorSource.cue3: return 'Cue 3';
      case MonitorSource.cue4: return 'Cue 4';
      case MonitorSource.external1: return 'External 1';
      case MonitorSource.external2: return 'External 2';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEAKER SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSpeakerSection(ControlRoomProvider controlRoom) {
    final speakerNames = ['Main', 'Alt', 'Small', 'Phones'];

    return _buildSection(
      title: 'SPEAKERS',
      child: Row(
        children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
            child: _buildSpeakerButton(controlRoom, i, speakerNames[i]),
          ),
        )),
      ),
    );
  }

  Widget _buildSpeakerButton(ControlRoomProvider controlRoom, int index, String name) {
    final isActive = controlRoom.activeSpeakerSet == index;
    final calibration = controlRoom.getSpeakerLevelDb(index);

    return GestureDetector(
      onTap: () => controlRoom.setSpeakerSet(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgSurface,
          ),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isActive ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
              ),
            ),
            if (calibration != 0)
              Text(
                '${calibration > 0 ? '+' : ''}${calibration.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 8,
                  color: isActive
                      ? FluxForgeTheme.textSecondary
                      : FluxForgeTheme.textSecondary.withOpacity(0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOLO SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSoloSection(ControlRoomProvider controlRoom) {
    return _buildSection(
      title: 'SOLO MODE',
      child: Row(
        children: [
          _buildSoloButton(controlRoom, SoloMode.off, 'OFF'),
          const SizedBox(width: 4),
          _buildSoloButton(controlRoom, SoloMode.sip, 'SIP'),
          const SizedBox(width: 4),
          _buildSoloButton(controlRoom, SoloMode.afl, 'AFL'),
          const SizedBox(width: 4),
          _buildSoloButton(controlRoom, SoloMode.pfl, 'PFL'),
        ],
      ),
    );
  }

  Widget _buildSoloButton(ControlRoomProvider controlRoom, SoloMode mode, String label) {
    final isActive = controlRoom.soloMode == mode;
    final color = mode == SoloMode.off
        ? FluxForgeTheme.textSecondary
        : mode == SoloMode.sip
            ? FluxForgeTheme.accentRed
            : mode == SoloMode.afl
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.accentOrange;

    return Expanded(
      child: GestureDetector(
        onTap: () => controlRoom.setSoloMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.3) : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isActive ? color : FluxForgeTheme.bgSurface,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? color : FluxForgeTheme.textSecondary.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CUE MIXES SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCueMixesSection(ControlRoomProvider controlRoom) {
    return _buildSection(
      title: 'CUE MIXES',
      child: Column(
        children: List.generate(4, (i) => Padding(
          padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
          child: _buildCueMixRow(controlRoom, i),
        )),
      ),
    );
  }

  Widget _buildCueMixRow(ControlRoomProvider controlRoom, int index) {
    final enabled = controlRoom.getCueEnabled(index);
    final levelDb = controlRoom.getCueLevelDb(index);
    final pan = controlRoom.getCuePan(index);

    return Row(
      children: [
        // Enable button
        GestureDetector(
          onTap: () => controlRoom.setCueEnabled(index, !enabled),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: enabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: enabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.bgSurface,
              ),
            ),
            child: enabled
                ? const Icon(Icons.check, size: 12, color: FluxForgeTheme.textPrimary)
                : null,
          ),
        ),
        const SizedBox(width: 8),

        // Name
        SizedBox(
          width: 40,
          child: Text(
            'Cue ${index + 1}',
            style: TextStyle(
              fontSize: 10,
              color: enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary.withOpacity(0.5),
            ),
          ),
        ),

        // Level slider
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: enabled ? FluxForgeTheme.accentBlue : Colors.white24,
              inactiveTrackColor: FluxForgeTheme.bgSurface,
              thumbColor: enabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary.withOpacity(0.5),
            ),
            child: Slider(
              value: levelDb,
              min: -60,
              max: 12,
              onChanged: enabled ? (v) => controlRoom.setCueLevelDb(index, v) : null,
            ),
          ),
        ),

        // Level value
        SizedBox(
          width: 35,
          child: Text(
            '${levelDb.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 9,
              color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textSecondary.withOpacity(0.3),
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),

        // Mini meter (placeholder - no per-cue metering yet)
        _buildMiniMeter(0.0, 0.0),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALKBACK SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTalkbackSection(ControlRoomProvider controlRoom) {
    return _buildSection(
      title: 'TALKBACK',
      child: Column(
        children: [
          Row(
            children: [
              // Talk button (momentary)
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => controlRoom.setTalkback(true),
                  onTapUp: (_) => controlRoom.setTalkback(false),
                  onTapCancel: () => controlRoom.setTalkback(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: controlRoom.talkbackEnabled ? FluxForgeTheme.accentRed : FluxForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: controlRoom.talkbackEnabled ? FluxForgeTheme.accentRed : FluxForgeTheme.bgSurface,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          size: 16,
                          color: controlRoom.talkbackEnabled
                              ? FluxForgeTheme.textPrimary
                              : FluxForgeTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TALK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: controlRoom.talkbackEnabled
                                ? FluxForgeTheme.textPrimary
                                : FluxForgeTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Destinations
          Row(
            children: [
              Text('To:', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary.withOpacity(0.5))),
              const SizedBox(width: 8),
              ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildTalkbackDestButton(controlRoom, i),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTalkbackDestButton(ControlRoomProvider controlRoom, int index) {
    final active = controlRoom.isTalkbackDestination(index);

    return GestureDetector(
      onTap: () => controlRoom.toggleTalkbackDestination(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentBlue.withOpacity(0.3) : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.bgSurface,
          ),
        ),
        child: Text(
          'C${index + 1}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary.withOpacity(0.5),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.3) : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.bgSurface,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: active ? activeColor : FluxForgeTheme.textSecondary.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelControl({
    required String label,
    required double value,
    required ValueChanged<double>? onChanged,
    double min = -60,
    double max = 12,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary.withOpacity(0.5))),
            Text(
              '${value.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: FluxForgeTheme.accentBlue,
            inactiveTrackColor: FluxForgeTheme.bgSurface,
            thumbColor: FluxForgeTheme.accentBlue,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

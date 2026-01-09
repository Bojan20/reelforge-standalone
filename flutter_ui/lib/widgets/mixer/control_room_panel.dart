/// Control Room Panel - Professional Monitor Mixer
///
/// Full control room with:
/// - Monitor source selection (Master, Cue 1-4, External)
/// - Monitor level + Dim + Mono
/// - Speaker selection (up to 4 sets)
/// - Solo modes (SIP, AFL, PFL)
/// - 4 Cue/Headphone mixes
/// - Talkback

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Monitor source
enum MonitorSource { master, cue1, cue2, cue3, cue4, external1, external2 }

/// Solo mode
enum SoloMode { off, sip, afl, pfl }

/// Cue mix data
class CueMixData {
  final String name;
  final bool enabled;
  final double level;
  final double pan;
  final double peakL;
  final double peakR;

  const CueMixData({
    required this.name,
    this.enabled = false,
    this.level = 1.0,
    this.pan = 0.0,
    this.peakL = 0.0,
    this.peakR = 0.0,
  });

  CueMixData copyWith({
    String? name,
    bool? enabled,
    double? level,
    double? pan,
    double? peakL,
    double? peakR,
  }) => CueMixData(
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    level: level ?? this.level,
    pan: pan ?? this.pan,
    peakL: peakL ?? this.peakL,
    peakR: peakR ?? this.peakR,
  );
}

/// Speaker set data
class SpeakerSetData {
  final String name;
  final double calibration; // dB offset
  final bool active;

  const SpeakerSetData({
    required this.name,
    this.calibration = 0.0,
    this.active = false,
  });
}

/// Talkback data
class TalkbackData {
  final bool enabled;
  final double level;
  final List<bool> destinations; // Which cue mixes receive talkback
  final bool dimMainOnTalk;

  const TalkbackData({
    this.enabled = false,
    this.level = 1.0,
    this.destinations = const [true, true, true, true],
    this.dimMainOnTalk = true,
  });
}

/// Full control room state
class ControlRoomState {
  final MonitorSource source;
  final double monitorLevel; // dB
  final bool dimEnabled;
  final double dimLevel; // dB (typically -20)
  final bool monoEnabled;
  final int activeSpeakerSet; // 0-3
  final List<SpeakerSetData> speakerSets;
  final SoloMode soloMode;
  final List<CueMixData> cueMixes;
  final TalkbackData talkback;
  final double monitorPeakL;
  final double monitorPeakR;

  const ControlRoomState({
    this.source = MonitorSource.master,
    this.monitorLevel = 0.0,
    this.dimEnabled = false,
    this.dimLevel = -20.0,
    this.monoEnabled = false,
    this.activeSpeakerSet = 0,
    this.speakerSets = const [
      SpeakerSetData(name: 'Main', active: true),
      SpeakerSetData(name: 'Alt'),
      SpeakerSetData(name: 'Small'),
      SpeakerSetData(name: 'Phones'),
    ],
    this.soloMode = SoloMode.off,
    this.cueMixes = const [
      CueMixData(name: 'Cue 1'),
      CueMixData(name: 'Cue 2'),
      CueMixData(name: 'Cue 3'),
      CueMixData(name: 'Cue 4'),
    ],
    this.talkback = const TalkbackData(),
    this.monitorPeakL = 0.0,
    this.monitorPeakR = 0.0,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL ROOM PANEL
// ═══════════════════════════════════════════════════════════════════════════

class ControlRoomPanel extends StatefulWidget {
  final ControlRoomState state;
  final ValueChanged<ControlRoomState>? onStateChanged;
  final ValueChanged<MonitorSource>? onSourceChanged;
  final ValueChanged<double>? onMonitorLevelChanged;
  final ValueChanged<bool>? onDimToggled;
  final ValueChanged<bool>? onMonoToggled;
  final ValueChanged<int>? onSpeakerSetChanged;
  final ValueChanged<SoloMode>? onSoloModeChanged;
  final Function(int, CueMixData)? onCueMixChanged;
  final ValueChanged<TalkbackData>? onTalkbackChanged;

  const ControlRoomPanel({
    super.key,
    required this.state,
    this.onStateChanged,
    this.onSourceChanged,
    this.onMonitorLevelChanged,
    this.onDimToggled,
    this.onMonoToggled,
    this.onSpeakerSetChanged,
    this.onSoloModeChanged,
    this.onCueMixChanged,
    this.onTalkbackChanged,
  });

  @override
  State<ControlRoomPanel> createState() => _ControlRoomPanelState();
}

class _ControlRoomPanelState extends State<ControlRoomPanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const Divider(height: 1, color: Colors.white10),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // Monitor Section
                    _buildMonitorSection(),
                    const SizedBox(height: 12),

                    // Speaker Selection
                    _buildSpeakerSection(),
                    const SizedBox(height: 12),

                    // Solo Mode
                    _buildSoloSection(),
                    const SizedBox(height: 12),

                    // Cue Mixes
                    _buildCueMixesSection(),
                    const SizedBox(height: 12),

                    // Talkback
                    _buildTalkbackSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF242430),
      child: Row(
        children: [
          const Icon(Icons.speaker, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          const Text(
            'CONTROL ROOM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Monitor meter mini
          _buildMiniMeter(widget.state.monitorPeakL, widget.state.monitorPeakR),
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
      color = Colors.red;
    } else if (db > -12) {
      color = Colors.yellow;
    } else {
      color = Colors.green;
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

  Widget _buildMonitorSection() {
    return _buildSection(
      title: 'MONITOR',
      child: Column(
        children: [
          // Source selector
          Row(
            children: [
              const Text('Source:', style: TextStyle(fontSize: 10, color: Colors.white54)),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSourceDropdown(),
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
                  value: widget.state.monitorLevel,
                  onChanged: widget.onMonitorLevelChanged,
                  min: -60,
                  max: 12,
                ),
              ),
              const SizedBox(width: 8),

              // Dim button
              _buildToggleButton(
                label: 'DIM',
                active: widget.state.dimEnabled,
                activeColor: Colors.orange,
                onTap: () => widget.onDimToggled?.call(!widget.state.dimEnabled),
              ),
              const SizedBox(width: 4),

              // Mono button
              _buildToggleButton(
                label: 'MONO',
                active: widget.state.monoEnabled,
                activeColor: Colors.blue,
                onTap: () => widget.onMonoToggled?.call(!widget.state.monoEnabled),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceDropdown() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MonitorSource>(
          value: widget.state.source,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF2A2A36),
          style: const TextStyle(fontSize: 10, color: Colors.white),
          items: MonitorSource.values.map((s) => DropdownMenuItem(
            value: s,
            child: Text(_sourceLabel(s)),
          )).toList(),
          onChanged: (v) {
            if (v != null) widget.onSourceChanged?.call(v);
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

  Widget _buildSpeakerSection() {
    return _buildSection(
      title: 'SPEAKERS',
      child: Row(
        children: List.generate(4, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
            child: _buildSpeakerButton(i),
          ),
        )),
      ),
    );
  }

  Widget _buildSpeakerButton(int index) {
    final speaker = widget.state.speakerSets[index];
    final isActive = widget.state.activeSpeakerSet == index;

    return GestureDetector(
      onTap: () => widget.onSpeakerSetChanged?.call(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF4A9EFF) : Colors.black26,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? const Color(0xFF4A9EFF) : Colors.white10,
          ),
        ),
        child: Column(
          children: [
            Text(
              speaker.name,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : Colors.white54,
              ),
            ),
            if (speaker.calibration != 0)
              Text(
                '${speaker.calibration > 0 ? '+' : ''}${speaker.calibration.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 8,
                  color: isActive ? Colors.white70 : Colors.white38,
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

  Widget _buildSoloSection() {
    return _buildSection(
      title: 'SOLO MODE',
      child: Row(
        children: [
          _buildSoloButton(SoloMode.off, 'OFF'),
          const SizedBox(width: 4),
          _buildSoloButton(SoloMode.sip, 'SIP'),
          const SizedBox(width: 4),
          _buildSoloButton(SoloMode.afl, 'AFL'),
          const SizedBox(width: 4),
          _buildSoloButton(SoloMode.pfl, 'PFL'),
        ],
      ),
    );
  }

  Widget _buildSoloButton(SoloMode mode, String label) {
    final isActive = widget.state.soloMode == mode;
    final color = mode == SoloMode.off
        ? Colors.white54
        : mode == SoloMode.sip
            ? Colors.red
            : mode == SoloMode.afl
                ? Colors.green
                : Colors.yellow;

    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onSoloModeChanged?.call(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.3) : Colors.black26,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isActive ? color : Colors.white10,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? color : Colors.white38,
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

  Widget _buildCueMixesSection() {
    return _buildSection(
      title: 'CUE MIXES',
      child: Column(
        children: List.generate(4, (i) => Padding(
          padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
          child: _buildCueMixRow(i),
        )),
      ),
    );
  }

  Widget _buildCueMixRow(int index) {
    final cue = widget.state.cueMixes[index];

    return Row(
      children: [
        // Enable button
        GestureDetector(
          onTap: () {
            widget.onCueMixChanged?.call(
              index,
              cue.copyWith(enabled: !cue.enabled),
            );
          },
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: cue.enabled ? const Color(0xFF40FF90) : Colors.black26,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: cue.enabled ? const Color(0xFF40FF90) : Colors.white10,
              ),
            ),
            child: cue.enabled
                ? const Icon(Icons.check, size: 12, color: Colors.black)
                : null,
          ),
        ),
        const SizedBox(width: 8),

        // Name
        SizedBox(
          width: 40,
          child: Text(
            cue.name,
            style: TextStyle(
              fontSize: 10,
              color: cue.enabled ? Colors.white : Colors.white38,
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
              activeTrackColor: cue.enabled ? const Color(0xFF4A9EFF) : Colors.white24,
              inactiveTrackColor: Colors.white10,
              thumbColor: cue.enabled ? const Color(0xFF4A9EFF) : Colors.white38,
            ),
            child: Slider(
              value: cue.level,
              min: 0,
              max: 1,
              onChanged: cue.enabled ? (v) {
                widget.onCueMixChanged?.call(index, cue.copyWith(level: v));
              } : null,
            ),
          ),
        ),

        // Level value
        SizedBox(
          width: 35,
          child: Text(
            cue.level > 0
                ? '${(20 * math.log(cue.level) / math.ln10).toStringAsFixed(1)}'
                : '-∞',
            style: TextStyle(
              fontSize: 9,
              color: cue.enabled ? Colors.white54 : Colors.white24,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),

        // Mini meter
        _buildMiniMeter(cue.peakL, cue.peakR),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALKBACK SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTalkbackSection() {
    final tb = widget.state.talkback;

    return _buildSection(
      title: 'TALKBACK',
      child: Column(
        children: [
          Row(
            children: [
              // Talk button (momentary)
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => _setTalkbackEnabled(true),
                  onTapUp: (_) => _setTalkbackEnabled(false),
                  onTapCancel: () => _setTalkbackEnabled(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: tb.enabled ? Colors.red : const Color(0xFF3A3A46),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tb.enabled ? Colors.red : Colors.white10,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          size: 16,
                          color: tb.enabled ? Colors.white : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TALK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: tb.enabled ? Colors.white : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Dim main checkbox
              GestureDetector(
                onTap: () {
                  widget.onTalkbackChanged?.call(TalkbackData(
                    enabled: tb.enabled,
                    level: tb.level,
                    destinations: tb.destinations,
                    dimMainOnTalk: !tb.dimMainOnTalk,
                  ));
                },
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: tb.dimMainOnTalk ? const Color(0xFF4A9EFF) : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: tb.dimMainOnTalk
                          ? const Icon(Icons.check, size: 10, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Dim Main',
                      style: TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Destinations
          Row(
            children: [
              const Text('To:', style: TextStyle(fontSize: 9, color: Colors.white38)),
              const SizedBox(width: 8),
              ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildTalkbackDestButton(i),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTalkbackDestButton(int index) {
    final tb = widget.state.talkback;
    final active = tb.destinations[index];

    return GestureDetector(
      onTap: () {
        final newDests = List<bool>.from(tb.destinations);
        newDests[index] = !active;
        widget.onTalkbackChanged?.call(TalkbackData(
          enabled: tb.enabled,
          level: tb.level,
          destinations: newDests,
          dimMainOnTalk: tb.dimMainOnTalk,
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4A9EFF).withOpacity(0.3) : Colors.black26,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? const Color(0xFF4A9EFF) : Colors.white10,
          ),
        ),
        child: Text(
          'C${index + 1}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: active ? const Color(0xFF4A9EFF) : Colors.white38,
          ),
        ),
      ),
    );
  }

  void _setTalkbackEnabled(bool enabled) {
    final tb = widget.state.talkback;
    widget.onTalkbackChanged?.call(TalkbackData(
      enabled: enabled,
      level: tb.level,
      destinations: tb.destinations,
      dimMainOnTalk: tb.dimMainOnTalk,
    ));
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
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
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
          color: active ? activeColor.withOpacity(0.3) : Colors.black26,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: active ? activeColor : Colors.white38,
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
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
            Text(
              '${value.toStringAsFixed(1)} dB',
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: const Color(0xFF4A9EFF),
            inactiveTrackColor: Colors.white10,
            thumbColor: const Color(0xFF4A9EFF),
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

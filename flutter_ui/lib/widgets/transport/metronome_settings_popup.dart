// Ultimate Metronome Settings Popup
//
// Pro Tools-level metronome configuration:
// - 12 click sound presets (Sine, Woodblock, Rimshot, Cowbell, etc.)
// - Per-sound volumes (Accent, Beat, Subdivision)
// - Master volume + pan
// - Click pattern (Quarter, Eighth, Sixteenth, Triplet, Downbeat Only)
// - Count-in mode (Off, 1 Bar, 2 Bars, 4 Beats)
// - Count-in visual beat indicator
// - Audibility mode (Always, Record Only, Count-In Only)
// - Tap tempo
// - Tempo slider + numeric display
// - Time signature selector
// - Enable/disable toggle

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Show metronome settings popup anchored below [anchor].
Future<void> showMetronomeSettings(
  BuildContext context, {
  required Offset anchor,
  required bool enabled,
  required VoidCallback onToggle,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _MetronomeSettingsDialog(
      anchor: anchor,
      enabled: enabled,
      onToggle: onToggle,
    ),
  );
}

class _MetronomeSettingsDialog extends StatefulWidget {
  final Offset anchor;
  final bool enabled;
  final VoidCallback onToggle;

  const _MetronomeSettingsDialog({
    required this.anchor,
    required this.enabled,
    required this.onToggle,
  });

  @override
  State<_MetronomeSettingsDialog> createState() =>
      _MetronomeSettingsDialogState();
}

class _MetronomeSettingsDialogState extends State<_MetronomeSettingsDialog> {
  // ── Core state ──
  late bool _enabled;
  double _volume = 0.7;
  int _pattern = 0;
  int _countIn = 0;
  double _pan = 0.0;
  double _tempo = 120.0;
  int _beatsPerBar = 4;

  // ── New state ──
  double _accentVolume = 1.0;
  double _beatVolume = 0.7;
  double _subdivisionVolume = 0.4;
  int _preset = 0;
  int _audibilityMode = 0; // 0=Always, 1=RecordOnly, 2=CountInOnly
  bool _countInActive = false;
  int _countInBeat = -1;

  // ── Count-in poll timer ──
  Timer? _countInPollTimer;

  // ── Collapsed sections ──
  bool _soundExpanded = false;

  static const _patternLabels = [
    '♩ Quarter',
    '♪ Eighth',
    '♬ Sixteenth',
    '𝅘𝅥𝅮 Triplet',
    '● Downbeat',
  ];

  static const _countInLabels = [
    'Off',
    '1 Bar',
    '2 Bars',
    '4 Beats',
  ];

  static const _presetLabels = [
    'Sine',
    'Woodblock',
    'Rimshot',
    'Cowbell',
    'Marimba',
    'Sticks',
    'Clave',
    'Beep',
    'Click',
    'SideStick',
    'HiHat',
    'Metronome',
  ];

  static const _audibilityLabels = [
    'Always',
    'Record',
    'Count-In',
  ];

  @override
  void initState() {
    super.initState();
    final ffi = NativeFFI.instance;
    _enabled = ffi.clickIsEnabled();
    _volume = ffi.clickGetVolume();
    _pattern = ffi.clickGetPattern();
    _countIn = ffi.clickGetCountIn();
    _pan = ffi.clickGetPan();
    _tempo = ffi.clickGetTempo();
    _beatsPerBar = ffi.clickGetBeatsPerBar();
    _accentVolume = ffi.clickGetAccentVolume();
    _beatVolume = ffi.clickGetBeatVolume();
    _subdivisionVolume = ffi.clickGetSubdivisionVolume();
    _preset = ffi.clickGetPreset();
    _audibilityMode = ffi.clickGetAudibilityMode();
    _countInActive = ffi.clickIsCountInActive();
    _countInBeat = ffi.clickGetCountInBeat();

    // Poll count-in status while active
    _countInPollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _pollCountIn(),
    );
  }

  @override
  void dispose() {
    _countInPollTimer?.cancel();
    super.dispose();
  }

  void _pollCountIn() {
    final wasActive = _countInActive;
    final active = NativeFFI.instance.clickIsCountInActive();
    final beat = NativeFFI.instance.clickGetCountInBeat();
    if (active != _countInActive || beat != _countInBeat) {
      setState(() {
        _countInActive = active;
        _countInBeat = beat;
      });
    }
    // Auto-stop polling if count-in just ended
    if (wasActive && !active) {
      setState(() {
        _countInActive = false;
        _countInBeat = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = 320.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final left = (widget.anchor.dx - panelWidth / 2).clamp(8.0, screenWidth - panelWidth - 8);
    final top = widget.anchor.dy + 8;

    return Stack(
      children: [
        // Dismiss on tap outside
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: screenHeight - top - 16,
              ),
              child: Container(
                width: panelWidth,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: FluxForgeTheme.borderSubtle,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const Divider(height: 1, color: Color(0xFF333340)),
                      // Count-in progress bar (conditional)
                      if (_countInActive) _buildCountInProgress(),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── TIMING ──
                            _buildSectionHeader('TIMING'),
                            const SizedBox(height: 8),
                            _buildTempoWithTap(),
                            const SizedBox(height: 10),
                            _buildTimeSigSelector(),
                            const SizedBox(height: 10),
                            _buildPatternSelector(),
                            const SizedBox(height: 10),
                            _buildCountInSelector(),

                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFF333340)),
                            const SizedBox(height: 14),

                            // ── SOUND ──
                            _buildSectionHeader('SOUND', collapsible: true, expanded: _soundExpanded, onToggle: () {
                              setState(() => _soundExpanded = !_soundExpanded);
                            }),
                            const SizedBox(height: 8),
                            _buildPresetBrowser(),
                            if (_soundExpanded) ...[
                              const SizedBox(height: 10),
                              _buildPerSoundVolumes(),
                            ],
                            const SizedBox(height: 10),
                            _buildMasterVolumeSlider(),

                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFF333340)),
                            const SizedBox(height: 14),

                            // ── BEHAVIOR ──
                            _buildSectionHeader('BEHAVIOR'),
                            const SizedBox(height: 8),
                            _buildPanSlider(),
                            const SizedBox(height: 10),
                            _buildAudibilityMode(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.timer,
            size: 16,
            color: _enabled
                ? FluxForgeTheme.accentOrange
                : FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            'METRONOME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          const Spacer(),
          // Tap tempo button
          _buildTapTempoButton(),
          const SizedBox(width: 8),
          // Enable/disable toggle
          _buildToggleSwitch(),
        ],
      ),
    );
  }

  Widget _buildTapTempoButton() {
    return GestureDetector(
      onTap: () {
        final bpm = NativeFFI.instance.clickTapTempo();
        if (bpm > 0) {
          setState(() => _tempo = bpm.roundToDouble());
          // Don't call clickSetTempo — tap_tempo already sets it in Rust
        }
        HapticFeedback.lightImpact();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: const Color(0xFF2A2A35),
          border: Border.all(color: const Color(0xFF444450), width: 1),
        ),
        child: Text(
          'TAP',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch() {
    return GestureDetector(
      onTap: () {
        setState(() => _enabled = !_enabled);
        NativeFFI.instance.clickSetEnabled(_enabled);
        widget.onToggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: _enabled
              ? FluxForgeTheme.accentOrange
              : const Color(0xFF444450),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: _enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COUNT-IN PROGRESS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCountInProgress() {
    return Container(
      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Beat dots
          ...List.generate(_beatsPerBar, (i) {
            final isCurrentBeat = i == _countInBeat;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: isCurrentBeat ? 14 : 10,
                height: isCurrentBeat ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrentBeat
                      ? FluxForgeTheme.accentOrange
                      : (i < _countInBeat
                          ? FluxForgeTheme.accentBlue.withValues(alpha: 0.6)
                          : const Color(0xFF444450)),
                  boxShadow: isCurrentBeat
                      ? [
                          BoxShadow(
                            color: FluxForgeTheme.accentOrange.withValues(alpha: 0.5),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
              ),
            );
          }),
          const Spacer(),
          // Beat number
          Text(
            '${_countInBeat + 1}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'JetBrains Mono',
              color: FluxForgeTheme.accentOrange,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'COUNT-IN',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: FluxForgeTheme.accentBlue,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTempoWithTap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('Tempo'),
            const Spacer(),
            Text(
              '${_tempo.round()} BPM',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: _sliderTheme(context),
          child: Slider(
            value: _tempo.clamp(20.0, 300.0),
            min: 20.0,
            max: 300.0,
            onChanged: (v) {
              setState(() => _tempo = v.roundToDouble());
              NativeFFI.instance.clickSetTempo(v.roundToDouble());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSigSelector() {
    const timeSigOptions = [2, 3, 4, 5, 6, 7];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Time Signature'),
        const SizedBox(height: 6),
        Row(
          children: timeSigOptions.map((beats) {
            final isSelected = _beatsPerBar == beats;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _beatsPerBar = beats);
                  NativeFFI.instance.clickSetBeatsPerBar(beats);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.only(
                    right: beats != timeSigOptions.last ? 4 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: isSelected
                        ? FluxForgeTheme.accentOrange.withValues(alpha: 0.25)
                        : const Color(0xFF2A2A35),
                    border: Border.all(
                      color: isSelected
                          ? FluxForgeTheme.accentOrange
                          : const Color(0xFF444450),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$beats/4',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPatternSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Click Pattern'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List.generate(_patternLabels.length, (i) {
            final isSelected = _pattern == i;
            return GestureDetector(
              onTap: () {
                setState(() => _pattern = i);
                NativeFFI.instance.clickSetPattern(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isSelected
                      ? FluxForgeTheme.accentOrange.withValues(alpha: 0.25)
                      : const Color(0xFF2A2A35),
                  border: Border.all(
                    color: isSelected
                        ? FluxForgeTheme.accentOrange
                        : const Color(0xFF444450),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  _patternLabels[i],
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCountInSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Count-In'),
        const SizedBox(height: 6),
        Row(
          children: List.generate(_countInLabels.length, (i) {
            final isSelected = _countIn == i;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _countIn = i);
                  NativeFFI.instance.clickSetCountIn(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: isSelected
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.25)
                        : const Color(0xFF2A2A35),
                    border: Border.all(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue
                          : const Color(0xFF444450),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _countInLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUND SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPresetBrowser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Preset'),
        const SizedBox(height: 6),
        SizedBox(
          height: 28,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _presetLabels.length,
            itemBuilder: (context, i) {
              final isSelected = _preset == i;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _preset = i);
                    NativeFFI.instance.clickSetPreset(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isSelected
                          ? FluxForgeTheme.accentOrange.withValues(alpha: 0.25)
                          : const Color(0xFF2A2A35),
                      border: Border.all(
                        color: isSelected
                            ? FluxForgeTheme.accentOrange
                            : const Color(0xFF444450),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      _presetLabels[i],
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? FluxForgeTheme.accentOrange
                            : FluxForgeTheme.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerSoundVolumes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMiniSlider(
          label: 'Accent',
          icon: '♩₁',
          value: _accentVolume,
          color: FluxForgeTheme.accentOrange,
          onChanged: (v) {
            setState(() => _accentVolume = v);
            NativeFFI.instance.clickSetAccentVolume(v);
          },
        ),
        const SizedBox(height: 6),
        _buildMiniSlider(
          label: 'Beat',
          icon: '♩',
          value: _beatVolume,
          color: FluxForgeTheme.textPrimary,
          onChanged: (v) {
            setState(() => _beatVolume = v);
            NativeFFI.instance.clickSetBeatVolume(v);
          },
        ),
        const SizedBox(height: 6),
        _buildMiniSlider(
          label: 'Sub',
          icon: '♬',
          value: _subdivisionVolume,
          color: FluxForgeTheme.textSecondary,
          onChanged: (v) {
            setState(() => _subdivisionVolume = v);
            NativeFFI.instance.clickSetSubdivisionVolume(v);
          },
        ),
      ],
    );
  }

  Widget _buildMiniSlider({
    required String label,
    required String icon,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            icon,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: color,
              inactiveTrackColor: const Color(0xFF333340),
              thumbColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              overlayColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textSecondary,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterVolumeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('Master Volume'),
            const Spacer(),
            Text(
              '${(_volume * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: _sliderTheme(context),
          child: Slider(
            value: _volume,
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _volume = v);
              NativeFFI.instance.clickSetVolume(v);
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BEHAVIOR SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPanSlider() {
    String panLabel;
    if (_pan < -0.01) {
      panLabel = 'L${(-_pan * 100).round()}';
    } else if (_pan > 0.01) {
      panLabel = 'R${(_pan * 100).round()}';
    } else {
      panLabel = 'C';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('Pan'),
            const Spacer(),
            Text(
              panLabel,
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: _sliderTheme(context),
          child: Slider(
            value: _pan,
            min: -1.0,
            max: 1.0,
            onChanged: (v) {
              setState(() => _pan = v);
              NativeFFI.instance.clickSetPan(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAudibilityMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Audibility'),
        const SizedBox(height: 6),
        Row(
          children: List.generate(_audibilityLabels.length, (i) {
            final isSelected = _audibilityMode == i;
            final color = i == 0
                ? FluxForgeTheme.accentOrange
                : (i == 1
                    ? const Color(0xFFFF4060) // red for record
                    : FluxForgeTheme.accentBlue); // cyan for count-in
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _audibilityMode = i);
                  NativeFFI.instance.clickSetAudibilityMode(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: isSelected
                        ? color.withValues(alpha: 0.25)
                        : const Color(0xFF2A2A35),
                    border: Border.all(
                      color: isSelected ? color : const Color(0xFF444450),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _audibilityLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? color : FluxForgeTheme.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String text, {
    bool collapsible = false,
    bool expanded = false,
    VoidCallback? onToggle,
  }) {
    return GestureDetector(
      onTap: collapsible ? onToggle : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
          if (collapsible) ...[
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: FluxForgeTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderThemeData(
      trackHeight: 3,
      activeTrackColor: FluxForgeTheme.accentOrange,
      inactiveTrackColor: const Color(0xFF333340),
      thumbColor: FluxForgeTheme.textPrimary,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      overlayColor: FluxForgeTheme.accentOrange.withValues(alpha: 0.15),
    );
  }
}

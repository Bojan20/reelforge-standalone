// Metronome Settings Popup
//
// Pro DAW-style metronome configuration:
// - Volume slider
// - Click pattern (Quarter, Eighth, Sixteenth, Triplet, Downbeat Only)
// - Count-in mode (Off, 1 Bar, 2 Bars, 4 Beats)
// - Pan control
// - Enable/disable toggle

import 'package:flutter/material.dart';
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
  late bool _enabled;
  double _volume = 0.7;
  int _pattern = 0; // 0=Quarter, 1=Eighth, 2=Sixteenth, 3=Triplet, 4=DownbeatOnly
  int _countIn = 0; // 0=Off, 1=OneBar, 2=TwoBars, 3=FourBeats
  double _pan = 0.0;
  double _tempo = 120.0;
  int _beatsPerBar = 4;
  bool _onlyDuringRecord = false;

  static const _patternLabels = [
    '♩ Quarter',
    '♪ Eighth',
    '♬ Sixteenth',
    '𝅘𝅥𝅮 Triplet',
    '● Downbeat Only',
  ];

  static const _countInLabels = [
    'Off',
    '1 Bar',
    '2 Bars',
    '4 Beats',
  ];

  @override
  void initState() {
    super.initState();
    // Read ALL current state from engine
    _enabled = NativeFFI.instance.clickIsEnabled();
    _volume = NativeFFI.instance.clickGetVolume();
    _pattern = NativeFFI.instance.clickGetPattern();
    _countIn = NativeFFI.instance.clickGetCountIn();
    _pan = NativeFFI.instance.clickGetPan();
    _tempo = NativeFFI.instance.clickGetTempo();
    _beatsPerBar = NativeFFI.instance.clickGetBeatsPerBar();
    _onlyDuringRecord = NativeFFI.instance.clickGetOnlyDuringRecord();
  }

  @override
  Widget build(BuildContext context) {
    // Position popup below the metronome button
    final panelWidth = 280.0;
    final left = (widget.anchor.dx - panelWidth / 2).clamp(8.0, MediaQuery.of(context).size.width - panelWidth - 8);
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const Divider(height: 1, color: Color(0xFF333340)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTempoControl(),
                        const SizedBox(height: 12),
                        _buildTimeSigSelector(),
                        const SizedBox(height: 12),
                        _buildVolumeSlider(),
                        const SizedBox(height: 12),
                        _buildPatternSelector(),
                        const SizedBox(height: 12),
                        _buildCountInSelector(),
                        const SizedBox(height: 12),
                        _buildPanSlider(),
                        const SizedBox(height: 12),
                        _buildOnlyDuringRecordToggle(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

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
          GestureDetector(
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
                alignment:
                    _enabled ? Alignment.centerRight : Alignment.centerLeft,
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
          ),
        ],
      ),
    );
  }

  Widget _buildTempoControl() {
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
            value: _tempo,
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

  Widget _buildVolumeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('Volume'),
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

  Widget _buildOnlyDuringRecordToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _onlyDuringRecord = !_onlyDuringRecord);
        NativeFFI.instance.clickSetOnlyDuringRecord(_onlyDuringRecord);
      },
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: _onlyDuringRecord
                  ? FluxForgeTheme.accentOrange.withValues(alpha: 0.25)
                  : const Color(0xFF2A2A35),
              border: Border.all(
                color: _onlyDuringRecord
                    ? FluxForgeTheme.accentOrange
                    : const Color(0xFF444450),
                width: _onlyDuringRecord ? 1.5 : 1,
              ),
            ),
            child: _onlyDuringRecord
                ? Icon(Icons.check, size: 12, color: FluxForgeTheme.accentOrange)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            'Only During Recording',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: _onlyDuringRecord
                  ? FluxForgeTheme.textPrimary
                  : FluxForgeTheme.textSecondary,
            ),
          ),
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

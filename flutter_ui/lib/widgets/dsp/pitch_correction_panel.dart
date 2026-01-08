/// Pitch Correction Panel - Auto-Tune Style Pitch Correction UI
///
/// Professional pitch correction with:
/// - Scale/Key selection
/// - Speed control (natural to robotic)
/// - Amount control
/// - Vibrato preservation
/// - Formant preservation
/// - Keyboard display showing active notes

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

class PitchCorrectionPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const PitchCorrectionPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<PitchCorrectionPanel> createState() => _PitchCorrectionPanelState();
}

class _PitchCorrectionPanelState extends State<PitchCorrectionPanel> {
  final _ffi = NativeFFI.instance;

  // Settings
  PitchScale _scale = PitchScale.chromatic;
  PitchRoot _root = PitchRoot.c;
  double _speed = 0.5;
  double _amount = 1.0;
  bool _preserveVibrato = true;
  double _formantPreservation = 1.0;
  bool _bypass = false;

  // Note names
  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  static const _scaleNames = [
    'Chromatic', 'Major', 'Minor', 'Harmonic Minor',
    'Pentatonic Major', 'Pentatonic Minor', 'Blues', 'Dorian', 'Custom'
  ];

  // Scale intervals (semitones from root)
  static const _scaleIntervals = <PitchScale, List<int>>{
    PitchScale.chromatic: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    PitchScale.major: [0, 2, 4, 5, 7, 9, 11],
    PitchScale.minor: [0, 2, 3, 5, 7, 8, 10],
    PitchScale.harmonicMinor: [0, 2, 3, 5, 7, 8, 11],
    PitchScale.pentatonicMajor: [0, 2, 4, 7, 9],
    PitchScale.pentatonicMinor: [0, 3, 5, 7, 10],
    PitchScale.blues: [0, 3, 5, 6, 7, 10],
    PitchScale.dorian: [0, 2, 3, 5, 7, 9, 10],
    PitchScale.custom: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  };

  @override
  void initState() {
    super.initState();
    _ffi.pitchCorrectorCreate(widget.trackId);
    _syncToEngine();
  }

  @override
  void dispose() {
    _ffi.pitchCorrectorDestroy(widget.trackId);
    super.dispose();
  }

  void _syncToEngine() {
    _ffi.pitchCorrectorSetScale(widget.trackId, _scale);
    _ffi.pitchCorrectorSetRoot(widget.trackId, _root);
    _ffi.pitchCorrectorSetSpeed(widget.trackId, _speed);
    _ffi.pitchCorrectorSetAmount(widget.trackId, _amount);
    _ffi.pitchCorrectorSetPreserveVibrato(widget.trackId, _preserveVibrato);
    _ffi.pitchCorrectorSetFormantPreservation(widget.trackId, _formantPreservation);
    widget.onSettingsChanged?.call();
  }

  bool _isNoteInScale(int note) {
    final intervals = _scaleIntervals[_scale] ?? [];
    final rootIndex = _root.index;
    final interval = (note - rootIndex + 12) % 12;
    return intervals.contains(interval);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          // Main content
          Expanded(
            child: Row(
              children: [
                // Left panel - Controls
                Expanded(
                  flex: 2,
                  child: _buildControlsPanel(),
                ),
                VerticalDivider(width: 1, color: ReelForgeTheme.borderSubtle),
                // Right panel - Keyboard
                Expanded(
                  flex: 3,
                  child: _buildKeyboardPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.music_note, color: ReelForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 8),
          Text(
            'PITCH CORRECTION',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Bypass button
          GestureDetector(
            onTap: () {
              setState(() => _bypass = !_bypass);
              _ffi.pitchCorrectorSetAmount(widget.trackId, _bypass ? 0.0 : _amount);
              widget.onSettingsChanged?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _bypass ? ReelForgeTheme.accentRed : ReelForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _bypass ? ReelForgeTheme.accentRed : ReelForgeTheme.borderMedium,
                ),
              ),
              child: Text(
                'BYPASS',
                style: TextStyle(
                  color: _bypass ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scale Selection
          _buildSectionTitle('SCALE'),
          const SizedBox(height: 8),
          _buildDropdown<PitchScale>(
            value: _scale,
            items: PitchScale.values,
            labels: _scaleNames,
            onChanged: (v) {
              setState(() => _scale = v);
              _ffi.pitchCorrectorSetScale(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 16),

          // Root Note Selection
          _buildSectionTitle('KEY'),
          const SizedBox(height: 8),
          _buildDropdown<PitchRoot>(
            value: _root,
            items: PitchRoot.values,
            labels: _noteNames,
            onChanged: (v) {
              setState(() => _root = v);
              _ffi.pitchCorrectorSetRoot(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 24),

          // Speed Control
          _buildSliderControl(
            label: 'SPEED',
            value: _speed,
            min: 0.0,
            max: 1.0,
            leftLabel: 'Natural',
            rightLabel: 'Robotic',
            color: ReelForgeTheme.accentCyan,
            onChanged: (v) {
              setState(() => _speed = v);
              _ffi.pitchCorrectorSetSpeed(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 16),

          // Amount Control
          _buildSliderControl(
            label: 'AMOUNT',
            value: _amount,
            min: 0.0,
            max: 1.0,
            leftLabel: 'Off',
            rightLabel: 'Full',
            color: ReelForgeTheme.accentBlue,
            onChanged: (v) {
              setState(() => _amount = v);
              if (!_bypass) {
                _ffi.pitchCorrectorSetAmount(widget.trackId, v);
              }
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 16),

          // Formant Preservation
          _buildSliderControl(
            label: 'FORMANT',
            value: _formantPreservation,
            min: 0.0,
            max: 1.0,
            leftLabel: 'Off',
            rightLabel: 'Full',
            color: ReelForgeTheme.accentOrange,
            onChanged: (v) {
              setState(() => _formantPreservation = v);
              _ffi.pitchCorrectorSetFormantPreservation(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 24),

          // Vibrato Toggle
          _buildToggle(
            label: 'PRESERVE VIBRATO',
            value: _preserveVibrato,
            onChanged: (v) {
              setState(() => _preserveVibrato = v);
              _ffi.pitchCorrectorSetPreserveVibrato(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('ACTIVE NOTES'),
          const SizedBox(height: 8),
          Text(
            '${_noteNames[_root.index]} ${_scaleNames[_scale.index]}',
            style: const TextStyle(
              color: ReelForgeTheme.accentBlue,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: CustomPaint(
              painter: _KeyboardPainter(
                rootNote: _root.index,
                activeNotes: List.generate(12, _isNoteInScale),
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          // Note indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(12, (i) {
              final isActive = _isNoteInScale(i);
              final isRoot = i == _root.index;
              return Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isRoot ? ReelForgeTheme.accentBlue : ReelForgeTheme.accentGreen)
                          : ReelForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isActive
                            ? (isRoot ? ReelForgeTheme.accentBlue : ReelForgeTheme.accentGreen)
                            : ReelForgeTheme.borderMedium,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _noteNames[i].replaceAll('#', ''),
                        style: TextStyle(
                          color: isActive ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (_noteNames[i].contains('#'))
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? ReelForgeTheme.accentGreen : ReelForgeTheme.textDisabled,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF808090),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required List<String> labels,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderMedium),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        dropdownColor: ReelForgeTheme.bgMid,
        underline: const SizedBox(),
        style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 13),
        items: List.generate(items.length, (i) {
          return DropdownMenuItem(
            value: items[i],
            child: Text(labels[i]),
          );
        }),
        onChanged: (v) => v != null ? onChanged(v) : null,
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required String leftLabel,
    required String rightLabel,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(label),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: ReelForgeTheme.borderSubtle,
            thumbColor: color,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: color.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftLabel, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
            Text(rightLabel, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionTitle(label),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: ReelForgeTheme.accentGreen,
          inactiveTrackColor: ReelForgeTheme.borderSubtle,
        ),
      ],
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  final int rootNote;
  final List<bool> activeNotes;

  _KeyboardPainter({required this.rootNote, required this.activeNotes});

  @override
  void paint(Canvas canvas, Size size) {
    final whiteKeyWidth = size.width / 7;
    final whiteKeyHeight = size.height;
    final blackKeyWidth = whiteKeyWidth * 0.6;
    final blackKeyHeight = whiteKeyHeight * 0.6;

    // White keys: C, D, E, F, G, A, B (indices: 0, 2, 4, 5, 7, 9, 11)
    const whiteNotes = [0, 2, 4, 5, 7, 9, 11];
    // Black keys: C#, D#, F#, G#, A# (indices: 1, 3, 6, 8, 10)
    const blackNotes = [1, 3, 6, 8, 10];
    const blackPositions = [0.7, 1.7, 3.7, 4.7, 5.7]; // Position relative to white keys

    // Draw white keys
    for (var i = 0; i < 7; i++) {
      final noteIndex = whiteNotes[i];
      final isActive = activeNotes[noteIndex];
      final isRoot = noteIndex == rootNote;

      final rect = Rect.fromLTWH(
        i * whiteKeyWidth,
        0,
        whiteKeyWidth - 2,
        whiteKeyHeight,
      );

      final paint = Paint()
        ..color = isActive
            ? (isRoot ? ReelForgeTheme.accentBlue : ReelForgeTheme.accentGreen.withValues(alpha: 0.3))
            : const Color(0xFFE0E0E0);

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, paint);

      // Border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isActive
              ? (isRoot ? ReelForgeTheme.accentBlue : ReelForgeTheme.accentGreen)
              : const Color(0xFFB0B0B0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 2 : 1,
      );
    }

    // Draw black keys
    for (var i = 0; i < blackNotes.length; i++) {
      final noteIndex = blackNotes[i];
      final isActive = activeNotes[noteIndex];
      final isRoot = noteIndex == rootNote;

      final rect = Rect.fromLTWH(
        blackPositions[i] * whiteKeyWidth - blackKeyWidth / 2,
        0,
        blackKeyWidth,
        blackKeyHeight,
      );

      final paint = Paint()
        ..color = isActive
            ? (isRoot ? ReelForgeTheme.accentBlue : ReelForgeTheme.accentGreen)
            : const Color(0xFF202020);

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, paint);

      // Highlight
      if (isActive) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter oldDelegate) =>
      rootNote != oldDelegate.rootNote ||
      !_listEquals(activeNotes, oldDelegate.activeNotes);

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

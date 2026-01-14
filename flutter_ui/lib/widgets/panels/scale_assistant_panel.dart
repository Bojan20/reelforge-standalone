/// Scale Assistant Panel - Cubase-style key/scale helper UI
///
/// Features:
/// - Key signature selection
/// - Scale type picker
/// - Piano keyboard visualization
/// - Chord suggestions
/// - Key detection

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/scale_assistant_provider.dart';
import '../../theme/fluxforge_theme.dart';

class ScaleAssistantPanel extends StatelessWidget {
  const ScaleAssistantPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ScaleAssistantProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header
              _buildHeader(context, provider),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Key/Scale selector (left)
                    SizedBox(
                      width: 200,
                      child: _buildKeySelector(provider),
                    ),

                    // Divider
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Piano keyboard + scale notes (center)
                    Expanded(
                      child: _buildPianoSection(provider),
                    ),

                    // Divider
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Chord suggestions (right)
                    SizedBox(
                      width: 180,
                      child: _buildChordSection(provider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ScaleAssistantProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 16, color: Color(0xFFFFD700)),
          const SizedBox(width: 8),
          Text(
            'Scale Assistant',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Current key display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
            ),
            child: Text(
              provider.globalKey.displayName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFD700),
              ),
            ),
          ),

          const Spacer(),

          // Constraint mode selector
          _buildConstraintModeSelector(provider),

          const SizedBox(width: 12),

          // Auto-detect toggle
          _buildToggleButton(
            'Auto-Detect',
            Icons.auto_awesome,
            provider.autoDetect,
            () => provider.setAutoDetect(!provider.autoDetect),
          ),
        ],
      ),
    );
  }

  Widget _buildConstraintModeSelector(ScaleAssistantProvider provider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Mode:',
          style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
        ),
        const SizedBox(width: 6),
        ...ScaleConstraintMode.values.map((mode) {
          final isSelected = provider.constraintMode == mode;
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Tooltip(
              message: _getConstraintModeTooltip(mode),
              child: GestureDetector(
                onTap: () => provider.setConstraintMode(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Text(
                    _getConstraintModeName(mode),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildToggleButton(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
                : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeySelector(ScaleAssistantProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Root note selector
        Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ROOT NOTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildNoteGrid(provider),
            ],
          ),
        ),

        Container(height: 1, color: FluxForgeTheme.borderSubtle),

        // Scale type selector
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SCALE TYPE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildScaleTypeList(provider),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteGrid(ScaleAssistantProvider provider) {
    final notes = NoteName.values;
    final currentRoot = provider.globalKey.root;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: notes.map((note) {
        final isSelected = note == currentRoot;
        final isSharp = note.displayName.contains('#');

        return GestureDetector(
          onTap: () => provider.setGlobalKey(note, provider.globalKey.scale),
          child: Container(
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                  : isSharp
                      ? FluxForgeTheme.bgDeepest
                      : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFFD700)
                    : FluxForgeTheme.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                note.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFFFFD700)
                      : FluxForgeTheme.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScaleTypeList(ScaleAssistantProvider provider) {
    // Group scales by category
    final scaleGroups = <String, List<ScaleType>>{
      'Diatonic': [
        ScaleType.major,
        ScaleType.minor,
        ScaleType.dorian,
        ScaleType.phrygian,
        ScaleType.lydian,
        ScaleType.mixolydian,
        ScaleType.locrian,
      ],
      'Minor Variants': [
        ScaleType.harmonicMinor,
        ScaleType.melodicMinor,
      ],
      'Pentatonic': [
        ScaleType.majorPentatonic,
        ScaleType.minorPentatonic,
        ScaleType.blues,
        ScaleType.majorBlues,
      ],
      'Symmetric': [
        ScaleType.wholeTone,
        ScaleType.diminished,
        ScaleType.diminishedWhole,
        ScaleType.chromatic,
      ],
      'Exotic': [
        ScaleType.hungarian,
        ScaleType.spanish,
        ScaleType.japanese,
        ScaleType.arabian,
        ScaleType.persian,
        ScaleType.byzantine,
      ],
    };

    final currentScale = provider.globalKey.scale;

    return ListView(
      children: scaleGroups.entries.expand((entry) {
        return [
          // Group header
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          // Scales in group
          ...entry.value.map((scale) {
            final isSelected = scale == currentScale;
            return GestureDetector(
              onTap: () => provider.setGlobalKey(provider.globalKey.root, scale),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  scale.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFFFFD700)
                        : FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ];
      }).toList(),
    );
  }

  Widget _buildPianoSection(ScaleAssistantProvider provider) {
    return Column(
      children: [
        // Scale notes display
        Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCALE NOTES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildScaleNotesDisplay(provider),
            ],
          ),
        ),

        Container(height: 1, color: FluxForgeTheme.borderSubtle),

        // Piano keyboard
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildPianoKeyboard(provider),
          ),
        ),
      ],
    );
  }

  Widget _buildScaleNotesDisplay(ScaleAssistantProvider provider) {
    final scaleNotes = provider.globalKey.scaleNotes;
    final intervals = provider.globalKey.scale.intervals;

    return Row(
      children: List.generate(scaleNotes.length, (index) {
        final note = scaleNotes[index];
        final interval = intervals[index];
        final isRoot = index == 0;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isRoot
                      ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                      : FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isRoot
                        ? const Color(0xFFFFD700)
                        : FluxForgeTheme.accentBlue.withValues(alpha: 0.5),
                    width: isRoot ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    note.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isRoot
                          ? const Color(0xFFFFD700)
                          : FluxForgeTheme.accentBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getIntervalName(interval),
                style: TextStyle(
                  fontSize: 9,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPianoKeyboard(ScaleAssistantProvider provider) {
    final scaleNotes = provider.globalKey.scaleNotes.map((n) => n.semitone).toSet();
    final rootSemitone = provider.globalKey.root.semitone;

    return LayoutBuilder(
      builder: (context, constraints) {
        final whiteKeyWidth = constraints.maxWidth / 14; // 2 octaves
        final blackKeyWidth = whiteKeyWidth * 0.6;
        final whiteKeyHeight = constraints.maxHeight;
        final blackKeyHeight = whiteKeyHeight * 0.6;

        // Build keys for 2 octaves
        final whiteKeys = <Widget>[];
        final blackKeys = <Widget>[];

        const whiteNotes = [0, 2, 4, 5, 7, 9, 11]; // C, D, E, F, G, A, B
        const blackNotes = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#
        const blackOffsets = [0.7, 1.7, 3.7, 4.7, 5.7]; // Relative positions

        for (var octave = 0; octave < 2; octave++) {
          // White keys
          for (var i = 0; i < 7; i++) {
            final semitone = (whiteNotes[i] + octave * 12) % 12;
            final isInScale = scaleNotes.contains(semitone);
            final isRoot = semitone == rootSemitone;

            whiteKeys.add(
              Positioned(
                left: (octave * 7 + i) * whiteKeyWidth,
                top: 0,
                child: Container(
                  width: whiteKeyWidth - 2,
                  height: whiteKeyHeight,
                  decoration: BoxDecoration(
                    color: isRoot
                        ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                        : isInScale
                            ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
                            : Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        NoteName.fromSemitone(semitone).displayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isInScale ? FontWeight.w600 : FontWeight.normal,
                          color: isRoot
                              ? const Color(0xFFFFD700)
                              : isInScale
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // Black keys
          for (var i = 0; i < 5; i++) {
            final semitone = (blackNotes[i] + octave * 12) % 12;
            final isInScale = scaleNotes.contains(semitone);
            final isRoot = semitone == rootSemitone;

            blackKeys.add(
              Positioned(
                left: (octave * 7 + blackOffsets[i]) * whiteKeyWidth - blackKeyWidth / 2,
                top: 0,
                child: Container(
                  width: blackKeyWidth,
                  height: blackKeyHeight,
                  decoration: BoxDecoration(
                    color: isRoot
                        ? const Color(0xFFFFD700).withValues(alpha: 0.8)
                        : isInScale
                            ? FluxForgeTheme.accentBlue.withValues(alpha: 0.7)
                            : FluxForgeTheme.bgDeepest,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                    border: Border.all(
                      color: isInScale
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                ),
              ),
            );
          }
        }

        return Stack(
          children: [
            ...whiteKeys,
            ...blackKeys,
          ],
        );
      },
    );
  }

  Widget _buildChordSection(ScaleAssistantProvider provider) {
    final chords = provider.globalKey.diatonicChords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Text(
            'DIATONIC CHORDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: chords.length,
            itemBuilder: (context, index) {
              final chord = chords[index];
              return _buildChordCard(chord, index);
            },
          ),
        ),

        // Related keys
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RELATED KEYS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              _buildRelatedKeys(provider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChordCard(ChordInfo chord, int index) {
    final colors = [
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentCyan,
      const Color(0xFFAA40FF),
      FluxForgeTheme.errorRed,
      FluxForgeTheme.textSecondary,
    ];

    final color = colors[index % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Roman numeral
          Container(
            width: 32,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                chord.romanNumeral ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Chord name
          Expanded(
            child: Text(
              chord.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedKeys(ScaleAssistantProvider provider) {
    final relativeKey = provider.globalKey.relativeKey;
    final parallelKey = provider.globalKey.parallelKey;

    return Column(
      children: [
        if (relativeKey != null)
          _buildRelatedKeyRow('Relative', relativeKey.shortName, FluxForgeTheme.accentCyan),
        if (parallelKey != null)
          _buildRelatedKeyRow('Parallel', parallelKey.shortName, FluxForgeTheme.accentOrange),
      ],
    );
  }

  Widget _buildRelatedKeyRow(String type, String key, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$type:',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              key,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getConstraintModeName(ScaleConstraintMode mode) {
    switch (mode) {
      case ScaleConstraintMode.off:
        return 'Off';
      case ScaleConstraintMode.highlight:
        return 'Highlight';
      case ScaleConstraintMode.snapOnInput:
        return 'Snap';
      case ScaleConstraintMode.strict:
        return 'Strict';
    }
  }

  String _getConstraintModeTooltip(ScaleConstraintMode mode) {
    switch (mode) {
      case ScaleConstraintMode.off:
        return 'No scale constraint';
      case ScaleConstraintMode.highlight:
        return 'Highlight scale notes in editor';
      case ScaleConstraintMode.snapOnInput:
        return 'Snap notes to scale on input';
      case ScaleConstraintMode.strict:
        return 'Only allow scale notes';
    }
  }

  String _getIntervalName(int semitones) {
    const names = {
      0: 'R',
      1: 'm2',
      2: 'M2',
      3: 'm3',
      4: 'M3',
      5: 'P4',
      6: 'TT',
      7: 'P5',
      8: 'm6',
      9: 'M6',
      10: 'm7',
      11: 'M7',
    };
    return names[semitones % 12] ?? '?';
  }
}

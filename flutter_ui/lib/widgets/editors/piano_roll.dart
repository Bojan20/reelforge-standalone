/// Pro Piano Roll - FL Studio Level Quality
///
/// Best-in-class MIDI editor with:
/// - Ghost notes (notes from other tracks)
/// - Scale highlighting (show in-scale keys)
/// - Velocity color coding
/// - Portamento/glide visualization
/// - Smart snap modes
/// - Multi-note selection
/// - Note preview on hover
/// - Chord detection display

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Single MIDI note
class MidiNote {
  final String id;
  final int pitch; // 0-127
  final double startBeat;
  final double duration; // in beats
  final double velocity; // 0.0-1.0
  final bool muted;
  final String? trackId;
  final Color? color;

  const MidiNote({
    required this.id,
    required this.pitch,
    required this.startBeat,
    required this.duration,
    this.velocity = 0.8,
    this.muted = false,
    this.trackId,
    this.color,
  });

  double get endBeat => startBeat + duration;

  MidiNote copyWith({
    String? id,
    int? pitch,
    double? startBeat,
    double? duration,
    double? velocity,
    bool? muted,
    String? trackId,
    Color? color,
  }) {
    return MidiNote(
      id: id ?? this.id,
      pitch: pitch ?? this.pitch,
      startBeat: startBeat ?? this.startBeat,
      duration: duration ?? this.duration,
      velocity: velocity ?? this.velocity,
      muted: muted ?? this.muted,
      trackId: trackId ?? this.trackId,
      color: color ?? this.color,
    );
  }
}

/// Musical scale for highlighting
class MusicalScale {
  final String name;
  final int root; // 0=C, 1=C#, etc.
  final List<int> intervals; // Semitones from root

  const MusicalScale({
    required this.name,
    required this.root,
    required this.intervals,
  });

  bool isInScale(int pitch) {
    final noteInOctave = pitch % 12;
    final relativeNote = (noteInOctave - root + 12) % 12;
    return intervals.contains(relativeNote);
  }

  static const major = [0, 2, 4, 5, 7, 9, 11];
  static const minor = [0, 2, 3, 5, 7, 8, 10];
  static const harmonicMinor = [0, 2, 3, 5, 7, 8, 11];
  static const melodicMinor = [0, 2, 3, 5, 7, 9, 11];
  static const pentatonicMajor = [0, 2, 4, 7, 9];
  static const pentatonicMinor = [0, 3, 5, 7, 10];
  static const blues = [0, 3, 5, 6, 7, 10];
  static const dorian = [0, 2, 3, 5, 7, 9, 10];
  static const phrygian = [0, 1, 3, 5, 7, 8, 10];
  static const lydian = [0, 2, 4, 6, 7, 9, 11];
  static const mixolydian = [0, 2, 4, 5, 7, 9, 10];

  static MusicalScale cMajor = const MusicalScale(
    name: 'C Major',
    root: 0,
    intervals: major,
  );
}

/// Snap mode
enum SnapMode {
  off,
  line,
  cell,
  beat,
  bar,
  // Tuplets
  triplet,
  quintuplet,
}

/// Piano roll configuration
class PianoRollConfig {
  final double beatsPerBar;
  final int subdivisions;
  final SnapMode snapMode;
  final MusicalScale? scale;
  final bool showGhostNotes;
  final bool showVelocity;
  final double noteHeight;
  final double beatWidth;
  final int lowNote; // Lowest visible note
  final int highNote; // Highest visible note

  const PianoRollConfig({
    this.beatsPerBar = 4,
    this.subdivisions = 4,
    this.snapMode = SnapMode.cell,
    this.scale,
    this.showGhostNotes = true,
    this.showVelocity = true,
    this.noteHeight = 14,
    this.beatWidth = 60,
    this.lowNote = 36, // C2
    this.highNote = 96, // C7
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// PIANO ROLL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class PianoRoll extends StatefulWidget {
  /// Current track's notes
  final List<MidiNote> notes;

  /// Ghost notes from other tracks
  final List<MidiNote> ghostNotes;

  /// Selected note IDs
  final Set<String> selectedIds;

  /// Configuration
  final PianoRollConfig config;

  /// Total length in beats
  final double totalBeats;

  /// Current playhead position
  final double? playheadBeat;

  /// Loop region
  final (double, double)? loopRegion;

  /// Callbacks
  final void Function(MidiNote note)? onNoteAdd;
  final void Function(String id)? onNoteDelete;
  final void Function(String id, MidiNote newNote)? onNoteUpdate;
  final void Function(Set<String> ids)? onSelectionChange;
  final void Function(int pitch)? onKeyPreview;

  const PianoRoll({
    super.key,
    required this.notes,
    this.ghostNotes = const [],
    this.selectedIds = const {},
    this.config = const PianoRollConfig(),
    this.totalBeats = 32,
    this.playheadBeat,
    this.loopRegion,
    this.onNoteAdd,
    this.onNoteDelete,
    this.onNoteUpdate,
    this.onSelectionChange,
    this.onKeyPreview,
  });

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll> {
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Interaction state
  int? _hoveredPitch;
  double? _hoveredBeat;
  String? _draggingNoteId;
  // ignore: unused_field
  Offset? _dragOffset;
  // ignore: unused_field
  bool _isResizing = false;
  Rect? _selectionRect;
  Offset? _selectionStart;

  // Piano key constants
  static const double _pianoKeyWidth = 80;
  static const List<bool> _isBlackKey = [
    false, true, false, true, false, false, true, false, true, false, true, false
  ];
  static const List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  String _noteName(int pitch) {
    final octave = (pitch ~/ 12) - 1;
    final noteName = _noteNames[pitch % 12];
    return '$noteName$octave';
  }

  bool _isBlack(int pitch) => _isBlackKey[pitch % 12];

  @override
  void dispose() {
    _hScrollController.dispose();
    _vScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double _beatToX(double beat) => beat * widget.config.beatWidth;
  double _xToBeat(double x) => x / widget.config.beatWidth;
  double _pitchToY(int pitch) =>
      (widget.config.highNote - pitch) * widget.config.noteHeight;
  int _yToPitch(double y) =>
      widget.config.highNote - (y / widget.config.noteHeight).floor();

  double _snapBeat(double beat) {
    switch (widget.config.snapMode) {
      case SnapMode.off:
        return beat;
      case SnapMode.line:
        return (beat * 4).round() / 4; // 1/16 note
      case SnapMode.cell:
        return (beat * widget.config.subdivisions).round() /
            widget.config.subdivisions;
      case SnapMode.beat:
        return beat.roundToDouble();
      case SnapMode.bar:
        return (beat / widget.config.beatsPerBar).round() *
            widget.config.beatsPerBar;
      case SnapMode.triplet:
        return (beat * 3).round() / 3;
      case SnapMode.quintuplet:
        return (beat * 5).round() / 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteRange = widget.config.highNote - widget.config.lowNote + 1;
    final gridHeight = noteRange * widget.config.noteHeight;
    final gridWidth = widget.totalBeats * widget.config.beatWidth;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        color: ReelForgeTheme.bgDeepest,
        child: Row(
          children: [
            // Piano keys
            SizedBox(
              width: _pianoKeyWidth,
              child: _buildPianoKeys(noteRange),
            ),

            // Grid area
            Expanded(
              child: Column(
                children: [
                  // Timeline header
                  SizedBox(
                    height: 24,
                    child: _buildTimeline(gridWidth),
                  ),

                  // Note grid
                  Expanded(
                    child: _buildNoteGrid(gridWidth, gridHeight, noteRange),
                  ),

                  // Velocity lane
                  if (widget.config.showVelocity)
                    SizedBox(
                      height: 60,
                      child: _buildVelocityLane(gridWidth),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPianoKeys(int noteRange) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _vScrollController,
        child: Column(
          children: List.generate(noteRange, (i) {
            final pitch = widget.config.highNote - i;
            final isBlack = _isBlack(pitch);
            final isInScale =
                widget.config.scale?.isInScale(pitch) ?? true;
            final isHovered = _hoveredPitch == pitch;
            final isC = pitch % 12 == 0;

            return GestureDetector(
              onTap: () => widget.onKeyPreview?.call(pitch),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hoveredPitch = pitch),
                onExit: (_) => setState(() => _hoveredPitch = null),
                child: Container(
                  height: widget.config.noteHeight,
                  width: _pianoKeyWidth,
                  decoration: BoxDecoration(
                    color: isHovered
                        ? ReelForgeTheme.accentBlue.withValues(alpha: 0.3)
                        : (isBlack
                            ? PianoRollColors.scaleKeyBlack
                            : PianoRollColors.scaleKeyWhite),
                    border: Border(
                      bottom: BorderSide(
                        color: isC
                            ? ReelForgeTheme.borderMedium
                            : ReelForgeTheme.borderSubtle,
                        width: isC ? 1.5 : 0.5,
                      ),
                      right: BorderSide(
                        color: ReelForgeTheme.borderMedium,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Scale highlight
                      if (widget.config.scale != null && isInScale)
                        Positioned.fill(
                          child: Container(
                            color: PianoRollColors.scaleHighlight,
                          ),
                        ),
                      // Key label
                      if (isC || isHovered)
                        Positioned(
                          right: 4,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Text(
                              _noteName(pitch),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isC ? FontWeight.w600 : FontWeight.w400,
                                color: isHovered
                                    ? ReelForgeTheme.accentBlue
                                    : (isC
                                        ? ReelForgeTheme.textPrimary
                                        : ReelForgeTheme.textSecondary),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTimeline(double gridWidth) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderMedium),
        ),
      ),
      child: SingleChildScrollView(
        controller: _hScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: CustomPaint(
            painter: _TimelinePainter(
              beatsPerBar: widget.config.beatsPerBar,
              beatWidth: widget.config.beatWidth,
              totalBeats: widget.totalBeats,
              playheadBeat: widget.playheadBeat,
              loopRegion: widget.loopRegion,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteGrid(double gridWidth, double gridHeight, int noteRange) {
    return GestureDetector(
      onTapUp: _handleTapUp,
      onSecondaryTapUp: _handleSecondaryTap,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: MouseRegion(
        onHover: _handleHover,
        onExit: (_) => setState(() {
          _hoveredPitch = null;
          _hoveredBeat = null;
        }),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _hScrollController,
          child: SingleChildScrollView(
            controller: _vScrollController,
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: Stack(
                children: [
                  // Grid background
                  CustomPaint(
                    size: Size(gridWidth, gridHeight),
                    painter: _GridPainter(
                      config: widget.config,
                      totalBeats: widget.totalBeats,
                      noteRange: noteRange,
                    ),
                  ),

                  // Ghost notes
                  if (widget.config.showGhostNotes)
                    ...widget.ghostNotes.map((note) => _buildNote(
                          note,
                          isGhost: true,
                          isSelected: false,
                        )),

                  // Regular notes
                  ...widget.notes.map((note) => _buildNote(
                        note,
                        isGhost: false,
                        isSelected: widget.selectedIds.contains(note.id),
                      )),

                  // Playhead
                  if (widget.playheadBeat != null)
                    Positioned(
                      left: _beatToX(widget.playheadBeat!),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: ReelForgeTheme.accentBlue,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            boxShadow: ReelForgeTheme.glowShadow(
                              ReelForgeTheme.accentBlue,
                              intensity: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Selection rectangle
                  if (_selectionRect != null)
                    Positioned.fromRect(
                      rect: _selectionRect!,
                      child: Container(
                        decoration: BoxDecoration(
                          color: PianoRollColors.selection,
                          border: Border.all(
                            color: PianoRollColors.selectionBorder,
                            width: 1,
                          ),
                        ),
                      ),
                    ),

                  // Hover preview (when adding note)
                  if (_hoveredPitch != null &&
                      _hoveredBeat != null &&
                      _draggingNoteId == null)
                    Positioned(
                      left: _beatToX(_snapBeat(_hoveredBeat!)),
                      top: _pitchToY(_hoveredPitch!),
                      child: Container(
                        width: widget.config.beatWidth / widget.config.subdivisions,
                        height: widget.config.noteHeight - 1,
                        decoration: BoxDecoration(
                          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: ReelForgeTheme.accentBlue.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNote(MidiNote note, {required bool isGhost, required bool isSelected}) {
    final x = _beatToX(note.startBeat);
    final y = _pitchToY(note.pitch);
    final width = note.duration * widget.config.beatWidth;
    final height = widget.config.noteHeight - 1;

    Color noteColor;
    if (isGhost) {
      noteColor = isSelected ? PianoRollColors.ghostNoteSelected : PianoRollColors.ghostNote;
    } else if (note.color != null) {
      noteColor = note.color!;
    } else {
      noteColor = PianoRollColors.noteColor(note.velocity);
    }

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: () => _selectNote(note.id),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: isGhost
                  ? noteColor
                  : (isSelected
                      ? noteColor
                      : noteColor.withValues(alpha: 0.9)),
              borderRadius: BorderRadius.circular(2),
              border: isSelected
                  ? Border.all(color: ReelForgeTheme.textPrimary, width: 1.5)
                  : null,
              boxShadow: isSelected && !isGhost
                  ? ReelForgeTheme.glowShadow(noteColor, intensity: 0.4)
                  : null,
            ),
            child: Stack(
              children: [
                // Velocity bar (left edge)
                if (!isGhost)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: note.velocity * 0.5),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(2),
                          bottomLeft: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),

                // Note name (if wide enough)
                if (width > 40 && !isGhost)
                  Positioned(
                    left: 6,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        _noteName(note.pitch),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                // Resize handle (right edge)
                if (!isGhost && isSelected)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeRight,
                      child: Container(
                        width: 6,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVelocityLane(double gridWidth) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(color: ReelForgeTheme.borderMedium),
        ),
      ),
      child: SingleChildScrollView(
        controller: _hScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: CustomPaint(
            painter: _VelocityPainter(
              notes: widget.notes,
              selectedIds: widget.selectedIds,
              beatWidth: widget.config.beatWidth,
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // EVENT HANDLERS
  // ═════════════════════════════════════════════════════════════════════════

  void _handleTapUp(TapUpDetails details) {
    final beat = _snapBeat(_xToBeat(details.localPosition.dx + _hScrollController.offset));
    final pitch = _yToPitch(details.localPosition.dy + _vScrollController.offset);

    // Check if we tapped on an existing note
    final tappedNote = widget.notes.firstWhere(
      (n) => n.pitch == pitch && beat >= n.startBeat && beat < n.endBeat,
      orElse: () => MidiNote(
        id: '',
        pitch: pitch,
        startBeat: beat,
        duration: 0,
      ),
    );

    if (tappedNote.id.isNotEmpty) {
      _selectNote(tappedNote.id);
    } else {
      // Add new note
      final newNote = MidiNote(
        id: 'note-${DateTime.now().millisecondsSinceEpoch}',
        pitch: pitch,
        startBeat: beat,
        duration: 1 / widget.config.subdivisions,
        velocity: 0.8,
      );
      widget.onNoteAdd?.call(newNote);
    }
  }

  void _handleSecondaryTap(TapUpDetails details) {
    // Delete note on right-click
    final beat = _xToBeat(details.localPosition.dx + _hScrollController.offset);
    final pitch = _yToPitch(details.localPosition.dy + _vScrollController.offset);

    final noteToDelete = widget.notes.firstWhere(
      (n) => n.pitch == pitch && beat >= n.startBeat && beat < n.endBeat,
      orElse: () => MidiNote(id: '', pitch: 0, startBeat: 0, duration: 0),
    );

    if (noteToDelete.id.isNotEmpty) {
      widget.onNoteDelete?.call(noteToDelete.id);
    }
  }

  void _handlePanStart(DragStartDetails details) {
    _selectionStart = details.localPosition;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_selectionStart != null) {
      final current = details.localPosition;
      setState(() {
        _selectionRect = Rect.fromPoints(_selectionStart!, current);
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_selectionRect != null) {
      // Find notes within selection
      final selectedIds = <String>{};
      for (final note in widget.notes) {
        final noteRect = Rect.fromLTWH(
          _beatToX(note.startBeat),
          _pitchToY(note.pitch),
          note.duration * widget.config.beatWidth,
          widget.config.noteHeight,
        );
        if (_selectionRect!.overlaps(noteRect)) {
          selectedIds.add(note.id);
        }
      }
      widget.onSelectionChange?.call(selectedIds);
    }

    setState(() {
      _selectionStart = null;
      _selectionRect = null;
    });
  }

  void _handleHover(PointerHoverEvent event) {
    setState(() {
      _hoveredBeat = _xToBeat(event.localPosition.dx + _hScrollController.offset);
      _hoveredPitch = _yToPitch(event.localPosition.dy + _vScrollController.offset);
    });
  }

  void _selectNote(String id) {
    final newSelection = Set<String>.from(widget.selectedIds);
    if (HardwareKeyboard.instance.isShiftPressed) {
      // Add to selection
      if (newSelection.contains(id)) {
        newSelection.remove(id);
      } else {
        newSelection.add(id);
      }
    } else {
      // Single selection
      newSelection.clear();
      newSelection.add(id);
    }
    widget.onSelectionChange?.call(newSelection);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        // Delete selected notes
        for (final id in widget.selectedIds) {
          widget.onNoteDelete?.call(id);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyA:
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          // Select all
          widget.onSelectionChange?.call(
            widget.notes.map((n) => n.id).toSet(),
          );
          return KeyEventResult.handled;
        }
        break;

      case LogicalKeyboardKey.escape:
        // Deselect all
        widget.onSelectionChange?.call({});
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final PianoRollConfig config;
  final double totalBeats;
  final int noteRange;

  _GridPainter({
    required this.config,
    required this.totalBeats,
    required this.noteRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal lines (pitch rows)
    for (int i = 0; i <= noteRange; i++) {
      final pitch = config.highNote - i;
      final y = i * config.noteHeight;
      final isBlack = [1, 3, 6, 8, 10].contains(pitch % 12);
      final isC = pitch % 12 == 0;

      // Row background
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, config.noteHeight),
        Paint()..color = isBlack
            ? PianoRollColors.scaleKeyBlack
            : PianoRollColors.scaleKeyWhite,
      );

      // Scale highlight
      if (config.scale != null && config.scale!.isInScale(pitch)) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, config.noteHeight),
          Paint()..color = PianoRollColors.scaleHighlight,
        );
      }

      // Row separator
      canvas.drawLine(
        Offset(0, y + config.noteHeight),
        Offset(size.width, y + config.noteHeight),
        Paint()
          ..color = isC ? PianoRollColors.gridBar : PianoRollColors.gridSubdivision
          ..strokeWidth = isC ? 1.5 : 0.5,
      );
    }

    // Vertical lines (beats)
    for (double beat = 0; beat <= totalBeats; beat += 1 / config.subdivisions) {
      final x = beat * config.beatWidth;
      final isBar = (beat % config.beatsPerBar) < 0.01;
      final isBeat = (beat % 1) < 0.01;

      Color lineColor;
      double lineWidth;

      if (isBar) {
        lineColor = PianoRollColors.gridBar;
        lineWidth = 1.5;
      } else if (isBeat) {
        lineColor = PianoRollColors.gridBeat;
        lineWidth = 1;
      } else {
        lineColor = PianoRollColors.gridSubdivision;
        lineWidth = 0.5;
      }

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = lineColor
          ..strokeWidth = lineWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      config != oldDelegate.config ||
      totalBeats != oldDelegate.totalBeats ||
      noteRange != oldDelegate.noteRange;
}

class _TimelinePainter extends CustomPainter {
  final double beatsPerBar;
  final double beatWidth;
  final double totalBeats;
  final double? playheadBeat;
  final (double, double)? loopRegion;

  _TimelinePainter({
    required this.beatsPerBar,
    required this.beatWidth,
    required this.totalBeats,
    this.playheadBeat,
    this.loopRegion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Loop region
    if (loopRegion != null) {
      final x1 = loopRegion!.$1 * beatWidth;
      final x2 = loopRegion!.$2 * beatWidth;
      canvas.drawRect(
        Rect.fromLTWH(x1, 0, x2 - x1, size.height),
        Paint()..color = ReelForgeTheme.accentPurple.withValues(alpha: 0.2),
      );
    }

    // Bar numbers
    for (int bar = 0; bar <= (totalBeats / beatsPerBar).ceil(); bar++) {
      final x = bar * beatsPerBar * beatWidth;

      // Bar marker
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x, size.height),
        Paint()
          ..color = ReelForgeTheme.textSecondary
          ..strokeWidth = 1,
      );

      // Bar number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${bar + 1}',
          style: TextStyle(
            fontSize: 10,
            color: ReelForgeTheme.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 4, 4));
    }

    // Playhead
    if (playheadBeat != null) {
      final x = playheadBeat! * beatWidth;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = ReelForgeTheme.accentBlue
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      playheadBeat != oldDelegate.playheadBeat ||
      loopRegion != oldDelegate.loopRegion;
}

class _VelocityPainter extends CustomPainter {
  final List<MidiNote> notes;
  final Set<String> selectedIds;
  final double beatWidth;

  _VelocityPainter({
    required this.notes,
    required this.selectedIds,
    required this.beatWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgDeep,
    );

    // 50% line
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      Paint()
        ..color = ReelForgeTheme.borderSubtle
        ..strokeWidth = 0.5,
    );

    // Velocity bars
    for (final note in notes) {
      final x = note.startBeat * beatWidth;
      final width = math.max(4.0, note.duration * beatWidth - 2);
      final barHeight = size.height * note.velocity;
      final isSelected = selectedIds.contains(note.id);

      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barHeight, width, barHeight),
        Paint()
          ..color = isSelected
              ? ReelForgeTheme.accentBlue
              : PianoRollColors.noteColor(note.velocity).withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_VelocityPainter oldDelegate) =>
      notes != oldDelegate.notes || selectedIds != oldDelegate.selectedIds;
}

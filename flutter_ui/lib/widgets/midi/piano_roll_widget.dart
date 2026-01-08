/// Professional MIDI Piano Roll Editor
///
/// Full-featured piano roll with:
/// - Note drawing/editing
/// - Velocity lane
/// - Piano keyboard
/// - Grid snapping
/// - Multi-selection
/// - Undo/redo

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Grid division options
enum GridDivision {
  bar,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  eighthTriplet,
  sixteenthTriplet,
}

extension GridDivisionExt on GridDivision {
  String get label {
    switch (this) {
      case GridDivision.bar: return '1 Bar';
      case GridDivision.half: return '1/2';
      case GridDivision.quarter: return '1/4';
      case GridDivision.eighth: return '1/8';
      case GridDivision.sixteenth: return '1/16';
      case GridDivision.thirtySecond: return '1/32';
      case GridDivision.eighthTriplet: return '1/8T';
      case GridDivision.sixteenthTriplet: return '1/16T';
    }
  }
}

/// Piano roll tool
enum PianoRollTool {
  select,
  draw,
  erase,
  velocity,
}

extension PianoRollToolExt on PianoRollTool {
  IconData get icon {
    switch (this) {
      case PianoRollTool.select: return Icons.touch_app;
      case PianoRollTool.draw: return Icons.edit;
      case PianoRollTool.erase: return Icons.delete_outline;
      case PianoRollTool.velocity: return Icons.bar_chart;
    }
  }

  String get label {
    switch (this) {
      case PianoRollTool.select: return 'Select';
      case PianoRollTool.draw: return 'Draw';
      case PianoRollTool.erase: return 'Erase';
      case PianoRollTool.velocity: return 'Velocity';
    }
  }
}

/// Piano Roll Widget
class PianoRollWidget extends StatefulWidget {
  final int clipId;
  final int lengthBars;
  final double bpm;
  final VoidCallback? onNotesChanged;

  const PianoRollWidget({
    super.key,
    required this.clipId,
    this.lengthBars = 4,
    this.bpm = 120.0,
    this.onNotesChanged,
  });

  @override
  State<PianoRollWidget> createState() => _PianoRollWidgetState();
}

class _PianoRollWidgetState extends State<PianoRollWidget> {
  // Constants
  static const int ticksPerBeat = 960;
  static const double defaultPixelsPerBeat = 100.0;
  static const double defaultPixelsPerNote = 16.0;
  static const double keysWidth = 80.0;
  static const double toolbarHeight = 40.0;
  static const double velocityLaneHeight = 60.0;

  // State
  List<PianoRollNote> _notes = [];
  PianoRollTool _tool = PianoRollTool.draw;
  GridDivision _grid = GridDivision.sixteenth;
  bool _snapEnabled = true;
  bool _showVelocity = true;

  // View
  double _pixelsPerBeat = defaultPixelsPerBeat;
  double _pixelsPerNote = defaultPixelsPerNote;
  double _scrollX = 0;
  double _scrollY = 0;
  int _visibleNoteLow = 36;  // C2
  int _visibleNoteHigh = 96; // C7

  // Interaction
  bool _isDragging = false;
  Offset? _dragStart;
  Offset? _dragCurrent;
  int? _dragNoteId;
  int? _drawingNoteStart;

  // Selection rectangle
  Rect? _selectionRect;

  @override
  void initState() {
    super.initState();
    _initializePianoRoll();
  }

  @override
  void dispose() {
    NativeFFI.instance.pianoRollRemove(widget.clipId);
    super.dispose();
  }

  void _initializePianoRoll() {
    NativeFFI.instance.pianoRollCreate(widget.clipId);
    final lengthTicks = widget.lengthBars * 4 * ticksPerBeat;
    NativeFFI.instance.pianoRollSetLength(widget.clipId, lengthTicks);
    _loadNotes();
  }

  void _loadNotes() {
    setState(() {
      _notes = NativeFFI.instance.pianoRollGetAllNotes(widget.clipId);
    });
  }

  int _snapToGrid(int tick) {
    if (!_snapEnabled) return tick;
    final gridTicks = _getGridTicks();
    return ((tick + gridTicks ~/ 2) ~/ gridTicks) * gridTicks;
  }

  int _getGridTicks() {
    switch (_grid) {
      case GridDivision.bar: return ticksPerBeat * 4;
      case GridDivision.half: return ticksPerBeat * 2;
      case GridDivision.quarter: return ticksPerBeat;
      case GridDivision.eighth: return ticksPerBeat ~/ 2;
      case GridDivision.sixteenth: return ticksPerBeat ~/ 4;
      case GridDivision.thirtySecond: return ticksPerBeat ~/ 8;
      case GridDivision.eighthTriplet: return ticksPerBeat ~/ 3;
      case GridDivision.sixteenthTriplet: return ticksPerBeat ~/ 6;
    }
  }

  int _xToTick(double x) {
    final beats = (x + _scrollX) / _pixelsPerBeat;
    return (beats * ticksPerBeat).round().clamp(0, widget.lengthBars * 4 * ticksPerBeat);
  }

  double _tickToX(int tick) {
    final beats = tick / ticksPerBeat;
    return beats * _pixelsPerBeat - _scrollX;
  }

  int _yToNote(double y) {
    final noteOffset = (y + _scrollY) / _pixelsPerNote;
    return (_visibleNoteHigh - noteOffset.floor()).clamp(0, 127);
  }

  double _noteToY(int note) {
    final noteOffset = _visibleNoteHigh - note;
    return noteOffset * _pixelsPerNote - _scrollY;
  }

  void _handleTap(TapDownDetails details, double gridWidth, double gridHeight) {
    final localPos = details.localPosition;
    final tick = _xToTick(localPos.dx);
    final note = _yToNote(localPos.dy);

    switch (_tool) {
      case PianoRollTool.draw:
        // Check if there's already a note here
        final existingId = NativeFFI.instance.pianoRollNoteAt(widget.clipId, tick, note);
        if (existingId == 0) {
          // Add new note
          final snappedTick = _snapToGrid(tick);
          final duration = _getGridTicks();
          NativeFFI.instance.pianoRollAddNote(
            widget.clipId, note, snappedTick, duration, 100,
          );
          _loadNotes();
          widget.onNotesChanged?.call();
        }
        break;

      case PianoRollTool.select:
        final noteId = NativeFFI.instance.pianoRollNoteAt(widget.clipId, tick, note);
        if (noteId != 0) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          NativeFFI.instance.pianoRollSelect(widget.clipId, noteId, addToSelection: isShift);
          _loadNotes();
        } else {
          NativeFFI.instance.pianoRollDeselectAll(widget.clipId);
          _loadNotes();
        }
        break;

      case PianoRollTool.erase:
        final noteId = NativeFFI.instance.pianoRollNoteAt(widget.clipId, tick, note);
        if (noteId != 0) {
          NativeFFI.instance.pianoRollRemoveNote(widget.clipId, noteId);
          _loadNotes();
          widget.onNotesChanged?.call();
        }
        break;

      case PianoRollTool.velocity:
        // Handled in velocity lane
        break;
    }
  }

  void _handlePanStart(DragStartDetails details) {
    _isDragging = true;
    _dragStart = details.localPosition;
    _dragCurrent = details.localPosition;

    if (_tool == PianoRollTool.select) {
      final tick = _xToTick(details.localPosition.dx);
      final note = _yToNote(details.localPosition.dy);
      _dragNoteId = NativeFFI.instance.pianoRollNoteAt(widget.clipId, tick, note);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    setState(() {
      _dragCurrent = details.localPosition;

      if (_tool == PianoRollTool.select && _dragNoteId == null) {
        // Rectangle selection
        _selectionRect = Rect.fromPoints(_dragStart!, _dragCurrent!);
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_tool == PianoRollTool.select) {
      if (_selectionRect != null) {
        // Finish rectangle selection
        final tickStart = _xToTick(_selectionRect!.left);
        final tickEnd = _xToTick(_selectionRect!.right);
        final noteHigh = _yToNote(_selectionRect!.top);
        final noteLow = _yToNote(_selectionRect!.bottom);

        final isShift = HardwareKeyboard.instance.isShiftPressed;
        NativeFFI.instance.pianoRollSelectRect(
          widget.clipId, tickStart, tickEnd, noteLow, noteHigh, add: isShift,
        );
        _loadNotes();
      } else if (_dragNoteId != null && _dragStart != null && _dragCurrent != null) {
        // Move selected notes
        final deltaTick = _xToTick(_dragCurrent!.dx) - _xToTick(_dragStart!.dx);
        final deltaNote = _yToNote(_dragStart!.dy) - _yToNote(_dragCurrent!.dy);

        if (deltaTick != 0 || deltaNote != 0) {
          NativeFFI.instance.pianoRollMoveSelected(widget.clipId, deltaTick, deltaNote);
          _loadNotes();
          widget.onNotesChanged?.call();
        }
      }
    }

    setState(() {
      _isDragging = false;
      _dragStart = null;
      _dragCurrent = null;
      _dragNoteId = null;
      _selectionRect = null;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                   HardwareKeyboard.instance.isMetaPressed;

    if (isCtrl) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyZ:
          if (HardwareKeyboard.instance.isShiftPressed) {
            NativeFFI.instance.pianoRollRedo(widget.clipId);
          } else {
            NativeFFI.instance.pianoRollUndo(widget.clipId);
          }
          _loadNotes();
          break;
        case LogicalKeyboardKey.keyA:
          NativeFFI.instance.pianoRollSelectAll(widget.clipId);
          _loadNotes();
          break;
        case LogicalKeyboardKey.keyC:
          NativeFFI.instance.pianoRollCopy(widget.clipId);
          break;
        case LogicalKeyboardKey.keyX:
          NativeFFI.instance.pianoRollCut(widget.clipId);
          _loadNotes();
          widget.onNotesChanged?.call();
          break;
        case LogicalKeyboardKey.keyV:
          NativeFFI.instance.pianoRollPaste(widget.clipId, 0);
          _loadNotes();
          widget.onNotesChanged?.call();
          break;
        case LogicalKeyboardKey.keyD:
          NativeFFI.instance.pianoRollDuplicate(widget.clipId, _getGridTicks() * 4);
          _loadNotes();
          widget.onNotesChanged?.call();
          break;
      }
    } else {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.delete:
        case LogicalKeyboardKey.backspace:
          NativeFFI.instance.pianoRollDeleteSelected(widget.clipId);
          _loadNotes();
          widget.onNotesChanged?.call();
          break;
        case LogicalKeyboardKey.escape:
          NativeFFI.instance.pianoRollDeselectAll(widget.clipId);
          _loadNotes();
          break;
        case LogicalKeyboardKey.keyS:
          setState(() => _tool = PianoRollTool.select);
          break;
        case LogicalKeyboardKey.keyD:
          setState(() => _tool = PianoRollTool.draw);
          break;
        case LogicalKeyboardKey.keyE:
          setState(() => _tool = PianoRollTool.erase);
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Container(
        decoration: BoxDecoration(
          color: ReelForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ReelForgeTheme.border),
        ),
        child: Column(
          children: [
            // Toolbar
            _buildToolbar(),
            Divider(height: 1, color: ReelForgeTheme.border),

            // Main content
            Expanded(
              child: Row(
                children: [
                  // Piano keys
                  SizedBox(
                    width: keysWidth,
                    child: _buildPianoKeys(),
                  ),

                  // Grid and notes
                  Expanded(
                    child: _buildNoteGrid(),
                  ),
                ],
              ),
            ),

            // Velocity lane
            if (_showVelocity) ...[
              Divider(height: 1, color: ReelForgeTheme.border),
              SizedBox(
                height: velocityLaneHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: keysWidth,
                      child: Center(
                        child: Text(
                          'Velocity',
                          style: TextStyle(
                            color: ReelForgeTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _buildVelocityLane()),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Tools
          for (final tool in PianoRollTool.values)
            Tooltip(
              message: tool.label,
              child: IconButton(
                icon: Icon(
                  tool.icon,
                  size: 18,
                  color: _tool == tool
                      ? ReelForgeTheme.accentBlue
                      : ReelForgeTheme.textSecondary,
                ),
                onPressed: () => setState(() => _tool = tool),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),

          const VerticalDivider(width: 16),

          // Grid selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<GridDivision>(
              value: _grid,
              dropdownColor: ReelForgeTheme.surfaceDark,
              style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 12),
              underline: const SizedBox(),
              items: GridDivision.values.map((g) => DropdownMenuItem(
                value: g,
                child: Text(g.label),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _grid = v);
                  NativeFFI.instance.pianoRollSetGrid(widget.clipId, v.index);
                }
              },
            ),
          ),

          const SizedBox(width: 8),

          // Snap toggle
          Tooltip(
            message: 'Snap to Grid',
            child: IconButton(
              icon: Icon(
                Icons.grid_on,
                size: 18,
                color: _snapEnabled
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textSecondary,
              ),
              onPressed: () {
                setState(() => _snapEnabled = !_snapEnabled);
                NativeFFI.instance.pianoRollSetSnap(widget.clipId, _snapEnabled);
              },
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),

          const Spacer(),

          // Note count
          Text(
            '${_notes.length} notes',
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
          ),

          const SizedBox(width: 16),

          // Velocity toggle
          Tooltip(
            message: 'Show Velocity',
            child: IconButton(
              icon: Icon(
                Icons.bar_chart,
                size: 18,
                color: _showVelocity
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textSecondary,
              ),
              onPressed: () => setState(() => _showVelocity = !_showVelocity),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),

          // Zoom controls
          IconButton(
            icon: Icon(Icons.zoom_out, size: 18, color: ReelForgeTheme.textSecondary),
            onPressed: () => setState(() {
              _pixelsPerBeat = (_pixelsPerBeat / 1.25).clamp(20.0, 500.0);
            }),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.zoom_in, size: 18, color: ReelForgeTheme.textSecondary),
            onPressed: () => setState(() {
              _pixelsPerBeat = (_pixelsPerBeat * 1.25).clamp(20.0, 500.0);
            }),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildPianoKeys() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final visibleNotes = (height / _pixelsPerNote).ceil() + 1;
        final startNote = _visibleNoteHigh - (_scrollY / _pixelsPerNote).floor();

        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleNotes,
          itemBuilder: (context, index) {
            final note = startNote - index;
            if (note < 0 || note > 127) return const SizedBox();

            final isBlack = [1, 3, 6, 8, 10].contains(note % 12);
            final isC = note % 12 == 0;
            final octave = (note ~/ 12) - 1;
            final noteName = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][note % 12];

            return Container(
              height: _pixelsPerNote,
              decoration: BoxDecoration(
                color: isBlack
                    ? const Color(0xFF1a1a1a)
                    : const Color(0xFF2a2a2a),
                border: Border(
                  bottom: BorderSide(
                    color: isC ? ReelForgeTheme.border : Colors.transparent,
                    width: isC ? 1 : 0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (isC)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'C$octave',
                        style: TextStyle(
                          color: ReelForgeTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Container(
                    width: isBlack ? 50 : 60,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: isBlack
                          ? const Color(0xFF2a2a2a)
                          : const Color(0xFF4a4a4a),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoteGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          onTapDown: (details) => _handleTap(details, width, height),
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: ClipRect(
            child: CustomPaint(
              painter: _NoteGridPainter(
                notes: _notes,
                pixelsPerBeat: _pixelsPerBeat,
                pixelsPerNote: _pixelsPerNote,
                scrollX: _scrollX,
                scrollY: _scrollY,
                visibleNoteLow: _visibleNoteLow,
                visibleNoteHigh: _visibleNoteHigh,
                gridTicks: _getGridTicks(),
                lengthTicks: widget.lengthBars * 4 * ticksPerBeat,
                selectionRect: _selectionRect,
              ),
              size: Size(width, height),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVelocityLane() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _VelocityLanePainter(
            notes: _notes,
            pixelsPerBeat: _pixelsPerBeat,
            scrollX: _scrollX,
            gridTicks: _getGridTicks(),
            lengthTicks: widget.lengthBars * 4 * ticksPerBeat,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

// Custom painter for the note grid
class _NoteGridPainter extends CustomPainter {
  final List<PianoRollNote> notes;
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final double scrollX;
  final double scrollY;
  final int visibleNoteLow;
  final int visibleNoteHigh;
  final int gridTicks;
  final int lengthTicks;
  final Rect? selectionRect;

  static const int ticksPerBeat = 960;

  _NoteGridPainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.scrollX,
    required this.scrollY,
    required this.visibleNoteLow,
    required this.visibleNoteHigh,
    required this.gridTicks,
    required this.lengthTicks,
    this.selectionRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1a1a1a),
    );

    // Draw grid
    _drawGrid(canvas, size);

    // Draw notes
    _drawNotes(canvas, size);

    // Draw selection rectangle
    if (selectionRect != null) {
      canvas.drawRect(
        selectionRect!,
        Paint()
          ..color = ReelForgeTheme.accentBlue.withOpacity(0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        selectionRect!,
        Paint()
          ..color = ReelForgeTheme.accentBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a2a)
      ..strokeWidth = 1;

    final barPaint = Paint()
      ..color = const Color(0xFF3a3a3a)
      ..strokeWidth = 1;

    final beatPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;

    // Vertical lines (time)
    final barTicks = ticksPerBeat * 4;
    var tick = 0;
    while (tick <= lengthTicks) {
      final x = _tickToX(tick);
      if (x >= -10 && x <= size.width + 10) {
        Paint paint;
        if (tick % barTicks == 0) {
          paint = barPaint;
        } else if (tick % ticksPerBeat == 0) {
          paint = beatPaint;
        } else {
          paint = gridPaint;
        }
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      tick += gridTicks;
    }

    // Horizontal lines (notes)
    for (int note = visibleNoteHigh; note >= visibleNoteLow; note--) {
      final y = _noteToY(note);
      if (y >= -pixelsPerNote && y <= size.height + pixelsPerNote) {
        final isC = note % 12 == 0;
        final isBlack = [1, 3, 6, 8, 10].contains(note % 12);

        // Row background for black keys
        if (isBlack) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, pixelsPerNote),
            Paint()..color = const Color(0xFF151515),
          );
        }

        // C note separator
        if (isC) {
          canvas.drawLine(
            Offset(0, y + pixelsPerNote),
            Offset(size.width, y + pixelsPerNote),
            Paint()
              ..color = const Color(0xFF444444)
              ..strokeWidth = 1,
          );
        }
      }
    }
  }

  void _drawNotes(Canvas canvas, Size size) {
    for (final note in notes) {
      final x = _tickToX(note.startTick);
      final y = _noteToY(note.note);
      final width = (note.duration / ticksPerBeat) * pixelsPerBeat;

      if (x + width < 0 || x > size.width) continue;
      if (y + pixelsPerNote < 0 || y > size.height) continue;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y + 1, width - 1, pixelsPerNote - 2),
        const Radius.circular(2),
      );

      // Note color based on velocity
      final velocityFactor = note.velocity / 127.0;
      final baseColor = note.selected
          ? ReelForgeTheme.accentBlue
          : HSLColor.fromAHSL(1.0, 200, 0.7, 0.3 + velocityFactor * 0.3).toColor();

      // Fill
      canvas.drawRRect(
        rect,
        Paint()..color = note.muted ? baseColor.withOpacity(0.3) : baseColor,
      );

      // Border
      if (note.selected) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // Velocity indicator (darker bar at bottom)
      final velHeight = (pixelsPerNote - 4) * velocityFactor;
      canvas.drawRect(
        Rect.fromLTWH(x + 2, y + pixelsPerNote - 2 - velHeight, 3, velHeight),
        Paint()..color = Colors.white.withOpacity(0.3),
      );
    }
  }

  double _tickToX(int tick) {
    final beats = tick / ticksPerBeat;
    return beats * pixelsPerBeat - scrollX;
  }

  double _noteToY(int note) {
    final noteOffset = visibleNoteHigh - note;
    return noteOffset * pixelsPerNote - scrollY;
  }

  @override
  bool shouldRepaint(covariant _NoteGridPainter oldDelegate) {
    return notes != oldDelegate.notes ||
           pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           scrollX != oldDelegate.scrollX ||
           scrollY != oldDelegate.scrollY ||
           selectionRect != oldDelegate.selectionRect;
  }
}

// Custom painter for velocity lane
class _VelocityLanePainter extends CustomPainter {
  final List<PianoRollNote> notes;
  final double pixelsPerBeat;
  final double scrollX;
  final int gridTicks;
  final int lengthTicks;

  static const int ticksPerBeat = 960;

  _VelocityLanePainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.scrollX,
    required this.gridTicks,
    required this.lengthTicks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1a1a1a),
    );

    // Grid lines
    final barTicks = ticksPerBeat * 4;
    var tick = 0;
    while (tick <= lengthTicks) {
      final x = _tickToX(tick);
      if (x >= -10 && x <= size.width + 10) {
        final isBar = tick % barTicks == 0;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = isBar ? const Color(0xFF3a3a3a) : const Color(0xFF2a2a2a)
            ..strokeWidth = 1,
        );
      }
      tick += gridTicks;
    }

    // Velocity bars
    for (final note in notes) {
      final x = _tickToX(note.startTick);
      final width = (note.duration / ticksPerBeat) * pixelsPerBeat;

      if (x + width < 0 || x > size.width) continue;

      final velHeight = (size.height - 4) * (note.velocity / 127.0);
      final barWidth = width.clamp(2.0, 20.0);

      canvas.drawRect(
        Rect.fromLTWH(
          x + (width - barWidth) / 2,
          size.height - velHeight - 2,
          barWidth,
          velHeight,
        ),
        Paint()
          ..color = note.selected
              ? ReelForgeTheme.accentBlue
              : const Color(0xFF4080ff).withOpacity(0.7),
      );
    }
  }

  double _tickToX(int tick) {
    final beats = tick / ticksPerBeat;
    return beats * pixelsPerBeat - scrollX;
  }

  @override
  bool shouldRepaint(covariant _VelocityLanePainter oldDelegate) {
    return notes != oldDelegate.notes ||
           pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           scrollX != oldDelegate.scrollX;
  }
}

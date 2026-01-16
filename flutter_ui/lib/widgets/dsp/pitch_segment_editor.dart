/// Pitch Segment Editor - VariAudio-Style Visual Pitch Editor
///
/// Professional pitch segment editing with:
/// - Visual pitch segment display
/// - Drag segments to change pitch
/// - Split/merge segments
/// - Pitch contour visualization
/// - Auto-correct to scale

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Main pitch segment editor widget
class PitchSegmentEditor extends StatefulWidget {
  final int clipId;
  final double sampleRate;
  final int clipDuration; // Total duration in samples
  final VoidCallback? onChanged;

  const PitchSegmentEditor({
    super.key,
    required this.clipId,
    this.sampleRate = 48000.0,
    required this.clipDuration,
    this.onChanged,
  });

  @override
  State<PitchSegmentEditor> createState() => _PitchSegmentEditorState();
}

class _PitchSegmentEditorState extends State<PitchSegmentEditor> {
  final _ffi = NativeFFI.instance;

  // State
  List<PitchSegmentData> _segments = [];
  int? _selectedSegmentId;
  bool _isAnalyzing = false;
  bool _hasAnalyzed = false;

  // View state
  double _horizontalZoom = 1.0;
  double _verticalZoom = 1.0;
  double _scrollOffset = 0.0;
  int _minMidiNote = 36; // C2
  int _maxMidiNote = 84; // C6

  // Drag state
  int? _draggingSegmentId;
  double _dragStartY = 0.0;
  double _dragStartPitch = 0.0;

  // Note names
  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  @override
  void initState() {
    super.initState();
    _checkExistingAnalysis();
  }

  void _checkExistingAnalysis() {
    final count = _ffi.pitchGetSegmentCount(widget.clipId);
    if (count > 0) {
      _loadSegments();
      _hasAnalyzed = true;
    }
  }

  Future<void> _analyzeClip() async {
    setState(() => _isAnalyzing = true);

    // Run analysis (potentially long operation)
    final segmentCount = _ffi.pitchAnalyzeClip(widget.clipId);
    debugPrint('[PitchEditor] Analyzed clip ${widget.clipId}: $segmentCount segments');

    if (segmentCount > 0) {
      _loadSegments();
      _hasAnalyzed = true;
    }

    setState(() => _isAnalyzing = false);
  }

  void _loadSegments() {
    _segments = _ffi.pitchGetSegments(widget.clipId);

    // Calculate pitch range for view
    if (_segments.isNotEmpty) {
      int minNote = 127;
      int maxNote = 0;
      for (final seg in _segments) {
        minNote = math.min(minNote, seg.midiNote);
        maxNote = math.max(maxNote, seg.midiNote);
      }
      // Add padding
      _minMidiNote = math.max(0, minNote - 6);
      _maxMidiNote = math.min(127, maxNote + 6);
    }

    setState(() {});
  }

  void _onSegmentTap(int segmentId) {
    setState(() => _selectedSegmentId = segmentId);
  }

  void _onSegmentDragStart(int segmentId, double localY) {
    final segment = _segments.firstWhere((s) => s.id == segmentId);
    _draggingSegmentId = segmentId;
    _dragStartY = localY;
    _dragStartPitch = segment.targetPitchMidi;
  }

  void _onSegmentDrag(double localY, double height) {
    if (_draggingSegmentId == null) return;

    // Calculate pitch change based on drag distance
    final noteRange = _maxMidiNote - _minMidiNote;
    final pixelsPerSemitone = height / noteRange;
    final deltaY = _dragStartY - localY; // Negative = down = lower pitch
    final deltaSemitones = deltaY / pixelsPerSemitone;

    // Apply shift to segment
    final newPitch = _dragStartPitch + deltaSemitones;
    final semitoneShift = newPitch - _segments.firstWhere((s) => s.id == _draggingSegmentId).pitchMidi;

    _ffi.pitchSetSegmentShift(widget.clipId, _draggingSegmentId!, semitoneShift);
    _loadSegments();
    widget.onChanged?.call();
  }

  void _onSegmentDragEnd() {
    _draggingSegmentId = null;
  }

  void _quantizeSelected() {
    if (_selectedSegmentId != null) {
      _ffi.pitchQuantizeSegment(widget.clipId, _selectedSegmentId!);
      _loadSegments();
      widget.onChanged?.call();
    }
  }

  void _resetSelected() {
    if (_selectedSegmentId != null) {
      _ffi.pitchResetSegment(widget.clipId, _selectedSegmentId!);
      _loadSegments();
      widget.onChanged?.call();
    }
  }

  void _quantizeAll() {
    _ffi.pitchQuantizeAll(widget.clipId);
    _loadSegments();
    widget.onChanged?.call();
  }

  void _resetAll() {
    _ffi.pitchResetAll(widget.clipId);
    _loadSegments();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: _hasAnalyzed ? _buildEditor() : _buildAnalyzePrompt(),
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
          Icon(Icons.tune, color: FluxForgeTheme.accentCyan, size: 20),
          const SizedBox(width: 8),
          const Text(
            'PITCH EDITOR',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_hasAnalyzed) ...[
            // Segment count
            Text(
              '${_segments.length} segments',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 16),
            // Quantize all button
            _buildToolButton(
              icon: Icons.grid_on,
              label: 'Quantize All',
              onTap: _quantizeAll,
            ),
            const SizedBox(width: 8),
            // Reset all button
            _buildToolButton(
              icon: Icons.refresh,
              label: 'Reset All',
              onTap: _resetAll,
            ),
            const SizedBox(width: 8),
            // Re-analyze button
            _buildToolButton(
              icon: Icons.analytics,
              label: 'Re-analyze',
              onTap: _analyzeClip,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderMedium),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzePrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isAnalyzing) ...[
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentCyan),
            ),
            const SizedBox(height: 16),
            const Text(
              'Analyzing pitch...',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ] else ...[
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: FluxForgeTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No pitch analysis available',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click Analyze to detect pitch segments',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _analyzeClip,
              icon: const Icon(Icons.analytics),
              label: const Text('Analyze Pitch'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentCyan,
                foregroundColor: FluxForgeTheme.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Row(
      children: [
        // Piano keyboard (note labels)
        SizedBox(
          width: 50,
          child: _buildPianoKeyboard(),
        ),
        // Segment canvas
        Expanded(
          child: _buildSegmentCanvas(),
        ),
      ],
    );
  }

  Widget _buildPianoKeyboard() {
    final noteRange = _maxMidiNote - _minMidiNote;

    return CustomPaint(
      painter: _PianoKeyboardPainter(
        minNote: _minMidiNote,
        maxNote: _maxMidiNote,
      ),
      size: Size.infinite,
    );
  }

  Widget _buildSegmentCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) {
            // Deselect if clicking on empty space
            setState(() => _selectedSegmentId = null);
          },
          onPanEnd: (_) => _onSegmentDragEnd(),
          child: CustomPaint(
            painter: _SegmentCanvasPainter(
              segments: _segments,
              selectedId: _selectedSegmentId,
              clipDuration: widget.clipDuration,
              minMidiNote: _minMidiNote,
              maxMidiNote: _maxMidiNote,
              horizontalZoom: _horizontalZoom,
              scrollOffset: _scrollOffset,
            ),
            child: Stack(
              children: _segments.map((segment) {
                return _buildSegmentOverlay(segment, constraints);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegmentOverlay(PitchSegmentData segment, BoxConstraints constraints) {
    final noteRange = _maxMidiNote - _minMidiNote;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // Calculate segment position
    final x = (segment.start / widget.clipDuration) * width * _horizontalZoom - _scrollOffset;
    final segWidth = ((segment.end - segment.start) / widget.clipDuration) * width * _horizontalZoom;

    // Calculate Y based on target pitch
    final pitchNormalized = (segment.targetPitchMidi - _minMidiNote) / noteRange;
    final y = height - (pitchNormalized * height) - 10; // Invert Y, center on segment

    if (x + segWidth < 0 || x > width) return const SizedBox.shrink();

    final isSelected = segment.id == _selectedSegmentId;

    return Positioned(
      left: x,
      top: y,
      width: segWidth,
      height: 20,
      child: GestureDetector(
        onTap: () => _onSegmentTap(segment.id),
        onPanStart: (details) => _onSegmentDragStart(segment.id, details.localPosition.dy + y),
        onPanUpdate: (details) => _onSegmentDrag(details.localPosition.dy + y, height),
        onPanEnd: (_) => _onSegmentDragEnd(),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accentCyan.withOpacity(0.8)
                  : (segment.edited
                      ? FluxForgeTheme.accentOrange.withOpacity(0.6)
                      : FluxForgeTheme.accentBlue.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? FluxForgeTheme.accentCyan : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                segment.targetNoteName,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Piano keyboard painter for note labels
class _PianoKeyboardPainter extends CustomPainter {
  final int minNote;
  final int maxNote;

  _PianoKeyboardPainter({
    required this.minNote,
    required this.maxNote,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final noteRange = maxNote - minNote;
    final noteHeight = size.height / noteRange;

    for (int note = minNote; note <= maxNote; note++) {
      final y = size.height - ((note - minNote + 0.5) * noteHeight);
      final noteInOctave = note % 12;
      final isBlack = [1, 3, 6, 8, 10].contains(noteInOctave);

      // Draw note label for C notes or selected notes
      if (noteInOctave == 0) {
        final octave = (note ~/ 12) - 1;
        final text = 'C$octave';

        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(4, y - textPainter.height / 2),
        );
      }

      // Draw horizontal grid line
      final linePaint = Paint()
        ..color = isBlack
            ? FluxForgeTheme.borderSubtle.withOpacity(0.3)
            : FluxForgeTheme.borderSubtle.withOpacity(0.5)
        ..strokeWidth = isBlack ? 0.5 : 1;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PianoKeyboardPainter oldDelegate) =>
      minNote != oldDelegate.minNote || maxNote != oldDelegate.maxNote;
}

/// Segment canvas painter
class _SegmentCanvasPainter extends CustomPainter {
  final List<PitchSegmentData> segments;
  final int? selectedId;
  final int clipDuration;
  final int minMidiNote;
  final int maxMidiNote;
  final double horizontalZoom;
  final double scrollOffset;

  _SegmentCanvasPainter({
    required this.segments,
    this.selectedId,
    required this.clipDuration,
    required this.minMidiNote,
    required this.maxMidiNote,
    required this.horizontalZoom,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final noteRange = maxMidiNote - minMidiNote;

    // Draw horizontal grid lines for each note
    for (int note = minMidiNote; note <= maxMidiNote; note++) {
      final y = size.height - ((note - minMidiNote + 0.5) / noteRange * size.height);
      final noteInOctave = note % 12;
      final isC = noteInOctave == 0;

      final paint = Paint()
        ..color = isC
            ? FluxForgeTheme.borderMedium.withOpacity(0.5)
            : FluxForgeTheme.borderSubtle.withOpacity(0.2)
        ..strokeWidth = isC ? 1 : 0.5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw pitch contour lines (connecting original to target)
    for (final segment in segments) {
      final x1 = (segment.start / clipDuration) * size.width * horizontalZoom - scrollOffset;
      final x2 = (segment.end / clipDuration) * size.width * horizontalZoom - scrollOffset;

      if (x2 < 0 || x1 > size.width) continue;

      // Original pitch line
      final origY = size.height - ((segment.pitchMidi - minMidiNote) / noteRange * size.height);
      final targetY = size.height - ((segment.targetPitchMidi - minMidiNote) / noteRange * size.height);

      // Draw original pitch as dotted line if different from target
      if ((segment.pitchMidi - segment.targetPitchMidi).abs() > 0.01) {
        final origPaint = Paint()
          ..color = FluxForgeTheme.textTertiary.withOpacity(0.5)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;

        // Dotted line
        const dashWidth = 4.0;
        for (double dx = x1; dx < x2; dx += dashWidth * 2) {
          canvas.drawLine(
            Offset(dx, origY),
            Offset(math.min(dx + dashWidth, x2), origY),
            origPaint,
          );
        }

        // Vertical connector
        canvas.drawLine(
          Offset((x1 + x2) / 2, origY),
          Offset((x1 + x2) / 2, targetY),
          origPaint..strokeWidth = 0.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SegmentCanvasPainter oldDelegate) => true;
}

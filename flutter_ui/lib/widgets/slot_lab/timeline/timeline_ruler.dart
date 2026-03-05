// Timeline Ruler — Time Reference Display
//
// Displays time units with major/minor ticks, supports multiple display modes:
// - Milliseconds (1000ms, 2000ms)
// - Seconds (1.0s, 2.5s)
// - Beats (1.1.1 - bar.beat.tick)
// - Timecode (00:00:01:00 SMPTE)

import 'package:flutter/material.dart';
import '../../../models/timeline/timeline_state.dart';

class TimelineRuler extends StatelessWidget {
  final double duration;
  final double zoom;
  final TimeDisplayMode displayMode;
  final GridMode gridMode;
  final int millisecondInterval;
  final int frameRate;
  final double? loopStart;
  final double? loopEnd;
  final VoidCallback? onLoopStartDrag;
  final VoidCallback? onLoopEndDrag;

  const TimelineRuler({
    super.key,
    required this.duration,
    this.zoom = 1.0,
    this.displayMode = TimeDisplayMode.seconds,
    this.gridMode = GridMode.millisecond,
    this.millisecondInterval = 100,
    this.frameRate = 60,
    this.loopStart,
    this.loopEnd,
    this.onLoopStartDrag,
    this.onLoopEndDrag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _TimelineRulerPainter(
              duration: duration,
              zoom: zoom,
              displayMode: displayMode,
              gridMode: gridMode,
              millisecondInterval: millisecondInterval,
              frameRate: frameRate,
            ),
          ),
          if (loopStart != null)
            _buildLoopHandle(
              position: loopStart! / duration,
              isStart: true,
              onDrag: onLoopStartDrag,
            ),
          if (loopEnd != null)
            _buildLoopHandle(
              position: loopEnd! / duration,
              isStart: false,
              onDrag: onLoopEndDrag,
            ),
        ],
      ),
    );
  }

  Widget _buildLoopHandle({
    required double position,
    required bool isStart,
    VoidCallback? onDrag,
  }) {
    return Positioned(
      left: position * 10000,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onPanUpdate: (_) => onDrag?.call(),
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9040).withOpacity(0.8),
            border: Border(
              left: isStart ? const BorderSide(color: Color(0xFFFF9040), width: 2) : BorderSide.none,
              right: !isStart ? const BorderSide(color: Color(0xFFFF9040), width: 2) : BorderSide.none,
            ),
          ),
          child: Center(
            child: Icon(
              isStart ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left,
              size: 10,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ruler CustomPainter — pre-allocated paints and cached ticks
class _TimelineRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;
  final TimeDisplayMode displayMode;
  final GridMode gridMode;
  final int millisecondInterval;
  final int frameRate;

  // Pre-allocated
  late final Paint _majorTickPaint;
  late final Paint _minorTickPaint;
  late final List<_GridLineTick> _ticks;
  late final Map<int, TextPainter> _labelPainters;

  _TimelineRulerPainter({
    required this.duration,
    required this.zoom,
    required this.displayMode,
    required this.gridMode,
    required this.millisecondInterval,
    required this.frameRate,
  }) {
    _majorTickPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 1.5;

    _minorTickPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0;

    _ticks = _generateTicks();

    // Pre-create TextPainters for major ticks
    _labelPainters = {};
    for (int i = 0; i < _ticks.length; i++) {
      final tick = _ticks[i];
      if (tick.isMajor && tick.label != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: tick.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _labelPainters[i] = tp;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _ticks.length; i++) {
      final tick = _ticks[i];
      final x = tick.position * size.width;
      final tickHeight = tick.isMajor ? 12.0 : 6.0;

      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        tick.isMajor ? _majorTickPaint : _minorTickPaint,
      );

      final tp = _labelPainters[i];
      if (tp != null) {
        tp.paint(canvas, Offset(x + 4, size.height - tickHeight - 14));
      }
    }
  }

  List<_GridLineTick> _generateTicks() {
    switch (gridMode) {
      case GridMode.millisecond:
        return _generateMillisecondTicks();
      case GridMode.frame:
        return _generateFrameTicks();
      case GridMode.beat:
        return _generateBeatTicks();
      case GridMode.free:
        return _generateSecondTicks();
    }
  }

  List<_GridLineTick> _generateMillisecondTicks() {
    final lines = <_GridLineTick>[];
    final intervalSeconds = millisecondInterval / 1000.0;

    int majorEvery = 10;
    if (zoom < 0.5) majorEvery = 20;
    if (zoom > 4.0) majorEvery = 5;

    int lineIndex = 0;
    for (double time = 0; time <= duration; time += intervalSeconds) {
      final isMajor = lineIndex % majorEvery == 0;
      final position = time / duration;

      lines.add(_GridLineTick(
        position: position,
        isMajor: isMajor,
        label: isMajor ? _formatTime(time) : null,
      ));

      lineIndex++;
    }

    return lines;
  }

  List<_GridLineTick> _generateFrameTicks() {
    final lines = <_GridLineTick>[];
    final frameSeconds = 1.0 / frameRate;
    final framesPerSecond = frameRate;

    int frameIndex = 0;
    for (double time = 0; time <= duration; time += frameSeconds) {
      final isMajor = frameIndex % framesPerSecond == 0;
      final position = time / duration;

      lines.add(_GridLineTick(
        position: position,
        isMajor: isMajor,
        label: isMajor ? _formatTime(time) : null,
      ));

      frameIndex++;
    }

    return lines;
  }

  List<_GridLineTick> _generateBeatTicks() {
    final lines = <_GridLineTick>[];
    const tempo = 120.0;
    final beatSeconds = 60.0 / tempo;

    int beatIndex = 0;
    for (double time = 0; time <= duration; time += beatSeconds) {
      final isMajor = beatIndex % 4 == 0;
      final position = time / duration;

      lines.add(_GridLineTick(
        position: position,
        isMajor: isMajor,
        label: isMajor ? '${(beatIndex ~/ 4) + 1}.1.1' : null,
      ));

      beatIndex++;
    }

    return lines;
  }

  List<_GridLineTick> _generateSecondTicks() {
    final lines = <_GridLineTick>[];

    for (double time = 0; time <= duration; time += 1.0) {
      final position = time / duration;

      lines.add(_GridLineTick(
        position: position,
        isMajor: true,
        label: _formatTime(time),
      ));
    }

    return lines;
  }

  String _formatTime(double timeSeconds) {
    switch (displayMode) {
      case TimeDisplayMode.milliseconds:
        return '${(timeSeconds * 1000).toInt()}ms';
      case TimeDisplayMode.seconds:
        return '${timeSeconds.toStringAsFixed(1)}s';
      case TimeDisplayMode.beats:
        return '1.1.1';
      case TimeDisplayMode.timecode:
        final hours = timeSeconds ~/ 3600;
        final minutes = (timeSeconds % 3600) ~/ 60;
        final seconds = (timeSeconds % 60).floor();
        final frames = ((timeSeconds % 1) * frameRate).floor();
        return '${hours.toString().padLeft(2, '0')}:'
            '${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}:'
            '${frames.toString().padLeft(2, '0')}';
    }
  }

  @override
  bool shouldRepaint(_TimelineRulerPainter oldDelegate) {
    return oldDelegate.duration != duration ||
        oldDelegate.zoom != zoom ||
        oldDelegate.displayMode != displayMode ||
        oldDelegate.gridMode != gridMode ||
        oldDelegate.millisecondInterval != millisecondInterval ||
        oldDelegate.frameRate != frameRate;
  }
}

class _GridLineTick {
  final double position;
  final bool isMajor;
  final String? label;

  const _GridLineTick({
    required this.position,
    required this.isMajor,
    this.label,
  });
}

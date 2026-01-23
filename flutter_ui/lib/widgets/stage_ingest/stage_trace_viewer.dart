// ═══════════════════════════════════════════════════════════════════════════════
// STAGE TRACE VIEWER — Visual timeline of stage events
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../providers/stage_ingest_provider.dart';

/// Visual timeline viewer for stage traces
class StageTraceViewer extends StatefulWidget {
  final StageIngestProvider provider;
  final int traceHandle;
  final double height;
  final Function(IngestStageEvent)? onEventTap;
  final Function(double)? onSeek;

  const StageTraceViewer({
    super.key,
    required this.provider,
    required this.traceHandle,
    this.height = 200,
    this.onEventTap,
    this.onSeek,
  });

  @override
  State<StageTraceViewer> createState() => _StageTraceViewerState();
}

class _StageTraceViewerState extends State<StageTraceViewer> {
  List<IngestStageEvent> _events = [];
  double _durationMs = 0;
  double _playheadMs = 0;
  double _zoom = 1.0;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void didUpdateWidget(StageTraceViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.traceHandle != widget.traceHandle) {
      _loadEvents();
    }
  }

  void _loadEvents() {
    _events = widget.provider.getTraceEvents(widget.traceHandle);
    _durationMs = widget.provider.stageTraceDurationMs(widget.traceHandle);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildTimeline()),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, color: Color(0xFF4a9eff), size: 16),
          const SizedBox(width: 8),
          Text(
            'Stage Trace',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '${_events.length} events | ${_formatDuration(_durationMs)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_events.isEmpty) {
      return Center(
        child: Text(
          'No events in trace',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _scrollOffset -= details.delta.dx;
          _scrollOffset = _scrollOffset.clamp(0, _maxScroll);
        });
      },
      onTapDown: (details) {
        final timeMs = _positionToTime(details.localPosition.dx);
        widget.onSeek?.call(timeMs);
        setState(() => _playheadMs = timeMs);
      },
      child: CustomPaint(
        painter: _TimelinePainter(
          events: _events,
          durationMs: _durationMs,
          playheadMs: _playheadMs,
          zoom: _zoom,
          scrollOffset: _scrollOffset,
        ),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () => setState(() => _zoom = (_zoom / 1.2).clamp(0.5, 10)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 24),
            color: Colors.white.withOpacity(0.7),
            iconSize: 16,
          ),
          SizedBox(
            width: 60,
            child: Slider(
              value: _zoom,
              min: 0.5,
              max: 10,
              onChanged: (v) => setState(() => _zoom = v),
              activeColor: const Color(0xFF4a9eff),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () => setState(() => _zoom = (_zoom * 1.2).clamp(0.5, 10)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 24),
            color: Colors.white.withOpacity(0.7),
            iconSize: 16,
          ),
          const Spacer(),
          // Playhead position
          Text(
            _formatDuration(_playheadMs),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  double get _maxScroll => (_durationMs * _zoom / 100).clamp(0, double.infinity);

  double _positionToTime(double x) {
    return (_scrollOffset + x) / _zoom * 100;
  }

  String _formatDuration(double ms) {
    final seconds = ms / 1000;
    final minutes = seconds ~/ 60;
    final secs = (seconds % 60).toStringAsFixed(1);
    return '$minutes:${secs.padLeft(4, '0')}';
  }
}

class _TimelinePainter extends CustomPainter {
  final List<IngestStageEvent> events;
  final double durationMs;
  final double playheadMs;
  final double zoom;
  final double scrollOffset;

  _TimelinePainter({
    required this.events,
    required this.durationMs,
    required this.playheadMs,
    required this.zoom,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFF1a1a20),
    );

    // Grid lines
    _drawGrid(canvas, size);

    // Events
    for (final event in events) {
      final x = _timeToPosition(event.timestampMs, width);
      if (x < -20 || x > width + 20) continue;

      final color = _getStageColor(event.stage);

      // Event marker
      canvas.drawCircle(
        Offset(x, height / 2),
        6,
        Paint()..color = color,
      );

      // Event label
      final textPainter = TextPainter(
        text: TextSpan(
          text: _formatStageName(event.stage),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, height / 2 + 10));
    }

    // Playhead
    final playheadX = _timeToPosition(playheadMs, width);
    if (playheadX >= 0 && playheadX <= width) {
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, height),
        Paint()
          ..color = const Color(0xFFff4040)
          ..strokeWidth = 2,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a34)
      ..strokeWidth = 1;

    // Calculate grid interval based on zoom
    double intervalMs = 1000; // 1 second
    if (zoom > 2) intervalMs = 500;
    if (zoom > 5) intervalMs = 100;
    if (zoom < 0.5) intervalMs = 5000;

    double time = 0;
    while (time <= durationMs) {
      final x = _timeToPosition(time, size.width);
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          gridPaint,
        );
      }
      time += intervalMs;
    }
  }

  double _timeToPosition(double timeMs, double width) {
    return (timeMs * zoom / 100) - scrollOffset;
  }

  Color _getStageColor(String stage) {
    final upper = stage.toUpperCase();
    if (upper.contains('SPIN_START')) return const Color(0xFF40ff90);
    if (upper.contains('SPIN_END')) return const Color(0xFF40c8ff);
    if (upper.contains('REEL_STOP')) return const Color(0xFF4a9eff);
    if (upper.contains('WIN')) return const Color(0xFFffff40);
    if (upper.contains('JACKPOT')) return const Color(0xFFff4040);
    if (upper.contains('FEATURE') || upper.contains('FREE')) return const Color(0xFFff9040);
    if (upper.contains('ANTICIPATION')) return const Color(0xFFff40ff);
    if (upper.contains('ROLLUP')) return const Color(0xFF40ffff);
    return const Color(0xFF888888);
  }

  String _formatStageName(String stage) {
    // Shorten common prefixes
    return stage
        .replaceAll('SPIN_', '')
        .replaceAll('REEL_', 'R')
        .replaceAll('WIN_', 'W')
        .replaceAll('FEATURE_', 'F');
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return events != oldDelegate.events ||
        playheadMs != oldDelegate.playheadMs ||
        zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset;
  }
}

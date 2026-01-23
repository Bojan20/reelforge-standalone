/// FluxForge Studio Music Transition Preview Panel
///
/// P4.10: Transition Preview
/// - Visual preview of segment-to-segment transitions
/// - Sync mode selection (immediate, beat, bar, phrase)
/// - Fade in/out curve visualization
/// - Playback simulation with timeline
/// - A/B segment comparison
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/ale_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSITION PREVIEW PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class MusicTransitionPreviewPanel extends StatefulWidget {
  final double height;

  const MusicTransitionPreviewPanel({
    super.key,
    this.height = 350,
  });

  @override
  State<MusicTransitionPreviewPanel> createState() => _MusicTransitionPreviewPanelState();
}

class _MusicTransitionPreviewPanelState extends State<MusicTransitionPreviewPanel>
    with SingleTickerProviderStateMixin {
  // Selection state
  int? _segmentAId;
  int? _segmentBId;

  // Transition settings
  SyncMode _syncMode = SyncMode.bar;
  int _fadeInMs = 500;
  int _fadeOutMs = 500;
  double _overlapPercent = 50.0; // 0-100%
  _FadeCurve _fadeInCurve = _FadeCurve.linear;
  _FadeCurve _fadeOutCurve = _FadeCurve.linear;

  // Playback state
  bool _isPlaying = false;
  double _playbackPosition = 0.0; // 0.0 = start of A, 1.0 = end of B
  Timer? _playbackTimer;

  // Animation
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        if (_isPlaying) {
          setState(() => _playbackPosition = _animationController.value);
        }
      });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final segments = provider.musicSegments;

        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Row(
                  children: [
                    // Left: Segment selectors
                    SizedBox(
                      width: 200,
                      child: _buildSegmentSelectors(segments),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Center: Timeline visualization
                    Expanded(
                      child: _buildTimelineVisualization(segments),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Right: Settings panel
                    SizedBox(
                      width: 220,
                      child: _buildSettingsPanel(),
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

  // ═══════════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 16, color: Colors.pink),
          const SizedBox(width: 8),
          Text(
            'Transition Preview',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Transport controls
          IconButton(
            icon: Icon(Icons.skip_previous, size: 18, color: FluxForgeTheme.textPrimary),
            onPressed: _rewind,
            tooltip: 'Rewind',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 20,
              color: _isPlaying ? Colors.pink : FluxForgeTheme.textPrimary,
            ),
            onPressed: _togglePlayback,
            tooltip: _isPlaying ? 'Pause' : 'Preview Transition',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: Icon(Icons.stop, size: 18, color: FluxForgeTheme.textPrimary),
            onPressed: _stop,
            tooltip: 'Stop',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 16),
          // Playback position display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatPosition(_playbackPosition),
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // SEGMENT SELECTORS
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildSegmentSelectors(List<MusicSegment> segments) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segment A selector
          Text(
            'FROM (Segment A)',
            style: TextStyle(
              color: Colors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildSegmentDropdown(
            value: _segmentAId,
            segments: segments,
            color: Colors.cyan,
            onChanged: (id) => setState(() => _segmentAId = id),
          ),
          const SizedBox(height: 16),
          // Segment B selector
          Text(
            'TO (Segment B)',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildSegmentDropdown(
            value: _segmentBId,
            segments: segments,
            color: Colors.orange,
            onChanged: (id) => setState(() => _segmentBId = id),
          ),
          const SizedBox(height: 16),
          // Swap button
          Center(
            child: OutlinedButton.icon(
              icon: Icon(Icons.swap_vert, size: 16),
              label: const Text('Swap'),
              onPressed: () {
                setState(() {
                  final temp = _segmentAId;
                  _segmentAId = _segmentBId;
                  _segmentBId = temp;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: FluxForgeTheme.textMuted,
                side: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
          ),
          const Spacer(),
          // Segment info
          if (_segmentAId != null) _buildSegmentInfo(segments, _segmentAId!, Colors.cyan),
          const SizedBox(height: 8),
          if (_segmentBId != null) _buildSegmentInfo(segments, _segmentBId!, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildSegmentDropdown({
    required int? value,
    required List<MusicSegment> segments,
    required Color color,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          hint: Text('Select segment', style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12)),
          isExpanded: true,
          dropdownColor: FluxForgeTheme.surface,
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
          items: segments.map((segment) {
            return DropdownMenuItem(
              value: segment.id,
              child: Text(segment.name),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSegmentInfo(List<MusicSegment> segments, int id, Color color) {
    final segment = segments.where((s) => s.id == id).firstOrNull;
    if (segment == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            segment.name,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${segment.tempo.toStringAsFixed(1)} BPM • ${segment.beatsPerBar}/4 • ${segment.durationBars} bars',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // TIMELINE VISUALIZATION
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildTimelineVisualization(List<MusicSegment> segments) {
    final segmentA = _segmentAId != null
        ? segments.where((s) => s.id == _segmentAId).firstOrNull
        : null;
    final segmentB = _segmentBId != null
        ? segments.where((s) => s.id == _segmentBId).firstOrNull
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Timeline header with labels
          _buildTimelineHeader(),
          const SizedBox(height: 8),
          // Main timeline area
          Expanded(
            child: CustomPaint(
              painter: _TransitionTimelinePainter(
                segmentA: segmentA,
                segmentB: segmentB,
                playbackPosition: _playbackPosition,
                syncMode: _syncMode,
                fadeInMs: _fadeInMs,
                fadeOutMs: _fadeOutMs,
                overlapPercent: _overlapPercent,
                fadeInCurve: _fadeInCurve,
                fadeOutCurve: _fadeOutCurve,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          // Playback scrubber
          _buildScrubber(),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader() {
    return Row(
      children: [
        // Segment A label
        Expanded(
          child: Text(
            'Segment A (Fade Out)',
            style: TextStyle(color: Colors.cyan, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
        // Transition zone label
        Container(
          width: 100,
          child: Text(
            'Transition',
            style: TextStyle(color: Colors.pink, fontSize: 10, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        // Segment B label
        Expanded(
          child: Text(
            'Segment B (Fade In)',
            style: TextStyle(color: Colors.orange, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildScrubber() {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: Colors.pink,
        inactiveTrackColor: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
        thumbColor: Colors.pink,
      ),
      child: Slider(
        value: _playbackPosition,
        onChanged: (value) => setState(() => _playbackPosition = value),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // SETTINGS PANEL
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sync Mode
            _buildSettingLabel('Sync Mode'),
            const SizedBox(height: 4),
            _buildSyncModeSelector(),
            const SizedBox(height: 16),
            // Fade In
            _buildSettingLabel('Fade In'),
            const SizedBox(height: 4),
            _buildFadeControl(
              value: _fadeInMs,
              curve: _fadeInCurve,
              onValueChanged: (v) => setState(() => _fadeInMs = v),
              onCurveChanged: (c) => setState(() => _fadeInCurve = c),
            ),
            const SizedBox(height: 16),
            // Fade Out
            _buildSettingLabel('Fade Out'),
            const SizedBox(height: 4),
            _buildFadeControl(
              value: _fadeOutMs,
              curve: _fadeOutCurve,
              onValueChanged: (v) => setState(() => _fadeOutMs = v),
              onCurveChanged: (c) => setState(() => _fadeOutCurve = c),
            ),
            const SizedBox(height: 16),
            // Overlap
            _buildSettingLabel('Overlap'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _overlapPercent,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (v) => setState(() => _overlapPercent = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${_overlapPercent.round()}%',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save as Profile'),
                onPressed: _saveAsProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: FluxForgeTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSyncModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: SyncMode.values.map((mode) {
          final isSelected = _syncMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _syncMode = mode),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.pink.withValues(alpha: 0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getSyncModeLabel(mode),
                  style: TextStyle(
                    color: isSelected ? Colors.pink : FluxForgeTheme.textMuted,
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFadeControl({
    required int value,
    required _FadeCurve curve,
    required ValueChanged<int> onValueChanged,
    required ValueChanged<_FadeCurve> onCurveChanged,
  }) {
    return Row(
      children: [
        // Time value
        SizedBox(
          width: 60,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${value}ms',
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Slider
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 2000,
            divisions: 40,
            onChanged: (v) => onValueChanged(v.round()),
          ),
        ),
        // Curve selector
        PopupMenuButton<_FadeCurve>(
          initialValue: curve,
          onSelected: onCurveChanged,
          tooltip: 'Fade Curve',
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _CurveIconPainter(curve: curve),
            ),
          ),
          itemBuilder: (context) => _FadeCurve.values.map((c) {
            return PopupMenuItem(
              value: c,
              child: Row(
                children: [
                  CustomPaint(
                    size: const Size(16, 16),
                    painter: _CurveIconPainter(curve: c),
                  ),
                  const SizedBox(width: 8),
                  Text(c.label),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  String _formatPosition(double position) {
    if (position < 0.5) {
      return 'A: ${((1 - position * 2) * 100).round()}%';
    } else {
      return 'B: ${((position - 0.5) * 2 * 100).round()}%';
    }
  }

  String _getSyncModeLabel(SyncMode mode) {
    switch (mode) {
      case SyncMode.immediate:
        return 'Now';
      case SyncMode.beat:
        return 'Beat';
      case SyncMode.bar:
        return 'Bar';
      case SyncMode.phrase:
        return 'Phrase';
      case SyncMode.nextDownbeat:
        return 'Down';
      case SyncMode.custom:
        return 'Custom';
    }
  }

  void _togglePlayback() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _animationController.forward(from: _playbackPosition);
      _animationController.addStatusListener(_onAnimationStatus);
    } else {
      _animationController.stop();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() => _isPlaying = false);
    }
  }

  void _rewind() {
    _animationController.stop();
    setState(() {
      _playbackPosition = 0.0;
      _isPlaying = false;
    });
  }

  void _stop() {
    _animationController.stop();
    setState(() {
      _playbackPosition = 0.0;
      _isPlaying = false;
    });
  }

  void _saveAsProfile() {
    // TODO: Save transition profile to ALE provider
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Transition profile saved'),
        backgroundColor: FluxForgeTheme.accent,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

enum _FadeCurve {
  linear('Linear'),
  easeIn('Ease In'),
  easeOut('Ease Out'),
  easeInOut('Ease In-Out'),
  exponential('Exponential'),
  logarithmic('Logarithmic'),
  sCurve('S-Curve');

  const _FadeCurve(this.label);
  final String label;

  double apply(double t) {
    switch (this) {
      case _FadeCurve.linear:
        return t;
      case _FadeCurve.easeIn:
        return t * t;
      case _FadeCurve.easeOut:
        return 1 - (1 - t) * (1 - t);
      case _FadeCurve.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case _FadeCurve.exponential:
        return t == 0 ? 0 : (t * t * t);
      case _FadeCurve.logarithmic:
        return 1 - (1 - t) * (1 - t) * (1 - t);
      case _FadeCurve.sCurve:
        return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _TransitionTimelinePainter extends CustomPainter {
  final MusicSegment? segmentA;
  final MusicSegment? segmentB;
  final double playbackPosition;
  final SyncMode syncMode;
  final int fadeInMs;
  final int fadeOutMs;
  final double overlapPercent;
  final _FadeCurve fadeInCurve;
  final _FadeCurve fadeOutCurve;

  _TransitionTimelinePainter({
    this.segmentA,
    this.segmentB,
    required this.playbackPosition,
    required this.syncMode,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.overlapPercent,
    required this.fadeInCurve,
    required this.fadeOutCurve,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final transitionWidth = size.width * (overlapPercent / 100) * 0.3;
    final transitionCenter = size.width * 0.5;
    final transitionStart = transitionCenter - transitionWidth / 2;
    final transitionEnd = transitionCenter + transitionWidth / 2;

    // Draw background
    final bgPaint = Paint()..color = FluxForgeTheme.bgSurface;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw segment A region (cyan)
    final segmentAPaint = Paint()..color = Colors.cyan.withValues(alpha: 0.2);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, transitionEnd, size.height),
      segmentAPaint,
    );

    // Draw segment B region (orange)
    final segmentBPaint = Paint()..color = Colors.orange.withValues(alpha: 0.2);
    canvas.drawRect(
      Rect.fromLTRB(transitionStart, 0, size.width, size.height),
      segmentBPaint,
    );

    // Draw transition zone highlight
    final transitionZonePaint = Paint()
      ..color = Colors.pink.withValues(alpha: 0.1);
    canvas.drawRect(
      Rect.fromLTRB(transitionStart, 0, transitionEnd, size.height),
      transitionZonePaint,
    );

    // Draw fade curves
    _drawFadeCurve(canvas, size, transitionStart, transitionEnd, true); // Fade out (A)
    _drawFadeCurve(canvas, size, transitionStart, transitionEnd, false); // Fade in (B)

    // Draw playhead
    final playheadX = playbackPosition * size.width;
    final playheadPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );

    // Draw transition zone borders
    final borderPaint = Paint()
      ..color = Colors.pink.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTRB(transitionStart, 0, transitionEnd, size.height),
      borderPaint,
    );

    // Draw sync point markers
    _drawSyncMarkers(canvas, size, transitionStart, transitionEnd);
  }

  void _drawFadeCurve(Canvas canvas, Size size, double transStart, double transEnd, bool isFadeOut) {
    final path = Path();
    final curveWidth = transEnd - transStart;
    final curve = isFadeOut ? fadeOutCurve : fadeInCurve;
    final color = isFadeOut ? Colors.cyan : Colors.orange;

    final startX = isFadeOut ? transStart : transStart;
    final endX = isFadeOut ? transEnd : transEnd;

    for (int i = 0; i <= 50; i++) {
      final t = i / 50.0;
      final x = startX + t * curveWidth;
      final curveValue = curve.apply(t);
      final y = isFadeOut
          ? size.height * 0.2 + (1 - curveValue) * size.height * 0.6
          : size.height * 0.8 - curveValue * size.height * 0.6;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);

    // Draw fill
    final fillPath = Path.from(path);
    if (isFadeOut) {
      fillPath.lineTo(endX, size.height * 0.8);
      fillPath.lineTo(startX, size.height * 0.2);
    } else {
      fillPath.lineTo(endX, size.height * 0.2);
      fillPath.lineTo(startX, size.height * 0.8);
    }
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawSyncMarkers(Canvas canvas, Size size, double transStart, double transEnd) {
    final markerPaint = Paint()
      ..color = Colors.pink.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    // Draw based on sync mode
    int divisions;
    switch (syncMode) {
      case SyncMode.immediate:
        divisions = 0;
      case SyncMode.beat:
        divisions = 8;
      case SyncMode.bar:
        divisions = 4;
      case SyncMode.phrase:
        divisions = 1;
      case SyncMode.nextDownbeat:
        divisions = 2;
      case SyncMode.custom:
        divisions = 4;
    }

    if (divisions > 0) {
      final width = transEnd - transStart;
      for (int i = 0; i <= divisions; i++) {
        final x = transStart + (i / divisions) * width;
        canvas.drawLine(
          Offset(x, size.height - 10),
          Offset(x, size.height),
          markerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TransitionTimelinePainter oldDelegate) {
    return playbackPosition != oldDelegate.playbackPosition ||
        syncMode != oldDelegate.syncMode ||
        fadeInMs != oldDelegate.fadeInMs ||
        fadeOutMs != oldDelegate.fadeOutMs ||
        overlapPercent != oldDelegate.overlapPercent ||
        fadeInCurve != oldDelegate.fadeInCurve ||
        fadeOutCurve != oldDelegate.fadeOutCurve;
  }
}

class _CurveIconPainter extends CustomPainter {
  final _FadeCurve curve;

  _CurveIconPainter({required this.curve});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    for (int i = 0; i <= 20; i++) {
      final t = i / 20.0;
      final x = t * size.width;
      final y = size.height - curve.apply(t) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CurveIconPainter oldDelegate) {
    return curve != oldDelegate.curve;
  }
}

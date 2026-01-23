/// FluxForge Studio Music Segment Looping Panel
///
/// P4.12: Music Segment Looping
/// - Loop region editor with start/end handles
/// - Visual waveform with loop markers
/// - Crossfade settings for seamless loops
/// - Loop count and infinite toggle
/// - Preview with visual playhead
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC SEGMENT LOOPING PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class MusicSegmentLoopingPanel extends StatefulWidget {
  final int? segmentId;
  final double height;

  const MusicSegmentLoopingPanel({
    super.key,
    this.segmentId,
    this.height = 300,
  });

  @override
  State<MusicSegmentLoopingPanel> createState() => _MusicSegmentLoopingPanelState();
}

class _MusicSegmentLoopingPanelState extends State<MusicSegmentLoopingPanel>
    with SingleTickerProviderStateMixin {
  // Playback state
  bool _isPlaying = false;
  double _playheadPosition = 0.0; // In bars
  int _currentLoopCount = 0;

  // Loop settings
  int _targetLoopCount = 0; // 0 = infinite
  double _crossfadeMs = 50.0;
  _CrossfadeShape _crossfadeShape = _CrossfadeShape.equalPower;

  // Drag state
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;
  bool _isDraggingPlayhead = false;

  // Animation
  late AnimationController _animationController;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  MusicSegment? _getSegment(MiddlewareProvider provider) {
    if (widget.segmentId == null) return null;
    return provider.musicSegments.where((s) => s.id == widget.segmentId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final segment = _getSegment(provider);

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
              _buildHeader(provider, segment),
              Expanded(
                child: segment != null
                    ? _buildContent(provider, segment)
                    : _buildEmptyState(),
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

  Widget _buildHeader(MiddlewareProvider provider, MusicSegment? segment) {
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
          Icon(Icons.loop, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            'Segment Looping',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (segment != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                segment.name,
                style: TextStyle(color: Colors.green, fontSize: 11),
              ),
            ),
          ],
          const Spacer(),
          // Transport controls
          _buildTransportControls(segment),
          const SizedBox(width: 16),
          // Loop status
          if (segment != null) _buildLoopStatus(segment),
        ],
      ),
    );
  }

  Widget _buildTransportControls(MusicSegment? segment) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous, size: 18, color: FluxForgeTheme.textPrimary),
          onPressed: segment != null ? _rewind : null,
          tooltip: 'Rewind',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            size: 20,
            color: _isPlaying ? Colors.green : FluxForgeTheme.textPrimary,
          ),
          onPressed: segment != null ? _togglePlayback : null,
          tooltip: _isPlaying ? 'Pause' : 'Play',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        IconButton(
          icon: Icon(Icons.stop, size: 18, color: FluxForgeTheme.textPrimary),
          onPressed: segment != null ? _stop : null,
          tooltip: 'Stop',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _buildLoopStatus(MusicSegment segment) {
    final hasLoop = segment.loopEndBars > segment.loopStartBars;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasLoop
            ? Colors.green.withValues(alpha: 0.2)
            : FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasLoop
              ? Colors.green.withValues(alpha: 0.5)
              : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasLoop ? Icons.repeat_on : Icons.repeat,
            size: 14,
            color: hasLoop ? Colors.green : FluxForgeTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            hasLoop
                ? 'Loop ${_currentLoopCount + 1}${_targetLoopCount > 0 ? "/$_targetLoopCount" : "/∞"}'
                : 'No Loop',
            style: TextStyle(
              color: hasLoop ? Colors.green : FluxForgeTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildContent(MiddlewareProvider provider, MusicSegment segment) {
    return Row(
      children: [
        // Left: Waveform with loop region
        Expanded(
          flex: 3,
          child: _buildWaveformArea(provider, segment),
        ),
        // Divider
        Container(
          width: 1,
          color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
        ),
        // Right: Loop settings
        SizedBox(
          width: 200,
          child: _buildLoopSettings(provider, segment),
        ),
      ],
    );
  }

  Widget _buildWaveformArea(MiddlewareProvider provider, MusicSegment segment) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Bar position display
          _buildPositionDisplay(segment),
          const SizedBox(height: 8),
          // Main waveform area
          Expanded(
            child: GestureDetector(
              onTapDown: (details) => _handleWaveformTap(provider, segment, details),
              child: CustomPaint(
                painter: _LoopWaveformPainter(
                  segment: segment,
                  playheadPosition: _playheadPosition,
                  isPlaying: _isPlaying,
                ),
                child: Stack(
                  children: [
                    // Loop region overlay
                    if (segment.loopEndBars > segment.loopStartBars)
                      _buildLoopRegionOverlay(provider, segment),
                    // Playhead
                    _buildPlayhead(segment),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Loop region quick controls
          _buildLoopQuickControls(provider, segment),
        ],
      ),
    );
  }

  Widget _buildPositionDisplay(MusicSegment segment) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Current position
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Pos: ${_formatBars(_playheadPosition, segment.beatsPerBar)}',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
        // Loop region
        if (segment.loopEndBars > segment.loopStartBars)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Loop: ${_formatBars(segment.loopStartBars, segment.beatsPerBar)} → ${_formatBars(segment.loopEndBars, segment.beatsPerBar)}',
              style: TextStyle(color: Colors.green, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        // Duration
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Duration: ${segment.durationBars} bars',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoopRegionOverlay(MiddlewareProvider provider, MusicSegment segment) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final startPercent = segment.loopStartBars / segment.durationBars;
        final endPercent = segment.loopEndBars / segment.durationBars;
        final startX = startPercent * constraints.maxWidth;
        final endX = endPercent * constraints.maxWidth;
        final width = endX - startX;

        return Stack(
          children: [
            // Loop region fill
            Positioned(
              left: startX,
              width: width,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  border: Border.symmetric(
                    vertical: BorderSide(color: Colors.green, width: 2),
                  ),
                ),
              ),
            ),
            // Start handle
            Positioned(
              left: startX - 8,
              top: 0,
              bottom: 0,
              width: 16,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _isDraggingStart = true,
                onHorizontalDragUpdate: (details) {
                  if (_isDraggingStart) {
                    _updateLoopStart(provider, segment, details.delta.dx / constraints.maxWidth);
                  }
                },
                onHorizontalDragEnd: (_) => _isDraggingStart = false,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    alignment: Alignment.center,
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // End handle
            Positioned(
              left: endX - 8,
              top: 0,
              bottom: 0,
              width: 16,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _isDraggingEnd = true,
                onHorizontalDragUpdate: (details) {
                  if (_isDraggingEnd) {
                    _updateLoopEnd(provider, segment, details.delta.dx / constraints.maxWidth);
                  }
                },
                onHorizontalDragEnd: (_) => _isDraggingEnd = false,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    alignment: Alignment.center,
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayhead(MusicSegment segment) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final playheadX = (_playheadPosition / segment.durationBars) * constraints.maxWidth;

        return Positioned(
          left: playheadX - 6,
          top: 0,
          bottom: 0,
          width: 12,
          child: GestureDetector(
            onHorizontalDragStart: (_) => _isDraggingPlayhead = true,
            onHorizontalDragUpdate: (details) {
              if (_isDraggingPlayhead) {
                setState(() {
                  _playheadPosition = ((_playheadPosition / segment.durationBars) +
                          details.delta.dx / constraints.maxWidth) *
                      segment.durationBars;
                  _playheadPosition = _playheadPosition.clamp(0.0, segment.durationBars.toDouble());
                });
              }
            },
            onHorizontalDragEnd: (_) => _isDraggingPlayhead = false,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Column(
                children: [
                  // Playhead triangle
                  CustomPaint(
                    size: const Size(12, 10),
                    painter: _PlayheadTrianglePainter(),
                  ),
                  // Playhead line
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoopQuickControls(MiddlewareProvider provider, MusicSegment segment) {
    final hasLoop = segment.loopEndBars > segment.loopStartBars;

    return Row(
      children: [
        // Set loop from selection
        OutlinedButton.icon(
          icon: Icon(Icons.add_box, size: 14),
          label: const Text('Set Loop'),
          onPressed: () => _setLoopFromPosition(provider, segment),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.green,
            side: BorderSide(color: Colors.green.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            textStyle: const TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        // Clear loop
        OutlinedButton.icon(
          icon: Icon(Icons.clear, size: 14),
          label: const Text('Clear'),
          onPressed: hasLoop ? () => _clearLoop(provider, segment) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: FluxForgeTheme.textMuted,
            side: BorderSide(color: FluxForgeTheme.borderSubtle),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            textStyle: const TextStyle(fontSize: 11),
          ),
        ),
        const Spacer(),
        // Jump to loop start
        if (hasLoop) ...[
          IconButton(
            icon: Icon(Icons.first_page, size: 18, color: Colors.green),
            onPressed: () => setState(() => _playheadPosition = segment.loopStartBars),
            tooltip: 'Jump to Loop Start',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Jump to loop end
          IconButton(
            icon: Icon(Icons.last_page, size: 18, color: Colors.green),
            onPressed: () => setState(() => _playheadPosition = segment.loopEndBars),
            tooltip: 'Jump to Loop End',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // LOOP SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildLoopSettings(MiddlewareProvider provider, MusicSegment segment) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Loop Count
            _buildSettingLabel('Loop Count'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _targetLoopCount == 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '∞ Infinite',
                            style: TextStyle(color: Colors.green, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove, size: 16),
                                onPressed: _targetLoopCount > 1
                                    ? () => setState(() => _targetLoopCount--)
                                    : null,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                              Text(
                                '$_targetLoopCount',
                                style: TextStyle(
                                  color: FluxForgeTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.add, size: 16),
                                onPressed: () => setState(() => _targetLoopCount++),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Infinite toggle
                Tooltip(
                  message: 'Infinite Loop',
                  child: GestureDetector(
                    onTap: () => setState(() => _targetLoopCount = _targetLoopCount == 0 ? 4 : 0),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _targetLoopCount == 0
                            ? Colors.green.withValues(alpha: 0.3)
                            : FluxForgeTheme.bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _targetLoopCount == 0 ? Colors.green : FluxForgeTheme.borderSubtle,
                        ),
                      ),
                      child: Icon(
                        Icons.all_inclusive,
                        size: 18,
                        color: _targetLoopCount == 0 ? Colors.green : FluxForgeTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Crossfade
            _buildSettingLabel('Crossfade'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _crossfadeMs,
                    min: 0,
                    max: 500,
                    divisions: 50,
                    onChanged: (v) => setState(() => _crossfadeMs = v),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${_crossfadeMs.round()}ms',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Crossfade shape
            _buildSettingLabel('Crossfade Shape'),
            const SizedBox(height: 4),
            _buildCrossfadeShapeSelector(),
            const SizedBox(height: 16),
            // Crossfade preview
            _buildCrossfadePreview(),
            const SizedBox(height: 16),
            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Apply Settings'),
                onPressed: () => _applySettings(provider, segment),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
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

  Widget _buildCrossfadeShapeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: _CrossfadeShape.values.map((shape) {
          final isSelected = _crossfadeShape == shape;
          return Expanded(
            child: Tooltip(
              message: shape.label,
              child: GestureDetector(
                onTap: () => setState(() => _crossfadeShape = shape),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green.withValues(alpha: 0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: CustomPaint(
                    size: const Size(24, 16),
                    painter: _CrossfadeShapePainter(shape: shape, isSelected: isSelected),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCrossfadePreview() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _CrossfadePreviewPainter(
          crossfadeMs: _crossfadeMs,
          shape: _crossfadeShape,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 48, color: FluxForgeTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            'No segment selected',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  String _formatBars(double bars, int beatsPerBar) {
    final wholeBars = bars.floor();
    final beat = ((bars - wholeBars) * beatsPerBar).floor() + 1;
    return '${wholeBars + 1}.$beat';
  }

  void _togglePlayback() {
    setState(() => _isPlaying = !_isPlaying);

    if (_isPlaying) {
      _startPlaybackTimer();
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _startPlaybackTimer() {
    final segment = _getSegment(context.read<MiddlewareProvider>());
    if (segment == null) return;

    final tickMs = (60000 / segment.tempo / 4).round(); // 16th notes
    _playbackTimer = Timer.periodic(Duration(milliseconds: tickMs), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      setState(() {
        _playheadPosition += 0.25 / segment.beatsPerBar; // Move by 16th note

        // Check for loop
        if (segment.loopEndBars > segment.loopStartBars) {
          if (_playheadPosition >= segment.loopEndBars) {
            _playheadPosition = segment.loopStartBars;
            _currentLoopCount++;

            // Check loop count limit
            if (_targetLoopCount > 0 && _currentLoopCount >= _targetLoopCount) {
              _isPlaying = false;
              _currentLoopCount = 0;
              timer.cancel();
            }
          }
        } else if (_playheadPosition >= segment.durationBars) {
          _playheadPosition = 0;
        }
      });
    });
  }

  void _rewind() {
    final segment = _getSegment(context.read<MiddlewareProvider>());
    if (segment != null && segment.loopEndBars > segment.loopStartBars) {
      setState(() => _playheadPosition = segment.loopStartBars);
    } else {
      setState(() => _playheadPosition = 0);
    }
    _currentLoopCount = 0;
  }

  void _stop() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _playheadPosition = 0;
      _currentLoopCount = 0;
    });
  }

  void _handleWaveformTap(MiddlewareProvider provider, MusicSegment segment, TapDownDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(details.globalPosition);
    final percent = localPosition.dx / box.size.width;
    setState(() => _playheadPosition = percent * segment.durationBars);
  }

  void _updateLoopStart(MiddlewareProvider provider, MusicSegment segment, double deltaNormalized) {
    final newStart = (segment.loopStartBars + deltaNormalized * segment.durationBars)
        .clamp(0.0, segment.loopEndBars - 0.5);
    provider.updateMusicSegment(segment.copyWith(loopStartBars: newStart));
  }

  void _updateLoopEnd(MiddlewareProvider provider, MusicSegment segment, double deltaNormalized) {
    final newEnd = (segment.loopEndBars + deltaNormalized * segment.durationBars)
        .clamp(segment.loopStartBars + 0.5, segment.durationBars.toDouble());
    provider.updateMusicSegment(segment.copyWith(loopEndBars: newEnd));
  }

  void _setLoopFromPosition(MiddlewareProvider provider, MusicSegment segment) {
    // Set loop from playhead position for 4 bars
    final start = _playheadPosition;
    final end = (start + 4).clamp(0.0, segment.durationBars.toDouble());
    provider.updateMusicSegment(segment.copyWith(loopStartBars: start, loopEndBars: end));
  }

  void _clearLoop(MiddlewareProvider provider, MusicSegment segment) {
    provider.updateMusicSegment(segment.copyWith(loopStartBars: 0.0, loopEndBars: 0.0));
  }

  void _applySettings(MiddlewareProvider provider, MusicSegment segment) {
    // Settings would be applied to engine here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loop settings applied'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

enum _CrossfadeShape {
  linear('Linear'),
  equalPower('Equal Power'),
  sCurve('S-Curve'),
  logarithmic('Logarithmic');

  const _CrossfadeShape(this.label);
  final String label;

  double apply(double t) {
    switch (this) {
      case _CrossfadeShape.linear:
        return t;
      case _CrossfadeShape.equalPower:
        return t == 0 ? 0 : t == 1 ? 1 : math.sin(t * math.pi / 2);
      case _CrossfadeShape.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      case _CrossfadeShape.logarithmic:
        return 1 - (1 - t) * (1 - t) * (1 - t);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _LoopWaveformPainter extends CustomPainter {
  final MusicSegment segment;
  final double playheadPosition;
  final bool isPlaying;

  _LoopWaveformPainter({
    required this.segment,
    required this.playheadPosition,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = FluxForgeTheme.bgSurface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    // Simulated waveform
    final wavePaint = Paint()
      ..color = Colors.pink.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    final centerY = size.height / 2;
    for (int i = 0; i < size.width; i += 2) {
      final amplitude = 0.3 + 0.7 * ((i * 17) % 31) / 31;
      final height = amplitude * size.height * 0.4;
      canvas.drawLine(
        Offset(i.toDouble(), centerY - height),
        Offset(i.toDouble(), centerY + height),
        wavePaint,
      );
    }

    // Bar grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    final barWidth = size.width / segment.durationBars;
    for (int i = 0; i <= segment.durationBars; i++) {
      final x = i * barWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_LoopWaveformPainter oldDelegate) {
    return playheadPosition != oldDelegate.playheadPosition ||
        isPlaying != oldDelegate.isPlaying;
  }
}

class _PlayheadTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrossfadeShapePainter extends CustomPainter {
  final _CrossfadeShape shape;
  final bool isSelected;

  _CrossfadeShapePainter({required this.shape, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    for (int i = 0; i <= 20; i++) {
      final t = i / 20.0;
      final x = t * size.width;
      final y = size.height - shape.apply(t) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = isSelected ? Colors.green : FluxForgeTheme.textMuted
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CrossfadeShapePainter oldDelegate) {
    return shape != oldDelegate.shape || isSelected != oldDelegate.isSelected;
  }
}

class _CrossfadePreviewPainter extends CustomPainter {
  final double crossfadeMs;
  final _CrossfadeShape shape;

  _CrossfadePreviewPainter({required this.crossfadeMs, required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final crossfadeWidth = (crossfadeMs / 500) * size.width * 0.4;
    final crossfadeStart = size.width / 2 - crossfadeWidth / 2;

    // Fade out (green, left)
    final fadeOutPath = Path();
    for (int i = 0; i <= 30; i++) {
      final t = i / 30.0;
      final x = crossfadeStart + t * crossfadeWidth;
      final y = size.height * 0.2 + (1 - shape.apply(1 - t)) * size.height * 0.6;

      if (i == 0) {
        fadeOutPath.moveTo(x, y);
      } else {
        fadeOutPath.lineTo(x, y);
      }
    }

    canvas.drawPath(
      fadeOutPath,
      Paint()
        ..color = Colors.green
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Fade in (orange, right)
    final fadeInPath = Path();
    for (int i = 0; i <= 30; i++) {
      final t = i / 30.0;
      final x = crossfadeStart + t * crossfadeWidth;
      final y = size.height * 0.8 - shape.apply(t) * size.height * 0.6;

      if (i == 0) {
        fadeInPath.moveTo(x, y);
      } else {
        fadeInPath.lineTo(x, y);
      }
    }

    canvas.drawPath(
      fadeInPath,
      Paint()
        ..color = Colors.orange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Crossfade zone indicator
    final zonePaint = Paint()
      ..color = Colors.pink.withValues(alpha: 0.2);
    canvas.drawRect(
      Rect.fromLTWH(crossfadeStart, 0, crossfadeWidth, size.height),
      zonePaint,
    );

    // Labels
    final outLabel = TextSpan(
      text: 'OUT',
      style: TextStyle(color: Colors.green, fontSize: 8),
    );
    final outPainter = TextPainter(text: outLabel, textDirection: TextDirection.ltr)..layout();
    outPainter.paint(canvas, Offset(crossfadeStart - 25, size.height / 2 - 5));

    final inLabel = TextSpan(
      text: 'IN',
      style: TextStyle(color: Colors.orange, fontSize: 8),
    );
    final inPainter = TextPainter(text: inLabel, textDirection: TextDirection.ltr)..layout();
    inPainter.paint(canvas, Offset(crossfadeStart + crossfadeWidth + 5, size.height / 2 - 5));
  }

  @override
  bool shouldRepaint(_CrossfadePreviewPainter oldDelegate) {
    return crossfadeMs != oldDelegate.crossfadeMs || shape != oldDelegate.shape;
  }
}

/// FluxForge Studio Beat Grid Editor
///
/// P4.9: Beat Grid Editor
/// - Visual beat/bar grid editing
/// - Tempo and time signature controls
/// - Marker placement and editing
/// - Loop region selection
/// - Snap-to-grid settings
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BEAT GRID EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class BeatGridEditor extends StatefulWidget {
  final int? segmentId;
  final double height;
  final VoidCallback? onSegmentChanged;

  const BeatGridEditor({
    super.key,
    this.segmentId,
    this.height = 300,
    this.onSegmentChanged,
  });

  @override
  State<BeatGridEditor> createState() => _BeatGridEditorState();
}

class _BeatGridEditorState extends State<BeatGridEditor>
    with SingleTickerProviderStateMixin {
  // View state
  double _zoom = 1.0;
  double _scrollOffset = 0.0;
  bool _isPlaying = false;
  double _playheadPosition = 0.0; // In bars

  // Edit state
  _EditMode _editMode = _EditMode.select;
  int? _selectedMarkerIndex;
  bool _isDraggingMarker = false;
  bool _isDraggingLoopStart = false;
  bool _isDraggingLoopEnd = false;
  bool _isDraggingPlayhead = false;

  // Snap settings
  _SnapMode _snapMode = _SnapMode.beat;
  bool _snapEnabled = true;

  // Animation
  late AnimationController _playbackController;

  // Constants
  static const double _barWidth = 120.0;
  static const double _headerHeight = 40.0;
  static const double _rulerHeight = 24.0;
  static const double _markerTrackHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(() {
        if (_isPlaying) {
          setState(() {
            _playheadPosition += 0.016 * (_getTempo() / 60.0);
            final segment = _getSegment();
            if (segment != null && _playheadPosition > segment.durationBars) {
              if (segment.loopEndBars > segment.loopStartBars) {
                _playheadPosition = segment.loopStartBars;
              } else {
                _playheadPosition = 0;
              }
            }
          });
        }
      });
  }

  @override
  void dispose() {
    _playbackController.dispose();
    super.dispose();
  }

  MusicSegment? _getSegment() {
    if (widget.segmentId == null) return null;
    final provider = context.read<MiddlewareProvider>();
    return provider.musicSegments
        .where((s) => s.id == widget.segmentId)
        .firstOrNull;
  }

  double _getTempo() {
    return _getSegment()?.tempo ?? 120.0;
  }

  int _getBeatsPerBar() {
    return _getSegment()?.beatsPerBar ?? 4;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final segment = widget.segmentId != null
            ? provider.musicSegments
                .where((s) => s.id == widget.segmentId)
                .firstOrNull
            : null;

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
              // Header with controls
              _buildHeader(provider, segment),
              // Grid area
              Expanded(
                child: segment != null
                    ? _buildGridArea(provider, segment)
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
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Icon(Icons.grid_on, size: 16, color: Colors.pink),
          const SizedBox(width: 8),
          Text(
            'Beat Grid',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (segment != null) ...[
            const SizedBox(width: 8),
            Text(
              segment.name,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(width: 16),
          // Transport controls
          _buildTransportControls(segment),
          const SizedBox(width: 16),
          // Tempo/Time signature
          if (segment != null) _buildTempoControls(provider, segment),
          const Spacer(),
          // Edit mode selector
          _buildEditModeSelector(),
          const SizedBox(width: 12),
          // Snap controls
          _buildSnapControls(),
          const SizedBox(width: 12),
          // Zoom
          _buildZoomControls(),
        ],
      ),
    );
  }

  Widget _buildTransportControls(MusicSegment? segment) {
    return Row(
      children: [
        // Rewind
        IconButton(
          icon: Icon(Icons.skip_previous, size: 18, color: FluxForgeTheme.textPrimary),
          onPressed: segment != null
              ? () => setState(() => _playheadPosition = 0)
              : null,
          tooltip: 'Rewind',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        // Play/Pause
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            size: 20,
            color: _isPlaying ? Colors.pink : FluxForgeTheme.textPrimary,
          ),
          onPressed: segment != null ? _togglePlayback : null,
          tooltip: _isPlaying ? 'Pause' : 'Play',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        // Stop
        IconButton(
          icon: Icon(Icons.stop, size: 18, color: FluxForgeTheme.textPrimary),
          onPressed: segment != null
              ? () {
                  setState(() {
                    _isPlaying = false;
                    _playheadPosition = 0;
                  });
                  _playbackController.stop();
                }
              : null,
          tooltip: 'Stop',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        const SizedBox(width: 8),
        // Position display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _formatPosition(_playheadPosition),
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTempoControls(MiddlewareProvider provider, MusicSegment segment) {
    return Row(
      children: [
        // Tempo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.pink.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.pink.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, size: 12, color: Colors.pink),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _editTempo(provider, segment),
                child: Text(
                  '${segment.tempo.toStringAsFixed(1)} BPM',
                  style: TextStyle(
                    color: Colors.pink,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Time signature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.accent.withValues(alpha: 0.4)),
          ),
          child: GestureDetector(
            onTap: () => _editTimeSignature(provider, segment),
            child: Text(
              '${segment.beatsPerBar}/4',
              style: TextStyle(
                color: FluxForgeTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Duration
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${segment.durationBars} bars',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: _EditMode.values.map((mode) {
          final isSelected = _editMode == mode;
          return Tooltip(
            message: mode.tooltip,
            child: InkWell(
              onTap: () => setState(() => _editMode = mode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? FluxForgeTheme.accent.withValues(alpha: 0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  mode.icon,
                  size: 16,
                  color: isSelected
                      ? FluxForgeTheme.accent
                      : FluxForgeTheme.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSnapControls() {
    return Row(
      children: [
        // Snap toggle
        Tooltip(
          message: 'Snap to Grid',
          child: InkWell(
            onTap: () => setState(() => _snapEnabled = !_snapEnabled),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _snapEnabled
                    ? FluxForgeTheme.accent.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.grid_3x3,
                size: 16,
                color: _snapEnabled
                    ? FluxForgeTheme.accent
                    : FluxForgeTheme.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Snap mode
        PopupMenuButton<_SnapMode>(
          initialValue: _snapMode,
          onSelected: (mode) => setState(() => _snapMode = mode),
          tooltip: 'Snap Resolution',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Text(
                  _snapMode.label,
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textMuted),
              ],
            ),
          ),
          itemBuilder: (context) => _SnapMode.values.map((mode) {
            return PopupMenuItem(
              value: mode,
              child: Text(mode.label),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.zoom_out, size: 16, color: FluxForgeTheme.textMuted),
          onPressed: () => setState(() => _zoom = (_zoom * 0.8).clamp(0.25, 4.0)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        Container(
          width: 40,
          alignment: Alignment.center,
          child: Text(
            '${(_zoom * 100).round()}%',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.zoom_in, size: 16, color: FluxForgeTheme.textMuted),
          onPressed: () => setState(() => _zoom = (_zoom * 1.25).clamp(0.25, 4.0)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // GRID AREA
  // ═══════════════════════════════════════════════════════════════════════════════

  Widget _buildGridArea(MiddlewareProvider provider, MusicSegment segment) {
    final totalWidth = segment.durationBars * _barWidth * _zoom;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _scrollOffset = (_scrollOffset - details.delta.dx).clamp(0.0, totalWidth - 200);
        });
      },
      child: ClipRect(
        child: Stack(
          children: [
            // Background grid
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(
                  segment: segment,
                  zoom: _zoom,
                  scrollOffset: _scrollOffset,
                  barWidth: _barWidth,
                ),
              ),
            ),
            // Ruler
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _rulerHeight,
              child: _buildRuler(segment),
            ),
            // Marker track
            Positioned(
              left: 0,
              right: 0,
              top: _rulerHeight,
              height: _markerTrackHeight,
              child: _buildMarkerTrack(provider, segment),
            ),
            // Loop region
            _buildLoopRegion(provider, segment),
            // Entry/Exit cues
            _buildCueMarkers(segment),
            // Markers
            ...segment.markers.asMap().entries.map((entry) =>
                _buildMarker(provider, segment, entry.key, entry.value)),
            // Playhead
            _buildPlayhead(segment),
            // Click handler for grid
            Positioned.fill(
              child: GestureDetector(
                onTapDown: (details) => _handleGridTap(provider, segment, details),
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuler(MusicSegment segment) {
    return CustomPaint(
      painter: _RulerPainter(
        segment: segment,
        zoom: _zoom,
        scrollOffset: _scrollOffset,
        barWidth: _barWidth,
      ),
    );
  }

  Widget _buildMarkerTrack(MiddlewareProvider provider, MusicSegment segment) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Add marker button
          if (_editMode == _EditMode.marker)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                icon: Icon(Icons.add_location, size: 16, color: Colors.orange),
                onPressed: () => _addMarker(provider, segment),
                tooltip: 'Add Marker at Playhead',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoopRegion(MiddlewareProvider provider, MusicSegment segment) {
    if (segment.loopStartBars >= segment.loopEndBars) return const SizedBox.shrink();

    final startX = (segment.loopStartBars * _barWidth * _zoom) - _scrollOffset;
    final endX = (segment.loopEndBars * _barWidth * _zoom) - _scrollOffset;
    final width = endX - startX;

    return Positioned(
      left: startX,
      top: _rulerHeight + _markerTrackHeight,
      width: width,
      bottom: 0,
      child: Stack(
        children: [
          // Loop region fill
          Container(
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              border: Border(
                left: BorderSide(color: Colors.green, width: 2),
                right: BorderSide(color: Colors.green, width: 2),
              ),
            ),
          ),
          // Loop start handle
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: GestureDetector(
              onHorizontalDragStart: (_) => _isDraggingLoopStart = true,
              onHorizontalDragUpdate: (details) {
                if (_isDraggingLoopStart) {
                  final newPos = _snapPosition(
                    segment,
                    segment.loopStartBars + details.delta.dx / (_barWidth * _zoom),
                  );
                  if (newPos < segment.loopEndBars && newPos >= 0) {
                    provider.updateMusicSegment(segment.copyWith(loopStartBars: newPos));
                  }
                }
              },
              onHorizontalDragEnd: (_) => _isDraggingLoopStart = false,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Loop end handle
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: GestureDetector(
              onHorizontalDragStart: (_) => _isDraggingLoopEnd = true,
              onHorizontalDragUpdate: (details) {
                if (_isDraggingLoopEnd) {
                  final newPos = _snapPosition(
                    segment,
                    segment.loopEndBars + details.delta.dx / (_barWidth * _zoom),
                  );
                  if (newPos > segment.loopStartBars && newPos <= segment.durationBars) {
                    provider.updateMusicSegment(segment.copyWith(loopEndBars: newPos));
                  }
                }
              },
              onHorizontalDragEnd: (_) => _isDraggingLoopEnd = false,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCueMarkers(MusicSegment segment) {
    final entryCueX = (segment.entryCueBars * _barWidth * _zoom) - _scrollOffset;
    final exitCueX = (segment.exitCueBars * _barWidth * _zoom) - _scrollOffset;

    return Stack(
      children: [
        // Entry cue
        if (segment.entryCueBars > 0)
          Positioned(
            left: entryCueX - 1,
            top: _rulerHeight,
            width: 2,
            bottom: 0,
            child: Container(
              color: Colors.cyan,
              child: Tooltip(
                message: 'Entry Cue (${segment.entryCueBars.toStringAsFixed(2)} bars)',
                child: const SizedBox.expand(),
              ),
            ),
          ),
        // Exit cue
        if (segment.exitCueBars > 0 && segment.exitCueBars < segment.durationBars)
          Positioned(
            left: exitCueX - 1,
            top: _rulerHeight,
            width: 2,
            bottom: 0,
            child: Container(
              color: Colors.amber,
              child: Tooltip(
                message: 'Exit Cue (${segment.exitCueBars.toStringAsFixed(2)} bars)',
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMarker(MiddlewareProvider provider, MusicSegment segment, int index, MusicMarker marker) {
    final x = (marker.positionBars * _barWidth * _zoom) - _scrollOffset;
    final isSelected = _selectedMarkerIndex == index;

    return Positioned(
      left: x - 8,
      top: _rulerHeight,
      width: 16,
      height: _markerTrackHeight,
      child: GestureDetector(
        onTap: () => setState(() => _selectedMarkerIndex = index),
        onDoubleTap: () => _editMarker(provider, segment, index, marker),
        onHorizontalDragStart: (_) {
          _isDraggingMarker = true;
          _selectedMarkerIndex = index;
        },
        onHorizontalDragUpdate: (details) {
          if (_isDraggingMarker && _editMode == _EditMode.marker) {
            final newPos = _snapPosition(
              segment,
              marker.positionBars + details.delta.dx / (_barWidth * _zoom),
            );
            if (newPos >= 0 && newPos <= segment.durationBars) {
              _updateMarkerPosition(provider, segment, index, newPos);
            }
          }
        },
        onHorizontalDragEnd: (_) => _isDraggingMarker = false,
        child: Tooltip(
          message: '${marker.name}\n${marker.positionBars.toStringAsFixed(2)} bars',
          child: Column(
            children: [
              // Marker flag
              Container(
                width: 16,
                height: 12,
                decoration: BoxDecoration(
                  color: _getMarkerColor(marker.markerType),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(2),
                  ),
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 1)
                      : null,
                ),
                child: Center(
                  child: Text(
                    marker.name.isNotEmpty ? marker.name[0].toUpperCase() : 'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Marker stem
              Container(
                width: 2,
                height: _markerTrackHeight - 12,
                color: _getMarkerColor(marker.markerType),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateMarkerPosition(MiddlewareProvider provider, MusicSegment segment, int index, double newPosition) {
    final updatedMarkers = List<MusicMarker>.from(segment.markers);
    updatedMarkers[index] = segment.markers[index].copyWith(positionBars: newPosition);
    provider.updateMusicSegment(segment.copyWith(markers: updatedMarkers));
  }

  Widget _buildPlayhead(MusicSegment segment) {
    final x = (_playheadPosition * _barWidth * _zoom) - _scrollOffset;

    return Positioned(
      left: x - 6,
      top: 0,
      width: 12,
      bottom: 0,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _isDraggingPlayhead = true,
        onHorizontalDragUpdate: (details) {
          if (_isDraggingPlayhead) {
            final newPos = _snapPosition(
              segment,
              _playheadPosition + details.delta.dx / (_barWidth * _zoom),
            );
            setState(() {
              _playheadPosition = newPos.clamp(0.0, segment.durationBars.toDouble());
            });
          }
        },
        onHorizontalDragEnd: (_) => _isDraggingPlayhead = false,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // Playhead triangle
              CustomPaint(
                size: const Size(12, 12),
                painter: _PlayheadPainter(),
              ),
              // Playhead line
              Positioned(
                top: 12,
                bottom: 0,
                child: Container(
                  width: 1,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
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
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a music segment to edit its beat grid',
            style: TextStyle(
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  String _formatPosition(double bars) {
    final wholeBars = bars.floor();
    final beat = ((bars - wholeBars) * _getBeatsPerBar()).floor() + 1;
    final tick = (((bars - wholeBars) * _getBeatsPerBar() - beat + 1) * 480).round();
    return '${wholeBars + 1}.$beat.${tick.toString().padLeft(3, '0')}';
  }

  double _snapPosition(MusicSegment segment, double position) {
    if (!_snapEnabled) return position;

    final beatsPerBar = segment.beatsPerBar;
    double snapValue;

    switch (_snapMode) {
      case _SnapMode.bar:
        snapValue = 1.0;
      case _SnapMode.beat:
        snapValue = 1.0 / beatsPerBar;
      case _SnapMode.halfBeat:
        snapValue = 0.5 / beatsPerBar;
      case _SnapMode.quarterBeat:
        snapValue = 0.25 / beatsPerBar;
      case _SnapMode.off:
        return position;
    }

    return (position / snapValue).round() * snapValue;
  }

  Color _getMarkerColor(MarkerType type) {
    switch (type) {
      case MarkerType.generic:
        return Colors.orange;
      case MarkerType.entry:
        return Colors.cyan;
      case MarkerType.exit:
        return Colors.amber;
      case MarkerType.sync:
        return Colors.purple;
    }
  }

  void _togglePlayback() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _playbackController.repeat();
    } else {
      _playbackController.stop();
    }
  }

  void _handleGridTap(MiddlewareProvider provider, MusicSegment segment, TapDownDetails details) {
    final localX = details.localPosition.dx + _scrollOffset;
    final position = localX / (_barWidth * _zoom);

    switch (_editMode) {
      case _EditMode.select:
        setState(() {
          _playheadPosition = _snapPosition(segment, position);
          _selectedMarkerIndex = null;
        });
      case _EditMode.marker:
        _addMarkerAt(provider, segment, position);
      case _EditMode.loop:
        // Toggle loop region
        if (segment.loopStartBars >= segment.loopEndBars) {
          // Create new loop region
          final snapped = _snapPosition(segment, position);
          provider.updateMusicSegment(segment.copyWith(
            loopStartBars: snapped,
            loopEndBars: (snapped + 1).clamp(0.0, segment.durationBars.toDouble()),
          ));
        }
      case _EditMode.cue:
        // Set entry or exit cue
        final snapped = _snapPosition(segment, position);
        if (snapped < segment.durationBars / 2) {
          provider.updateMusicSegment(segment.copyWith(entryCueBars: snapped));
        } else {
          provider.updateMusicSegment(segment.copyWith(exitCueBars: snapped));
        }
    }
  }

  void _addMarker(MiddlewareProvider provider, MusicSegment segment) {
    _addMarkerAt(provider, segment, _playheadPosition);
  }

  void _addMarkerAt(MiddlewareProvider provider, MusicSegment segment, double position) {
    final snapped = _snapPosition(segment, position);
    provider.addMusicMarker(
      segment.id,
      name: 'Marker ${segment.markers.length + 1}',
      positionBars: snapped,
      markerType: MarkerType.generic,
    );
  }

  void _editMarker(MiddlewareProvider provider, MusicSegment segment, int index, MusicMarker marker) {
    final nameController = TextEditingController(text: marker.name);
    MarkerType selectedType = marker.markerType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.surface,
          title: Text('Edit Marker', style: TextStyle(color: FluxForgeTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: FluxForgeTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MarkerType>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Type'),
                dropdownColor: FluxForgeTheme.surface,
                style: TextStyle(color: FluxForgeTheme.textPrimary),
                items: MarkerType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _getMarkerColor(type),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(type.displayName),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedType = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _deleteMarker(provider, segment, index);
                Navigator.pop(context);
              },
              child: Text('Delete', style: TextStyle(color: FluxForgeTheme.errorRed)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                _updateMarker(provider, segment, index, nameController.text, selectedType);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateMarker(MiddlewareProvider provider, MusicSegment segment, int index, String name, MarkerType type) {
    final updatedMarkers = List<MusicMarker>.from(segment.markers);
    updatedMarkers[index] = segment.markers[index].copyWith(name: name, markerType: type);
    provider.updateMusicSegment(segment.copyWith(markers: updatedMarkers));
  }

  void _deleteMarker(MiddlewareProvider provider, MusicSegment segment, int index) {
    final updatedMarkers = List<MusicMarker>.from(segment.markers);
    updatedMarkers.removeAt(index);
    provider.updateMusicSegment(segment.copyWith(markers: updatedMarkers));
    setState(() => _selectedMarkerIndex = null);
  }

  void _editTempo(MiddlewareProvider provider, MusicSegment segment) {
    final controller = TextEditingController(text: segment.tempo.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surface,
        title: Text('Edit Tempo', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'BPM',
            suffixText: 'BPM',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final tempo = double.tryParse(controller.text);
              if (tempo != null && tempo > 0 && tempo <= 300) {
                provider.updateMusicSegment(segment.copyWith(tempo: tempo));
              }
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _editTimeSignature(MiddlewareProvider provider, MusicSegment segment) {
    int beatsPerBar = segment.beatsPerBar;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FluxForgeTheme.surface,
          title: Text('Time Signature', style: TextStyle(color: FluxForgeTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$beatsPerBar / 4',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: beatsPerBar.toDouble(),
                min: 2,
                max: 12,
                divisions: 10,
                label: beatsPerBar.toString(),
                onChanged: (value) {
                  setDialogState(() => beatsPerBar = value.round());
                },
              ),
              Text(
                'Beats per bar',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                provider.updateMusicSegment(segment.copyWith(beatsPerBar: beatsPerBar));
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

enum _EditMode {
  select(Icons.mouse, 'Select'),
  marker(Icons.location_on, 'Add Marker'),
  loop(Icons.loop, 'Set Loop'),
  cue(Icons.flag, 'Set Cue');

  const _EditMode(this.icon, this.tooltip);
  final IconData icon;
  final String tooltip;
}

enum _SnapMode {
  bar('Bar'),
  beat('Beat'),
  halfBeat('1/2'),
  quarterBeat('1/4'),
  off('Off');

  const _SnapMode(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final MusicSegment segment;
  final double zoom;
  final double scrollOffset;
  final double barWidth;

  _GridPainter({
    required this.segment,
    required this.zoom,
    required this.scrollOffset,
    required this.barWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaledBarWidth = barWidth * zoom;
    final beatsPerBar = segment.beatsPerBar;
    final beatWidth = scaledBarWidth / beatsPerBar;

    // Calculate visible range
    final startBar = (scrollOffset / scaledBarWidth).floor();
    final endBar = ((scrollOffset + size.width) / scaledBarWidth).ceil();

    // Draw beat lines
    final beatPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    final barPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    for (int bar = startBar; bar <= endBar && bar <= segment.durationBars; bar++) {
      final barX = bar * scaledBarWidth - scrollOffset;

      // Bar line
      canvas.drawLine(
        Offset(barX, 0),
        Offset(barX, size.height),
        barPaint,
      );

      // Beat lines
      for (int beat = 1; beat < beatsPerBar; beat++) {
        final beatX = barX + beat * beatWidth;
        canvas.drawLine(
          Offset(beatX, 0),
          Offset(beatX, size.height),
          beatPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return segment != oldDelegate.segment ||
        zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset;
  }
}

class _RulerPainter extends CustomPainter {
  final MusicSegment segment;
  final double zoom;
  final double scrollOffset;
  final double barWidth;

  _RulerPainter({
    required this.segment,
    required this.zoom,
    required this.scrollOffset,
    required this.barWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaledBarWidth = barWidth * zoom;
    final beatsPerBar = segment.beatsPerBar;
    final beatWidth = scaledBarWidth / beatsPerBar;

    // Calculate visible range
    final startBar = (scrollOffset / scaledBarWidth).floor();
    final endBar = ((scrollOffset + size.width) / scaledBarWidth).ceil();

    // Background
    final bgPaint = Paint()..color = FluxForgeTheme.bgSurface;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      borderPaint,
    );

    // Draw bar numbers and beat ticks
    final textStyle = TextStyle(
      color: FluxForgeTheme.textMuted,
      fontSize: 10,
    );

    for (int bar = startBar; bar <= endBar && bar <= segment.durationBars; bar++) {
      final barX = bar * scaledBarWidth - scrollOffset;

      // Bar number
      final textSpan = TextSpan(text: '${bar + 1}', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(barX + 4, 2));

      // Beat ticks
      final tickPaint = Paint()
        ..color = FluxForgeTheme.textMuted.withValues(alpha: 0.5)
        ..strokeWidth = 1;

      for (int beat = 0; beat < beatsPerBar; beat++) {
        final beatX = barX + beat * beatWidth;
        final tickHeight = beat == 0 ? 8.0 : 4.0;
        canvas.drawLine(
          Offset(beatX, size.height - tickHeight),
          Offset(beatX, size.height),
          tickPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) {
    return segment != oldDelegate.segment ||
        zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset;
  }
}

class _PlayheadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

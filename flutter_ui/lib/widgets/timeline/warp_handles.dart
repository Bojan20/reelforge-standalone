// Audio Warp/Stretch Handles
//
// Professional time-stretch handles for clips:
// - Edge handles for non-destructive stretch
// - Warp markers within clips
// - Tempo-sync stretching
// - Algorithm selection
// - Visual feedback

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/fluxforge_theme.dart';

/// Time stretch algorithm
enum StretchAlgorithm {
  elastique,    // High quality, preserves transients
  polyphonic,   // Best for complex material
  monophonic,   // Optimized for single voice/instrument
  drums,        // Preserves transients, slice-based
  realtime,     // Lower quality but fast
}

extension StretchAlgorithmExt on StretchAlgorithm {
  String get label {
    switch (this) {
      case StretchAlgorithm.elastique: return 'Elastique';
      case StretchAlgorithm.polyphonic: return 'Polyphonic';
      case StretchAlgorithm.monophonic: return 'Monophonic';
      case StretchAlgorithm.drums: return 'Drums';
      case StretchAlgorithm.realtime: return 'Realtime';
    }
  }

  String get description {
    switch (this) {
      case StretchAlgorithm.elastique: return 'High quality, preserves transients';
      case StretchAlgorithm.polyphonic: return 'Best for complex material';
      case StretchAlgorithm.monophonic: return 'Single voice/instrument';
      case StretchAlgorithm.drums: return 'Slice-based, preserves attacks';
      case StretchAlgorithm.realtime: return 'Fast preview, lower quality';
    }
  }
}

/// Warp marker within a clip
class WarpMarker {
  final String id;
  final double originalTime; // Time in source audio
  final double warpedTime;   // Time after warping
  final bool isLocked;

  WarpMarker({
    required this.id,
    required this.originalTime,
    required this.warpedTime,
    this.isLocked = false,
  });

  double get stretchFactor => warpedTime / originalTime;

  WarpMarker copyWith({
    double? warpedTime,
    bool? isLocked,
  }) {
    return WarpMarker(
      id: id,
      originalTime: originalTime,
      warpedTime: warpedTime ?? this.warpedTime,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

/// Warp state for a clip
class ClipWarpState {
  final String clipId;
  final double originalDuration;
  final double warpedDuration;
  final double stretchRatio;
  final bool isStretched;
  final StretchAlgorithm algorithm;
  final List<WarpMarker> markers;
  final bool preservePitch;

  ClipWarpState({
    required this.clipId,
    required this.originalDuration,
    double? warpedDuration,
    double? stretchRatio,
    this.isStretched = false,
    this.algorithm = StretchAlgorithm.elastique,
    this.markers = const [],
    this.preservePitch = true,
  }) : warpedDuration = warpedDuration ?? originalDuration,
       stretchRatio = stretchRatio ?? 1.0;

  ClipWarpState copyWith({
    double? warpedDuration,
    double? stretchRatio,
    bool? isStretched,
    StretchAlgorithm? algorithm,
    List<WarpMarker>? markers,
    bool? preservePitch,
  }) {
    return ClipWarpState(
      clipId: clipId,
      originalDuration: originalDuration,
      warpedDuration: warpedDuration ?? this.warpedDuration,
      stretchRatio: stretchRatio ?? this.stretchRatio,
      isStretched: isStretched ?? this.isStretched,
      algorithm: algorithm ?? this.algorithm,
      markers: markers ?? this.markers,
      preservePitch: preservePitch ?? this.preservePitch,
    );
  }

  String get stretchPercentage {
    final percent = (stretchRatio * 100).toStringAsFixed(1);
    return '$percent%';
  }
}

/// Warp handles widget for clip edges
class WarpHandles extends StatefulWidget {
  final ClipWarpState warpState;
  final double clipWidth;
  final double clipHeight;
  final double zoom;
  final bool isSelected;
  final void Function(double newDuration)? onStretch;
  final void Function(WarpMarker marker, double newTime)? onWarpMarkerMoved;
  final void Function(double time)? onAddWarpMarker;
  final void Function(StretchAlgorithm algorithm)? onAlgorithmChanged;

  const WarpHandles({
    super.key,
    required this.warpState,
    required this.clipWidth,
    required this.clipHeight,
    required this.zoom,
    this.isSelected = false,
    this.onStretch,
    this.onWarpMarkerMoved,
    this.onAddWarpMarker,
    this.onAlgorithmChanged,
  });

  @override
  State<WarpHandles> createState() => _WarpHandlesState();
}

class _WarpHandlesState extends State<WarpHandles> {
  bool _isDraggingLeft = false;
  bool _isDraggingRight = false;
  bool _isHoveringLeft = false;
  bool _isHoveringRight = false;
  String? _draggingMarkerId;
  double _dragStartX = 0;
  double _originalWidth = 0;

  static const double handleWidth = 8.0;
  static const double handleMargin = 2.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.isSelected) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: widget.clipWidth,
      height: widget.clipHeight,
      child: Stack(
        children: [
          // Warp markers
          for (final marker in widget.warpState.markers)
            _buildWarpMarker(marker),
          // Left stretch handle
          Positioned(
            left: handleMargin,
            top: 0,
            bottom: 0,
            child: _buildStretchHandle(isLeft: true),
          ),
          // Right stretch handle
          Positioned(
            right: handleMargin,
            top: 0,
            bottom: 0,
            child: _buildStretchHandle(isLeft: false),
          ),
          // Stretch info badge
          if (widget.warpState.isStretched)
            Positioned(
              top: 4,
              left: widget.clipWidth / 2 - 30,
              child: _buildStretchBadge(),
            ),
        ],
      ),
    );
  }

  Widget _buildStretchHandle({required bool isLeft}) {
    final isHovered = isLeft ? _isHoveringLeft : _isHoveringRight;
    final isDragging = isLeft ? _isDraggingLeft : _isDraggingRight;

    return MouseRegion(
      onEnter: (_) => setState(() {
        if (isLeft) {
          _isHoveringLeft = true;
        } else {
          _isHoveringRight = true;
        }
      }),
      onExit: (_) => setState(() {
        if (isLeft) {
          _isHoveringLeft = false;
        } else {
          _isHoveringRight = false;
        }
      }),
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onPanStart: (details) => _handleStretchStart(details, isLeft),
        onPanUpdate: (details) => _handleStretchUpdate(details, isLeft),
        onPanEnd: (_) => _handleStretchEnd(isLeft),
        child: Container(
          width: handleWidth,
          decoration: BoxDecoration(
            color: (isHovered || isDragging)
                ? FluxForgeTheme.accentOrange.withValues(alpha: 0.4)
                : FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(4) : Radius.zero,
              right: isLeft ? Radius.zero : const Radius.circular(4),
            ),
            border: Border.all(
              color: FluxForgeTheme.accentOrange,
              width: (isHovered || isDragging) ? 2 : 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2,
                  height: 12,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 2,
                  height: 12,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarpMarker(WarpMarker marker) {
    final x = (marker.warpedTime / widget.warpState.warpedDuration) * widget.clipWidth;
    final isDragging = _draggingMarkerId == marker.id;

    return Positioned(
      left: x - 4,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onPanStart: (details) {
          if (!marker.isLocked) {
            setState(() => _draggingMarkerId = marker.id);
            _dragStartX = details.globalPosition.dx;
          }
        },
        onPanUpdate: (details) {
          if (_draggingMarkerId == marker.id) {
            final deltaX = details.globalPosition.dx - _dragStartX;
            final deltaTime = deltaX / widget.zoom;
            final newTime = (marker.warpedTime + deltaTime).clamp(0.0, widget.warpState.warpedDuration);
            widget.onWarpMarkerMoved?.call(marker, newTime);
            _dragStartX = details.globalPosition.dx;
          }
        },
        onPanEnd: (_) => setState(() => _draggingMarkerId = null),
        child: MouseRegion(
          cursor: marker.isLocked ? SystemMouseCursors.forbidden : SystemMouseCursors.resizeColumn,
          child: Container(
            width: 8,
            decoration: BoxDecoration(
              color: isDragging
                  ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                  : FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
              border: Border.symmetric(
                vertical: BorderSide(
                  color: marker.isLocked ? Colors.white38 : FluxForgeTheme.accentCyan,
                  width: 1,
                ),
              ),
            ),
            child: Center(
              child: Icon(
                marker.isLocked ? Icons.lock : Icons.drag_indicator,
                size: 10,
                color: marker.isLocked ? Colors.white38 : FluxForgeTheme.accentCyan,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStretchBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentOrange.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            widget.warpState.stretchPercentage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }

  void _handleStretchStart(DragStartDetails details, bool isLeft) {
    setState(() {
      if (isLeft) {
        _isDraggingLeft = true;
      } else {
        _isDraggingRight = true;
      }
    });
    _dragStartX = details.globalPosition.dx;
    _originalWidth = widget.clipWidth;
  }

  void _handleStretchUpdate(DragUpdateDetails details, bool isLeft) {
    final deltaX = details.globalPosition.dx - _dragStartX;
    double newWidth;

    if (isLeft) {
      newWidth = _originalWidth - deltaX;
    } else {
      newWidth = _originalWidth + deltaX;
    }

    // Minimum width constraint
    newWidth = math.max(20, newWidth);

    final newDuration = newWidth / widget.zoom;
    widget.onStretch?.call(newDuration);
  }

  void _handleStretchEnd(bool isLeft) {
    setState(() {
      if (isLeft) {
        _isDraggingLeft = false;
      } else {
        _isDraggingRight = false;
      }
    });
  }
}

/// Algorithm selector popup
class StretchAlgorithmSelector extends StatelessWidget {
  final StretchAlgorithm current;
  final ValueChanged<StretchAlgorithm>? onChanged;

  const StretchAlgorithmSelector({
    super.key,
    required this.current,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StretchAlgorithm>(
      initialValue: current,
      tooltip: 'Stretch Algorithm',
      color: FluxForgeTheme.bgMid,
      onSelected: onChanged,
      itemBuilder: (ctx) => StretchAlgorithm.values.map((algo) {
        return PopupMenuItem(
          value: algo,
          child: Row(
            children: [
              Icon(
                _getAlgorithmIcon(algo),
                size: 16,
                color: algo == current ? FluxForgeTheme.accentOrange : Colors.white54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      algo.label,
                      style: TextStyle(
                        color: algo == current ? FluxForgeTheme.accentOrange : Colors.white,
                        fontSize: 12,
                        fontWeight: algo == current ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    Text(
                      algo.description,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (algo == current)
                const Icon(Icons.check, size: 16, color: FluxForgeTheme.accentOrange),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getAlgorithmIcon(current), size: 14, color: FluxForgeTheme.accentOrange),
            const SizedBox(width: 6),
            Text(
              current.label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  IconData _getAlgorithmIcon(StretchAlgorithm algo) {
    switch (algo) {
      case StretchAlgorithm.elastique: return Icons.auto_awesome;
      case StretchAlgorithm.polyphonic: return Icons.piano;
      case StretchAlgorithm.monophonic: return Icons.mic;
      case StretchAlgorithm.drums: return Icons.album;
      case StretchAlgorithm.realtime: return Icons.speed;
    }
  }
}

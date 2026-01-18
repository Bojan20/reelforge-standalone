/// Glass Timeline Components
///
/// Theme-aware wrappers for timeline widgets with Glass styling.
/// All timeline components maintain full functionality in both modes.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../models/comping_models.dart';
import '../../models/timeline_models.dart' hide TimelineMarker;
import '../timeline/automation_lane.dart';
import '../timeline/lane_header.dart';
import '../timeline/marker_track.dart';
import '../timeline/tempo_track.dart';
import '../timeline/time_ruler.dart';
import '../timeline/grid_lines.dart';
import '../timeline/zoom_slider.dart';

// ==============================================================================
// GLASS TIMELINE COMPONENT WRAPPER
// ==============================================================================

/// Applies Glass styling to timeline components with subtle overlay
class GlassTimelineComponentWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;

  const GlassTimelineComponentWrapper({
    super.key,
    required this.child,
    this.blurAmount = 6.0,
    this.borderRadius = 4.0,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blurAmount,
          sigmaY: blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: showBorder
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==============================================================================
// THEME-AWARE AUTOMATION LANE
// ==============================================================================

class ThemeAwareAutomationLane extends StatelessWidget {
  final AutomationLaneData data;
  final double zoom;
  final double scrollOffset;
  final double width;
  final ValueChanged<AutomationLaneData>? onDataChanged;
  final VoidCallback? onRemove;

  const ThemeAwareAutomationLane({
    super.key,
    required this.data,
    required this.zoom,
    required this.scrollOffset,
    required this.width,
    this.onDataChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final lane = AutomationLane(
      data: data,
      zoom: zoom,
      scrollOffset: scrollOffset,
      width: width,
      onDataChanged: onDataChanged,
      onRemove: onRemove,
    );
    if (isGlassMode) {
      return GlassTimelineComponentWrapper(
        borderRadius: 0,
        showBorder: false,
        child: lane,
      );
    }
    return lane;
  }
}

// ==============================================================================
// THEME-AWARE LANE HEADER
// ==============================================================================

class ThemeAwareLaneHeader extends StatelessWidget {
  final RecordingLane lane;
  final bool isActive;
  final bool isCompLane;
  final VoidCallback? onActivate;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVisible;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onRename;

  const ThemeAwareLaneHeader({
    super.key,
    required this.lane,
    this.isActive = false,
    this.isCompLane = false,
    this.onActivate,
    this.onToggleMute,
    this.onToggleVisible,
    this.onDelete,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final header = LaneHeader(
      lane: lane,
      isActive: isActive,
      isCompLane: isCompLane,
      onActivate: onActivate,
      onToggleMute: onToggleMute,
      onToggleVisible: onToggleVisible,
      onDelete: onDelete,
      onRename: onRename,
    );
    if (isGlassMode) return GlassTimelineComponentWrapper(child: header);
    return header;
  }
}

// ==============================================================================
// THEME-AWARE MARKER TRACK
// ==============================================================================

class ThemeAwareMarkerTrack extends StatelessWidget {
  final List<TimelineMarker> markers;
  final double zoom;
  final double scrollOffset;
  final double height;
  final double? cycleStart;
  final double? cycleEnd;
  final ValueChanged<TimelineMarker>? onMarkerTap;
  final ValueChanged<TimelineMarker>? onMarkerDoubleTap;
  final void Function(TimelineMarker marker, double newTime)? onMarkerMoved;
  final void Function(TimelineMarker marker, double newEnd)? onRegionResized;
  final void Function(double time, MarkerType type)? onAddMarker;
  final ValueChanged<TimelineMarker>? onDeleteMarker;

  const ThemeAwareMarkerTrack({
    super.key,
    required this.markers,
    required this.zoom,
    required this.scrollOffset,
    this.height = 48,
    this.cycleStart,
    this.cycleEnd,
    this.onMarkerTap,
    this.onMarkerDoubleTap,
    this.onMarkerMoved,
    this.onRegionResized,
    this.onAddMarker,
    this.onDeleteMarker,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final track = MarkerTrack(
      markers: markers,
      zoom: zoom,
      scrollOffset: scrollOffset,
      height: height,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      onMarkerTap: onMarkerTap,
      onMarkerDoubleTap: onMarkerDoubleTap,
      onMarkerMoved: onMarkerMoved,
      onRegionResized: onRegionResized,
      onAddMarker: onAddMarker,
      onDeleteMarker: onDeleteMarker,
    );
    if (isGlassMode) {
      return GlassTimelineComponentWrapper(
        borderRadius: 0,
        showBorder: false,
        child: track,
      );
    }
    return track;
  }
}

// ==============================================================================
// THEME-AWARE TEMPO TRACK
// ==============================================================================

class ThemeAwareTempoTrack extends StatelessWidget {
  final List<TempoPoint> tempoPoints;
  final double zoom;
  final double scrollOffset;
  final double height;
  final bool isExpanded;
  final ValueChanged<TempoPoint>? onTempoPointAdd;
  final void Function(String id, TempoPoint newPoint)? onTempoPointChange;
  final ValueChanged<String>? onTempoPointDelete;
  final VoidCallback? onToggleExpanded;
  final double playheadPosition;

  const ThemeAwareTempoTrack({
    super.key,
    required this.tempoPoints,
    required this.zoom,
    required this.scrollOffset,
    this.height = 80,
    this.isExpanded = true,
    this.onTempoPointAdd,
    this.onTempoPointChange,
    this.onTempoPointDelete,
    this.onToggleExpanded,
    this.playheadPosition = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final track = TempoTrack(
      tempoPoints: tempoPoints,
      zoom: zoom,
      scrollOffset: scrollOffset,
      height: height,
      isExpanded: isExpanded,
      onTempoPointAdd: onTempoPointAdd,
      onTempoPointChange: onTempoPointChange,
      onTempoPointDelete: onTempoPointDelete,
      onToggleExpanded: onToggleExpanded,
      playheadPosition: playheadPosition,
    );
    if (isGlassMode) {
      return GlassTimelineComponentWrapper(
        borderRadius: 0,
        showBorder: false,
        child: track,
      );
    }
    return track;
  }
}

// ==============================================================================
// THEME-AWARE TIME RULER
// ==============================================================================

class ThemeAwareTimeRuler extends StatelessWidget {
  final double width;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final TimeDisplayMode timeDisplayMode;
  final int sampleRate;
  final LoopRegion? loopRegion;
  final bool loopEnabled;
  final double playheadPosition;
  final ValueChanged<double>? onTimeClick;
  final ValueChanged<double>? onTimeScrub;
  final VoidCallback? onLoopToggle;

  const ThemeAwareTimeRuler({
    super.key,
    required this.width,
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.sampleRate = 48000,
    this.loopRegion,
    this.loopEnabled = false,
    this.playheadPosition = 0,
    this.onTimeClick,
    this.onTimeScrub,
    this.onLoopToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final ruler = TimeRuler(
      width: width,
      zoom: zoom,
      scrollOffset: scrollOffset,
      tempo: tempo,
      timeSignatureNum: timeSignatureNum,
      timeSignatureDenom: timeSignatureDenom,
      timeDisplayMode: timeDisplayMode,
      sampleRate: sampleRate,
      loopRegion: loopRegion,
      loopEnabled: loopEnabled,
      playheadPosition: playheadPosition,
      onTimeClick: onTimeClick,
      onTimeScrub: onTimeScrub,
      onLoopToggle: onLoopToggle,
    );
    if (isGlassMode) {
      return GlassTimelineComponentWrapper(
        borderRadius: 0,
        blurAmount: 4.0,
        child: ruler,
      );
    }
    return ruler;
  }
}

// ==============================================================================
// THEME-AWARE GRID LINES
// ==============================================================================

class ThemeAwareGridLines extends StatelessWidget {
  final double width;
  final double height;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final int timeSignatureDenom;
  final bool showBeatNumbers;

  const ThemeAwareGridLines({
    super.key,
    required this.width,
    required this.height,
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
    this.showBeatNumbers = false,
  });

  @override
  Widget build(BuildContext context) {
    // Grid lines don't need Glass wrapper - they're background elements
    // But we return them directly in both modes for consistency
    return GridLines(
      width: width,
      height: height,
      zoom: zoom,
      scrollOffset: scrollOffset,
      tempo: tempo,
      timeSignatureNum: timeSignatureNum,
      timeSignatureDenom: timeSignatureDenom,
      showBeatNumbers: showBeatNumbers,
    );
  }
}

// ==============================================================================
// THEME-AWARE ZOOM SLIDER
// ==============================================================================

class ThemeAwareZoomSlider extends StatelessWidget {
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final double defaultZoom;
  final ValueChanged<double>? onZoomChange;
  final double width;
  final bool showLabel;

  const ThemeAwareZoomSlider({
    super.key,
    required this.zoom,
    this.minZoom = 10,
    this.maxZoom = 1000,
    this.defaultZoom = 100,
    this.onZoomChange,
    this.width = 120,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final slider = ZoomSlider(
      zoom: zoom,
      minZoom: minZoom,
      maxZoom: maxZoom,
      defaultZoom: defaultZoom,
      onZoomChange: onZoomChange,
      width: width,
      showLabel: showLabel,
    );
    if (isGlassMode) {
      return GlassTimelineComponentWrapper(
        borderRadius: 6,
        blurAmount: 8.0,
        child: slider,
      );
    }
    return slider;
  }
}

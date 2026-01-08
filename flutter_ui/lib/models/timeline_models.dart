// Timeline Models
//
// Core data types for timeline/sequencer:
// - TimelineClip
// - TimelineTrack
// - TimelineMarker
// - Crossfade
// - SnapConfig

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

// Forward declaration for automation types (full impl in automation_lane.dart)
import '../widgets/timeline/automation_lane.dart';

/// Clip on a timeline track
class TimelineClip {
  final String id;
  final String trackId;
  final String name;
  final double startTime; // in seconds
  final double duration;
  final Color? color;
  /// Pre-computed waveform peaks left channel (0-1)
  final Float32List? waveform;
  /// Pre-computed waveform peaks right channel (0-1) - for stereo display
  final Float32List? waveformRight;
  /// Source audio file path (for Rust engine lookup)
  final String? sourceFile;
  /// Source offset within audio file (for left-edge trim)
  final double sourceOffset;
  /// Original source audio duration (immutable)
  final double? sourceDuration;
  /// Fade in duration in seconds
  final double fadeIn;
  /// Fade out duration in seconds
  final double fadeOut;
  /// Clip gain (0-2, 1 = unity)
  final double gain;
  /// Is muted
  final bool muted;
  /// Is selected
  final bool selected;
  /// Clip FX chain (non-destructive per-clip processing)
  final ClipFxChain fxChain;

  const TimelineClip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    this.color,
    this.waveform,
    this.waveformRight,
    this.sourceFile,
    this.sourceOffset = 0,
    this.sourceDuration,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.gain = 1,
    this.muted = false,
    this.selected = false,
    this.fxChain = const ClipFxChain(),
  });

  /// Check if clip has active FX processing
  bool get hasFx => fxChain.hasActiveProcessing;

  double get endTime => startTime + duration;

  TimelineClip copyWith({
    String? id,
    String? trackId,
    String? name,
    double? startTime,
    double? duration,
    Color? color,
    Float32List? waveform,
    Float32List? waveformRight,
    String? sourceFile,
    double? sourceOffset,
    double? sourceDuration,
    double? fadeIn,
    double? fadeOut,
    double? gain,
    bool? muted,
    bool? selected,
    ClipFxChain? fxChain,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      color: color ?? this.color,
      waveform: waveform ?? this.waveform,
      waveformRight: waveformRight ?? this.waveformRight,
      sourceFile: sourceFile ?? this.sourceFile,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      gain: gain ?? this.gain,
      muted: muted ?? this.muted,
      selected: selected ?? this.selected,
      fxChain: fxChain ?? this.fxChain,
    );
  }
}

/// Bus routing options
enum OutputBus { master, music, sfx, ambience, voice }

/// Track type for the timeline
enum TrackType {
  audio,      // Standard audio track
  midi,       // MIDI track
  instrument, // Instrument track (MIDI + synth)
  folder,     // Folder track (contains child tracks)
  bus,        // Bus/Group track
  aux,        // Aux/Return track
  master,     // Master output
}

/// Track on the timeline
class TimelineTrack {
  final String id;
  final String name;
  final Color color;
  final double height;
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool locked;
  final OutputBus outputBus;
  final bool inputMonitor;
  final bool frozen;
  final double volume; // 0-1, 1 = unity
  final double pan; // -1 to 1, 0 = center
  /// Automation lanes for this track
  final List<AutomationLaneData> automationLanes;
  /// Whether automation lanes are expanded/visible
  final bool automationExpanded;
  /// Track type (audio, midi, folder, etc.)
  final TrackType trackType;
  /// Parent folder track ID (null if root level)
  final String? parentFolderId;
  /// Child track IDs (only for folder tracks)
  final List<String> childTrackIds;
  /// Whether folder is expanded
  final bool folderExpanded;
  /// Indent level (depth in folder hierarchy)
  final int indentLevel;

  const TimelineTrack({
    required this.id,
    required this.name,
    this.color = const Color(0xFF5B9BD5), // Logic Pro audio blue
    this.height = 80,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.locked = false,
    this.outputBus = OutputBus.master,
    this.inputMonitor = false,
    this.frozen = false,
    this.volume = 1,
    this.pan = 0,
    this.automationLanes = const [],
    this.automationExpanded = false,
    this.trackType = TrackType.audio,
    this.parentFolderId,
    this.childTrackIds = const [],
    this.folderExpanded = true,
    this.indentLevel = 0,
  });

  /// Whether this is a folder track
  bool get isFolder => trackType == TrackType.folder;

  /// Total height including automation lanes if expanded
  double get totalHeight {
    if (!automationExpanded || automationLanes.isEmpty) return height;
    final automationHeight = automationLanes
        .where((l) => l.visible)
        .fold<double>(0, (sum, lane) => sum + lane.height);
    return height + automationHeight;
  }

  /// Get visible automation lanes
  List<AutomationLaneData> get visibleAutomationLanes =>
      automationLanes.where((l) => l.visible).toList();

  TimelineTrack copyWith({
    String? id,
    String? name,
    Color? color,
    double? height,
    bool? muted,
    bool? soloed,
    bool? armed,
    bool? locked,
    OutputBus? outputBus,
    bool? inputMonitor,
    bool? frozen,
    double? volume,
    double? pan,
    List<AutomationLaneData>? automationLanes,
    bool? automationExpanded,
    TrackType? trackType,
    String? parentFolderId,
    List<String>? childTrackIds,
    bool? folderExpanded,
    int? indentLevel,
  }) {
    return TimelineTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      height: height ?? this.height,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      armed: armed ?? this.armed,
      locked: locked ?? this.locked,
      outputBus: outputBus ?? this.outputBus,
      inputMonitor: inputMonitor ?? this.inputMonitor,
      frozen: frozen ?? this.frozen,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      automationLanes: automationLanes ?? this.automationLanes,
      automationExpanded: automationExpanded ?? this.automationExpanded,
      trackType: trackType ?? this.trackType,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      childTrackIds: childTrackIds ?? this.childTrackIds,
      folderExpanded: folderExpanded ?? this.folderExpanded,
      indentLevel: indentLevel ?? this.indentLevel,
    );
  }
}

/// Marker on the timeline
class TimelineMarker {
  final String id;
  final double time;
  final String name;
  final Color color;

  const TimelineMarker({
    required this.id,
    required this.time,
    required this.name,
    this.color = const Color(0xFFFF9040),
  });
}

/// Crossfade curve type
enum CrossfadeCurve { linear, equalPower, sCurve, logarithmic, exponential }

// ============ Clip FX Types ============

/// Maximum number of FX slots per clip
const int kMaxClipFxSlots = 8;

/// FX processor type for clip-based processing
enum ClipFxType {
  gain,
  compressor,
  limiter,
  gate,
  saturation,
  pitchShift,
  timeStretch,
  proEq,
  ultraEq,
  pultec,
  api550,
  neve1073,
  morphEq,
  roomCorrection,
  external,
}

/// Display name for FX type
String clipFxTypeName(ClipFxType type) {
  switch (type) {
    case ClipFxType.gain:
      return 'Gain';
    case ClipFxType.compressor:
      return 'Compressor';
    case ClipFxType.limiter:
      return 'Limiter';
    case ClipFxType.gate:
      return 'Gate';
    case ClipFxType.saturation:
      return 'Saturation';
    case ClipFxType.pitchShift:
      return 'Pitch Shift';
    case ClipFxType.timeStretch:
      return 'Time Stretch';
    case ClipFxType.proEq:
      return 'Pro EQ';
    case ClipFxType.ultraEq:
      return 'Ultra EQ';
    case ClipFxType.pultec:
      return 'Pultec EQ';
    case ClipFxType.api550:
      return 'API 550';
    case ClipFxType.neve1073:
      return 'Neve 1073';
    case ClipFxType.morphEq:
      return 'Morph EQ';
    case ClipFxType.roomCorrection:
      return 'Room Correction';
    case ClipFxType.external:
      return 'External Plugin';
  }
}

/// Icon for FX type
IconData clipFxTypeIcon(ClipFxType type) {
  switch (type) {
    case ClipFxType.gain:
      return Icons.volume_up;
    case ClipFxType.compressor:
      return Icons.compress;
    case ClipFxType.limiter:
      return Icons.vertical_align_top;
    case ClipFxType.gate:
      return Icons.door_front_door_outlined;
    case ClipFxType.saturation:
      return Icons.whatshot;
    case ClipFxType.pitchShift:
      return Icons.music_note;
    case ClipFxType.timeStretch:
      return Icons.timer;
    case ClipFxType.proEq:
    case ClipFxType.ultraEq:
    case ClipFxType.pultec:
    case ClipFxType.api550:
    case ClipFxType.neve1073:
    case ClipFxType.morphEq:
    case ClipFxType.roomCorrection:
      return Icons.equalizer;
    case ClipFxType.external:
      return Icons.extension;
  }
}

/// Color for FX type category
Color clipFxTypeColor(ClipFxType type) {
  switch (type) {
    case ClipFxType.gain:
      return const Color(0xFF4A9EFF);
    case ClipFxType.compressor:
    case ClipFxType.limiter:
    case ClipFxType.gate:
      return const Color(0xFFFF6B6B);
    case ClipFxType.saturation:
      return const Color(0xFFFF922B);
    case ClipFxType.pitchShift:
    case ClipFxType.timeStretch:
      return const Color(0xFF845EF7);
    case ClipFxType.proEq:
    case ClipFxType.ultraEq:
    case ClipFxType.pultec:
    case ClipFxType.api550:
    case ClipFxType.neve1073:
    case ClipFxType.morphEq:
    case ClipFxType.roomCorrection:
      return const Color(0xFF51CF66);
    case ClipFxType.external:
      return const Color(0xFF888888);
  }
}

/// Parameters for Gain FX
class GainFxParams {
  final double db;
  final double pan;

  const GainFxParams({this.db = 0.0, this.pan = 0.0});

  GainFxParams copyWith({double? db, double? pan}) {
    return GainFxParams(db: db ?? this.db, pan: pan ?? this.pan);
  }
}

/// Parameters for Compressor FX
class CompressorFxParams {
  final double ratio;
  final double thresholdDb;
  final double attackMs;
  final double releaseMs;

  const CompressorFxParams({
    this.ratio = 4.0,
    this.thresholdDb = -20.0,
    this.attackMs = 10.0,
    this.releaseMs = 100.0,
  });

  CompressorFxParams copyWith({
    double? ratio,
    double? thresholdDb,
    double? attackMs,
    double? releaseMs,
  }) {
    return CompressorFxParams(
      ratio: ratio ?? this.ratio,
      thresholdDb: thresholdDb ?? this.thresholdDb,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
    );
  }
}

/// Parameters for Limiter FX
class LimiterFxParams {
  final double ceilingDb;

  const LimiterFxParams({this.ceilingDb = -0.3});

  LimiterFxParams copyWith({double? ceilingDb}) {
    return LimiterFxParams(ceilingDb: ceilingDb ?? this.ceilingDb);
  }
}

/// Parameters for Gate FX
class GateFxParams {
  final double thresholdDb;
  final double attackMs;
  final double releaseMs;

  const GateFxParams({
    this.thresholdDb = -40.0,
    this.attackMs = 1.0,
    this.releaseMs = 50.0,
  });

  GateFxParams copyWith({
    double? thresholdDb,
    double? attackMs,
    double? releaseMs,
  }) {
    return GateFxParams(
      thresholdDb: thresholdDb ?? this.thresholdDb,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
    );
  }
}

/// Parameters for Saturation FX
class SaturationFxParams {
  final double drive;
  final double mix;

  const SaturationFxParams({this.drive = 0.5, this.mix = 1.0});

  SaturationFxParams copyWith({double? drive, double? mix}) {
    return SaturationFxParams(drive: drive ?? this.drive, mix: mix ?? this.mix);
  }
}

/// Single FX slot in a clip's chain
class ClipFxSlot {
  final String id;
  final ClipFxType type;
  final String name;
  final bool bypass;
  final double wetDry;
  final double outputGainDb;
  final int order;

  // Type-specific parameters
  final GainFxParams? gainParams;
  final CompressorFxParams? compressorParams;
  final LimiterFxParams? limiterParams;
  final GateFxParams? gateParams;
  final SaturationFxParams? saturationParams;

  // For external plugins
  final String? pluginId;

  const ClipFxSlot({
    required this.id,
    required this.type,
    this.name = '',
    this.bypass = false,
    this.wetDry = 1.0,
    this.outputGainDb = 0.0,
    this.order = 0,
    this.gainParams,
    this.compressorParams,
    this.limiterParams,
    this.gateParams,
    this.saturationParams,
    this.pluginId,
  });

  /// Create a new slot with default parameters
  factory ClipFxSlot.create(ClipFxType type) {
    final id = 'fx-${DateTime.now().millisecondsSinceEpoch}';
    switch (type) {
      case ClipFxType.gain:
        return ClipFxSlot(
          id: id,
          type: type,
          name: 'Gain',
          gainParams: const GainFxParams(),
        );
      case ClipFxType.compressor:
        return ClipFxSlot(
          id: id,
          type: type,
          name: 'Compressor',
          compressorParams: const CompressorFxParams(),
        );
      case ClipFxType.limiter:
        return ClipFxSlot(
          id: id,
          type: type,
          name: 'Limiter',
          limiterParams: const LimiterFxParams(),
        );
      case ClipFxType.gate:
        return ClipFxSlot(
          id: id,
          type: type,
          name: 'Gate',
          gateParams: const GateFxParams(),
        );
      case ClipFxType.saturation:
        return ClipFxSlot(
          id: id,
          type: type,
          name: 'Saturation',
          saturationParams: const SaturationFxParams(),
        );
      default:
        return ClipFxSlot(
          id: id,
          type: type,
          name: clipFxTypeName(type),
        );
    }
  }

  ClipFxSlot copyWith({
    String? id,
    ClipFxType? type,
    String? name,
    bool? bypass,
    double? wetDry,
    double? outputGainDb,
    int? order,
    GainFxParams? gainParams,
    CompressorFxParams? compressorParams,
    LimiterFxParams? limiterParams,
    GateFxParams? gateParams,
    SaturationFxParams? saturationParams,
    String? pluginId,
  }) {
    return ClipFxSlot(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      bypass: bypass ?? this.bypass,
      wetDry: wetDry ?? this.wetDry,
      outputGainDb: outputGainDb ?? this.outputGainDb,
      order: order ?? this.order,
      gainParams: gainParams ?? this.gainParams,
      compressorParams: compressorParams ?? this.compressorParams,
      limiterParams: limiterParams ?? this.limiterParams,
      gateParams: gateParams ?? this.gateParams,
      saturationParams: saturationParams ?? this.saturationParams,
      pluginId: pluginId ?? this.pluginId,
    );
  }

  /// Get display label for the slot
  String get displayName => name.isNotEmpty ? name : clipFxTypeName(type);
}

/// FX chain for a clip (collection of FX slots)
class ClipFxChain {
  final List<ClipFxSlot> slots;
  final bool bypass;
  final double inputGainDb;
  final double outputGainDb;

  const ClipFxChain({
    this.slots = const [],
    this.bypass = false,
    this.inputGainDb = 0.0,
    this.outputGainDb = 0.0,
  });

  bool get isEmpty => slots.isEmpty;
  bool get isNotEmpty => slots.isNotEmpty;
  int get length => slots.length;

  /// Check if chain has any active (non-bypassed) processing
  bool get hasActiveProcessing {
    if (bypass) return false;
    return slots.any((s) => !s.bypass);
  }

  /// Get active (non-bypassed) slots
  List<ClipFxSlot> get activeSlots => slots.where((s) => !s.bypass).toList();

  ClipFxChain copyWith({
    List<ClipFxSlot>? slots,
    bool? bypass,
    double? inputGainDb,
    double? outputGainDb,
  }) {
    return ClipFxChain(
      slots: slots ?? this.slots,
      bypass: bypass ?? this.bypass,
      inputGainDb: inputGainDb ?? this.inputGainDb,
      outputGainDb: outputGainDb ?? this.outputGainDb,
    );
  }

  /// Add a slot to the chain
  ClipFxChain addSlot(ClipFxSlot slot) {
    if (slots.length >= kMaxClipFxSlots) {
      // Remove oldest if at capacity
      return copyWith(
        slots: [...slots.sublist(1), slot.copyWith(order: slots.length - 1)],
      );
    }
    return copyWith(
      slots: [...slots, slot.copyWith(order: slots.length)],
    );
  }

  /// Remove a slot from the chain
  ClipFxChain removeSlot(String slotId) {
    final newSlots = slots.where((s) => s.id != slotId).toList();
    // Reorder
    for (int i = 0; i < newSlots.length; i++) {
      newSlots[i] = newSlots[i].copyWith(order: i);
    }
    return copyWith(slots: newSlots);
  }

  /// Update a slot in the chain
  ClipFxChain updateSlot(String slotId, ClipFxSlot Function(ClipFxSlot) update) {
    return copyWith(
      slots: slots.map((s) => s.id == slotId ? update(s) : s).toList(),
    );
  }

  /// Move a slot to a new position
  ClipFxChain moveSlot(String slotId, int newIndex) {
    final index = slots.indexWhere((s) => s.id == slotId);
    if (index == -1 || index == newIndex) return this;

    final newSlots = List<ClipFxSlot>.from(slots);
    final slot = newSlots.removeAt(index);
    newSlots.insert(newIndex.clamp(0, newSlots.length), slot);

    // Reorder
    for (int i = 0; i < newSlots.length; i++) {
      newSlots[i] = newSlots[i].copyWith(order: i);
    }
    return copyWith(slots: newSlots);
  }
}

/// Crossfade between two clips
class Crossfade {
  final String id;
  final String trackId;
  final String clipAId;
  final String clipBId;
  final double startTime;
  final double duration;
  final CrossfadeCurve curveType;

  const Crossfade({
    required this.id,
    required this.trackId,
    required this.clipAId,
    required this.clipBId,
    required this.startTime,
    required this.duration,
    this.curveType = CrossfadeCurve.equalPower,
  });

  Crossfade copyWith({
    String? id,
    String? trackId,
    String? clipAId,
    String? clipBId,
    double? startTime,
    double? duration,
    CrossfadeCurve? curveType,
  }) {
    return Crossfade(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      clipAId: clipAId ?? this.clipAId,
      clipBId: clipBId ?? this.clipBId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      curveType: curveType ?? this.curveType,
    );
  }
}

/// Snap configuration
enum SnapType { grid, gridRelative, events, magneticCursor }

class SnapConfig {
  final bool enabled;
  /// Snap value in beats (0.25 = 16th, 0.5 = 8th, 1 = quarter, 4 = bar)
  final double value;
  final SnapType type;

  const SnapConfig({
    this.enabled = true,
    this.value = 1,
    this.type = SnapType.grid,
  });
}

/// Time display mode
enum TimeDisplayMode { bars, timecode, samples }

/// Loop region
class LoopRegion {
  final double start;
  final double end;

  const LoopRegion({required this.start, required this.end});

  double get duration => end - start;

  LoopRegion copyWith({double? start, double? end}) {
    return LoopRegion(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

// ============ Snap Utilities ============

/// Snap time to grid based on tempo and snap value.
double snapToGrid(double time, double snapValue, double tempo) {
  final beatsPerSecond = tempo / 60;
  final gridInterval = snapValue / beatsPerSecond;
  return (time / gridInterval).round() * gridInterval;
}

/// Snap time to nearest event boundary.
double snapToEvents(double time, List<TimelineClip> clips, {double threshold = 0.1}) {
  double nearestTime = time;
  double nearestDistance = threshold;

  for (final clip in clips) {
    // Check clip start
    final startDist = (clip.startTime - time).abs();
    if (startDist < nearestDistance) {
      nearestDistance = startDist;
      nearestTime = clip.startTime;
    }

    // Check clip end
    final endDist = (clip.endTime - time).abs();
    if (endDist < nearestDistance) {
      nearestDistance = endDist;
      nearestTime = clip.endTime;
    }
  }

  return nearestTime;
}

/// Apply snap based on configuration.
double applySnap(
  double time,
  bool snapEnabled,
  double snapValue,
  double tempo,
  List<TimelineClip> clips, {
  double eventSnapThreshold = 0.05,
}) {
  if (!snapEnabled) return time;

  // First, try event snap (higher priority)
  final eventSnapped = snapToEvents(time, clips, threshold: eventSnapThreshold);
  if (eventSnapped != time) {
    return eventSnapped;
  }

  // Fall back to grid snap
  return snapToGrid(time, snapValue, tempo);
}

// ============ Time Formatting ============

/// Format time as bars.beats
String formatBars(double seconds, double tempo, int timeSignatureNum) {
  final beatsPerSecond = tempo / 60;
  final totalBeats = seconds * beatsPerSecond;
  final bar = (totalBeats / timeSignatureNum).floor() + 1;
  final beat = (totalBeats % timeSignatureNum).floor() + 1;
  return '$bar.$beat';
}

/// Format time as timecode (MM:SS:FF)
String formatTimecode(double seconds, {int fps = 30}) {
  final mins = (seconds / 60).floor();
  final secs = (seconds % 60).floor();
  final frames = ((seconds % 1) * fps).floor();
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
}

/// Format time based on mode
String formatTime(
  double seconds,
  TimeDisplayMode mode, {
  double tempo = 120,
  int timeSignatureNum = 4,
  int sampleRate = 48000,
}) {
  switch (mode) {
    case TimeDisplayMode.bars:
      return formatBars(seconds, tempo, timeSignatureNum);
    case TimeDisplayMode.timecode:
      return formatTimecode(seconds);
    case TimeDisplayMode.samples:
      return (seconds * sampleRate).floor().toString();
  }
}

// ============ Demo Waveform Generator ============

/// Generate demo waveform data
Float32List generateDemoWaveform({int samples = 1000}) {
  final waveform = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    final t = i / samples;
    final envelope = math.sin(t * 3.14159); // Fade in/out
    final noise = (_randomDouble() - 0.5) * 0.3;
    final sine = math.sin(t * 3.14159 * 8) * 0.5;
    final burst = (t > 0.2 && t < 0.4) ? _randomDouble() * 0.8 : 0;
    waveform[i] = (sine + noise + burst) * envelope;
  }
  return waveform;
}

double _randomDouble() {
  // Simple deterministic pseudo-random for demo
  return (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
}

// ============ Track Colors ============

const List<Color> kTrackColors = [
  Color(0xFF4A9EFF), // Blue
  Color(0xFFFF6B6B), // Red
  Color(0xFF51CF66), // Green
  Color(0xFFFFD43B), // Yellow
  Color(0xFF845EF7), // Purple
  Color(0xFFFF922B), // Orange
  Color(0xFF22B8CF), // Cyan
  Color(0xFFF06595), // Pink
  Color(0xFF94D82D), // Lime
  Color(0xFFBE4BDB), // Violet
  Color(0xFF339AF0), // Light Blue
  Color(0xFF20C997), // Teal
  Color(0xFFFAB005), // Gold
  Color(0xFF748FFC), // Indigo
  Color(0xFF69DB7C), // Light Green
];

/// Bus display info
class BusInfo {
  final OutputBus bus;
  final String name;
  final Color color;

  const BusInfo(this.bus, this.name, this.color);

  String get shortName => name.substring(0, 3);
}

const List<BusInfo> kBusOptions = [
  BusInfo(OutputBus.master, 'Master', Color(0xFF888888)),
  BusInfo(OutputBus.music, 'Music', Color(0xFF4A9EFF)),
  BusInfo(OutputBus.sfx, 'SFX', Color(0xFFFF6B6B)),
  BusInfo(OutputBus.voice, 'Voice', Color(0xFF51CF66)),
  BusInfo(OutputBus.ambience, 'Ambience', Color(0xFFFFD43B)),
];

BusInfo getBusInfo(OutputBus bus) {
  return kBusOptions.firstWhere((b) => b.bus == bus, orElse: () => kBusOptions[0]);
}

// ============ Audio Pool ============

/// Audio file in the pool (imported but not on timeline)
class PoolAudioFile {
  final String id;
  final String path;
  final String name;
  final double duration;
  final int sampleRate;
  final int channels;
  final String format;
  final Float32List? waveform;
  final DateTime importedAt;
  /// Default bus for clips created from this file
  final OutputBus defaultBus;

  const PoolAudioFile({
    required this.id,
    required this.path,
    required this.name,
    required this.duration,
    this.sampleRate = 48000,
    this.channels = 2,
    this.format = 'wav',
    this.waveform,
    required this.importedAt,
    this.defaultBus = OutputBus.master,
  });

  PoolAudioFile copyWith({
    String? id,
    String? path,
    String? name,
    double? duration,
    int? sampleRate,
    int? channels,
    String? format,
    Float32List? waveform,
    DateTime? importedAt,
    OutputBus? defaultBus,
  }) {
    return PoolAudioFile(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      format: format ?? this.format,
      waveform: waveform ?? this.waveform,
      importedAt: importedAt ?? this.importedAt,
      defaultBus: defaultBus ?? this.defaultBus,
    );
  }

  /// Format duration as MM:SS
  String get durationFormatted {
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Format file size info
  String get formatInfo => '$format • ${sampleRate ~/ 1000}kHz • ${channels}ch';
}

/// Pool folder for organizing audio files
class PoolFolder {
  final String id;
  final String name;
  final String? parentId;
  final List<String> fileIds;
  final bool expanded;

  const PoolFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.fileIds = const [],
    this.expanded = true,
  });

  PoolFolder copyWith({
    String? id,
    String? name,
    String? parentId,
    List<String>? fileIds,
    bool? expanded,
  }) {
    return PoolFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      fileIds: fileIds ?? this.fileIds,
      expanded: expanded ?? this.expanded,
    );
  }
}

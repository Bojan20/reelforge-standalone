/// Advanced Loop Asset Models — Wwise-grade loop control
///
/// Dart mirrors of Rust loop_asset.rs data structures.
/// Used by LoopProvider and Loop Editor UI.

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// How the sound source is referenced.
enum LoopSourceType {
  file,
  sprite,
  stream;

  String toJson() => name;

  static LoopSourceType fromJson(String s) {
    switch (s) {
      case 'file':
        return LoopSourceType.file;
      case 'sprite':
        return LoopSourceType.sprite;
      case 'stream':
        return LoopSourceType.stream;
      default:
        return LoopSourceType.file;
    }
  }
}

/// Cue point type.
enum CueType {
  entry,
  exit,
  custom,
  event,
  sync;

  String toJson() => name;

  static CueType fromJson(String s) {
    switch (s) {
      case 'entry':
        return CueType.entry;
      case 'exit':
        return CueType.exit;
      case 'custom':
        return CueType.custom;
      case 'event':
        return CueType.event;
      case 'sync':
        return CueType.sync;
      default:
        return CueType.custom;
    }
  }
}

/// Loop mode.
enum LoopMode {
  hard,
  crossfade,
  dualVoice;

  String toJson() => name;

  static LoopMode fromJson(String s) {
    switch (s) {
      case 'hard':
        return LoopMode.hard;
      case 'crossfade':
        return LoopMode.crossfade;
      case 'dualVoice':
        return LoopMode.dualVoice;
      default:
        return LoopMode.hard;
    }
  }
}

/// Wrap policy (what happens at loop boundary).
enum WrapPolicy {
  playOnceThenLoop,
  skipIntro,
  includeInLoop,
  introOnly;

  String toJson() => name;

  static WrapPolicy fromJson(String s) {
    switch (s) {
      case 'playOnceThenLoop':
        return WrapPolicy.playOnceThenLoop;
      case 'skipIntro':
        return WrapPolicy.skipIntro;
      case 'includeInLoop':
        return WrapPolicy.includeInLoop;
      case 'introOnly':
        return WrapPolicy.introOnly;
      default:
        return WrapPolicy.playOnceThenLoop;
    }
  }
}

/// Crossfade curve shape.
enum LoopCrossfadeCurve {
  equalPower,
  linear,
  sCurve,
  logarithmic,
  exponential,
  cosineHalf,
  squareRoot,
  sine,
  fastAttack,
  slowAttack;

  int get engineIndex => index;

  String toJson() => name;

  static LoopCrossfadeCurve fromJson(String s) {
    switch (s) {
      case 'equalPower':
        return LoopCrossfadeCurve.equalPower;
      case 'linear':
        return LoopCrossfadeCurve.linear;
      case 'sCurve':
        return LoopCrossfadeCurve.sCurve;
      case 'logarithmic':
        return LoopCrossfadeCurve.logarithmic;
      case 'exponential':
        return LoopCrossfadeCurve.exponential;
      case 'cosineHalf':
        return LoopCrossfadeCurve.cosineHalf;
      case 'squareRoot':
        return LoopCrossfadeCurve.squareRoot;
      case 'sine':
        return LoopCrossfadeCurve.sine;
      case 'fastAttack':
        return LoopCrossfadeCurve.fastAttack;
      case 'slowAttack':
        return LoopCrossfadeCurve.slowAttack;
      default:
        return LoopCrossfadeCurve.equalPower;
    }
  }
}

/// Sync mode for region switch / exit timing.
enum SyncMode {
  nextBar,
  nextBeat,
  nextCue,
  immediate,
  exitCue,
  onWrap,
  entryCue,
  sameTime;

  int get engineIndex => index;

  String toJson() => name;

  static SyncMode fromJson(String s) {
    switch (s) {
      case 'nextBar':
        return SyncMode.nextBar;
      case 'nextBeat':
        return SyncMode.nextBeat;
      case 'nextCue':
        return SyncMode.nextCue;
      case 'immediate':
        return SyncMode.immediate;
      case 'exitCue':
        return SyncMode.exitCue;
      case 'onWrap':
        return SyncMode.onWrap;
      case 'entryCue':
        return SyncMode.entryCue;
      case 'sameTime':
        return SyncMode.sameTime;
      default:
        return SyncMode.immediate;
    }
  }
}

/// Quantize type for loop timing.
enum QuantizeType {
  bar,
  beat,
  subdivision;

  String toJson() => name;
}

/// Loop playback state (from callback).
enum LoopPlaybackState {
  intro,
  looping,
  exiting,
  stopped;

  static LoopPlaybackState fromJson(String s) {
    switch (s) {
      case 'intro':
        return LoopPlaybackState.intro;
      case 'looping':
        return LoopPlaybackState.looping;
      case 'exiting':
        return LoopPlaybackState.exiting;
      case 'stopped':
        return LoopPlaybackState.stopped;
      default:
        return LoopPlaybackState.stopped;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Sound reference (file path or sprite).
class SoundRef {
  final LoopSourceType sourceType;
  final String soundId;
  final String? spriteId;

  const SoundRef({
    required this.sourceType,
    required this.soundId,
    this.spriteId,
  });

  Map<String, dynamic> toJson() => {
        'source_type': sourceType.toJson(),
        'sound_id': soundId,
        if (spriteId != null) 'sprite_id': spriteId,
      };

  factory SoundRef.fromJson(Map<String, dynamic> json) => SoundRef(
        sourceType: LoopSourceType.fromJson(json['source_type'] ?? 'file'),
        soundId: json['sound_id'] ?? '',
        spriteId: json['sprite_id'],
      );
}

/// Timeline info for a loop asset.
class LoopTimelineInfo {
  final int sampleRate;
  final int channels;
  final int lengthSamples;
  final double? bpm;
  final int? beatsPerBar;

  const LoopTimelineInfo({
    required this.sampleRate,
    required this.channels,
    required this.lengthSamples,
    this.bpm,
    this.beatsPerBar,
  });

  double get durationSeconds => lengthSamples / sampleRate;

  Map<String, dynamic> toJson() => {
        'sample_rate': sampleRate,
        'channels': channels,
        'length_samples': lengthSamples,
        if (bpm != null) 'bpm': bpm,
        if (beatsPerBar != null) 'beats_per_bar': beatsPerBar,
      };

  factory LoopTimelineInfo.fromJson(Map<String, dynamic> json) =>
      LoopTimelineInfo(
        sampleRate: json['sample_rate'] ?? 48000,
        channels: json['channels'] ?? 2,
        lengthSamples: json['length_samples'] ?? 0,
        bpm: (json['bpm'] as num?)?.toDouble(),
        beatsPerBar: json['beats_per_bar'],
      );
}

/// Cue point in a loop asset.
class LoopCue {
  final String name;
  final int atSamples;
  final CueType cueType;

  const LoopCue({
    required this.name,
    required this.atSamples,
    required this.cueType,
  });

  double atSeconds(int sampleRate) => atSamples / sampleRate;

  Map<String, dynamic> toJson() => {
        'name': name,
        'at_samples': atSamples,
        'cue_type': cueType.toJson(),
      };

  factory LoopCue.fromJson(Map<String, dynamic> json) => LoopCue(
        name: json['name'] ?? '',
        atSamples: json['at_samples'] ?? 0,
        cueType: CueType.fromJson(json['cue_type'] ?? 'custom'),
      );
}

/// Quantize settings for a loop region.
class LoopQuantize {
  final QuantizeType quantizeType;
  final int divisions;

  const LoopQuantize({
    required this.quantizeType,
    this.divisions = 4,
  });

  Map<String, dynamic> toJson() => {
        'quantize_type': quantizeType.toJson(),
        'divisions': divisions,
      };

  factory LoopQuantize.fromJson(Map<String, dynamic> json) => LoopQuantize(
        quantizeType: QuantizeType.values.firstWhere(
          (e) => e.name == json['quantize_type'],
          orElse: () => QuantizeType.bar,
        ),
        divisions: json['divisions'] ?? 4,
      );
}

/// Zone policy for pre-entry / post-exit.
class ZonePolicy {
  final bool enabled;
  final int startSamples;
  final int endSamples;
  final double fadeMs;

  const ZonePolicy({
    this.enabled = false,
    this.startSamples = 0,
    this.endSamples = 0,
    this.fadeMs = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start_samples': startSamples,
        'end_samples': endSamples,
        'fade_ms': fadeMs,
      };

  factory ZonePolicy.fromJson(Map<String, dynamic> json) => ZonePolicy(
        enabled: json['enabled'] ?? false,
        startSamples: json['start_samples'] ?? 0,
        endSamples: json['end_samples'] ?? 0,
        fadeMs: (json['fade_ms'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Advanced loop region — a named loop range within the asset.
class AdvancedLoopRegion {
  final String name;
  final int inSamples;
  final int outSamples;
  final LoopMode mode;
  final WrapPolicy wrapPolicy;
  final double seamFadeMs;
  final double crossfadeMs;
  final LoopCrossfadeCurve crossfadeCurve;
  final LoopQuantize? quantize;
  final int? maxLoops;
  final double? iterationGainFactor;
  final int randomStartRange;

  const AdvancedLoopRegion({
    required this.name,
    required this.inSamples,
    required this.outSamples,
    this.mode = LoopMode.hard,
    this.wrapPolicy = WrapPolicy.playOnceThenLoop,
    this.seamFadeMs = 5.0,
    this.crossfadeMs = 50.0,
    this.crossfadeCurve = LoopCrossfadeCurve.equalPower,
    this.quantize,
    this.maxLoops,
    this.iterationGainFactor,
    this.randomStartRange = 0,
  });

  double durationSeconds(int sampleRate) =>
      (outSamples - inSamples) / sampleRate;

  AdvancedLoopRegion copyWith({
    String? name,
    int? inSamples,
    int? outSamples,
    LoopMode? mode,
    WrapPolicy? wrapPolicy,
    double? seamFadeMs,
    double? crossfadeMs,
    LoopCrossfadeCurve? crossfadeCurve,
    LoopQuantize? quantize,
    int? maxLoops,
    double? iterationGainFactor,
    int? randomStartRange,
  }) =>
      AdvancedLoopRegion(
        name: name ?? this.name,
        inSamples: inSamples ?? this.inSamples,
        outSamples: outSamples ?? this.outSamples,
        mode: mode ?? this.mode,
        wrapPolicy: wrapPolicy ?? this.wrapPolicy,
        seamFadeMs: seamFadeMs ?? this.seamFadeMs,
        crossfadeMs: crossfadeMs ?? this.crossfadeMs,
        crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
        quantize: quantize ?? this.quantize,
        maxLoops: maxLoops ?? this.maxLoops,
        iterationGainFactor: iterationGainFactor ?? this.iterationGainFactor,
        randomStartRange: randomStartRange ?? this.randomStartRange,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'in_samples': inSamples,
        'out_samples': outSamples,
        'mode': mode.toJson(),
        'wrap_policy': wrapPolicy.toJson(),
        'seam_fade_ms': seamFadeMs,
        'crossfade_ms': crossfadeMs,
        'crossfade_curve': crossfadeCurve.toJson(),
        if (quantize != null) 'quantize': quantize!.toJson(),
        if (maxLoops != null) 'max_loops': maxLoops,
        if (iterationGainFactor != null)
          'iteration_gain_factor': iterationGainFactor,
        'random_start_range': randomStartRange,
      };

  factory AdvancedLoopRegion.fromJson(Map<String, dynamic> json) =>
      AdvancedLoopRegion(
        name: json['name'] ?? 'LoopA',
        inSamples: json['in_samples'] ?? 0,
        outSamples: json['out_samples'] ?? 0,
        mode: LoopMode.fromJson(json['mode'] ?? 'hard'),
        wrapPolicy: WrapPolicy.fromJson(json['wrap_policy'] ?? 'playOnceThenLoop'),
        seamFadeMs: (json['seam_fade_ms'] as num?)?.toDouble() ?? 5.0,
        crossfadeMs: (json['crossfade_ms'] as num?)?.toDouble() ?? 50.0,
        crossfadeCurve: LoopCrossfadeCurve.fromJson(
            json['crossfade_curve'] ?? 'equalPower'),
        quantize: json['quantize'] != null
            ? LoopQuantize.fromJson(json['quantize'])
            : null,
        maxLoops: json['max_loops'],
        iterationGainFactor:
            (json['iteration_gain_factor'] as num?)?.toDouble(),
        randomStartRange: json['random_start_range'] ?? 0,
      );
}

/// Complete loop asset definition.
class LoopAsset {
  final String id;
  final SoundRef soundRef;
  final LoopTimelineInfo timeline;
  final List<LoopCue> cues;
  final List<AdvancedLoopRegion> regions;
  final ZonePolicy preEntry;
  final ZonePolicy postExit;

  const LoopAsset({
    required this.id,
    required this.soundRef,
    required this.timeline,
    this.cues = const [],
    this.regions = const [],
    this.preEntry = const ZonePolicy(),
    this.postExit = const ZonePolicy(),
  });

  LoopCue? get entryCue =>
      cues.where((c) => c.cueType == CueType.entry).firstOrNull;
  LoopCue? get exitCue =>
      cues.where((c) => c.cueType == CueType.exit).firstOrNull;
  List<LoopCue> get customCues =>
      cues.where((c) => c.cueType == CueType.custom).toList();

  AdvancedLoopRegion? regionByName(String name) =>
      regions.where((r) => r.name == name).firstOrNull;

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'sound_ref': soundRef.toJson(),
        'timeline': timeline.toJson(),
        'cues': cues.map((c) => c.toJson()).toList(),
        'regions': regions.map((r) => r.toJson()).toList(),
        'pre_entry': preEntry.toJson(),
        'post_exit': postExit.toJson(),
      };

  factory LoopAsset.fromJson(Map<String, dynamic> json) => LoopAsset(
        id: json['id'] ?? '',
        soundRef: SoundRef.fromJson(json['sound_ref'] ?? {}),
        timeline: LoopTimelineInfo.fromJson(json['timeline'] ?? {}),
        cues: (json['cues'] as List?)
                ?.map((c) => LoopCue.fromJson(c))
                .toList() ??
            [],
        regions: (json['regions'] as List?)
                ?.map((r) => AdvancedLoopRegion.fromJson(r))
                .toList() ??
            [],
        preEntry: ZonePolicy.fromJson(json['pre_entry'] ?? {}),
        postExit: ZonePolicy.fromJson(json['post_exit'] ?? {}),
      );

  factory LoopAsset.fromJsonString(String json) =>
      LoopAsset.fromJson(jsonDecode(json));
}

// ═══════════════════════════════════════════════════════════════════════════════
// CALLBACK MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Callback event from the audio thread.
class LoopCallback {
  final String type;
  final int? instanceId;
  final String? assetId;
  final LoopPlaybackState? state;
  final int? loopCount;
  final int? atSamples;
  final String? fromRegion;
  final String? toRegion;
  final String? cueName;
  final String? message;

  const LoopCallback({
    required this.type,
    this.instanceId,
    this.assetId,
    this.state,
    this.loopCount,
    this.atSamples,
    this.fromRegion,
    this.toRegion,
    this.cueName,
    this.message,
  });

  bool get isStarted => type == 'started';
  bool get isStateChanged => type == 'stateChanged';
  bool get isWrap => type == 'wrap';
  bool get isRegionSwitched => type == 'regionSwitched';
  bool get isCueHit => type == 'cueHit';
  bool get isStopped => type == 'stopped';
  bool get isVoiceStealWarning => type == 'voiceStealWarning';
  bool get isError => type == 'error';

  factory LoopCallback.fromJson(Map<String, dynamic> json) => LoopCallback(
        type: json['type'] ?? '',
        instanceId: json['instanceId'],
        assetId: json['assetId'],
        state: json['state'] != null
            ? LoopPlaybackState.fromJson(json['state'])
            : null,
        loopCount: json['loopCount'],
        atSamples: json['atSamples'],
        fromRegion: json['from'],
        toRegion: json['to'],
        cueName: json['cueName'],
        message: json['message'],
      );

  factory LoopCallback.fromJsonString(String json) =>
      LoopCallback.fromJson(jsonDecode(json));
}

// ═══════════════════════════════════════════════════════════════════════════════
// INSTANCE STATE (UI-SIDE)
// ═══════════════════════════════════════════════════════════════════════════════

/// UI-side tracking of an active loop instance.
class LoopInstanceState {
  final int instanceId;
  final String assetId;
  String currentRegion;
  LoopPlaybackState state;
  int loopCount;
  double volume;
  double iterationGain;
  int bus;

  LoopInstanceState({
    required this.instanceId,
    required this.assetId,
    required this.currentRegion,
    this.state = LoopPlaybackState.intro,
    this.loopCount = 0,
    this.volume = 1.0,
    this.iterationGain = 1.0,
    this.bus = 0,
  });
}

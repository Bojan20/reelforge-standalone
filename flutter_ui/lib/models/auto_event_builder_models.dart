/// Auto Event Builder Models
///
/// Data models for SlotLab Auto Event Builder system:
/// - AudioAsset: Audio file with metadata, tags, loudness info
/// - DropTarget: UI element that accepts audio drops
/// - EventDraft: Uncommitted event being configured
/// - EventBinding: Connection between event and target
/// - EventPreset: Parameter template for common event types
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md specification.
library;

import 'dart:math' as math;

// =============================================================================
// ASSET TYPE
// =============================================================================

/// Type of audio asset
enum AssetType {
  sfx,      // Sound effects (clicks, impacts, whooshes)
  music,    // Music loops and stingers
  vo,       // Voice/announcer
  amb,      // Ambience/atmosphere
}

extension AssetTypeExtension on AssetType {
  String get displayName {
    switch (this) {
      case AssetType.sfx: return 'SFX';
      case AssetType.music: return 'Music';
      case AssetType.vo: return 'Voice';
      case AssetType.amb: return 'Ambience';
    }
  }

  String get defaultBus {
    switch (this) {
      case AssetType.sfx: return 'SFX';
      case AssetType.music: return 'MUSIC/Base';
      case AssetType.vo: return 'VO';
      case AssetType.amb: return 'AMB';
    }
  }

  static AssetType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'sfx': return AssetType.sfx;
      case 'music': return AssetType.music;
      case 'vo':
      case 'voice': return AssetType.vo;
      case 'amb':
      case 'ambience': return AssetType.amb;
      default: return AssetType.sfx;
    }
  }
}

// =============================================================================
// ASSET TAGS
// =============================================================================

/// Common tags for audio assets
class AssetTags {
  // Interaction tags
  static const String click = 'click';
  static const String press = 'press';
  static const String release = 'release';
  static const String hover = 'hover';

  // Sound character tags
  static const String whoosh = 'whoosh';
  static const String impact = 'impact';
  static const String loop = 'loop';
  static const String stinger = 'stinger';
  static const String tick = 'tick';
  static const String chime = 'chime';
  static const String fanfare = 'fanfare';

  // Slot-specific tags
  static const String reel = 'reel';
  static const String stop = 'stop';
  static const String spin = 'spin';
  static const String anticipation = 'anticipation';
  static const String win = 'win';
  static const String bigwin = 'bigwin';
  static const String jackpot = 'jackpot';
  static const String scatter = 'scatter';
  static const String wild = 'wild';
  static const String bonus = 'bonus';
  static const String freespin = 'freespin';
  static const String cascade = 'cascade';
  static const String rollup = 'rollup';

  // UI tags
  static const String button = 'button';
  static const String menu = 'menu';
  static const String notification = 'notification';
  static const String error = 'error';
  static const String success = 'success';

  /// All available tags
  static const List<String> all = [
    click, press, release, hover,
    whoosh, impact, loop, stinger, tick, chime, fanfare,
    reel, stop, spin, anticipation, win, bigwin, jackpot,
    scatter, wild, bonus, freespin, cascade, rollup,
    button, menu, notification, error, success,
  ];
}

// =============================================================================
// LOUDNESS INFO
// =============================================================================

/// Loudness normalization data for an asset (GAP 3 FIX)
class LoudnessInfo {
  /// Integrated loudness in LUFS
  final double integratedLufs;

  /// True peak in dBFS
  final double truePeak;

  /// Target loudness for normalization
  final double normalizeTarget;

  /// Computed gain to reach target (auto-calculated)
  final double normalizeGain;

  const LoudnessInfo({
    this.integratedLufs = -16.0,
    this.truePeak = -1.0,
    this.normalizeTarget = -14.0,
    this.normalizeGain = 0.0,
  });

  /// Create with auto-computed normalize gain
  factory LoudnessInfo.computed({
    required double integratedLufs,
    required double truePeak,
    double normalizeTarget = -14.0,
  }) {
    final gain = normalizeTarget - integratedLufs;
    // Clamp to avoid excessive gain that would clip
    final safeGain = math.min(gain, -truePeak - 0.5);
    return LoudnessInfo(
      integratedLufs: integratedLufs,
      truePeak: truePeak,
      normalizeTarget: normalizeTarget,
      normalizeGain: safeGain,
    );
  }

  Map<String, dynamic> toJson() => {
    'integratedLufs': integratedLufs,
    'truePeak': truePeak,
    'normalizeTarget': normalizeTarget,
    'normalizeGain': normalizeGain,
  };

  factory LoudnessInfo.fromJson(Map<String, dynamic> json) => LoudnessInfo(
    integratedLufs: (json['integratedLufs'] as num?)?.toDouble() ?? -16.0,
    truePeak: (json['truePeak'] as num?)?.toDouble() ?? -1.0,
    normalizeTarget: (json['normalizeTarget'] as num?)?.toDouble() ?? -14.0,
    normalizeGain: (json['normalizeGain'] as num?)?.toDouble() ?? 0.0,
  );

  static const defaultInfo = LoudnessInfo();
}

// =============================================================================
// AUDIO ASSET
// =============================================================================

/// Exception for invalid asset paths (GAP 25)
class InvalidAssetPathException implements Exception {
  final String message;
  const InvalidAssetPathException(this.message);
  @override
  String toString() => 'InvalidAssetPathException: $message';
}

/// Audio asset with metadata and loudness info
class AudioAsset {
  /// Unique identifier
  final String assetId;

  /// File path (sanitized)
  final String path;

  /// Asset type (SFX, Music, VO, Amb)
  final AssetType assetType;

  /// Tags for categorization and auto-matching
  final List<String> tags;

  /// Whether asset loops
  final bool isLoop;

  /// Duration in milliseconds
  final int durationMs;

  /// Auto-detected variants (e.g., spin_click_01..05)
  final List<String> variants;

  /// Loudness normalization data
  final LoudnessInfo loudnessInfo;

  /// Display name (filename without extension)
  String get displayName {
    final filename = path.split('/').last;
    final dotIndex = filename.lastIndexOf('.');
    return dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
  }

  /// File extension
  String get extension {
    final dotIndex = path.lastIndexOf('.');
    return dotIndex > 0 ? path.substring(dotIndex + 1).toLowerCase() : '';
  }

  const AudioAsset({
    required this.assetId,
    required this.path,
    required this.assetType,
    this.tags = const [],
    this.isLoop = false,
    this.durationMs = 0,
    this.variants = const [],
    this.loudnessInfo = const LoudnessInfo(),
  });

  /// Validate and sanitize asset path (GAP 25 FIX)
  static String sanitizePath(String rawPath) {
    // No path traversal
    if (rawPath.contains('..')) {
      throw const InvalidAssetPathException('Path traversal detected');
    }

    // Only allowed extensions
    const allowedExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};
    final dotIndex = rawPath.lastIndexOf('.');
    if (dotIndex < 0) {
      throw const InvalidAssetPathException('No file extension');
    }
    final ext = rawPath.substring(dotIndex).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw InvalidAssetPathException('Extension not allowed: $ext');
    }

    // Max path length
    if (rawPath.length > 512) {
      throw const InvalidAssetPathException('Path exceeds 512 characters');
    }

    // Remove special characters (keep path separators)
    final sanitized = rawPath.replaceAll(RegExp(r'[<>:"|?*]'), '_');

    return sanitized;
  }

  /// Create from file path with auto-detection
  factory AudioAsset.fromPath(String rawPath, {String? assetId}) {
    final path = sanitizePath(rawPath);
    final filename = path.split('/').last.toLowerCase();

    // Auto-detect asset type from path/filename
    AssetType type = AssetType.sfx;
    if (filename.contains('music') || filename.contains('loop') || filename.contains('bgm')) {
      type = AssetType.music;
    } else if (filename.contains('vo_') || filename.contains('voice') || filename.contains('announce')) {
      type = AssetType.vo;
    } else if (filename.contains('amb') || filename.contains('atmo')) {
      type = AssetType.amb;
    }

    // Auto-detect tags from filename
    final tags = <String>[];
    for (final tag in AssetTags.all) {
      if (filename.contains(tag)) {
        tags.add(tag);
      }
    }

    // Auto-detect loop
    final isLoop = filename.contains('loop') || filename.contains('_lp');

    return AudioAsset(
      assetId: assetId ?? _generateAssetId(path),
      path: path,
      assetType: type,
      tags: tags,
      isLoop: isLoop,
    );
  }

  static String _generateAssetId(String path) {
    final filename = path.split('/').last;
    final dotIndex = filename.lastIndexOf('.');
    final name = dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
    // Convert to snake_case id
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  }

  /// Check if asset matches any of the given tags
  bool hasAnyTag(List<String> checkTags) {
    return tags.any((t) => checkTags.contains(t));
  }

  /// Check if asset matches all of the given tags
  bool hasAllTags(List<String> checkTags) {
    return checkTags.every((t) => tags.contains(t));
  }

  AudioAsset copyWith({
    String? assetId,
    String? path,
    AssetType? assetType,
    List<String>? tags,
    bool? isLoop,
    int? durationMs,
    List<String>? variants,
    LoudnessInfo? loudnessInfo,
  }) {
    return AudioAsset(
      assetId: assetId ?? this.assetId,
      path: path ?? this.path,
      assetType: assetType ?? this.assetType,
      tags: tags ?? this.tags,
      isLoop: isLoop ?? this.isLoop,
      durationMs: durationMs ?? this.durationMs,
      variants: variants ?? this.variants,
      loudnessInfo: loudnessInfo ?? this.loudnessInfo,
    );
  }

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'path': path,
    'assetType': assetType.name,
    'tags': tags,
    'isLoop': isLoop,
    'durationMs': durationMs,
    'variants': variants,
    'loudnessInfo': loudnessInfo.toJson(),
  };

  factory AudioAsset.fromJson(Map<String, dynamic> json) => AudioAsset(
    assetId: json['assetId'] as String,
    path: json['path'] as String,
    assetType: AssetTypeExtension.fromString(json['assetType'] as String? ?? 'sfx'),
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    isLoop: json['isLoop'] as bool? ?? false,
    durationMs: json['durationMs'] as int? ?? 0,
    variants: (json['variants'] as List<dynamic>?)?.cast<String>() ?? [],
    loudnessInfo: json['loudnessInfo'] != null
        ? LoudnessInfo.fromJson(json['loudnessInfo'] as Map<String, dynamic>)
        : const LoudnessInfo(),
  );
}

// =============================================================================
// TARGET TYPE
// =============================================================================

/// Type of drop target in SlotLab UI
enum TargetType {
  uiButton,         // Spin, AutoSpin, Turbo buttons
  uiToggle,         // Toggle buttons
  hudCounter,       // Balance, bet, win displays
  hudMeter,         // Progress bars, meters
  reelSurface,      // Entire reel area
  reelStopZone,     // Individual reel stop positions
  symbol,           // Symbol elements
  symbolZone,       // Per-symbol type drop zones (wild, scatter, HP, LP)
  overlay,          // Win overlays, popups
  featureContainer, // Feature UI containers
  screenZone,       // General screen areas
  musicZone,        // Background music drop zones
}

extension TargetTypeExtension on TargetType {
  String get displayName {
    switch (this) {
      case TargetType.uiButton: return 'UI Button';
      case TargetType.uiToggle: return 'UI Toggle';
      case TargetType.hudCounter: return 'HUD Counter';
      case TargetType.hudMeter: return 'HUD Meter';
      case TargetType.reelSurface: return 'Reel Surface';
      case TargetType.reelStopZone: return 'Reel Stop Zone';
      case TargetType.symbol: return 'Symbol';
      case TargetType.symbolZone: return 'Symbol Zone';
      case TargetType.overlay: return 'Overlay';
      case TargetType.featureContainer: return 'Feature Container';
      case TargetType.screenZone: return 'Screen Zone';
      case TargetType.musicZone: return 'Music Zone';
    }
  }

  /// Default triggers for this target type
  List<String> get defaultTriggers {
    switch (this) {
      case TargetType.uiButton:
        return ['press', 'release', 'hover'];
      case TargetType.uiToggle:
        return ['toggle_on', 'toggle_off'];
      case TargetType.hudCounter:
        return ['value_change', 'increment', 'decrement'];
      case TargetType.hudMeter:
        return ['fill', 'drain', 'threshold'];
      case TargetType.reelSurface:
        return ['spin_start', 'spin_stop'];
      case TargetType.reelStopZone:
        return ['reel_stop', 'anticipation_on', 'anticipation_off'];
      case TargetType.symbol:
        return ['land', 'highlight', 'match'];
      case TargetType.symbolZone:
        return ['land', 'highlight', 'animate', 'win_line'];
      case TargetType.overlay:
        return ['show', 'hide', 'pulse'];
      case TargetType.featureContainer:
        return ['enter', 'exit', 'step'];
      case TargetType.screenZone:
        return ['activate', 'deactivate'];
      case TargetType.musicZone:
        return ['play', 'stop', 'crossfade', 'layer'];
    }
  }

  static TargetType fromString(String s) {
    switch (s) {
      case 'ui_button': return TargetType.uiButton;
      case 'ui_toggle': return TargetType.uiToggle;
      case 'hud_counter': return TargetType.hudCounter;
      case 'hud_meter': return TargetType.hudMeter;
      case 'reel_surface': return TargetType.reelSurface;
      case 'reel_stop_zone': return TargetType.reelStopZone;
      case 'symbol': return TargetType.symbol;
      case 'symbol_zone': return TargetType.symbolZone;
      case 'overlay': return TargetType.overlay;
      case 'feature_container': return TargetType.featureContainer;
      case 'screen_zone': return TargetType.screenZone;
      case 'music_zone': return TargetType.musicZone;
      default: return TargetType.uiButton;
    }
  }
}

// =============================================================================
// STAGE CONTEXT
// =============================================================================

/// Game stage context for target
enum StageContext {
  global,     // Active in all stages
  baseGame,   // Base game only
  freeSpins,  // Free spins feature
  bonus,      // Bonus game
  holdWin,    // Hold & Win / Respin feature
}

extension StageContextExtension on StageContext {
  String get displayName {
    switch (this) {
      case StageContext.global: return 'Global';
      case StageContext.baseGame: return 'Base Game';
      case StageContext.freeSpins: return 'Free Spins';
      case StageContext.bonus: return 'Bonus';
      case StageContext.holdWin: return 'Hold & Win';
    }
  }

  static StageContext fromString(String s) {
    switch (s.toLowerCase()) {
      case 'global': return StageContext.global;
      case 'basegame':
      case 'base_game':
      case 'base': return StageContext.baseGame;
      case 'freespins':
      case 'free_spins':
      case 'fs': return StageContext.freeSpins;
      case 'bonus': return StageContext.bonus;
      case 'holdwin':
      case 'hold_win':
      case 'respin': return StageContext.holdWin;
      default: return StageContext.global;
    }
  }
}

// =============================================================================
// DROP TARGET
// =============================================================================

/// Drop target in SlotLab UI
class DropTarget {
  /// Unique identifier (e.g., "ui.spin", "reel.1", "overlay.bigWin")
  final String targetId;

  /// Target type
  final TargetType targetType;

  /// Tags for matching rules
  final List<String> targetTags;

  /// Stage context
  final StageContext stageContext;

  /// Supported interaction triggers
  final List<String> interactionSemantics;

  /// Display name for UI
  String get displayName {
    final parts = targetId.split('.');
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
  }

  const DropTarget({
    required this.targetId,
    required this.targetType,
    this.targetTags = const [],
    this.stageContext = StageContext.global,
    List<String>? interactionSemantics,
  }) : interactionSemantics = interactionSemantics ?? const [];

  /// Get available triggers (custom or default for type)
  List<String> get availableTriggers {
    return interactionSemantics.isNotEmpty
        ? interactionSemantics
        : targetType.defaultTriggers;
  }

  /// Check if target matches given tags
  bool hasAnyTag(List<String> checkTags) {
    return targetTags.any((t) => checkTags.contains(t));
  }

  Map<String, dynamic> toJson() => {
    'targetId': targetId,
    'targetType': targetType.name,
    'targetTags': targetTags,
    'stageContext': stageContext.name,
    'interactionSemantics': interactionSemantics,
  };

  factory DropTarget.fromJson(Map<String, dynamic> json) => DropTarget(
    targetId: json['targetId'] as String,
    targetType: TargetTypeExtension.fromString(json['targetType'] as String? ?? 'ui_button'),
    targetTags: (json['targetTags'] as List<dynamic>?)?.cast<String>() ?? [],
    stageContext: StageContextExtension.fromString(json['stageContext'] as String? ?? 'global'),
    interactionSemantics: (json['interactionSemantics'] as List<dynamic>?)?.cast<String>(),
  );
}

// =============================================================================
// VARIATION POLICY
// =============================================================================

/// Policy for selecting variants when multiple assets match
enum VariationPolicy {
  random,       // Random selection each time
  roundRobin,   // Cycle through in order
  shuffleBag,   // Random but no repeats until all played
  sequential,   // Always play in order
  weighted,     // Weighted random selection
}

extension VariationPolicyExtension on VariationPolicy {
  String get displayName {
    switch (this) {
      case VariationPolicy.random: return 'Random';
      case VariationPolicy.roundRobin: return 'Round Robin';
      case VariationPolicy.shuffleBag: return 'Shuffle Bag';
      case VariationPolicy.sequential: return 'Sequential';
      case VariationPolicy.weighted: return 'Weighted';
    }
  }

  static VariationPolicy fromString(String s) {
    switch (s.toLowerCase()) {
      case 'random': return VariationPolicy.random;
      case 'roundrobin':
      case 'round_robin': return VariationPolicy.roundRobin;
      case 'shufflebag':
      case 'shuffle_bag': return VariationPolicy.shuffleBag;
      case 'sequential': return VariationPolicy.sequential;
      case 'weighted': return VariationPolicy.weighted;
      default: return VariationPolicy.random;
    }
  }
}

// =============================================================================
// VOICE STEAL POLICY
// =============================================================================

/// Policy for voice stealing when limit is reached (GAP 5 FIX)
enum VoiceStealPolicy {
  none,           // Don't steal, skip new sound
  oldest,         // Steal oldest playing voice
  quietest,       // Steal quietest voice
  lowestPriority, // Steal lowest priority voice
  farthest,       // Steal farthest (spatial) voice
}

extension VoiceStealPolicyExtension on VoiceStealPolicy {
  String get displayName {
    switch (this) {
      case VoiceStealPolicy.none: return 'None (Skip)';
      case VoiceStealPolicy.oldest: return 'Oldest';
      case VoiceStealPolicy.quietest: return 'Quietest';
      case VoiceStealPolicy.lowestPriority: return 'Lowest Priority';
      case VoiceStealPolicy.farthest: return 'Farthest';
    }
  }

  static VoiceStealPolicy fromString(String s) {
    switch (s.toLowerCase()) {
      case 'none': return VoiceStealPolicy.none;
      case 'oldest': return VoiceStealPolicy.oldest;
      case 'quietest': return VoiceStealPolicy.quietest;
      case 'lowestpriority':
      case 'lowest_priority': return VoiceStealPolicy.lowestPriority;
      case 'farthest': return VoiceStealPolicy.farthest;
      default: return VoiceStealPolicy.oldest;
    }
  }
}

// =============================================================================
// PRELOAD POLICY
// =============================================================================

/// Policy for when to preload assets (GAP 9 FIX)
enum PreloadPolicy {
  onCommit,       // Load when event committed to manifest
  onStageEnter,   // Load when game stage activates
  onFirstTrigger, // Lazy load on first trigger
  manual,         // Explicit load via API
}

extension PreloadPolicyExtension on PreloadPolicy {
  String get displayName {
    switch (this) {
      case PreloadPolicy.onCommit: return 'On Commit';
      case PreloadPolicy.onStageEnter: return 'On Stage Enter';
      case PreloadPolicy.onFirstTrigger: return 'On First Trigger';
      case PreloadPolicy.manual: return 'Manual';
    }
  }

  static PreloadPolicy fromString(String s) {
    switch (s.toLowerCase()) {
      case 'oncommit':
      case 'on_commit': return PreloadPolicy.onCommit;
      case 'onstageenter':
      case 'on_stage_enter': return PreloadPolicy.onStageEnter;
      case 'onfirsttrigger':
      case 'on_first_trigger': return PreloadPolicy.onFirstTrigger;
      case 'manual': return PreloadPolicy.manual;
      default: return PreloadPolicy.onStageEnter;
    }
  }
}

// =============================================================================
// EVENT PRESET
// =============================================================================

/// Preset template for event parameters
class EventPreset {
  final String presetId;
  final String name;
  final String? description;

  // Audio parameters
  final double volume;      // -60 to +12 dB
  final double pitch;       // 0.5 to 2.0
  final double pan;         // -1.0 to +1.0
  final double lpf;         // Low-pass filter cutoff (20-20000 Hz)
  final double hpf;         // High-pass filter cutoff (20-20000 Hz)

  // Timing
  final int delayMs;        // Delay before playback
  final int fadeInMs;       // Fade in duration
  final int fadeOutMs;      // Fade out duration
  final int cooldownMs;     // Minimum time between triggers

  // Voice management
  final int polyphony;      // Max simultaneous voices
  final String voiceLimitGroup;
  final VoiceStealPolicy voiceStealPolicy;
  final int voiceStealFadeMs;

  // Priority (0-100)
  final int priority;

  // Preload
  final PreloadPolicy preloadPolicy;

  const EventPreset({
    required this.presetId,
    required this.name,
    this.description,
    this.volume = 0.0,
    this.pitch = 1.0,
    this.pan = 0.0,
    this.lpf = 20000.0,
    this.hpf = 20.0,
    this.delayMs = 0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.cooldownMs = 0,
    this.polyphony = 1,
    this.voiceLimitGroup = 'default',
    this.voiceStealPolicy = VoiceStealPolicy.oldest,
    this.voiceStealFadeMs = 10,
    this.priority = 50,
    this.preloadPolicy = PreloadPolicy.onStageEnter,
  });

  EventPreset copyWith({
    String? presetId,
    String? name,
    String? description,
    double? volume,
    double? pitch,
    double? pan,
    double? lpf,
    double? hpf,
    int? delayMs,
    int? fadeInMs,
    int? fadeOutMs,
    int? cooldownMs,
    int? polyphony,
    String? voiceLimitGroup,
    VoiceStealPolicy? voiceStealPolicy,
    int? voiceStealFadeMs,
    int? priority,
    PreloadPolicy? preloadPolicy,
  }) {
    return EventPreset(
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      description: description ?? this.description,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
      pan: pan ?? this.pan,
      lpf: lpf ?? this.lpf,
      hpf: hpf ?? this.hpf,
      delayMs: delayMs ?? this.delayMs,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      cooldownMs: cooldownMs ?? this.cooldownMs,
      polyphony: polyphony ?? this.polyphony,
      voiceLimitGroup: voiceLimitGroup ?? this.voiceLimitGroup,
      voiceStealPolicy: voiceStealPolicy ?? this.voiceStealPolicy,
      voiceStealFadeMs: voiceStealFadeMs ?? this.voiceStealFadeMs,
      priority: priority ?? this.priority,
      preloadPolicy: preloadPolicy ?? this.preloadPolicy,
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'name': name,
    if (description != null) 'description': description,
    'volume': volume,
    'pitch': pitch,
    'pan': pan,
    'lpf': lpf,
    'hpf': hpf,
    'delayMs': delayMs,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'cooldownMs': cooldownMs,
    'polyphony': polyphony,
    'voiceLimitGroup': voiceLimitGroup,
    'voiceStealPolicy': voiceStealPolicy.name,
    'voiceStealFadeMs': voiceStealFadeMs,
    'priority': priority,
    'preloadPolicy': preloadPolicy.name,
  };

  factory EventPreset.fromJson(Map<String, dynamic> json) => EventPreset(
    presetId: json['presetId'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
    pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    lpf: (json['lpf'] as num?)?.toDouble() ?? 20000.0,
    hpf: (json['hpf'] as num?)?.toDouble() ?? 20.0,
    delayMs: json['delayMs'] as int? ?? 0,
    fadeInMs: json['fadeInMs'] as int? ?? 0,
    fadeOutMs: json['fadeOutMs'] as int? ?? 0,
    cooldownMs: json['cooldownMs'] as int? ?? 0,
    polyphony: json['polyphony'] as int? ?? 1,
    voiceLimitGroup: json['voiceLimitGroup'] as String? ?? 'default',
    voiceStealPolicy: VoiceStealPolicyExtension.fromString(json['voiceStealPolicy'] as String? ?? 'oldest'),
    voiceStealFadeMs: json['voiceStealFadeMs'] as int? ?? 10,
    priority: json['priority'] as int? ?? 50,
    preloadPolicy: PreloadPolicyExtension.fromString(json['preloadPolicy'] as String? ?? 'on_stage_enter'),
  );
}

// =============================================================================
// STANDARD PRESETS
// =============================================================================

// =============================================================================
// EVENT DEPENDENCY (D.1)
// =============================================================================

/// Type of event dependency
enum DependencyType {
  /// Wait for another event to complete before starting
  after,
  /// Start together with another event
  with_,
  /// Stop when another event starts
  stopOnStart,
  /// Stop when another event stops
  stopOnStop,
}

extension DependencyTypeExtension on DependencyType {
  String get displayName {
    switch (this) {
      case DependencyType.after: return 'After';
      case DependencyType.with_: return 'With';
      case DependencyType.stopOnStart: return 'Stop On Start';
      case DependencyType.stopOnStop: return 'Stop On Stop';
    }
  }

  static DependencyType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'after': return DependencyType.after;
      case 'with':
      case 'with_': return DependencyType.with_;
      case 'stoponstart':
      case 'stop_on_start': return DependencyType.stopOnStart;
      case 'stoponstop':
      case 'stop_on_stop': return DependencyType.stopOnStop;
      default: return DependencyType.after;
    }
  }
}

/// A dependency relationship between events
class EventDependency {
  /// The event ID this dependency references
  final String targetEventId;

  /// Type of dependency
  final DependencyType type;

  /// Optional delay after dependency condition is met (ms)
  final int delayMs;

  /// Whether dependency is required (event won't play without it)
  final bool required;

  const EventDependency({
    required this.targetEventId,
    this.type = DependencyType.after,
    this.delayMs = 0,
    this.required = true,
  });

  EventDependency copyWith({
    String? targetEventId,
    DependencyType? type,
    int? delayMs,
    bool? required,
  }) {
    return EventDependency(
      targetEventId: targetEventId ?? this.targetEventId,
      type: type ?? this.type,
      delayMs: delayMs ?? this.delayMs,
      required: required ?? this.required,
    );
  }

  Map<String, dynamic> toJson() => {
    'targetEventId': targetEventId,
    'type': type.name,
    'delayMs': delayMs,
    'required': required,
  };

  factory EventDependency.fromJson(Map<String, dynamic> json) => EventDependency(
    targetEventId: json['targetEventId'] as String,
    type: DependencyTypeExtension.fromString(json['type'] as String? ?? 'after'),
    delayMs: json['delayMs'] as int? ?? 0,
    required: json['required'] as bool? ?? true,
  );
}

// =============================================================================
// CONDITIONAL TRIGGER (D.2)
// =============================================================================

/// Comparison operator for conditional triggers
enum ConditionOperator {
  equals,
  notEquals,
  greaterThan,
  lessThan,
  greaterOrEqual,
  lessOrEqual,
  contains,
  startsWith,
  endsWith,
}

extension ConditionOperatorExtension on ConditionOperator {
  String get symbol {
    switch (this) {
      case ConditionOperator.equals: return '==';
      case ConditionOperator.notEquals: return '!=';
      case ConditionOperator.greaterThan: return '>';
      case ConditionOperator.lessThan: return '<';
      case ConditionOperator.greaterOrEqual: return '>=';
      case ConditionOperator.lessOrEqual: return '<=';
      case ConditionOperator.contains: return 'contains';
      case ConditionOperator.startsWith: return 'starts';
      case ConditionOperator.endsWith: return 'ends';
    }
  }

  String get displayName {
    switch (this) {
      case ConditionOperator.equals: return 'Equals';
      case ConditionOperator.notEquals: return 'Not Equals';
      case ConditionOperator.greaterThan: return 'Greater Than';
      case ConditionOperator.lessThan: return 'Less Than';
      case ConditionOperator.greaterOrEqual: return 'Greater or Equal';
      case ConditionOperator.lessOrEqual: return 'Less or Equal';
      case ConditionOperator.contains: return 'Contains';
      case ConditionOperator.startsWith: return 'Starts With';
      case ConditionOperator.endsWith: return 'Ends With';
    }
  }

  static ConditionOperator fromString(String s) {
    switch (s.toLowerCase()) {
      case 'equals':
      case '==': return ConditionOperator.equals;
      case 'notequals':
      case 'not_equals':
      case '!=': return ConditionOperator.notEquals;
      case 'greaterthan':
      case 'greater_than':
      case '>': return ConditionOperator.greaterThan;
      case 'lessthan':
      case 'less_than':
      case '<': return ConditionOperator.lessThan;
      case 'greaterorequal':
      case 'greater_or_equal':
      case '>=': return ConditionOperator.greaterOrEqual;
      case 'lessorequal':
      case 'less_or_equal':
      case '<=': return ConditionOperator.lessOrEqual;
      case 'contains': return ConditionOperator.contains;
      case 'startswith':
      case 'starts_with': return ConditionOperator.startsWith;
      case 'endswith':
      case 'ends_with': return ConditionOperator.endsWith;
      default: return ConditionOperator.equals;
    }
  }
}

/// Logic operator for combining conditions
enum ConditionLogic {
  and,
  or,
}

/// A single condition for conditional triggers
class TriggerCondition {
  /// Parameter/variable name to check
  final String paramName;

  /// Comparison operator
  final ConditionOperator operator;

  /// Value to compare against
  final dynamic value;

  const TriggerCondition({
    required this.paramName,
    required this.operator,
    required this.value,
  });

  /// Evaluate this condition against a set of parameters
  bool evaluate(Map<String, dynamic> params) {
    final paramValue = params[paramName];
    if (paramValue == null) return false;

    switch (operator) {
      case ConditionOperator.equals:
        return paramValue == value;
      case ConditionOperator.notEquals:
        return paramValue != value;
      case ConditionOperator.greaterThan:
        return (paramValue as num) > (value as num);
      case ConditionOperator.lessThan:
        return (paramValue as num) < (value as num);
      case ConditionOperator.greaterOrEqual:
        return (paramValue as num) >= (value as num);
      case ConditionOperator.lessOrEqual:
        return (paramValue as num) <= (value as num);
      case ConditionOperator.contains:
        return paramValue.toString().contains(value.toString());
      case ConditionOperator.startsWith:
        return paramValue.toString().startsWith(value.toString());
      case ConditionOperator.endsWith:
        return paramValue.toString().endsWith(value.toString());
    }
  }

  Map<String, dynamic> toJson() => {
    'paramName': paramName,
    'operator': operator.name,
    'value': value,
  };

  factory TriggerCondition.fromJson(Map<String, dynamic> json) => TriggerCondition(
    paramName: json['paramName'] as String,
    operator: ConditionOperatorExtension.fromString(json['operator'] as String? ?? 'equals'),
    value: json['value'],
  );
}

/// Conditional trigger that evaluates runtime conditions
class ConditionalTrigger {
  /// Unique ID for this conditional trigger
  final String triggerId;

  /// Display name
  final String name;

  /// Conditions to evaluate
  final List<TriggerCondition> conditions;

  /// How to combine conditions
  final ConditionLogic logic;

  /// Whether trigger is enabled
  final bool enabled;

  const ConditionalTrigger({
    required this.triggerId,
    required this.name,
    this.conditions = const [],
    this.logic = ConditionLogic.and,
    this.enabled = true,
  });

  /// Evaluate all conditions
  bool evaluate(Map<String, dynamic> params) {
    if (!enabled || conditions.isEmpty) return true;

    if (logic == ConditionLogic.and) {
      return conditions.every((c) => c.evaluate(params));
    } else {
      return conditions.any((c) => c.evaluate(params));
    }
  }

  ConditionalTrigger copyWith({
    String? triggerId,
    String? name,
    List<TriggerCondition>? conditions,
    ConditionLogic? logic,
    bool? enabled,
  }) {
    return ConditionalTrigger(
      triggerId: triggerId ?? this.triggerId,
      name: name ?? this.name,
      conditions: conditions ?? this.conditions,
      logic: logic ?? this.logic,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'triggerId': triggerId,
    'name': name,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'logic': logic.name,
    'enabled': enabled,
  };

  factory ConditionalTrigger.fromJson(Map<String, dynamic> json) => ConditionalTrigger(
    triggerId: json['triggerId'] as String,
    name: json['name'] as String,
    conditions: (json['conditions'] as List<dynamic>?)
        ?.map((c) => TriggerCondition.fromJson(c as Map<String, dynamic>))
        .toList() ?? [],
    logic: json['logic'] == 'or' ? ConditionLogic.or : ConditionLogic.and,
    enabled: json['enabled'] as bool? ?? true,
  );
}

// =============================================================================
// RTPC BINDING (D.3)
// =============================================================================

/// Curve types for RTPC mapping
enum RtpcCurveType {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  logarithmic,
  exponential,
  sCurve,
}

extension RtpcCurveTypeExtension on RtpcCurveType {
  String get displayName {
    switch (this) {
      case RtpcCurveType.linear: return 'Linear';
      case RtpcCurveType.easeIn: return 'Ease In';
      case RtpcCurveType.easeOut: return 'Ease Out';
      case RtpcCurveType.easeInOut: return 'Ease In/Out';
      case RtpcCurveType.logarithmic: return 'Logarithmic';
      case RtpcCurveType.exponential: return 'Exponential';
      case RtpcCurveType.sCurve: return 'S-Curve';
    }
  }

  static RtpcCurveType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'linear': return RtpcCurveType.linear;
      case 'easein':
      case 'ease_in': return RtpcCurveType.easeIn;
      case 'easeout':
      case 'ease_out': return RtpcCurveType.easeOut;
      case 'easeinout':
      case 'ease_in_out': return RtpcCurveType.easeInOut;
      case 'logarithmic':
      case 'log': return RtpcCurveType.logarithmic;
      case 'exponential':
      case 'exp': return RtpcCurveType.exponential;
      case 'scurve':
      case 's_curve': return RtpcCurveType.sCurve;
      default: return RtpcCurveType.linear;
    }
  }
}

/// RTPC (Real-Time Parameter Control) binding
class RtpcBinding {
  /// RTPC parameter name (e.g., "winAmount", "spinSpeed", "volume")
  final String rtpcName;

  /// Event parameter to modulate
  final String eventParam;

  /// Input range (RTPC value range)
  final double inputMin;
  final double inputMax;

  /// Output range (event parameter range)
  final double outputMin;
  final double outputMax;

  /// Curve type for mapping
  final RtpcCurveType curveType;

  /// Whether binding is enabled
  final bool enabled;

  const RtpcBinding({
    required this.rtpcName,
    required this.eventParam,
    this.inputMin = 0.0,
    this.inputMax = 1.0,
    this.outputMin = 0.0,
    this.outputMax = 1.0,
    this.curveType = RtpcCurveType.linear,
    this.enabled = true,
  });

  /// Map input value to output value
  double map(double input) {
    if (!enabled) return outputMin;

    // Clamp input to range
    final clamped = input.clamp(inputMin, inputMax);

    // Normalize to 0-1
    final normalized = (clamped - inputMin) / (inputMax - inputMin);

    // Apply curve
    final curved = _applyCurve(normalized);

    // Map to output range
    return outputMin + curved * (outputMax - outputMin);
  }

  double _applyCurve(double t) {
    switch (curveType) {
      case RtpcCurveType.linear:
        return t;
      case RtpcCurveType.easeIn:
        return t * t;
      case RtpcCurveType.easeOut:
        return 1 - (1 - t) * (1 - t);
      case RtpcCurveType.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      case RtpcCurveType.logarithmic:
        return math.log(1 + t * 9) / math.log(10);
      case RtpcCurveType.exponential:
        return (math.pow(10, t) - 1) / 9;
      case RtpcCurveType.sCurve:
        return 1 / (1 + math.exp(-12 * (t - 0.5)));
    }
  }

  RtpcBinding copyWith({
    String? rtpcName,
    String? eventParam,
    double? inputMin,
    double? inputMax,
    double? outputMin,
    double? outputMax,
    RtpcCurveType? curveType,
    bool? enabled,
  }) {
    return RtpcBinding(
      rtpcName: rtpcName ?? this.rtpcName,
      eventParam: eventParam ?? this.eventParam,
      inputMin: inputMin ?? this.inputMin,
      inputMax: inputMax ?? this.inputMax,
      outputMin: outputMin ?? this.outputMin,
      outputMax: outputMax ?? this.outputMax,
      curveType: curveType ?? this.curveType,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'rtpcName': rtpcName,
    'eventParam': eventParam,
    'inputMin': inputMin,
    'inputMax': inputMax,
    'outputMin': outputMin,
    'outputMax': outputMax,
    'curveType': curveType.name,
    'enabled': enabled,
  };

  factory RtpcBinding.fromJson(Map<String, dynamic> json) => RtpcBinding(
    rtpcName: json['rtpcName'] as String,
    eventParam: json['eventParam'] as String,
    inputMin: (json['inputMin'] as num?)?.toDouble() ?? 0.0,
    inputMax: (json['inputMax'] as num?)?.toDouble() ?? 1.0,
    outputMin: (json['outputMin'] as num?)?.toDouble() ?? 0.0,
    outputMax: (json['outputMax'] as num?)?.toDouble() ?? 1.0,
    curveType: RtpcCurveTypeExtension.fromString(json['curveType'] as String? ?? 'linear'),
    enabled: json['enabled'] as bool? ?? true,
  );
}

// =============================================================================
// MUSIC CROSSFADE CONFIG (D.7)
// =============================================================================

/// Crossfade curve types
enum CrossfadeCurve {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  equalPower,
  sCurve,
}

extension CrossfadeCurveExtension on CrossfadeCurve {
  String get displayName {
    switch (this) {
      case CrossfadeCurve.linear: return 'Linear';
      case CrossfadeCurve.easeIn: return 'Ease In';
      case CrossfadeCurve.easeOut: return 'Ease Out';
      case CrossfadeCurve.easeInOut: return 'Ease In/Out';
      case CrossfadeCurve.equalPower: return 'Equal Power';
      case CrossfadeCurve.sCurve: return 'S-Curve';
    }
  }

  static CrossfadeCurve fromString(String s) {
    switch (s.toLowerCase()) {
      case 'linear': return CrossfadeCurve.linear;
      case 'easein':
      case 'ease_in': return CrossfadeCurve.easeIn;
      case 'easeout':
      case 'ease_out': return CrossfadeCurve.easeOut;
      case 'easeinout':
      case 'ease_in_out': return CrossfadeCurve.easeInOut;
      case 'equalpower':
      case 'equal_power': return CrossfadeCurve.equalPower;
      case 'scurve':
      case 's_curve': return CrossfadeCurve.sCurve;
      default: return CrossfadeCurve.linear;
    }
  }

  /// Calculate fade value at position t (0-1)
  double calculate(double t) {
    switch (this) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.easeIn:
        return t * t;
      case CrossfadeCurve.easeOut:
        return 1 - (1 - t) * (1 - t);
      case CrossfadeCurve.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      case CrossfadeCurve.equalPower:
        return math.sqrt(t);
      case CrossfadeCurve.sCurve:
        return 1 / (1 + math.exp(-12 * (t - 0.5)));
    }
  }
}

/// Crossfade overlap modes
enum CrossfadeOverlap {
  /// Full overlap - both tracks at full volume briefly
  full,
  /// Half overlap - 50% overlap
  half,
  /// No overlap - outgoing ends before incoming starts
  none,
  /// Custom overlap percentage
  custom,
}

extension CrossfadeOverlapExtension on CrossfadeOverlap {
  String get displayName {
    switch (this) {
      case CrossfadeOverlap.full: return 'Full';
      case CrossfadeOverlap.half: return 'Half';
      case CrossfadeOverlap.none: return 'None';
      case CrossfadeOverlap.custom: return 'Custom';
    }
  }

  static CrossfadeOverlap fromString(String s) {
    switch (s.toLowerCase()) {
      case 'full': return CrossfadeOverlap.full;
      case 'half': return CrossfadeOverlap.half;
      case 'none': return CrossfadeOverlap.none;
      case 'custom': return CrossfadeOverlap.custom;
      default: return CrossfadeOverlap.full;
    }
  }
}

/// Crossfade configuration for music transitions
class MusicCrossfadeConfig {
  /// Crossfade duration in milliseconds
  final int durationMs;

  /// Fade curve for outgoing track
  final CrossfadeCurve outCurve;

  /// Fade curve for incoming track
  final CrossfadeCurve inCurve;

  /// Whether to sync to beat
  final bool syncToBeat;

  /// Overlap mode
  final CrossfadeOverlap overlap;

  /// Optional delay before crossfade starts
  final int preDelayMs;

  const MusicCrossfadeConfig({
    this.durationMs = 2000,
    this.outCurve = CrossfadeCurve.linear,
    this.inCurve = CrossfadeCurve.linear,
    this.syncToBeat = true,
    this.overlap = CrossfadeOverlap.full,
    this.preDelayMs = 0,
  });

  /// Equal power crossfade (default for music)
  static const equalPower = MusicCrossfadeConfig(
    durationMs: 2000,
    outCurve: CrossfadeCurve.equalPower,
    inCurve: CrossfadeCurve.equalPower,
    syncToBeat: true,
    overlap: CrossfadeOverlap.full,
  );

  /// Quick cut crossfade
  static const quickCut = MusicCrossfadeConfig(
    durationMs: 500,
    outCurve: CrossfadeCurve.easeOut,
    inCurve: CrossfadeCurve.easeIn,
    syncToBeat: true,
    overlap: CrossfadeOverlap.half,
  );

  /// Smooth blend crossfade
  static const smoothBlend = MusicCrossfadeConfig(
    durationMs: 4000,
    outCurve: CrossfadeCurve.sCurve,
    inCurve: CrossfadeCurve.sCurve,
    syncToBeat: true,
    overlap: CrossfadeOverlap.full,
  );

  MusicCrossfadeConfig copyWith({
    int? durationMs,
    CrossfadeCurve? outCurve,
    CrossfadeCurve? inCurve,
    bool? syncToBeat,
    CrossfadeOverlap? overlap,
    int? preDelayMs,
  }) {
    return MusicCrossfadeConfig(
      durationMs: durationMs ?? this.durationMs,
      outCurve: outCurve ?? this.outCurve,
      inCurve: inCurve ?? this.inCurve,
      syncToBeat: syncToBeat ?? this.syncToBeat,
      overlap: overlap ?? this.overlap,
      preDelayMs: preDelayMs ?? this.preDelayMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'durationMs': durationMs,
    'outCurve': outCurve.name,
    'inCurve': inCurve.name,
    'syncToBeat': syncToBeat,
    'overlap': overlap.name,
    'preDelayMs': preDelayMs,
  };

  factory MusicCrossfadeConfig.fromJson(Map<String, dynamic> json) => MusicCrossfadeConfig(
    durationMs: json['durationMs'] as int? ?? 2000,
    outCurve: CrossfadeCurveExtension.fromString(json['outCurve'] as String? ?? 'linear'),
    inCurve: CrossfadeCurveExtension.fromString(json['inCurve'] as String? ?? 'linear'),
    syncToBeat: json['syncToBeat'] as bool? ?? true,
    overlap: CrossfadeOverlapExtension.fromString(json['overlap'] as String? ?? 'full'),
    preDelayMs: json['preDelayMs'] as int? ?? 0,
  );
}

// =============================================================================
// TEMPLATE INHERITANCE (D.4)
// =============================================================================

/// Override mode for inherited parameters
enum OverrideMode {
  /// Replace parent value completely
  replace,
  /// Merge with parent (for lists/maps)
  merge,
  /// Add to parent value (for numbers)
  additive,
  /// Multiply with parent value (for numbers)
  multiplicative,
}

extension OverrideModeExtension on OverrideMode {
  String get displayName {
    switch (this) {
      case OverrideMode.replace: return 'Replace';
      case OverrideMode.merge: return 'Merge';
      case OverrideMode.additive: return 'Add';
      case OverrideMode.multiplicative: return 'Multiply';
    }
  }

  static OverrideMode fromString(String s) {
    switch (s.toLowerCase()) {
      case 'replace': return OverrideMode.replace;
      case 'merge': return OverrideMode.merge;
      case 'additive':
      case 'add': return OverrideMode.additive;
      case 'multiplicative':
      case 'multiply': return OverrideMode.multiplicative;
      default: return OverrideMode.replace;
    }
  }
}

/// A parameter override with mode
class ParameterOverride {
  final String paramName;
  final dynamic value;
  final OverrideMode mode;

  const ParameterOverride({
    required this.paramName,
    required this.value,
    this.mode = OverrideMode.replace,
  });

  /// Apply override to parent value
  dynamic apply(dynamic parentValue) {
    if (parentValue == null) return value;

    switch (mode) {
      case OverrideMode.replace:
        return value;

      case OverrideMode.merge:
        if (parentValue is Map && value is Map) {
          return {...parentValue, ...value};
        }
        if (parentValue is List && value is List) {
          return [...parentValue, ...value];
        }
        return value;

      case OverrideMode.additive:
        if (parentValue is num && value is num) {
          return parentValue + value;
        }
        return value;

      case OverrideMode.multiplicative:
        if (parentValue is num && value is num) {
          return parentValue * value;
        }
        return value;
    }
  }

  Map<String, dynamic> toJson() => {
    'paramName': paramName,
    'value': value,
    'mode': mode.name,
  };

  factory ParameterOverride.fromJson(Map<String, dynamic> json) => ParameterOverride(
    paramName: json['paramName'] as String,
    value: json['value'],
    mode: OverrideModeExtension.fromString(json['mode'] as String? ?? 'replace'),
  );
}

/// Inheritable preset with extends support
class InheritablePreset {
  /// Unique preset ID
  final String presetId;

  /// Display name
  final String name;

  /// Optional description
  final String? description;

  /// Parent preset ID (null = root preset)
  final String? extendsPresetId;

  /// Tags for categorization
  final List<String> tags;

  /// Category path (e.g., "UI/Buttons", "Reels/Stops")
  final String category;

  /// Whether this preset is sealed (cannot be extended)
  final bool isSealed;

  /// Whether this preset is abstract (cannot be used directly)
  final bool isAbstract;

  /// Parameter overrides (applied on top of parent)
  final List<ParameterOverride> overrides;

  /// Full parameter values (for leaf presets or convenience)
  final Map<String, dynamic> parameters;

  /// Dependencies on other presets (for multi-inheritance-like behavior)
  final List<String> mixinPresetIds;

  /// Version number (for migration support)
  final int version;

  /// Created timestamp
  final DateTime createdAt;

  /// Last modified timestamp
  final DateTime? modifiedAt;

  const InheritablePreset({
    required this.presetId,
    required this.name,
    this.description,
    this.extendsPresetId,
    this.tags = const [],
    this.category = 'General',
    this.isSealed = false,
    this.isAbstract = false,
    this.overrides = const [],
    this.parameters = const {},
    this.mixinPresetIds = const [],
    this.version = 1,
    required this.createdAt,
    this.modifiedAt,
  });

  /// Check if this preset extends another
  bool get hasParent => extendsPresetId != null;

  /// Check if this preset has mixins
  bool get hasMixins => mixinPresetIds.isNotEmpty;

  /// Get display path (category + name)
  String get displayPath => category.isEmpty ? name : '$category / $name';

  InheritablePreset copyWith({
    String? presetId,
    String? name,
    String? description,
    String? extendsPresetId,
    List<String>? tags,
    String? category,
    bool? isSealed,
    bool? isAbstract,
    List<ParameterOverride>? overrides,
    Map<String, dynamic>? parameters,
    List<String>? mixinPresetIds,
    int? version,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return InheritablePreset(
      presetId: presetId ?? this.presetId,
      name: name ?? this.name,
      description: description ?? this.description,
      extendsPresetId: extendsPresetId ?? this.extendsPresetId,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      isSealed: isSealed ?? this.isSealed,
      isAbstract: isAbstract ?? this.isAbstract,
      overrides: overrides ?? this.overrides,
      parameters: parameters ?? this.parameters,
      mixinPresetIds: mixinPresetIds ?? this.mixinPresetIds,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'name': name,
    if (description != null) 'description': description,
    if (extendsPresetId != null) 'extends': extendsPresetId,
    'tags': tags,
    'category': category,
    'isSealed': isSealed,
    'isAbstract': isAbstract,
    'overrides': overrides.map((o) => o.toJson()).toList(),
    'parameters': parameters,
    'mixinPresetIds': mixinPresetIds,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
  };

  factory InheritablePreset.fromJson(Map<String, dynamic> json) => InheritablePreset(
    presetId: json['presetId'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    extendsPresetId: json['extends'] as String?,
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    category: json['category'] as String? ?? 'General',
    isSealed: json['isSealed'] as bool? ?? false,
    isAbstract: json['isAbstract'] as bool? ?? false,
    overrides: (json['overrides'] as List<dynamic>?)
        ?.map((o) => ParameterOverride.fromJson(o as Map<String, dynamic>))
        .toList() ?? [],
    parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
    mixinPresetIds: (json['mixinPresetIds'] as List<dynamic>?)?.cast<String>() ?? [],
    version: json['version'] as int? ?? 1,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now(),
    modifiedAt: json['modifiedAt'] != null
        ? DateTime.parse(json['modifiedAt'] as String)
        : null,
  );

  /// Convert from legacy EventPreset
  factory InheritablePreset.fromEventPreset(EventPreset preset) {
    return InheritablePreset(
      presetId: preset.presetId,
      name: preset.name,
      description: preset.description,
      category: _inferCategory(preset.presetId),
      parameters: {
        'volume': preset.volume,
        'pitch': preset.pitch,
        'pan': preset.pan,
        'lpf': preset.lpf,
        'hpf': preset.hpf,
        'delayMs': preset.delayMs,
        'fadeInMs': preset.fadeInMs,
        'fadeOutMs': preset.fadeOutMs,
        'cooldownMs': preset.cooldownMs,
        'polyphony': preset.polyphony,
        'voiceLimitGroup': preset.voiceLimitGroup,
        'voiceStealPolicy': preset.voiceStealPolicy.name,
        'voiceStealFadeMs': preset.voiceStealFadeMs,
        'priority': preset.priority,
        'preloadPolicy': preset.preloadPolicy.name,
      },
      createdAt: DateTime.now(),
    );
  }

  static String _inferCategory(String presetId) {
    if (presetId.startsWith('ui_')) return 'UI';
    if (presetId.startsWith('reel_')) return 'Reels';
    if (presetId.startsWith('win_')) return 'Wins';
    if (presetId.startsWith('music_')) return 'Music';
    if (presetId.contains('jackpot')) return 'Wins/Jackpot';
    if (presetId.contains('anticipation')) return 'Features';
    return 'General';
  }

  /// Convert to legacy EventPreset (for backward compatibility)
  EventPreset toEventPreset() {
    return EventPreset(
      presetId: presetId,
      name: name,
      description: description,
      volume: (parameters['volume'] as num?)?.toDouble() ?? 0.0,
      pitch: (parameters['pitch'] as num?)?.toDouble() ?? 1.0,
      pan: (parameters['pan'] as num?)?.toDouble() ?? 0.0,
      lpf: (parameters['lpf'] as num?)?.toDouble() ?? 20000.0,
      hpf: (parameters['hpf'] as num?)?.toDouble() ?? 20.0,
      delayMs: parameters['delayMs'] as int? ?? 0,
      fadeInMs: parameters['fadeInMs'] as int? ?? 0,
      fadeOutMs: parameters['fadeOutMs'] as int? ?? 0,
      cooldownMs: parameters['cooldownMs'] as int? ?? 0,
      polyphony: parameters['polyphony'] as int? ?? 1,
      voiceLimitGroup: parameters['voiceLimitGroup'] as String? ?? 'default',
      voiceStealPolicy: VoiceStealPolicyExtension.fromString(
        parameters['voiceStealPolicy'] as String? ?? 'oldest',
      ),
      voiceStealFadeMs: parameters['voiceStealFadeMs'] as int? ?? 10,
      priority: parameters['priority'] as int? ?? 50,
      preloadPolicy: PreloadPolicyExtension.fromString(
        parameters['preloadPolicy'] as String? ?? 'on_stage_enter',
      ),
    );
  }
}

/// Resolver for preset inheritance chains
class PresetInheritanceResolver {
  final Map<String, InheritablePreset> _presets = {};

  /// Register a preset
  void register(InheritablePreset preset) {
    _presets[preset.presetId] = preset;
  }

  /// Unregister a preset
  void unregister(String presetId) {
    _presets.remove(presetId);
  }

  /// Get preset by ID
  InheritablePreset? getPreset(String presetId) => _presets[presetId];

  /// Get all registered presets
  List<InheritablePreset> get allPresets => _presets.values.toList();

  /// Resolve full inheritance chain for a preset
  List<String> resolveInheritanceChain(String presetId) {
    final chain = <String>[];
    final visited = <String>{};
    String? current = presetId;

    while (current != null && !visited.contains(current)) {
      visited.add(current);
      chain.add(current);
      current = _presets[current]?.extendsPresetId;
    }

    return chain.reversed.toList(); // Root first
  }

  /// Check for circular inheritance
  bool hasCircularInheritance(String presetId, {String? proposedParentId}) {
    final visited = <String>{};
    String? current = proposedParentId ?? _presets[presetId]?.extendsPresetId;

    while (current != null) {
      if (current == presetId) return true;
      if (visited.contains(current)) return false; // Already checked
      visited.add(current);
      current = _presets[current]?.extendsPresetId;
    }

    return false;
  }

  /// Get all presets that extend a given preset
  List<InheritablePreset> getDirectChildren(String presetId) {
    return _presets.values
        .where((p) => p.extendsPresetId == presetId)
        .toList();
  }

  /// Get all descendants (direct + indirect children)
  List<InheritablePreset> getAllDescendants(String presetId) {
    final result = <InheritablePreset>[];
    final queue = [presetId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = getDirectChildren(current);
      result.addAll(children);
      queue.addAll(children.map((c) => c.presetId));
    }

    return result;
  }

  /// Get root presets (no parent)
  List<InheritablePreset> getRootPresets() {
    return _presets.values.where((p) => !p.hasParent).toList();
  }

  /// Get presets by category
  List<InheritablePreset> getPresetsByCategory(String category) {
    return _presets.values.where((p) => p.category == category).toList();
  }

  /// Get all unique categories
  List<String> getAllCategories() {
    return _presets.values.map((p) => p.category).toSet().toList()..sort();
  }

  /// Resolve final parameters for a preset (applies full inheritance chain)
  Map<String, dynamic> resolveParameters(String presetId) {
    final chain = resolveInheritanceChain(presetId);
    final result = <String, dynamic>{};

    for (final id in chain) {
      final preset = _presets[id];
      if (preset == null) continue;

      // First apply base parameters
      for (final entry in preset.parameters.entries) {
        result[entry.key] = entry.value;
      }

      // Then apply mixins (in order)
      for (final mixinId in preset.mixinPresetIds) {
        final mixinParams = resolveParameters(mixinId);
        for (final entry in mixinParams.entries) {
          if (!result.containsKey(entry.key)) {
            result[entry.key] = entry.value;
          }
        }
      }

      // Finally apply overrides
      for (final override in preset.overrides) {
        result[override.paramName] = override.apply(result[override.paramName]);
      }
    }

    return result;
  }

  /// Get which parameters are overridden at each level
  Map<String, List<String>> getOverrideMap(String presetId) {
    final chain = resolveInheritanceChain(presetId);
    final result = <String, List<String>>{};

    for (final id in chain) {
      final preset = _presets[id];
      if (preset == null) continue;

      final overriddenParams = <String>[];

      // Parameters defined at this level
      overriddenParams.addAll(preset.parameters.keys);

      // Explicit overrides
      overriddenParams.addAll(preset.overrides.map((o) => o.paramName));

      if (overriddenParams.isNotEmpty) {
        result[id] = overriddenParams;
      }
    }

    return result;
  }

  /// Validate inheritance for a preset
  List<String> validateInheritance(String presetId) {
    final errors = <String>[];
    final preset = _presets[presetId];

    if (preset == null) {
      errors.add('Preset not found: $presetId');
      return errors;
    }

    // Check parent exists
    if (preset.extendsPresetId != null) {
      final parent = _presets[preset.extendsPresetId];
      if (parent == null) {
        errors.add('Parent preset not found: ${preset.extendsPresetId}');
      } else if (parent.isSealed) {
        errors.add('Cannot extend sealed preset: ${preset.extendsPresetId}');
      }
    }

    // Check for circular inheritance
    if (hasCircularInheritance(presetId)) {
      errors.add('Circular inheritance detected');
    }

    // Check mixins exist
    for (final mixinId in preset.mixinPresetIds) {
      if (!_presets.containsKey(mixinId)) {
        errors.add('Mixin preset not found: $mixinId');
      }
    }

    // Check abstract preset not used directly (would be checked at usage site)
    if (preset.isAbstract) {
      errors.add('Warning: Abstract preset should not be used directly');
    }

    return errors;
  }

  /// Build inheritance tree as nested structure
  Map<String, dynamic> buildInheritanceTree() {
    Map<String, dynamic> buildNode(String presetId) {
      final preset = _presets[presetId]!;
      final children = getDirectChildren(presetId);

      return {
        'preset': preset,
        'children': children.map((c) => buildNode(c.presetId)).toList(),
      };
    }

    final roots = getRootPresets();
    return {
      'roots': roots.map((r) => buildNode(r.presetId)).toList(),
    };
  }

  /// Convert to flat list with depth info (for tree view)
  List<({InheritablePreset preset, int depth, bool hasChildren})> toFlatTree() {
    final result = <({InheritablePreset preset, int depth, bool hasChildren})>[];

    void traverse(String presetId, int depth) {
      final preset = _presets[presetId];
      if (preset == null) return;

      final children = getDirectChildren(presetId);
      result.add((preset: preset, depth: depth, hasChildren: children.isNotEmpty));

      for (final child in children) {
        traverse(child.presetId, depth + 1);
      }
    }

    for (final root in getRootPresets()) {
      traverse(root.presetId, 0);
    }

    return result;
  }
}

// =============================================================================
// BATCH DROP GROUP TARGETS (D.5)
// =============================================================================

/// Group target for batch operations
enum GroupTargetType {
  /// All reels (reel.0, reel.1, reel.2, reel.3, reel.4)
  allReels,
  /// All reel stop zones
  allReelStops,
  /// All UI buttons
  allUiButtons,
  /// All symbol zones
  allSymbolZones,
  /// All win overlays
  allWinOverlays,
  /// All feature containers
  allFeatures,
  /// Custom group
  custom,
}

extension GroupTargetTypeExtension on GroupTargetType {
  String get displayName {
    switch (this) {
      case GroupTargetType.allReels: return 'All Reels';
      case GroupTargetType.allReelStops: return 'All Reel Stops';
      case GroupTargetType.allUiButtons: return 'All UI Buttons';
      case GroupTargetType.allSymbolZones: return 'All Symbol Zones';
      case GroupTargetType.allWinOverlays: return 'All Win Overlays';
      case GroupTargetType.allFeatures: return 'All Features';
      case GroupTargetType.custom: return 'Custom Group';
    }
  }

  String get description {
    switch (this) {
      case GroupTargetType.allReels:
        return 'Drop to all 5 reels with automatic L-R panning';
      case GroupTargetType.allReelStops:
        return 'Drop to all reel stop zones';
      case GroupTargetType.allUiButtons:
        return 'Drop to all UI buttons';
      case GroupTargetType.allSymbolZones:
        return 'Drop to all symbol type zones';
      case GroupTargetType.allWinOverlays:
        return 'Drop to all win tier overlays';
      case GroupTargetType.allFeatures:
        return 'Drop to all feature containers';
      case GroupTargetType.custom:
        return 'Custom target group';
    }
  }

  /// Get target IDs for this group
  List<String> getTargetIds({int reelCount = 5}) {
    switch (this) {
      case GroupTargetType.allReels:
        return List.generate(reelCount, (i) => 'reel.$i');
      case GroupTargetType.allReelStops:
        return List.generate(reelCount, (i) => 'reel.$i.stop');
      case GroupTargetType.allUiButtons:
        return ['ui.spin', 'ui.autospin', 'ui.turbo', 'ui.maxbet', 'ui.menu', 'ui.info'];
      case GroupTargetType.allSymbolZones:
        return ['symbol.wild', 'symbol.scatter', 'symbol.bonus', 'symbol.hp1', 'symbol.hp2', 'symbol.lp1', 'symbol.lp2', 'symbol.lp3', 'symbol.lp4'];
      case GroupTargetType.allWinOverlays:
        return ['overlay.win.small', 'overlay.win.medium', 'overlay.win.big', 'overlay.win.mega', 'overlay.win.epic'];
      case GroupTargetType.allFeatures:
        return ['feature.freespins', 'feature.bonus', 'feature.holdwin', 'feature.gamble'];
      case GroupTargetType.custom:
        return [];
    }
  }

  static GroupTargetType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'allreels':
      case 'all_reels': return GroupTargetType.allReels;
      case 'allreelstops':
      case 'all_reel_stops': return GroupTargetType.allReelStops;
      case 'alluibuttons':
      case 'all_ui_buttons': return GroupTargetType.allUiButtons;
      case 'allsymbolzones':
      case 'all_symbol_zones': return GroupTargetType.allSymbolZones;
      case 'allwinoverlays':
      case 'all_win_overlays': return GroupTargetType.allWinOverlays;
      case 'allfeatures':
      case 'all_features': return GroupTargetType.allFeatures;
      default: return GroupTargetType.custom;
    }
  }
}

/// Spatial distribution mode for batch drops
enum SpatialDistributionMode {
  /// Left to right linear pan (-1.0 to +1.0)
  linearLeftToRight,
  /// Center outward (0 in center, +/- at edges)
  centerOutward,
  /// All center (no spatial)
  allCenter,
  /// Random within range
  randomWithinRange,
  /// Custom per-target
  custom,
}

extension SpatialDistributionModeExtension on SpatialDistributionMode {
  String get displayName {
    switch (this) {
      case SpatialDistributionMode.linearLeftToRight: return 'Linear L→R';
      case SpatialDistributionMode.centerOutward: return 'Center Outward';
      case SpatialDistributionMode.allCenter: return 'All Center';
      case SpatialDistributionMode.randomWithinRange: return 'Random';
      case SpatialDistributionMode.custom: return 'Custom';
    }
  }

  /// Calculate pan for index in total count
  double calculatePan(int index, int total, {double range = 0.8}) {
    if (total <= 1) return 0.0;

    switch (this) {
      case SpatialDistributionMode.linearLeftToRight:
        // Map 0..total-1 to -range..+range
        return -range + (2 * range * index / (total - 1));

      case SpatialDistributionMode.centerOutward:
        // Center has pan 0, edges have max pan
        final center = (total - 1) / 2;
        final distFromCenter = (index - center).abs();
        final maxDist = center;
        final sign = index < center ? -1.0 : (index > center ? 1.0 : 0.0);
        return sign * (distFromCenter / maxDist) * range;

      case SpatialDistributionMode.allCenter:
        return 0.0;

      case SpatialDistributionMode.randomWithinRange:
        // Generate deterministic "random" based on index
        final seed = index * 7919; // Prime number for spread
        return ((seed % 1000) / 500 - 1) * range;

      case SpatialDistributionMode.custom:
        return 0.0; // Custom handles this externally
    }
  }

  static SpatialDistributionMode fromString(String s) {
    switch (s.toLowerCase()) {
      case 'linearlefttoright':
      case 'linear_left_to_right':
      case 'linear': return SpatialDistributionMode.linearLeftToRight;
      case 'centeroutward':
      case 'center_outward': return SpatialDistributionMode.centerOutward;
      case 'allcenter':
      case 'all_center':
      case 'center': return SpatialDistributionMode.allCenter;
      case 'randomwithinrange':
      case 'random_within_range':
      case 'random': return SpatialDistributionMode.randomWithinRange;
      default: return SpatialDistributionMode.custom;
    }
  }
}

/// Parameter variation mode for batch drops
enum ParameterVariationMode {
  /// Same parameters for all
  identical,
  /// Slight random variation
  slightVariation,
  /// Progressive change (e.g., pitch rise)
  progressive,
  /// Per-target custom
  custom,
}

extension ParameterVariationModeExtension on ParameterVariationMode {
  String get displayName {
    switch (this) {
      case ParameterVariationMode.identical: return 'Identical';
      case ParameterVariationMode.slightVariation: return 'Slight Variation';
      case ParameterVariationMode.progressive: return 'Progressive';
      case ParameterVariationMode.custom: return 'Custom';
    }
  }

  static ParameterVariationMode fromString(String s) {
    switch (s.toLowerCase()) {
      case 'identical': return ParameterVariationMode.identical;
      case 'slightvariation':
      case 'slight_variation':
      case 'variation': return ParameterVariationMode.slightVariation;
      case 'progressive': return ParameterVariationMode.progressive;
      default: return ParameterVariationMode.custom;
    }
  }
}

/// Variation range for a parameter
class ParameterVariationRange {
  final String paramName;
  final double minOffset;
  final double maxOffset;
  final bool isPercentage; // If true, offset is percentage of base value

  const ParameterVariationRange({
    required this.paramName,
    this.minOffset = -0.1,
    this.maxOffset = 0.1,
    this.isPercentage = true,
  });

  /// Calculate variation for index
  double calculateVariation(double baseValue, int index, int total, ParameterVariationMode mode) {
    switch (mode) {
      case ParameterVariationMode.identical:
        return baseValue;

      case ParameterVariationMode.slightVariation:
        // Deterministic pseudo-random variation
        final seed = (index * 7919 + paramName.hashCode) % 1000;
        final t = seed / 1000; // 0..1
        final offset = minOffset + t * (maxOffset - minOffset);
        if (isPercentage) {
          return baseValue * (1 + offset);
        } else {
          return baseValue + offset;
        }

      case ParameterVariationMode.progressive:
        // Linear progression from min to max
        if (total <= 1) return baseValue;
        final t = index / (total - 1);
        final offset = minOffset + t * (maxOffset - minOffset);
        if (isPercentage) {
          return baseValue * (1 + offset);
        } else {
          return baseValue + offset;
        }

      case ParameterVariationMode.custom:
        return baseValue;
    }
  }

  Map<String, dynamic> toJson() => {
    'paramName': paramName,
    'minOffset': minOffset,
    'maxOffset': maxOffset,
    'isPercentage': isPercentage,
  };

  factory ParameterVariationRange.fromJson(Map<String, dynamic> json) => ParameterVariationRange(
    paramName: json['paramName'] as String,
    minOffset: (json['minOffset'] as num?)?.toDouble() ?? -0.1,
    maxOffset: (json['maxOffset'] as num?)?.toDouble() ?? 0.1,
    isPercentage: json['isPercentage'] as bool? ?? true,
  );
}

/// Configuration for batch drop operation
class BatchDropConfig {
  /// Group target type
  final GroupTargetType groupType;

  /// Custom target IDs (when groupType is custom)
  final List<String> customTargetIds;

  /// Spatial distribution mode
  final SpatialDistributionMode spatialMode;

  /// Spatial range (typically 0.0 to 1.0)
  final double spatialRange;

  /// Custom pan values per target (when spatialMode is custom)
  final Map<String, double> customPanValues;

  /// Parameter variation mode
  final ParameterVariationMode variationMode;

  /// Variation ranges for parameters
  final List<ParameterVariationRange> variationRanges;

  /// Timing stagger between events (ms)
  final int staggerMs;

  /// Whether to create dependencies between batch events
  final bool createDependencies;

  /// Dependency type if creating dependencies
  final DependencyType dependencyType;

  /// Preset ID to use for all events
  final String? presetId;

  /// Event ID prefix
  final String eventIdPrefix;

  /// Voice limit group for all events
  final String voiceLimitGroup;

  const BatchDropConfig({
    this.groupType = GroupTargetType.allReels,
    this.customTargetIds = const [],
    this.spatialMode = SpatialDistributionMode.linearLeftToRight,
    this.spatialRange = 0.8,
    this.customPanValues = const {},
    this.variationMode = ParameterVariationMode.identical,
    this.variationRanges = const [],
    this.staggerMs = 0,
    this.createDependencies = false,
    this.dependencyType = DependencyType.after,
    this.presetId,
    this.eventIdPrefix = 'batch',
    this.voiceLimitGroup = 'batch',
  });

  /// Get all target IDs for this config
  List<String> getTargetIds({int reelCount = 5}) {
    if (groupType == GroupTargetType.custom) {
      return customTargetIds;
    }
    return groupType.getTargetIds(reelCount: reelCount);
  }

  /// Get pan value for target at index
  double getPanForIndex(int index, int total) {
    return spatialMode.calculatePan(index, total, range: spatialRange);
  }

  /// Get pan value for specific target
  double? getPanForTarget(String targetId) {
    return customPanValues[targetId];
  }

  BatchDropConfig copyWith({
    GroupTargetType? groupType,
    List<String>? customTargetIds,
    SpatialDistributionMode? spatialMode,
    double? spatialRange,
    Map<String, double>? customPanValues,
    ParameterVariationMode? variationMode,
    List<ParameterVariationRange>? variationRanges,
    int? staggerMs,
    bool? createDependencies,
    DependencyType? dependencyType,
    String? presetId,
    String? eventIdPrefix,
    String? voiceLimitGroup,
  }) {
    return BatchDropConfig(
      groupType: groupType ?? this.groupType,
      customTargetIds: customTargetIds ?? this.customTargetIds,
      spatialMode: spatialMode ?? this.spatialMode,
      spatialRange: spatialRange ?? this.spatialRange,
      customPanValues: customPanValues ?? this.customPanValues,
      variationMode: variationMode ?? this.variationMode,
      variationRanges: variationRanges ?? this.variationRanges,
      staggerMs: staggerMs ?? this.staggerMs,
      createDependencies: createDependencies ?? this.createDependencies,
      dependencyType: dependencyType ?? this.dependencyType,
      presetId: presetId ?? this.presetId,
      eventIdPrefix: eventIdPrefix ?? this.eventIdPrefix,
      voiceLimitGroup: voiceLimitGroup ?? this.voiceLimitGroup,
    );
  }

  Map<String, dynamic> toJson() => {
    'groupType': groupType.name,
    'customTargetIds': customTargetIds,
    'spatialMode': spatialMode.name,
    'spatialRange': spatialRange,
    'customPanValues': customPanValues,
    'variationMode': variationMode.name,
    'variationRanges': variationRanges.map((r) => r.toJson()).toList(),
    'staggerMs': staggerMs,
    'createDependencies': createDependencies,
    'dependencyType': dependencyType.name,
    if (presetId != null) 'presetId': presetId,
    'eventIdPrefix': eventIdPrefix,
    'voiceLimitGroup': voiceLimitGroup,
  };

  factory BatchDropConfig.fromJson(Map<String, dynamic> json) => BatchDropConfig(
    groupType: GroupTargetTypeExtension.fromString(json['groupType'] as String? ?? 'allReels'),
    customTargetIds: (json['customTargetIds'] as List<dynamic>?)?.cast<String>() ?? [],
    spatialMode: SpatialDistributionModeExtension.fromString(json['spatialMode'] as String? ?? 'linearLeftToRight'),
    spatialRange: (json['spatialRange'] as num?)?.toDouble() ?? 0.8,
    customPanValues: (json['customPanValues'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {},
    variationMode: ParameterVariationModeExtension.fromString(json['variationMode'] as String? ?? 'identical'),
    variationRanges: (json['variationRanges'] as List<dynamic>?)
        ?.map((r) => ParameterVariationRange.fromJson(r as Map<String, dynamic>))
        .toList() ?? [],
    staggerMs: json['staggerMs'] as int? ?? 0,
    createDependencies: json['createDependencies'] as bool? ?? false,
    dependencyType: DependencyTypeExtension.fromString(json['dependencyType'] as String? ?? 'after'),
    presetId: json['presetId'] as String?,
    eventIdPrefix: json['eventIdPrefix'] as String? ?? 'batch',
    voiceLimitGroup: json['voiceLimitGroup'] as String? ?? 'batch',
  );

  /// Preset configs for common scenarios
  static const reelStopsConfig = BatchDropConfig(
    groupType: GroupTargetType.allReels,
    spatialMode: SpatialDistributionMode.linearLeftToRight,
    spatialRange: 0.8,
    variationMode: ParameterVariationMode.slightVariation,
    variationRanges: [
      ParameterVariationRange(paramName: 'pitch', minOffset: -0.05, maxOffset: 0.05),
    ],
    staggerMs: 100,
    createDependencies: true,
    dependencyType: DependencyType.after,
    eventIdPrefix: 'reel_stop',
    voiceLimitGroup: 'reels',
  );

  static const cascadeConfig = BatchDropConfig(
    groupType: GroupTargetType.allReels,
    spatialMode: SpatialDistributionMode.linearLeftToRight,
    spatialRange: 0.6,
    variationMode: ParameterVariationMode.progressive,
    variationRanges: [
      ParameterVariationRange(paramName: 'pitch', minOffset: 0.0, maxOffset: 0.2),
      ParameterVariationRange(paramName: 'volume', minOffset: 0.0, maxOffset: 3.0, isPercentage: false),
    ],
    staggerMs: 50,
    eventIdPrefix: 'cascade',
    voiceLimitGroup: 'cascade',
  );

  static const winTiersConfig = BatchDropConfig(
    groupType: GroupTargetType.allWinOverlays,
    spatialMode: SpatialDistributionMode.allCenter,
    variationMode: ParameterVariationMode.progressive,
    variationRanges: [
      ParameterVariationRange(paramName: 'volume', minOffset: 0.0, maxOffset: 6.0, isPercentage: false),
      ParameterVariationRange(paramName: 'priority', minOffset: 0.0, maxOffset: 40.0, isPercentage: false),
    ],
    eventIdPrefix: 'win',
    voiceLimitGroup: 'wins',
  );
}

/// Result of a batch drop operation
/// Note: Uses String IDs instead of direct type references to avoid circular dependencies
class BatchDropResult {
  /// Created event IDs
  final List<String> eventIds;

  /// Created binding IDs (format: "eventId_targetId")
  final List<String> bindingIds;

  /// Any errors during creation
  final List<String> errors;

  /// Total count
  int get count => eventIds.length;

  /// Whether all succeeded
  bool get allSucceeded => errors.isEmpty;

  const BatchDropResult({
    required this.eventIds,
    required this.bindingIds,
    this.errors = const [],
  });

  /// Empty result
  static const empty = BatchDropResult(eventIds: [], bindingIds: []);
}

// =============================================================================
// BINDING GRAPH (D.6)
// =============================================================================

/// Node type in binding graph
enum GraphNodeType {
  event,
  target,
  preset,
  bus,
  rtpc,
  condition,
}

extension GraphNodeTypeExtension on GraphNodeType {
  String get displayName {
    switch (this) {
      case GraphNodeType.event: return 'Event';
      case GraphNodeType.target: return 'Target';
      case GraphNodeType.preset: return 'Preset';
      case GraphNodeType.bus: return 'Bus';
      case GraphNodeType.rtpc: return 'RTPC';
      case GraphNodeType.condition: return 'Condition';
    }
  }

  static GraphNodeType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'event': return GraphNodeType.event;
      case 'target': return GraphNodeType.target;
      case 'preset': return GraphNodeType.preset;
      case 'bus': return GraphNodeType.bus;
      case 'rtpc': return GraphNodeType.rtpc;
      case 'condition': return GraphNodeType.condition;
      default: return GraphNodeType.event;
    }
  }
}

/// Edge type in binding graph
enum GraphEdgeType {
  /// Event → Target binding
  binding,
  /// Event → Event dependency
  dependency,
  /// Event → Preset usage
  usesPreset,
  /// Event → Bus routing
  routesToBus,
  /// RTPC → Event parameter
  rtpcBinding,
  /// Condition → Event trigger
  conditionalTrigger,
  /// Preset → Preset inheritance
  inherits,
}

extension GraphEdgeTypeExtension on GraphEdgeType {
  String get displayName {
    switch (this) {
      case GraphEdgeType.binding: return 'Binds To';
      case GraphEdgeType.dependency: return 'Depends On';
      case GraphEdgeType.usesPreset: return 'Uses Preset';
      case GraphEdgeType.routesToBus: return 'Routes To';
      case GraphEdgeType.rtpcBinding: return 'RTPC Controls';
      case GraphEdgeType.conditionalTrigger: return 'Triggers When';
      case GraphEdgeType.inherits: return 'Extends';
    }
  }

  String get lineStyle {
    switch (this) {
      case GraphEdgeType.binding: return 'solid';
      case GraphEdgeType.dependency: return 'dashed';
      case GraphEdgeType.usesPreset: return 'dotted';
      case GraphEdgeType.routesToBus: return 'solid';
      case GraphEdgeType.rtpcBinding: return 'dashed';
      case GraphEdgeType.conditionalTrigger: return 'dotted';
      case GraphEdgeType.inherits: return 'solid';
    }
  }

  static GraphEdgeType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'binding': return GraphEdgeType.binding;
      case 'dependency': return GraphEdgeType.dependency;
      case 'usespreset':
      case 'uses_preset': return GraphEdgeType.usesPreset;
      case 'routestobus':
      case 'routes_to_bus': return GraphEdgeType.routesToBus;
      case 'rtpcbinding':
      case 'rtpc_binding': return GraphEdgeType.rtpcBinding;
      case 'conditionaltrigger':
      case 'conditional_trigger': return GraphEdgeType.conditionalTrigger;
      case 'inherits': return GraphEdgeType.inherits;
      default: return GraphEdgeType.binding;
    }
  }
}

/// A node in the binding graph
class GraphNode {
  /// Unique node ID
  final String nodeId;

  /// Node type
  final GraphNodeType nodeType;

  /// Display label
  final String label;

  /// Subtitle (optional detail)
  final String? subtitle;

  /// Node metadata (e.g., full event/preset data)
  final Map<String, dynamic> metadata;

  /// Position (for layout, 0-1 normalized)
  double x;
  double y;

  /// Whether node is selected
  bool isSelected;

  /// Whether node is highlighted (e.g., by search)
  bool isHighlighted;

  /// Whether node is collapsed (for grouped nodes)
  bool isCollapsed;

  GraphNode({
    required this.nodeId,
    required this.nodeType,
    required this.label,
    this.subtitle,
    this.metadata = const {},
    this.x = 0.5,
    this.y = 0.5,
    this.isSelected = false,
    this.isHighlighted = false,
    this.isCollapsed = false,
  });

  GraphNode copyWith({
    String? nodeId,
    GraphNodeType? nodeType,
    String? label,
    String? subtitle,
    Map<String, dynamic>? metadata,
    double? x,
    double? y,
    bool? isSelected,
    bool? isHighlighted,
    bool? isCollapsed,
  }) {
    return GraphNode(
      nodeId: nodeId ?? this.nodeId,
      nodeType: nodeType ?? this.nodeType,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      metadata: metadata ?? this.metadata,
      x: x ?? this.x,
      y: y ?? this.y,
      isSelected: isSelected ?? this.isSelected,
      isHighlighted: isHighlighted ?? this.isHighlighted,
      isCollapsed: isCollapsed ?? this.isCollapsed,
    );
  }

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'nodeType': nodeType.name,
    'label': label,
    if (subtitle != null) 'subtitle': subtitle,
    'metadata': metadata,
    'x': x,
    'y': y,
  };

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
    nodeId: json['nodeId'] as String,
    nodeType: GraphNodeTypeExtension.fromString(json['nodeType'] as String? ?? 'event'),
    label: json['label'] as String,
    subtitle: json['subtitle'] as String?,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
  );

  /// Create event node from metadata
  factory GraphNode.forEvent({
    required String eventId,
    String? intent,
    String? bus,
    String? presetId,
  }) => GraphNode(
    nodeId: 'event_$eventId',
    nodeType: GraphNodeType.event,
    label: eventId,
    subtitle: intent,
    metadata: {
      'eventId': eventId,
      if (bus != null) 'bus': bus,
      if (presetId != null) 'presetId': presetId,
    },
  );

  /// Create target node
  factory GraphNode.fromTarget(String targetId, {String? displayName}) => GraphNode(
    nodeId: 'target_$targetId',
    nodeType: GraphNodeType.target,
    label: displayName ?? targetId,
    metadata: {'targetId': targetId},
  );

  /// Create preset node
  factory GraphNode.fromPreset(EventPreset preset) => GraphNode(
    nodeId: 'preset_${preset.presetId}',
    nodeType: GraphNodeType.preset,
    label: preset.name,
    subtitle: preset.description,
    metadata: {'presetId': preset.presetId},
  );

  /// Create bus node
  factory GraphNode.fromBus(String busPath) => GraphNode(
    nodeId: 'bus_$busPath',
    nodeType: GraphNodeType.bus,
    label: busPath,
    metadata: {'busPath': busPath},
  );

  /// Create RTPC node
  factory GraphNode.fromRtpc(String rtpcName) => GraphNode(
    nodeId: 'rtpc_$rtpcName',
    nodeType: GraphNodeType.rtpc,
    label: rtpcName,
    metadata: {'rtpcName': rtpcName},
  );
}

/// An edge in the binding graph
class GraphEdge {
  /// Source node ID
  final String sourceId;

  /// Target node ID
  final String targetId;

  /// Edge type
  final GraphEdgeType edgeType;

  /// Edge label (optional)
  final String? label;

  /// Edge metadata
  final Map<String, dynamic> metadata;

  /// Whether edge is highlighted
  final bool isHighlighted;

  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.edgeType,
    this.label,
    this.metadata = const {},
    this.isHighlighted = false,
  });

  /// Create copy with highlight toggled
  GraphEdge copyWith({bool? isHighlighted}) => GraphEdge(
    sourceId: sourceId,
    targetId: targetId,
    edgeType: edgeType,
    label: label,
    metadata: metadata,
    isHighlighted: isHighlighted ?? this.isHighlighted,
  );

  /// Unique edge ID
  String get edgeId => '${sourceId}_${edgeType.name}_$targetId';

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'targetId': targetId,
    'edgeType': edgeType.name,
    if (label != null) 'label': label,
    'metadata': metadata,
  };

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
    sourceId: json['sourceId'] as String,
    targetId: json['targetId'] as String,
    edgeType: GraphEdgeTypeExtension.fromString(json['edgeType'] as String? ?? 'binding'),
    label: json['label'] as String?,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
  );
}

/// Complete binding graph
class BindingGraph {
  /// All nodes
  final List<GraphNode> nodes;

  /// All edges
  final List<GraphEdge> edges;

  /// Graph metadata
  final Map<String, dynamic> metadata;

  const BindingGraph({
    this.nodes = const [],
    this.edges = const [],
    this.metadata = const {},
  });

  /// Get node by ID
  GraphNode? getNode(String nodeId) {
    try {
      return nodes.firstWhere((n) => n.nodeId == nodeId);
    } catch (_) {
      return null;
    }
  }

  /// Get edges from a node
  List<GraphEdge> getOutgoingEdges(String nodeId) {
    return edges.where((e) => e.sourceId == nodeId).toList();
  }

  /// Get edges to a node
  List<GraphEdge> getIncomingEdges(String nodeId) {
    return edges.where((e) => e.targetId == nodeId).toList();
  }

  /// Get connected nodes (either direction)
  List<GraphNode> getConnectedNodes(String nodeId) {
    final connectedIds = <String>{};

    for (final edge in edges) {
      if (edge.sourceId == nodeId) connectedIds.add(edge.targetId);
      if (edge.targetId == nodeId) connectedIds.add(edge.sourceId);
    }

    return nodes.where((n) => connectedIds.contains(n.nodeId)).toList();
  }

  /// Get nodes by type
  List<GraphNode> getNodesByType(GraphNodeType type) {
    return nodes.where((n) => n.nodeType == type).toList();
  }

  /// Get edges by type
  List<GraphEdge> getEdgesByType(GraphEdgeType type) {
    return edges.where((e) => e.edgeType == type).toList();
  }

  /// Search nodes by label
  List<GraphNode> searchNodes(String query) {
    final lowerQuery = query.toLowerCase();
    return nodes.where((n) =>
      n.label.toLowerCase().contains(lowerQuery) ||
      (n.subtitle?.toLowerCase().contains(lowerQuery) ?? false)
    ).toList();
  }

  /// Get statistics
  Map<String, int> getStatistics() {
    return {
      'totalNodes': nodes.length,
      'eventNodes': getNodesByType(GraphNodeType.event).length,
      'targetNodes': getNodesByType(GraphNodeType.target).length,
      'presetNodes': getNodesByType(GraphNodeType.preset).length,
      'busNodes': getNodesByType(GraphNodeType.bus).length,
      'totalEdges': edges.length,
      'bindingEdges': getEdgesByType(GraphEdgeType.binding).length,
      'dependencyEdges': getEdgesByType(GraphEdgeType.dependency).length,
    };
  }

  Map<String, dynamic> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'metadata': metadata,
  };

  factory BindingGraph.fromJson(Map<String, dynamic> json) => BindingGraph(
    nodes: (json['nodes'] as List<dynamic>?)
        ?.map((n) => GraphNode.fromJson(n as Map<String, dynamic>))
        .toList() ?? [],
    edges: (json['edges'] as List<dynamic>?)
        ?.map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
  );
}

/// Builder for creating binding graphs from provider data
class BindingGraphBuilder {
  final List<GraphNode> _nodes = [];
  final List<GraphEdge> _edges = [];
  final Set<String> _nodeIds = {};
  final Set<String> _edgeIds = {};

  /// Add node (deduped)
  void addNode(GraphNode node) {
    if (!_nodeIds.contains(node.nodeId)) {
      _nodes.add(node);
      _nodeIds.add(node.nodeId);
    }
  }

  /// Add edge (deduped)
  void addEdge(GraphEdge edge) {
    if (!_edgeIds.contains(edge.edgeId)) {
      _edges.add(edge);
      _edgeIds.add(edge.edgeId);
    }
  }

  /// Build from event and binding data (uses Maps to avoid circular dependency)
  ///
  /// Event map keys: eventId, intent, bus, presetId, dependencies, rtpcBindings, conditionalTrigger
  /// Binding map keys: bindingId, eventId, targetId, stageId, trigger, enabled
  void addEventsFromMaps(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> bindings,
  ) {
    // Add event nodes
    for (final event in events) {
      final eventId = event['eventId'] as String;
      final intent = event['intent'] as String?;
      final bus = event['bus'] as String;
      final presetId = event['presetId'] as String?;

      // Add event node
      addNode(GraphNode.forEvent(
        eventId: eventId,
        intent: intent,
        bus: bus,
        presetId: presetId,
      ));

      // Add bus node and edge
      addNode(GraphNode.fromBus(bus));
      addEdge(GraphEdge(
        sourceId: 'event_$eventId',
        targetId: 'bus_$bus',
        edgeType: GraphEdgeType.routesToBus,
      ));

      // Add preset node and edge
      if (presetId != null) {
        addNode(GraphNode(
          nodeId: 'preset_$presetId',
          nodeType: GraphNodeType.preset,
          label: presetId,
        ));
        addEdge(GraphEdge(
          sourceId: 'event_$eventId',
          targetId: 'preset_$presetId',
          edgeType: GraphEdgeType.usesPreset,
        ));
      }

      // Add dependency edges
      final dependencies = event['dependencies'] as List<Map<String, dynamic>>? ?? [];
      for (final dep in dependencies) {
        final targetEventId = dep['targetEventId'] as String;
        final depType = dep['type'] as String? ?? 'afterComplete';
        final delayMs = dep['delayMs'] as int? ?? 0;
        final required = dep['required'] as bool? ?? true;

        addEdge(GraphEdge(
          sourceId: 'event_$eventId',
          targetId: 'event_$targetEventId',
          edgeType: GraphEdgeType.dependency,
          label: depType,
          metadata: {'delayMs': delayMs, 'required': required},
        ));
      }

      // Add RTPC binding edges
      final rtpcBindings = event['rtpcBindings'] as List<Map<String, dynamic>>? ?? [];
      for (final rtpc in rtpcBindings) {
        final rtpcName = rtpc['rtpcName'] as String;
        final eventParam = rtpc['eventParam'] as String;

        addNode(GraphNode.fromRtpc(rtpcName));
        addEdge(GraphEdge(
          sourceId: 'rtpc_$rtpcName',
          targetId: 'event_$eventId',
          edgeType: GraphEdgeType.rtpcBinding,
          label: eventParam,
        ));
      }

      // Add conditional trigger node
      final conditionalTrigger = event['conditionalTrigger'] as Map<String, dynamic>?;
      if (conditionalTrigger != null) {
        final triggerName = conditionalTrigger['name'] as String? ?? 'Condition';
        final conditions = conditionalTrigger['conditions'] as List? ?? [];
        final logic = conditionalTrigger['logic'] as String? ?? 'and';

        final condNode = GraphNode(
          nodeId: 'condition_$eventId',
          nodeType: GraphNodeType.condition,
          label: triggerName,
          subtitle: '${conditions.length} conditions',
          metadata: {'logic': logic},
        );
        addNode(condNode);
        addEdge(GraphEdge(
          sourceId: 'condition_$eventId',
          targetId: 'event_$eventId',
          edgeType: GraphEdgeType.conditionalTrigger,
        ));
      }
    }

    // Add binding edges
    for (final binding in bindings) {
      final eventId = binding['eventId'] as String;
      final targetId = binding['targetId'] as String;
      final stageId = binding['stageId'] as String? ?? 'global';
      final trigger = binding['trigger'] as String? ?? 'press';
      final enabled = binding['enabled'] as bool? ?? true;

      // Add target node
      addNode(GraphNode.fromTarget(targetId));

      // Add binding edge
      addEdge(GraphEdge(
        sourceId: 'event_$eventId',
        targetId: 'target_$targetId',
        edgeType: GraphEdgeType.binding,
        label: trigger,
        metadata: {'stageId': stageId, 'enabled': enabled},
      ));
    }
  }

  /// Add preset inheritance edges
  void addPresetInheritance(PresetInheritanceResolver resolver) {
    for (final preset in resolver.allPresets) {
      addNode(GraphNode(
        nodeId: 'preset_${preset.presetId}',
        nodeType: GraphNodeType.preset,
        label: preset.name,
        subtitle: preset.category,
        metadata: {'isSealed': preset.isSealed, 'isAbstract': preset.isAbstract},
      ));

      if (preset.extendsPresetId != null) {
        addEdge(GraphEdge(
          sourceId: 'preset_${preset.presetId}',
          targetId: 'preset_${preset.extendsPresetId}',
          edgeType: GraphEdgeType.inherits,
        ));
      }
    }
  }

  /// Build final graph
  BindingGraph build() {
    return BindingGraph(
      nodes: List.unmodifiable(_nodes),
      edges: List.unmodifiable(_edges),
      metadata: {
        'builtAt': DateTime.now().toIso8601String(),
        'nodeCount': _nodes.length,
        'edgeCount': _edges.length,
      },
    );
  }

  /// Clear builder
  void clear() {
    _nodes.clear();
    _edges.clear();
    _nodeIds.clear();
    _edgeIds.clear();
  }
}

/// Layout algorithm for binding graph
enum GraphLayoutAlgorithm {
  /// Force-directed layout (spring physics)
  forceDirected,
  /// Hierarchical layout (tree-like)
  hierarchical,
  /// Circular layout
  circular,
  /// Grid layout
  grid,
}

/// Graph layout options
class GraphLayoutOptions {
  final GraphLayoutAlgorithm algorithm;
  final double padding;
  final double nodeSpacing;
  final double layerSpacing;
  final bool centerRoot;

  const GraphLayoutOptions({
    this.algorithm = GraphLayoutAlgorithm.hierarchical,
    this.padding = 50.0,
    this.nodeSpacing = 100.0,
    this.layerSpacing = 150.0,
    this.centerRoot = true,
  });
}

/// Simple graph layout calculator
class GraphLayoutCalculator {
  /// Apply hierarchical layout to graph
  static void applyHierarchicalLayout(BindingGraph graph, GraphLayoutOptions options) {
    final nodes = graph.nodes;
    final edges = graph.edges;

    if (nodes.isEmpty) return;

    // Find root nodes (no incoming edges)
    final hasIncoming = <String>{};
    for (final edge in edges) {
      hasIncoming.add(edge.targetId);
    }
    final roots = nodes.where((n) => !hasIncoming.contains(n.nodeId)).toList();

    // Assign layers via BFS
    final layers = <int, List<GraphNode>>{};
    final nodeLayer = <String, int>{};

    void assignLayer(GraphNode node, int layer) {
      if (nodeLayer.containsKey(node.nodeId)) {
        // Already assigned, take max layer
        if (layer > nodeLayer[node.nodeId]!) {
          nodeLayer[node.nodeId] = layer;
        }
        return;
      }
      nodeLayer[node.nodeId] = layer;
      layers.putIfAbsent(layer, () => []).add(node);

      // Process children
      for (final edge in edges.where((e) => e.sourceId == node.nodeId)) {
        final child = nodes.firstWhere(
          (n) => n.nodeId == edge.targetId,
          orElse: () => node,
        );
        assignLayer(child, layer + 1);
      }
    }

    // Start from roots
    for (final root in roots) {
      assignLayer(root, 0);
    }

    // Handle orphans (nodes not reachable from roots)
    for (final node in nodes) {
      if (!nodeLayer.containsKey(node.nodeId)) {
        final maxLayer = layers.keys.fold(0, (max, l) => l > max ? l : max);
        assignLayer(node, maxLayer + 1);
      }
    }

    // Position nodes
    final totalLayers = layers.length;
    for (final entry in layers.entries) {
      final layer = entry.key;
      final layerNodes = entry.value;
      final y = (layer + 0.5) / totalLayers; // Normalize to 0-1

      for (var i = 0; i < layerNodes.length; i++) {
        final x = (i + 0.5) / layerNodes.length; // Normalize to 0-1
        layerNodes[i].x = x;
        layerNodes[i].y = y;
      }
    }
  }

  /// Apply circular layout to graph
  static void applyCircularLayout(BindingGraph graph) {
    final nodes = graph.nodes;
    if (nodes.isEmpty) return;

    final count = nodes.length;
    for (var i = 0; i < count; i++) {
      final angle = 2 * math.pi * i / count - math.pi / 2; // Start at top
      nodes[i].x = 0.5 + 0.4 * math.cos(angle);
      nodes[i].y = 0.5 + 0.4 * math.sin(angle);
    }
  }

  /// Apply grid layout to graph
  static void applyGridLayout(BindingGraph graph) {
    final nodes = graph.nodes;
    if (nodes.isEmpty) return;

    final cols = math.sqrt(nodes.length).ceil();
    final rows = (nodes.length / cols).ceil();

    for (var i = 0; i < nodes.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      nodes[i].x = (col + 0.5) / cols;
      nodes[i].y = (row + 0.5) / rows;
    }
  }
}

// =============================================================================
// STANDARD PRESETS
// =============================================================================

/// Built-in presets for common event types
class StandardPresets {
  static const uiClickPrimary = EventPreset(
    presetId: 'ui_click_primary',
    name: 'UI Click (Primary)',
    description: 'Main button clicks',
    volume: 0.0,
    cooldownMs: 50,
    polyphony: 2,
    voiceLimitGroup: 'ui',
    priority: 60,
  );

  static const uiClickSecondary = EventPreset(
    presetId: 'ui_click_secondary',
    name: 'UI Click (Secondary)',
    description: 'Secondary button clicks',
    volume: -3.0,
    cooldownMs: 30,
    polyphony: 2,
    voiceLimitGroup: 'ui',
    priority: 50,
  );

  static const uiHover = EventPreset(
    presetId: 'ui_hover',
    name: 'UI Hover',
    description: 'Hover feedback',
    volume: -6.0,
    cooldownMs: 100,
    polyphony: 1,
    voiceLimitGroup: 'ui',
    priority: 40,
  );

  static const reelSpin = EventPreset(
    presetId: 'reel_spin',
    name: 'Reel Spin',
    description: 'Reel spinning loop',
    volume: -3.0,
    fadeInMs: 50,
    fadeOutMs: 100,
    polyphony: 1,
    voiceLimitGroup: 'reels',
    priority: 70,
  );

  static const reelStop = EventPreset(
    presetId: 'reel_stop',
    name: 'Reel Stop',
    description: 'Reel stop impact',
    volume: 0.0,
    cooldownMs: 50,
    polyphony: 5,
    voiceLimitGroup: 'reels',
    priority: 75,
  );

  static const anticipation = EventPreset(
    presetId: 'anticipation',
    name: 'Anticipation',
    description: 'Near-win tension',
    volume: -3.0,
    fadeInMs: 200,
    fadeOutMs: 500,
    polyphony: 1,
    voiceLimitGroup: 'anticipation',
    priority: 80,
  );

  static const winSmall = EventPreset(
    presetId: 'win_small',
    name: 'Small Win',
    description: 'Minor win celebration',
    volume: 0.0,
    cooldownMs: 100,
    polyphony: 2,
    voiceLimitGroup: 'wins',
    priority: 60,
  );

  static const winBig = EventPreset(
    presetId: 'win_big',
    name: 'Big Win',
    description: 'Major win celebration',
    volume: 3.0,
    cooldownMs: 500,
    polyphony: 1,
    voiceLimitGroup: 'wins',
    priority: 90,
  );

  static const bigwinTier = EventPreset(
    presetId: 'bigwin_tier',
    name: 'Big Win Tier',
    description: 'Tier escalation sounds',
    volume: 0.0,
    cooldownMs: 1000,
    polyphony: 1,
    voiceLimitGroup: 'wins',
    priority: 95,
  );

  static const jackpot = EventPreset(
    presetId: 'jackpot',
    name: 'Jackpot',
    description: 'Jackpot win',
    volume: 6.0,
    cooldownMs: 2000,
    polyphony: 1,
    voiceLimitGroup: 'jackpot',
    priority: 100,
  );

  static const musicBase = EventPreset(
    presetId: 'music_base',
    name: 'Base Music',
    description: 'Background music loop',
    volume: -6.0,
    fadeInMs: 500,
    fadeOutMs: 1000,
    polyphony: 1,
    voiceLimitGroup: 'music',
    priority: 30,
    preloadPolicy: PreloadPolicy.onCommit,
  );

  static const musicFeature = EventPreset(
    presetId: 'music_feature',
    name: 'Feature Music',
    description: 'Feature/bonus music',
    volume: -3.0,
    fadeInMs: 500,
    fadeOutMs: 1000,
    polyphony: 1,
    voiceLimitGroup: 'music',
    priority: 40,
    preloadPolicy: PreloadPolicy.onStageEnter,
  );

  // ==========================================================================
  // V9: Symbol and Win Line Presets
  // ==========================================================================

  static const symbolLand = EventPreset(
    presetId: 'symbol_land',
    name: 'Symbol Land',
    description: 'Symbol landing on reel',
    volume: -3.0,
    cooldownMs: 30,
    polyphony: 5,
    voiceLimitGroup: 'symbols',
    priority: 65,
  );

  static const winLine = EventPreset(
    presetId: 'win_line',
    name: 'Win Line',
    description: 'Win line presentation sound',
    volume: 0.0,
    cooldownMs: 100,
    polyphony: 3,
    voiceLimitGroup: 'wins',
    priority: 55,
  );

  /// All standard presets
  static const List<EventPreset> all = [
    uiClickPrimary,
    uiClickSecondary,
    uiHover,
    reelSpin,
    reelStop,
    anticipation,
    winSmall,
    winBig,
    bigwinTier,
    jackpot,
    musicBase,
    musicFeature,
    // V9: Symbol and Win Line presets
    symbolLand,
    winLine,
  ];

  /// Get preset by ID
  static EventPreset? getById(String presetId) {
    try {
      return all.firstWhere((p) => p.presetId == presetId);
    } catch (_) {
      return null;
    }
  }
}

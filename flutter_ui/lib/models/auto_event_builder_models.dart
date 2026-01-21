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
  overlay,          // Win overlays, popups
  featureContainer, // Feature UI containers
  screenZone,       // General screen areas
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
      case TargetType.overlay: return 'Overlay';
      case TargetType.featureContainer: return 'Feature Container';
      case TargetType.screenZone: return 'Screen Zone';
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
      case TargetType.overlay:
        return ['show', 'hide', 'pulse'];
      case TargetType.featureContainer:
        return ['enter', 'exit', 'step'];
      case TargetType.screenZone:
        return ['activate', 'deactivate'];
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
      case 'overlay': return TargetType.overlay;
      case 'feature_container': return TargetType.featureContainer;
      case 'screen_zone': return TargetType.screenZone;
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

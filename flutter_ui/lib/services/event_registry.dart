/// FluxForge Event Registry — Centralni Audio Event System
///
/// Wwise/FMOD-style arhitektura:
/// - Event je DEFINICIJA (layers, timing, parameters)
/// - Stage je TRIGGER (kada se pušta)
/// - Registry POVEZUJE stage → event
///
/// Prednosti:
/// - Jedan event može biti triggerovan iz više izvora
/// - Timeline editor samo definiše zvuk
/// - Game engine šalje samo stage name
/// - Hot-reload audio bez restarta
///
/// Audio playback koristi Rust engine preko FFI (unified audio stack)
///
/// AudioPool Integration:
/// - Rapid-fire events (CASCADE_STEP, ROLLUP_TICK) use voice pooling
/// - Pool hit = instant playback, Pool miss = new voice allocation
/// - Configurable via AudioPoolConfig for different scenarios

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../spatial/auto_spatial.dart';
import '../src/rust/native_ffi.dart';
import 'audio_playback_service.dart';
import 'audio_pool.dart';
import 'ducking_service.dart';
import 'rtpc_modulation_service.dart';
import 'unified_playback_controller.dart';

// =============================================================================
// AUDIO LAYER — Pojedinačni zvuk u eventu
// =============================================================================

class AudioLayer {
  final String id;
  final String audioPath;
  final String name;
  final double volume;
  final double pan;
  final double delay; // Delay pre početka (ms)
  final double offset; // Offset unutar timeline-a (seconds)
  final int busId;

  const AudioLayer({
    required this.id,
    required this.audioPath,
    required this.name,
    this.volume = 1.0,
    this.pan = 0.0,
    this.delay = 0.0,
    this.offset = 0.0,
    this.busId = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'name': name,
    'volume': volume,
    'pan': pan,
    'delay': delay,
    'offset': offset,
    'busId': busId,
  };

  factory AudioLayer.fromJson(Map<String, dynamic> json) => AudioLayer(
    id: json['id'] as String,
    audioPath: json['audioPath'] as String,
    name: json['name'] as String,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    delay: (json['delay'] as num?)?.toDouble() ?? 0.0,
    offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
    busId: json['busId'] as int? ?? 0,
  );
}

// =============================================================================
// AUDIO EVENT — Kompletna definicija zvučnog eventa
// =============================================================================

class AudioEvent {
  final String id;
  final String name;
  final String stage; // Koji stage trigeruje ovaj event
  final List<AudioLayer> layers;
  final double duration; // Ukupno trajanje eventa (seconds)
  final bool loop;
  final int priority; // Viši priority prekida niži

  const AudioEvent({
    required this.id,
    required this.name,
    required this.stage,
    required this.layers,
    this.duration = 0.0,
    this.loop = false,
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'stage': stage,
    'layers': layers.map((l) => l.toJson()).toList(),
    'duration': duration,
    'loop': loop,
    'priority': priority,
  };

  factory AudioEvent.fromJson(Map<String, dynamic> json) => AudioEvent(
    id: json['id'] as String,
    name: json['name'] as String,
    stage: json['stage'] as String,
    layers: (json['layers'] as List<dynamic>)
        .map((l) => AudioLayer.fromJson(l as Map<String, dynamic>))
        .toList(),
    duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
    loop: json['loop'] as bool? ?? false,
    priority: json['priority'] as int? ?? 0,
  );
}

// =============================================================================
// PLAYING INSTANCE — Aktivna instanca eventa (using Rust engine)
// =============================================================================

class _PlayingInstance {
  final String eventId;
  final List<int> voiceIds; // Rust voice IDs from PlaybackEngine one-shots
  final DateTime startTime;

  _PlayingInstance({
    required this.eventId,
    required this.voiceIds,
    required this.startTime,
  });

  Future<void> stop() async {
    try {
      // Stop each voice individually through bus routing
      for (final voiceId in voiceIds) {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      }
    } catch (e) {
      debugPrint('[EventRegistry] Stop error: $e');
    }
  }
}

// =============================================================================
// EVENT REGISTRY — Centralni sistem
// =============================================================================

/// Events that benefit from voice pooling (rapid-fire playback)
/// These are short, frequently triggered sounds that need instant response
const _pooledEventStages = {
  // Reel stops (core gameplay)
  'REEL_STOP',
  'REEL_STOP_0',
  'REEL_STOP_1',
  'REEL_STOP_2',
  'REEL_STOP_3',
  'REEL_STOP_4',
  'REEL_STOP_5',
  'REEL_STOP_SOFT',
  'REEL_QUICK_STOP',
  'REEL_STOP_TICK',
  // Cascade/Tumble (rapid sequence)
  'CASCADE_STEP',
  'CASCADE_SYMBOL_POP',
  'CASCADE_SYMBOL_POP_0',
  'CASCADE_SYMBOLS_FALL',
  'CASCADE_SYMBOLS_LAND',
  'TUMBLE_DROP',
  'TUMBLE_LAND',
  // Rollup counter (very rapid)
  'ROLLUP_TICK',
  'ROLLUP_TICK_SLOW',
  'ROLLUP_TICK_FAST',
  // Win evaluation (rapid highlighting)
  'WIN_LINE_SHOW',
  'WIN_LINE_FLASH',
  'WIN_LINE_TRACE',
  'WIN_SYMBOL_HIGHLIGHT',
  'WIN_CLUSTER_HIGHLIGHT',
  // UI clicks (instant response needed)
  'UI_BUTTON_PRESS',
  'UI_BUTTON_HOVER',
  'UI_BET_UP',
  'UI_BET_DOWN',
  'UI_TAB_SWITCH',
  // Symbol lands (rapid sequence during stop)
  'SYMBOL_LAND',
  'SYMBOL_LAND_LOW',
  'SYMBOL_LAND_MID',
  'SYMBOL_LAND_HIGH',
  // Wheel ticks
  'WHEEL_TICK',
  'WHEEL_TICK_FAST',
  'WHEEL_TICK_SLOW',
  // Trail steps
  'TRAIL_MOVE_STEP',
  // Hold & Spin
  'HOLD_RESPIN_STOP',
  // Progressive meter
  'PROGRESSIVE_TICK',
  'PROGRESSIVE_CONTRIBUTION',
};

class EventRegistry extends ChangeNotifier {
  // Stage → Event mapping
  final Map<String, AudioEvent> _stageToEvent = {};

  // Event ID → Event
  final Map<String, AudioEvent> _events = {};

  // Currently playing instances
  final List<_PlayingInstance> _playingInstances = [];

  // Preloaded paths (for tracking)
  final Set<String> _preloadedPaths = {};

  // Audio pool for rapid-fire events
  bool _useAudioPool = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO SPATIAL ENGINE — UI-driven spatial audio positioning
  // ═══════════════════════════════════════════════════════════════════════════
  final AutoSpatialEngine _spatialEngine = AutoSpatialEngine();
  bool _useSpatialAudio = true;

  /// Get spatial engine for external anchor registration
  AutoSpatialEngine get spatialEngine => _spatialEngine;

  /// Enable/disable spatial audio positioning
  void setUseSpatialAudio(bool enabled) {
    _useSpatialAudio = enabled;
    debugPrint('[EventRegistry] Spatial audio: ${enabled ? "ENABLED" : "DISABLED"}');
  }

  /// Check if spatial audio is enabled
  bool get useSpatialAudio => _useSpatialAudio;

  // Stats
  int _triggerCount = 0;
  int _pooledTriggers = 0;
  int _spatialTriggers = 0;
  int get triggerCount => _triggerCount;
  int get pooledTriggers => _pooledTriggers;
  int get spatialTriggers => _spatialTriggers;

  // Last triggered event info (for Event Log display)
  String _lastTriggeredEventName = '';
  String _lastTriggeredStage = '';
  List<String> _lastTriggeredLayers = [];
  bool _lastTriggerSuccess = false;
  String _lastTriggerError = '';
  String get lastTriggeredEventName => _lastTriggeredEventName;
  String get lastTriggeredStage => _lastTriggeredStage;
  List<String> get lastTriggeredLayers => _lastTriggeredLayers;
  bool get lastTriggerSuccess => _lastTriggerSuccess;
  String get lastTriggerError => _lastTriggerError;

  /// Enable/disable audio pooling for rapid-fire events
  void setUseAudioPool(bool enabled) {
    _useAudioPool = enabled;
    debugPrint('[EventRegistry] Audio pooling: ${enabled ? "ENABLED" : "DISABLED"}');
  }

  /// Check if a stage should use pooling
  bool _shouldUsePool(String stage) {
    if (!_useAudioPool) return false;
    final normalized = stage.toUpperCase().trim();
    return _pooledEventStages.contains(normalized);
  }

  /// Get priority level for a stage (0-100, higher = more important)
  /// Based on slot-audio-events-master.md priority definitions
  /// LOWEST=0, LOW=20, MEDIUM=40, HIGH=60, HIGHEST=80-100
  int _stageToPriority(String stage) {
    final normalized = stage.toUpperCase().trim();

    // HIGHEST priority (80-100) - Critical moments
    if (normalized.startsWith('JACKPOT_')) return 100;
    if (normalized.contains('WIN_TIER_6') || normalized.contains('WIN_TIER_7')) return 95;
    if (normalized.contains('WIN_EPIC') || normalized.contains('WIN_ULTRA')) return 95;
    if (normalized.startsWith('FS_TRIGGER') || normalized == 'FS_RETRIGGER') return 90;
    if (normalized.startsWith('HOLD_TRIGGER') || normalized == 'HOLD_GRID_FULL') return 90;
    if (normalized.startsWith('BONUS_TRIGGER')) return 90;
    if (normalized.contains('WIN_TIER_4') || normalized.contains('WIN_TIER_5')) return 85;
    if (normalized.contains('WIN_MEGA') || normalized.contains('WIN_SUPER')) return 85;
    if (normalized.startsWith('SCATTER_LAND_3') || normalized.startsWith('SCATTER_LAND_4')) return 85;
    if (normalized.startsWith('BONUS_LAND_3')) return 85;
    if (normalized.contains('FANFARE')) return 80;
    if (normalized.contains('SUMMARY')) return 80;
    if (normalized.startsWith('CASCADE_COMBO_5') || normalized.startsWith('CASCADE_COMBO_6')) return 80;

    // HIGH priority (60-79) - Important feedback
    if (normalized.startsWith('SPIN_START') || normalized.startsWith('SPIN_BUTTON')) return 70;
    if (normalized.startsWith('REEL_STOP') || normalized.startsWith('REEL_SLAM')) return 70;
    if (normalized.startsWith('REEL_SPIN_START')) return 70;
    if (normalized.startsWith('WILD_')) return 65;
    if (normalized.startsWith('SCATTER_')) return 65;
    if (normalized.startsWith('BONUS_LAND')) return 65;
    if (normalized.startsWith('ANTICIPATION_')) return 65;
    if (normalized.contains('WIN_BIG') || normalized.contains('WIN_TIER_3')) return 65;
    if (normalized.contains('WIN_MEDIUM') || normalized.contains('WIN_TIER_2')) return 60;
    if (normalized.startsWith('ROLLUP_START') || normalized.startsWith('ROLLUP_SLAM')) return 65;
    if (normalized.startsWith('CASCADE_WIN') || normalized.startsWith('CASCADE_START')) return 65;
    if (normalized.startsWith('CASCADE_COMBO_')) return 65;
    if (normalized.startsWith('MULT_')) return 65;
    if (normalized.startsWith('PICK_REVEAL')) return 60;
    if (normalized.startsWith('WHEEL_')) return 60;
    if (normalized.startsWith('HOLD_SYMBOL_LOCK') || normalized.startsWith('HOLD_NEW')) return 65;
    if (normalized.startsWith('HOLD_SPECIAL')) return 70;
    if (normalized.contains('TRANSITION')) return 60;
    if (normalized.contains('ENTER') || normalized.contains('EXIT')) return 60;

    // MEDIUM priority (40-59) - Gameplay
    if (normalized.startsWith('REEL_SPIN_LOOP')) return 50;
    if (normalized.startsWith('REEL_NUDGE') || normalized.startsWith('REEL_RESPIN')) return 50;
    if (normalized.contains('WIN_SMALL') || normalized.contains('WIN_TIER_1')) return 50;
    if (normalized.contains('WIN_MICRO') || normalized.contains('WIN_TIER_0')) return 45;
    if (normalized.startsWith('WIN_LINE') || normalized.startsWith('WIN_SYMBOL')) return 50;
    if (normalized.startsWith('SYMBOL_LAND_HIGH') || normalized.startsWith('SYMBOL_LAND_PREMIUM')) return 50;
    if (normalized.startsWith('CASCADE_SYMBOL')) return 45;
    if (normalized.startsWith('TUMBLE_') || normalized.startsWith('AVALANCHE_')) return 45;
    if (normalized.startsWith('ROLLUP_MILESTONE')) return 55;
    if (normalized.startsWith('ROLLUP_LOOP')) return 45;
    if (normalized.startsWith('NEAR_MISS')) return 50;
    if (normalized.startsWith('TENSION_')) return 45;
    if (normalized.startsWith('FS_SPIN') || normalized.startsWith('FS_WIN')) return 50;
    if (normalized.startsWith('HOLD_RESPIN')) return 50;
    if (normalized.startsWith('GAMBLE_')) return 50;
    if (normalized.startsWith('TRAIL_')) return 45;
    if (normalized.startsWith('UI_SPIN_BUTTON')) return 50;
    if (normalized.startsWith('UI_ERROR')) return 50;
    if (normalized.startsWith('COIN_') || normalized.startsWith('MYSTERY_')) return 45;
    if (normalized.startsWith('MUSIC_FEATURE') || normalized.startsWith('MUSIC_WIN')) return 50;

    // LOW priority (20-39) - UI and minor feedback
    if (normalized.startsWith('UI_')) return 25;
    if (normalized.startsWith('SYMBOL_LAND')) return 25;
    if (normalized.startsWith('ROLLUP_TICK')) return 30;
    if (normalized.startsWith('WIN_EVAL') || normalized.startsWith('WIN_LINE_EVAL')) return 25;
    if (normalized.startsWith('NO_WIN') || normalized == 'LDW_SOUND') return 30;
    if (normalized.startsWith('WHEEL_TICK')) return 25;
    if (normalized.startsWith('TRAIL_MOVE')) return 30;
    if (normalized.startsWith('PROGRESSIVE_')) return 25;
    if (normalized.startsWith('SYSTEM_') || normalized.startsWith('CONNECTION_')) return 35;
    if (normalized.startsWith('REALITY_') || normalized.startsWith('TIME_')) return 35;

    // LOWEST priority (0-19) - Ambient/background
    if (normalized.startsWith('MUSIC_BASE') || normalized.startsWith('MUSIC_INTENSITY')) return 15;
    if (normalized.startsWith('AMBIENT_')) return 10;
    if (normalized.startsWith('ATTRACT_') || normalized.startsWith('IDLE_')) return 15;
    if (normalized.startsWith('DEMO_')) return 15;

    // Default
    return 40;
  }

  /// Map stage name to SpatialBus
  /// Complete mapping based on slot-audio-events-master.md categories
  SpatialBus _stageToBus(String stage, int busId) {
    final normalized = stage.toUpperCase();

    // ═══════════════════════════════════════════════════════════════════════════
    // REEL BUS — Reel spin and stop sounds (spatial panning left-to-right)
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('REEL_')) return SpatialBus.reels;
    if (normalized.startsWith('SPIN_') && !normalized.contains('FREE')) return SpatialBus.reels;
    if (normalized.startsWith('SYMBOL_LAND')) return SpatialBus.reels;

    // ═══════════════════════════════════════════════════════════════════════════
    // SFX BUS — Wins, jackpots, cascades, features, celebrations
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('WIN_')) return SpatialBus.sfx;
    if (normalized.startsWith('BIGWIN_')) return SpatialBus.sfx;
    if (normalized.startsWith('JACKPOT_')) return SpatialBus.sfx;
    if (normalized.startsWith('CASCADE_')) return SpatialBus.sfx;
    if (normalized.startsWith('TUMBLE_')) return SpatialBus.sfx;
    if (normalized.startsWith('AVALANCHE_')) return SpatialBus.sfx;
    if (normalized.startsWith('ROLLUP_')) return SpatialBus.sfx;
    if (normalized.startsWith('WILD_')) return SpatialBus.sfx;
    if (normalized.startsWith('SCATTER_')) return SpatialBus.sfx;
    if (normalized.startsWith('BONUS_')) return SpatialBus.sfx;
    if (normalized.startsWith('COIN_')) return SpatialBus.sfx;
    if (normalized.startsWith('MYSTERY_')) return SpatialBus.sfx;
    if (normalized.startsWith('COLLECTOR_')) return SpatialBus.sfx;
    if (normalized.startsWith('PAYER_')) return SpatialBus.sfx;
    if (normalized.startsWith('MULT_')) return SpatialBus.sfx;
    if (normalized.startsWith('ANTICIPATION_')) return SpatialBus.sfx;
    if (normalized.startsWith('NEAR_MISS')) return SpatialBus.sfx;
    if (normalized.startsWith('TENSION_')) return SpatialBus.sfx;
    if (normalized.startsWith('SUSPENSE_')) return SpatialBus.sfx;
    if (normalized.startsWith('FS_') && !normalized.contains('MUSIC')) return SpatialBus.sfx;
    if (normalized.startsWith('HOLD_') && !normalized.contains('MUSIC')) return SpatialBus.sfx;
    if (normalized.startsWith('PICK_')) return SpatialBus.sfx;
    if (normalized.startsWith('WHEEL_') && !normalized.contains('MUSIC')) return SpatialBus.sfx;
    if (normalized.startsWith('TRAIL_') && !normalized.contains('MUSIC')) return SpatialBus.sfx;
    if (normalized.startsWith('GAMBLE_')) return SpatialBus.sfx;
    if (normalized.startsWith('MODIFIER_')) return SpatialBus.sfx;
    if (normalized.startsWith('RANDOM_')) return SpatialBus.sfx;
    if (normalized.startsWith('GOD_')) return SpatialBus.sfx;
    if (normalized.startsWith('XBOMB_') || normalized.startsWith('XNUDGE_') || normalized.startsWith('XWAYS_')) return SpatialBus.sfx;

    // ═══════════════════════════════════════════════════════════════════════════
    // MUSIC BUS — Background music, feature music, transitions
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('MUSIC_')) return SpatialBus.music;
    if (normalized.contains('MUSIC_LOOP')) return SpatialBus.music;
    if (normalized.startsWith('FS_MUSIC')) return SpatialBus.music;
    if (normalized.startsWith('HOLD_MUSIC')) return SpatialBus.music;
    if (normalized.startsWith('BONUS_MUSIC')) return SpatialBus.music;
    if (normalized.startsWith('TRAIL_MUSIC')) return SpatialBus.music;
    if (normalized.startsWith('ATTRACT_')) return SpatialBus.music;

    // ═══════════════════════════════════════════════════════════════════════════
    // VO BUS — Voice overs, announcements
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.contains('VOICE') || normalized.contains('_VO')) return SpatialBus.vo;
    if (normalized.contains('ANNOUNCE')) return SpatialBus.vo;
    if (normalized.startsWith('FS_TRIGGER_VOICE')) return SpatialBus.vo;
    if (normalized.startsWith('HOLD_TRIGGER_VOICE')) return SpatialBus.vo;
    if (normalized.startsWith('JACKPOT_VOICE')) return SpatialBus.vo;
    if (normalized.startsWith('MULT_ANNOUNCE')) return SpatialBus.vo;
    if (normalized.startsWith('FS_LAST_SPIN_ANNOUNCE')) return SpatialBus.vo;

    // ═══════════════════════════════════════════════════════════════════════════
    // UI BUS — Interface sounds, buttons, menus
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('UI_')) return SpatialBus.ui;
    if (normalized.startsWith('SYSTEM_')) return SpatialBus.ui;
    if (normalized.startsWith('CONNECTION_')) return SpatialBus.ui;
    if (normalized.startsWith('GAME_')) return SpatialBus.ui;
    if (normalized.startsWith('AUDIO_')) return SpatialBus.ui;
    if (normalized.startsWith('REALITY_')) return SpatialBus.ui;
    if (normalized.startsWith('TIME_')) return SpatialBus.ui;
    if (normalized.startsWith('LOSS_')) return SpatialBus.ui;
    if (normalized.startsWith('DEPOSIT_')) return SpatialBus.ui;
    if (normalized.startsWith('SESSION_')) return SpatialBus.ui;
    if (normalized.startsWith('BREAK_')) return SpatialBus.ui;
    if (normalized.startsWith('COOL_')) return SpatialBus.ui;
    if (normalized.startsWith('SELF_')) return SpatialBus.ui;

    // ═══════════════════════════════════════════════════════════════════════════
    // AMBIENCE BUS — Background ambience, atmosphere
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('AMBIENT_')) return SpatialBus.ambience;
    if (normalized.startsWith('IDLE_')) return SpatialBus.ambience;
    if (normalized.startsWith('DEMO_')) return SpatialBus.ambience;

    // ═══════════════════════════════════════════════════════════════════════════
    // FALLBACK — Based on busId parameter
    // ═══════════════════════════════════════════════════════════════════════════
    return switch (busId) {
      0 => SpatialBus.sfx,      // Master/default
      1 => SpatialBus.music,    // Music bus
      2 => SpatialBus.sfx,      // SFX bus
      3 => SpatialBus.vo,       // VO bus
      4 => SpatialBus.ui,       // UI bus
      5 => SpatialBus.ambience, // Ambience bus
      _ => SpatialBus.sfx,
    };
  }

  /// Get spatial intent from stage name (maps to SlotIntentRules)
  /// Complete mapping based on slot-audio-events-master.md catalog
  String _stageToIntent(String stage) {
    // Normalize and return - SlotIntentRules uses uppercase names
    final normalized = stage.toUpperCase().trim();

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN & REEL EVENTS
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('SPIN_')) {
      return switch (normalized) {
        'SPIN_START' => 'SPIN_START',
        'SPIN_BUTTON_PRESS' => 'SPIN_START',
        'SPIN_TURBO_START' => 'SPIN_START',
        'SPIN_QUICK_STOP' => 'SPIN_START',
        'SPIN_AUTO_START' => 'SPIN_START',
        _ => 'SPIN_START',
      };
    }

    if (normalized.startsWith('REEL_SPIN')) {
      return 'REEL_SPIN';
    }

    if (normalized.startsWith('REEL_STOP')) {
      return switch (normalized) {
        'REEL_STOP' => 'REEL_STOP_2',  // Default to center
        'REEL_STOP_0' => 'REEL_STOP_0',
        'REEL_STOP_1' => 'REEL_STOP_1',
        'REEL_STOP_2' => 'REEL_STOP_2',
        'REEL_STOP_3' => 'REEL_STOP_3',
        'REEL_STOP_4' => 'REEL_STOP_4',
        'REEL_STOP_5' => 'REEL_STOP_4',  // Map to rightmost
        'REEL_STOP_FINAL' => 'REEL_STOP_4',
        _ => 'REEL_STOP_2',
      };
    }

    if (normalized.startsWith('REEL_SLAM')) {
      return switch (normalized) {
        'REEL_SLAM_0' => 'REEL_STOP_0',
        'REEL_SLAM_1' => 'REEL_STOP_1',
        'REEL_SLAM_2' => 'REEL_STOP_2',
        'REEL_SLAM_3' => 'REEL_STOP_3',
        'REEL_SLAM_4' => 'REEL_STOP_4',
        _ => 'REEL_STOP_2',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYMBOL EVENTS (Wild, Scatter, Bonus)
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('WILD_')) {
      return switch (normalized) {
        'WILD_LAND_0' => 'REEL_STOP_0',
        'WILD_LAND_1' => 'REEL_STOP_1',
        'WILD_LAND_2' => 'REEL_STOP_2',
        'WILD_LAND_3' => 'REEL_STOP_3',
        'WILD_LAND_4' => 'REEL_STOP_4',
        'WILD_EXPAND' || 'WILD_EXPAND_START' || 'WILD_EXPAND_COMPLETE' => 'WIN_BIG',
        'WILD_STACK' || 'WILD_STACK_FULL' || 'WILD_COLOSSAL' => 'WIN_MEGA',
        'WILD_MULTIPLY' || 'WILD_MULTIPLY_2X' || 'WILD_MULTIPLY_3X' || 'WILD_MULTIPLY_5X' => 'WIN_BIG',
        _ => 'WIN_MEDIUM',
      };
    }

    if (normalized.startsWith('SCATTER_')) {
      return switch (normalized) {
        'SCATTER_LAND_1' => 'ANTICIPATION',
        'SCATTER_LAND_2' => 'ANTICIPATION',
        'SCATTER_LAND_3' => 'FREE_SPIN_TRIGGER',
        'SCATTER_LAND_4' || 'SCATTER_LAND_5' => 'JACKPOT_TRIGGER',
        _ => 'ANTICIPATION',
      };
    }

    if (normalized.startsWith('BONUS_LAND')) {
      return switch (normalized) {
        'BONUS_LAND_1' => 'ANTICIPATION',
        'BONUS_LAND_2' => 'ANTICIPATION',
        'BONUS_LAND_3' => 'FEATURE_ENTER',
        _ => 'ANTICIPATION',
      };
    }

    if (normalized.startsWith('SYMBOL_')) {
      return 'DEFAULT'; // Symbol lands don't need special spatial
    }

    if (normalized.startsWith('COIN_') || normalized.startsWith('MYSTERY_') ||
        normalized.startsWith('COLLECTOR_') || normalized.startsWith('PAYER_')) {
      return 'WIN_MEDIUM';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANTICIPATION & TENSION
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('ANTICIPATION_') || normalized == 'ANTICIPATION') {
      return 'ANTICIPATION';
    }

    if (normalized.startsWith('NEAR_MISS')) {
      return 'ANTICIPATION';
    }

    if (normalized.startsWith('TENSION_') || normalized.startsWith('SUSPENSE_')) {
      return 'ANTICIPATION';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WIN EVALUATION & CELEBRATION
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('WIN_')) {
      return switch (normalized) {
        // Win tiers
        'WIN_MICRO' || 'WIN_TIER_0' => 'WIN_SMALL',
        'WIN_TIER_1_SMALL' || 'WIN_SMALL' || 'SMALL_WIN' => 'WIN_SMALL',
        'WIN_TIER_2_MEDIUM' || 'WIN_MEDIUM' || 'MEDIUM_WIN' => 'WIN_MEDIUM',
        'WIN_TIER_3_BIG' || 'WIN_BIG' || 'BIG_WIN' => 'WIN_BIG',
        'WIN_TIER_4_MEGA' || 'WIN_MEGA' || 'MEGA_WIN' => 'WIN_MEGA',
        'WIN_TIER_5_SUPER' => 'WIN_MEGA',
        'WIN_TIER_6_EPIC' || 'WIN_EPIC' || 'EPIC_WIN' => 'WIN_EPIC',
        'WIN_TIER_7_ULTRA' => 'JACKPOT_TRIGGER',
        // Win presentation
        'WIN_PRESENT' => 'WIN_MEDIUM',
        'WIN_DETECTED' => 'WIN_SMALL',
        'WIN_MULTIPLIED' => 'WIN_BIG',
        'WIN_MULTIPLIER_COMBINE' => 'WIN_MEGA',
        // Celebration sounds (center)
        'WIN_FANFARE_INTRO' || 'WIN_FANFARE_LOOP' || 'WIN_FANFARE_OUTRO' => 'WIN_MEGA',
        'WIN_COINS_BURST' || 'WIN_COINS_LOOP' || 'WIN_COINS_SHOWER' => 'WIN_BIG',
        'WIN_FIREWORK' || 'WIN_FIREWORKS_LOOP' => 'WIN_MEGA',
        'WIN_CROWD_CHEER' || 'WIN_APPLAUSE' => 'WIN_EPIC',
        _ => 'WIN_MEDIUM',
      };
    }

    // Big Win tier mapping
    if (normalized.startsWith('BIGWIN_TIER_')) {
      return switch (normalized) {
        'BIGWIN_TIER_NICE' || 'SLOT_BIGWIN_TIER_NICE' => 'WIN_SMALL',
        'BIGWIN_TIER_SUPER' || 'SLOT_BIGWIN_TIER_SUPER' => 'WIN_BIG',
        'BIGWIN_TIER_MEGA' || 'SLOT_BIGWIN_TIER_MEGA' => 'WIN_MEGA',
        'BIGWIN_TIER_EPIC' || 'SLOT_BIGWIN_TIER_EPIC' => 'WIN_EPIC',
        'BIGWIN_TIER_ULTRA' || 'SLOT_BIGWIN_TIER_ULTRA' => 'JACKPOT_TRIGGER',
        _ => 'WIN_BIG',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLLUP COUNTER
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('ROLLUP_')) {
      return switch (normalized) {
        'ROLLUP_START' => 'WIN_MEDIUM',
        'ROLLUP_SLAM' || 'ROLLUP_END' => 'WIN_BIG',
        'ROLLUP_MILESTONE_25' => 'WIN_SMALL',
        'ROLLUP_MILESTONE_50' => 'WIN_MEDIUM',
        'ROLLUP_MILESTONE_75' => 'WIN_BIG',
        _ => 'DEFAULT', // Ticks don't need spatial
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CASCADE / TUMBLE
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('CASCADE_')) {
      return switch (normalized) {
        'CASCADE_WIN' || 'CASCADE_START' => 'CASCADE_STEP',
        'CASCADE_COMBO_1' => 'WIN_SMALL',
        'CASCADE_COMBO_2' => 'WIN_MEDIUM',
        'CASCADE_COMBO_3' => 'WIN_BIG',
        'CASCADE_COMBO_4' => 'WIN_MEGA',
        'CASCADE_COMBO_5' || 'CASCADE_COMBO_6_PLUS' => 'WIN_EPIC',
        'CASCADE_MULTIPLIER_UP' => 'WIN_BIG',
        'CASCADE_END' => 'WIN_MEDIUM',
        _ => 'CASCADE_STEP',
      };
    }

    if (normalized.startsWith('TUMBLE_') || normalized.startsWith('AVALANCHE_') ||
        normalized.startsWith('REACTION_')) {
      return 'CASCADE_STEP';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FREE SPINS
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('FS_')) {
      return switch (normalized) {
        'FS_TRIGGER' || 'FS_TRIGGER_VOICE' => 'FREE_SPIN_TRIGGER',
        'FS_ENTER' || 'FS_TRANSITION_IN' => 'FEATURE_ENTER',
        'FS_EXIT' || 'FS_TRANSITION_OUT' => 'FEATURE_EXIT',
        'FS_RETRIGGER' || 'FS_RETRIGGER_SCATTER_3' || 'FS_RETRIGGER_AWARD' => 'FREE_SPIN_TRIGGER',
        'FS_MULTIPLIER_UP' || 'FS_MULTIPLIER_MAX' => 'WIN_BIG',
        'FS_SUMMARY_START' || 'FS_SUMMARY_ROLLUP' || 'FS_SUMMARY_END' => 'WIN_MEGA',
        'FS_LAST_SPIN' || 'FS_LAST_SPIN_ANNOUNCE' => 'ANTICIPATION',
        _ => 'DEFAULT',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HOLD & SPIN / RESPIN
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('HOLD_')) {
      return switch (normalized) {
        'HOLD_TRIGGER' || 'HOLD_TRIGGER_VOICE' => 'FEATURE_ENTER',
        'HOLD_ENTER' || 'HOLD_GRID_TRANSFORM' => 'FEATURE_ENTER',
        'HOLD_SYMBOL_LOCK' || 'HOLD_SYMBOL_LOCK_VALUE' => 'WIN_SMALL',
        'HOLD_NEW_SYMBOL' => 'WIN_MEDIUM',
        'HOLD_RESPIN_COUNTER_1' => 'ANTICIPATION',
        'HOLD_SPECIAL_COLLECTOR' || 'HOLD_SPECIAL_PAYER' => 'WIN_MEGA',
        'HOLD_SPECIAL_MULTIPLIER' => 'WIN_BIG',
        'HOLD_GRID_FULL' => 'WIN_EPIC',
        'HOLD_LEVEL_UP' => 'WIN_BIG',
        'HOLD_JACKPOT_SYMBOL' => 'JACKPOT_TRIGGER',
        'HOLD_END' || 'HOLD_EXIT' => 'FEATURE_EXIT',
        'HOLD_COLLECT' || 'HOLD_SUMMARY' => 'WIN_MEGA',
        _ => 'DEFAULT',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BONUS GAMES
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('BONUS_')) {
      return switch (normalized) {
        'BONUS_TRIGGER' => 'FEATURE_ENTER',
        'BONUS_ENTER' => 'FEATURE_ENTER',
        _ => 'DEFAULT',
      };
    }

    if (normalized.startsWith('PICK_')) {
      return switch (normalized) {
        'PICK_REVEAL_SMALL' => 'WIN_SMALL',
        'PICK_REVEAL_MEDIUM' => 'WIN_MEDIUM',
        'PICK_REVEAL_LARGE' => 'WIN_BIG',
        'PICK_REVEAL_JACKPOT' => 'JACKPOT_TRIGGER',
        'PICK_REVEAL_MULTIPLIER' => 'WIN_BIG',
        'PICK_LEVEL_UP' => 'WIN_MEGA',
        _ => 'DEFAULT',
      };
    }

    if (normalized.startsWith('WHEEL_')) {
      return switch (normalized) {
        'WHEEL_APPEAR' => 'FEATURE_ENTER',
        'WHEEL_LAND' || 'WHEEL_PRIZE_REVEAL' => 'WIN_BIG',
        'WHEEL_ADVANCE' => 'WIN_MEGA',
        _ => 'DEFAULT',
      };
    }

    if (normalized.startsWith('TRAIL_')) {
      return switch (normalized) {
        'TRAIL_ENTER' => 'FEATURE_ENTER',
        'TRAIL_LAND_PRIZE' => 'WIN_SMALL',
        'TRAIL_LAND_MULTIPLIER' => 'WIN_MEDIUM',
        'TRAIL_LAND_ADVANCE' => 'WIN_BIG',
        _ => 'DEFAULT',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // JACKPOT
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('JACKPOT_')) {
      return switch (normalized) {
        'JACKPOT_TRIGGER' || 'JACKPOT' => 'JACKPOT_TRIGGER',
        'JACKPOT_MINI' => 'WIN_BIG',
        'JACKPOT_MINOR' => 'WIN_MEGA',
        'JACKPOT_MAJOR' => 'WIN_EPIC',
        'JACKPOT_GRAND' || 'JACKPOT_MEGA' => 'JACKPOT_TRIGGER',
        _ => 'JACKPOT_TRIGGER',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTIPLIER
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('MULT_')) {
      return switch (normalized) {
        'MULT_2X' || 'MULT_3X' => 'WIN_MEDIUM',
        'MULT_5X' || 'MULT_10X' => 'WIN_BIG',
        'MULT_25X' || 'MULT_50X' => 'WIN_MEGA',
        'MULT_100X' || 'MULT_MAX' => 'WIN_EPIC',
        'MULT_COMBINE' => 'WIN_MEGA',
        _ => 'WIN_MEDIUM',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS & RANDOM FEATURES
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('MODIFIER_') || normalized.startsWith('RANDOM_')) {
      return switch (normalized) {
        'RANDOM_INSTANT_PRIZE' => 'WIN_MEGA',
        'GOD_APPEAR' || 'GOD_BLESSING' => 'WIN_EPIC',
        'XBOMB_EXPLODE' || 'XBOMB_CHAIN' => 'WIN_BIG',
        'QUAD_MERGE' => 'WIN_MEGA',
        _ => 'WIN_MEDIUM',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAMBLE
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('GAMBLE_')) {
      return switch (normalized) {
        'GAMBLE_WIN' || 'GAMBLE_DOUBLE' => 'WIN_BIG',
        'GAMBLE_MAX_WIN' => 'WIN_MEGA',
        'GAMBLE_LOSE' => 'DEFAULT',
        _ => 'DEFAULT',
      };
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UI EVENTS (minimal spatial, center biased)
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('UI_')) {
      return 'DEFAULT';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AMBIENT & MUSIC (center, wide stereo)
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('MUSIC_') || normalized.startsWith('AMBIENT_') ||
        normalized.startsWith('ATTRACT_') || normalized.startsWith('IDLE_')) {
      return 'DEFAULT';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYSTEM
    // ═══════════════════════════════════════════════════════════════════════════
    if (normalized.startsWith('SYSTEM_') || normalized.startsWith('CONNECTION_') ||
        normalized.startsWith('SESSION_') || normalized.startsWith('GAME_') ||
        normalized.startsWith('REALITY_') || normalized.startsWith('TIME_') ||
        normalized.startsWith('LOSS_') || normalized.startsWith('DEPOSIT_')) {
      return 'DEFAULT';
    }

    // Legacy mappings for backwards compatibility
    return switch (normalized) {
      'ANTICIPATION' || 'ANTICIPATION_ON' => 'ANTICIPATION',
      'FEATURE_ENTER' => 'FEATURE_ENTER',
      'FEATURE_EXIT' => 'FEATURE_EXIT',
      'FREE_SPIN_TRIGGER' || 'FREE_SPINS' => 'FREE_SPIN_TRIGGER',
      _ => 'DEFAULT',  // Fallback to default intent
    };
  }

  // ==========================================================================
  // REGISTRATION
  // ==========================================================================

  /// Registruj event za stage
  /// CRITICAL: This REPLACES any existing event with same ID or stage
  /// Stops any playing instances before replacing to prevent stale audio
  void registerEvent(AudioEvent event) {
    // Stop any playing instances of this event before replacing
    // This prevents old audio from continuing to play after layer changes
    final existingEvent = _events[event.id];
    if (existingEvent != null) {
      // Event exists - stop all playing instances SYNCHRONOUSLY
      _stopEventSync(event.id);
      debugPrint('[EventRegistry] Stopping existing instances before update: ${event.name}');
    }

    // Also check if another event has this stage (shouldn't happen but defensive)
    final existingByStage = _stageToEvent[event.stage];
    if (existingByStage != null && existingByStage.id != event.id) {
      _stopEventSync(existingByStage.id);
      _events.remove(existingByStage.id);
      debugPrint('[EventRegistry] Removed conflicting event for stage: ${event.stage}');
    }

    _events[event.id] = event;
    _stageToEvent[event.stage] = event;

    // Log layer details for debugging
    final layerPaths = event.layers.map((l) => l.audioPath.split('/').last).join(', ');
    debugPrint('[EventRegistry] Registered: ${event.name} → ${event.stage} (${event.layers.length} layers: $layerPaths)');

    // Update preloaded paths
    for (final layer in event.layers) {
      if (layer.audioPath.isNotEmpty) {
        _preloadedPaths.add(layer.audioPath);
      }
    }

    notifyListeners();
  }

  /// Synchronous stop - for use in registerEvent
  void _stopEventSync(String eventIdOrStage) {
    final eventByStage = _stageToEvent[eventIdOrStage];
    final targetEventId = eventByStage?.id ?? eventIdOrStage;

    final toRemove = <_PlayingInstance>[];
    for (final instance in _playingInstances) {
      if (instance.eventId == targetEventId) {
        // Stop each voice via bus routing (synchronous calls)
        try {
          for (final voiceId in instance.voiceIds) {
            NativeFFI.instance.playbackStopOneShot(voiceId);
          }
        } catch (e) {
          debugPrint('[EventRegistry] Stop error: $e');
        }
        toRemove.add(instance);
      }
    }

    _playingInstances.removeWhere((i) => toRemove.contains(i));
    if (toRemove.isNotEmpty) {
      debugPrint('[EventRegistry] Sync stopped ${toRemove.length} instance(s) of: $eventIdOrStage');
    }
  }

  /// Ukloni event
  /// CRITICAL: Stops any playing instances before removing
  void unregisterEvent(String eventId) {
    // Stop any playing instances first (synchronous)
    _stopEventSync(eventId);

    final event = _events.remove(eventId);
    if (event != null) {
      _stageToEvent.remove(event.stage);
      debugPrint('[EventRegistry] Unregistered: ${event.name} (stopped all instances)');
      notifyListeners();
    }
  }

  /// Dobij sve registrovane evente
  List<AudioEvent> get allEvents => _events.values.toList();

  /// Dobij event po stage-u
  AudioEvent? getEventForStage(String stage) => _stageToEvent[stage];

  /// Dobij event po ID-u
  AudioEvent? getEventById(String eventId) => _events[eventId];

  /// Proveri da li je stage registrovan
  bool hasEventForStage(String stage) => _stageToEvent.containsKey(stage);

  /// Proveri da li se event trenutno reprodukuje
  bool isEventPlaying(String eventId) =>
      _playingInstances.any((i) => i.eventId == eventId);

  // ==========================================================================
  // TRIGGERING
  // ==========================================================================

  /// Trigeruj event po stage-u
  /// FIXED: Case-insensitive lookup — normalizes stage to UPPERCASE
  Future<void> triggerStage(String stage, {Map<String, dynamic>? context}) async {
    final normalizedStage = stage.toUpperCase().trim();

    // Try exact match first, then normalized
    var event = _stageToEvent[stage];
    event ??= _stageToEvent[normalizedStage];

    // If still not found, try case-insensitive search through all keys
    if (event == null) {
      for (final key in _stageToEvent.keys) {
        if (key.toUpperCase() == normalizedStage) {
          event = _stageToEvent[key];
          break;
        }
      }
    }

    if (event == null) {
      // More detailed logging for debugging
      final registeredStages = _stageToEvent.keys.take(10).join(', ');
      final suffix = _stageToEvent.length > 10 ? '...(+${_stageToEvent.length - 10} more)' : '';
      debugPrint('[EventRegistry] ❌ No event for stage: "$stage" (normalized: "$normalizedStage")');
      debugPrint('[EventRegistry] 📋 Registered stages (${_stageToEvent.length}): $registeredStages$suffix');
      return;
    }
    await triggerEvent(event.id, context: context);
  }

  /// Trigeruj event po ID-u
  Future<void> triggerEvent(String eventId, {Map<String, dynamic>? context}) async {
    final event = _events[eventId];
    if (event == null) {
      debugPrint('[EventRegistry] Event not found: $eventId');
      return;
    }

    _triggerCount++;

    // Store last triggered event info for Event Log display
    _lastTriggeredEventName = event.name;
    _lastTriggeredStage = event.stage;
    _lastTriggeredLayers = event.layers
        .where((l) => l.audioPath.isNotEmpty)
        .map((l) => l.audioPath.split('/').last) // Just filename
        .toList();

    // Check if event has playable layers
    if (_lastTriggeredLayers.isEmpty) {
      _lastTriggerSuccess = false;
      _lastTriggerError = 'No audio layers';
      debugPrint('[EventRegistry] ⚠️ Event "${event.name}" has no playable audio layers!');
      notifyListeners();
      return;
    }

    // Check if this event should use pooling
    final usePool = _shouldUsePool(event.stage);
    final poolStr = usePool ? ' [POOLED]' : '';

    // Debug: Log all layer paths
    final layerPaths = event.layers.map((l) => l.audioPath).toList();
    debugPrint('[EventRegistry] Triggering: ${event.name} (${event.layers.length} layers)$poolStr');
    debugPrint('[EventRegistry] Layer paths: $layerPaths');

    // Reset success tracking
    _lastTriggerSuccess = true;
    _lastTriggerError = '';

    // Kreiraj playing instance
    final voiceIds = <int>[];
    final instance = _PlayingInstance(
      eventId: eventId,
      voiceIds: voiceIds,
      startTime: DateTime.now(),
    );
    _playingInstances.add(instance);

    // Pokreni sve layer-e sa njihovim delay-ima
    for (final layer in event.layers) {
      _playLayer(
        layer,
        voiceIds,
        context,
        usePool: usePool,
        eventKey: event.stage,
        loop: event.loop, // P0.2: Pass loop flag for seamless looping (REEL_SPIN)
      );
    }

    notifyListeners();
  }

  Future<void> _playLayer(
    AudioLayer layer,
    List<int> voiceIds,
    Map<String, dynamic>? context, {
    bool usePool = false,
    String? eventKey,
    bool loop = false, // P0.2: Seamless loop support
  }) async {
    if (layer.audioPath.isEmpty) {
      debugPrint('[EventRegistry] ⚠️ Skipping layer "${layer.name}" — empty audioPath');
      return;
    }
    debugPrint('[EventRegistry] 🔊 Playing layer "${layer.name}" | path: ${layer.audioPath}');

    // Delay pre početka
    final totalDelayMs = (layer.delay + layer.offset * 1000).round();
    if (totalDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: totalDelayMs));
    }

    try {
      // Apply volume (može se modulirati context-om)
      double volume = layer.volume;
      if (context != null && context.containsKey('volumeMultiplier')) {
        volume *= (context['volumeMultiplier'] as num).toDouble();
      }

      // Apply RTPC modulation if layer/event has bindings
      final eventId = eventKey ?? layer.id;
      if (RtpcModulationService.instance.hasMapping(eventId)) {
        volume = RtpcModulationService.instance.getModulatedVolume(eventId, volume);
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SPATIAL AUDIO POSITIONING (AutoSpatialEngine integration)
      // P1.3: Context pan takes priority over layer pan, spatial engine overrides both
      // ═══════════════════════════════════════════════════════════════════════
      double pan = layer.pan; // Default to layer's configured pan

      // P1.3: Context pan (from win line panning etc.) overrides layer pan
      if (context != null && context.containsKey('pan')) {
        pan = (context['pan'] as num).toDouble().clamp(-1.0, 1.0);
      }

      if (_useSpatialAudio && eventKey != null) {
        final spatialEventId = '${eventKey}_${layer.id}_${DateTime.now().millisecondsSinceEpoch}';
        final intent = _stageToIntent(eventKey);
        final bus = _stageToBus(eventKey, layer.busId);

        // Create spatial event
        final spatialEvent = SpatialEvent(
          id: spatialEventId,
          name: layer.name,
          intent: intent,
          bus: bus,
          timeMs: DateTime.now().millisecondsSinceEpoch,
          lifetimeMs: 500, // Track for 500ms
          importance: 0.8,
        );

        // Register with spatial engine
        _spatialEngine.onEvent(spatialEvent);

        // Update engine and get output
        final outputs = _spatialEngine.update();
        final spatialOutput = outputs[spatialEventId];

        if (spatialOutput != null) {
          // Apply spatial pan (overrides layer pan)
          pan = spatialOutput.pan;
          // Could also apply volume attenuation from distance
          // volume *= spatialOutput.distanceGain;
          _spatialTriggers++;
        }
      }

      // Notify DuckingService that this bus is playing
      DuckingService.instance.notifyBusActive(layer.busId);

      // Determine correct PlaybackSource from active section in UnifiedPlaybackController
      final activeSection = UnifiedPlaybackController.instance.activeSection;
      final source = switch (activeSection) {
        PlaybackSection.daw => PlaybackSource.daw,
        PlaybackSection.slotLab => PlaybackSource.slotlab,
        PlaybackSection.middleware => PlaybackSource.middleware,
        PlaybackSection.browser => PlaybackSource.browser,
        null => PlaybackSource.slotlab, // Default to slotlab for EventRegistry
      };

      debugPrint('[EventRegistry] _playLayer: activeSection=$activeSection, source=$source, path=${layer.audioPath}');

      int voiceId;

      // Use bus routing for middleware/slotlab, preview engine for browser/daw
      if (source == PlaybackSource.browser) {
        // Browser uses isolated PreviewEngine
        voiceId = AudioPlaybackService.instance.previewFile(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          source: source,
        );
      } else if (usePool && eventKey != null) {
        // Use AudioPool for rapid-fire events (CASCADE_STEP, ROLLUP_TICK, etc.)
        voiceId = AudioPool.instance.acquire(
          eventKey: eventKey,
          audioPath: layer.audioPath,
          busId: layer.busId,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
        );
        _pooledTriggers++;
      } else if (loop) {
        // P0.2: Seamless looping for REEL_SPIN and similar events
        voiceId = AudioPlaybackService.instance.playLoopingToBus(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          busId: layer.busId,
          source: source,
        );
      } else {
        // Standard bus routing through PlaybackEngine
        voiceId = AudioPlaybackService.instance.playFileToBus(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          busId: layer.busId,
          source: source,
        );
      }

      if (voiceId >= 0) {
        voiceIds.add(voiceId);
        final poolStr = usePool ? ' [POOLED]' : '';
        final loopStr = loop ? ' [LOOP]' : '';
        final spatialStr = (_useSpatialAudio && pan != layer.pan) ? ' [SPATIAL pan=${pan.toStringAsFixed(2)}]' : '';
        // Store voice info for debug display
        _lastTriggerError = 'voice=$voiceId, bus=${layer.busId}, section=$activeSection';
        debugPrint('[EventRegistry] ✅ Playing: ${layer.name} (voice $voiceId, source: $source, bus: ${layer.busId})$poolStr$loopStr$spatialStr');
      } else {
        // Voice ID -1 means playback failed - get error from AudioPlaybackService
        final ffiError = AudioPlaybackService.instance.lastPlaybackToBusError;
        _lastTriggerSuccess = false;
        _lastTriggerError = 'FAILED: $ffiError';
        debugPrint('[EventRegistry] ❌ FAILED to play: ${layer.name} | path: ${layer.audioPath} | error: $ffiError');
      }
    } catch (e) {
      debugPrint('[EventRegistry] Error playing layer ${layer.name}: $e');
    }
  }

  // ==========================================================================
  // STOPPING
  // ==========================================================================

  /// Zaustavi sve instance eventa po ID-u ili stage-u
  Future<void> stopEvent(String eventIdOrStage) async {
    final toRemove = <_PlayingInstance>[];

    // Prvo probaj naći event po stage-u
    final eventByStage = _stageToEvent[eventIdOrStage];
    final targetEventId = eventByStage?.id ?? eventIdOrStage;

    for (final instance in _playingInstances) {
      if (instance.eventId == targetEventId) {
        await instance.stop();
        toRemove.add(instance);
      }
    }

    _playingInstances.removeWhere((i) => toRemove.contains(i));
    if (toRemove.isNotEmpty) {
      debugPrint('[EventRegistry] Stopped ${toRemove.length} instance(s) of: $eventIdOrStage');
    }
    notifyListeners();
  }

  /// Zaustavi sve
  Future<void> stopAll() async {
    // Stop all one-shot voices via bus routing
    AudioPlaybackService.instance.stopAllOneShots();

    for (final instance in _playingInstances) {
      await instance.stop();
    }
    _playingInstances.clear();
    notifyListeners();
  }

  // ==========================================================================
  // PRELOADING (Rust engine handles actual caching)
  // ==========================================================================

  /// Preload audio za brži playback
  Future<void> preloadEvent(String eventId) async {
    final event = _events[eventId];
    if (event == null) return;

    for (final layer in event.layers) {
      if (layer.audioPath.isEmpty) continue;
      _preloadedPaths.add(layer.audioPath);
      debugPrint('[EventRegistry] Marked for preload: ${layer.name}');
    }
  }

  /// Preload sve registrovane evente
  Future<void> preloadAll() async {
    for (final eventId in _events.keys) {
      await preloadEvent(eventId);
    }
  }

  // ==========================================================================
  // P0.7: BIG WIN LAYERED AUDIO TEMPLATES
  // ==========================================================================

  /// Create a template Big Win event with layered audio structure
  /// Layers include: Impact, Coin Shower, Music Swell, Voice Over
  /// Each tier has different timing and intensity
  static AudioEvent createBigWinTemplate({
    required String tier, // 'nice', 'super', 'mega', 'epic', 'ultra'
    required String impactPath,
    String? coinShowerPath,
    String? musicSwellPath,
    String? voiceOverPath,
  }) {
    final stageMap = {
      'nice': 'BIGWIN_TIER_NICE',
      'super': 'BIGWIN_TIER_SUPER',
      'mega': 'BIGWIN_TIER_MEGA',
      'epic': 'BIGWIN_TIER_EPIC',
      'ultra': 'BIGWIN_TIER_ULTRA',
    };

    // Tier-specific timing (ms)
    final timingMap = {
      'nice': (coinDelay: 100, musicDelay: 0, voDelay: 300),
      'super': (coinDelay: 150, musicDelay: 0, voDelay: 400),
      'mega': (coinDelay: 100, musicDelay: 0, voDelay: 500),
      'epic': (coinDelay: 100, musicDelay: 0, voDelay: 600),
      'ultra': (coinDelay: 100, musicDelay: 0, voDelay: 700),
    };

    final timing = timingMap[tier] ?? timingMap['nice']!;
    final layers = <AudioLayer>[];

    // Layer 1: Impact Hit (immediate)
    layers.add(AudioLayer(
      id: '${tier}_impact',
      audioPath: impactPath,
      name: 'Impact Hit',
      volume: 1.0,
      pan: 0.0,
      delay: 0,
      busId: 2, // SFX bus
    ));

    // Layer 2: Coin Shower (delayed)
    if (coinShowerPath != null && coinShowerPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_coins',
        audioPath: coinShowerPath,
        name: 'Coin Shower',
        volume: 0.8,
        pan: 0.0,
        delay: timing.coinDelay.toDouble(),
        busId: 2, // SFX bus
      ));
    }

    // Layer 3: Music Swell (simultaneous or slightly delayed)
    if (musicSwellPath != null && musicSwellPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_music',
        audioPath: musicSwellPath,
        name: 'Music Swell',
        volume: 0.9,
        pan: 0.0,
        delay: timing.musicDelay.toDouble(),
        busId: 1, // Music bus
      ));
    }

    // Layer 4: Voice Over (most delayed)
    if (voiceOverPath != null && voiceOverPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_vo',
        audioPath: voiceOverPath,
        name: 'Voice Over',
        volume: 1.0,
        pan: 0.0,
        delay: timing.voDelay.toDouble(),
        busId: 3, // Voice bus
      ));
    }

    return AudioEvent(
      id: 'slot_bigwin_tier_$tier',
      name: 'Big Win - ${tier[0].toUpperCase()}${tier.substring(1)}',
      stage: stageMap[tier] ?? 'BIGWIN_TIER',
      layers: layers,
      priority: tier == 'ultra' ? 100 : (tier == 'epic' ? 80 : (tier == 'mega' ? 60 : 40)),
    );
  }

  /// Register default Big Win events with placeholder paths
  /// Call this to set up the event structure, then update paths via UI
  void registerDefaultBigWinEvents() {
    const tiers = ['nice', 'super', 'mega', 'epic', 'ultra'];

    for (final tier in tiers) {
      final event = createBigWinTemplate(
        tier: tier,
        impactPath: '', // User will fill these via Audio Pool
        coinShowerPath: '',
        musicSwellPath: '',
        voiceOverPath: '',
      );
      registerEvent(event);
      debugPrint('[EventRegistry] P0.7: Registered Big Win template: ${event.id}');
    }
  }

  /// Update a Big Win event with actual audio paths
  void updateBigWinEvent({
    required String tier,
    String? impactPath,
    String? coinShowerPath,
    String? musicSwellPath,
    String? voiceOverPath,
  }) {
    final eventId = 'slot_bigwin_tier_$tier';
    final existing = _events[eventId];
    if (existing == null) {
      debugPrint('[EventRegistry] Big Win event not found: $eventId');
      return;
    }

    // Create new event with updated paths
    final event = createBigWinTemplate(
      tier: tier,
      impactPath: impactPath ?? existing.layers.firstWhere((l) => l.id.contains('impact'), orElse: () => const AudioLayer(id: '', audioPath: '', name: '')).audioPath,
      coinShowerPath: coinShowerPath ?? existing.layers.where((l) => l.id.contains('coins')).firstOrNull?.audioPath,
      musicSwellPath: musicSwellPath ?? existing.layers.where((l) => l.id.contains('music')).firstOrNull?.audioPath,
      voiceOverPath: voiceOverPath ?? existing.layers.where((l) => l.id.contains('vo')).firstOrNull?.audioPath,
    );

    registerEvent(event);
    debugPrint('[EventRegistry] P0.7: Updated Big Win event: $eventId');
  }

  // ==========================================================================
  // SERIALIZATION
  // ==========================================================================

  Map<String, dynamic> toJson() => {
    'events': _events.values.map((e) => e.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _events.clear();
    _stageToEvent.clear();

    final events = json['events'] as List<dynamic>? ?? [];
    for (final eventJson in events) {
      final event = AudioEvent.fromJson(eventJson as Map<String, dynamic>);
      registerEvent(event);
    }
  }

  // ==========================================================================
  // POOL & SPATIAL STATS
  // ==========================================================================

  /// Get combined stats from EventRegistry, AudioPool, and SpatialEngine
  String get statsString {
    final poolStats = AudioPool.instance.statsString;
    final spatialStats = _spatialEngine.getStats();
    return 'EventRegistry: triggers=$_triggerCount, pooled=$_pooledTriggers, spatial=$_spatialTriggers | '
        '$poolStats | Spatial: active=${spatialStats.activeEvents}, processed=${spatialStats.totalEventsProcessed}';
  }

  /// Get spatial engine stats directly
  AutoSpatialStats get spatialStats => _spatialEngine.getStats();

  /// Reset all stats
  void resetStats() {
    _triggerCount = 0;
    _pooledTriggers = 0;
    _spatialTriggers = 0;
    AudioPool.instance.reset();
    _spatialEngine.clear();
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  @override
  void dispose() {
    stopAll();
    _preloadedPaths.clear();
    _spatialEngine.dispose();
    super.dispose();
  }
}

// =============================================================================
// GLOBAL SINGLETON
// =============================================================================

final eventRegistry = EventRegistry();

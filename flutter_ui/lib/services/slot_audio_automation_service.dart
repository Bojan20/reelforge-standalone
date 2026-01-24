/// Slot Audio Automation Service
///
/// Ultimate automation system for slot game audio design.
/// Provides intelligent batch operations, flow templates, and smart asset parsing.
///
/// Features:
/// - Smart Asset Parser: Recognizes reel_stop_2, win_big, fs_intro from names
/// - Reel Set Generator: Drop 1 audio → 5 reel events with auto-pan
/// - Win Tier Escalation: Auto-create win tier series with volume scaling
/// - Music Context Pairs: Auto-create STOP+PLAY pairs for transitions
/// - Flow Templates: One-click spin/feature/cascade flows
/// - Batch Folder Import: Drop folder → analyze → preview → commit all
/// - Cascade Step Generator: Auto-create N cascade steps
library;

import 'dart:math' as math;
import '../models/middleware_models.dart' show ActionType;
import 'audio_context_service.dart';

// =============================================================================
// SMART ASSET PARSER
// =============================================================================

/// Parsed information from audio file name
class ParsedAudioAsset {
  /// Original file path
  final String path;

  /// Detected category
  final AssetCategory category;

  /// Detected reel index (0-4) if applicable
  final int? reelIndex;

  /// Detected win tier if applicable
  final WinTier? winTier;

  /// Detected feature type if applicable
  final FeatureType? featureType;

  /// Detected stage phase (start, loop, end)
  final StagePhase? phase;

  /// Suggested stage name
  final String suggestedStage;

  /// Suggested bus
  final String suggestedBus;

  /// Suggested pan (-1.0 to 1.0)
  final double suggestedPan;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  const ParsedAudioAsset({
    required this.path,
    required this.category,
    this.reelIndex,
    this.winTier,
    this.featureType,
    this.phase,
    required this.suggestedStage,
    required this.suggestedBus,
    this.suggestedPan = 0.0,
    this.confidence = 0.5,
  });

  @override
  String toString() =>
      'ParsedAudioAsset($category, stage: $suggestedStage, conf: ${(confidence * 100).toInt()}%)';
}

/// Asset category
enum AssetCategory {
  reelStop,
  reelSpin,
  spin,
  win,
  music,
  feature,
  jackpot,
  cascade,
  symbol,
  ui,
  ambience,
  unknown,
}

/// Win tier levels
enum WinTier {
  small,
  medium,
  big,
  mega,
  epic,
  ultra,
}

/// Feature types
enum FeatureType {
  freeSpins,
  bonus,
  holdAndWin,
  gamble,
  picker,
  wheel,
}

/// Stage phase
enum StagePhase {
  trigger,
  start,
  loop,
  step,
  end,
  exit,
}

// =============================================================================
// AUTOMATION RESULTS
// =============================================================================

/// Result of a batch operation
class AutomationResult {
  /// Events to be created
  final List<AutoEventSpec> events;

  /// Human-readable summary
  final String summary;

  /// Warnings or suggestions
  final List<String> warnings;

  const AutomationResult({
    required this.events,
    required this.summary,
    this.warnings = const [],
  });

  int get eventCount => events.length;
}

/// Specification for an auto-generated event
class AutoEventSpec {
  final String eventId;
  final String stage;
  final String bus;
  final String audioPath;
  final double volume;
  final double pan;
  final ActionType actionType;
  final String? stopTarget;
  final bool loop;
  final int priority;
  final Map<String, dynamic> metadata;

  const AutoEventSpec({
    required this.eventId,
    required this.stage,
    required this.bus,
    required this.audioPath,
    this.volume = 1.0,
    this.pan = 0.0,
    this.actionType = ActionType.play,
    this.stopTarget,
    this.loop = false,
    this.priority = 50,
    this.metadata = const {},
  });
}

// =============================================================================
// FLOW TEMPLATES
// =============================================================================

/// Pre-defined slot audio flow template
class FlowTemplate {
  final String id;
  final String name;
  final String description;
  final List<FlowTemplateStage> stages;
  final FlowCategory category;

  const FlowTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.stages,
    required this.category,
  });
}

/// Stage within a flow template
class FlowTemplateStage {
  final String stage;
  final String bus;
  final AssetCategory expectedAssetType;
  final double defaultPan;
  final double defaultVolume;
  final bool isOptional;
  final String hint;

  const FlowTemplateStage({
    required this.stage,
    required this.bus,
    required this.expectedAssetType,
    this.defaultPan = 0.0,
    this.defaultVolume = 1.0,
    this.isOptional = false,
    this.hint = '',
  });
}

enum FlowCategory {
  spin,
  win,
  feature,
  music,
  cascade,
  jackpot,
}

// =============================================================================
// SLOT AUDIO AUTOMATION SERVICE
// =============================================================================

/// Singleton service for slot audio automation
class SlotAudioAutomationService {
  SlotAudioAutomationService._();
  static final instance = SlotAudioAutomationService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. SMART ASSET PARSER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse audio file name to extract slot-specific information
  ParsedAudioAsset parseAsset(String path) {
    final name = path.toLowerCase();
    final fileName = name.split('/').last.split('\\').last;
    final baseName = fileName.replaceAll(RegExp(r'\.(wav|mp3|ogg|flac|aiff)$'), '');

    // Try to detect category and details
    AssetCategory category = AssetCategory.unknown;
    int? reelIndex;
    WinTier? winTier;
    FeatureType? featureType;
    StagePhase? phase;
    String suggestedStage = 'UNKNOWN';
    String suggestedBus = 'sfx';
    double suggestedPan = 0.0;
    double confidence = 0.3;

    // ─────────────────────────────────────────────────────────────────────────
    // REEL STOP detection (reel_stop, reel_stop_0, stop_reel_2, etc.)
    // ─────────────────────────────────────────────────────────────────────────
    final reelStopMatch = RegExp(r'reel[_\-]?stop[_\-]?(\d)?|stop[_\-]?reel[_\-]?(\d)?').firstMatch(baseName);
    if (reelStopMatch != null || baseName.contains('reel_stop') || baseName.contains('reelstop')) {
      category = AssetCategory.reelStop;
      suggestedBus = 'reels';
      confidence = 0.9;

      // Extract reel index if present
      final indexMatch = RegExp(r'(\d)').firstMatch(baseName);
      if (indexMatch != null) {
        reelIndex = int.tryParse(indexMatch.group(1)!);
        if (reelIndex != null && reelIndex >= 0 && reelIndex <= 4) {
          suggestedStage = 'REEL_STOP_$reelIndex';
          suggestedPan = _reelIndexToPan(reelIndex);
          confidence = 0.95;
        }
      } else {
        suggestedStage = 'REEL_STOP';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REEL SPIN detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('reel_spin') || baseName.contains('reelspin') || baseName.contains('spinning')) {
      category = AssetCategory.reelSpin;
      suggestedStage = 'REEL_SPIN_LOOP';
      suggestedBus = 'reels';
      confidence = 0.9;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SPIN detection (spin_start, spin_button, etc.)
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('spin') && !baseName.contains('free')) {
      category = AssetCategory.spin;
      suggestedBus = 'sfx';
      confidence = 0.8;

      if (baseName.contains('start') || baseName.contains('press') || baseName.contains('click')) {
        suggestedStage = 'SPIN_START';
        phase = StagePhase.start;
      } else if (baseName.contains('stop') || baseName.contains('end')) {
        suggestedStage = 'SPIN_END';
        phase = StagePhase.end;
      } else {
        suggestedStage = 'SPIN_START';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WIN detection (win_small, win_big, mega_win, etc.)
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('win')) {
      category = AssetCategory.win;
      suggestedBus = 'wins';
      confidence = 0.85;

      // Detect win tier
      if (baseName.contains('ultra')) {
        winTier = WinTier.ultra;
        suggestedStage = 'WIN_ULTRA';
      } else if (baseName.contains('epic')) {
        winTier = WinTier.epic;
        suggestedStage = 'WIN_EPIC';
      } else if (baseName.contains('mega')) {
        winTier = WinTier.mega;
        suggestedStage = 'WIN_MEGA';
      } else if (baseName.contains('big') || baseName.contains('large')) {
        winTier = WinTier.big;
        suggestedStage = 'WIN_BIG';
      } else if (baseName.contains('medium') || baseName.contains('med')) {
        winTier = WinTier.medium;
        suggestedStage = 'WIN_MEDIUM';
      } else if (baseName.contains('small') || baseName.contains('minor')) {
        winTier = WinTier.small;
        suggestedStage = 'WIN_SMALL';
      } else {
        suggestedStage = 'WIN_PRESENT';
      }

      // Detect phase
      if (baseName.contains('start') || baseName.contains('intro')) {
        phase = StagePhase.start;
        suggestedStage = '${suggestedStage}_START';
      } else if (baseName.contains('loop')) {
        phase = StagePhase.loop;
        suggestedStage = '${suggestedStage}_LOOP';
      } else if (baseName.contains('end') || baseName.contains('outro')) {
        phase = StagePhase.end;
        suggestedStage = '${suggestedStage}_END';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MUSIC detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('music') || baseName.contains('bgm') || baseName.contains('theme') || baseName.contains('soundtrack')) {
      category = AssetCategory.music;
      suggestedBus = 'music';
      confidence = 0.9;

      final audioContext = AudioContextService.instance.detectContextFromAudio(path);
      switch (audioContext) {
        case AudioContext.freeSpins:
          suggestedStage = 'FS_MUSIC';
          featureType = FeatureType.freeSpins;
        case AudioContext.bonus:
          suggestedStage = 'BONUS_MUSIC';
          featureType = FeatureType.bonus;
        case AudioContext.holdWin:
          suggestedStage = 'HOLD_MUSIC';
          featureType = FeatureType.holdAndWin;
        case AudioContext.jackpot:
          suggestedStage = 'JACKPOT_MUSIC';
        case AudioContext.baseGame:
        case AudioContext.unknown:
          suggestedStage = 'MUSIC_BASE';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FEATURE detection (free spins, bonus, hold & win)
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('fs_') || baseName.contains('freespin') || baseName.contains('free_spin')) {
      category = AssetCategory.feature;
      featureType = FeatureType.freeSpins;
      suggestedBus = 'sfx';
      confidence = 0.85;

      if (baseName.contains('trigger') || baseName.contains('intro')) {
        suggestedStage = 'FS_TRIGGER';
        phase = StagePhase.trigger;
      } else if (baseName.contains('start') || baseName.contains('enter')) {
        suggestedStage = 'FS_ENTER';
        phase = StagePhase.start;
      } else if (baseName.contains('spin')) {
        suggestedStage = 'FS_SPIN';
        phase = StagePhase.step;
      } else if (baseName.contains('end') || baseName.contains('exit') || baseName.contains('outro')) {
        suggestedStage = 'FS_EXIT';
        phase = StagePhase.exit;
      } else {
        suggestedStage = 'FS_TRIGGER';
      }
    }

    else if (baseName.contains('bonus')) {
      category = AssetCategory.feature;
      featureType = FeatureType.bonus;
      suggestedBus = 'sfx';
      confidence = 0.85;

      if (baseName.contains('trigger') || baseName.contains('intro')) {
        suggestedStage = 'BONUS_TRIGGER';
        phase = StagePhase.trigger;
      } else if (baseName.contains('start') || baseName.contains('enter')) {
        suggestedStage = 'BONUS_ENTER';
        phase = StagePhase.start;
      } else if (baseName.contains('end') || baseName.contains('exit') || baseName.contains('complete')) {
        suggestedStage = 'BONUS_EXIT';
        phase = StagePhase.exit;
      } else {
        suggestedStage = 'BONUS_TRIGGER';
      }
    }

    else if (baseName.contains('hold') || baseName.contains('respin')) {
      category = AssetCategory.feature;
      featureType = FeatureType.holdAndWin;
      suggestedBus = 'sfx';
      confidence = 0.85;

      if (baseName.contains('trigger') || baseName.contains('start')) {
        suggestedStage = 'HOLD_TRIGGER';
        phase = StagePhase.trigger;
      } else if (baseName.contains('spin') || baseName.contains('respin')) {
        suggestedStage = 'HOLD_SPIN';
        phase = StagePhase.step;
      } else if (baseName.contains('end') || baseName.contains('exit') || baseName.contains('complete')) {
        suggestedStage = 'HOLD_EXIT';
        phase = StagePhase.exit;
      } else if (baseName.contains('lock') || baseName.contains('land')) {
        suggestedStage = 'HOLD_SYMBOL_LOCK';
      } else {
        suggestedStage = 'HOLD_TRIGGER';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CASCADE detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('cascade') || baseName.contains('tumble') || baseName.contains('avalanche')) {
      category = AssetCategory.cascade;
      suggestedBus = 'sfx';
      confidence = 0.85;

      if (baseName.contains('start') || baseName.contains('trigger')) {
        suggestedStage = 'CASCADE_START';
        phase = StagePhase.start;
      } else if (baseName.contains('step') || baseName.contains('drop') || baseName.contains('fall')) {
        suggestedStage = 'CASCADE_STEP';
        phase = StagePhase.step;
      } else if (baseName.contains('end') || baseName.contains('stop')) {
        suggestedStage = 'CASCADE_END';
        phase = StagePhase.end;
      } else if (baseName.contains('pop') || baseName.contains('explode') || baseName.contains('destroy')) {
        suggestedStage = 'CASCADE_SYMBOL_POP';
      } else {
        suggestedStage = 'CASCADE_STEP';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // JACKPOT detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('jackpot') || baseName.contains('grand') || baseName.contains('major') || baseName.contains('mini_jp')) {
      category = AssetCategory.jackpot;
      suggestedBus = 'wins';
      confidence = 0.9;

      if (baseName.contains('grand')) {
        suggestedStage = 'JACKPOT_GRAND';
      } else if (baseName.contains('major')) {
        suggestedStage = 'JACKPOT_MAJOR';
      } else if (baseName.contains('minor')) {
        suggestedStage = 'JACKPOT_MINOR';
      } else if (baseName.contains('mini')) {
        suggestedStage = 'JACKPOT_MINI';
      } else {
        suggestedStage = 'JACKPOT_TRIGGER';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SYMBOL detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('symbol') || baseName.contains('wild') || baseName.contains('scatter')) {
      category = AssetCategory.symbol;
      suggestedBus = 'sfx';
      confidence = 0.8;

      if (baseName.contains('wild')) {
        suggestedStage = 'WILD_LAND';
      } else if (baseName.contains('scatter')) {
        suggestedStage = 'SCATTER_LAND';
      } else if (baseName.contains('land')) {
        suggestedStage = 'SYMBOL_LAND';
      } else if (baseName.contains('expand')) {
        suggestedStage = 'WILD_EXPAND';
      } else {
        suggestedStage = 'SYMBOL_LAND';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UI detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('ui_') || baseName.contains('button') || baseName.contains('click') || baseName.contains('hover')) {
      category = AssetCategory.ui;
      suggestedBus = 'ui';
      confidence = 0.8;

      if (baseName.contains('click') || baseName.contains('press')) {
        suggestedStage = 'UI_BUTTON_PRESS';
      } else if (baseName.contains('hover')) {
        suggestedStage = 'UI_BUTTON_HOVER';
      } else {
        suggestedStage = 'UI_GENERIC';
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AMBIENCE detection
    // ─────────────────────────────────────────────────────────────────────────
    else if (baseName.contains('amb') || baseName.contains('ambient') || baseName.contains('atmosphere')) {
      category = AssetCategory.ambience;
      suggestedBus = 'ambience';
      suggestedStage = 'AMBIENT_LOOP';
      confidence = 0.85;
    }

    return ParsedAudioAsset(
      path: path,
      category: category,
      reelIndex: reelIndex,
      winTier: winTier,
      featureType: featureType,
      phase: phase,
      suggestedStage: suggestedStage,
      suggestedBus: suggestedBus,
      suggestedPan: suggestedPan,
      confidence: confidence,
    );
  }

  /// Convert reel index (0-4) to pan value (-0.8 to +0.8)
  double _reelIndexToPan(int reelIndex) {
    // 5 reels: 0=-0.8, 1=-0.4, 2=0.0, 3=+0.4, 4=+0.8
    return (reelIndex - 2) * 0.4;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. REEL SET GENERATOR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate events for all 5 reels from a single audio file
  AutomationResult generateReelSet({
    required String audioPath,
    int reelCount = 5,
    String baseStage = 'REEL_STOP',
    String bus = 'reels',
    double baseVolume = 1.0,
  }) {
    final events = <AutoEventSpec>[];
    final warnings = <String>[];

    for (int i = 0; i < reelCount; i++) {
      final pan = _reelIndexToPan(i);
      events.add(AutoEventSpec(
        eventId: '${baseStage}_$i',
        stage: '${baseStage}_$i',
        bus: bus,
        audioPath: audioPath,
        volume: baseVolume,
        pan: pan,
        priority: 60 + i, // Slightly increasing priority for later reels
        metadata: {'reelIndex': i, 'generatedBy': 'reelSetGenerator'},
      ));
    }

    return AutomationResult(
      events: events,
      summary: 'Generated $reelCount reel stop events with auto-pan (-0.8 to +0.8)',
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. WIN TIER ESCALATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate escalating win tier events from audio files
  AutomationResult generateWinTierSet({
    required Map<WinTier, String> audioByTier,
    String bus = 'wins',
  }) {
    final events = <AutoEventSpec>[];
    final warnings = <String>[];

    // Volume scaling per tier
    const volumeScale = {
      WinTier.small: 0.7,
      WinTier.medium: 0.8,
      WinTier.big: 0.9,
      WinTier.mega: 1.0,
      WinTier.epic: 1.0,
      WinTier.ultra: 1.0,
    };

    // Priority per tier
    const priorityScale = {
      WinTier.small: 40,
      WinTier.medium: 50,
      WinTier.big: 60,
      WinTier.mega: 70,
      WinTier.epic: 80,
      WinTier.ultra: 90,
    };

    for (final tier in WinTier.values) {
      final audioPath = audioByTier[tier];
      if (audioPath == null) {
        warnings.add('No audio for ${tier.name} tier');
        continue;
      }

      final stageName = 'WIN_${tier.name.toUpperCase()}';
      events.add(AutoEventSpec(
        eventId: stageName.toLowerCase(),
        stage: stageName,
        bus: bus,
        audioPath: audioPath,
        volume: volumeScale[tier] ?? 1.0,
        priority: priorityScale[tier] ?? 50,
        metadata: {'winTier': tier.name, 'generatedBy': 'winTierEscalation'},
      ));
    }

    return AutomationResult(
      events: events,
      summary: 'Generated ${events.length} win tier events with volume escalation',
      warnings: warnings,
    );
  }

  /// Auto-detect win tiers from a list of audio paths
  Map<WinTier, String> detectWinTiersFromPaths(List<String> paths) {
    final result = <WinTier, String>{};

    for (final path in paths) {
      final parsed = parseAsset(path);
      if (parsed.winTier != null) {
        result[parsed.winTier!] = path;
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. MUSIC CONTEXT PAIRS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate music transition pair (STOP old + PLAY new)
  AutomationResult generateMusicTransitionPair({
    required String newMusicPath,
    required String oldMusicContext, // e.g., 'base', 'fs', 'bonus'
    required String triggerStage, // e.g., 'FS_TRIGGER'
    String bus = 'music',
  }) {
    final events = <AutoEventSpec>[];
    final parsed = parseAsset(newMusicPath);

    // 1. STOP old music
    events.add(AutoEventSpec(
      eventId: 'stop_${oldMusicContext}_music',
      stage: triggerStage,
      bus: bus,
      audioPath: '', // No audio for stop action
      actionType: ActionType.stop,
      stopTarget: bus,
      priority: 100, // High priority - stop first
      metadata: {
        'isStopAction': true,
        'stopsContext': oldMusicContext,
        'generatedBy': 'musicTransitionPair',
      },
    ));

    // 2. PLAY new music
    events.add(AutoEventSpec(
      eventId: 'play_${parsed.suggestedStage.toLowerCase()}',
      stage: triggerStage,
      bus: bus,
      audioPath: newMusicPath,
      actionType: ActionType.play,
      loop: true,
      priority: 99, // Just after stop
      metadata: {
        'startsContext': parsed.featureType?.name ?? 'unknown',
        'generatedBy': 'musicTransitionPair',
      },
    ));

    return AutomationResult(
      events: events,
      summary: 'Generated music transition: STOP $oldMusicContext → PLAY ${parsed.suggestedStage}',
    );
  }

  /// Generate complete music context flow (enter + exit)
  AutomationResult generateMusicContextFlow({
    required String contextMusicPath,
    required String baseMusicPath,
    required String contextName, // 'fs', 'bonus', 'hold'
    required String enterStage, // 'FS_TRIGGER'
    required String exitStage, // 'FS_EXIT'
  }) {
    final events = <AutoEventSpec>[];

    // Enter: Stop base → Play context
    final enterResult = generateMusicTransitionPair(
      newMusicPath: contextMusicPath,
      oldMusicContext: 'base',
      triggerStage: enterStage,
    );
    events.addAll(enterResult.events);

    // Exit: Stop context → Play base
    final exitResult = generateMusicTransitionPair(
      newMusicPath: baseMusicPath,
      oldMusicContext: contextName,
      triggerStage: exitStage,
    );
    events.addAll(exitResult.events);

    return AutomationResult(
      events: events,
      summary: 'Generated complete music flow for $contextName (4 events: enter STOP+PLAY, exit STOP+PLAY)',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. CASCADE STEP GENERATOR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate cascade step events with escalating intensity
  AutomationResult generateCascadeSteps({
    required String baseAudioPath,
    int stepCount = 10,
    String bus = 'sfx',
    double volumeEscalation = 0.05, // Volume increase per step
    double pitchEscalation = 0.02, // Pitch increase per step (0.02 = 2%)
  }) {
    final events = <AutoEventSpec>[];

    // Start event
    events.add(AutoEventSpec(
      eventId: 'cascade_start',
      stage: 'CASCADE_START',
      bus: bus,
      audioPath: baseAudioPath,
      volume: 0.8,
      priority: 50,
      metadata: {'cascadeStep': 0, 'generatedBy': 'cascadeGenerator'},
    ));

    // Step events with escalation
    for (int i = 1; i <= stepCount; i++) {
      final volume = math.min(1.0, 0.8 + (i * volumeEscalation));
      events.add(AutoEventSpec(
        eventId: 'cascade_step_$i',
        stage: 'CASCADE_STEP',
        bus: bus,
        audioPath: baseAudioPath,
        volume: volume,
        priority: 50 + i,
        metadata: {
          'cascadeStep': i,
          'pitchMultiplier': 1.0 + (i * pitchEscalation),
          'generatedBy': 'cascadeGenerator',
        },
      ));
    }

    // End event
    events.add(AutoEventSpec(
      eventId: 'cascade_end',
      stage: 'CASCADE_END',
      bus: bus,
      audioPath: baseAudioPath,
      volume: 1.0,
      priority: 60,
      metadata: {'cascadeStep': stepCount + 1, 'generatedBy': 'cascadeGenerator'},
    ));

    return AutomationResult(
      events: events,
      summary: 'Generated ${events.length} cascade events (start + $stepCount steps + end) with volume escalation',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. FLOW TEMPLATES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all available flow templates
  List<FlowTemplate> getFlowTemplates() => _flowTemplates;

  /// Get template by ID
  FlowTemplate? getTemplate(String id) {
    try {
      return _flowTemplates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Apply flow template with provided audio assets
  AutomationResult applyFlowTemplate({
    required String templateId,
    required Map<String, String> audioByStage, // stage → audioPath
  }) {
    final template = getTemplate(templateId);
    if (template == null) {
      return AutomationResult(
        events: [],
        summary: 'Template not found: $templateId',
        warnings: ['Unknown template ID'],
      );
    }

    final events = <AutoEventSpec>[];
    final warnings = <String>[];

    for (final stage in template.stages) {
      final audioPath = audioByStage[stage.stage];
      if (audioPath == null) {
        if (!stage.isOptional) {
          warnings.add('Missing audio for required stage: ${stage.stage}');
        }
        continue;
      }

      events.add(AutoEventSpec(
        eventId: stage.stage.toLowerCase(),
        stage: stage.stage,
        bus: stage.bus,
        audioPath: audioPath,
        volume: stage.defaultVolume,
        pan: stage.defaultPan,
        metadata: {
          'templateId': templateId,
          'generatedBy': 'flowTemplate',
        },
      ));
    }

    return AutomationResult(
      events: events,
      summary: 'Applied template "${template.name}": ${events.length}/${template.stages.length} stages filled',
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. BATCH FOLDER IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyze a batch of audio files and suggest assignments
  AutomationResult analyzeBatch(List<String> audioPaths) {
    final events = <AutoEventSpec>[];
    final warnings = <String>[];
    final usedStages = <String>{};

    for (final path in audioPaths) {
      final parsed = parseAsset(path);

      // Check for stage conflicts
      if (usedStages.contains(parsed.suggestedStage)) {
        warnings.add('Duplicate stage detected: ${parsed.suggestedStage} (${path.split('/').last})');
      }
      usedStages.add(parsed.suggestedStage);

      // Determine action type
      final audioContext = AudioContextService.instance;
      final autoAction = audioContext.determineAutoAction(
        audioPath: path,
        stage: parsed.suggestedStage,
      );

      events.add(AutoEventSpec(
        eventId: parsed.suggestedStage.toLowerCase(),
        stage: parsed.suggestedStage,
        bus: parsed.suggestedBus,
        audioPath: path,
        pan: parsed.suggestedPan,
        actionType: autoAction.actionType,
        stopTarget: autoAction.stopTarget,
        loop: parsed.category == AssetCategory.music || parsed.category == AssetCategory.ambience,
        metadata: {
          'category': parsed.category.name,
          'confidence': parsed.confidence,
          'generatedBy': 'batchImport',
        },
      ));
    }

    // Sort by category for better organization
    events.sort((a, b) {
      final catA = a.metadata['category'] as String? ?? 'unknown';
      final catB = b.metadata['category'] as String? ?? 'unknown';
      return catA.compareTo(catB);
    });

    return AutomationResult(
      events: events,
      summary: 'Analyzed ${audioPaths.length} files → ${events.length} events suggested',
      warnings: warnings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOW TEMPLATE DEFINITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static const _flowTemplates = [
    // ─────────────────────────────────────────────────────────────────────────
    // SPIN FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'spin_basic',
      name: 'Basic Spin Flow',
      description: 'Essential spin cycle: start → spin loop → reel stops',
      category: FlowCategory.spin,
      stages: [
        FlowTemplateStage(stage: 'SPIN_START', bus: 'sfx', expectedAssetType: AssetCategory.spin, hint: 'Button press / spin initiate'),
        FlowTemplateStage(stage: 'REEL_SPIN_LOOP', bus: 'reels', expectedAssetType: AssetCategory.reelSpin, hint: 'Looping reel spin sound'),
        FlowTemplateStage(stage: 'REEL_STOP_0', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: -0.8, hint: 'First reel stop'),
        FlowTemplateStage(stage: 'REEL_STOP_1', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: -0.4, hint: 'Second reel stop'),
        FlowTemplateStage(stage: 'REEL_STOP_2', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.0, hint: 'Center reel stop'),
        FlowTemplateStage(stage: 'REEL_STOP_3', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.4, hint: 'Fourth reel stop'),
        FlowTemplateStage(stage: 'REEL_STOP_4', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.8, hint: 'Last reel stop'),
      ],
    ),

    FlowTemplate(
      id: 'spin_complete',
      name: 'Complete Spin Flow',
      description: 'Full spin cycle with anticipation and win evaluation',
      category: FlowCategory.spin,
      stages: [
        FlowTemplateStage(stage: 'SPIN_START', bus: 'sfx', expectedAssetType: AssetCategory.spin),
        FlowTemplateStage(stage: 'REEL_SPIN_LOOP', bus: 'reels', expectedAssetType: AssetCategory.reelSpin),
        FlowTemplateStage(stage: 'ANTICIPATION_START', bus: 'sfx', expectedAssetType: AssetCategory.feature, isOptional: true),
        FlowTemplateStage(stage: 'REEL_STOP_0', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: -0.8),
        FlowTemplateStage(stage: 'REEL_STOP_1', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: -0.4),
        FlowTemplateStage(stage: 'REEL_STOP_2', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.0),
        FlowTemplateStage(stage: 'REEL_STOP_3', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.4),
        FlowTemplateStage(stage: 'REEL_STOP_4', bus: 'reels', expectedAssetType: AssetCategory.reelStop, defaultPan: 0.8),
        FlowTemplateStage(stage: 'WIN_EVAL', bus: 'sfx', expectedAssetType: AssetCategory.win, isOptional: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // WIN FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'win_tiers',
      name: 'Win Tier Flow',
      description: 'All win tiers from small to ultra',
      category: FlowCategory.win,
      stages: [
        FlowTemplateStage(stage: 'WIN_SMALL', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 0.7),
        FlowTemplateStage(stage: 'WIN_MEDIUM', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 0.8),
        FlowTemplateStage(stage: 'WIN_BIG', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 0.9),
        FlowTemplateStage(stage: 'WIN_MEGA', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 1.0),
        FlowTemplateStage(stage: 'WIN_EPIC', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 1.0, isOptional: true),
        FlowTemplateStage(stage: 'WIN_ULTRA', bus: 'wins', expectedAssetType: AssetCategory.win, defaultVolume: 1.0, isOptional: true),
      ],
    ),

    FlowTemplate(
      id: 'win_presentation',
      name: 'Win Presentation Flow',
      description: 'Win line display and rollup sequence',
      category: FlowCategory.win,
      stages: [
        FlowTemplateStage(stage: 'WIN_LINE_SHOW', bus: 'sfx', expectedAssetType: AssetCategory.win),
        FlowTemplateStage(stage: 'WIN_SYMBOL_HIGHLIGHT', bus: 'sfx', expectedAssetType: AssetCategory.symbol, isOptional: true),
        FlowTemplateStage(stage: 'ROLLUP_START', bus: 'sfx', expectedAssetType: AssetCategory.win),
        FlowTemplateStage(stage: 'ROLLUP_TICK', bus: 'sfx', expectedAssetType: AssetCategory.win),
        FlowTemplateStage(stage: 'ROLLUP_END', bus: 'sfx', expectedAssetType: AssetCategory.win),
        FlowTemplateStage(stage: 'WIN_COLLECT', bus: 'sfx', expectedAssetType: AssetCategory.win, isOptional: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // FREE SPINS FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'freespins_complete',
      name: 'Free Spins Complete Flow',
      description: 'Full free spins feature with music transitions',
      category: FlowCategory.feature,
      stages: [
        FlowTemplateStage(stage: 'FS_TRIGGER', bus: 'sfx', expectedAssetType: AssetCategory.feature, hint: 'Scatter land / trigger'),
        FlowTemplateStage(stage: 'MUSIC_BASE_STOP', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Stop base music'),
        FlowTemplateStage(stage: 'FS_INTRO', bus: 'sfx', expectedAssetType: AssetCategory.feature, hint: 'Intro fanfare'),
        FlowTemplateStage(stage: 'FS_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Free spins music loop'),
        FlowTemplateStage(stage: 'FS_SPIN', bus: 'sfx', expectedAssetType: AssetCategory.spin, isOptional: true),
        FlowTemplateStage(stage: 'FS_WIN', bus: 'wins', expectedAssetType: AssetCategory.win, isOptional: true),
        FlowTemplateStage(stage: 'FS_RETRIGGER', bus: 'sfx', expectedAssetType: AssetCategory.feature, isOptional: true),
        FlowTemplateStage(stage: 'FS_OUTRO', bus: 'sfx', expectedAssetType: AssetCategory.feature, hint: 'Outro / total win'),
        FlowTemplateStage(stage: 'FS_MUSIC_STOP', bus: 'music', expectedAssetType: AssetCategory.music),
        FlowTemplateStage(stage: 'MUSIC_BASE', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Resume base music'),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // CASCADE FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'cascade_basic',
      name: 'Cascade/Tumble Flow',
      description: 'Cascading reels / avalanche mechanic',
      category: FlowCategory.cascade,
      stages: [
        FlowTemplateStage(stage: 'CASCADE_START', bus: 'sfx', expectedAssetType: AssetCategory.cascade),
        FlowTemplateStage(stage: 'CASCADE_SYMBOL_POP', bus: 'sfx', expectedAssetType: AssetCategory.cascade, hint: 'Symbols explode/disappear'),
        FlowTemplateStage(stage: 'CASCADE_STEP', bus: 'sfx', expectedAssetType: AssetCategory.cascade, hint: 'Symbols fall'),
        FlowTemplateStage(stage: 'CASCADE_LAND', bus: 'sfx', expectedAssetType: AssetCategory.cascade, hint: 'Symbols land', isOptional: true),
        FlowTemplateStage(stage: 'CASCADE_END', bus: 'sfx', expectedAssetType: AssetCategory.cascade),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // HOLD & WIN FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'holdwin_complete',
      name: 'Hold & Win Complete Flow',
      description: 'Hold & Win / Respins feature',
      category: FlowCategory.feature,
      stages: [
        FlowTemplateStage(stage: 'HOLD_TRIGGER', bus: 'sfx', expectedAssetType: AssetCategory.feature),
        FlowTemplateStage(stage: 'HOLD_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music),
        FlowTemplateStage(stage: 'HOLD_SPIN', bus: 'reels', expectedAssetType: AssetCategory.reelSpin),
        FlowTemplateStage(stage: 'HOLD_SYMBOL_LOCK', bus: 'sfx', expectedAssetType: AssetCategory.symbol, hint: 'Coin/symbol locks'),
        FlowTemplateStage(stage: 'HOLD_RESPIN_RESET', bus: 'sfx', expectedAssetType: AssetCategory.feature, hint: 'Respins counter reset'),
        FlowTemplateStage(stage: 'HOLD_JACKPOT_UPGRADE', bus: 'wins', expectedAssetType: AssetCategory.jackpot, isOptional: true),
        FlowTemplateStage(stage: 'HOLD_COMPLETE', bus: 'sfx', expectedAssetType: AssetCategory.feature),
        FlowTemplateStage(stage: 'HOLD_TOTAL_WIN', bus: 'wins', expectedAssetType: AssetCategory.win),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // JACKPOT FLOW
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'jackpot_tiers',
      name: 'Jackpot Tiers Flow',
      description: 'All jackpot tiers (Mini, Minor, Major, Grand)',
      category: FlowCategory.jackpot,
      stages: [
        FlowTemplateStage(stage: 'JACKPOT_TRIGGER', bus: 'sfx', expectedAssetType: AssetCategory.jackpot),
        FlowTemplateStage(stage: 'JACKPOT_MINI', bus: 'wins', expectedAssetType: AssetCategory.jackpot, defaultVolume: 0.8),
        FlowTemplateStage(stage: 'JACKPOT_MINOR', bus: 'wins', expectedAssetType: AssetCategory.jackpot, defaultVolume: 0.9),
        FlowTemplateStage(stage: 'JACKPOT_MAJOR', bus: 'wins', expectedAssetType: AssetCategory.jackpot, defaultVolume: 1.0),
        FlowTemplateStage(stage: 'JACKPOT_GRAND', bus: 'wins', expectedAssetType: AssetCategory.jackpot, defaultVolume: 1.0),
        FlowTemplateStage(stage: 'JACKPOT_COLLECT', bus: 'sfx', expectedAssetType: AssetCategory.jackpot, isOptional: true),
      ],
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // MUSIC CONTEXTS
    // ─────────────────────────────────────────────────────────────────────────
    FlowTemplate(
      id: 'music_contexts',
      name: 'Music Contexts Flow',
      description: 'All game music contexts',
      category: FlowCategory.music,
      stages: [
        FlowTemplateStage(stage: 'MUSIC_BASE', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Base game music'),
        FlowTemplateStage(stage: 'MUSIC_TENSION', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Near win / anticipation', isOptional: true),
        FlowTemplateStage(stage: 'FS_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Free spins music'),
        FlowTemplateStage(stage: 'BONUS_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Bonus game music', isOptional: true),
        FlowTemplateStage(stage: 'HOLD_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Hold & Win music', isOptional: true),
        FlowTemplateStage(stage: 'BIGWIN_MUSIC', bus: 'music', expectedAssetType: AssetCategory.music, hint: 'Big win celebration', isOptional: true),
      ],
    ),
  ];
}

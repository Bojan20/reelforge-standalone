/// Stage Group Service for Batch Import
///
/// Groups related slot stages together for efficient batch audio assignment.
/// Supports fuzzy matching of audio filenames to stages.

import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Three main stage groups for simplified batch import
enum StageGroup {
  spinsAndReels,
  wins,
  musicAndFeatures,
}

/// Extension for StageGroup display properties
extension StageGroupExtension on StageGroup {
  String get displayName {
    switch (this) {
      case StageGroup.spinsAndReels:
        return 'Spins & Reels';
      case StageGroup.wins:
        return 'Wins';
      case StageGroup.musicAndFeatures:
        return 'Music & Features';
    }
  }

  String get description {
    switch (this) {
      case StageGroup.spinsAndReels:
        return 'UI elements, spin button, reel spinning, reel stops';
      case StageGroup.wins:
        return 'All win types: small, big, mega, epic, ultra, jackpot';
      case StageGroup.musicAndFeatures:
        return 'Background music, free spins, bonus, cascade, features';
    }
  }

  String get icon {
    switch (this) {
      case StageGroup.spinsAndReels:
        return '🎰';
      case StageGroup.wins:
        return '🏆';
      case StageGroup.musicAndFeatures:
        return '🎵';
    }
  }
}

/// A match result with confidence score
class StageMatch {
  final String audioFileName;
  final String audioPath;
  final String stage;
  final double confidence;
  final List<String> matchedKeywords;

  const StageMatch({
    required this.audioFileName,
    required this.audioPath,
    required this.stage,
    required this.confidence,
    required this.matchedKeywords,
  });

  /// Generated event name (e.g., 'onReelLand1' for REEL_STOP_0)
  String get eventName => generateEventName(stage);

  bool get isHighConfidence => confidence >= 0.7;
  bool get isMediumConfidence => confidence >= 0.4 && confidence < 0.7;
  bool get isLowConfidence => confidence < 0.4;

  @override
  String toString() =>
      'StageMatch($audioFileName → $stage ($eventName), ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Result of batch matching operation
class BatchMatchResult {
  final StageGroup group;
  final List<StageMatch> matched;
  final List<UnmatchedFile> unmatched;

  const BatchMatchResult({
    required this.group,
    required this.matched,
    required this.unmatched,
  });

  int get totalFiles => matched.length + unmatched.length;
  int get matchedCount => matched.length;
  int get unmatchedCount => unmatched.length;
  double get matchRate =>
      totalFiles > 0 ? matchedCount / totalFiles : 0.0;
}

/// An unmatched file with suggested stages
class UnmatchedFile {
  final String audioFileName;
  final String audioPath;
  final List<StageSuggestion> suggestions;

  const UnmatchedFile({
    required this.audioFileName,
    required this.audioPath,
    required this.suggestions,
  });

  bool get hasSuggestions => suggestions.isNotEmpty;
  StageSuggestion? get topSuggestion =>
      suggestions.isNotEmpty ? suggestions.first : null;
}

/// A suggested stage for an unmatched file
class StageSuggestion {
  final String stage;
  final double confidence;
  final String reason;

  const StageSuggestion({
    required this.stage,
    required this.confidence,
    required this.reason,
  });
}

/// Stage definition with keywords for fuzzy matching
class _StageDefinition {
  final String stage;
  final List<String> keywords;
  final List<String> suffixes;
  final int priority;
  /// Keywords that MUST be present for a match (all must match)
  final List<String> requiredKeywords;
  /// Keywords that EXCLUDE this stage if present
  final List<String> excludeKeywords;
  /// If true, requires explicit number in filename (for REEL_STOP_0-4)
  final bool requiresNumber;
  /// Specific number required (e.g., 0 for REEL_STOP_0)
  final int? specificNumber;
  /// Event name template (e.g., 'onReelLand{n}' for REEL_STOP_0-4)
  final String? eventNameTemplate;

  const _StageDefinition({
    required this.stage,
    required this.keywords,
    this.suffixes = const [],
    this.priority = 50,
    this.requiredKeywords = const [],
    this.excludeKeywords = const [],
    this.requiresNumber = false,
    this.specificNumber,
    this.eventNameTemplate,
  });
}

/// Generates standard event name from stage name
/// Examples:
/// - SPIN_START → onUiSpin
/// - REEL_STOP → onReelStop
/// - REEL_STOP_0 → onReelLand1 (1-indexed for display)
/// - REEL_SPIN_LOOP → onReelSpin
/// - WIN_BIG → onWinBig
String generateEventName(String stage) {
  // Special cases with custom naming
  const customNames = {
    // UI Events
    'SPIN_START': 'onUiSpin',
    'SPIN_END': 'onUiSpinEnd',
    'UI_BUTTON_PRESS': 'onUiButtonPress',
    'UI_BUTTON_HOVER': 'onUiButtonHover',
    'UI_PANEL_OPEN': 'onUiOpen',
    'UI_PANEL_CLOSE': 'onUiClose',

    // Reel Events (landing uses 1-indexed: Reel 1-5)
    'REEL_SPIN_LOOP': 'onReelSpin',
    'REEL_STOP': 'onReelStop',
    'REEL_STOP_0': 'onReelLand1',
    'REEL_STOP_1': 'onReelLand2',
    'REEL_STOP_2': 'onReelLand3',
    'REEL_STOP_3': 'onReelLand4',
    'REEL_STOP_4': 'onReelLand5',

    // Symbol Events
    'SYMBOL_LAND': 'onSymbolLand',
    'WILD_LAND': 'onWildLand',
    'SCATTER_LAND': 'onScatterLand',

    // Anticipation
    'ANTICIPATION_TENSION': 'onAnticipationStart',
    'ANTICIPATION_MISS': 'onAnticipationMiss',

    // Win Events — unified WIN_PRESENT_1..5 system
    'NO_WIN': 'onNoWin',
    'WIN_PRESENT_LOW': 'onWinPresentLow',
    'WIN_PRESENT_EQUAL': 'onWinPresentEqual',
    'WIN_PRESENT_1': 'onWinPresent1',
    'WIN_PRESENT_2': 'onWinPresent2',
    'WIN_PRESENT_3': 'onWinPresent3',
    'WIN_PRESENT_4': 'onWinPresent4',
    'WIN_PRESENT_5': 'onWinPresent5',
    'BIG_WIN_TRIGGER': 'onBigWinTrigger',
    'BIG_WIN_START': 'onBigWinIntro',
    'BIG_WIN_LOOP': 'onBigWinLoop',
    'BIG_WIN_COINS': 'onBigWinCoins',
    'BIG_WIN_IMPACT': 'onBigWinImpact',
    'BIG_WIN_UPGRADE': 'onBigWinUpgrade',
    'BIG_WIN_END': 'onBigWinEnd',
    'BIG_WIN_OUTRO': 'onBigWinOutro',
    'BIG_WIN_TIER_1': 'onBigWinTier1',
    'BIG_WIN_TIER_2': 'onBigWinTier2',
    'BIG_WIN_TIER_3': 'onBigWinTier3',
    'BIG_WIN_TIER_4': 'onBigWinTier4',
    'BIG_WIN_TIER_5': 'onBigWinTier5',
    'WIN_FANFARE': 'onWinFanfare',
    'WIN_LINE_SHOW': 'onWinLineShow',
    'WIN_LINE_HIDE': 'onWinLineHide',
    'WIN_LINE_CYCLE': 'onWinLineCycle',
    'WIN_SYMBOL_HIGHLIGHT': 'onWinSymbolHighlight',
    'WIN_EVAL': 'onWinEval',
    'WIN_DETECTED': 'onWinDetected',
    'WIN_CALCULATE': 'onWinCalculate',
    'WIN_COLLECT': 'onWinCollect',
    'WIN_PRESENT_END': 'onWinPresentEnd',
    'PAYLINE_HIGHLIGHT': 'onPaylineHighlight',
    // Per-symbol highlights
    'WIN_SYMBOL_HIGHLIGHT_HP': 'onWinSymHighlightHp',
    'WIN_SYMBOL_HIGHLIGHT_HP1': 'onWinSymHighlightHp1',
    'WIN_SYMBOL_HIGHLIGHT_HP2': 'onWinSymHighlightHp2',
    'WIN_SYMBOL_HIGHLIGHT_HP3': 'onWinSymHighlightHp3',
    'WIN_SYMBOL_HIGHLIGHT_HP4': 'onWinSymHighlightHp4',
    'WIN_SYMBOL_HIGHLIGHT_LP': 'onWinSymHighlightLp',
    'WIN_SYMBOL_HIGHLIGHT_LP1': 'onWinSymHighlightLp1',
    'WIN_SYMBOL_HIGHLIGHT_LP2': 'onWinSymHighlightLp2',
    'WIN_SYMBOL_HIGHLIGHT_LP3': 'onWinSymHighlightLp3',
    'WIN_SYMBOL_HIGHLIGHT_LP4': 'onWinSymHighlightLp4',
    'WIN_SYMBOL_HIGHLIGHT_LP5': 'onWinSymHighlightLp5',
    'WIN_SYMBOL_HIGHLIGHT_LP6': 'onWinSymHighlightLp6',
    'WIN_SYMBOL_HIGHLIGHT_WILD': 'onWinSymHighlightWild',
    'WIN_SYMBOL_HIGHLIGHT_SCATTER': 'onWinSymHighlightScatter',
    'WIN_SYMBOL_HIGHLIGHT_BONUS': 'onWinSymHighlightBonus',
    // Scatter lands (sequential)
    'SCATTER_LAND_1': 'onScatterLand1',
    'SCATTER_LAND_2': 'onScatterLand2',
    'SCATTER_LAND_3': 'onScatterLand3',
    'SCATTER_LAND_4': 'onScatterLand4',
    'SCATTER_LAND_5': 'onScatterLand5',
    'SCATTER_COLLECT': 'onScatterCollect',

    // Rollup
    'ROLLUP_START': 'onRollupStart',
    'ROLLUP_TICK': 'onRollupTick',
    'ROLLUP_TICK_FAST': 'onRollupTickFast',
    'ROLLUP_TICK_SLOW': 'onRollupTickSlow',
    'ROLLUP_END': 'onRollupEnd',
    'ROLLUP_SKIP': 'onRollupSkip',
    'ROLLUP_ACCELERATION': 'onRollupAcceleration',
    'ROLLUP_DECELERATION': 'onRollupDeceleration',

    // Jackpot
    'JACKPOT_TRIGGER': 'onJackpotTrigger',
    'JACKPOT_AWARD': 'onJackpotAward',
    'JACKPOT_MINI': 'onJackpotMini',
    'JACKPOT_MINOR': 'onJackpotMinor',
    'JACKPOT_MAJOR': 'onJackpotMajor',
    'JACKPOT_GRAND': 'onJackpotGrand',

    // Coins
    'COIN_BURST': 'onCoinBurst',
    'COIN_DROP': 'onCoinDrop',
    'COIN_SHOWER': 'onCoinShower',
    'COIN_RAIN': 'onCoinRain',
    'COIN_LAND': 'onCoinLand',
    'COIN_LOCK': 'onCoinLock',
    'COIN_COLLECT': 'onCoinCollect',
    'COIN_VALUE_REVEAL': 'onCoinValueReveal',

    // Gamble
    'GAMBLE_ENTER': 'onGambleEnter',
    'GAMBLE_WIN': 'onGambleWin',
    'GAMBLE_LOSE': 'onGambleLose',
    'GAMBLE_COLLECT': 'onGambleCollect',
    'GAMBLE_EXIT': 'onGambleExit',

    // Music — unified MUSIC_{SCENE}_{TYPE} naming
    // Layer = complete arrangement, Extension = additive overlay
    'GAME_START': 'onGameStart',
    // Base game
    'MUSIC_BASE_INTRO': 'onMusicBaseIntro',
    'MUSIC_BASE_OUTRO': 'onMusicBaseOutro',
    'MUSIC_BASE_L1': 'onMusicBaseL1',
    'MUSIC_BASE_L2': 'onMusicBaseL2',
    'MUSIC_BASE_L3': 'onMusicBaseL3',
    'MUSIC_BASE_L4': 'onMusicBaseL4',
    'MUSIC_BASE_L5': 'onMusicBaseL5',
    // Free spins
    'MUSIC_FS_INTRO': 'onMusicFsIntro',
    'MUSIC_FS_OUTRO': 'onMusicFsOutro',
    'MUSIC_FS_L1': 'onMusicFsL1',
    'MUSIC_FS_L2': 'onMusicFsL2',
    'MUSIC_FS_L3': 'onMusicFsL3',
    'MUSIC_FS_L4': 'onMusicFsL4',
    'MUSIC_FS_L5': 'onMusicFsL5',
    // Bonus
    'MUSIC_BONUS_INTRO': 'onMusicBonusIntro',
    'MUSIC_BONUS_OUTRO': 'onMusicBonusOutro',
    'MUSIC_BONUS_L1': 'onMusicBonusL1',
    'MUSIC_BONUS_L2': 'onMusicBonusL2',
    'MUSIC_BONUS_L3': 'onMusicBonusL3',
    'MUSIC_BONUS_L4': 'onMusicBonusL4',
    'MUSIC_BONUS_L5': 'onMusicBonusL5',
    // Hold & Spin
    'MUSIC_HOLD_INTRO': 'onMusicHoldIntro',
    'MUSIC_HOLD_OUTRO': 'onMusicHoldOutro',
    'MUSIC_HOLD_L1': 'onMusicHoldL1',
    'MUSIC_HOLD_L2': 'onMusicHoldL2',
    'MUSIC_HOLD_L3': 'onMusicHoldL3',
    'MUSIC_HOLD_L4': 'onMusicHoldL4',
    'MUSIC_HOLD_L5': 'onMusicHoldL5',
    // Jackpot
    'MUSIC_JACKPOT_INTRO': 'onMusicJackpotIntro',
    'MUSIC_JACKPOT_OUTRO': 'onMusicJackpotOutro',
    'MUSIC_JACKPOT_L1': 'onMusicJackpotL1',
    'MUSIC_JACKPOT_L2': 'onMusicJackpotL2',
    'MUSIC_JACKPOT_L3': 'onMusicJackpotL3',
    'MUSIC_JACKPOT_L4': 'onMusicJackpotL4',
    'MUSIC_JACKPOT_L5': 'onMusicJackpotL5',
    // Gamble
    'MUSIC_GAMBLE_INTRO': 'onMusicGambleIntro',
    'MUSIC_GAMBLE_OUTRO': 'onMusicGambleOutro',
    'MUSIC_GAMBLE_L1': 'onMusicGambleL1',
    'MUSIC_GAMBLE_L2': 'onMusicGambleL2',
    'MUSIC_GAMBLE_L3': 'onMusicGambleL3',
    'MUSIC_GAMBLE_L4': 'onMusicGambleL4',
    'MUSIC_GAMBLE_L5': 'onMusicGambleL5',
    // Reveal
    'MUSIC_REVEAL_INTRO': 'onMusicRevealIntro',
    'MUSIC_REVEAL_OUTRO': 'onMusicRevealOutro',
    'MUSIC_REVEAL_L1': 'onMusicRevealL1',
    'MUSIC_REVEAL_L2': 'onMusicRevealL2',
    'MUSIC_REVEAL_L3': 'onMusicRevealL3',
    'MUSIC_REVEAL_L4': 'onMusicRevealL4',
    'MUSIC_REVEAL_L5': 'onMusicRevealL5',
    // Legacy compat
    'MUSIC_BASE': 'onMusicBaseL1',
    'MUSIC_FREESPINS': 'onMusicFsL1',
    'MUSIC_BONUS': 'onMusicBonusL1',
    'MUSIC_HOLD': 'onMusicHoldL1',
    'MUSIC_BIG_WIN': 'onMusicBigwinL1',
    'MUSIC_JACKPOT': 'onMusicJackpotL1',
    'MUSIC_GAMBLE': 'onMusicGambleL1',

    // Ambient — per scene
    'AMBIENT_BASE': 'onAmbientBase',
    'AMBIENT_FS': 'onAmbientFs',
    'AMBIENT_BONUS': 'onAmbientBonus',
    'AMBIENT_HOLD': 'onAmbientHold',
    'AMBIENT_BIGWIN': 'onAmbientBigwin',
    'AMBIENT_JACKPOT': 'onAmbientJackpot',
    'AMBIENT_GAMBLE': 'onAmbientGamble',
    'AMBIENT_REVEAL': 'onAmbientReveal',

    // Free Spins
    'FREESPIN_TRIGGER': 'onFreeSpinTrigger',
    'FREESPIN_START': 'onFreeSpinStart',
    'FREESPIN_SPIN': 'onFreeSpinSpin',
    'FREESPIN_END': 'onFreeSpinEnd',
    'FREESPIN_MUSIC': 'onMusicFreeSpins',
    'FREESPIN_RETRIGGER': 'onFreeSpinRetrigger',

    // Bonus
    'BONUS_TRIGGER': 'onBonusTrigger',
    'BONUS_ENTER': 'onBonusEnter',
    'BONUS_STEP': 'onBonusStep',
    'BONUS_EXIT': 'onBonusExit',
    'BONUS_MUSIC': 'onMusicBonus',

    // Cascade
    'CASCADE_START': 'onCascadeStart',
    'CASCADE_STEP': 'onCascadeStep',
    'CASCADE_POP': 'onCascadePop',
    'CASCADE_END': 'onCascadeEnd',

    // Hold & Win
    'HOLD_TRIGGER': 'onHoldTrigger',
    'HOLD_START': 'onHoldStart',
    'HOLD_SPIN': 'onHoldSpin',
    'HOLD_LOCK': 'onHoldLock',
    'HOLD_END': 'onHoldEnd',
    'HOLD_MUSIC': 'onMusicHold',

    // Multiplier
    'MULTIPLIER_INCREASE': 'onMultiplierIncrease',
    'MULTIPLIER_APPLY': 'onMultiplierApply',

    // Feature
    'FEATURE_ENTER': 'onFeatureEnter',
    'FEATURE_EXIT': 'onFeatureExit',

    // Attract
    'ATTRACT_LOOP': 'onAttractLoop',
  };

  // Check for custom name first
  if (customNames.containsKey(stage)) {
    return customNames[stage]!;
  }

  // Fallback: convert STAGE_NAME to onStageName
  final parts = stage.split('_');
  if (parts.isEmpty) return 'on${stage.capitalize()}';

  final camelCase = parts.map((p) => p.toLowerCase().capitalize()).join('');
  return 'on$camelCase';
}

/// Extension for String capitalize
extension StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

/// Service for stage group management and fuzzy matching
class StageGroupService {
  StageGroupService._();
  static final StageGroupService instance = StageGroupService._();

  /// DEBUG: Test matching with verbose output
  /// Call this to diagnose matching issues
  void debugTestMatch(String fileName) {
    final normalized = _normalizeFileName(fileName);
    if (kDebugMode) debugPrint('═══════════════════════════════════════════════════════════════');
    if (kDebugMode) debugPrint('[DEBUG] Testing match for: "$fileName"');
    if (kDebugMode) debugPrint('[DEBUG] Normalized: "$normalized"');
    if (kDebugMode) debugPrint('───────────────────────────────────────────────────────────────');

    for (final group in StageGroup.values) {
      final definitions = _stageDefinitions[group] ?? [];
      for (final def in definitions) {
        final (confidence, keywords) = _calculateConfidence(normalized, def);
        if (confidence > 0 || keywords.any((k) => k.startsWith('EXCLUDED:') || k.startsWith('MISSING'))) {
          final status = confidence > 0 ? '✅' : '❌';
          if (kDebugMode) debugPrint('$status ${def.stage}: ${(confidence * 100).toStringAsFixed(0)}% — ${keywords.join(", ")}');
        }
      }
    }

    // Final result
    final match = matchSingleFile('/fake/$fileName.wav');
    if (match != null) {
      if (kDebugMode) debugPrint('───────────────────────────────────────────────────────────────');
      if (kDebugMode) debugPrint('[RESULT] MATCHED: ${match.stage} (${(match.confidence * 100).toStringAsFixed(0)}%)');
      if (kDebugMode) debugPrint('[RESULT] Event name: ${match.eventName}');
    } else {
      if (kDebugMode) debugPrint('───────────────────────────────────────────────────────────────');
      if (kDebugMode) debugPrint('[RESULT] NO MATCH');
    }
    if (kDebugMode) debugPrint('═══════════════════════════════════════════════════════════════');
  }

  /// RUN ALL TESTS: Verify matching logic with common filenames
  /// Returns true if all tests pass
  bool runMatchingTests() {
    if (kDebugMode) debugPrint('\n╔═══════════════════════════════════════════════════════════════╗');
    if (kDebugMode) debugPrint('║        BATCH IMPORT MATCHING TESTS v2.0                        ║');
    if (kDebugMode) debugPrint('╚═══════════════════════════════════════════════════════════════╝\n');

    final tests = <(String fileName, String expectedStage)>[
      // ── SPIN_START (UI spin button) ──
      ('spin_button', 'SPIN_START'),
      ('spin_click', 'SPIN_START'),
      ('ui_spin', 'SPIN_START'),
      ('spin_press', 'SPIN_START'),
      ('spin_start', 'SPIN_START'),
      ('button_spin_click', 'SPIN_START'),

      // ── REEL_SPIN_LOOP (spinning loop) ──
      ('reel_spin', 'REEL_SPIN_LOOP'),
      ('reel_spinning', 'REEL_SPIN_LOOP'),
      ('reel_spin_loop', 'REEL_SPIN_LOOP'),
      ('reels_spinning', 'REEL_SPIN_LOOP'),
      ('spin_loop', 'REEL_SPIN_LOOP'),
      ('spins_loop', 'REEL_SPIN_LOOP'),

      // ── REEL_STOP (generic stop) ──
      ('reel_stop', 'REEL_STOP'),
      ('reel_land', 'REEL_STOP'),
      ('reelstop', 'REEL_STOP'),

      // ── REEL_STOP_0-4 (specific stops) ──
      ('reel_stop_0', 'REEL_STOP_0'),
      ('reel_stop_1', 'REEL_STOP_1'),
      ('reel_stop_2', 'REEL_STOP_2'),
      ('reel_land_3', 'REEL_STOP_3'),
      ('reel_stop_4', 'REEL_STOP_4'),

      // ── WIN sounds ──
      ('win_big', 'WIN_PRESENT_4'),
      ('win_mega', 'WIN_PRESENT_5'),
      ('win_small', 'WIN_PRESENT_1'),

      // ── MUSIC ──
      ('music_base', 'MUSIC_BASE_L1'),
      ('base_music_loop', 'MUSIC_BASE_L1'),
      ('mus_bg_lvl_1', 'MUSIC_BASE_L1'),
      ('mus_bg_lvl_2', 'MUSIC_BASE_L2'),
      ('mus_bg_lvl_3', 'MUSIC_BASE_L3'),
      ('mus_bw', 'BIG_WIN_START'),
      ('mus_rs', 'MUSIC_HOLD_L1'),

      // ── FREESPIN ──
      ('freespin_start', 'FREESPIN_START'),
      ('freespin_music', 'MUSIC_FS_L1'),
    ];

    int passed = 0;
    int failed = 0;
    final failures = <String>[];

    for (final (fileName, expectedStage) in tests) {
      final match = matchSingleFile('/fake/$fileName.wav');
      final actualStage = match?.stage;

      if (actualStage == expectedStage) {
        passed++;
        if (kDebugMode) debugPrint('✅ "$fileName" → $expectedStage');
      } else {
        failed++;
        final msg = '❌ "$fileName" → Expected: $expectedStage, Got: ${actualStage ?? "NO MATCH"}';
        if (kDebugMode) debugPrint(msg);
        failures.add(msg);
      }
    }

    if (kDebugMode) debugPrint('\n────────────────────────────────────────────────────────────────');
    if (kDebugMode) debugPrint('RESULTS: $passed passed, $failed failed');
    if (failures.isNotEmpty) {
      if (kDebugMode) debugPrint('\nFAILURES:');
      for (final f in failures) {
        if (kDebugMode) debugPrint('  $f');
      }
    }
    if (kDebugMode) debugPrint('────────────────────────────────────────────────────────────────\n');

    return failed == 0;
  }

  /// Alias map: substring → stage. Checked BEFORE fuzzy matching.
  /// Uses original filename (lowercased, without extension/prefix number).
  /// If ANY alias key is found as substring in the filename → instant match.
  /// SORTED by specificity — longest aliases first to avoid partial matches.
  static const Map<String, String> _aliasMap = {
    // ═══════════════════════════════════════════════════════════════════
    // BASE GAME MUSIC — all layer naming conventions
    // ═══════════════════════════════════════════════════════════════════
    'mus_bg_lvl_1': 'MUSIC_BASE_L1',
    'mus_bg_lvl_2': 'MUSIC_BASE_L2',
    'mus_bg_lvl_3': 'MUSIC_BASE_L3',
    'mus_bg_lvl_4': 'MUSIC_BASE_L4',
    'mus_bg_lvl_5': 'MUSIC_BASE_L5',
    'mus_bg_level_1': 'MUSIC_BASE_L1',
    'mus_bg_level_2': 'MUSIC_BASE_L2',
    'mus_bg_level_3': 'MUSIC_BASE_L3',
    'mus_bg_level_4': 'MUSIC_BASE_L4',
    'mus_bg_level_5': 'MUSIC_BASE_L5',
    'mus_bg_l1': 'MUSIC_BASE_L1',
    'mus_bg_l2': 'MUSIC_BASE_L2',
    'mus_bg_l3': 'MUSIC_BASE_L3',
    'mus_bg_l4': 'MUSIC_BASE_L4',
    'mus_bg_l5': 'MUSIC_BASE_L5',
    'music_base_l1': 'MUSIC_BASE_L1',
    'music_base_l2': 'MUSIC_BASE_L2',
    'music_base_l3': 'MUSIC_BASE_L3',
    'music_base_l4': 'MUSIC_BASE_L4',
    'music_base_l5': 'MUSIC_BASE_L5',
    'base_music_layer_1': 'MUSIC_BASE_L1',
    'base_music_layer_2': 'MUSIC_BASE_L2',
    'base_music_layer_3': 'MUSIC_BASE_L3',
    'base_music_layer_4': 'MUSIC_BASE_L4',
    'base_music_layer_5': 'MUSIC_BASE_L5',
    'basegame_music': 'MUSIC_BASE_L1',
    'base_game_music': 'MUSIC_BASE_L1',
    'bgm_loop': 'MUSIC_BASE_L1',
    'music_loop': 'MUSIC_BASE_L1',
    'musicloop': 'MUSIC_BASE_L1',
    'mus_bg_intro': 'MUSIC_BASE_INTRO',
    'mus_bg_outro': 'MUSIC_BASE_OUTRO',
    'base_music_intro': 'MUSIC_BASE_INTRO',
    'base_music_outro': 'MUSIC_BASE_OUTRO',

    // ═══════════════════════════════════════════════════════════════════
    // FREE SPINS MUSIC — all naming conventions
    // ═══════════════════════════════════════════════════════════════════
    'mus_fs_lvl_1': 'MUSIC_FS_L1',
    'mus_fs_lvl_2': 'MUSIC_FS_L2',
    'mus_fs_lvl_3': 'MUSIC_FS_L3',
    'mus_fs_lvl_4': 'MUSIC_FS_L4',
    'mus_fs_lvl_5': 'MUSIC_FS_L5',
    'mus_fs_l1': 'MUSIC_FS_L1',
    'mus_fs_l2': 'MUSIC_FS_L2',
    'mus_fs_l3': 'MUSIC_FS_L3',
    'mus_fs_l4': 'MUSIC_FS_L4',
    'mus_fs_l5': 'MUSIC_FS_L5',
    'mus_fs_start': 'MUSIC_FS_L1',
    'mus_fs_loop': 'MUSIC_FS_L1',
    'mus_fs_intro': 'MUSIC_FS_INTRO',
    'mus_fs_outro': 'MUSIC_FS_OUTRO',
    'mus_fs': 'MUSIC_FS_L1',
    'freespins_music': 'MUSIC_FS_L1',
    'free_spins_music': 'MUSIC_FS_L1',
    'freespin_music': 'MUSIC_FS_L1',

    // ═══════════════════════════════════════════════════════════════════
    // BONUS MUSIC — all naming conventions
    // ═══════════════════════════════════════════════════════════════════
    'mus_bonus_lvl_1': 'MUSIC_BONUS_L1',
    'mus_bonus_lvl_2': 'MUSIC_BONUS_L2',
    'mus_bonus_lvl_3': 'MUSIC_BONUS_L3',
    'mus_bonus_lvl_4': 'MUSIC_BONUS_L4',
    'mus_bonus_lvl_5': 'MUSIC_BONUS_L5',
    'mus_bonus_l1': 'MUSIC_BONUS_L1',
    'mus_bonus_l2': 'MUSIC_BONUS_L2',
    'mus_bonus_l3': 'MUSIC_BONUS_L3',
    'mus_bonus_l4': 'MUSIC_BONUS_L4',
    'mus_bonus_l5': 'MUSIC_BONUS_L5',
    'mus_bonus_intro': 'MUSIC_BONUS_INTRO',
    'mus_bonus_outro': 'MUSIC_BONUS_OUTRO',
    'mus_bonus': 'MUSIC_BONUS_L1',
    'bonus_music': 'MUSIC_BONUS_L1',

    // ═══════════════════════════════════════════════════════════════════
    // HOLD & SPIN MUSIC — all naming conventions
    // ═══════════════════════════════════════════════════════════════════
    'mus_hold_lvl_1': 'MUSIC_HOLD_L1',
    'mus_hold_lvl_2': 'MUSIC_HOLD_L2',
    'mus_hold_lvl_3': 'MUSIC_HOLD_L3',
    'mus_hold_lvl_4': 'MUSIC_HOLD_L4',
    'mus_hold_lvl_5': 'MUSIC_HOLD_L5',
    'mus_hold_l1': 'MUSIC_HOLD_L1',
    'mus_hold_l2': 'MUSIC_HOLD_L2',
    'mus_hold_l3': 'MUSIC_HOLD_L3',
    'mus_hold_l4': 'MUSIC_HOLD_L4',
    'mus_hold_l5': 'MUSIC_HOLD_L5',
    'mus_hold_intro': 'MUSIC_HOLD_INTRO',
    'mus_hold_outro': 'MUSIC_HOLD_OUTRO',
    'mus_hold': 'MUSIC_HOLD_L1',
    'mus_rs': 'MUSIC_HOLD_L1',
    'hold_music': 'MUSIC_HOLD_L1',
    'respin_music': 'MUSIC_HOLD_L1',

    // ═══════════════════════════════════════════════════════════════════
    // BIG WIN — all naming conventions map to BIG_WIN_* stages
    // ═══════════════════════════════════════════════════════════════════
    'mus_bw_intro': 'BIG_WIN_START',
    'mus_bw_end': 'BIG_WIN_END',
    'mus_bw_outro': 'BIG_WIN_OUTRO',
    'mus_bw': 'BIG_WIN_START',
    'bigwin_music': 'BIG_WIN_START',
    'win_music': 'BIG_WIN_START',

    // ═══════════════════════════════════════════════════════════════════
    // JACKPOT MUSIC — all naming conventions
    // ═══════════════════════════════════════════════════════════════════
    'mus_jackpot_l1': 'MUSIC_JACKPOT_L1',
    'mus_jackpot_l2': 'MUSIC_JACKPOT_L2',
    'mus_jackpot_l3': 'MUSIC_JACKPOT_L3',
    'mus_jackpot_l4': 'MUSIC_JACKPOT_L4',
    'mus_jackpot_l5': 'MUSIC_JACKPOT_L5',
    'mus_jackpot_intro': 'MUSIC_JACKPOT_INTRO',
    'mus_jackpot_outro': 'MUSIC_JACKPOT_OUTRO',
    'mus_jackpot': 'MUSIC_JACKPOT_L1',
    'mus_jp': 'MUSIC_JACKPOT_L1',
    'jackpot_music': 'MUSIC_JACKPOT_L1',

    // ═══════════════════════════════════════════════════════════════════
    // GAMBLE MUSIC
    // ═══════════════════════════════════════════════════════════════════
    'mus_gamble': 'MUSIC_GAMBLE_L1',
    'mus_gam': 'MUSIC_GAMBLE_L1',
    'gamble_music': 'MUSIC_GAMBLE_L1',

    // ═══════════════════════════════════════════════════════════════════
    // REVEAL MUSIC
    // ═══════════════════════════════════════════════════════════════════
    'mus_reveal': 'MUSIC_REVEAL_L1',
    'mus_rev': 'MUSIC_REVEAL_L1',
    'reveal_music': 'MUSIC_REVEAL_L1',

    // ═══════════════════════════════════════════════════════════════════
    // AMBIENT — per scene
    // ═══════════════════════════════════════════════════════════════════
    'ambient_base': 'AMBIENT_BASE',
    'ambient_basegame': 'AMBIENT_BASE',
    'ambient_bg': 'AMBIENT_BASE',
    'amb_base': 'AMBIENT_BASE',
    'amb_bg': 'AMBIENT_BASE',
    'ambient_freespins': 'AMBIENT_FS',
    'ambient_free_spins': 'AMBIENT_FS',
    'ambient_fs': 'AMBIENT_FS',
    'amb_fs': 'AMBIENT_FS',
    'ambient_bonus': 'AMBIENT_BONUS',
    'amb_bonus': 'AMBIENT_BONUS',
    'ambient_hold': 'AMBIENT_HOLD',
    'amb_hold': 'AMBIENT_HOLD',
    'ambient_bigwin': 'AMBIENT_BIGWIN',
    'ambient_big_win': 'AMBIENT_BIGWIN',
    'amb_bw': 'AMBIENT_BIGWIN',
    'ambient_jackpot': 'AMBIENT_JACKPOT',
    'amb_jackpot': 'AMBIENT_JACKPOT',
    'amb_jp': 'AMBIENT_JACKPOT',
    'ambient_gamble': 'AMBIENT_GAMBLE',
    'amb_gamble': 'AMBIENT_GAMBLE',
    'ambient_reveal': 'AMBIENT_REVEAL',
    'amb_reveal': 'AMBIENT_REVEAL',

    // ═══════════════════════════════════════════════════════════════════
    // SPIN / REEL — special naming conventions
    // ═══════════════════════════════════════════════════════════════════
    // NOTE: reels_appear is NOT a spin loop — it's a visual reel animation sound
    // Removed: 'reels_appear': 'REEL_SPIN_LOOP' (was wrong binding)

    // ═══════════════════════════════════════════════════════════════════
    // SUSPENSE / ANTICIPATION
    // ═══════════════════════════════════════════════════════════════════
    'spins_susp': 'ANTICIPATION_TENSION',
    'suspense': 'ANTICIPATION_TENSION',

    // ═══════════════════════════════════════════════════════════════════
    // WIN — all legacy and modern naming → unified WIN_PRESENT_1..5
    // ═══════════════════════════════════════════════════════════════════
    'no_win': 'NO_WIN',
    'nowin': 'NO_WIN',
    'sfx_nowin': 'NO_WIN',
    'sfx_no_win': 'NO_WIN',
    // Legacy naming → WIN_PRESENT_1..5
    'quick_win': 'WIN_PRESENT_1',
    'small_win': 'WIN_PRESENT_1',
    'win_small': 'WIN_PRESENT_1',
    'sfx_win_small': 'WIN_PRESENT_1',
    'normal_win': 'WIN_PRESENT_2',
    'medium_win': 'WIN_PRESENT_2',
    'win_medium': 'WIN_PRESENT_2',
    'sfx_win_medium': 'WIN_PRESENT_2',
    'big_win': 'WIN_PRESENT_4',
    'win_big': 'WIN_PRESENT_4',
    'sfx_win_big': 'WIN_PRESENT_4',
    'mega_win': 'WIN_PRESENT_5',
    'win_mega': 'WIN_PRESENT_5',
    'sfx_win_mega': 'WIN_PRESENT_5',
    'epic_win': 'WIN_PRESENT_5',
    'win_epic': 'WIN_PRESENT_5',
    'sfx_win_epic': 'WIN_PRESENT_5',
    'ultra_win': 'WIN_PRESENT_5',
    'win_ultra': 'WIN_PRESENT_5',
    'sfx_win_ultra': 'WIN_PRESENT_5',
    'super_win': 'WIN_PRESENT_5',
    'max_win': 'WIN_PRESENT_5',

    // Win presentation tiers
    'win_present_low': 'WIN_PRESENT_LOW',
    'win_low': 'WIN_PRESENT_LOW',
    'sfx_win_low': 'WIN_PRESENT_LOW',
    'win_present_equal': 'WIN_PRESENT_EQUAL',
    'win_equal': 'WIN_PRESENT_EQUAL',
    'win_present_1': 'WIN_PRESENT_1',
    'win_tier_1': 'WIN_PRESENT_1',
    'sfx_win_1': 'WIN_PRESENT_1',
    'sfx_win_tier_1': 'WIN_PRESENT_1',
    'win_present_2': 'WIN_PRESENT_2',
    'win_tier_2': 'WIN_PRESENT_2',
    'sfx_win_2': 'WIN_PRESENT_2',
    'sfx_win_tier_2': 'WIN_PRESENT_2',
    'win_present_3': 'WIN_PRESENT_3',
    'win_tier_3': 'WIN_PRESENT_3',
    'sfx_win_3': 'WIN_PRESENT_3',
    'sfx_win_tier_3': 'WIN_PRESENT_3',
    'win_present_4': 'WIN_PRESENT_4',
    'win_tier_4': 'WIN_PRESENT_4',
    'sfx_win_4': 'WIN_PRESENT_4',
    'sfx_win_tier_4': 'WIN_PRESENT_4',
    'win_present_5': 'WIN_PRESENT_5',
    'win_tier_5': 'WIN_PRESENT_5',
    'sfx_win_5': 'WIN_PRESENT_5',
    'sfx_win_tier_5': 'WIN_PRESENT_5',

    // Win fanfare / celebration
    'win_fanfare': 'WIN_FANFARE',
    'sfx_win_fanfare': 'WIN_FANFARE',
    'win_celebration': 'WIN_FANFARE',
    'fanfare': 'WIN_FANFARE',
    'victory': 'WIN_FANFARE',

    // Win evaluation flow
    'win_eval': 'WIN_EVAL',
    'sfx_win_eval': 'WIN_EVAL',
    'evaluate_wins': 'WIN_EVAL',
    'win_detect': 'WIN_DETECTED',
    'win_detected': 'WIN_DETECTED',
    'win_calc': 'WIN_CALCULATE',
    'win_calculate': 'WIN_CALCULATE',
    'win_collect': 'WIN_COLLECT',
    'sfx_win_collect': 'WIN_COLLECT',
    'win_end': 'WIN_PRESENT_END',
    'win_present_end': 'WIN_PRESENT_END',

    // Paylines & Win Lines
    'payline': 'PAYLINE_HIGHLIGHT',
    'payline_highlight': 'PAYLINE_HIGHLIGHT',
    'pay_line': 'PAYLINE_HIGHLIGHT',
    'sfx_payline': 'PAYLINE_HIGHLIGHT',
    'sfx_pay_line': 'PAYLINE_HIGHLIGHT',
    'win_line': 'WIN_LINE_SHOW',
    'win_line_show': 'WIN_LINE_SHOW',
    'line_show': 'WIN_LINE_SHOW',
    'line_win': 'WIN_LINE_SHOW',
    'sfx_line_win': 'WIN_LINE_SHOW',
    'sfx_win_line': 'WIN_LINE_SHOW',
    'sfx_line_show': 'WIN_LINE_SHOW',
    'line_highlight': 'WIN_LINE_SHOW',
    'win_line_hide': 'WIN_LINE_HIDE',
    'line_hide': 'WIN_LINE_HIDE',
    'sfx_line_hide': 'WIN_LINE_HIDE',
    'win_line_cycle': 'WIN_LINE_CYCLE',
    'line_cycle': 'WIN_LINE_CYCLE',

    // Symbol highlights (generic + per-symbol)
    'symbol_highlight': 'WIN_SYMBOL_HIGHLIGHT',
    'win_highlight': 'WIN_SYMBOL_HIGHLIGHT',
    'sfx_symbol_highlight': 'WIN_SYMBOL_HIGHLIGHT',
    'sym_win': 'WIN_SYMBOL_HIGHLIGHT',
    'sym_highlight': 'WIN_SYMBOL_HIGHLIGHT',
    'sfx_hp1_win': 'WIN_SYMBOL_HIGHLIGHT_HP1',
    'sfx_hp2_win': 'WIN_SYMBOL_HIGHLIGHT_HP2',
    'sfx_hp3_win': 'WIN_SYMBOL_HIGHLIGHT_HP3',
    'sfx_hp4_win': 'WIN_SYMBOL_HIGHLIGHT_HP4',
    'sfx_lp1_win': 'WIN_SYMBOL_HIGHLIGHT_LP1',
    'sfx_lp2_win': 'WIN_SYMBOL_HIGHLIGHT_LP2',
    'sfx_lp3_win': 'WIN_SYMBOL_HIGHLIGHT_LP3',
    'sfx_lp4_win': 'WIN_SYMBOL_HIGHLIGHT_LP4',
    'sfx_lp5_win': 'WIN_SYMBOL_HIGHLIGHT_LP5',
    'sfx_lp6_win': 'WIN_SYMBOL_HIGHLIGHT_LP6',
    'sfx_wild_win': 'WIN_SYMBOL_HIGHLIGHT_WILD',
    'sfx_scatter_win': 'WIN_SYMBOL_HIGHLIGHT_SCATTER',
    'sfx_bonus_win': 'WIN_SYMBOL_HIGHLIGHT_BONUS',
    'hp1_win': 'WIN_SYMBOL_HIGHLIGHT_HP1',
    'hp2_win': 'WIN_SYMBOL_HIGHLIGHT_HP2',
    'hp3_win': 'WIN_SYMBOL_HIGHLIGHT_HP3',
    'hp4_win': 'WIN_SYMBOL_HIGHLIGHT_HP4',
    'lp1_win': 'WIN_SYMBOL_HIGHLIGHT_LP1',
    'lp2_win': 'WIN_SYMBOL_HIGHLIGHT_LP2',
    'lp3_win': 'WIN_SYMBOL_HIGHLIGHT_LP3',
    'lp4_win': 'WIN_SYMBOL_HIGHLIGHT_LP4',
    'lp5_win': 'WIN_SYMBOL_HIGHLIGHT_LP5',
    'lp6_win': 'WIN_SYMBOL_HIGHLIGHT_LP6',
    'wild_win': 'WIN_SYMBOL_HIGHLIGHT_WILD',
    'scatter_win': 'WIN_SYMBOL_HIGHLIGHT_SCATTER',
    'bonus_sym_win': 'WIN_SYMBOL_HIGHLIGHT_BONUS',

    // Symbol lands
    'symbol_land': 'SYMBOL_LAND',
    'sym_land': 'SYMBOL_LAND',
    'sfx_symbol_land': 'SYMBOL_LAND',
    'wild_land': 'WILD_LAND',
    'sfx_wild_land': 'WILD_LAND',
    'scatter_land': 'SCATTER_LAND',
    'sfx_scatter_land': 'SCATTER_LAND',
    'scatter_land_1': 'SCATTER_LAND_1',
    'scatter_land_2': 'SCATTER_LAND_2',
    'scatter_land_3': 'SCATTER_LAND_3',
    'scatter_land_4': 'SCATTER_LAND_4',
    'scatter_land_5': 'SCATTER_LAND_5',
    'sfx_scatter_1': 'SCATTER_LAND_1',
    'sfx_scatter_2': 'SCATTER_LAND_2',
    'sfx_scatter_3': 'SCATTER_LAND_3',
    'sfx_scatter_4': 'SCATTER_LAND_4',
    'sfx_scatter_5': 'SCATTER_LAND_5',

    // Rollup / Counter
    'rollup_start': 'ROLLUP_START',
    'sfx_rollup_start': 'ROLLUP_START',
    'rollup_tick': 'ROLLUP_TICK',
    'sfx_rollup_tick': 'ROLLUP_TICK',
    'sfx_rollup': 'ROLLUP_TICK',
    'rollup_end': 'ROLLUP_END',
    'sfx_rollup_end': 'ROLLUP_END',
    'rollup_skip': 'ROLLUP_SKIP',
    'sfx_rollup_skip': 'ROLLUP_SKIP',
    'rollup_fast': 'ROLLUP_TICK_FAST',
    'rollup_tick_fast': 'ROLLUP_TICK_FAST',
    'sfx_rollup_fast': 'ROLLUP_TICK_FAST',
    'rollup_slow': 'ROLLUP_TICK_SLOW',
    'rollup_tick_slow': 'ROLLUP_TICK_SLOW',
    'sfx_rollup_slow': 'ROLLUP_TICK_SLOW',
    'rollup_accel': 'ROLLUP_ACCELERATION',
    'rollup_decel': 'ROLLUP_DECELERATION',
    'countup': 'ROLLUP_TICK',
    'countup_start': 'ROLLUP_START',
    'countup_end': 'ROLLUP_END',
    'totalizer': 'ROLLUP_TICK',

    // Coins & Effects
    'coin_burst': 'COIN_BURST',
    'sfx_coin_burst': 'COIN_BURST',
    'coin_drop': 'COIN_DROP',
    'sfx_coin_drop': 'COIN_DROP',
    'coin_shower': 'COIN_SHOWER',
    'sfx_coin_shower': 'COIN_SHOWER',
    'coin_rain': 'COIN_RAIN',
    'sfx_coin_rain': 'COIN_RAIN',
    'coin_land': 'COIN_LAND',
    'sfx_coin_land': 'COIN_LAND',
    'coin_lock': 'COIN_LOCK',
    'sfx_coin_lock': 'COIN_LOCK',
    'coin_collect': 'COIN_COLLECT',
    'sfx_coin_collect': 'COIN_COLLECT',
    'coin_value': 'COIN_VALUE_REVEAL',
    'sfx_coin_value': 'COIN_VALUE_REVEAL',

    // Big Win celebration
    'big_win_intro': 'BIG_WIN_START',
    'sfx_bw_intro': 'BIG_WIN_START',
    'big_win_loop': 'BIG_WIN_LOOP',
    'sfx_bw_loop': 'BIG_WIN_LOOP',
    'big_win_end': 'BIG_WIN_END',
    'sfx_bw_end': 'BIG_WIN_END',
    'big_win_coins': 'BIG_WIN_COINS',
    'sfx_bw_coins': 'BIG_WIN_COINS',
    'big_win_impact': 'BIG_WIN_IMPACT',
    'sfx_bw_impact': 'BIG_WIN_IMPACT',
    'big_win_upgrade': 'BIG_WIN_UPGRADE',
    'sfx_bw_upgrade': 'BIG_WIN_UPGRADE',
    'big_win_outro': 'BIG_WIN_OUTRO',
    'sfx_bw_outro': 'BIG_WIN_OUTRO',
    'big_win_trigger': 'BIG_WIN_TRIGGER',
    'sfx_bw_trigger': 'BIG_WIN_TRIGGER',

    // Big Win tier stages
    'bw_tier_1': 'BIG_WIN_TIER_1',
    'bw_tier_2': 'BIG_WIN_TIER_2',
    'bw_tier_3': 'BIG_WIN_TIER_3',
    'bw_tier_4': 'BIG_WIN_TIER_4',
    'bw_tier_5': 'BIG_WIN_TIER_5',
    'big_win_tier_1': 'BIG_WIN_TIER_1',
    'big_win_tier_2': 'BIG_WIN_TIER_2',
    'big_win_tier_3': 'BIG_WIN_TIER_3',
    'big_win_tier_4': 'BIG_WIN_TIER_4',
    'big_win_tier_5': 'BIG_WIN_TIER_5',
    'sfx_bw_tier_1': 'BIG_WIN_TIER_1',
    'sfx_bw_tier_2': 'BIG_WIN_TIER_2',
    'sfx_bw_tier_3': 'BIG_WIN_TIER_3',
    'sfx_bw_tier_4': 'BIG_WIN_TIER_4',
    'sfx_bw_tier_5': 'BIG_WIN_TIER_5',

    // Scatter collect
    'scatter_collect': 'SCATTER_COLLECT',
    'sfx_scatter_collect': 'SCATTER_COLLECT',

    // Bonus
    'bonus_trigger': 'BONUS_TRIGGER',
    'sfx_bonus_trigger': 'BONUS_TRIGGER',
    'bonus_enter': 'BONUS_ENTER',
    'sfx_bonus_enter': 'BONUS_ENTER',
    'bonus_step': 'BONUS_STEP',
    'sfx_bonus_step': 'BONUS_STEP',
    'bonus_exit': 'BONUS_EXIT',
    'sfx_bonus_exit': 'BONUS_EXIT',

    // Gamble
    'gamble_win': 'GAMBLE_WIN',
    'sfx_gamble_win': 'GAMBLE_WIN',
    'gamble_lose': 'GAMBLE_LOSE',
    'sfx_gamble_lose': 'GAMBLE_LOSE',
    'gamble_collect': 'GAMBLE_COLLECT',
    'sfx_gamble_collect': 'GAMBLE_COLLECT',

    // Jackpot
    'jackpot_award': 'JACKPOT_AWARD',
    'sfx_jackpot': 'JACKPOT_AWARD',
    'sfx_jp_award': 'JACKPOT_AWARD',
  };

  /// Check alias map for instant match. Returns stage ID or null.
  ///
  /// Uses BOUNDARY-AWARE matching: alias must match at word boundaries
  /// (start/end of string, or adjacent to separators like _ - space).
  /// This prevents partial matches like "mus_rs" matching inside "mus_rs_end".
  String? _checkAlias(String audioPath) {
    final fileName = _extractFileName(audioPath).toLowerCase();
    // Try longest alias first to avoid partial matches
    final sortedAliases = _aliasMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in sortedAliases) {
      // Exact match (whole filename)
      if (fileName == alias) {
        return _aliasMap[alias];
      }
      // Boundary-aware: alias must be at start/end or bounded by separators
      final escaped = RegExp.escape(alias);
      final pattern = RegExp('(?:^|[-_\\s])$escaped(?:\$|[-_\\s])');
      if (pattern.hasMatch(fileName)) {
        return _aliasMap[alias];
      }
    }
    return null;
  }

  /// Stages grouped by StageGroup
  ///
  /// MATCHING LOGIC v2.0 — Intent-Based Matching
  ///
  /// Instead of simple keyword matching, we use INTENT patterns:
  /// - SPIN_START = UI spin button → requires 'spin' + UI indicators (button/click/press/ui/start)
  /// - REEL_SPIN_LOOP = Reel spinning loop → requires 'spin' + loop indicators (loop/roll/spinning)
  /// - REEL_STOP = Reel stop sound → requires 'stop/land' + reel indicators
  ///
  /// Priority: More specific patterns beat less specific ones.
  /// Exclusion: Based on conflicting intent, not individual keywords.
  static const Map<StageGroup, List<_StageDefinition>> _stageDefinitions = {
    // ═══════════════════════════════════════════════════════════════════
    // GROUP 1: SPINS & REELS
    // ═══════════════════════════════════════════════════════════════════
    StageGroup.spinsAndReels: [
      // ───────────────────────────────────────────────────────────────────
      // SPIN_START — UI spin button click sound
      // ───────────────────────────────────────────────────────────────────
      // INTENT: User clicks spin button → plays UI click sound
      // MATCHES: spin_button, spin_click, ui_spin, spin_press, spin_start
      // DOES NOT MATCH: reel_spin_loop (that's REEL_SPIN_LOOP)
      //
      // KEY INSIGHT: Even if 'reel' is in the name, if 'button/click/press/ui'
      // is ALSO present, it's still a UI spin sound!
      _StageDefinition(
        stage: 'SPIN_START',
        keywords: ['spin', 'start', 'button', 'press', 'click', 'ui', 'tap'],
        requiredKeywords: [], // At least one of: spin, button, click, press, ui
        suffixes: ['_start', '_press', '_click', '_spin', '_tap'],
        // Exclude: loop sounds, free spin indicators, animation/visual sounds
        excludeKeywords: ['loop', 'roll', 'spinning', 'stop', 'land',
          'fs', 'free', 'freespin', 'anim', 'animation', 'bonus',
          'feature', 'highlight', 'glow', 'music', 'bg'],
        priority: 95, // HIGH priority - UI sounds are important
      ),
      _StageDefinition(
        stage: 'SPIN_END',
        keywords: ['spin', 'end', 'complete', 'done', 'finish'],
        suffixes: ['_end', '_complete', '_done', '_finish'],
        excludeKeywords: ['reel', 'loop', 'start'],
        priority: 80,
      ),

      // ───────────────────────────────────────────────────────────────────
      // REEL_SPIN_LOOP — Reel spinning loop sound
      // ───────────────────────────────────────────────────────────────────
      // INTENT: Reels are spinning → plays looping spin sound
      // MATCHES: reel_spin, reel_spinning, reel_loop, spins_loop, spin_roll
      // DOES NOT MATCH: spin_button (that's SPIN_START)
      //
      // KEY INSIGHT: 'spin' (not just 'spinning') + 'loop/roll/reel' = REEL_SPIN_LOOP
      _StageDefinition(
        stage: 'REEL_SPIN_LOOP',
        keywords: ['spin', 'spinning', 'spins', 'loop', 'roll', 'reel', 'reels'],
        // Positive intent only: MUST have spin/reel + loop/motion
        requiredKeywords: [
          'spin|spinning|spins|reel|reels',  // reel/spin context
          'loop|spinning|roll|spin|spins',   // motion/loop context
        ],
        suffixes: ['_loop', '_spinning', '_spins', '_roll'],
        excludeKeywords: ['button', 'press', 'click', 'tap', 'ui', 'stop', 'land'],
        priority: 92,
      ),

      // ───────────────────────────────────────────────────────────────────
      // REEL_STOP — Generic reel stop/land sound (plays on ALL reel stops)
      // ───────────────────────────────────────────────────────────────────
      // INTENT: A reel stops → plays stop sound
      // MATCHES: reel_stop, reel_land, reelstop, spins_stop (WITHOUT specific number)
      // DOES NOT MATCH: reel_stop_0 (that's REEL_STOP_0)
      // NOTE: 'spin'/'spins' in name is OK if 'stop'/'land' is also present!
      _StageDefinition(
        stage: 'REEL_STOP',
        keywords: ['stop', 'land', 'spin', 'spins'],
        requiredKeywords: [],
        suffixes: ['_stop', '_land'],
        excludeKeywords: ['spinning', 'loop', 'roll', 'button', 'press', 'click',
          'highlight', 'glow', 'anim', 'animation', 'fs', 'free', 'bonus', 'music',
          'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: false,
        priority: 88,
      ),

      // ───────────────────────────────────────────────────────────────────
      // REEL_STOP_0-4 — Individual reel stop sounds
      // ───────────────────────────────────────────────────────────────────
      _StageDefinition(
        stage: 'REEL_STOP_0',
        keywords: ['stop', 'land', 'first', '1st'],
        requiredKeywords: [],
        suffixes: ['_0', '_first'],
        excludeKeywords: ['spinning', 'loop', 'highlight', 'glow', 'anim', 'animation',
          'fs', 'free', 'bonus', 'music', 'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: true,
        specificNumber: 0,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_1',
        keywords: ['stop', 'land', 'second', '2nd'],
        requiredKeywords: [],
        suffixes: ['_1', '_second'],
        excludeKeywords: ['spinning', 'loop', 'highlight', 'glow', 'anim', 'animation',
          'fs', 'free', 'bonus', 'music', 'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: true,
        specificNumber: 1,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_2',
        keywords: ['stop', 'land', 'third', '3rd', 'middle', 'center'],
        requiredKeywords: [],
        suffixes: ['_2', '_third', '_middle'],
        excludeKeywords: ['spinning', 'loop', 'highlight', 'glow', 'anim', 'animation',
          'fs', 'free', 'bonus', 'music', 'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: true,
        specificNumber: 2,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_3',
        keywords: ['stop', 'land', 'fourth', '4th'],
        requiredKeywords: [],
        suffixes: ['_3', '_fourth'],
        excludeKeywords: ['spinning', 'loop', 'highlight', 'glow', 'anim', 'animation',
          'fs', 'free', 'bonus', 'music', 'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: true,
        specificNumber: 3,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_4',
        keywords: ['stop', 'land', 'fifth', '5th', 'last', 'final'],
        requiredKeywords: [],
        suffixes: ['_4', '_fifth', '_last', '_final'],
        excludeKeywords: ['spinning', 'loop', 'highlight', 'glow', 'anim', 'animation',
          'fs', 'free', 'bonus', 'music', 'appear', 'scatter', 'wild', 'symbol', 'win', 'reveal'],
        requiresNumber: true,
        specificNumber: 4,
        priority: 87,
      ),

      // ───────────────────────────────────────────────────────────────────
      // UI_BUTTON_PRESS — Generic UI button (NOT spin button)
      // ───────────────────────────────────────────────────────────────────
      _StageDefinition(
        stage: 'UI_BUTTON_PRESS',
        keywords: ['ui', 'button', 'press', 'click', 'tap', 'btn', 'menu'],
        suffixes: ['_press', '_click', '_tap', '_ui'],
        excludeKeywords: ['spin', 'reel', 'win', 'bet'],
        priority: 70,
      ),
      _StageDefinition(
        stage: 'UI_BUTTON_HOVER',
        keywords: ['ui', 'button', 'hover', 'over', 'highlight'],
        suffixes: ['_hover', '_over'],
        priority: 60,
      ),
      _StageDefinition(
        stage: 'UI_PANEL_OPEN',
        keywords: ['ui', 'panel', 'open', 'show', 'menu'],
        suffixes: ['_open', '_show'],
        priority: 65,
      ),
      _StageDefinition(
        stage: 'UI_PANEL_CLOSE',
        keywords: ['ui', 'panel', 'close', 'hide'],
        suffixes: ['_close', '_hide'],
        priority: 65,
      ),

      // Anticipation
      _StageDefinition(
        stage: 'ANTICIPATION_TENSION',
        keywords: ['anticipation', 'antici', 'tension', 'buildup', 'suspense'],
        suffixes: ['_on', '_start', '_begin', '_tension'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'ANTICIPATION_MISS',
        keywords: ['anticipation', 'antici', 'miss', 'release'],
        suffixes: ['_off', '_end', '_stop', '_miss'],
        priority: 74,
      ),

      // Symbol lands
      _StageDefinition(
        stage: 'SYMBOL_LAND',
        keywords: ['symbol', 'land', 'drop'],
        suffixes: ['_land', '_drop'],
        priority: 72,
      ),
      _StageDefinition(
        stage: 'WILD_LAND',
        keywords: ['wild', 'land', 'drop', 'appear'],
        suffixes: ['_land', '_appear'],
        priority: 78,
      ),
      _StageDefinition(
        stage: 'SCATTER_LAND',
        keywords: ['scatter', 'land', 'drop', 'appear'],
        suffixes: ['_land', '_appear'],
        priority: 79,
      ),
    ],

    // ═══════════════════════════════════════════════════════════════════
    // GROUP 2: WINS
    // ═══════════════════════════════════════════════════════════════════
    StageGroup.wins: [
      // Win presentation
      _StageDefinition(
        stage: 'WIN_PRESENT',
        keywords: ['win', 'present', 'show', 'display'],
        requiredKeywords: ['win'],
        suffixes: ['_present', '_show'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 85,
      ),

      // Win tiers — unified WIN_PRESENT_1..5 system
      // Legacy names (small/medium/big/mega/epic/ultra) → WIN_PRESENT_1..5
      // ALL win definitions require 'win' token to prevent non-win files from matching
      _StageDefinition(
        stage: 'WIN_PRESENT_1',
        keywords: ['win', 'small', 'minor', 'low', 'tiny', 'quick'],
        requiredKeywords: ['win'],
        suffixes: ['_small', '_minor', '_low', '_quick'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'spin', 'line', 'collect'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_2',
        keywords: ['win', 'medium', 'med', 'normal', 'regular'],
        requiredKeywords: ['win'],
        suffixes: ['_medium', '_med', '_normal'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'spin', 'line', 'collect'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_4',
        keywords: ['win', 'big', 'large', 'great'],
        requiredKeywords: ['win'],
        suffixes: ['_big', '_large'],
        excludeKeywords: ['music', 'mus', 'panel', 'trn', 'transition', 'line', 'collect'],
        priority: 88,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_5',
        keywords: ['win', 'mega', 'huge', 'massive', 'epic', 'super', 'ultra', 'max', 'ultimate', 'extreme'],
        requiredKeywords: ['win'],
        suffixes: ['_mega', '_huge', '_epic', '_super', '_ultra', '_max'],
        excludeKeywords: ['music', 'mus', 'panel', 'trn', 'transition', 'line', 'collect'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'NO_WIN',
        keywords: ['no', 'win', 'loss', 'lose', 'empty'],
        requiredKeywords: ['no'],
        suffixes: ['_nowin', '_loss'],
        priority: 75,
      ),
      // Win presentation tiers (new UI stage IDs)
      _StageDefinition(
        stage: 'WIN_PRESENT_1',
        keywords: ['win', 'present', 'tier', '1'],
        requiredKeywords: ['win'],
        suffixes: ['_1'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_2',
        keywords: ['win', 'present', 'tier', '2'],
        requiredKeywords: ['win'],
        suffixes: ['_2'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_3',
        keywords: ['win', 'present', 'tier', '3'],
        requiredKeywords: ['win'],
        suffixes: ['_3'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 84,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_4',
        keywords: ['win', 'present', 'tier', '4'],
        requiredKeywords: ['win'],
        suffixes: ['_4'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 86,
      ),
      _StageDefinition(
        stage: 'WIN_PRESENT_5',
        keywords: ['win', 'present', 'tier', '5'],
        requiredKeywords: ['win'],
        suffixes: ['_5'],
        excludeKeywords: ['loop', 'music', 'mus', 'panel', 'trn', 'transition', 'reel', 'appear'],
        priority: 88,
      ),
      // Big Win celebration
      _StageDefinition(
        stage: 'BIG_WIN_START',
        keywords: ['big', 'win', 'intro', 'start'],
        requiredKeywords: ['big'],
        suffixes: ['_intro', '_start'],
        priority: 92,
      ),
      _StageDefinition(
        stage: 'BIG_WIN_LOOP',
        keywords: ['big', 'win', 'loop', 'main'],
        requiredKeywords: ['big'],
        suffixes: ['_loop', '_main'],
        priority: 91,
      ),
      _StageDefinition(
        stage: 'BIG_WIN_END',
        keywords: ['big', 'win', 'end', 'outro', 'finish'],
        requiredKeywords: ['big'],
        suffixes: ['_end', '_outro', '_finish'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'BIG_WIN_COINS',
        keywords: ['big', 'win', 'coins', 'shower', 'rain'],
        requiredKeywords: ['big'],
        suffixes: ['_coins', '_shower'],
        priority: 89,
      ),
      _StageDefinition(
        stage: 'WIN_FANFARE',
        keywords: ['win', 'fanfare', 'celebration', 'victory'],
        suffixes: ['_fanfare', '_celebration'],
        priority: 86,
      ),

      // Rollup
      _StageDefinition(
        stage: 'ROLLUP_START',
        keywords: ['rollup', 'roll', 'count', 'tally', 'start'],
        suffixes: ['_start', '_begin'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'ROLLUP_TICK',
        keywords: ['rollup', 'roll', 'tick', 'count', 'increment'],
        suffixes: ['_tick', '_count'],
        priority: 70,
      ),
      _StageDefinition(
        stage: 'ROLLUP_END',
        keywords: ['rollup', 'roll', 'end', 'complete', 'finish'],
        suffixes: ['_end', '_complete', '_finish'],
        priority: 76,
      ),

      // Win lines
      _StageDefinition(
        stage: 'WIN_LINE_SHOW',
        keywords: ['win', 'line', 'show', 'display', 'highlight'],
        suffixes: ['_show', '_highlight'],
        priority: 72,
      ),
      _StageDefinition(
        stage: 'WIN_LINE_HIDE',
        keywords: ['win', 'line', 'hide', 'clear'],
        suffixes: ['_hide', '_clear'],
        priority: 71,
      ),

      // Jackpots
      _StageDefinition(
        stage: 'JACKPOT_TRIGGER',
        keywords: ['jackpot', 'jp', 'trigger', 'hit'],
        suffixes: ['_trigger', '_hit'],
        priority: 98,
      ),
      _StageDefinition(
        stage: 'JACKPOT_AWARD',
        keywords: ['jackpot', 'jp', 'award', 'win', 'collect'],
        suffixes: ['_award', '_win', '_collect'],
        priority: 99,
      ),
      _StageDefinition(
        stage: 'JACKPOT_MINI',
        keywords: ['jackpot', 'jp', 'mini', 'bronze'],
        suffixes: ['_mini', '_bronze'],
        priority: 93,
      ),
      _StageDefinition(
        stage: 'JACKPOT_MINOR',
        keywords: ['jackpot', 'jp', 'minor', 'silver'],
        suffixes: ['_minor', '_silver'],
        priority: 94,
      ),
      _StageDefinition(
        stage: 'JACKPOT_MAJOR',
        keywords: ['jackpot', 'jp', 'major', 'gold'],
        suffixes: ['_major', '_gold'],
        priority: 96,
      ),
      _StageDefinition(
        stage: 'JACKPOT_GRAND',
        keywords: ['jackpot', 'jp', 'grand', 'platinum', 'mega'],
        suffixes: ['_grand', '_platinum'],
        priority: 100,
      ),

      // Coin burst
      _StageDefinition(
        stage: 'COIN_BURST',
        keywords: ['coin', 'burst', 'shower', 'rain', 'explosion'],
        suffixes: ['_burst', '_shower', '_rain'],
        priority: 77,
      ),
      _StageDefinition(
        stage: 'COIN_DROP',
        keywords: ['coin', 'drop', 'fall', 'collect'],
        suffixes: ['_drop', '_fall'],
        priority: 73,
      ),
    ],

    // ═══════════════════════════════════════════════════════════════════
    // GROUP 3: MUSIC & FEATURES
    // ═══════════════════════════════════════════════════════════════════
    StageGroup.musicAndFeatures: [
      // Game start (triggers base music automatically)
      _StageDefinition(
        stage: 'GAME_START',
        keywords: ['game', 'start', 'begin', 'load', 'init', 'base'],
        suffixes: ['_start', '_begin', '_init'],
        priority: 95,
      ),
      // Base game music — layers (full arrangements, gradatively stronger)
      _StageDefinition(
        stage: 'MUSIC_BASE_L1',
        keywords: ['music', 'base', 'main', 'background', 'bg', 'mus', 'bgm', 'basegame', 'l1', 'lvl1'],
        requiredKeywords: ['music|mus|bgm|basegame'],
        suffixes: ['_base', '_main', '_bg', '_music', '_loop', '_l1'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'MUSIC_BASE_L2',
        keywords: ['music', 'base', 'l2', 'lvl2', 'layer2', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_l2', '_lvl2', '_layer2'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 84,
      ),
      _StageDefinition(
        stage: 'MUSIC_BASE_L3',
        keywords: ['music', 'base', 'l3', 'lvl3', 'layer3', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_l3', '_lvl3', '_layer3'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 83,
      ),
      _StageDefinition(
        stage: 'MUSIC_BASE_L4',
        keywords: ['music', 'base', 'l4', 'lvl4', 'layer4', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_l4', '_lvl4', '_layer4'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'MUSIC_BASE_L5',
        keywords: ['music', 'base', 'l5', 'lvl5', 'layer5', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_l5', '_lvl5', '_layer5'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 81,
      ),
      // Base game music — intro/outro
      _StageDefinition(
        stage: 'MUSIC_BASE_INTRO',
        keywords: ['music', 'base', 'intro', 'opening', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_intro', '_opening'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'MUSIC_BASE_OUTRO',
        keywords: ['music', 'base', 'outro', 'ending', 'mus'],
        requiredKeywords: ['music|mus|bgm'],
        suffixes: ['_outro', '_ending'],
        excludeKeywords: ['trn', 'transition', 'panel', 'wild', 'scatter', 'symbol'],
        priority: 82,
      ),

      // Free spins
      _StageDefinition(
        stage: 'FREESPIN_TRIGGER',
        keywords: ['freespin', 'free', 'spin', 'fs', 'trigger'],
        suffixes: ['_trigger', '_start'],
        priority: 92,
      ),
      _StageDefinition(
        stage: 'FREESPIN_START',
        keywords: ['freespin', 'free', 'spin', 'fs', 'start', 'begin', 'enter'],
        suffixes: ['_start', '_begin', '_enter'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'FREESPIN_SPIN',
        keywords: ['freespin', 'free', 'spin', 'fs', 'loop'],
        suffixes: ['_spin', '_loop'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'FREESPIN_END',
        keywords: ['freespin', 'free', 'spin', 'fs', 'end', 'exit', 'complete'],
        suffixes: ['_end', '_exit', '_complete'],
        priority: 88,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_L1',
        keywords: ['freespin', 'free', 'spin', 'fs', 'music', 'bg'],
        suffixes: ['_music', '_bg', '_l1'],
        priority: 86,
      ),
      // Free spins music layers L2-L5
      _StageDefinition(
        stage: 'MUSIC_FS_INTRO',
        keywords: ['freespin', 'free', 'fs', 'music', 'intro'],
        requiredKeywords: ['intro'],
        suffixes: ['_intro'],
        priority: 87,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_OUTRO',
        keywords: ['freespin', 'free', 'fs', 'music', 'outro'],
        requiredKeywords: ['outro'],
        suffixes: ['_outro'],
        priority: 87,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_L2',
        keywords: ['freespin', 'free', 'fs', 'music', 'l2', 'lvl2', 'layer2'],
        suffixes: ['_l2', '_lvl2', '_layer2'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_L3',
        keywords: ['freespin', 'free', 'fs', 'music', 'l3', 'lvl3', 'layer3'],
        suffixes: ['_l3', '_lvl3', '_layer3'],
        priority: 84,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_L4',
        keywords: ['freespin', 'free', 'fs', 'music', 'l4', 'lvl4', 'layer4'],
        suffixes: ['_l4', '_lvl4', '_layer4'],
        priority: 83,
      ),
      _StageDefinition(
        stage: 'MUSIC_FS_L5',
        keywords: ['freespin', 'free', 'fs', 'music', 'l5', 'lvl5', 'layer5'],
        suffixes: ['_l5', '_lvl5', '_layer5'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'FREESPIN_RETRIGGER',
        keywords: ['freespin', 'free', 'spin', 'fs', 'retrigger', 'extra'],
        suffixes: ['_retrigger', '_extra'],
        priority: 91,
      ),

      // Bonus
      _StageDefinition(
        stage: 'BONUS_TRIGGER',
        keywords: ['bonus', 'trigger', 'activate'],
        suffixes: ['_trigger', '_activate'],
        priority: 93,
      ),
      _StageDefinition(
        stage: 'BONUS_ENTER',
        keywords: ['bonus', 'enter', 'start', 'begin'],
        suffixes: ['_enter', '_start'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'BONUS_STEP',
        keywords: ['bonus', 'step', 'pick', 'reveal', 'turn'],
        suffixes: ['_step', '_pick', '_reveal'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'BONUS_EXIT',
        keywords: ['bonus', 'exit', 'end', 'complete', 'finish'],
        suffixes: ['_exit', '_end', '_complete'],
        priority: 88,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_L1',
        keywords: ['bonus', 'music', 'bg'],
        suffixes: ['_music', '_bg', '_l1'],
        priority: 84,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_INTRO',
        keywords: ['bonus', 'music', 'intro'],
        requiredKeywords: ['intro'],
        suffixes: ['_intro'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_OUTRO',
        keywords: ['bonus', 'music', 'outro'],
        requiredKeywords: ['outro'],
        suffixes: ['_outro'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_L2',
        keywords: ['bonus', 'music', 'l2', 'lvl2', 'layer2'],
        suffixes: ['_l2', '_lvl2', '_layer2'],
        priority: 83,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_L3',
        keywords: ['bonus', 'music', 'l3', 'lvl3', 'layer3'],
        suffixes: ['_l3', '_lvl3', '_layer3'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_L4',
        keywords: ['bonus', 'music', 'l4', 'lvl4', 'layer4'],
        suffixes: ['_l4', '_lvl4', '_layer4'],
        priority: 81,
      ),
      _StageDefinition(
        stage: 'MUSIC_BONUS_L5',
        keywords: ['bonus', 'music', 'l5', 'lvl5', 'layer5'],
        suffixes: ['_l5', '_lvl5', '_layer5'],
        priority: 80,
      ),

      // Cascade
      _StageDefinition(
        stage: 'CASCADE_START',
        keywords: ['cascade', 'tumble', 'avalanche', 'start'],
        suffixes: ['_start', '_begin'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'CASCADE_STEP',
        keywords: ['cascade', 'tumble', 'avalanche', 'step', 'drop', 'fall'],
        suffixes: ['_step', '_drop', '_fall'],
        priority: 83,
      ),
      _StageDefinition(
        stage: 'CASCADE_POP',
        keywords: ['cascade', 'tumble', 'pop', 'explode', 'destroy', 'break'],
        suffixes: ['_pop', '_explode', '_break'],
        priority: 84,
      ),
      _StageDefinition(
        stage: 'CASCADE_END',
        keywords: ['cascade', 'tumble', 'avalanche', 'end', 'complete'],
        suffixes: ['_end', '_complete'],
        priority: 82,
      ),

      // Hold & Win / Respins
      _StageDefinition(
        stage: 'HOLD_TRIGGER',
        keywords: ['hold', 'respin', 'lock', 'trigger'],
        suffixes: ['_trigger', '_start'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'HOLD_START',
        keywords: ['hold', 'respin', 'start', 'begin', 'enter'],
        suffixes: ['_start', '_enter'],
        priority: 88,
      ),
      _StageDefinition(
        stage: 'HOLD_SPIN',
        keywords: ['hold', 'respin', 'spin', 'loop'],
        suffixes: ['_spin', '_loop'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'HOLD_LOCK',
        keywords: ['hold', 'lock', 'stick', 'freeze'],
        suffixes: ['_lock', '_stick'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'HOLD_END',
        keywords: ['hold', 'respin', 'end', 'exit', 'complete'],
        suffixes: ['_end', '_exit'],
        priority: 86,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_L1',
        keywords: ['hold', 'respin', 'music', 'bg'],
        suffixes: ['_music', '_bg', '_l1'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_INTRO',
        keywords: ['hold', 'music', 'intro'],
        requiredKeywords: ['intro'],
        suffixes: ['_intro'],
        priority: 81,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_OUTRO',
        keywords: ['hold', 'music', 'outro'],
        requiredKeywords: ['outro'],
        suffixes: ['_outro'],
        priority: 81,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_L2',
        keywords: ['hold', 'respin', 'music', 'l2', 'lvl2', 'layer2'],
        suffixes: ['_l2', '_lvl2', '_layer2'],
        priority: 79,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_L3',
        keywords: ['hold', 'respin', 'music', 'l3', 'lvl3', 'layer3'],
        suffixes: ['_l3', '_lvl3', '_layer3'],
        priority: 78,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_L4',
        keywords: ['hold', 'respin', 'music', 'l4', 'lvl4', 'layer4'],
        suffixes: ['_l4', '_lvl4', '_layer4'],
        priority: 77,
      ),
      _StageDefinition(
        stage: 'MUSIC_HOLD_L5',
        keywords: ['hold', 'respin', 'music', 'l5', 'lvl5', 'layer5'],
        suffixes: ['_l5', '_lvl5', '_layer5'],
        priority: 76,
      ),

      // Multiplier
      _StageDefinition(
        stage: 'MULTIPLIER_INCREASE',
        keywords: ['multiplier', 'mult', 'multi', 'increase', 'up', 'boost'],
        suffixes: ['_increase', '_up', '_boost'],
        priority: 87,
      ),
      _StageDefinition(
        stage: 'MULTIPLIER_APPLY',
        keywords: ['multiplier', 'mult', 'multi', 'apply', 'activate'],
        suffixes: ['_apply', '_activate'],
        priority: 86,
      ),

      // Gamble
      _StageDefinition(
        stage: 'GAMBLE_ENTER',
        keywords: ['gamble', 'risk', 'double', 'enter', 'start'],
        suffixes: ['_enter', '_start'],
        priority: 78,
      ),
      _StageDefinition(
        stage: 'GAMBLE_WIN',
        keywords: ['gamble', 'risk', 'double', 'win', 'correct'],
        suffixes: ['_win', '_correct'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'GAMBLE_LOSE',
        keywords: ['gamble', 'risk', 'double', 'lose', 'wrong', 'fail'],
        suffixes: ['_lose', '_wrong', '_fail'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'GAMBLE_EXIT',
        keywords: ['gamble', 'risk', 'double', 'exit', 'collect'],
        suffixes: ['_exit', '_collect'],
        priority: 76,
      ),

      // Feature generic
      _StageDefinition(
        stage: 'FEATURE_ENTER',
        keywords: ['feature', 'special', 'enter', 'start'],
        suffixes: ['_enter', '_start'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'FEATURE_EXIT',
        keywords: ['feature', 'special', 'exit', 'end'],
        suffixes: ['_exit', '_end'],
        priority: 74,
      ),

      // ─── Jackpot Music Layers ──────────────────────────────────────────
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_L1',
        keywords: ['jackpot', 'jp', 'music', 'bg'],
        suffixes: ['_music', '_bg', '_l1'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_INTRO',
        keywords: ['jackpot', 'jp', 'music', 'intro'],
        suffixes: ['_intro'],
        priority: 81,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_OUTRO',
        keywords: ['jackpot', 'jp', 'music', 'outro'],
        suffixes: ['_outro'],
        priority: 81,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_L2',
        keywords: ['jackpot', 'jp', 'music', 'l2', 'lvl2'],
        suffixes: ['_l2', '_lvl2'],
        priority: 79,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_L3',
        keywords: ['jackpot', 'jp', 'music', 'l3', 'lvl3'],
        suffixes: ['_l3', '_lvl3'],
        priority: 78,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_L4',
        keywords: ['jackpot', 'jp', 'music', 'l4', 'lvl4'],
        suffixes: ['_l4', '_lvl4'],
        priority: 77,
      ),
      _StageDefinition(
        stage: 'MUSIC_JACKPOT_L5',
        keywords: ['jackpot', 'jp', 'music', 'l5', 'lvl5'],
        suffixes: ['_l5', '_lvl5'],
        priority: 76,
      ),

      // ─── Gamble Music Layers ───────────────────────────────────────────
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_L1',
        keywords: ['gamble', 'risk', 'double', 'music', 'bg'],
        suffixes: ['_music', '_bg', '_l1'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_INTRO',
        keywords: ['gamble', 'music', 'intro'],
        suffixes: ['_intro'],
        priority: 76,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_OUTRO',
        keywords: ['gamble', 'music', 'outro'],
        suffixes: ['_outro'],
        priority: 76,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_L2',
        keywords: ['gamble', 'music', 'l2', 'lvl2'],
        suffixes: ['_l2', '_lvl2'],
        priority: 74,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_L3',
        keywords: ['gamble', 'music', 'l3', 'lvl3'],
        suffixes: ['_l3', '_lvl3'],
        priority: 73,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_L4',
        keywords: ['gamble', 'music', 'l4', 'lvl4'],
        suffixes: ['_l4', '_lvl4'],
        priority: 72,
      ),
      _StageDefinition(
        stage: 'MUSIC_GAMBLE_L5',
        keywords: ['gamble', 'music', 'l5', 'lvl5'],
        suffixes: ['_l5', '_lvl5'],
        priority: 71,
      ),

      // ─── Reveal Music Layers ───────────────────────────────────────────
      _StageDefinition(
        stage: 'MUSIC_REVEAL_L1',
        keywords: ['reveal', 'music', 'mus', 'bg'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_music', '_bg', '_l1'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_INTRO',
        keywords: ['reveal', 'music', 'mus', 'intro'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_intro'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 76,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_OUTRO',
        keywords: ['reveal', 'music', 'mus', 'outro'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_outro'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 76,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_L2',
        keywords: ['reveal', 'music', 'mus', 'l2', 'lvl2'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_l2', '_lvl2'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 74,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_L3',
        keywords: ['reveal', 'music', 'mus', 'l3', 'lvl3'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_l3', '_lvl3'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 73,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_L4',
        keywords: ['reveal', 'music', 'mus', 'l4', 'lvl4'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_l4', '_lvl4'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 72,
      ),
      _StageDefinition(
        stage: 'MUSIC_REVEAL_L5',
        keywords: ['reveal', 'music', 'mus', 'l5', 'lvl5'],
        requiredKeywords: ['music|mus'],
        suffixes: ['_l5', '_lvl5'],
        excludeKeywords: ['wild', 'mystery', 'pick', 'bonus'],
        priority: 71,
      ),

      // ─── Ambient — Per Scene ───────────────────────────────────────────
      _StageDefinition(
        stage: 'AMBIENT_BASE',
        keywords: ['ambient', 'ambience', 'amb', 'base', 'basegame', 'bg', 'background'],
        suffixes: ['_ambient', '_amb', '_ambience'],
        excludeKeywords: ['free', 'fs', 'bonus', 'hold', 'jackpot', 'gamble', 'reveal', 'bigwin', 'win'],
        priority: 65,
      ),
      _StageDefinition(
        stage: 'AMBIENT_FS',
        keywords: ['ambient', 'ambience', 'amb', 'free', 'fs', 'freespin'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_BONUS',
        keywords: ['ambient', 'ambience', 'amb', 'bonus'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_HOLD',
        keywords: ['ambient', 'ambience', 'amb', 'hold', 'respin'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_BIGWIN',
        keywords: ['ambient', 'ambience', 'amb', 'bigwin', 'big', 'win'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_JACKPOT',
        keywords: ['ambient', 'ambience', 'amb', 'jackpot', 'jp'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_GAMBLE',
        keywords: ['ambient', 'ambience', 'amb', 'gamble', 'risk'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),
      _StageDefinition(
        stage: 'AMBIENT_REVEAL',
        keywords: ['ambient', 'ambience', 'amb', 'reveal'],
        suffixes: ['_ambient', '_amb'],
        priority: 66,
      ),

      // Attract / Idle
      _StageDefinition(
        stage: 'ATTRACT_LOOP',
        keywords: ['attract', 'idle', 'demo', 'loop'],
        suffixes: ['_loop'],
        priority: 60,
      ),
    ],
  };

  /// Get all stages for a group
  List<String> getStagesForGroup(StageGroup group) {
    return _stageDefinitions[group]?.map((d) => d.stage).toList() ?? [];
  }

  /// Get all groups
  List<StageGroup> get allGroups => StageGroup.values;

  /// Match multiple audio files to stages within a group
  /// Uses smart batch-level indexing convention detection for REEL_STOP files
  BatchMatchResult matchFilesToGroup({
    required StageGroup group,
    required List<String> audioPaths,
  }) {
    final definitions = _stageDefinitions[group] ?? [];
    final matched = <StageMatch>[];
    final unmatched = <UnmatchedFile>[];

    // ═══════════════════════════════════════════════════════════════════════
    // BATCH-LEVEL INDEXING CONVENTION DETECTION
    // Analyze ALL files to determine if they use 0-indexed (0-4) or 1-indexed (1-5)
    // ═══════════════════════════════════════════════════════════════════════
    final indexOffset = _detectIndexingConvention(audioPaths);
    if (indexOffset != 0) {
      if (kDebugMode) debugPrint('[BatchMatch] Detected 1-indexed naming convention, applying offset: $indexOffset');
    }

    // Collect valid stage names for this group (for alias filtering)
    final groupStages = definitions.map((d) => d.stage).toSet();

    for (final path in audioPaths) {
      final fileName = _extractFileName(path);
      final normalizedName = _normalizeFileName(fileName);

      // ── ALIAS PRE-CHECK: instant match for known naming patterns ──
      final aliasStage = _checkAlias(path);
      if (aliasStage != null && groupStages.contains(aliasStage)) {
        matched.add(StageMatch(
          audioFileName: fileName,
          audioPath: path,
          stage: aliasStage,
          confidence: 0.95,
          matchedKeywords: ['alias:$aliasStage'],
        ));
        continue;
      }

      // Apply indexing offset to normalized name for matching
      final adjustedName = indexOffset != 0
          ? _applyIndexOffset(normalizedName, indexOffset)
          : normalizedName;

      // Find best match
      _StageDefinition? bestMatch;
      double bestConfidence = 0.0;
      List<String> bestKeywords = [];

      for (final def in definitions) {
        final (confidence, keywords) = _calculateConfidence(adjustedName, def);
        if (confidence > bestConfidence) {
          bestConfidence = confidence;
          bestMatch = def;
          bestKeywords = keywords;
        }
      }

      // Threshold 0.3 = requires 2+ keywords or 1 keyword + suffix/exact match
      if (bestMatch != null && bestConfidence >= 0.3) {
        matched.add(StageMatch(
          audioFileName: fileName,
          audioPath: path,
          stage: bestMatch.stage,
          confidence: bestConfidence,
          matchedKeywords: bestKeywords,
        ));
      } else {
        // Generate suggestions for unmatched
        final suggestions = _generateSuggestions(normalizedName, definitions);
        unmatched.add(UnmatchedFile(
          audioFileName: fileName,
          audioPath: path,
          suggestions: suggestions,
        ));
      }
    }

    // Sort matched by stage name for hierarchical ordering
    matched.sort((a, b) => a.stage.compareTo(b.stage));

    return BatchMatchResult(
      group: group,
      matched: matched,
      unmatched: unmatched,
    );
  }

  /// Detect if batch uses 0-indexed (0-4) or 1-indexed (1-5) naming convention
  /// Returns offset to subtract from file numbers: 0 = already 0-indexed, 1 = convert 1-indexed to 0-indexed
  /// NOTE: If ANY reel-stop file uses XofY naming (e.g. "1of5"), returns 0
  /// because XofY has its own conversion logic in _calculateConfidence STEP 4.
  int _detectIndexingConvention(List<String> audioPaths) {
    final allNumbers = <int>{};
    bool hasXofYPattern = false;

    for (final path in audioPaths) {
      final fileName = _extractFileName(path);
      final normalizedName = _normalizeFileName(fileName);

      // Only consider files that look like reel stop sounds
      if (!normalizedName.contains('stop') &&
          !normalizedName.contains('land') &&
          !normalizedName.contains('reel')) {
        continue;
      }

      // If any reel-stop file uses XofY, skip indexing convention entirely
      if (RegExp(r'\dof\d').hasMatch(normalizedName)) {
        hasXofYPattern = true;
        break;
      }

      // Extract numbers AFTER a stop/land keyword only (ignore prefix IDs)
      final stopIdx = normalizedName.lastIndexOf('stop');
      final landIdx = normalizedName.lastIndexOf('land');
      final kwEnd = stopIdx > landIdx ? stopIdx : landIdx;
      if (kwEnd < 0) continue;

      final afterKw = normalizedName.substring(kwEnd);
      final numbers = RegExp(r'\d+')
          .allMatches(afterKw)
          .map((m) => int.tryParse(m.group(0) ?? '') ?? -1)
          .where((n) => n >= 0 && n <= 9)
          .toList();

      allNumbers.addAll(numbers);
    }

    // XofY files handle their own indexing — don't apply global offset
    if (hasXofYPattern) return 0;

    if (allNumbers.isEmpty) return 0;

    // Heuristics:
    // - If we have 0 but not 5 → 0-indexed (0-4)
    // - If we have 5 but not 0 → 1-indexed (1-5), offset = 1
    // - If we have both 0 and 5 → ambiguous, prefer 0-indexed (safer)
    // - If we have 1-4 only (no 0 or 5) → check if 1 is present, likely 1-indexed

    final has0 = allNumbers.contains(0);
    final has5 = allNumbers.contains(5);
    final has1 = allNumbers.contains(1);

    if (has5 && !has0) {
      // Files use 1-5, convert to 0-4
      return 1;
    }

    if (!has0 && has1 && !has5) {
      // Files use 1-4 (partial set), likely 1-indexed
      // Check if max number is 4 or less AND min is 1
      final minNum = allNumbers.reduce(min);
      final maxNum = allNumbers.reduce(max);
      if (minNum == 1 && maxNum <= 4) {
        return 1;
      }
    }

    // Default: assume 0-indexed
    return 0;
  }

  /// Apply index offset to normalized filename for matching
  /// Converts 1-indexed numbers to 0-indexed (subtracts offset from each number)
  /// SKIPS XofY patterns (they have their own conversion logic in STEP 4)
  /// SKIPS leading prefix numbers (asset IDs like "004")
  String _applyIndexOffset(String normalizedName, int offset) {
    // First, identify XofY spans to skip
    final xofyRegions = RegExp(r'\dof\d')
        .allMatches(normalizedName)
        .map((m) => (m.start, m.end))
        .toList();

    return normalizedName.replaceAllMapped(
      RegExp(r'\d+'),
      (match) {
        // Skip if inside XofY pattern
        for (final (start, end) in xofyRegions) {
          if (match.start >= start && match.end <= end) return match.group(0)!;
        }
        // Skip leading prefix (starts at position 0)
        if (match.start == 0) return match.group(0)!;
        final num = int.tryParse(match.group(0) ?? '') ?? 0;
        final adjusted = num - offset;
        return adjusted >= 0 ? adjusted.toString() : match.group(0)!;
      },
    );
  }

  /// Auto-detect which group an audio file belongs to
  StageGroup? detectGroup(String audioPath) {
    final fileName = _extractFileName(audioPath);
    final normalizedName = _normalizeFileName(fileName);

    StageGroup? bestGroup;
    double bestConfidence = 0.0;

    for (final group in StageGroup.values) {
      final definitions = _stageDefinitions[group] ?? [];
      for (final def in definitions) {
        final (confidence, _) = _calculateConfidence(normalizedName, def);
        if (confidence > bestConfidence) {
          bestConfidence = confidence;
          bestGroup = group;
        }
      }
    }

    return bestConfidence >= 0.2 ? bestGroup : null;
  }

  /// Batch-match files to stages across ALL groups, with indexing convention detection.
  /// Unlike matchFilesToGroup (single group), this matches against the entire stage catalog
  /// and filters results to only include stages in [allowedStages] if provided.
  BatchMatchResult matchFilesToStages({
    required List<String> audioPaths,
    Set<String>? allowedStages,
  }) {
    final matched = <StageMatch>[];
    final unmatched = <UnmatchedFile>[];

    // Batch-level indexing convention detection (1-indexed vs 0-indexed)
    final indexOffset = _detectIndexingConvention(audioPaths);

    // Flatten ALL definitions across ALL groups
    final allDefinitions = <_StageDefinition>[];
    for (final group in StageGroup.values) {
      allDefinitions.addAll(_stageDefinitions[group] ?? []);
    }

    for (final path in audioPaths) {
      final fileName = _extractFileName(path);
      final normalizedName = _normalizeFileName(fileName);

      // ── ALIAS PRE-CHECK: instant match for known naming patterns ──
      final aliasStage = _checkAlias(path);
      if (aliasStage != null && (allowedStages == null || allowedStages.contains(aliasStage))) {
        matched.add(StageMatch(
          audioFileName: fileName,
          audioPath: path,
          stage: aliasStage,
          confidence: 0.95,
          matchedKeywords: ['alias:$aliasStage'],
        ));
        continue;
      }

      // Apply indexing offset for batch matching
      final adjustedName = indexOffset != 0
          ? _applyIndexOffset(normalizedName, indexOffset)
          : normalizedName;

      _StageDefinition? bestMatch;
      double bestConfidence = 0.0;
      List<String> bestKeywords = [];

      for (final def in allDefinitions) {
        // Skip stages not in allowed set (if filter provided)
        if (allowedStages != null && !allowedStages.contains(def.stage)) {
          continue;
        }
        final (confidence, keywords) = _calculateConfidence(adjustedName, def);
        if (confidence > bestConfidence) {
          bestConfidence = confidence;
          bestMatch = def;
          bestKeywords = keywords;
        }
      }

      // Threshold 0.4 = requires at least 2 keyword matches (0.40 base).
      // Single keyword (0.20) + suffix (0.15) = 0.35 NOT enough — prevents false positives.
      if (bestMatch != null && bestConfidence >= 0.4) {
        matched.add(StageMatch(
          audioFileName: fileName,
          audioPath: path,
          stage: bestMatch.stage,
          confidence: bestConfidence,
          matchedKeywords: bestKeywords,
        ));
      } else {
        final suggestions = _generateSuggestions(
          adjustedName,
          allowedStages != null
              ? allDefinitions.where((d) => allowedStages.contains(d.stage)).toList()
              : allDefinitions,
        );
        unmatched.add(UnmatchedFile(
          audioFileName: fileName,
          audioPath: path,
          suggestions: suggestions,
        ));
      }
    }

    // Sort by stage name for hierarchical ordering (reel_land_0, reel_land_1, ...)
    matched.sort((a, b) => a.stage.compareTo(b.stage));

    return BatchMatchResult(
      group: StageGroup.spinsAndReels, // placeholder — cross-group result
      matched: matched,
      unmatched: unmatched,
    );
  }

  /// Match a single file to a stage (across all groups)
  StageMatch? matchSingleFile(String audioPath) {
    final fileName = _extractFileName(audioPath);
    final normalizedName = _normalizeFileName(fileName);

    // ── ALIAS PRE-CHECK ──
    final aliasStage = _checkAlias(audioPath);
    if (aliasStage != null) {
      return StageMatch(
        audioFileName: fileName,
        audioPath: audioPath,
        stage: aliasStage,
        confidence: 0.95,
        matchedKeywords: ['alias:$aliasStage'],
      );
    }

    _StageDefinition? bestMatch;
    double bestConfidence = 0.0;
    List<String> bestKeywords = [];

    for (final group in StageGroup.values) {
      final definitions = _stageDefinitions[group] ?? [];
      for (final def in definitions) {
        final (confidence, keywords) = _calculateConfidence(normalizedName, def);
        if (confidence > bestConfidence) {
          bestConfidence = confidence;
          bestMatch = def;
          bestKeywords = keywords;
        }
      }
    }

    if (bestMatch != null && bestConfidence >= 0.4) {
      return StageMatch(
        audioFileName: fileName,
        audioPath: audioPath,
        stage: bestMatch.stage,
        confidence: bestConfidence,
        matchedKeywords: bestKeywords,
      );
    }

    return null;
  }

  /// Calculate confidence score for a filename against a stage definition
  ///
  /// INTENT-BASED MATCHING ALGORITHM v2.0
  ///
  /// This algorithm uses a smarter approach:
  /// 1. PRIMARY KEYWORDS — Core intent indicators (spin, stop, reel, etc.)
  /// 2. CONTEXT KEYWORDS — Modifiers that clarify intent (button, loop, land, etc.)
  /// 3. CONFLICT DETECTION — If both intents match, use context to disambiguate
  ///
  /// Example: "reel_spin_button"
  /// - Old algorithm: EXCLUDED from SPIN_START (has 'reel')
  /// - New algorithm: Matches SPIN_START (has 'button' which indicates UI intent)
  ///
  (double confidence, List<String> matchedKeywords) _calculateConfidence(
    String normalizedName,
    _StageDefinition def,
  ) {
    final matchedKeywords = <String>[];
    double score = 0.0;
    final fileTokens = _tokenizeNormalized(normalizedName);

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 1: Count keyword matches using TOKEN-BASED matching
    // Token matching prevents substring false positives like:
    //   'win' matching inside 'rewind', 'panel' inside 'panelsappear'
    // ═══════════════════════════════════════════════════════════════════════
    int keywordMatches = 0;
    for (final keyword in def.keywords) {
      if (_keywordMatchesAsToken(normalizedName, keyword, fileTokens)) {
        matchedKeywords.add(keyword);
        keywordMatches++;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 2: Check EXCLUDE keywords with TOKEN-BASED matching
    // ═══════════════════════════════════════════════════════════════════════
    int excludeMatches = 0;
    String? primaryExclude;
    for (final exclude in def.excludeKeywords) {
      if (_keywordMatchesAsToken(normalizedName, exclude, fileTokens)) {
        excludeMatches++;
        primaryExclude ??= exclude;
      }
    }

    // STRICT EXCLUSION: If ANY exclude keyword matches, block unless strong positive
    if (excludeMatches > 0) {
      if (keywordMatches == 0) {
        return (0.0, ['EXCLUDED:$primaryExclude (no positive matches)']);
      } else if (keywordMatches <= excludeMatches) {
        return (0.0, ['EXCLUDED:$primaryExclude ($keywordMatches keywords <= $excludeMatches excludes)']);
      }
      score -= 0.1 * excludeMatches;
      matchedKeywords.add('PENALTY:${excludeMatches}x excludes');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 3: Check REQUIRED keywords (all must be present)
    // ═══════════════════════════════════════════════════════════════════════
    for (final required in def.requiredKeywords) {
      // Support OR-alternatives in required keywords: "music|mus" means either matches
      final alternatives = required.split('|');
      final anyMatch = alternatives.any((alt) => _keywordMatchesAsToken(normalizedName, alt, fileTokens));
      if (!anyMatch) {
        return (0.0, ['MISSING_REQUIRED:$required']);
      }
      matchedKeywords.add('required:$required');
      score += 0.25;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 4: Check for specific number requirement (REEL_STOP_0-4)
    //
    // Supports multiple naming conventions:
    //   - XofY pattern: "spins_stop_3of5_2" → X=3, Y=5, 0-indexed = X-1 = 2
    //   - Direct suffix: "reel_stop_2" → number after stop/land keyword
    //   - Prefix number: "004" at start is IGNORED (it's an asset ID)
    //   - Trailing number after XofY: "_2" at end is version/variant, IGNORED
    // ═══════════════════════════════════════════════════════════════════════
    // Use compact form (no spaces) for number matching patterns
    final compactName = normalizedName.replaceAll(' ', '');
    if (def.requiresNumber) {
      if (def.specificNumber != null) {
        final xofyMatch = RegExp(r'(\d)of(\d)').firstMatch(compactName);
        if (xofyMatch != null) {
          final x = int.tryParse(xofyMatch.group(1) ?? '') ?? -1;
          final reelIndex = x - 1;
          if (reelIndex == def.specificNumber!) {
            matchedKeywords.add('xofy:${xofyMatch.group(0)}→index$reelIndex');
            score += 0.35;
          } else {
            return (0.0, ['XOFY_MISMATCH:${xofyMatch.group(0)}→index$reelIndex, need ${def.specificNumber}']);
          }
        } else {
          final stopIdx = compactName.lastIndexOf('stop');
          final landIdx = compactName.lastIndexOf('land');
          final reelIdx = compactName.lastIndexOf('reel');
          final keywordEnd = [stopIdx, landIdx, reelIdx]
              .where((i) => i >= 0)
              .fold<int>(-1, (a, b) => b > a ? b : a);
          if (keywordEnd >= 0) {
            final afterKeyword = compactName.substring(keywordEnd);
            final nums = RegExp(r'\d+')
                .allMatches(afterKeyword)
                .map((m) => int.tryParse(m.group(0) ?? '') ?? -1)
                .where((n) => n >= 0 && n <= 9)
                .toList();
            if (nums.contains(def.specificNumber!)) {
              matchedKeywords.add('number:${def.specificNumber}');
              score += 0.35;
            } else {
              return (0.0, ['MISSING_NUMBER:${def.specificNumber} (after keyword)']);
            }
          } else {
            return (0.0, ['MISSING_NUMBER:${def.specificNumber} (no keyword context)']);
          }
        }
      } else if (!RegExp(r'\d').hasMatch(compactName)) {
        return (0.0, ['MISSING_ANY_NUMBER']);
      }
    } else if (def.stage == 'REEL_STOP') {
      final xofyMatch = RegExp(r'(\d)of(\d)').firstMatch(compactName);
      if (xofyMatch != null) {
        return (0.0, ['HAS_XOFY:${xofyMatch.group(0)}']);
      }
      final numbers = RegExp(r'\d+').allMatches(compactName).toList();
      for (final m in numbers) {
        final num = int.tryParse(m.group(0) ?? '') ?? -1;
        if (num >= 0 && num <= 5) {
          final beforeMatch = compactName.substring(0, m.start);
          if (beforeMatch.endsWith('stop') ||
              beforeMatch.endsWith('land') ||
              beforeMatch.endsWith('reel') ||
              beforeMatch.endsWith('reelstop') ||
              beforeMatch.endsWith('reelland')) {
            return (0.0, ['HAS_SPECIFIC_REEL_NUMBER:$num']);
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 5: Calculate score from keyword matches
    // ═══════════════════════════════════════════════════════════════════════
    // Progressive scoring: more matches = higher confidence
    if (keywordMatches == 0) {
      return (0.0, ['NO_KEYWORDS']);
    } else if (keywordMatches == 1) {
      score += 0.20; // Single keyword match
    } else if (keywordMatches == 2) {
      score += 0.40; // Two keywords = moderate confidence
    } else if (keywordMatches >= 3) {
      score += 0.60; // Three+ keywords = high confidence
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 6: Check suffixes (exact match at end)
    // ═══════════════════════════════════════════════════════════════════════
    for (final suffix in def.suffixes) {
      final normalizedSuffix = suffix.replaceAll('_', '');
      // Check compact filename ends with suffix
      if (compactName.endsWith(normalizedSuffix)) {
        matchedKeywords.add('suffix:$suffix');
        score += 0.15;
        break; // Only count one suffix match
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 7: Boost for exact stage name match (token-joined comparison)
    // ═══════════════════════════════════════════════════════════════════════
    final stageNormalized = def.stage.toLowerCase().replaceAll('_', ' ');
    final joinedFileTokens = fileTokens.join(' ');
    if (joinedFileTokens.contains(stageNormalized) || joinedFileTokens == stageNormalized) {
      matchedKeywords.add('exact:${def.stage}');
      score += 0.30;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 8: Priority bonus (smaller to not overshadow matches)
    // ═══════════════════════════════════════════════════════════════════════
    score += (def.priority / 2000); // Max 0.05 from priority

    return (min(max(score, 0.0), 1.0), matchedKeywords);
  }

  /// Generate suggestions for unmatched files
  List<StageSuggestion> _generateSuggestions(
    String normalizedName,
    List<_StageDefinition> definitions,
  ) {
    final suggestions = <(double, _StageDefinition, String)>[];

    for (final def in definitions) {
      final (confidence, keywords) = _calculateConfidence(normalizedName, def);
      if (confidence > 0.1) {
        final reason = keywords.isNotEmpty
            ? 'Contains: ${keywords.take(3).join(", ")}'
            : 'Similar to ${def.stage}';
        suggestions.add((confidence, def, reason));
      }
    }

    // Sort by confidence and take top 3
    suggestions.sort((a, b) => b.$1.compareTo(a.$1));
    return suggestions.take(3).map((s) => StageSuggestion(
          stage: s.$2.stage,
          confidence: s.$1,
          reason: s.$3,
        )).toList();
  }

  /// Extract filename from path
  String _extractFileName(String path) {
    final parts = path.split('/');
    final fileName = parts.isNotEmpty ? parts.last : path;
    // Remove extension
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  /// Normalize filename for matching — keeps separators as spaces for token matching
  String _normalizeFileName(String fileName) {
    return fileName
        .toLowerCase()
        .replaceAll(RegExp(r'[-_\s]+'), ' ')   // Normalize separators to spaces
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '') // Keep alphanumeric + spaces
        .trim();
  }

  /// Tokenize normalized filename into individual words
  List<String> _tokenizeNormalized(String normalizedName) {
    return normalizedName.split(' ').where((t) => t.isNotEmpty).toList();
  }

  /// Check if a keyword matches as a whole token in the filename.
  /// Prevents substring false positives like 'win' matching inside 'rewind'.
  bool _keywordMatchesAsToken(String normalizedName, String keyword, List<String> fileTokens) {
    // Exact token match (highest priority)
    if (fileTokens.contains(keyword)) return true;
    // Singular/plural match
    final singular = keyword.endsWith('s') && keyword.length > 2
        ? keyword.substring(0, keyword.length - 1)
        : keyword;
    final plural = '${keyword}s';
    if (fileTokens.contains(singular) || fileTokens.contains(plural)) return true;
    // Token starts with keyword (for compound tokens like 'freespin' matching 'free')
    // Only for keywords ≥ 4 chars to avoid false positives
    if (keyword.length >= 4) {
      for (final t in fileTokens) {
        if (t.startsWith(keyword) && t.length <= keyword.length + 3) return true;
      }
    }
    return false;
  }

  /// Levenshtein similarity (0-1)
  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final maxLen = max(a.length, b.length);
    final distance = _levenshteinDistance(a, b);
    return 1.0 - (distance / maxLen);
  }

  /// Levenshtein edit distance
  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }

    return matrix[a.length][b.length];
  }
}

/// Stage Group Service for Batch Import
///
/// Groups related slot stages together for efficient batch audio assignment.
/// Supports fuzzy matching of audio filenames to stages.

import 'dart:math';

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
/// - REEL_SPIN → onReelSpin
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
    'REEL_SPIN': 'onReelSpin',
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
    'ANTICIPATION_ON': 'onAnticipationStart',
    'ANTICIPATION_OFF': 'onAnticipationEnd',

    // Win Events
    'WIN_PRESENT': 'onWinPresent',
    'WIN_SMALL': 'onWinSmall',
    'WIN_MEDIUM': 'onWinMedium',
    'WIN_BIG': 'onWinBig',
    'WIN_MEGA': 'onWinMega',
    'WIN_EPIC': 'onWinEpic',
    'WIN_ULTRA': 'onWinUltra',
    'WIN_LINE_SHOW': 'onWinLineShow',
    'WIN_LINE_HIDE': 'onWinLineHide',

    // Rollup
    'ROLLUP_START': 'onRollupStart',
    'ROLLUP_TICK': 'onRollupTick',
    'ROLLUP_END': 'onRollupEnd',

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

    // Music
    'GAME_START': 'onGameStart',
    'MUSIC_BASE': 'onMusicBase',
    'MUSIC_INTRO': 'onMusicIntro',
    'MUSIC_LAYER_1': 'onMusicLayer1',
    'MUSIC_LAYER_2': 'onMusicLayer2',
    'MUSIC_LAYER_3': 'onMusicLayer3',

    // Free Spins
    'FREESPIN_TRIGGER': 'onFreeSpinTrigger',
    'FREESPIN_START': 'onFreeSpinStart',
    'FREESPIN_SPIN': 'onFreeSpinSpin',
    'FREESPIN_END': 'onFreeSpinEnd',
    'FREESPIN_MUSIC': 'onFreeSpinMusic',
    'FREESPIN_RETRIGGER': 'onFreeSpinRetrigger',

    // Bonus
    'BONUS_TRIGGER': 'onBonusTrigger',
    'BONUS_ENTER': 'onBonusEnter',
    'BONUS_STEP': 'onBonusStep',
    'BONUS_EXIT': 'onBonusExit',
    'BONUS_MUSIC': 'onBonusMusic',

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
    'HOLD_MUSIC': 'onHoldMusic',

    // Multiplier
    'MULTIPLIER_INCREASE': 'onMultiplierIncrease',
    'MULTIPLIER_APPLY': 'onMultiplierApply',

    // Gamble
    'GAMBLE_ENTER': 'onGambleEnter',
    'GAMBLE_WIN': 'onGambleWin',
    'GAMBLE_LOSE': 'onGambleLose',
    'GAMBLE_EXIT': 'onGambleExit',

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
    print('═══════════════════════════════════════════════════════════════');
    print('[DEBUG] Testing match for: "$fileName"');
    print('[DEBUG] Normalized: "$normalized"');
    print('───────────────────────────────────────────────────────────────');

    for (final group in StageGroup.values) {
      final definitions = _stageDefinitions[group] ?? [];
      for (final def in definitions) {
        final (confidence, keywords) = _calculateConfidence(normalized, def);
        if (confidence > 0 || keywords.any((k) => k.startsWith('EXCLUDED:') || k.startsWith('MISSING'))) {
          final status = confidence > 0 ? '✅' : '❌';
          print('$status ${def.stage}: ${(confidence * 100).toStringAsFixed(0)}% — ${keywords.join(", ")}');
        }
      }
    }

    // Final result
    final match = matchSingleFile('/fake/$fileName.wav');
    if (match != null) {
      print('───────────────────────────────────────────────────────────────');
      print('[RESULT] MATCHED: ${match.stage} (${(match.confidence * 100).toStringAsFixed(0)}%)');
      print('[RESULT] Event name: ${match.eventName}');
    } else {
      print('───────────────────────────────────────────────────────────────');
      print('[RESULT] NO MATCH');
    }
    print('═══════════════════════════════════════════════════════════════');
  }

  /// RUN ALL TESTS: Verify matching logic with common filenames
  /// Returns true if all tests pass
  bool runMatchingTests() {
    print('\n╔═══════════════════════════════════════════════════════════════╗');
    print('║        BATCH IMPORT MATCHING TESTS v2.0                        ║');
    print('╚═══════════════════════════════════════════════════════════════╝\n');

    final tests = <(String fileName, String expectedStage)>[
      // ── SPIN_START (UI spin button) ──
      ('spin_button', 'SPIN_START'),
      ('spin_click', 'SPIN_START'),
      ('ui_spin', 'SPIN_START'),
      ('spin_press', 'SPIN_START'),
      ('spin_start', 'SPIN_START'),
      ('button_spin_click', 'SPIN_START'),

      // ── REEL_SPIN (spinning loop) ──
      ('reel_spin', 'REEL_SPIN'),
      ('reel_spinning', 'REEL_SPIN'),
      ('reel_spin_loop', 'REEL_SPIN'),
      ('reels_spinning', 'REEL_SPIN'),
      ('spin_loop', 'REEL_SPIN'),
      ('spins_loop', 'REEL_SPIN'),

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
      ('win_big', 'WIN_BIG'),
      ('win_mega', 'WIN_MEGA'),
      ('win_small', 'WIN_SMALL'),

      // ── MUSIC ──
      ('music_base', 'MUSIC_BASE'),
      ('base_music_loop', 'MUSIC_BASE'),

      // ── FREESPIN ──
      ('freespin_start', 'FREESPIN_START'),
      ('freespin_music', 'FREESPIN_MUSIC'),
    ];

    int passed = 0;
    int failed = 0;
    final failures = <String>[];

    for (final (fileName, expectedStage) in tests) {
      final match = matchSingleFile('/fake/$fileName.wav');
      final actualStage = match?.stage;

      if (actualStage == expectedStage) {
        passed++;
        print('✅ "$fileName" → $expectedStage');
      } else {
        failed++;
        final msg = '❌ "$fileName" → Expected: $expectedStage, Got: ${actualStage ?? "NO MATCH"}';
        print(msg);
        failures.add(msg);
      }
    }

    print('\n────────────────────────────────────────────────────────────────');
    print('RESULTS: $passed passed, $failed failed');
    if (failures.isNotEmpty) {
      print('\nFAILURES:');
      for (final f in failures) {
        print('  $f');
      }
    }
    print('────────────────────────────────────────────────────────────────\n');

    return failed == 0;
  }

  /// Stages grouped by StageGroup
  ///
  /// MATCHING LOGIC v2.0 — Intent-Based Matching
  ///
  /// Instead of simple keyword matching, we use INTENT patterns:
  /// - SPIN_START = UI spin button → requires 'spin' + UI indicators (button/click/press/ui/start)
  /// - REEL_SPIN = Reel spinning loop → requires 'spin' + loop indicators (loop/roll/spinning)
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
      // DOES NOT MATCH: reel_spin_loop (that's REEL_SPIN)
      //
      // KEY INSIGHT: Even if 'reel' is in the name, if 'button/click/press/ui'
      // is ALSO present, it's still a UI spin sound!
      _StageDefinition(
        stage: 'SPIN_START',
        keywords: ['spin', 'start', 'button', 'press', 'click', 'ui', 'tap'],
        requiredKeywords: [], // At least one of: spin, button, click, press, ui
        suffixes: ['_start', '_press', '_click', '_spin', '_tap'],
        // CRITICAL FIX: Only exclude if it's clearly a LOOP sound (spinning + loop together)
        excludeKeywords: ['loop', 'roll', 'spinning', 'stop', 'land'],
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
      // REEL_SPIN — Reel spinning loop sound
      // ───────────────────────────────────────────────────────────────────
      // INTENT: Reels are spinning → plays looping spin sound
      // MATCHES: reel_spin, reel_spinning, reel_loop, spins_loop, spin_roll
      // DOES NOT MATCH: spin_button (that's SPIN_START)
      //
      // KEY INSIGHT: 'spin' (not just 'spinning') + 'loop/roll/reel' = REEL_SPIN
      _StageDefinition(
        stage: 'REEL_SPIN',
        // CRITICAL FIX: Include 'spin' (not just 'spinning')
        keywords: ['spin', 'spinning', 'spins', 'loop', 'roll', 'reel', 'reels'],
        requiredKeywords: [], // Need spin-related + loop/reel
        suffixes: ['_loop', '_spinning', '_spins', '_roll'],
        // CRITICAL FIX: Exclude UI indicators (button/click/press) and stop indicators
        excludeKeywords: ['button', 'press', 'click', 'tap', 'ui', 'stop', 'land', 'start', 'end'],
        priority: 92, // High priority for spinning sounds
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
        keywords: ['stop', 'land', 'reel', 'reels', 'spin', 'spins'],
        requiredKeywords: [],
        suffixes: ['_stop', '_land'],
        // Only exclude continuous action indicators (loop/spinning) and UI indicators
        excludeKeywords: ['spinning', 'loop', 'roll', 'button', 'press', 'click'],
        requiresNumber: false,
        priority: 88,
      ),

      // ───────────────────────────────────────────────────────────────────
      // REEL_STOP_0-4 — Individual reel stop sounds
      // ───────────────────────────────────────────────────────────────────
      _StageDefinition(
        stage: 'REEL_STOP_0',
        keywords: ['stop', 'land', 'first', '1st', 'reel', 'reels'],
        requiredKeywords: [],
        suffixes: ['_0', '_first'],
        excludeKeywords: ['spinning', 'loop'], // Only continuous action
        requiresNumber: true,
        specificNumber: 0,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_1',
        keywords: ['stop', 'land', 'second', '2nd', 'reel', 'reels'],
        requiredKeywords: [],
        suffixes: ['_1', '_second'],
        excludeKeywords: ['spinning', 'loop'],
        requiresNumber: true,
        specificNumber: 1,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_2',
        keywords: ['stop', 'land', 'third', '3rd', 'middle', 'center', 'reel', 'reels'],
        requiredKeywords: [],
        suffixes: ['_2', '_third', '_middle'],
        excludeKeywords: ['spinning', 'loop'],
        requiresNumber: true,
        specificNumber: 2,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_3',
        keywords: ['stop', 'land', 'fourth', '4th', 'reel', 'reels'],
        requiredKeywords: [],
        suffixes: ['_3', '_fourth'],
        excludeKeywords: ['spinning', 'loop'],
        requiresNumber: true,
        specificNumber: 3,
        priority: 87,
      ),
      _StageDefinition(
        stage: 'REEL_STOP_4',
        keywords: ['stop', 'land', 'fifth', '5th', 'last', 'final', 'reel', 'reels'],
        requiredKeywords: [],
        suffixes: ['_4', '_fifth', '_last', '_final'],
        excludeKeywords: ['spinning', 'loop'],
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
        stage: 'ANTICIPATION_ON',
        keywords: ['anticipation', 'antici', 'tension', 'buildup', 'suspense'],
        suffixes: ['_on', '_start', '_begin'],
        priority: 75,
      ),
      _StageDefinition(
        stage: 'ANTICIPATION_OFF',
        keywords: ['anticipation', 'antici', 'tension', 'release'],
        suffixes: ['_off', '_end', '_stop'],
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
        suffixes: ['_present', '_show'],
        priority: 85,
      ),

      // Win tiers
      _StageDefinition(
        stage: 'WIN_SMALL',
        keywords: ['win', 'small', 'minor', 'low', 'tiny'],
        suffixes: ['_small', '_minor', '_low'],
        priority: 80,
      ),
      _StageDefinition(
        stage: 'WIN_MEDIUM',
        keywords: ['win', 'medium', 'med', 'normal', 'regular'],
        suffixes: ['_medium', '_med', '_normal'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'WIN_BIG',
        keywords: ['win', 'big', 'large', 'great'],
        suffixes: ['_big', '_large'],
        priority: 88,
      ),
      _StageDefinition(
        stage: 'WIN_MEGA',
        keywords: ['win', 'mega', 'huge', 'massive'],
        suffixes: ['_mega', '_huge'],
        priority: 90,
      ),
      _StageDefinition(
        stage: 'WIN_EPIC',
        keywords: ['win', 'epic', 'super', 'amazing', 'incredible'],
        suffixes: ['_epic', '_super'],
        priority: 92,
      ),
      _StageDefinition(
        stage: 'WIN_ULTRA',
        keywords: ['win', 'ultra', 'max', 'ultimate', 'extreme'],
        suffixes: ['_ultra', '_max', '_ultimate'],
        priority: 95,
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
      // Base music
      _StageDefinition(
        stage: 'MUSIC_BASE',
        keywords: ['music', 'base', 'main', 'background', 'bg', 'ambient', 'mus', 'bgm', 'basegame', 'lvl'],
        suffixes: ['_base', '_main', '_bg', '_music', '_loop'],
        priority: 85,
      ),
      _StageDefinition(
        stage: 'MUSIC_INTRO',
        keywords: ['music', 'intro', 'start', 'opening'],
        suffixes: ['_intro', '_opening'],
        priority: 82,
      ),
      _StageDefinition(
        stage: 'MUSIC_LAYER_1',
        keywords: ['music', 'layer', 'l1', 'level1', 'low'],
        suffixes: ['_l1', '_layer1', '_low'],
        priority: 78,
      ),
      _StageDefinition(
        stage: 'MUSIC_LAYER_2',
        keywords: ['music', 'layer', 'l2', 'level2', 'mid'],
        suffixes: ['_l2', '_layer2', '_mid'],
        priority: 79,
      ),
      _StageDefinition(
        stage: 'MUSIC_LAYER_3',
        keywords: ['music', 'layer', 'l3', 'level3', 'high'],
        suffixes: ['_l3', '_layer3', '_high'],
        priority: 80,
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
        stage: 'FREESPIN_MUSIC',
        keywords: ['freespin', 'free', 'spin', 'fs', 'music', 'bg'],
        suffixes: ['_music', '_bg'],
        priority: 86,
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
        stage: 'BONUS_MUSIC',
        keywords: ['bonus', 'music', 'bg'],
        suffixes: ['_music', '_bg'],
        priority: 84,
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
        stage: 'HOLD_MUSIC',
        keywords: ['hold', 'respin', 'music', 'bg'],
        suffixes: ['_music', '_bg'],
        priority: 80,
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

      // Attract / Idle
      _StageDefinition(
        stage: 'ATTRACT_LOOP',
        keywords: ['attract', 'idle', 'demo', 'loop', 'ambient'],
        suffixes: ['_loop', '_ambient'],
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
      print('[BatchMatch] Detected 1-indexed naming convention, applying offset: $indexOffset');
    }

    for (final path in audioPaths) {
      final fileName = _extractFileName(path);
      final normalizedName = _normalizeFileName(fileName);

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

      // Threshold for considering it a match (lowered from 0.3 to 0.2 for broader matching)
      if (bestMatch != null && bestConfidence >= 0.2) {
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

    // Sort matched by confidence (highest first)
    matched.sort((a, b) => b.confidence.compareTo(a.confidence));

    return BatchMatchResult(
      group: group,
      matched: matched,
      unmatched: unmatched,
    );
  }

  /// Detect if batch uses 0-indexed (0-4) or 1-indexed (1-5) naming convention
  /// Returns offset to subtract from file numbers: 0 = already 0-indexed, 1 = convert 1-indexed to 0-indexed
  int _detectIndexingConvention(List<String> audioPaths) {
    final allNumbers = <int>{};

    for (final path in audioPaths) {
      final fileName = _extractFileName(path);
      final normalizedName = _normalizeFileName(fileName);

      // Only consider files that look like reel stop sounds
      if (!normalizedName.contains('stop') &&
          !normalizedName.contains('land') &&
          !normalizedName.contains('reel')) {
        continue;
      }

      // Extract all numbers from filename
      final numbers = RegExp(r'\d+')
          .allMatches(normalizedName)
          .map((m) => int.tryParse(m.group(0) ?? '') ?? -1)
          .where((n) => n >= 0 && n <= 9) // Only single digits likely to be reel indices
          .toList();

      allNumbers.addAll(numbers);
    }

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
  String _applyIndexOffset(String normalizedName, int offset) {
    return normalizedName.replaceAllMapped(
      RegExp(r'\d+'),
      (match) {
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

  /// Match a single file to a stage (across all groups)
  StageMatch? matchSingleFile(String audioPath) {
    final fileName = _extractFileName(audioPath);
    final normalizedName = _normalizeFileName(fileName);

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

    if (bestMatch != null && bestConfidence >= 0.2) {
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

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 1: Count keyword matches FIRST (before exclusions)
    // ═══════════════════════════════════════════════════════════════════════
    int keywordMatches = 0;
    for (final keyword in def.keywords) {
      if (normalizedName.contains(keyword)) {
        matchedKeywords.add(keyword);
        keywordMatches++;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 2: Check EXCLUDE keywords with SMART logic
    // ═══════════════════════════════════════════════════════════════════════
    // KEY INSIGHT: Don't blindly exclude. If we have strong positive matches,
    // exclusion keywords need to be MORE relevant than our matches.
    int excludeMatches = 0;
    String? primaryExclude;
    for (final exclude in def.excludeKeywords) {
      if (normalizedName.contains(exclude)) {
        excludeMatches++;
        primaryExclude ??= exclude;
      }
    }

    // SMART EXCLUSION LOGIC:
    // - If we have NO keyword matches and ANY exclude → exclude
    // - If we have 1-2 keyword matches and 2+ excludes → exclude
    // - If we have 3+ keyword matches and any excludes → DON'T exclude (strong intent)
    if (excludeMatches > 0) {
      if (keywordMatches == 0) {
        // No positive matches, any exclude is disqualifying
        return (0.0, ['EXCLUDED:$primaryExclude (no positive matches)']);
      } else if (keywordMatches <= 2 && excludeMatches >= 2) {
        // Weak positive, strong negative
        return (0.0, ['EXCLUDED:$primaryExclude (weak match, $excludeMatches excludes)']);
      } else if (keywordMatches < excludeMatches) {
        // More excludes than matches
        return (0.0, ['EXCLUDED:$primaryExclude ($excludeMatches excludes > $keywordMatches matches)']);
      }
      // Otherwise: we have enough positive matches to override excludes
      // Apply a small penalty instead of full exclusion
      score -= 0.1 * excludeMatches;
      matchedKeywords.add('PENALTY:${excludeMatches}x excludes');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 3: Check REQUIRED keywords (all must be present)
    // ═══════════════════════════════════════════════════════════════════════
    for (final required in def.requiredKeywords) {
      if (!normalizedName.contains(required)) {
        return (0.0, ['MISSING_REQUIRED:$required']);
      }
      matchedKeywords.add('required:$required');
      score += 0.25;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 4: Check for specific number requirement (REEL_STOP_0-4)
    // ═══════════════════════════════════════════════════════════════════════
    if (def.requiresNumber) {
      final numbers = RegExp(r'\d+')
          .allMatches(normalizedName)
          .map((m) => int.tryParse(m.group(0) ?? '') ?? -1)
          .toList();

      if (def.specificNumber != null) {
        if (!numbers.contains(def.specificNumber!)) {
          return (0.0, ['MISSING_NUMBER:${def.specificNumber}']);
        }
        matchedKeywords.add('number:${def.specificNumber}');
        score += 0.35;
      } else if (numbers.isEmpty) {
        return (0.0, ['MISSING_ANY_NUMBER']);
      }
    } else if (def.stage == 'REEL_STOP') {
      // Generic REEL_STOP should not match if there's a specific reel number
      final numbers = RegExp(r'\d+').allMatches(normalizedName).toList();
      for (final m in numbers) {
        final num = int.tryParse(m.group(0) ?? '') ?? -1;
        if (num >= 0 && num <= 5) {
          final beforeMatch = normalizedName.substring(0, m.start);
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
      if (normalizedName.endsWith(normalizedSuffix)) {
        matchedKeywords.add('suffix:$suffix');
        score += 0.15;
        break; // Only count one suffix match
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 7: Boost for exact stage name match
    // ═══════════════════════════════════════════════════════════════════════
    final stageNormalized = def.stage.toLowerCase().replaceAll('_', '');
    if (normalizedName.contains(stageNormalized)) {
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

  /// Normalize filename for matching
  String _normalizeFileName(String fileName) {
    return fileName
        .toLowerCase()
        .replaceAll(RegExp(r'[-_\s]+'), '') // Remove separators
        .replaceAll(RegExp(r'[^a-z0-9]'), ''); // Keep only alphanumeric
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

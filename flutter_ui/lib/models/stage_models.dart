/// FluxForge Universal Stage System — Dart Models
///
/// Mirror of rf-stage Rust crate for Flutter/Dart integration.
/// FluxForge doesn't understand engine events — only STAGES.
library;

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TAXONOMY
// ═══════════════════════════════════════════════════════════════════════════

/// Big win tier classification based on win-to-bet ratio
enum BigWinTier {
  win,       // 10-15x
  bigWin,    // 15-25x
  megaWin,   // 25-50x
  epicWin,   // 50-100x
  ultraWin;  // 100x+

  /// Get tier from win-to-bet ratio
  static BigWinTier fromRatio(double ratio) {
    if (ratio >= 100.0) return BigWinTier.ultraWin;
    if (ratio >= 50.0) return BigWinTier.epicWin;
    if (ratio >= 25.0) return BigWinTier.megaWin;
    if (ratio >= 15.0) return BigWinTier.bigWin;
    return BigWinTier.win;
  }

  double get minRatio => switch (this) {
    win => 10.0,
    bigWin => 15.0,
    megaWin => 25.0,
    epicWin => 50.0,
    ultraWin => 100.0,
  };

  String get displayName => switch (this) {
    win => 'WIN',
    bigWin => 'BIG WIN',
    megaWin => 'MEGA WIN',
    epicWin => 'EPIC WIN',
    ultraWin => 'ULTRA WIN',
  };

  static BigWinTier? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Map) {
      if (json.containsKey('custom')) return BigWinTier.win; // Custom tier
    }
    return switch (json.toString()) {
      'win' => BigWinTier.win,
      'big_win' => BigWinTier.bigWin,
      'mega_win' => BigWinTier.megaWin,
      'epic_win' => BigWinTier.epicWin,
      'ultra_win' => BigWinTier.ultraWin,
      _ => null,
    };
  }

  String toJson() => switch (this) {
    win => 'win',
    bigWin => 'big_win',
    megaWin => 'mega_win',
    epicWin => 'epic_win',
    ultraWin => 'ultra_win',
  };
}

/// Feature type classification
enum FeatureType {
  freeSpins,
  bonusGame,
  pickBonus,
  wheelBonus,
  respin,
  holdAndSpin,
  expandingWilds,
  stickyWilds,
  multiplier,
  cascade,
  mysterySymbols,
  walkingWilds,
  colossalReels,
  megaways;

  String get displayName => switch (this) {
    freeSpins => 'Free Spins',
    bonusGame => 'Bonus Game',
    pickBonus => 'Pick Bonus',
    wheelBonus => 'Wheel Bonus',
    respin => 'Respin',
    holdAndSpin => 'Hold & Spin',
    expandingWilds => 'Expanding Wilds',
    stickyWilds => 'Sticky Wilds',
    multiplier => 'Multiplier',
    cascade => 'Cascade',
    mysterySymbols => 'Mystery Symbols',
    walkingWilds => 'Walking Wilds',
    colossalReels => 'Colossal Reels',
    megaways => 'Megaways',
  };

  bool get isMultiStep => switch (this) {
    freeSpins || holdAndSpin || cascade || walkingWilds => true,
    _ => false,
  };

  static FeatureType? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Map && json.containsKey('custom')) return null;
    return switch (json.toString()) {
      'free_spins' => FeatureType.freeSpins,
      'bonus_game' => FeatureType.bonusGame,
      'pick_bonus' => FeatureType.pickBonus,
      'wheel_bonus' => FeatureType.wheelBonus,
      'respin' => FeatureType.respin,
      'hold_and_spin' => FeatureType.holdAndSpin,
      'expanding_wilds' => FeatureType.expandingWilds,
      'sticky_wilds' => FeatureType.stickyWilds,
      'multiplier' => FeatureType.multiplier,
      'cascade' => FeatureType.cascade,
      'mystery_symbols' => FeatureType.mysterySymbols,
      'walking_wilds' => FeatureType.walkingWilds,
      'colossal_reels' => FeatureType.colossalReels,
      'megaways' => FeatureType.megaways,
      _ => null,
    };
  }

  String toJson() => switch (this) {
    freeSpins => 'free_spins',
    bonusGame => 'bonus_game',
    pickBonus => 'pick_bonus',
    wheelBonus => 'wheel_bonus',
    respin => 'respin',
    holdAndSpin => 'hold_and_spin',
    expandingWilds => 'expanding_wilds',
    stickyWilds => 'sticky_wilds',
    multiplier => 'multiplier',
    cascade => 'cascade',
    mysterySymbols => 'mystery_symbols',
    walkingWilds => 'walking_wilds',
    colossalReels => 'colossal_reels',
    megaways => 'megaways',
  };
}

/// Jackpot tier classification
enum JackpotTier {
  mini,
  minor,
  major,
  grand;

  String get displayName => switch (this) {
    mini => 'MINI',
    minor => 'MINOR',
    major => 'MAJOR',
    grand => 'GRAND',
  };

  int get level => switch (this) {
    mini => 1,
    minor => 2,
    major => 3,
    grand => 4,
  };

  static JackpotTier? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Map && json.containsKey('custom')) return null;
    return switch (json.toString()) {
      'mini' => JackpotTier.mini,
      'minor' => JackpotTier.minor,
      'major' => JackpotTier.major,
      'grand' => JackpotTier.grand,
      _ => null,
    };
  }

  String toJson() => name;
}

/// Gamble/Risk game result
enum GambleResult {
  win,
  lose,
  draw,
  collected;

  static GambleResult? fromJson(dynamic json) => switch (json?.toString()) {
    'win' => GambleResult.win,
    'lose' => GambleResult.lose,
    'draw' => GambleResult.draw,
    'collected' => GambleResult.collected,
    _ => null,
  };

  String toJson() => name;
}

/// Bonus choice type
enum BonusChoiceType {
  redBlack,
  suit,
  higherLower,
  pick,
  wheel;

  static BonusChoiceType? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Map && json.containsKey('custom')) return null;
    return switch (json.toString()) {
      'red_black' => BonusChoiceType.redBlack,
      'suit' => BonusChoiceType.suit,
      'higher_lower' => BonusChoiceType.higherLower,
      'pick' => BonusChoiceType.pick,
      'wheel' => BonusChoiceType.wheel,
      _ => null,
    };
  }

  String toJson() => switch (this) {
    redBlack => 'red_black',
    suit => 'suit',
    higherLower => 'higher_lower',
    pick => 'pick',
    wheel => 'wheel',
  };
}

/// Symbol position on reels
class SymbolPosition {
  final int reel;
  final int row;

  const SymbolPosition({required this.reel, required this.row});

  factory SymbolPosition.fromJson(Map<String, dynamic> json) => SymbolPosition(
    reel: json['reel'] as int? ?? 0,
    row: json['row'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {'reel': reel, 'row': row};

  @override
  bool operator ==(Object other) =>
      other is SymbolPosition && other.reel == reel && other.row == row;

  @override
  int get hashCode => Object.hash(reel, row);
}

/// Win line definition
class WinLine {
  final int lineIndex;
  final List<SymbolPosition> positions;
  final int symbolId;
  final String? symbolName;
  final int matchCount;
  final double winAmount;
  final double multiplier;

  const WinLine({
    required this.lineIndex,
    required this.positions,
    required this.symbolId,
    this.symbolName,
    required this.matchCount,
    required this.winAmount,
    this.multiplier = 1.0,
  });

  factory WinLine.fromJson(Map<String, dynamic> json) => WinLine(
    lineIndex: json['line_index'] as int? ?? 0,
    positions: (json['positions'] as List<dynamic>?)
        ?.map((p) => SymbolPosition.fromJson(p as Map<String, dynamic>))
        .toList() ?? [],
    symbolId: json['symbol_id'] as int? ?? 0,
    symbolName: json['symbol_name'] as String?,
    matchCount: json['match_count'] as int? ?? 0,
    winAmount: (json['win_amount'] as num?)?.toDouble() ?? 0.0,
    multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
  );

  Map<String, dynamic> toJson() => {
    'line_index': lineIndex,
    'positions': positions.map((p) => p.toJson()).toList(),
    'symbol_id': symbolId,
    if (symbolName != null) 'symbol_name': symbolName,
    'match_count': matchCount,
    'win_amount': winAmount,
    'multiplier': multiplier,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE CATEGORY
// ═══════════════════════════════════════════════════════════════════════════

/// Stage category for grouping
enum StageCategory {
  spinLifecycle,
  anticipation,
  winLifecycle,
  feature,
  cascade,
  bonus,
  gamble,
  jackpot,
  ui,
  special;

  String get displayName => switch (this) {
    spinLifecycle => 'Spin Lifecycle',
    anticipation => 'Anticipation',
    winLifecycle => 'Win Lifecycle',
    feature => 'Features',
    cascade => 'Cascade/Tumble',
    bonus => 'Bonus Games',
    gamble => 'Gamble/Risk',
    jackpot => 'Jackpot',
    ui => 'UI/Idle',
    special => 'Special',
  };

  static StageCategory? fromJson(String? json) => switch (json) {
    'spin_lifecycle' => StageCategory.spinLifecycle,
    'anticipation' => StageCategory.anticipation,
    'win_lifecycle' => StageCategory.winLifecycle,
    'feature' => StageCategory.feature,
    'cascade' => StageCategory.cascade,
    'bonus' => StageCategory.bonus,
    'gamble' => StageCategory.gamble,
    'jackpot' => StageCategory.jackpot,
    'ui' => StageCategory.ui,
    'special' => StageCategory.special,
    _ => null,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE (Sealed Class Hierarchy)
// ═══════════════════════════════════════════════════════════════════════════

/// Canonical game stage — the universal language of slot game flow
sealed class Stage {
  const Stage();

  String get typeName;
  StageCategory get category;
  bool get isLooping => false;
  bool get shouldDuckMusic => false;

  /// Create Stage from type name string and optional data
  static Stage? fromTypeName(String typeName, [Map<String, dynamic>? data]) {
    try {
      final json = {'type': typeName, ...?data};
      return Stage.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  factory Stage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return switch (type) {
      // Spin lifecycle
      'spin_start' => const SpinStart(),
      'reel_spinning' => ReelSpinning(reelIndex: json['reel_index'] as int? ?? 0),
      'reel_stop' => ReelStop(
        reelIndex: json['reel_index'] as int? ?? 0,
        symbols: (json['symbols'] as List<dynamic>?)?.cast<int>() ?? [],
      ),
      'evaluate_wins' => const EvaluateWins(),
      'spin_end' => const SpinEnd(),

      // Anticipation
      'anticipation_on' => AnticipationOn(
        reelIndex: json['reel_index'] as int? ?? 0,
        reason: json['reason'] as String?,
      ),
      'anticipation_off' => AnticipationOff(reelIndex: json['reel_index'] as int? ?? 0),

      // Win lifecycle
      'win_present' => WinPresent(
        winAmount: (json['win_amount'] as num?)?.toDouble() ?? 0.0,
        lineCount: json['line_count'] as int? ?? 0,
      ),
      'win_line_show' => WinLineShow(
        lineIndex: json['line_index'] as int? ?? 0,
        lineAmount: (json['line_amount'] as num?)?.toDouble() ?? 0.0,
      ),
      'rollup_start' => RollupStart(
        targetAmount: (json['target_amount'] as num?)?.toDouble() ?? 0.0,
        startAmount: (json['start_amount'] as num?)?.toDouble() ?? 0.0,
      ),
      'rollup_tick' => RollupTick(
        currentAmount: (json['current_amount'] as num?)?.toDouble() ?? 0.0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      ),
      'rollup_end' => RollupEnd(finalAmount: (json['final_amount'] as num?)?.toDouble() ?? 0.0),
      'bigwin_tier' => BigWinTierStage(
        tier: BigWinTier.fromJson(json['tier']) ?? BigWinTier.win,
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      ),

      // Feature lifecycle
      'feature_enter' => FeatureEnter(
        featureType: FeatureType.fromJson(json['feature_type']) ?? FeatureType.freeSpins,
        totalSteps: json['total_steps'] as int?,
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      ),
      'feature_step' => FeatureStep(
        stepIndex: json['step_index'] as int? ?? 0,
        stepsRemaining: json['steps_remaining'] as int?,
        currentMultiplier: (json['current_multiplier'] as num?)?.toDouble() ?? 1.0,
      ),
      'feature_retrigger' => FeatureRetrigger(
        additionalSteps: json['additional_steps'] as int? ?? 0,
        newTotal: json['new_total'] as int?,
      ),
      'feature_exit' => FeatureExit(totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0),

      // Cascade
      'cascade_start' => const CascadeStart(),
      'cascade_step' => CascadeStep(
        stepIndex: json['step_index'] as int? ?? 0,
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      ),
      'cascade_end' => CascadeEnd(
        totalSteps: json['total_steps'] as int? ?? 0,
        totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0,
      ),

      // Bonus
      'bonus_enter' => BonusEnter(bonusName: json['bonus_name'] as String?),
      'bonus_choice' => BonusChoice(
        choiceType: BonusChoiceType.fromJson(json['choice_type']) ?? BonusChoiceType.pick,
        optionCount: json['option_count'] as int? ?? 0,
      ),
      'bonus_reveal' => BonusReveal(
        revealedValue: (json['revealed_value'] as num?)?.toDouble() ?? 0.0,
        isTerminal: json['is_terminal'] as bool? ?? false,
      ),
      'bonus_exit' => BonusExit(totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0),

      // Gamble
      'gamble_start' => GambleStart(stakeAmount: (json['stake_amount'] as num?)?.toDouble() ?? 0.0),
      'gamble_choice' => GambleChoice(
        choiceType: BonusChoiceType.fromJson(json['choice_type']) ?? BonusChoiceType.redBlack,
      ),
      'gamble_result' => GambleResultStage(
        result: GambleResult.fromJson(json['result']) ?? GambleResult.lose,
        newAmount: (json['new_amount'] as num?)?.toDouble() ?? 0.0,
      ),
      'gamble_end' => GambleEnd(collectedAmount: (json['collected_amount'] as num?)?.toDouble() ?? 0.0),

      // Jackpot
      'jackpot_trigger' => JackpotTrigger(tier: JackpotTier.fromJson(json['tier']) ?? JackpotTier.mini),
      'jackpot_present' => JackpotPresent(
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        tier: JackpotTier.fromJson(json['tier']) ?? JackpotTier.mini,
      ),
      'jackpot_end' => const JackpotEnd(),

      // UI/Idle
      'idle_start' => const IdleStart(),
      'idle_loop' => const IdleLoop(),
      'menu_open' => MenuOpen(menuName: json['menu_name'] as String?),
      'menu_close' => const MenuClose(),
      'autoplay_start' => AutoplayStart(spinCount: json['spin_count'] as int?),
      'autoplay_stop' => AutoplayStop(reason: json['reason'] as String?),

      // Special
      'symbol_transform' => SymbolTransform(
        reelIndex: json['reel_index'] as int? ?? 0,
        rowIndex: json['row_index'] as int? ?? 0,
        fromSymbol: json['from_symbol'] as int?,
        toSymbol: json['to_symbol'] as int? ?? 0,
      ),
      'wild_expand' => WildExpand(
        reelIndex: json['reel_index'] as int? ?? 0,
        direction: json['direction'] as String?,
      ),
      'multiplier_change' => MultiplierChange(
        newValue: (json['new_value'] as num?)?.toDouble() ?? 1.0,
        oldValue: (json['old_value'] as num?)?.toDouble(),
      ),
      'custom' => CustomStage(
        name: json['name'] as String? ?? 'unknown',
        id: json['id'] as int? ?? 0,
      ),

      _ => CustomStage(name: type ?? 'unknown', id: 0),
    };
  }

  Map<String, dynamic> toJson();
}

// ─── SPIN LIFECYCLE ─────────────────────────────────────────────────────────

class SpinStart extends Stage {
  const SpinStart();

  @override String get typeName => 'spin_start';
  @override StageCategory get category => StageCategory.spinLifecycle;
  @override Map<String, dynamic> toJson() => {'type': 'spin_start'};
}

class ReelSpinning extends Stage {
  final int reelIndex;
  const ReelSpinning({required this.reelIndex});

  @override String get typeName => 'reel_spinning';
  @override StageCategory get category => StageCategory.spinLifecycle;
  @override bool get isLooping => true;
  @override Map<String, dynamic> toJson() => {'type': 'reel_spinning', 'reel_index': reelIndex};
}

class ReelStop extends Stage {
  final int reelIndex;
  final List<int> symbols;
  const ReelStop({required this.reelIndex, this.symbols = const []});

  @override String get typeName => 'reel_stop';
  @override StageCategory get category => StageCategory.spinLifecycle;
  @override Map<String, dynamic> toJson() => {
    'type': 'reel_stop',
    'reel_index': reelIndex,
    'symbols': symbols,
  };
}

class EvaluateWins extends Stage {
  const EvaluateWins();

  @override String get typeName => 'evaluate_wins';
  @override StageCategory get category => StageCategory.spinLifecycle;
  @override Map<String, dynamic> toJson() => {'type': 'evaluate_wins'};
}

class SpinEnd extends Stage {
  const SpinEnd();

  @override String get typeName => 'spin_end';
  @override StageCategory get category => StageCategory.spinLifecycle;
  @override Map<String, dynamic> toJson() => {'type': 'spin_end'};
}

// ─── ANTICIPATION ───────────────────────────────────────────────────────────

class AnticipationOn extends Stage {
  final int reelIndex;
  final String? reason;
  const AnticipationOn({required this.reelIndex, this.reason});

  @override String get typeName => 'anticipation_on';
  @override StageCategory get category => StageCategory.anticipation;
  @override bool get isLooping => true;
  @override Map<String, dynamic> toJson() => {
    'type': 'anticipation_on',
    'reel_index': reelIndex,
    if (reason != null) 'reason': reason,
  };
}

class AnticipationOff extends Stage {
  final int reelIndex;
  const AnticipationOff({required this.reelIndex});

  @override String get typeName => 'anticipation_off';
  @override StageCategory get category => StageCategory.anticipation;
  @override Map<String, dynamic> toJson() => {'type': 'anticipation_off', 'reel_index': reelIndex};
}

// ─── WIN LIFECYCLE ──────────────────────────────────────────────────────────

class WinPresent extends Stage {
  final double winAmount;
  final int lineCount;
  const WinPresent({this.winAmount = 0.0, this.lineCount = 0});

  @override String get typeName => 'win_present';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override Map<String, dynamic> toJson() => {
    'type': 'win_present',
    'win_amount': winAmount,
    'line_count': lineCount,
  };
}

class WinLineShow extends Stage {
  final int lineIndex;
  final double lineAmount;
  const WinLineShow({required this.lineIndex, this.lineAmount = 0.0});

  @override String get typeName => 'win_line_show';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override Map<String, dynamic> toJson() => {
    'type': 'win_line_show',
    'line_index': lineIndex,
    'line_amount': lineAmount,
  };
}

class RollupStart extends Stage {
  final double targetAmount;
  final double startAmount;
  const RollupStart({required this.targetAmount, this.startAmount = 0.0});

  @override String get typeName => 'rollup_start';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override Map<String, dynamic> toJson() => {
    'type': 'rollup_start',
    'target_amount': targetAmount,
    'start_amount': startAmount,
  };
}

class RollupTick extends Stage {
  final double currentAmount;
  final double progress;
  const RollupTick({required this.currentAmount, required this.progress});

  @override String get typeName => 'rollup_tick';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override bool get isLooping => true;
  @override Map<String, dynamic> toJson() => {
    'type': 'rollup_tick',
    'current_amount': currentAmount,
    'progress': progress,
  };
}

class RollupEnd extends Stage {
  final double finalAmount;
  const RollupEnd({required this.finalAmount});

  @override String get typeName => 'rollup_end';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override Map<String, dynamic> toJson() => {'type': 'rollup_end', 'final_amount': finalAmount};
}

class BigWinTierStage extends Stage {
  final BigWinTier tier;
  final double amount;
  const BigWinTierStage({required this.tier, this.amount = 0.0});

  @override String get typeName => 'bigwin_tier';
  @override StageCategory get category => StageCategory.winLifecycle;
  @override bool get shouldDuckMusic => true;
  @override Map<String, dynamic> toJson() => {
    'type': 'bigwin_tier',
    'tier': tier.toJson(),
    'amount': amount,
  };
}

// ─── FEATURE LIFECYCLE ──────────────────────────────────────────────────────

class FeatureEnter extends Stage {
  final FeatureType featureType;
  final int? totalSteps;
  final double multiplier;
  const FeatureEnter({required this.featureType, this.totalSteps, this.multiplier = 1.0});

  @override String get typeName => 'feature_enter';
  @override StageCategory get category => StageCategory.feature;
  @override bool get shouldDuckMusic => true;
  @override Map<String, dynamic> toJson() => {
    'type': 'feature_enter',
    'feature_type': featureType.toJson(),
    if (totalSteps != null) 'total_steps': totalSteps,
    'multiplier': multiplier,
  };
}

class FeatureStep extends Stage {
  final int stepIndex;
  final int? stepsRemaining;
  final double currentMultiplier;
  const FeatureStep({required this.stepIndex, this.stepsRemaining, this.currentMultiplier = 1.0});

  @override String get typeName => 'feature_step';
  @override StageCategory get category => StageCategory.feature;
  @override Map<String, dynamic> toJson() => {
    'type': 'feature_step',
    'step_index': stepIndex,
    if (stepsRemaining != null) 'steps_remaining': stepsRemaining,
    'current_multiplier': currentMultiplier,
  };
}

class FeatureRetrigger extends Stage {
  final int additionalSteps;
  final int? newTotal;
  const FeatureRetrigger({required this.additionalSteps, this.newTotal});

  @override String get typeName => 'feature_retrigger';
  @override StageCategory get category => StageCategory.feature;
  @override Map<String, dynamic> toJson() => {
    'type': 'feature_retrigger',
    'additional_steps': additionalSteps,
    if (newTotal != null) 'new_total': newTotal,
  };
}

class FeatureExit extends Stage {
  final double totalWin;
  const FeatureExit({this.totalWin = 0.0});

  @override String get typeName => 'feature_exit';
  @override StageCategory get category => StageCategory.feature;
  @override Map<String, dynamic> toJson() => {'type': 'feature_exit', 'total_win': totalWin};
}

// ─── CASCADE ────────────────────────────────────────────────────────────────

class CascadeStart extends Stage {
  const CascadeStart();

  @override String get typeName => 'cascade_start';
  @override StageCategory get category => StageCategory.cascade;
  @override Map<String, dynamic> toJson() => {'type': 'cascade_start'};
}

class CascadeStep extends Stage {
  final int stepIndex;
  final double multiplier;
  const CascadeStep({required this.stepIndex, this.multiplier = 1.0});

  @override String get typeName => 'cascade_step';
  @override StageCategory get category => StageCategory.cascade;
  @override Map<String, dynamic> toJson() => {
    'type': 'cascade_step',
    'step_index': stepIndex,
    'multiplier': multiplier,
  };
}

class CascadeEnd extends Stage {
  final int totalSteps;
  final double totalWin;
  const CascadeEnd({required this.totalSteps, this.totalWin = 0.0});

  @override String get typeName => 'cascade_end';
  @override StageCategory get category => StageCategory.cascade;
  @override Map<String, dynamic> toJson() => {
    'type': 'cascade_end',
    'total_steps': totalSteps,
    'total_win': totalWin,
  };
}

// ─── BONUS ──────────────────────────────────────────────────────────────────

class BonusEnter extends Stage {
  final String? bonusName;
  const BonusEnter({this.bonusName});

  @override String get typeName => 'bonus_enter';
  @override StageCategory get category => StageCategory.bonus;
  @override Map<String, dynamic> toJson() => {
    'type': 'bonus_enter',
    if (bonusName != null) 'bonus_name': bonusName,
  };
}

class BonusChoice extends Stage {
  final BonusChoiceType choiceType;
  final int optionCount;
  const BonusChoice({required this.choiceType, this.optionCount = 0});

  @override String get typeName => 'bonus_choice';
  @override StageCategory get category => StageCategory.bonus;
  @override Map<String, dynamic> toJson() => {
    'type': 'bonus_choice',
    'choice_type': choiceType.toJson(),
    'option_count': optionCount,
  };
}

class BonusReveal extends Stage {
  final double revealedValue;
  final bool isTerminal;
  const BonusReveal({this.revealedValue = 0.0, this.isTerminal = false});

  @override String get typeName => 'bonus_reveal';
  @override StageCategory get category => StageCategory.bonus;
  @override Map<String, dynamic> toJson() => {
    'type': 'bonus_reveal',
    'revealed_value': revealedValue,
    'is_terminal': isTerminal,
  };
}

class BonusExit extends Stage {
  final double totalWin;
  const BonusExit({this.totalWin = 0.0});

  @override String get typeName => 'bonus_exit';
  @override StageCategory get category => StageCategory.bonus;
  @override Map<String, dynamic> toJson() => {'type': 'bonus_exit', 'total_win': totalWin};
}

// ─── GAMBLE ─────────────────────────────────────────────────────────────────

class GambleStart extends Stage {
  final double stakeAmount;
  const GambleStart({required this.stakeAmount});

  @override String get typeName => 'gamble_start';
  @override StageCategory get category => StageCategory.gamble;
  @override Map<String, dynamic> toJson() => {'type': 'gamble_start', 'stake_amount': stakeAmount};
}

class GambleChoice extends Stage {
  final BonusChoiceType choiceType;
  const GambleChoice({required this.choiceType});

  @override String get typeName => 'gamble_choice';
  @override StageCategory get category => StageCategory.gamble;
  @override Map<String, dynamic> toJson() => {'type': 'gamble_choice', 'choice_type': choiceType.toJson()};
}

class GambleResultStage extends Stage {
  final GambleResult result;
  final double newAmount;
  const GambleResultStage({required this.result, this.newAmount = 0.0});

  @override String get typeName => 'gamble_result';
  @override StageCategory get category => StageCategory.gamble;
  @override Map<String, dynamic> toJson() => {
    'type': 'gamble_result',
    'result': result.toJson(),
    'new_amount': newAmount,
  };
}

class GambleEnd extends Stage {
  final double collectedAmount;
  const GambleEnd({required this.collectedAmount});

  @override String get typeName => 'gamble_end';
  @override StageCategory get category => StageCategory.gamble;
  @override Map<String, dynamic> toJson() => {'type': 'gamble_end', 'collected_amount': collectedAmount};
}

// ─── JACKPOT ────────────────────────────────────────────────────────────────

class JackpotTrigger extends Stage {
  final JackpotTier tier;
  const JackpotTrigger({required this.tier});

  @override String get typeName => 'jackpot_trigger';
  @override StageCategory get category => StageCategory.jackpot;
  @override bool get shouldDuckMusic => true;
  @override Map<String, dynamic> toJson() => {'type': 'jackpot_trigger', 'tier': tier.toJson()};
}

class JackpotPresent extends Stage {
  final double amount;
  final JackpotTier tier;
  const JackpotPresent({required this.amount, required this.tier});

  @override String get typeName => 'jackpot_present';
  @override StageCategory get category => StageCategory.jackpot;
  @override bool get shouldDuckMusic => true;
  @override Map<String, dynamic> toJson() => {
    'type': 'jackpot_present',
    'amount': amount,
    'tier': tier.toJson(),
  };
}

class JackpotEnd extends Stage {
  const JackpotEnd();

  @override String get typeName => 'jackpot_end';
  @override StageCategory get category => StageCategory.jackpot;
  @override Map<String, dynamic> toJson() => {'type': 'jackpot_end'};
}

// ─── UI / IDLE ──────────────────────────────────────────────────────────────

class IdleStart extends Stage {
  const IdleStart();

  @override String get typeName => 'idle_start';
  @override StageCategory get category => StageCategory.ui;
  @override Map<String, dynamic> toJson() => {'type': 'idle_start'};
}

class IdleLoop extends Stage {
  const IdleLoop();

  @override String get typeName => 'idle_loop';
  @override StageCategory get category => StageCategory.ui;
  @override bool get isLooping => true;
  @override Map<String, dynamic> toJson() => {'type': 'idle_loop'};
}

class MenuOpen extends Stage {
  final String? menuName;
  const MenuOpen({this.menuName});

  @override String get typeName => 'menu_open';
  @override StageCategory get category => StageCategory.ui;
  @override Map<String, dynamic> toJson() => {
    'type': 'menu_open',
    if (menuName != null) 'menu_name': menuName,
  };
}

class MenuClose extends Stage {
  const MenuClose();

  @override String get typeName => 'menu_close';
  @override StageCategory get category => StageCategory.ui;
  @override Map<String, dynamic> toJson() => {'type': 'menu_close'};
}

class AutoplayStart extends Stage {
  final int? spinCount;
  const AutoplayStart({this.spinCount});

  @override String get typeName => 'autoplay_start';
  @override StageCategory get category => StageCategory.ui;
  @override Map<String, dynamic> toJson() => {
    'type': 'autoplay_start',
    if (spinCount != null) 'spin_count': spinCount,
  };
}

class AutoplayStop extends Stage {
  final String? reason;
  const AutoplayStop({this.reason});

  @override String get typeName => 'autoplay_stop';
  @override StageCategory get category => StageCategory.ui;
  @override Map<String, dynamic> toJson() => {
    'type': 'autoplay_stop',
    if (reason != null) 'reason': reason,
  };
}

// ─── SPECIAL ────────────────────────────────────────────────────────────────

class SymbolTransform extends Stage {
  final int reelIndex;
  final int rowIndex;
  final int? fromSymbol;
  final int toSymbol;
  const SymbolTransform({
    required this.reelIndex,
    required this.rowIndex,
    this.fromSymbol,
    required this.toSymbol,
  });

  @override String get typeName => 'symbol_transform';
  @override StageCategory get category => StageCategory.special;
  @override Map<String, dynamic> toJson() => {
    'type': 'symbol_transform',
    'reel_index': reelIndex,
    'row_index': rowIndex,
    if (fromSymbol != null) 'from_symbol': fromSymbol,
    'to_symbol': toSymbol,
  };
}

class WildExpand extends Stage {
  final int reelIndex;
  final String? direction;
  const WildExpand({required this.reelIndex, this.direction});

  @override String get typeName => 'wild_expand';
  @override StageCategory get category => StageCategory.special;
  @override Map<String, dynamic> toJson() => {
    'type': 'wild_expand',
    'reel_index': reelIndex,
    if (direction != null) 'direction': direction,
  };
}

class MultiplierChange extends Stage {
  final double newValue;
  final double? oldValue;
  const MultiplierChange({required this.newValue, this.oldValue});

  @override String get typeName => 'multiplier_change';
  @override StageCategory get category => StageCategory.special;
  @override Map<String, dynamic> toJson() => {
    'type': 'multiplier_change',
    'new_value': newValue,
    if (oldValue != null) 'old_value': oldValue,
  };
}

class CustomStage extends Stage {
  final String name;
  final int id;
  const CustomStage({required this.name, this.id = 0});

  @override String get typeName => 'custom';
  @override StageCategory get category => StageCategory.special;
  @override Map<String, dynamic> toJson() => {'type': 'custom', 'name': name, 'id': id};
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE EVENT
// ═══════════════════════════════════════════════════════════════════════════

/// A stage event with full metadata
class StageEvent {
  final Stage stage;
  final double timestampMs;
  final StagePayload payload;
  final String? sourceEvent;
  final List<String> tags;

  const StageEvent({
    required this.stage,
    required this.timestampMs,
    this.payload = const StagePayload(),
    this.sourceEvent,
    this.tags = const [],
  });

  String get typeName => stage.typeName;

  factory StageEvent.fromJson(Map<String, dynamic> json) => StageEvent(
    stage: Stage.fromJson(json['stage'] as Map<String, dynamic>? ?? json),
    timestampMs: (json['timestamp_ms'] as num?)?.toDouble() ?? 0.0,
    payload: StagePayload.fromJson(json['payload'] as Map<String, dynamic>? ?? {}),
    sourceEvent: json['source_event'] as String?,
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'stage': stage.toJson(),
    'timestamp_ms': timestampMs,
    'payload': payload.toJson(),
    if (sourceEvent != null) 'source_event': sourceEvent,
    if (tags.isNotEmpty) 'tags': tags,
  };

  StageEvent copyWith({
    Stage? stage,
    double? timestampMs,
    StagePayload? payload,
    String? sourceEvent,
    List<String>? tags,
  }) => StageEvent(
    stage: stage ?? this.stage,
    timestampMs: timestampMs ?? this.timestampMs,
    payload: payload ?? this.payload,
    sourceEvent: sourceEvent ?? this.sourceEvent,
    tags: tags ?? this.tags,
  );
}

/// Additional payload data for a stage event
class StagePayload {
  final double? winAmount;
  final double? betAmount;
  final double? winRatio;
  final List<WinLine> winLines;
  final int? symbolId;
  final String? symbolName;
  final List<List<int>>? reelGrid;
  final String? featureName;
  final int? spinsRemaining;
  final double? multiplier;
  final String? jackpotName;
  final double? jackpotPool;
  final double? balance;
  final String? sessionId;
  final String? spinId;
  final Map<String, dynamic>? custom;

  const StagePayload({
    this.winAmount,
    this.betAmount,
    this.winRatio,
    this.winLines = const [],
    this.symbolId,
    this.symbolName,
    this.reelGrid,
    this.featureName,
    this.spinsRemaining,
    this.multiplier,
    this.jackpotName,
    this.jackpotPool,
    this.balance,
    this.sessionId,
    this.spinId,
    this.custom,
  });

  factory StagePayload.fromJson(Map<String, dynamic> json) => StagePayload(
    winAmount: (json['win_amount'] as num?)?.toDouble(),
    betAmount: (json['bet_amount'] as num?)?.toDouble(),
    winRatio: (json['win_ratio'] as num?)?.toDouble(),
    winLines: (json['win_lines'] as List<dynamic>?)
        ?.map((w) => WinLine.fromJson(w as Map<String, dynamic>))
        .toList() ?? [],
    symbolId: json['symbol_id'] as int?,
    symbolName: json['symbol_name'] as String?,
    reelGrid: (json['reel_grid'] as List<dynamic>?)
        ?.map((row) => (row as List<dynamic>).cast<int>())
        .toList(),
    featureName: json['feature_name'] as String?,
    spinsRemaining: json['spins_remaining'] as int?,
    multiplier: (json['multiplier'] as num?)?.toDouble(),
    jackpotName: json['jackpot_name'] as String?,
    jackpotPool: (json['jackpot_pool'] as num?)?.toDouble(),
    balance: (json['balance'] as num?)?.toDouble(),
    sessionId: json['session_id'] as String?,
    spinId: json['spin_id'] as String?,
    custom: json['custom'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (winAmount != null) map['win_amount'] = winAmount;
    if (betAmount != null) map['bet_amount'] = betAmount;
    if (winRatio != null) map['win_ratio'] = winRatio;
    if (winLines.isNotEmpty) map['win_lines'] = winLines.map((w) => w.toJson()).toList();
    if (symbolId != null) map['symbol_id'] = symbolId;
    if (symbolName != null) map['symbol_name'] = symbolName;
    if (reelGrid != null) map['reel_grid'] = reelGrid;
    if (featureName != null) map['feature_name'] = featureName;
    if (spinsRemaining != null) map['spins_remaining'] = spinsRemaining;
    if (multiplier != null) map['multiplier'] = multiplier;
    if (jackpotName != null) map['jackpot_name'] = jackpotName;
    if (jackpotPool != null) map['jackpot_pool'] = jackpotPool;
    if (balance != null) map['balance'] = balance;
    if (sessionId != null) map['session_id'] = sessionId;
    if (spinId != null) map['spin_id'] = spinId;
    if (custom != null) map['custom'] = custom;
    return map;
  }

  double? calculateRatio() {
    if (winAmount != null && betAmount != null && betAmount! > 0) {
      return winAmount! / betAmount!;
    }
    return null;
  }

  bool isBigWin(double threshold) => (calculateRatio() ?? 0) >= threshold;
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TRACE
// ═══════════════════════════════════════════════════════════════════════════

/// A complete trace of stage events for one spin or session
class StageTrace {
  final String traceId;
  final String gameId;
  final String? sessionId;
  final String? spinId;
  final List<StageEvent> events;
  final DateTime recordedAt;
  final TimingProfile? timingProfile;
  final String? adapterId;
  final Map<String, dynamic> metadata;

  StageTrace({
    required this.traceId,
    required this.gameId,
    this.sessionId,
    this.spinId,
    List<StageEvent>? events,
    DateTime? recordedAt,
    this.timingProfile,
    this.adapterId,
    Map<String, dynamic>? metadata,
  })  : events = events ?? [],
        recordedAt = recordedAt ?? DateTime.now(),
        metadata = metadata ?? {};

  factory StageTrace.fromJson(Map<String, dynamic> json) => StageTrace(
    traceId: json['trace_id'] as String? ?? '',
    gameId: json['game_id'] as String? ?? '',
    sessionId: json['session_id'] as String?,
    spinId: json['spin_id'] as String?,
    events: (json['events'] as List<dynamic>?)
        ?.map((e) => StageEvent.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    recordedAt: json['recorded_at'] != null
        ? DateTime.parse(json['recorded_at'] as String)
        : DateTime.now(),
    timingProfile: TimingProfile.fromJson(json['timing_profile']),
    adapterId: json['adapter_id'] as String?,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
  );

  Map<String, dynamic> toJson() => {
    'trace_id': traceId,
    'game_id': gameId,
    if (sessionId != null) 'session_id': sessionId,
    if (spinId != null) 'spin_id': spinId,
    'events': events.map((e) => e.toJson()).toList(),
    'recorded_at': recordedAt.toIso8601String(),
    if (timingProfile != null) 'timing_profile': timingProfile!.toJson(),
    if (adapterId != null) 'adapter_id': adapterId,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  double get durationMs {
    if (events.isEmpty) return 0.0;
    final first = events.first.timestampMs;
    final last = events.last.timestampMs;
    return last - first;
  }

  List<StageEvent> eventsByCategory(StageCategory category) =>
      events.where((e) => e.stage.category == category).toList();

  List<StageEvent> eventsByType(String typeName) =>
      events.where((e) => e.stage.typeName == typeName).toList();

  bool hasStage(String typeName) =>
      events.any((e) => e.stage.typeName == typeName);

  List<StageEvent> get reelStops => eventsByType('reel_stop');

  double get totalWin {
    for (final event in events.reversed) {
      if (event.payload.winAmount != null) {
        return event.payload.winAmount!;
      }
      switch (event.stage) {
        case WinPresent(winAmount: final amount):
          return amount;
        case BigWinTierStage(amount: final amount):
          return amount;
        case FeatureExit(totalWin: final amount):
          return amount;
        default:
          continue;
      }
    }
    return 0.0;
  }

  BigWinTier? get maxBigWinTier {
    BigWinTier? max;
    for (final event in events) {
      if (event.stage case BigWinTierStage(tier: final tier)) {
        if (max == null || tier.minRatio > max.minRatio) {
          max = tier;
        }
      }
    }
    return max;
  }

  bool get hasFeature => hasStage('feature_enter');
  bool get hasJackpot => hasStage('jackpot_trigger');

  FeatureType? get featureType {
    for (final event in events) {
      if (event.stage case FeatureEnter(featureType: final ft)) {
        return ft;
      }
    }
    return null;
  }

  TraceSummary get summary => TraceSummary(
    traceId: traceId,
    gameId: gameId,
    eventCount: events.length,
    durationMs: durationMs,
    totalWin: totalWin,
    hasFeature: hasFeature,
    hasJackpot: hasJackpot,
    maxBigWinTier: maxBigWinTier,
  );
}

/// Summary of a trace for quick overview
class TraceSummary {
  final String traceId;
  final String gameId;
  final int eventCount;
  final double durationMs;
  final double totalWin;
  final bool hasFeature;
  final bool hasJackpot;
  final BigWinTier? maxBigWinTier;

  const TraceSummary({
    required this.traceId,
    required this.gameId,
    required this.eventCount,
    required this.durationMs,
    required this.totalWin,
    required this.hasFeature,
    required this.hasJackpot,
    this.maxBigWinTier,
  });

  factory TraceSummary.fromJson(Map<String, dynamic> json) => TraceSummary(
    traceId: json['trace_id'] as String? ?? '',
    gameId: json['game_id'] as String? ?? '',
    eventCount: json['event_count'] as int? ?? 0,
    durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0.0,
    totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0,
    hasFeature: json['has_feature'] as bool? ?? false,
    hasJackpot: json['has_jackpot'] as bool? ?? false,
    maxBigWinTier: BigWinTier.fromJson(json['max_bigwin_tier']),
  );

  Map<String, dynamic> toJson() => {
    'trace_id': traceId,
    'game_id': gameId,
    'event_count': eventCount,
    'duration_ms': durationMs,
    'total_win': totalWin,
    'has_feature': hasFeature,
    'has_jackpot': hasJackpot,
    if (maxBigWinTier != null) 'max_bigwin_tier': maxBigWinTier!.toJson(),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMING
// ═══════════════════════════════════════════════════════════════════════════

/// Timing profile identifier
enum TimingProfile {
  normal,
  turbo,
  mobile,
  studio,
  instant;

  String get displayName => switch (this) {
    normal => 'Normal',
    turbo => 'Turbo',
    mobile => 'Mobile',
    studio => 'Studio',
    instant => 'Instant',
  };

  static TimingProfile? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is Map && json.containsKey('custom')) return null;
    return switch (json.toString()) {
      'normal' => TimingProfile.normal,
      'turbo' => TimingProfile.turbo,
      'mobile' => TimingProfile.mobile,
      'studio' => TimingProfile.studio,
      'instant' => TimingProfile.instant,
      _ => null,
    };
  }

  String toJson() => name;
}

/// A stage event with resolved timing
class TimedStageEvent {
  final StageEvent event;
  final double absoluteTimeMs;
  final double durationMs;

  const TimedStageEvent({
    required this.event,
    required this.absoluteTimeMs,
    required this.durationMs,
  });

  bool get isLooping => durationMs == double.infinity;

  double? get endTime => isLooping ? null : absoluteTimeMs + durationMs;

  factory TimedStageEvent.fromJson(Map<String, dynamic> json) => TimedStageEvent(
    event: StageEvent.fromJson(json['event'] as Map<String, dynamic>),
    absoluteTimeMs: (json['absolute_time_ms'] as num?)?.toDouble() ?? 0.0,
    durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0.0,
  );

  Map<String, dynamic> toJson() => {
    'event': event.toJson(),
    'absolute_time_ms': absoluteTimeMs,
    'duration_ms': durationMs,
  };
}

/// A trace with resolved timing
class TimedStageTrace {
  final String traceId;
  final String gameId;
  final List<TimedStageEvent> events;
  final double totalDurationMs;
  final TimingProfile profile;

  const TimedStageTrace({
    required this.traceId,
    required this.gameId,
    required this.events,
    required this.totalDurationMs,
    required this.profile,
  });

  factory TimedStageTrace.fromJson(Map<String, dynamic> json) => TimedStageTrace(
    traceId: json['trace_id'] as String? ?? '',
    gameId: json['game_id'] as String? ?? '',
    events: (json['events'] as List<dynamic>?)
        ?.map((e) => TimedStageEvent.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    totalDurationMs: (json['total_duration_ms'] as num?)?.toDouble() ?? 0.0,
    profile: TimingProfile.fromJson(json['profile']) ?? TimingProfile.normal,
  );

  Map<String, dynamic> toJson() => {
    'trace_id': traceId,
    'game_id': gameId,
    'events': events.map((e) => e.toJson()).toList(),
    'total_duration_ms': totalDurationMs,
    'profile': profile.toJson(),
  };

  List<TimedStageEvent> eventsAt(double timeMs) => events.where((e) =>
      e.absoluteTimeMs <= timeMs &&
      (e.isLooping || e.absoluteTimeMs + e.durationMs > timeMs)
  ).toList();

  TimedStageEvent? stageAt(double timeMs) {
    for (final event in events.reversed) {
      if (event.absoluteTimeMs <= timeMs) {
        return event;
      }
    }
    return null;
  }

  TimedStageEvent? findStage(String typeName) =>
      events.cast<TimedStageEvent?>().firstWhere(
        (e) => e!.event.stage.typeName == typeName,
        orElse: () => null,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// ADAPTER WIZARD (for auto-detection)
// ═══════════════════════════════════════════════════════════════════════════

/// Ingest layer type
enum IngestLayer {
  directEvent,
  snapshotDiff,
  ruleBased;

  String get displayName => switch (this) {
    directEvent => 'Direct Event (Layer 1)',
    snapshotDiff => 'Snapshot Diff (Layer 2)',
    ruleBased => 'Rule-Based (Layer 3)',
  };

  static IngestLayer? fromJson(String? json) => switch (json) {
    'direct_event' || 'DirectEvent' => IngestLayer.directEvent,
    'snapshot_diff' || 'SnapshotDiff' => IngestLayer.snapshotDiff,
    'rule_based' || 'RuleBased' => IngestLayer.ruleBased,
    _ => null,
  };

  /// Create from FFI int value (0=DirectEvent, 1=SnapshotDiff, 2=RuleBased)
  static IngestLayer fromInt(int value) => switch (value) {
    0 => IngestLayer.directEvent,
    1 => IngestLayer.snapshotDiff,
    2 => IngestLayer.ruleBased,
    _ => IngestLayer.directEvent,
  };

  String toJson() => switch (this) {
    directEvent => 'direct_event',
    snapshotDiff => 'snapshot_diff',
    ruleBased => 'rule_based',
  };
}

/// Detected event from wizard analysis
class DetectedEvent {
  final String eventName;
  final String? suggestedStage;
  final int sampleCount;
  final Map<String, dynamic>? samplePayload;

  const DetectedEvent({
    required this.eventName,
    this.suggestedStage,
    required this.sampleCount,
    this.samplePayload,
  });

  factory DetectedEvent.fromJson(Map<String, dynamic> json) => DetectedEvent(
    eventName: json['event_name'] as String? ?? '',
    suggestedStage: json['suggested_stage'] as String?,
    sampleCount: json['sample_count'] as int? ?? 0,
    samplePayload: json['sample_payload'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toJson() => {
    'event_name': eventName,
    if (suggestedStage != null) 'suggested_stage': suggestedStage,
    'sample_count': sampleCount,
    if (samplePayload != null) 'sample_payload': samplePayload,
  };
}

/// Wizard analysis result
class WizardResult {
  final String? detectedCompany;
  final String? detectedEngine;
  final IngestLayer recommendedLayer;
  final double confidence;
  final List<DetectedEvent> detectedEvents;
  final String? configToml;

  const WizardResult({
    this.detectedCompany,
    this.detectedEngine,
    required this.recommendedLayer,
    required this.confidence,
    this.detectedEvents = const [],
    this.configToml,
  });

  factory WizardResult.fromJson(Map<String, dynamic> json) => WizardResult(
    detectedCompany: json['detected_company'] as String?,
    detectedEngine: json['detected_engine'] as String?,
    recommendedLayer: IngestLayer.fromJson(json['recommended_layer'] as String?) ?? IngestLayer.directEvent,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    detectedEvents: (json['detected_events'] as List<dynamic>?)
        ?.map((e) => DetectedEvent.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    configToml: json['config_toml'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (detectedCompany != null) 'detected_company': detectedCompany,
    if (detectedEngine != null) 'detected_engine': detectedEngine,
    'recommended_layer': recommendedLayer.toJson(),
    'confidence': confidence,
    'detected_events': detectedEvents.map((e) => e.toJson()).toList(),
    if (configToml != null) 'config_toml': configToml,
  };

  String get confidenceLabel {
    if (confidence >= 0.9) return 'Excellent';
    if (confidence >= 0.7) return 'Good';
    if (confidence >= 0.5) return 'Fair';
    return 'Low';
  }
}

/// Adapter info for registry display
class AdapterInfo {
  final String adapterId;
  final String companyName;
  final String engineName;

  const AdapterInfo({
    required this.adapterId,
    required this.companyName,
    required this.engineName,
  });

  factory AdapterInfo.fromJson(Map<String, dynamic> json) => AdapterInfo(
    adapterId: json['adapter_id'] as String? ?? '',
    companyName: json['company_name'] as String? ?? '',
    engineName: json['engine_name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'adapter_id': adapterId,
    'company_name': companyName,
    'engine_name': engineName,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// ENGINE CONNECTION (Live Mode)
// ═══════════════════════════════════════════════════════════════════════════

/// Connection protocol
enum ConnectionProtocol {
  webSocket,
  tcp;

  String get displayName => switch (this) {
    webSocket => 'WebSocket',
    tcp => 'TCP',
  };
}

/// Engine connection state
enum EngineConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error;

  bool get isConnected => this == EngineConnectionState.connected;
  bool get isConnecting => this == EngineConnectionState.connecting;

  static EngineConnectionState? fromJson(String? json) => switch (json) {
    'disconnected' || 'Disconnected' => EngineConnectionState.disconnected,
    'connecting' || 'Connecting' => EngineConnectionState.connecting,
    'connected' || 'Connected' => EngineConnectionState.connected,
    'disconnecting' || 'Disconnecting' => EngineConnectionState.disconnecting,
    'error' || 'Error' => EngineConnectionState.error,
    _ => null,
  };
}

/// Connection configuration
class ConnectionConfig {
  final ConnectionProtocol protocol;
  final String host;
  final int port;
  final String? url;
  final String adapterId;
  final String? authToken;
  final int timeoutMs;

  const ConnectionConfig({
    required this.protocol,
    this.host = 'localhost',
    this.port = 8080,
    this.url,
    this.adapterId = 'generic',
    this.authToken,
    this.timeoutMs = 5000,
  });

  factory ConnectionConfig.webSocket(String url, {String adapterId = 'generic'}) =>
      ConnectionConfig(
        protocol: ConnectionProtocol.webSocket,
        url: url,
        adapterId: adapterId,
      );

  factory ConnectionConfig.tcp(String host, int port, {String adapterId = 'generic'}) =>
      ConnectionConfig(
        protocol: ConnectionProtocol.tcp,
        host: host,
        port: port,
        adapterId: adapterId,
      );

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'] as Map<String, dynamic>?;
    if (protocol?.containsKey('web_socket') == true || protocol?.containsKey('WebSocket') == true) {
      final ws = protocol!['web_socket'] ?? protocol['WebSocket'];
      return ConnectionConfig(
        protocol: ConnectionProtocol.webSocket,
        url: (ws as Map<String, dynamic>)['url'] as String?,
        adapterId: json['adapter_id'] as String? ?? 'generic',
        authToken: json['auth_token'] as String?,
        timeoutMs: json['timeout_ms'] as int? ?? 5000,
      );
    } else if (protocol?.containsKey('tcp') == true || protocol?.containsKey('Tcp') == true) {
      final tcp = protocol!['tcp'] ?? protocol['Tcp'];
      return ConnectionConfig(
        protocol: ConnectionProtocol.tcp,
        host: (tcp as Map<String, dynamic>)['host'] as String? ?? 'localhost',
        port: tcp['port'] as int? ?? 8080,
        adapterId: json['adapter_id'] as String? ?? 'generic',
        authToken: json['auth_token'] as String?,
        timeoutMs: json['timeout_ms'] as int? ?? 5000,
      );
    }
    return const ConnectionConfig(protocol: ConnectionProtocol.webSocket);
  }

  Map<String, dynamic> toJson() => {
    'protocol': protocol == ConnectionProtocol.webSocket
        ? {'web_socket': {'url': url ?? 'ws://$host:$port'}}
        : {'tcp': {'host': host, 'port': port}},
    'adapter_id': adapterId,
    if (authToken != null) 'auth_token': authToken,
    'timeout_ms': timeoutMs,
  };

  String get displayUrl => protocol == ConnectionProtocol.webSocket
      ? (url ?? 'ws://$host:$port')
      : '$host:$port';
}

/// Engine command types
enum EngineCommandType {
  playSpin,
  pause,
  resume,
  stop,
  seek,
  setSpeed,
  setTimingProfile,
  requestState,
  sendEvent,
  custom;
}

/// Engine command
class EngineCommand {
  final EngineCommandType type;
  final Map<String, dynamic> params;

  const EngineCommand({required this.type, this.params = const {}});

  factory EngineCommand.playSpin(String spinId) =>
      EngineCommand(type: EngineCommandType.playSpin, params: {'spin_id': spinId});

  factory EngineCommand.pause() => const EngineCommand(type: EngineCommandType.pause);

  factory EngineCommand.resume() => const EngineCommand(type: EngineCommandType.resume);

  factory EngineCommand.stop() => const EngineCommand(type: EngineCommandType.stop);

  factory EngineCommand.seek(double timestampMs) =>
      EngineCommand(type: EngineCommandType.seek, params: {'timestamp_ms': timestampMs});

  factory EngineCommand.setSpeed(double speed) =>
      EngineCommand(type: EngineCommandType.setSpeed, params: {'speed': speed});

  factory EngineCommand.setTimingProfile(TimingProfile profile) =>
      EngineCommand(type: EngineCommandType.setTimingProfile, params: {'profile': profile.name});

  Map<String, dynamic> toJson() => {
    'type': type.name,
    ...params,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// P0.10: STAGE SEQUENCE VALIDATION MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Type of validation issue found
enum StageValidationType {
  /// Stage ordering violated (e.g., SPIN_END before SPIN_START)
  orderViolation,
  /// Required stage missing
  missingStage,
  /// Timestamp not monotonically increasing
  timestampViolation,
  /// Duplicate stage where only one expected
  duplicateStage,
  /// Unknown or invalid stage type
  unknownStage,
}

/// Severity of validation issue
enum StageValidationSeverity {
  /// Info - informational only
  info,
  /// Warning - unusual but not necessarily wrong
  warning,
  /// Error - violates expected sequence
  error,
}

/// A validation issue found in stage sequence
class StageValidationIssue {
  final StageValidationType type;
  final String message;
  final StageValidationSeverity severity;
  final int? stageIndex;
  final String? stageName;

  const StageValidationIssue({
    required this.type,
    required this.message,
    this.severity = StageValidationSeverity.error,
    this.stageIndex,
    this.stageName,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'message': message,
    'severity': severity.name,
    if (stageIndex != null) 'stageIndex': stageIndex,
    if (stageName != null) 'stageName': stageName,
  };

  @override
  String toString() => '[${severity.name}] $type: $message';
}

/// Smart Defaults per stage — provides sensible volume, bus, fade, and loop
/// values for each stage when Auto-Bind creates composite events.
///
/// All values sourced from FFNC.md Smart Defaults tables.
/// Priority chain: ASSIGN tab > Smart Defaults > StageConfigurationService > Global fallback

class StageDefault {
  final double volume;
  final int busId; // 0=master, 1=music, 2=sfx, 3=voice, 4=ambience, 5=aux
  final double? fadeInMs;
  final double? fadeOutMs;
  final bool loop;
  final double pan; // -1.0 to 1.0 (default 0.0 = center for mono, -1.0 = hard left for stereo)
  final double panRight; // -1.0 to 1.0 (default 0.0 = unused for mono, 1.0 = hard right for stereo)

  const StageDefault({
    required this.volume,
    required this.busId,
    this.fadeInMs,
    this.fadeOutMs,
    this.loop = false,
    this.pan = 0.0,
    this.panRight = 0.0,
  });
}

class StageDefaults {
  StageDefaults._();

  static const _globalDefault = StageDefault(volume: 1.0, busId: 2, pan: -1.0, panRight: 1.0);

  /// Get default parameters for a stage. Resolution order:
  /// 1. Exact match (e.g., "SPIN_START")
  /// 2. Wildcard match — longest prefix (e.g., "REEL_STOP_" matches "REEL_STOP_0")
  /// 3. Category match (e.g., "UI_" prefix)
  /// 4. Global fallback (volume 1.0, bus sfx)
  static StageDefault getDefaultForStage(String stage) {
    // 1. Exact match
    final exact = _exactDefaults[stage];
    if (exact != null) return exact;

    // 2. Wildcard match — try longest prefix first
    StageDefault? bestMatch;
    int bestLength = 0;
    for (final entry in _wildcardDefaults.entries) {
      if (stage.startsWith(entry.key) && entry.key.length > bestLength) {
        bestMatch = entry.value;
        bestLength = entry.key.length;
      }
    }
    if (bestMatch != null) return bestMatch;

    // 3. Category match
    if (stage.startsWith('UI_')) return _uiDefault;
    if (stage.startsWith('VO_')) return _voDefault;
    if (stage.startsWith('MUSIC_')) return _musicDefault;
    if (stage.startsWith('AMBIENT_')) return _ambientDefault;
    if (stage.startsWith('TRANSITION_')) return _transitionDefault;

    // 4. Global fallback
    return _globalDefault;
  }

  // ═══════════════════════════════════════════════════════════════
  // Category defaults (Priority 3)
  // ═══════════════════════════════════════════════════════════════

  // All categories default to stereo spread (pan=-1 L, panRight=+1 R).
  // Engine detects actual channel count from audio file and applies dual-pan
  // only for stereo sources. Mono sources ignore panRight.
  static const _uiDefault = StageDefault(volume: 1.0, busId: 2, pan: -1.0, panRight: 1.0);
  static const _voDefault = StageDefault(volume: 1.0, busId: 3, pan: -1.0, panRight: 1.0);
  static const _musicDefault = StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0);
  static const _ambientDefault = StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true, pan: -1.0, panRight: 1.0);
  static const _transitionDefault = StageDefault(volume: 1.0, busId: 2, pan: -1.0, panRight: 1.0);

  // ═══════════════════════════════════════════════════════════════
  // Wildcard defaults (Priority 2) — prefix matching
  // ═══════════════════════════════════════════════════════════════

  static const _wildcardDefaults = <String, StageDefault>{
    // Reel stops
    'REEL_STOP_': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 100),

    // Anticipation — one-shot, plays once during anticipation phase
    'ANTICIPATION_TENSION_R': StageDefault(volume: 1.0, busId: 2, fadeInMs: 300),
    'ANTICIPATION_': StageDefault(volume: 1.0, busId: 2, fadeInMs: 300),

    // Win tiers
    'WIN_PRESENT_': StageDefault(volume: 1.0, busId: 2),

    // Big win tiers
    'BIG_WIN_TIER_': StageDefault(volume: 1.0, busId: 2, fadeInMs: 50),

    // Scatter / Wild indexed
    'SCATTER_LAND_': StageDefault(volume: 1.0, busId: 2),
    'WILD_EXPAND_': StageDefault(volume: 1.0, busId: 2),
    'WILD_STICKY_': StageDefault(volume: 1.0, busId: 2),
    'WILD_WALK_': StageDefault(volume: 1.0, busId: 2),

    // Cascade indexed
    'CASCADE_STEP_': StageDefault(volume: 1.0, busId: 2),

    // Multiplier
    'MULTIPLIER_X': StageDefault(volume: 1.0, busId: 2),

    // Music layers — L1 at full volume, L2+ silent (crossfade ready — MUST stay 0.0)
    'MUSIC_BASE_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_BASE_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_FS_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_FS_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_BONUS_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_BONUS_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_HOLD_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_HOLD_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_JACKPOT_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_JACKPOT_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_GAMBLE_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_GAMBLE_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_REVEAL_L1': StageDefault(volume: 1.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_REVEAL_L': StageDefault(volume: 0.0, busId: 1, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_TENSION_': StageDefault(volume: 1.0, busId: 1, fadeInMs: 300, loop: true, pan: -1.0, panRight: 1.0),
    'MUSIC_STINGER_': StageDefault(volume: 1.0, busId: 1, pan: -1.0, panRight: 1.0),

    // Jackpot
    'JACKPOT_': StageDefault(volume: 1.0, busId: 2),

    // Near miss
    'NEAR_MISS_': StageDefault(volume: 1.0, busId: 2),

    // Respin
    'RESPIN_': StageDefault(volume: 1.0, busId: 2),

    // Gamble
    'GAMBLE_': StageDefault(volume: 1.0, busId: 2),

    // Pick bonus
    'PICK_': StageDefault(volume: 1.0, busId: 2),

    // Wheel
    'WHEEL_': StageDefault(volume: 1.0, busId: 2),

    // Collect
    'COLLECT_': StageDefault(volume: 1.0, busId: 2),
    'COIN_': StageDefault(volume: 1.0, busId: 2),

    // Symbol wins
    'HP': StageDefault(volume: 1.0, busId: 2),
    'MP': StageDefault(volume: 1.0, busId: 2),
    'LP': StageDefault(volume: 1.0, busId: 2),

    // Megaways
    'MEGAWAYS_': StageDefault(volume: 1.0, busId: 2),

    // Ambient indexed
    'AMBIENT_': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),

    // Transitions
    'TRANSITION_BASE_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_HOLD_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_FS_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_BONUS_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_GAMBLE_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_JACKPOT_TO_': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_': StageDefault(volume: 1.0, busId: 2),

    // Freespin
    'FREESPIN_': StageDefault(volume: 1.0, busId: 2),

    // Bonus
    'BONUS_': StageDefault(volume: 1.0, busId: 2),

    // Hold
    'HOLD_': StageDefault(volume: 1.0, busId: 2),
  };

  // ═══════════════════════════════════════════════════════════════
  // Exact defaults (Priority 1) — specific stage names
  // ═══════════════════════════════════════════════════════════════

  static const _exactDefaults = <String, StageDefault>{
    // Spin lifecycle
    'SPIN_START': StageDefault(volume: 1.0, busId: 2),
    'REEL_SPIN_LOOP': StageDefault(volume: 1.0, busId: 2, loop: true),
    'SPIN_END': StageDefault(volume: 1.0, busId: 2),
    'QUICK_STOP': StageDefault(volume: 1.0, busId: 2),
    'SPIN_ACCELERATION': StageDefault(volume: 1.0, busId: 2),
    'SPIN_DECELERATION': StageDefault(volume: 1.0, busId: 2),
    'SPIN_CANCEL': StageDefault(volume: 1.0, busId: 2),
    'REEL_SHAKE': StageDefault(volume: 1.0, busId: 2),
    'REEL_WIGGLE': StageDefault(volume: 1.0, busId: 2),
    'REEL_SLOW_STOP': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 100),
    'REEL_NUDGE': StageDefault(volume: 1.0, busId: 2),

    // Anticipation
    'ANTICIPATION_TENSION': StageDefault(volume: 1.0, busId: 2, fadeInMs: 300),
    'ANTICIPATION_OFF': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 200),
    'ANTICIPATION_MISS': StageDefault(volume: 1.0, busId: 2),

    // Wins
    'WIN_PRESENT_LOW': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_EQUAL': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_1': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_2': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_3': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_4': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_5': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_6': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_7': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_8': StageDefault(volume: 1.0, busId: 2),
    'WIN_PRESENT_END': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_START': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_TICK': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_TICK_FAST': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_TICK_SLOW': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_END': StageDefault(volume: 1.0, busId: 2),
    'ROLLUP_SKIP': StageDefault(volume: 1.0, busId: 2),
    'WIN_LINE_SHOW': StageDefault(volume: 1.0, busId: 2),
    'WIN_LINE_HIDE': StageDefault(volume: 1.0, busId: 2),
    'WIN_LINE_CYCLE': StageDefault(volume: 1.0, busId: 2),
    'WIN_SYMBOL_HIGHLIGHT': StageDefault(volume: 1.0, busId: 2),
    'WIN_FANFARE': StageDefault(volume: 1.0, busId: 2),

    // Big wins
    'BIG_WIN_START': StageDefault(volume: 1.0, busId: 1, loop: true), // Music bus — looping big win music
    'BIG_WIN_END': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500), // Music bus — end stinger + restart base
    'BIG_WIN_OUTRO': StageDefault(volume: 1.0, busId: 2), // SFX — plaque fadeout sound
    'BIG_WIN_TRIGGER': StageDefault(volume: 1.0, busId: 2), // SFX — attention alert
    'BIG_WIN_TICK_START': StageDefault(volume: 1.0, busId: 2),
    'BIG_WIN_TICK_END': StageDefault(volume: 1.0, busId: 2),
    'COIN_SHOWER_START': StageDefault(volume: 1.0, busId: 2),
    'COIN_SHOWER_END': StageDefault(volume: 1.0, busId: 2),

    // Scatter & Wild
    'SCATTER_LAND': StageDefault(volume: 1.0, busId: 2),
    'WILD_LAND': StageDefault(volume: 1.0, busId: 2),
    'WILD_EXPAND': StageDefault(volume: 1.0, busId: 2),
    'WILD_STICKY': StageDefault(volume: 1.0, busId: 2),
    'WILD_TRANSFORM': StageDefault(volume: 1.0, busId: 2),
    'WILD_MULTIPLY': StageDefault(volume: 1.0, busId: 2),
    'WILD_SPREAD': StageDefault(volume: 1.0, busId: 2),
    'WILD_NUDGE': StageDefault(volume: 1.0, busId: 2),
    'WILD_STACK': StageDefault(volume: 1.0, busId: 2),
    'WILD_UPGRADE': StageDefault(volume: 1.0, busId: 2),
    'WILD_COLLECT': StageDefault(volume: 1.0, busId: 2),
    'WILD_RANDOM': StageDefault(volume: 1.0, busId: 2),

    // Free Spins End (music bus — outro music/stinger)
    'FS_END': StageDefault(volume: 1.0, busId: 1),

    // Features
    'FEATURE_ENTER': StageDefault(volume: 1.0, busId: 2, fadeInMs: 100),
    'FEATURE_EXIT': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 200),
    'FEATURE_STEP': StageDefault(volume: 1.0, busId: 2),
    'FREESPIN_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'FREESPIN_START': StageDefault(volume: 1.0, busId: 2),
    'FREESPIN_END': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 200),
    'FREESPIN_RETRIGGER': StageDefault(volume: 1.0, busId: 2),

    // Cascade
    'CASCADE_START': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_STEP': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_POP': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_END': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_SYMBOL_POP': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_SYMBOL_DROP': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_SYMBOL_LAND': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_CHAIN_START': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_CHAIN_END': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_ANTICIPATION': StageDefault(volume: 1.0, busId: 2),
    'CASCADE_MEGA': StageDefault(volume: 1.0, busId: 2),

    // Multiplier
    'MULTIPLIER_INCREASE': StageDefault(volume: 1.0, busId: 2),
    'MULTIPLIER_APPLY': StageDefault(volume: 1.0, busId: 2),
    'MULTIPLIER_LAND': StageDefault(volume: 1.0, busId: 2),
    'MULTIPLIER_MAX': StageDefault(volume: 1.0, busId: 2),
    'MULTIPLIER_RESET': StageDefault(volume: 1.0, busId: 2),
    'MULTIPLIER_STACK': StageDefault(volume: 1.0, busId: 2),

    // Hold & Win
    'HOLD_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'HOLD_START': StageDefault(volume: 1.0, busId: 2),
    'HOLD_END': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 200),
    'HOLD_WIN_TOTAL': StageDefault(volume: 1.0, busId: 2),
    'PRIZE_REVEAL': StageDefault(volume: 1.0, busId: 2),
    'PRIZE_UPGRADE': StageDefault(volume: 1.0, busId: 2),
    'GRAND_TRIGGER': StageDefault(volume: 1.0, busId: 2),

    // Gamble
    'GAMBLE_START': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_ENTER': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_OFFER': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_WIN': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_LOSE': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_DOUBLE': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_HALF': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_COLLECT': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_EXIT': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_CARD_FLIP': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_COLOR_PICK': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_SUIT_PICK': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_LADDER_STEP': StageDefault(volume: 1.0, busId: 2),
    'GAMBLE_LADDER_FALL': StageDefault(volume: 1.0, busId: 2),

    // Jackpot
    'JACKPOT_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_ELIGIBLE': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_PROGRESS': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_BUILDUP': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_REVEAL': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_MINI': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_MINOR': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_MAJOR': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_GRAND': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_MEGA': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_ULTRA': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_PRESENT': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_AWARD': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_ROLLUP': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_BELLS': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_SIRENS': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_CELEBRATION': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_COLLECT': StageDefault(volume: 1.0, busId: 2),
    'JACKPOT_END': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 300),

    // Bonus
    'BONUS_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'BONUS_ENTER': StageDefault(volume: 1.0, busId: 2, fadeInMs: 100),
    'BONUS_EXIT': StageDefault(volume: 1.0, busId: 2, fadeOutMs: 200),
    'BONUS_WIN': StageDefault(volume: 1.0, busId: 2),
    'BONUS_STEP': StageDefault(volume: 1.0, busId: 2),
    'BONUS_SUMMARY': StageDefault(volume: 1.0, busId: 2),
    'BONUS_TOTAL': StageDefault(volume: 1.0, busId: 2),

    // Near miss
    'NEAR_MISS': StageDefault(volume: 1.0, busId: 2),
    'NEAR_MISS_SCATTER': StageDefault(volume: 1.0, busId: 2),
    'NEAR_MISS_BONUS': StageDefault(volume: 1.0, busId: 2),
    'NEAR_MISS_WILD': StageDefault(volume: 1.0, busId: 2),
    'NEAR_MISS_JACKPOT': StageDefault(volume: 1.0, busId: 2),
    'NEAR_MISS_FEATURE': StageDefault(volume: 1.0, busId: 2),

    // Respin
    'RESPIN_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_START': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_SPIN': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_STOP': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_END': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_RESET': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_RETRIGGER': StageDefault(volume: 1.0, busId: 2),
    'RESPIN_LAST': StageDefault(volume: 1.0, busId: 2),

    // Pick bonus
    'PICK_BONUS_START': StageDefault(volume: 1.0, busId: 2),
    'PICK_BONUS_END': StageDefault(volume: 1.0, busId: 2),
    'PICK_REVEAL': StageDefault(volume: 1.0, busId: 2),
    'PICK_COLLECT': StageDefault(volume: 1.0, busId: 2),
    'PICK_HOVER': StageDefault(volume: 1.0, busId: 2),
    'PICK_CHEST_OPEN': StageDefault(volume: 1.0, busId: 2),
    'PICK_GOOD': StageDefault(volume: 1.0, busId: 2),
    'PICK_BAD': StageDefault(volume: 1.0, busId: 2),
    'PICK_MULTIPLIER': StageDefault(volume: 1.0, busId: 2),
    'PICK_UPGRADE': StageDefault(volume: 1.0, busId: 2),

    // Wheel
    'WHEEL_START': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_SPIN': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_TICK': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_SLOW': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_LAND': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_ANTICIPATION': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_NEAR_MISS': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_CELEBRATION': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_PRIZE': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_BONUS': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_MULTIPLIER': StageDefault(volume: 1.0, busId: 2),
    'WHEEL_JACKPOT_LAND': StageDefault(volume: 1.0, busId: 2),

    // Collect & Coins
    'COIN_BURST': StageDefault(volume: 1.0, busId: 2),
    'COIN_DROP': StageDefault(volume: 1.0, busId: 2),
    'COIN_LAND': StageDefault(volume: 1.0, busId: 2),
    'COIN_COLLECT': StageDefault(volume: 1.0, busId: 2),
    'COIN_COLLECT_ALL': StageDefault(volume: 1.0, busId: 2),
    'COIN_RAIN': StageDefault(volume: 1.0, busId: 2),
    'COIN_SHOWER': StageDefault(volume: 1.0, busId: 2),
    'COIN_UPGRADE': StageDefault(volume: 1.0, busId: 2),
    'COIN_VALUE_REVEAL': StageDefault(volume: 1.0, busId: 2),
    'COIN_LOCK': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_TRIGGER': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_COIN': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_SYMBOL': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_METER_FILL': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_METER_FULL': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_PAYOUT': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_FLY_TO': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_IMPACT': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_UPGRADE': StageDefault(volume: 1.0, busId: 2),
    'COLLECT_COMPLETE': StageDefault(volume: 1.0, busId: 2),

    // Celebration & VFX
    'SCREEN_SHAKE': StageDefault(volume: 1.0, busId: 2),
    'LIGHT_FLASH': StageDefault(volume: 1.0, busId: 2),
    'CONFETTI_BURST': StageDefault(volume: 1.0, busId: 2),
    'FIREWORKS_LAUNCH': StageDefault(volume: 1.0, busId: 2),
    'FIREWORKS_EXPLODE': StageDefault(volume: 1.0, busId: 2),
    'GAME_INTRO': StageDefault(volume: 1.0, busId: 2), // SFX — splash screen entry animation
    'GAME_CONTINUE': StageDefault(volume: 1.0, busId: 2), // SFX — continue button press
    'GAME_READY': StageDefault(volume: 1.0, busId: 2),
    'GAME_START': StageDefault(volume: 1.0, busId: 1, loop: true),

    // Music
    'MUSIC_BASE_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_BASE_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_FS_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_FS_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_BONUS_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_BONUS_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_HOLD_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_HOLD_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_JACKPOT_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_JACKPOT_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_GAMBLE_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_GAMBLE_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_REVEAL_INTRO': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_REVEAL_OUTRO': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_TENSION_LOW': StageDefault(volume: 1.0, busId: 1, fadeInMs: 300, loop: true),
    'MUSIC_TENSION_MED': StageDefault(volume: 1.0, busId: 1, fadeInMs: 300, loop: true),
    'MUSIC_TENSION_HIGH': StageDefault(volume: 1.0, busId: 1, fadeInMs: 300, loop: true),
    'MUSIC_TENSION_MAX': StageDefault(volume: 1.0, busId: 1, fadeInMs: 300, loop: true),
    'MUSIC_BUILDUP': StageDefault(volume: 1.0, busId: 1, fadeInMs: 200),
    'MUSIC_CLIMAX': StageDefault(volume: 1.0, busId: 1),
    'MUSIC_RESOLVE': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 500),
    'MUSIC_WIND_DOWN': StageDefault(volume: 1.0, busId: 1, fadeOutMs: 300),
    'MUSIC_BIGWIN': StageDefault(volume: 1.0, busId: 1, loop: true),

    // Ambience
    'AMBIENT_BASE': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),
    'AMBIENT_FS': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),
    'AMBIENT_BONUS': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),
    'AMBIENT_HOLD': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),
    'AMBIENT_BIGWIN': StageDefault(volume: 1.0, busId: 4, fadeInMs: 300, loop: true),
    'AMBIENT_JACKPOT': StageDefault(volume: 1.0, busId: 4, fadeInMs: 300, loop: true),
    'AMBIENT_GAMBLE': StageDefault(volume: 1.0, busId: 4, fadeInMs: 500, loop: true),
    'ATTRACT_LOOP': StageDefault(volume: 1.0, busId: 4, fadeInMs: 1000, loop: true),
    'ATTRACT_EXIT': StageDefault(volume: 1.0, busId: 4, fadeOutMs: 300),
    'IDLE_LOOP': StageDefault(volume: 1.0, busId: 4, fadeInMs: 1000, loop: true),
    'IDLE_TO_ACTIVE': StageDefault(volume: 1.0, busId: 4, fadeOutMs: 200),

    // Transitions
    'TRANSITION_GAME_INTRO': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_PLAQUE_APPEAR': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_PLAQUE_DISAPPEAR': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_SWOOSH': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_IMPACT': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_REVEAL': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_STINGER': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_FADE_IN': StageDefault(volume: 1.0, busId: 2),
    'TRANSITION_FADE_OUT': StageDefault(volume: 1.0, busId: 2),

    // UI
    'UI_SPIN_PRESS': StageDefault(volume: 1.0, busId: 2),
    'UI_SPIN_HOVER': StageDefault(volume: 1.0, busId: 2),
    'UI_SPIN_RELEASE': StageDefault(volume: 1.0, busId: 2),
    'UI_STOP_PRESS': StageDefault(volume: 1.0, busId: 2),
    'UI_BET_UP': StageDefault(volume: 1.0, busId: 2),
    'UI_BET_DOWN': StageDefault(volume: 1.0, busId: 2),
    'UI_BET_MAX': StageDefault(volume: 1.0, busId: 2),
    'UI_BET_MIN': StageDefault(volume: 1.0, busId: 2),
    'UI_MENU_OPEN': StageDefault(volume: 1.0, busId: 2),
    'UI_MENU_CLOSE': StageDefault(volume: 1.0, busId: 2),
    'UI_MENU_HOVER': StageDefault(volume: 1.0, busId: 2),
    'UI_MENU_SELECT': StageDefault(volume: 1.0, busId: 2),
    'UI_AUTOPLAY_START': StageDefault(volume: 1.0, busId: 2),
    'UI_AUTOPLAY_STOP': StageDefault(volume: 1.0, busId: 2),
    'UI_TURBO_ON': StageDefault(volume: 1.0, busId: 2),
    'UI_TURBO_OFF': StageDefault(volume: 1.0, busId: 2),
    'UI_SETTINGS_OPEN': StageDefault(volume: 1.0, busId: 2),
    'UI_SETTINGS_CLOSE': StageDefault(volume: 1.0, busId: 2),
    'UI_FULLSCREEN_ENTER': StageDefault(volume: 1.0, busId: 2),
    'UI_FULLSCREEN_EXIT': StageDefault(volume: 1.0, busId: 2),
    'UI_NOTIFICATION': StageDefault(volume: 1.0, busId: 2),
    'UI_ERROR': StageDefault(volume: 1.0, busId: 2),
    'UI_WARNING': StageDefault(volume: 1.0, busId: 2),
    'UI_ALERT': StageDefault(volume: 1.0, busId: 2),

    // Voice-Over
    'VO_WIN_1': StageDefault(volume: 1.0, busId: 3),
    'VO_WIN_2': StageDefault(volume: 1.0, busId: 3),
    'VO_WIN_3': StageDefault(volume: 1.0, busId: 3),
    'VO_WIN_4': StageDefault(volume: 1.0, busId: 3),
    'VO_WIN_5': StageDefault(volume: 1.0, busId: 3),
    'VO_BIG_WIN': StageDefault(volume: 1.0, busId: 3),
    'VO_CONGRATULATIONS': StageDefault(volume: 1.0, busId: 3),
    'VO_INCREDIBLE': StageDefault(volume: 1.0, busId: 3),
    'VO_SENSATIONAL': StageDefault(volume: 1.0, busId: 3),
    'VO_BONUS': StageDefault(volume: 1.0, busId: 3),
  };
}

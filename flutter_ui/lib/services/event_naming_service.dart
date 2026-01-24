/// Event Naming Service
///
/// Generates semantic event names based on drop target and stage.
///
/// Naming Convention:
/// - UI Elements: onUiPa{ElementName} (e.g., onUiPaSpinButton)
/// - Reel Events: onReel{Action}{Index} (e.g., onReelStop0, onReelLand)
/// - Win Events: onWin{Tier} (e.g., onWinSmall, onWinBig)
/// - Feature: onFeature{Name}{Phase} (e.g., onFeatureFreespinsStart)
/// - FreeSpins: onFs{Phase} (e.g., onFsTrigger, onFsEnter, onFsExit)
/// - Bonus: onBonus{Phase} (e.g., onBonusTrigger, onBonusEnter)
/// - Symbol: onSymbol{Type}{Action} (e.g., onSymbolWildLand)
/// - Jackpot: onJackpot{Tier} (e.g., onJackpotMini, onJackpotGrand)
/// - Cascade: onCascade{Phase} (e.g., onCascadeStart, onCascadeStep)
/// - Tumble: onTumble{Phase} (e.g., onTumbleDrop, onTumbleLand)
/// - Hold: onHold{Phase} (e.g., onHoldTrigger, onHoldEnter)
/// - Gamble: onGamble{Phase} (e.g., onGambleStart, onGambleWin)
/// - Pick: onPick{Action} (e.g., onPickReveal, onPickComplete)
/// - Wheel: onWheel{Action} (e.g., onWheelSpin, onWheelLand)
/// - Trail: onTrail{Action} (e.g., onTrailEnter, onTrailAdvance)
/// - BigWin: onBigWin{Tier} (e.g., onBigWinTierMega, onBigWinTierEpic)
/// - Multiplier: onMult{Value} (e.g., onMult5, onMult100)
/// - Menu: onMenu{Action} (e.g., onMenuOpen, onMenuClose)
/// - Autoplay: onAutoplay{Action} (e.g., onAutoplayStart, onAutoplayStop)
/// - Ambient: onAmbient{Type} (e.g., onAmbientLoop, onAmbientFade)
library;

/// Singleton service for generating event names
class EventNamingService {
  EventNamingService._();
  static final EventNamingService instance = EventNamingService._();

  /// Generate event name from target ID and stage
  ///
  /// [targetId] - Drop target ID (e.g., "ui.spin", "reel.0", "overlay.win.big")
  /// [stage] - Stage name (e.g., "SPIN_START", "REEL_STOP_0", "WIN_BIG")
  ///
  /// Returns semantic event name (e.g., "onUiPaSpinButton", "onReelStop0")
  String generateEventName(String targetId, String stage) {
    // Try target-based naming first
    final targetName = _fromTargetId(targetId);
    if (targetName != null) return targetName;

    // Fall back to stage-based naming
    return _fromStage(stage);
  }

  /// Generate name from target ID
  String? _fromTargetId(String targetId) {
    if (targetId.isEmpty) return null;

    final parts = targetId.toLowerCase().split('.');

    if (parts.isEmpty) return null;

    final category = parts[0];

    switch (category) {
      case 'ui':
        return _generateUiName(parts);
      case 'reel':
        return _generateReelName(parts);
      case 'overlay':
        return _generateOverlayName(parts);
      case 'symbol':
        return _generateSymbolName(parts);
      case 'music':
        return _generateMusicName(parts);
      case 'jackpot':
        return _generateJackpotName(parts);
      default:
        return null;
    }
  }

  /// Generate name from stage
  String _fromStage(String stage) {
    final normalized = stage.toUpperCase().trim();

    // SPIN stages
    if (normalized == 'SPIN_START') return 'onSpinStart';
    if (normalized == 'SPIN_END') return 'onSpinEnd';
    if (normalized == 'SPIN_BUTTON_PRESS') return 'onUiPaSpinButton';

    // REEL stages
    if (normalized.startsWith('REEL_STOP_')) {
      final index = normalized.replaceFirst('REEL_STOP_', '');
      return 'onReelStop$index';
    }
    if (normalized == 'REEL_STOP') return 'onReelStop';
    if (normalized == 'REEL_SPIN_LOOP') return 'onReelSpinLoop';

    // ANTICIPATION stages
    if (normalized == 'ANTICIPATION_ON') return 'onAnticipationStart';
    if (normalized == 'ANTICIPATION_OFF') return 'onAnticipationEnd';
    if (normalized.startsWith('ANTICIPATION_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('ANTICIPATION_', ''));
      return 'onAnticipation$suffix';
    }

    // WIN stages
    if (normalized == 'WIN_PRESENT') return 'onWinPresent';
    if (normalized == 'WIN_SMALL') return 'onWinSmall';
    if (normalized == 'WIN_MEDIUM') return 'onWinMedium';
    if (normalized == 'WIN_BIG') return 'onWinBig';
    if (normalized == 'WIN_MEGA') return 'onWinMega';
    if (normalized == 'WIN_EPIC') return 'onWinEpic';
    if (normalized == 'WIN_ULTRA') return 'onWinUltra';
    if (normalized == 'WIN_END') return 'onWinEnd';
    if (normalized == 'WIN_LINE_SHOW') return 'onWinLineShow';
    if (normalized == 'WIN_LINE_HIDE') return 'onWinLineHide';
    if (normalized == 'WIN_SYMBOL_HIGHLIGHT') return 'onWinSymbolHighlight';
    if (normalized.startsWith('WIN_TIER_')) {
      final tier = normalized.replaceFirst('WIN_TIER_', '');
      return 'onWinTier$tier';
    }
    if (normalized.startsWith('WIN_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('WIN_', ''));
      return 'onWin$suffix';
    }

    // ROLLUP stages
    if (normalized == 'ROLLUP_START') return 'onRollupStart';
    if (normalized == 'ROLLUP_END') return 'onRollupEnd';
    if (normalized == 'ROLLUP_TICK') return 'onRollupTick';
    if (normalized == 'ROLLUP_TICK_FAST') return 'onRollupTickFast';
    if (normalized == 'ROLLUP_TICK_SLOW') return 'onRollupTickSlow';
    if (normalized == 'ROLLUP_SLAM') return 'onRollupSlam';
    if (normalized == 'ROLLUP_MILESTONE') return 'onRollupMilestone';
    if (normalized.startsWith('ROLLUP_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('ROLLUP_', ''));
      return 'onRollup$suffix';
    }

    // JACKPOT stages
    if (normalized == 'JACKPOT_TRIGGER') return 'onJackpotTrigger';
    if (normalized == 'JACKPOT_MINI') return 'onJackpotMini';
    if (normalized == 'JACKPOT_MINOR') return 'onJackpotMinor';
    if (normalized == 'JACKPOT_MAJOR') return 'onJackpotMajor';
    if (normalized == 'JACKPOT_GRAND') return 'onJackpotGrand';
    if (normalized == 'JACKPOT_PRESENT') return 'onJackpotPresent';
    if (normalized == 'JACKPOT_END') return 'onJackpotEnd';
    if (normalized.startsWith('JACKPOT_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('JACKPOT_', ''));
      return 'onJackpot$suffix';
    }

    // CASCADE stages
    if (normalized == 'CASCADE_START') return 'onCascadeStart';
    if (normalized == 'CASCADE_STEP') return 'onCascadeStep';
    if (normalized == 'CASCADE_END') return 'onCascadeEnd';
    if (normalized == 'CASCADE_DROP') return 'onCascadeDrop';
    if (normalized == 'CASCADE_SYMBOL_POP') return 'onCascadeSymbolPop';
    if (normalized.startsWith('CASCADE_COMBO_')) {
      final combo = normalized.replaceFirst('CASCADE_COMBO_', '');
      return 'onCascadeCombo$combo';
    }
    if (normalized.startsWith('CASCADE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('CASCADE_', ''));
      return 'onCascade$suffix';
    }

    // FREE SPINS (FS_*) stages
    if (normalized == 'FS_TRIGGER') return 'onFsTrigger';
    if (normalized == 'FS_ENTER') return 'onFsEnter';
    if (normalized == 'FS_SPIN_START') return 'onFsSpinStart';
    if (normalized == 'FS_SPIN_END') return 'onFsSpinEnd';
    if (normalized == 'FS_RETRIGGER') return 'onFsRetrigger';
    if (normalized == 'FS_EXIT') return 'onFsExit';
    if (normalized == 'FS_MUSIC') return 'onFsMusic';
    if (normalized == 'FS_SUMMARY') return 'onFsSummary';
    if (normalized == 'FS_MULTIPLIER') return 'onFsMultiplier';
    if (normalized == 'FS_LAST_SPIN') return 'onFsLastSpin';
    if (normalized == 'FS_TRANSITION_IN') return 'onFsTransitionIn';
    if (normalized == 'FS_TRANSITION_OUT') return 'onFsTransitionOut';
    if (normalized == 'FREESPIN_START' || normalized == 'FS_START') {
      return 'onFsStart';
    }
    if (normalized == 'FREESPIN_END' || normalized == 'FS_END') {
      return 'onFsEnd';
    }
    if (normalized.startsWith('FS_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('FS_', ''));
      return 'onFs$suffix';
    }

    // BONUS stages
    if (normalized == 'BONUS_TRIGGER') return 'onBonusTrigger';
    if (normalized == 'BONUS_ENTER') return 'onBonusEnter';
    if (normalized == 'BONUS_STEP') return 'onBonusStep';
    if (normalized == 'BONUS_REVEAL') return 'onBonusReveal';
    if (normalized == 'BONUS_EXIT') return 'onBonusExit';
    if (normalized == 'BONUS_LAND_3') return 'onBonusLand3';
    if (normalized == 'BONUS_START') return 'onBonusStart';
    if (normalized == 'BONUS_END') return 'onBonusEnd';
    if (normalized.startsWith('BONUS_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('BONUS_', ''));
      return 'onBonus$suffix';
    }

    // FEATURE stages
    if (normalized.startsWith('FEATURE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('FEATURE_', ''));
      return 'onFeature$suffix';
    }

    // TUMBLE stages
    if (normalized == 'TUMBLE_DROP') return 'onTumbleDrop';
    if (normalized == 'TUMBLE_LAND') return 'onTumbleLand';
    if (normalized.startsWith('TUMBLE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('TUMBLE_', ''));
      return 'onTumble$suffix';
    }

    // AVALANCHE stages (alias for cascade/tumble)
    if (normalized.startsWith('AVALANCHE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('AVALANCHE_', ''));
      return 'onAvalanche$suffix';
    }

    // BIGWIN stages
    if (normalized.startsWith('BIGWIN_TIER_')) {
      final tier = _toCamelCase(normalized.replaceFirst('BIGWIN_TIER_', ''));
      return 'onBigWinTier$tier';
    }
    if (normalized.startsWith('BIGWIN_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('BIGWIN_', ''));
      return 'onBigWin$suffix';
    }

    // MULTIPLIER stages
    if (normalized == 'MULT_MAX') return 'onMultMax';
    if (normalized.startsWith('MULT_')) {
      final value = normalized.replaceFirst('MULT_', '');
      return 'onMult$value';
    }

    // PICK stages
    if (normalized.startsWith('PICK_REVEAL_')) {
      final type = _toCamelCase(normalized.replaceFirst('PICK_REVEAL_', ''));
      return 'onPickReveal$type';
    }
    if (normalized.startsWith('PICK_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('PICK_', ''));
      return 'onPick$suffix';
    }

    // WHEEL stages
    if (normalized == 'WHEEL_APPEAR') return 'onWheelAppear';
    if (normalized == 'WHEEL_SPIN') return 'onWheelSpin';
    if (normalized == 'WHEEL_LAND') return 'onWheelLand';
    if (normalized == 'WHEEL_TICK') return 'onWheelTick';
    if (normalized == 'WHEEL_ADVANCE') return 'onWheelAdvance';
    if (normalized == 'WHEEL_PRIZE_REVEAL') return 'onWheelPrizeReveal';
    if (normalized.startsWith('WHEEL_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('WHEEL_', ''));
      return 'onWheel$suffix';
    }

    // TRAIL stages
    if (normalized == 'TRAIL_ENTER') return 'onTrailEnter';
    if (normalized == 'TRAIL_MOVE_STEP') return 'onTrailMoveStep';
    if (normalized.startsWith('TRAIL_LAND_')) {
      final type = _toCamelCase(normalized.replaceFirst('TRAIL_LAND_', ''));
      return 'onTrailLand$type';
    }
    if (normalized.startsWith('TRAIL_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('TRAIL_', ''));
      return 'onTrail$suffix';
    }

    // TENSION stages
    if (normalized.startsWith('TENSION_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('TENSION_', ''));
      return 'onTension$suffix';
    }

    // NEAR MISS
    if (normalized == 'NEAR_MISS') return 'onNearMiss';

    // SYMBOL stages
    if (normalized == 'SYMBOL_LAND_LOW') return 'onSymbolLandLow';
    if (normalized == 'SYMBOL_LAND_MID') return 'onSymbolLandMid';
    if (normalized == 'SYMBOL_LAND_HIGH') return 'onSymbolLandHigh';
    if (normalized.startsWith('SYMBOL_LAND_')) {
      final symbol = _toCamelCase(normalized.replaceFirst('SYMBOL_LAND_', ''));
      return 'onSymbol${symbol}Land';
    }
    if (normalized == 'SYMBOL_LAND') return 'onSymbolLand';
    if (normalized.startsWith('WILD_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('WILD_', ''));
      return 'onSymbolWild$suffix';
    }
    if (normalized.startsWith('SCATTER_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('SCATTER_', ''));
      return 'onSymbolScatter$suffix';
    }

    // UI stages
    if (normalized == 'UI_BUTTON_PRESS') return 'onUiButtonPress';
    if (normalized == 'UI_BUTTON_HOVER') return 'onUiButtonHover';
    if (normalized == 'UI_BET_UP') return 'onUiBetUp';
    if (normalized == 'UI_BET_DOWN') return 'onUiBetDown';
    if (normalized == 'UI_TAB_SWITCH') return 'onUiTabSwitch';
    if (normalized.startsWith('UI_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('UI_', ''));
      return 'onUiPa$suffix';
    }

    // MENU stages
    if (normalized == 'MENU_OPEN') return 'onMenuOpen';
    if (normalized == 'MENU_CLOSE') return 'onMenuClose';
    if (normalized.startsWith('MENU_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('MENU_', ''));
      return 'onMenu$suffix';
    }

    // AUTOPLAY stages
    if (normalized == 'AUTOPLAY_START') return 'onAutoplayStart';
    if (normalized == 'AUTOPLAY_STOP') return 'onAutoplayStop';
    if (normalized.startsWith('AUTOPLAY_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('AUTOPLAY_', ''));
      return 'onAutoplay$suffix';
    }

    // MUSIC stages
    if (normalized == 'MUSIC_BASE') return 'onMusicBase';
    if (normalized == 'MUSIC_TENSION') return 'onMusicTension';
    if (normalized == 'MUSIC_BIGWIN') return 'onMusicBigwin';
    if (normalized.startsWith('MUSIC_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('MUSIC_', ''));
      return 'onMusic$suffix';
    }

    // AMBIENT stages
    if (normalized == 'AMBIENT_LOOP') return 'onAmbientLoop';
    if (normalized.startsWith('AMBIENT_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('AMBIENT_', ''));
      return 'onAmbient$suffix';
    }

    // ATTRACT mode
    if (normalized == 'ATTRACT_MODE') return 'onAttractMode';
    if (normalized.startsWith('ATTRACT_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('ATTRACT_', ''));
      return 'onAttract$suffix';
    }

    // IDLE stages
    if (normalized == 'IDLE_LOOP') return 'onIdleLoop';
    if (normalized.startsWith('IDLE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('IDLE_', ''));
      return 'onIdle$suffix';
    }

    // HOLD stages
    if (normalized == 'HOLD_TRIGGER') return 'onHoldTrigger';
    if (normalized == 'HOLD_ENTER') return 'onHoldEnter';
    if (normalized == 'HOLD_SPIN') return 'onHoldSpin';
    if (normalized == 'HOLD_RESPIN_STOP') return 'onHoldRespinStop';
    if (normalized == 'HOLD_SYMBOL_LAND') return 'onHoldSymbolLand';
    if (normalized == 'HOLD_RESPIN_RESET') return 'onHoldRespinReset';
    if (normalized == 'HOLD_GRID_FULL') return 'onHoldGridFull';
    if (normalized == 'HOLD_EXIT') return 'onHoldExit';
    if (normalized == 'HOLD_MUSIC') return 'onHoldMusic';
    if (normalized == 'HOLD_JACKPOT') return 'onHoldJackpot';
    if (normalized == 'HOLD_SPECIAL') return 'onHoldSpecial';
    if (normalized == 'HOLD_END') return 'onHoldEnd';
    if (normalized == 'HOLD_COLLECT') return 'onHoldCollect';
    if (normalized == 'HOLD_SUMMARY') return 'onHoldSummary';
    if (normalized.startsWith('HOLD_RESPIN_COUNTER_')) {
      final count = normalized.replaceFirst('HOLD_RESPIN_COUNTER_', '');
      return 'onHoldRespinCounter$count';
    }
    if (normalized.startsWith('HOLD_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('HOLD_', ''));
      return 'onHold$suffix';
    }

    // GAMBLE stages
    if (normalized == 'GAMBLE_START') return 'onGambleStart';
    if (normalized == 'GAMBLE_CHOICE') return 'onGambleChoice';
    if (normalized == 'GAMBLE_WIN') return 'onGambleWin';
    if (normalized == 'GAMBLE_LOSE') return 'onGambleLose';
    if (normalized == 'GAMBLE_COLLECT') return 'onGambleCollect';
    if (normalized == 'GAMBLE_END') return 'onGambleEnd';
    if (normalized == 'GAMBLE_DOUBLE') return 'onGambleDouble';
    if (normalized == 'GAMBLE_MAX_WIN') return 'onGambleMaxWin';
    if (normalized.startsWith('GAMBLE_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('GAMBLE_', ''));
      return 'onGamble$suffix';
    }

    // SYSTEM stages
    if (normalized.startsWith('SYSTEM_')) {
      final suffix = _toCamelCase(normalized.replaceFirst('SYSTEM_', ''));
      return 'onSystem$suffix';
    }

    // Generic fallback
    return 'on${_toCamelCase(normalized)}';
  }

  /// Generate UI element name
  /// targetId: "ui.spin", "ui.bet.up", "ui.auto"
  String _generateUiName(List<String> parts) {
    if (parts.length < 2) return 'onUiPaButton';

    final element = parts.sublist(1).map(_capitalize).join('');
    return 'onUiPa$element';
  }

  /// Generate Reel name
  /// targetId: "reel.0", "reel.1", "reel.stop"
  String _generateReelName(List<String> parts) {
    if (parts.length < 2) return 'onReelStop';

    final action = parts[1];

    // Check if it's a reel index
    final reelIndex = int.tryParse(action);
    if (reelIndex != null) {
      return 'onReelStop$reelIndex';
    }

    // Otherwise it's an action
    return 'onReel${_capitalize(action)}';
  }

  /// Generate Overlay name
  /// targetId: "overlay.win.big", "overlay.jackpot.grand"
  String _generateOverlayName(List<String> parts) {
    if (parts.length < 2) return 'onOverlay';

    final type = parts[1];

    if (type == 'win' && parts.length >= 3) {
      final tier = _capitalize(parts[2]);
      return 'onWin$tier';
    }

    if (type == 'jackpot' && parts.length >= 3) {
      final tier = _capitalize(parts[2]);
      return 'onJackpot$tier';
    }

    return 'onOverlay${parts.sublist(1).map(_capitalize).join('')}';
  }

  /// Generate Symbol name
  /// targetId: "symbol.wild", "symbol.scatter", "symbol.seven"
  String _generateSymbolName(List<String> parts) {
    if (parts.length < 2) return 'onSymbolLand';

    final symbolType = _capitalize(parts[1]);
    final action = parts.length >= 3 ? _capitalize(parts[2]) : 'Land';

    return 'onSymbol$symbolType$action';
  }

  /// Generate Music name
  /// targetId: "music.base", "music.feature", "music.bigwin"
  String _generateMusicName(List<String> parts) {
    if (parts.length < 2) return 'onMusicBase';

    final layer = parts.sublist(1).map(_capitalize).join('');
    return 'onMusic$layer';
  }

  /// Generate Jackpot name
  /// targetId: "jackpot.mini", "jackpot.grand"
  String _generateJackpotName(List<String> parts) {
    if (parts.length < 2) return 'onJackpotTrigger';

    final tier = _capitalize(parts[1]);
    return 'onJackpot$tier';
  }

  /// Convert SNAKE_CASE to CamelCase
  String _toCamelCase(String input) {
    if (input.isEmpty) return '';

    final parts = input.toLowerCase().split('_');
    if (parts.isEmpty) return '';

    return parts.map(_capitalize).join('');
  }

  /// Capitalize first letter
  String _capitalize(String input) {
    if (input.isEmpty) return '';
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  /// Check if name is unique in existing events
  bool isNameUnique(String name, List<String> existingNames) {
    return !existingNames.contains(name);
  }

  /// Generate unique name by appending number if needed
  String ensureUnique(String baseName, List<String> existingNames) {
    if (isNameUnique(baseName, existingNames)) {
      return baseName;
    }

    var counter = 2;
    while (!isNameUnique('$baseName$counter', existingNames)) {
      counter++;
      if (counter > 100) break; // Safety limit
    }

    return '$baseName$counter';
  }
}

/// FluxForge Slot Audio Event Definitions
///
/// Predefined MiddlewareEvents for slot game audio integration.
/// Maps STAGES protocol events to audio actions.
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'middleware_models.dart';
import '../services/event_registry.dart' show ContainerType, ContainerTypeExtension;

// ═══════════════════════════════════════════════════════════════════════════
// SLOT AUDIO EVENT IDS
// ═══════════════════════════════════════════════════════════════════════════

/// Reserved ID ranges for slot audio events
class SlotEventIds {
  // Spin lifecycle: 1000-1099
  static const int spinStart = 1000;
  static const int reelSpin = 1010;
  static const int reelStop = 1020;
  static const int spinEnd = 1030;

  // Anticipation: 1100-1199
  static const int anticipationOn = 1100;
  static const int anticipationOff = 1110;
  static const int nearMiss = 1120;

  // Win lifecycle: 1200-1299
  static const int winPresent = 1200;
  static const int winLineShow = 1210;
  static const int rollupStart = 1220;
  static const int rollupTick = 1225;
  static const int rollupEnd = 1230;

  // Big win tiers: 1300-1399
  static const int bigWinBase = 1300;
  static const int bigWinMega = 1310;
  static const int bigWinEpic = 1320;
  static const int bigWinUltra = 1330;

  // Feature lifecycle: 1400-1499
  static const int featureEnter = 1400;
  static const int featureStep = 1410;
  static const int featureRetrigger = 1420;
  static const int featureExit = 1430;

  // Cascade: 1500-1599
  static const int cascadeStart = 1500;
  static const int cascadeStep = 1510;
  static const int cascadeEnd = 1520;

  // Bonus: 1600-1699
  static const int bonusEnter = 1600;
  static const int bonusChoice = 1610;
  static const int bonusReveal = 1620;
  static const int bonusExit = 1630;

  // Gamble: 1700-1799
  static const int gambleStart = 1700;
  static const int gambleWin = 1710;
  static const int gambleLose = 1720;
  static const int gambleCollect = 1730;

  // Jackpot: 1800-1899
  static const int jackpotTrigger = 1800;
  static const int jackpotPresent = 1810;
  static const int jackpotEnd = 1820;

  // UI: 1900-1999
  static const int idleStart = 1900;
  static const int menuOpen = 1910;
  static const int menuClose = 1920;
  static const int buttonClick = 1930;
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT BUS IDS
// ═══════════════════════════════════════════════════════════════════════════

/// Audio bus IDs for slot game routing
class SlotBusIds {
  static const int master = 0;
  static const int music = 1;
  static const int sfx = 2;
  static const int voice = 3;
  static const int ui = 4;
  static const int reels = 5;
  static const int wins = 6;
  static const int anticipation = 7;
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT RTPC IDS
// ═══════════════════════════════════════════════════════════════════════════

/// RTPC IDs for dynamic slot audio control
class SlotRtpcIds {
  static const int winMultiplier = 100;
  static const int betLevel = 101;
  static const int volatility = 102;
  static const int tension = 103;
  static const int cascadeDepth = 104;
  static const int featureProgress = 105;
  static const int rollupSpeed = 106;
  static const int jackpotPool = 107;
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT STATE GROUP IDS
// ═══════════════════════════════════════════════════════════════════════════

/// State group IDs for slot game states
class SlotStateGroupIds {
  static const int gamePhase = 200;
  static const int featureType = 201;
  static const int musicMode = 202;
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FOR UNIQUE ACTION IDS
// ═══════════════════════════════════════════════════════════════════════════

int _actionId = 0;
String _nextActionId() => 'slot_action_${_actionId++}';

// ═══════════════════════════════════════════════════════════════════════════
// CORE SLOT AUDIO EVENTS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for creating predefined slot audio events
/// NOTE: Templates removed - events are now created by user or synced from Slot Lab
class SlotAudioEventFactory {
  /// Create all core slot audio events
  /// Returns empty list - no placeholder events
  static List<MiddlewareEvent> createAllEvents() {
    return []; // No placeholder events - user creates events in Slot Lab
  }

  /// Create events from templates (optional, call explicitly if needed)
  static List<MiddlewareEvent> createFromTemplates() {
    _actionId = 0; // Reset counter
    return [
      ...createSpinLifecycleEvents(),
      ...createAnticipationEvents(),
      ...createWinLifecycleEvents(),
      ...createBigWinEvents(),
      ...createFeatureEvents(),
      ...createCascadeEvents(),
      ...createBonusEvents(),
      ...createGambleEvents(),
      ...createJackpotEvents(),
      ...createUIEvents(),
    ];
  }

  // ─── SPIN LIFECYCLE ────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createSpinLifecycleEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_spin_start',
        name: 'Spin Start',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_spin_button', bus: 'UI'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.7, fadeTime: 0.2),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_reel_spin',
        name: 'Reel Spinning',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_reel_spin_loop', bus: 'Reels', loop: true),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_reel_stop',
        name: 'Reel Stop',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_reel_spin_loop'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_reel_stop', bus: 'Reels'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_spin_end',
        name: 'Spin End',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 1.0, fadeTime: 0.5),
        ],
      ),
    ];
  }

  // ─── ANTICIPATION ──────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createAnticipationEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_anticipation_on',
        name: 'Anticipation Start',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_anticipation_loop', bus: 'Anticipation', loop: true, fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.4, fadeTime: 0.1),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_anticipation_off',
        name: 'Anticipation End',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_anticipation_loop', fadeTime: 0.2),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 1.0, fadeTime: 0.3),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_near_miss',
        name: 'Near Miss',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_near_miss', bus: 'SFX'),
        ],
      ),
    ];
  }

  // ─── WIN LIFECYCLE ─────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createWinLifecycleEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_win_present',
        name: 'Win Present',
        category: 'Slot_Win',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_win_present', bus: 'Wins'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_win_line_show',
        name: 'Win Line Show',
        category: 'Slot_Win',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_win_line', bus: 'Wins'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_rollup_start',
        name: 'Rollup Start',
        category: 'Slot_Win',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_rollup_loop', bus: 'Wins', loop: true),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_rollup_tick',
        name: 'Rollup Tick',
        category: 'Slot_Win',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_rollup_tick', bus: 'Wins'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_rollup_end',
        name: 'Rollup End',
        category: 'Slot_Win',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_rollup_loop'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_rollup_end', bus: 'Wins'),
        ],
      ),
    ];
  }

  // ─── BIG WIN TIERS ─────────────────────────────────────────────────────────
  // Tier system: BIG_WIN_TIER_1 (20x-50x) → BIG_WIN_TIER_2 (50x-100x) → BIG_WIN_TIER_3 (100x-250x) → BIG_WIN_TIER_4 (250x-500x) → BIG_WIN_TIER_5 (500x+)

  static List<MiddlewareEvent> createBigWinEvents() {
    return [
      // BIG WIN TIER 1 — 20x-50x bet multiplier
      MiddlewareEvent(
        id: 'slot_bigwin_tier_1',
        name: 'BIG WIN TIER 1',
        category: 'Slot_BigWin',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.5, fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_bigwin_tier_1', bus: 'Wins'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_coins_light', bus: 'SFX', delay: 0.1),
        ],
      ),
      // BIG WIN TIER 2 — 50x-100x bet multiplier
      MiddlewareEvent(
        id: 'slot_bigwin_tier_2',
        name: 'BIG WIN TIER 2',
        category: 'Slot_BigWin',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.4, fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_bigwin_tier_2', bus: 'Wins'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_coins_shower', bus: 'SFX', delay: 0.15),
        ],
      ),
      // BIG WIN TIER 3 — 100x-250x bet multiplier
      MiddlewareEvent(
        id: 'slot_bigwin_tier_3',
        name: 'BIG WIN TIER 3',
        category: 'Slot_BigWin',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.3, fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_bigwin_tier_3', bus: 'Wins'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_crowd_cheer', bus: 'SFX', delay: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_coins_cascade', bus: 'SFX', delay: 0.3),
        ],
      ),
      // BIG WIN TIER 4 — 250x-500x bet multiplier
      MiddlewareEvent(
        id: 'slot_bigwin_tier_4',
        name: 'BIG WIN TIER 4',
        category: 'Slot_BigWin',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.2, fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_bigwin_tier_4', bus: 'Wins'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_crowd_roar', bus: 'SFX', delay: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_fireworks', bus: 'SFX', delay: 0.5),
        ],
      ),
      // BIG WIN TIER 5 — 500x+ bet multiplier (max tier)
      MiddlewareEvent(
        id: 'slot_bigwin_tier_5',
        name: 'BIG WIN TIER 5',
        category: 'Slot_BigWin',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stopAll, bus: 'Music', fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_bigwin_tier_5', bus: 'Wins'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_crowd_eruption', bus: 'SFX', delay: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_explosion_shower', bus: 'SFX', delay: 0.3),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'vo_bigwin_tier_5', bus: 'Voice', delay: 0.5),
        ],
      ),
    ];
  }

  // ─── FEATURE LIFECYCLE ─────────────────────────────────────────────────────

  static List<MiddlewareEvent> createFeatureEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_feature_enter',
        name: 'Feature Enter',
        category: 'Slot_Feature',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.0, fadeTime: 0.5),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_feature_intro', bus: 'Music', delay: 0.5),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_feature_trigger', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'vo_free_spins', bus: 'Voice', delay: 0.2),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_feature_step',
        name: 'Feature Step',
        category: 'Slot_Feature',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_feature_step', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_feature_retrigger',
        name: 'Feature Retrigger',
        category: 'Slot_Feature',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_retrigger', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'vo_more_spins', bus: 'Voice', delay: 0.1),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_feature_exit',
        name: 'Feature Exit',
        category: 'Slot_Feature',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.0, fadeTime: 0.3),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_feature_end', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_base_game', bus: 'Music', delay: 1.0, fadeTime: 0.5),
        ],
      ),
    ];
  }

  // ─── CASCADE/TUMBLE ────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createCascadeEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_cascade_start',
        name: 'Cascade Start',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_cascade_whoosh', bus: 'Reels'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_cascade_step',
        name: 'Cascade Step',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_cascade_impact', bus: 'Reels'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_cascade_end',
        name: 'Cascade End',
        category: 'Slot_Gameplay',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_cascade_end', bus: 'Reels'),
        ],
      ),
    ];
  }

  // ─── BONUS ─────────────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createBonusEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_bonus_enter',
        name: 'Bonus Enter',
        category: 'Slot_Bonus',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.0, fadeTime: 0.3),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_bonus_intro', bus: 'Music', delay: 0.3),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_bonus_enter', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_bonus_choice',
        name: 'Bonus Choice',
        category: 'Slot_Bonus',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_pick_select', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_bonus_reveal',
        name: 'Bonus Reveal',
        category: 'Slot_Bonus',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_reveal_good', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_bonus_exit',
        name: 'Bonus Exit',
        category: 'Slot_Bonus',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_bonus_complete', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_base_game', bus: 'Music', delay: 0.5, fadeTime: 0.5),
        ],
      ),
    ];
  }

  // ─── GAMBLE ────────────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createGambleEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_gamble_start',
        name: 'Gamble Start',
        category: 'Slot_Gamble',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.5, fadeTime: 0.2),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_gamble_heartbeat', bus: 'SFX', loop: true),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_gamble_win',
        name: 'Gamble Win',
        category: 'Slot_Gamble',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_gamble_heartbeat'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_gamble_win', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_gamble_lose',
        name: 'Gamble Lose',
        category: 'Slot_Gamble',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_gamble_heartbeat'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_gamble_lose', bus: 'SFX'),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_gamble_collect',
        name: 'Gamble Collect',
        category: 'Slot_Gamble',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stop, assetId: 'sfx_gamble_heartbeat'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_collect', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 1.0, fadeTime: 0.3),
        ],
      ),
    ];
  }

  // ─── JACKPOT ───────────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createJackpotEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_jackpot_trigger',
        name: 'Jackpot Trigger',
        category: 'Slot_Jackpot',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.stopAll, bus: 'Music', fadeTime: 0.1),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_jackpot_alarm', bus: 'SFX'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_jackpot_intro', bus: 'Music', delay: 0.5),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_jackpot_present',
        name: 'Jackpot Present',
        category: 'Slot_Jackpot',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_jackpot_win', bus: 'Music'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_jackpot_bells', bus: 'SFX', delay: 0.2),
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'vo_jackpot', bus: 'Voice', delay: 0.5),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_jackpot_end',
        name: 'Jackpot End',
        category: 'Slot_Jackpot',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'mus_base_game', bus: 'Music', delay: 1.0, fadeTime: 1.0),
        ],
      ),
    ];
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  static List<MiddlewareEvent> createUIEvents() {
    return [
      MiddlewareEvent(
        id: 'slot_idle_start',
        name: 'Idle Start',
        category: 'Slot_UI',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.6, fadeTime: 2.0),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_menu_open',
        name: 'Menu Open',
        category: 'Slot_UI',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_menu_open', bus: 'UI'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 0.4, fadeTime: 0.2),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_menu_close',
        name: 'Menu Close',
        category: 'Slot_UI',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_menu_close', bus: 'UI'),
          MiddlewareAction(id: _nextActionId(), type: ActionType.setVolume, bus: 'Music', gain: 1.0, fadeTime: 0.2),
        ],
      ),
      MiddlewareEvent(
        id: 'slot_button_click',
        name: 'Button Click',
        category: 'Slot_UI',
        actions: [
          MiddlewareAction(id: _nextActionId(), type: ActionType.play, assetId: 'sfx_button_click', bus: 'UI'),
        ],
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT RTPC DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for creating slot-specific RTPC definitions
class SlotRtpcFactory {
  static List<RtpcDefinition> createAllRtpcs() {
    return [
      RtpcDefinition(
        id: SlotRtpcIds.winMultiplier,
        name: 'Win_Multiplier',
        min: 0.0,
        max: 1000.0,
        defaultValue: 0.0,
        curve: RtpcCurve(points: [
          const RtpcCurvePoint(x: 0.0, y: 0.0),
          const RtpcCurvePoint(x: 0.15, y: 0.3),
          const RtpcCurvePoint(x: 0.5, y: 0.6),
          const RtpcCurvePoint(x: 1.0, y: 1.0),
        ]),
      ),
      RtpcDefinition(
        id: SlotRtpcIds.betLevel,
        name: 'Bet_Level',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.5,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.volatility,
        name: 'Volatility',
        min: 0.0,
        max: 4.0,
        defaultValue: 1.0,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.tension,
        name: 'Tension',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.0,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.cascadeDepth,
        name: 'Cascade_Depth',
        min: 0.0,
        max: 15.0,
        defaultValue: 0.0,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.featureProgress,
        name: 'Feature_Progress',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.0,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.rollupSpeed,
        name: 'Rollup_Speed',
        min: 0.5,
        max: 4.0,
        defaultValue: 1.0,
      ),
      RtpcDefinition(
        id: SlotRtpcIds.jackpotPool,
        name: 'Jackpot_Pool',
        min: 0.0,
        max: 1.0,
        defaultValue: 0.3,
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT STATE GROUPS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for creating slot-specific state groups
class SlotStateGroupFactory {
  static StateGroup createGamePhaseGroup() {
    return StateGroup(
      id: SlotStateGroupIds.gamePhase,
      name: 'Game_Phase',
      states: const [
        StateDefinition(id: 0, name: 'Idle'),
        StateDefinition(id: 1, name: 'Base_Game'),
        StateDefinition(id: 2, name: 'Free_Spins'),
        StateDefinition(id: 3, name: 'Bonus'),
        StateDefinition(id: 4, name: 'Jackpot'),
        StateDefinition(id: 5, name: 'Gamble'),
      ],
      defaultStateId: 1,
      currentStateId: 1,
    );
  }

  static StateGroup createFeatureTypeGroup() {
    return StateGroup(
      id: SlotStateGroupIds.featureType,
      name: 'Feature_Type',
      states: const [
        StateDefinition(id: 0, name: 'None'),
        StateDefinition(id: 1, name: 'Free_Spins'),
        StateDefinition(id: 2, name: 'Pick_Bonus'),
        StateDefinition(id: 3, name: 'Wheel_Bonus'),
        StateDefinition(id: 4, name: 'Hold_And_Spin'),
        StateDefinition(id: 5, name: 'Cascade'),
      ],
      defaultStateId: 0,
      currentStateId: 0,
    );
  }

  static StateGroup createMusicModeGroup() {
    return StateGroup(
      id: SlotStateGroupIds.musicMode,
      name: 'Music_Mode',
      states: const [
        StateDefinition(id: 0, name: 'Normal'),
        StateDefinition(id: 1, name: 'Feature'),
        StateDefinition(id: 2, name: 'BigWin'),
        StateDefinition(id: 3, name: 'Jackpot'),
        StateDefinition(id: 4, name: 'Silent'),
      ],
      defaultStateId: 0,
      currentStateId: 0,
    );
  }

  static List<StateGroup> createAllGroups() {
    return [
      createGamePhaseGroup(),
      createFeatureTypeGroup(),
      createMusicModeGroup(),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT DUCKING PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Predefined ducking rules for slot games
class SlotDuckingPresets {
  static DuckingRule winsDuckMusic() => DuckingRule(
    id: 1,
    sourceBus: 'Wins',
    sourceBusId: SlotBusIds.wins,
    targetBus: 'Music',
    targetBusId: SlotBusIds.music,
    duckAmountDb: -6.0,
    attackMs: 50.0,
    releaseMs: 500.0,
    threshold: 0.01,
    curve: DuckingCurve.exponential,
  );

  static DuckingRule voiceDucksMusic() => DuckingRule(
    id: 2,
    sourceBus: 'Voice',
    sourceBusId: SlotBusIds.voice,
    targetBus: 'Music',
    targetBusId: SlotBusIds.music,
    duckAmountDb: -8.0,
    attackMs: 30.0,
    releaseMs: 300.0,
    threshold: 0.01,
    curve: DuckingCurve.linear,
  );

  static DuckingRule anticipationDucksMusic() => DuckingRule(
    id: 3,
    sourceBus: 'Anticipation',
    sourceBusId: SlotBusIds.anticipation,
    targetBus: 'Music',
    targetBusId: SlotBusIds.music,
    duckAmountDb: -10.0,
    attackMs: 100.0,
    releaseMs: 200.0,
    threshold: 0.01,
    curve: DuckingCurve.sCurve,
  );

  static List<DuckingRule> createAllRules() {
    return [
      winsDuckMusic(),
      voiceDucksMusic(),
      anticipationDucksMusic(),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT MUSIC SEGMENTS
// ═══════════════════════════════════════════════════════════════════════════

/// Music segment IDs for slot game states
class SlotMusicSegmentIds {
  static const int baseGame = 1;
  static const int freeSpins = 2;
  static const int bonus = 3;
  static const int bigWin = 4;
  static const int jackpot = 5;
  static const int idle = 6;
}

/// Factory for creating slot-specific music segments
class SlotMusicSegmentFactory {
  static MusicSegment createBaseGameSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.baseGame,
      name: 'Base_Game',
      soundId: 10001,
      tempo: 120.0,
      beatsPerBar: 4,
      durationBars: 16,
    );
  }

  static MusicSegment createFreeSpinsSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.freeSpins,
      name: 'Free_Spins',
      soundId: 10002,
      tempo: 130.0,
      beatsPerBar: 4,
      durationBars: 8,
    );
  }

  static MusicSegment createBonusSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.bonus,
      name: 'Bonus_Game',
      soundId: 10003,
      tempo: 110.0,
      beatsPerBar: 4,
      durationBars: 12,
    );
  }

  static MusicSegment createBigWinSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.bigWin,
      name: 'Big_Win',
      soundId: 10004,
      tempo: 140.0,
      beatsPerBar: 4,
      durationBars: 8,
    );
  }

  static MusicSegment createJackpotSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.jackpot,
      name: 'Jackpot',
      soundId: 10005,
      tempo: 150.0,
      beatsPerBar: 4,
      durationBars: 16,
    );
  }

  static MusicSegment createIdleSegment() {
    return MusicSegment(
      id: SlotMusicSegmentIds.idle,
      name: 'Idle',
      soundId: 10006,
      tempo: 90.0,
      beatsPerBar: 4,
      durationBars: 32,
    );
  }

  static List<MusicSegment> createAllSegments() {
    return [
      createBaseGameSegment(),
      createFreeSpinsSegment(),
      createBonusSegment(),
      createBigWinSegment(),
      createJackpotSegment(),
      createIdleSegment(),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT STINGERS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for creating slot-specific stingers
class SlotStingerFactory {
  static Stinger createBigWinStinger() {
    return Stinger(
      id: 1,
      name: 'BigWin_Stinger',
      soundId: 20001,
      syncPoint: MusicSyncPoint.bar,
      musicDuckDb: -12.0,
      duckAttackMs: 50.0,
      duckReleaseMs: 500.0,
      priority: 80,
      canInterrupt: true,
    );
  }

  static Stinger createFeatureTriggerStinger() {
    return Stinger(
      id: 2,
      name: 'Feature_Trigger',
      soundId: 20002,
      syncPoint: MusicSyncPoint.beat,
      musicDuckDb: -6.0,
      duckAttackMs: 30.0,
      duckReleaseMs: 300.0,
      priority: 70,
      canInterrupt: false,
    );
  }

  static Stinger createJackpotStinger() {
    return Stinger(
      id: 3,
      name: 'Jackpot_Stinger',
      soundId: 20003,
      syncPoint: MusicSyncPoint.immediate,
      musicDuckDb: -24.0,
      duckAttackMs: 10.0,
      duckReleaseMs: 1000.0,
      priority: 100,
      canInterrupt: true,
    );
  }

  static Stinger createNearMissStinger() {
    return Stinger(
      id: 4,
      name: 'Near_Miss',
      soundId: 20004,
      syncPoint: MusicSyncPoint.beat,
      musicDuckDb: -3.0,
      duckAttackMs: 50.0,
      duckReleaseMs: 200.0,
      priority: 40,
      canInterrupt: false,
    );
  }

  static List<Stinger> createAllStingers() {
    return [
      createBigWinStinger(),
      createFeatureTriggerStinger(),
      createJackpotStinger(),
      createNearMissStinger(),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT AUDIO PROFILE
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// SLOT ELEMENT TO EVENT MAPPING
// ═══════════════════════════════════════════════════════════════════════════

/// Defines which slot UI element triggers which event
enum SlotElementType {
  // Main controls
  spinButton,
  betIncrease,
  betDecrease,
  maxBet,
  autoPlay,
  turboMode,

  // Reels (indexed)
  reel1,
  reel2,
  reel3,
  reel4,
  reel5,

  // Win displays
  winDisplay,
  bigWinOverlay,
  jackpotDisplay,

  // Feature elements
  freeSpinTrigger,
  bonusTrigger,
  scatterSymbol,
  wildSymbol,

  // General
  menuButton,
  infoButton,

  // Timeline stages (for drag & drop)
  stageSpinStart,
  stageReelStop,
  stageAnticipation,
  stageWinPresent,
  stageRollup,
  stageBigWin,
  stageFeature,
  stageSpinEnd,

  // Custom user-defined
  custom,
}

/// Maps a slot element to its default event
class SlotElementEventMapping {
  /// Element type
  final SlotElementType element;

  /// Custom name (for custom elements)
  final String? customName;

  /// Event ID this element triggers
  final String eventId;

  /// Audio layers attached to this element (multiple sounds can play)
  final List<SlotAudioLayer> audioLayers;

  const SlotElementEventMapping({
    required this.element,
    this.customName,
    required this.eventId,
    this.audioLayers = const [],
  });

  /// Display name for the element
  String get displayName {
    if (customName != null) return customName!;
    return switch (element) {
      SlotElementType.spinButton => 'Spin Button',
      SlotElementType.betIncrease => 'Bet +',
      SlotElementType.betDecrease => 'Bet -',
      SlotElementType.maxBet => 'Max Bet',
      SlotElementType.autoPlay => 'Auto Play',
      SlotElementType.turboMode => 'Turbo Mode',
      SlotElementType.reel1 => 'Reel 1',
      SlotElementType.reel2 => 'Reel 2',
      SlotElementType.reel3 => 'Reel 3',
      SlotElementType.reel4 => 'Reel 4',
      SlotElementType.reel5 => 'Reel 5',
      SlotElementType.winDisplay => 'Win Display',
      SlotElementType.bigWinOverlay => 'Big Win',
      SlotElementType.jackpotDisplay => 'Jackpot',
      SlotElementType.freeSpinTrigger => 'Free Spins',
      SlotElementType.bonusTrigger => 'Bonus',
      SlotElementType.scatterSymbol => 'Scatter',
      SlotElementType.wildSymbol => 'Wild',
      SlotElementType.menuButton => 'Menu',
      SlotElementType.infoButton => 'Info',
      SlotElementType.stageSpinStart => 'SPIN START',
      SlotElementType.stageReelStop => 'REEL STOP',
      SlotElementType.stageAnticipation => 'ANTICIPATION',
      SlotElementType.stageWinPresent => 'WIN PRESENT',
      SlotElementType.stageRollup => 'ROLLUP',
      SlotElementType.stageBigWin => 'BIG WIN',
      SlotElementType.stageFeature => 'FEATURE',
      SlotElementType.stageSpinEnd => 'SPIN END',
      SlotElementType.custom => customName ?? 'Custom',
    };
  }

  /// Create a copy with updated audio layers
  SlotElementEventMapping copyWith({
    SlotElementType? element,
    String? customName,
    String? eventId,
    List<SlotAudioLayer>? audioLayers,
  }) {
    return SlotElementEventMapping(
      element: element ?? this.element,
      customName: customName ?? this.customName,
      eventId: eventId ?? this.eventId,
      audioLayers: audioLayers ?? this.audioLayers,
    );
  }

  /// Add an audio layer to this element
  SlotElementEventMapping addAudioLayer(SlotAudioLayer layer) {
    return copyWith(audioLayers: [...audioLayers, layer]);
  }
}

/// An audio layer attached to a slot element
class SlotAudioLayer {
  final String id;
  final String assetPath;
  final String assetName;
  final double volume;
  final bool muted;
  final bool solo;
  final double pan;
  final String bus;

  const SlotAudioLayer({
    required this.id,
    required this.assetPath,
    required this.assetName,
    this.volume = 1.0,
    this.muted = false,
    this.solo = false,
    this.pan = 0.0,
    this.bus = 'SFX',
  });

  SlotAudioLayer copyWith({
    String? id,
    String? assetPath,
    String? assetName,
    double? volume,
    bool? muted,
    bool? solo,
    double? pan,
    String? bus,
  }) {
    return SlotAudioLayer(
      id: id ?? this.id,
      assetPath: assetPath ?? this.assetPath,
      assetName: assetName ?? this.assetName,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      pan: pan ?? this.pan,
      bus: bus ?? this.bus,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetPath': assetPath,
    'assetName': assetName,
    'volume': volume,
    'muted': muted,
    'solo': solo,
    'pan': pan,
    'bus': bus,
  };

  factory SlotAudioLayer.fromJson(Map<String, dynamic> json) {
    return SlotAudioLayer(
      id: json['id'] as String,
      assetPath: json['assetPath'] as String,
      assetName: json['assetName'] as String,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      muted: json['muted'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      bus: json['bus'] as String? ?? 'SFX',
    );
  }
}

/// Factory for creating default element-to-event mappings
class SlotElementMappingFactory {
  static Map<SlotElementType, String> get defaultMappings => {
    // Main controls
    SlotElementType.spinButton: 'slot_spin_start',
    SlotElementType.betIncrease: 'slot_button_click',
    SlotElementType.betDecrease: 'slot_button_click',
    SlotElementType.maxBet: 'slot_button_click',
    SlotElementType.autoPlay: 'slot_button_click',
    SlotElementType.turboMode: 'slot_button_click',

    // Reels
    SlotElementType.reel1: 'slot_reel_stop',
    SlotElementType.reel2: 'slot_reel_stop',
    SlotElementType.reel3: 'slot_reel_stop',
    SlotElementType.reel4: 'slot_reel_stop',
    SlotElementType.reel5: 'slot_reel_stop',

    // Win
    SlotElementType.winDisplay: 'slot_win_present',
    SlotElementType.bigWinOverlay: 'slot_bigwin_mega',
    SlotElementType.jackpotDisplay: 'slot_jackpot_trigger',

    // Features
    SlotElementType.freeSpinTrigger: 'slot_feature_enter',
    SlotElementType.bonusTrigger: 'slot_bonus_enter',
    SlotElementType.scatterSymbol: 'slot_anticipation_on',
    SlotElementType.wildSymbol: 'slot_win_line_show',

    // UI
    SlotElementType.menuButton: 'slot_menu_open',
    SlotElementType.infoButton: 'slot_button_click',

    // Timeline stages
    SlotElementType.stageSpinStart: 'slot_spin_start',
    SlotElementType.stageReelStop: 'slot_reel_stop',
    SlotElementType.stageAnticipation: 'slot_anticipation_on',
    SlotElementType.stageWinPresent: 'slot_win_present',
    SlotElementType.stageRollup: 'slot_rollup_start',
    SlotElementType.stageBigWin: 'slot_bigwin_mega',
    SlotElementType.stageFeature: 'slot_feature_enter',
    SlotElementType.stageSpinEnd: 'slot_spin_end',
  };

  /// Create all default mappings with empty audio layers
  static List<SlotElementEventMapping> createDefaultMappings() {
    return defaultMappings.entries.map((entry) {
      return SlotElementEventMapping(
        element: entry.key,
        eventId: entry.value,
        audioLayers: [],
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT AUDIO PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// Complete slot audio profile containing all audio definitions
class SlotAudioProfile {
  final List<MiddlewareEvent> events;
  final List<RtpcDefinition> rtpcs;
  final List<StateGroup> stateGroups;
  final List<DuckingRule> duckingRules;
  final List<MusicSegment> musicSegments;
  final List<Stinger> stingers;
  final List<SlotElementEventMapping> elementMappings;

  const SlotAudioProfile({
    required this.events,
    required this.rtpcs,
    required this.stateGroups,
    required this.duckingRules,
    required this.musicSegments,
    required this.stingers,
    this.elementMappings = const [],
  });

  factory SlotAudioProfile.defaultProfile() {
    return SlotAudioProfile(
      events: SlotAudioEventFactory.createAllEvents(),
      rtpcs: SlotRtpcFactory.createAllRtpcs(),
      stateGroups: SlotStateGroupFactory.createAllGroups(),
      duckingRules: SlotDuckingPresets.createAllRules(),
      musicSegments: SlotMusicSegmentFactory.createAllSegments(),
      stingers: SlotStingerFactory.createAllStingers(),
      elementMappings: SlotElementMappingFactory.createDefaultMappings(),
    );
  }

  /// Get mapping for a specific element type
  SlotElementEventMapping? getMappingForElement(SlotElementType element) {
    try {
      return elementMappings.firstWhere((m) => m.element == element);
    } catch (_) {
      return null;
    }
  }

  /// Get event ID for a specific element
  String? getEventIdForElement(SlotElementType element) {
    return getMappingForElement(element)?.eventId;
  }

  ({
    int eventCount,
    int rtpcCount,
    int stateGroupCount,
    int duckingRuleCount,
    int musicSegmentCount,
    int stingerCount,
    int elementMappingCount,
  }) get stats => (
    eventCount: events.length,
    rtpcCount: rtpcs.length,
    stateGroupCount: stateGroups.length,
    duckingRuleCount: duckingRules.length,
    musicSegmentCount: musicSegments.length,
    stingerCount: stingers.length,
    elementMappingCount: elementMappings.length,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED AUDIO POOL (for DAW, Middleware, Slot Mode)
// ═══════════════════════════════════════════════════════════════════════════

/// Audio file in shared pool (accessible from all modes)
class SharedPoolAudioFile {
  final String id;
  final String path;
  final String name;
  final double duration;
  final int sampleRate;
  final int channels;
  final String format;
  final Float32List? waveform;
  final DateTime importedAt;

  const SharedPoolAudioFile({
    required this.id,
    required this.path,
    required this.name,
    required this.duration,
    this.sampleRate = 48000,
    this.channels = 2,
    this.format = 'wav',
    this.waveform,
    required this.importedAt,
  });

  SharedPoolAudioFile copyWith({
    String? id,
    String? path,
    String? name,
    double? duration,
    int? sampleRate,
    int? channels,
    String? format,
    Float32List? waveform,
    DateTime? importedAt,
  }) {
    return SharedPoolAudioFile(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      format: format ?? this.format,
      waveform: waveform ?? this.waveform,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  String get durationFormatted {
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();
    final ms = ((duration % 1) * 100).floor();
    if (mins > 0) {
      return '$mins:${secs.toString().padLeft(2, '0')}';
    }
    return '0:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT MODE STATE MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Audio region on a slot timeline track
class SlotAudioRegion {
  final String id;
  final String name;
  final String audioPath;
  final double startPosition; // 0.0 to 1.0 normalized
  final double duration; // in seconds
  final List<double>? waveformData;

  const SlotAudioRegion({
    required this.id,
    required this.name,
    required this.audioPath,
    required this.startPosition,
    required this.duration,
    this.waveformData,
  });

  SlotAudioRegion copyWith({
    String? id,
    String? name,
    String? audioPath,
    double? startPosition,
    double? duration,
    List<double>? waveformData,
  }) {
    return SlotAudioRegion(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      startPosition: startPosition ?? this.startPosition,
      duration: duration ?? this.duration,
      waveformData: waveformData ?? this.waveformData,
    );
  }
}

/// Audio track in slot timeline
class SlotAudioTrack {
  final String id;
  final String name;
  final Color color;
  final List<SlotAudioRegion> regions;
  final bool muted;
  final bool solo;
  final double volume;

  const SlotAudioTrack({
    required this.id,
    required this.name,
    required this.color,
    this.regions = const [],
    this.muted = false,
    this.solo = false,
    this.volume = 0.8,
  });

  SlotAudioTrack copyWith({
    String? id,
    String? name,
    Color? color,
    List<SlotAudioRegion>? regions,
    bool? muted,
    bool? solo,
    double? volume,
  }) {
    return SlotAudioTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      regions: regions ?? this.regions,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      volume: volume ?? this.volume,
    );
  }
}

/// Stage marker on slot timeline
class SlotStageMarker {
  final String id;
  final double position; // 0.0 to 1.0
  final String name;
  final Color color;

  const SlotStageMarker({
    required this.id,
    required this.position,
    required this.name,
    required this.color,
  });

  SlotStageMarker copyWith({
    String? id,
    double? position,
    String? name,
    Color? color,
  }) {
    return SlotStageMarker(
      id: id ?? this.id,
      position: position ?? this.position,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPOSITE EVENT SYSTEM (Wwise/FMOD-style event layering)
// ═══════════════════════════════════════════════════════════════════════════

/// Single audio layer within a composite event
class SlotEventLayer {
  final String id;
  final String name;
  final String audioPath;
  final double volume; // 0.0 to 1.0
  final double pan; // -1.0 (left) to 1.0 (right)
  final double offsetMs; // Delay offset in milliseconds
  final double fadeInMs; // Fade in duration
  final double fadeOutMs; // Fade out duration
  final CrossfadeCurve fadeInCurve; // Fade in curve type
  final CrossfadeCurve fadeOutCurve; // Fade out curve type
  final double trimStartMs; // Non-destructive trim start (M3.2)
  final double trimEndMs; // Non-destructive trim end (M3.2) - 0 means no trim
  final bool muted;
  final bool solo;
  final List<double>? waveformData;
  final double? durationSeconds;
  final int? busId; // Target bus for routing
  final String actionType; // Action type: Play, Stop, SetVolume, etc.
  final int? aleLayerId; // ALE layer assignment (1-5: L1=Calm to L5=Epic) — P0 WF-04

  const SlotEventLayer({
    required this.id,
    required this.name,
    required this.audioPath,
    this.volume = 1.0,
    this.pan = 0.0,
    this.offsetMs = 0.0,
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
    this.fadeInCurve = CrossfadeCurve.linear,
    this.fadeOutCurve = CrossfadeCurve.linear,
    this.trimStartMs = 0.0,
    this.trimEndMs = 0.0,
    this.muted = false,
    this.solo = false,
    this.waveformData,
    this.durationSeconds,
    this.busId,
    this.actionType = 'Play',
    this.aleLayerId,
  });

  SlotEventLayer copyWith({
    String? id,
    String? name,
    String? audioPath,
    double? volume,
    double? pan,
    double? offsetMs,
    double? fadeInMs,
    double? fadeOutMs,
    CrossfadeCurve? fadeInCurve,
    CrossfadeCurve? fadeOutCurve,
    double? trimStartMs,
    double? trimEndMs,
    bool? muted,
    bool? solo,
    List<double>? waveformData,
    double? durationSeconds,
    int? busId,
    String? actionType,
    int? aleLayerId,
  }) {
    return SlotEventLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      offsetMs: offsetMs ?? this.offsetMs,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      fadeInCurve: fadeInCurve ?? this.fadeInCurve,
      fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      muted: muted ?? this.muted,
      solo: solo ?? this.solo,
      waveformData: waveformData ?? this.waveformData,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      busId: busId ?? this.busId,
      actionType: actionType ?? this.actionType,
      aleLayerId: aleLayerId ?? this.aleLayerId,
    );
  }

  /// Total duration including offset
  double get totalDurationMs => (durationSeconds ?? 0) * 1000 + offsetMs;

  /// Convert to JSON for project save
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'audioPath': audioPath,
    'volume': volume,
    'pan': pan,
    'offsetMs': offsetMs,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'fadeInCurve': fadeInCurve.name,
    'fadeOutCurve': fadeOutCurve.name,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'muted': muted,
    'solo': solo,
    'durationSeconds': durationSeconds,
    'busId': busId,
    'actionType': actionType,
    'aleLayerId': aleLayerId, // P0 WF-04
    // Note: waveformData is not saved - it's regenerated on load
  };

  /// Create from JSON
  factory SlotEventLayer.fromJson(Map<String, dynamic> json) {
    return SlotEventLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      audioPath: json['audioPath'] as String,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      offsetMs: (json['offsetMs'] as num?)?.toDouble() ?? 0.0,
      fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 0.0,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
      fadeInCurve: CrossfadeCurve.values.firstWhere(
        (e) => e.name == json['fadeInCurve'],
        orElse: () => CrossfadeCurve.linear,
      ),
      fadeOutCurve: CrossfadeCurve.values.firstWhere(
        (e) => e.name == json['fadeOutCurve'],
        orElse: () => CrossfadeCurve.linear,
      ),
      trimStartMs: (json['trimStartMs'] as num?)?.toDouble() ?? 0.0,
      trimEndMs: (json['trimEndMs'] as num?)?.toDouble() ?? 0.0,
      muted: json['muted'] as bool? ?? false,
      solo: json['solo'] as bool? ?? false,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
      busId: json['busId'] as int?,
      actionType: json['actionType'] as String? ?? 'Play',
      aleLayerId: json['aleLayerId'] as int?, // P0 WF-04
    );
  }
}

/// Composite event containing multiple layered sounds
class SlotCompositeEvent {
  final String id;
  final String name;
  final String category; // spin, win, feature, ui, etc.
  final Color color;
  final List<SlotEventLayer> layers;
  final double masterVolume;
  final int? targetBusId;
  final bool looping;
  final int maxInstances; // Polyphony limit
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Stage types that trigger this event (e.g., ['spin_start', 'reel_stop'])
  final List<String> triggerStages;

  /// Optional RTPC conditions for triggering (e.g., {'win_multiplier': '>= 10'})
  final Map<String, String> triggerConditions;

  /// Timeline position in milliseconds (for SlotLab timeline display)
  /// This is the absolute position where the event starts on the timeline.
  /// Layer offsetMs values are relative to this position.
  final double timelinePositionMs;

  /// Track index on the SlotLab timeline (0-based)
  final int trackIndex;

  /// Container integration: type of container to use instead of direct layers
  final ContainerType containerType;

  /// Container integration: ID of the container (if using container)
  final int? containerId;

  /// Music overlap control: when false, stops any other music on same bus before playing
  /// Default: true (overlapping allowed)
  /// For music events (busId == 1), this should be false to prevent music overlap
  final bool overlap;

  /// Default crossfade duration in ms when transitioning music (when overlap=false)
  final int crossfadeMs;

  const SlotCompositeEvent({
    required this.id,
    required this.name,
    this.category = 'general',
    required this.color,
    this.layers = const [],
    this.masterVolume = 1.0,
    this.targetBusId,
    this.looping = false,
    this.maxInstances = 1,
    required this.createdAt,
    required this.modifiedAt,
    this.triggerStages = const [],
    this.triggerConditions = const {},
    this.timelinePositionMs = 0.0,
    this.trackIndex = 0,
    this.containerType = ContainerType.none,
    this.containerId,
    this.overlap = true,
    this.crossfadeMs = 500,
  });

  SlotCompositeEvent copyWith({
    String? id,
    String? name,
    String? category,
    Color? color,
    List<SlotEventLayer>? layers,
    double? masterVolume,
    int? targetBusId,
    bool? looping,
    int? maxInstances,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? triggerStages,
    Map<String, String>? triggerConditions,
    double? timelinePositionMs,
    int? trackIndex,
    ContainerType? containerType,
    int? containerId,
    bool? overlap,
    int? crossfadeMs,
  }) {
    return SlotCompositeEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      color: color ?? this.color,
      layers: layers ?? this.layers,
      masterVolume: masterVolume ?? this.masterVolume,
      targetBusId: targetBusId ?? this.targetBusId,
      looping: looping ?? this.looping,
      maxInstances: maxInstances ?? this.maxInstances,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      triggerStages: triggerStages ?? this.triggerStages,
      triggerConditions: triggerConditions ?? this.triggerConditions,
      timelinePositionMs: timelinePositionMs ?? this.timelinePositionMs,
      trackIndex: trackIndex ?? this.trackIndex,
      containerType: containerType ?? this.containerType,
      containerId: containerId ?? this.containerId,
      overlap: overlap ?? this.overlap,
      crossfadeMs: crossfadeMs ?? this.crossfadeMs,
    );
  }

  /// Returns true if this event uses a container instead of direct layers
  bool get usesContainer => containerType != ContainerType.none && containerId != null;

  /// Timeline position in seconds (convenience getter)
  double get timelinePositionSeconds => timelinePositionMs / 1000.0;

  /// Total duration of event (longest layer including offset)
  double get totalDurationMs {
    if (layers.isEmpty) return 0;
    return layers.map((l) => l.totalDurationMs).reduce((a, b) => a > b ? a : b);
  }

  double get totalDurationSeconds => totalDurationMs / 1000;

  /// Number of active (non-muted) layers
  int get activeLayerCount => layers.where((l) => !l.muted).length;

  /// Check if any layer is soloed
  bool get hasSoloedLayer => layers.any((l) => l.solo);

  /// Get layers that should play (respecting solo/mute)
  List<SlotEventLayer> get playableLayers {
    if (hasSoloedLayer) {
      return layers.where((l) => l.solo && !l.muted).toList();
    }
    return layers.where((l) => !l.muted).toList();
  }

  /// Convert to JSON for project save
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'color': color.value,
    'layers': layers.map((l) => l.toJson()).toList(),
    'masterVolume': masterVolume,
    'targetBusId': targetBusId,
    'looping': looping,
    'maxInstances': maxInstances,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'triggerStages': triggerStages,
    'triggerConditions': triggerConditions,
    'timelinePositionMs': timelinePositionMs,
    'trackIndex': trackIndex,
    'containerType': containerType.index,
    'containerId': containerId,
    'overlap': overlap,
    'crossfadeMs': crossfadeMs,
  };

  /// Create from JSON
  factory SlotCompositeEvent.fromJson(Map<String, dynamic> json) {
    return SlotCompositeEvent(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? 'general',
      color: Color(json['color'] as int? ?? 0xFF4A9EFF),
      layers: (json['layers'] as List<dynamic>?)
          ?.map((l) => SlotEventLayer.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 1.0,
      targetBusId: json['targetBusId'] as int?,
      looping: json['looping'] as bool? ?? false,
      maxInstances: json['maxInstances'] as int? ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : DateTime.now(),
      triggerStages: (json['triggerStages'] as List<dynamic>?)
          ?.map((s) => s as String)
          .toList() ?? [],
      triggerConditions: (json['triggerConditions'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)) ?? {},
      timelinePositionMs: (json['timelinePositionMs'] as num?)?.toDouble() ?? 0.0,
      trackIndex: json['trackIndex'] as int? ?? 0,
      containerType: ContainerTypeExtension.fromValue(json['containerType'] as int? ?? 0),
      containerId: json['containerId'] as int?,
      overlap: json['overlap'] as bool? ?? true,
      crossfadeMs: json['crossfadeMs'] as int? ?? 500,
    );
  }

  /// Check if this event is a music event (targets music bus)
  bool get isMusicEvent => targetBusId == SlotBusIds.music;

  /// Check if this event should auto-loop (music without _END in name)
  bool get shouldAutoLoop {
    if (!isMusicEvent) return false;
    final upperName = name.toUpperCase();
    // If name contains _END, don't loop
    if (upperName.contains('_END')) return false;
    // Music events loop by default
    return true;
  }
}

/// Event categories for slot games
enum SlotEventCategory {
  spin('Spin', Color(0xFF4A9EFF)),
  reelStop('Reel Stop', Color(0xFF9B59B6)),
  anticipation('Anticipation', Color(0xFFE74C3C)),
  win('Win', Color(0xFFF1C40F)),
  bigWin('Big Win', Color(0xFFFF9040)),
  feature('Feature', Color(0xFF40FF90)),
  bonus('Bonus', Color(0xFFFF40FF)),
  ui('UI', Color(0xFF888888)),
  ambient('Ambient', Color(0xFF40C8FF)),
  music('Music', Color(0xFFE91E63));

  final String displayName;
  final Color color;

  const SlotEventCategory(this.displayName, this.color);
}

/// Predefined slot event templates
class SlotEventTemplates {
  static SlotCompositeEvent spinStart() => SlotCompositeEvent(
    id: 'template_spin_start',
    name: 'Spin Start',
    category: 'spin',
    color: SlotEventCategory.spin.color,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static SlotCompositeEvent reelStop(int reelIndex) => SlotCompositeEvent(
    id: 'template_reel_stop_$reelIndex',
    name: 'Reel $reelIndex Stop',
    category: 'reelStop',
    color: SlotEventCategory.reelStop.color,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static SlotCompositeEvent anticipation() => SlotCompositeEvent(
    id: 'template_anticipation',
    name: 'Anticipation',
    category: 'anticipation',
    color: SlotEventCategory.anticipation.color,
    looping: true,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static SlotCompositeEvent winSmall() => SlotCompositeEvent(
    id: 'template_win_small',
    name: 'Small Win',
    category: 'win',
    color: SlotEventCategory.win.color,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static SlotCompositeEvent bigWinStart() => SlotCompositeEvent(
    id: 'template_big_win_start',
    name: 'Big Win Start',
    category: 'bigWin',
    color: SlotEventCategory.bigWin.color,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static SlotCompositeEvent featureEnter() => SlotCompositeEvent(
    id: 'template_feature_enter',
    name: 'Feature Enter',
    category: 'feature',
    color: SlotEventCategory.feature.color,
    createdAt: DateTime.now(),
    modifiedAt: DateTime.now(),
  );

  static List<SlotCompositeEvent> allTemplates() => [
    spinStart(),
    reelStop(1),
    reelStop(2),
    reelStop(3),
    reelStop(4),
    reelStop(5),
    anticipation(),
    winSmall(),
    bigWinStart(),
    featureEnter(),
  ];
}

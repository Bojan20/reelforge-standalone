/**
 * ReelForge Spatial System - Intent Rules
 * Defines spatial behavior rules per event intent.
 *
 * @module reelforge/spatial/core
 */

import type { IntentRule, SpatialBus } from '../types';

/**
 * Default intent rules for slot games.
 * These can be overridden or extended by game-specific rules.
 */
export const DEFAULT_INTENT_RULES: IntentRule[] = [
  // ========================================================================
  // UI INTERACTIONS
  // ========================================================================
  {
    intent: 'BUTTON_CLICK',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.95,
    smoothingTauMs: 40,
    lifetimeMs: 300,
    priority: 5,
    intentDefaultPos: { x: 0.5, y: 0.9 },
  },
  {
    intent: 'SPIN_BUTTON',
    defaultAnchorId: 'spin_button',
    wAnchor: 0.85,
    wMotion: 0.05,
    wIntent: 0.10,
    width: 0.40,
    deadzone: 0.04,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 400,
    priority: 6,
    intentDefaultPos: { x: 0.5, y: 0.92 },
  },
  {
    intent: 'UI_OPEN',
    wAnchor: 0.70,
    wMotion: 0.10,
    wIntent: 0.20,
    width: 0.50,
    deadzone: 0.05,
    maxPan: 0.70,
    smoothingTauMs: 80,
    lifetimeMs: 500,
    priority: 4,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'UI_CLOSE',
    wAnchor: 0.60,
    wMotion: 0.15,
    wIntent: 0.25,
    width: 0.45,
    deadzone: 0.05,
    maxPan: 0.65,
    smoothingTauMs: 70,
    lifetimeMs: 400,
    priority: 4,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'MENU_ITEM_HOVER',
    wAnchor: 0.95,
    wMotion: 0.03,
    wIntent: 0.02,
    width: 0.25,
    deadzone: 0.02,
    maxPan: 0.80,
    smoothingTauMs: 35,
    lifetimeMs: 200,
    priority: 3,
  },

  // ========================================================================
  // REEL MECHANICS
  // ========================================================================
  {
    intent: 'SPIN_START',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.75,
    wMotion: 0.10,
    wIntent: 0.15,
    width: 0.60,
    deadzone: 0.05,
    maxPan: 0.70,
    smoothingTauMs: 60,
    lifetimeMs: 500,
    priority: 7,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'REEL_STOP',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.20,
    deadzone: 0.03,
    maxPan: 0.80,
    smoothingTauMs: 55,
    lifetimeMs: 400,
    priority: 8,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'REEL_0_STOP',
    defaultAnchorId: 'reel_0',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.15,
    deadzone: 0.02,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.2, y: 0.55 },
  },
  {
    intent: 'REEL_1_STOP',
    defaultAnchorId: 'reel_1',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.15,
    deadzone: 0.02,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.35, y: 0.55 },
  },
  {
    intent: 'REEL_2_STOP',
    defaultAnchorId: 'reel_2',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.15,
    deadzone: 0.02,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'REEL_3_STOP',
    defaultAnchorId: 'reel_3',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.15,
    deadzone: 0.02,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.65, y: 0.55 },
  },
  {
    intent: 'REEL_4_STOP',
    defaultAnchorId: 'reel_4',
    wAnchor: 0.90,
    wMotion: 0.05,
    wIntent: 0.05,
    width: 0.15,
    deadzone: 0.02,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.8, y: 0.55 },
  },
  {
    intent: 'ANTICIPATION',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.70,
    wMotion: 0.05,
    wIntent: 0.25,
    width: 0.50,
    deadzone: 0.04,
    maxPan: 0.60,
    smoothingTauMs: 100,
    lifetimeMs: 2000,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },

  // ========================================================================
  // WIN PRESENTATIONS
  // ========================================================================
  {
    intent: 'WIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.60,
    wMotion: 0.10,
    wIntent: 0.30,
    width: 0.45,
    deadzone: 0.04,
    maxPan: 0.65,
    smoothingTauMs: 75,
    lifetimeMs: 800,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'WIN_LINE',
    wAnchor: 0.75,
    wMotion: 0.15,
    wIntent: 0.10,
    width: 0.55,
    deadzone: 0.03,
    maxPan: 0.80,
    smoothingTauMs: 65,
    lifetimeMs: 600,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'BIG_WIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.20,
    wMotion: 0.00,
    wIntent: 0.80,
    width: 0.70,
    deadzone: 0.06,
    maxPan: 0.25,
    smoothingTauMs: 90,
    lifetimeMs: 3000,
    priority: 15,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'MEGA_WIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.15,
    wMotion: 0.00,
    wIntent: 0.85,
    width: 0.75,
    deadzone: 0.08,
    maxPan: 0.20,
    smoothingTauMs: 100,
    lifetimeMs: 4000,
    priority: 16,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'EPIC_WIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.10,
    wMotion: 0.00,
    wIntent: 0.90,
    width: 0.80,
    deadzone: 0.10,
    maxPan: 0.15,
    smoothingTauMs: 120,
    lifetimeMs: 5000,
    priority: 17,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'WIN_COUNTER',
    defaultAnchorId: 'win_display',
    wAnchor: 0.80,
    wMotion: 0.05,
    wIntent: 0.15,
    width: 0.30,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 60,
    lifetimeMs: 2000,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.35 },
  },

  // ========================================================================
  // COIN ANIMATIONS
  // ========================================================================
  {
    intent: 'COIN_FLY',
    wAnchor: 0.50,
    wMotion: 0.40,
    wIntent: 0.10,
    width: 0.45,
    deadzone: 0.03,
    maxPan: 0.90,
    smoothingTauMs: 60,
    yToLPF: { minHz: 1000, maxHz: 18000 },
    lifetimeMs: 1000,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'COIN_FLY_TO_BALANCE',
    defaultAnchorId: 'balance_value',
    startAnchorFallback: 'reels_center',
    endAnchorFallback: 'balance_value',
    wAnchor: 0.55,
    wMotion: 0.35,
    wIntent: 0.10,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.95,
    smoothingTauMs: 70,
    yToLPF: { minHz: 1200, maxHz: 18000 },
    lifetimeMs: 1200,
    priority: 10,
    intentDefaultPos: { x: 0.85, y: 0.1 },
  },
  {
    intent: 'COIN_BURST',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.60,
    wMotion: 0.20,
    wIntent: 0.20,
    width: 0.65,
    deadzone: 0.05,
    maxPan: 0.85,
    smoothingTauMs: 55,
    lifetimeMs: 800,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },

  // ========================================================================
  // FEATURE TRIGGERS
  // ========================================================================
  {
    intent: 'FREE_SPIN_TRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.40,
    wMotion: 0.10,
    wIntent: 0.50,
    width: 0.65,
    deadzone: 0.05,
    maxPan: 0.45,
    smoothingTauMs: 85,
    lifetimeMs: 2500,
    priority: 14,
    intentDefaultPos: { x: 0.5, y: 0.45 },
  },
  {
    intent: 'FREE_SPIN_SPIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.65,
    wMotion: 0.15,
    wIntent: 0.20,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 60,
    lifetimeMs: 600,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'FREE_SPIN_RETRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.30,
    wMotion: 0.10,
    wIntent: 0.60,
    width: 0.70,
    deadzone: 0.06,
    maxPan: 0.40,
    smoothingTauMs: 95,
    lifetimeMs: 2000,
    priority: 15,
    intentDefaultPos: { x: 0.5, y: 0.45 },
  },
  {
    intent: 'RESPIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.70,
    wMotion: 0.15,
    wIntent: 0.15,
    width: 0.50,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 55,
    lifetimeMs: 500,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'RESPIN_TRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.50,
    wMotion: 0.10,
    wIntent: 0.40,
    width: 0.60,
    deadzone: 0.05,
    maxPan: 0.55,
    smoothingTauMs: 75,
    lifetimeMs: 1500,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.50 },
  },
  {
    intent: 'BONUS_TRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.35,
    wMotion: 0.10,
    wIntent: 0.55,
    width: 0.70,
    deadzone: 0.06,
    maxPan: 0.40,
    smoothingTauMs: 90,
    lifetimeMs: 2500,
    priority: 14,
    intentDefaultPos: { x: 0.5, y: 0.45 },
  },
  {
    intent: 'SCATTER_LAND',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.40,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 55,
    lifetimeMs: 500,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'SCATTER_COUNT',
    defaultAnchorId: 'scatter_counter',
    wAnchor: 0.70,
    wMotion: 0.10,
    wIntent: 0.20,
    width: 0.45,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 60,
    lifetimeMs: 400,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.35 },
  },
  {
    intent: 'WILD_LAND',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 450,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'MULTIPLIER_INCREASE',
    defaultAnchorId: 'multiplier_display',
    wAnchor: 0.75,
    wMotion: 0.05,
    wIntent: 0.20,
    width: 0.35,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 65,
    lifetimeMs: 600,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.3 },
  },

  // ========================================================================
  // HOLD & WIN / LIGHTNING
  // ========================================================================
  {
    intent: 'HOLD_AND_WIN_TRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.35,
    wMotion: 0.10,
    wIntent: 0.55,
    width: 0.70,
    deadzone: 0.06,
    maxPan: 0.40,
    smoothingTauMs: 90,
    lifetimeMs: 2500,
    priority: 14,
    intentDefaultPos: { x: 0.5, y: 0.45 },
  },
  {
    intent: 'HOLD_AND_WIN_SPIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.65,
    wMotion: 0.15,
    wIntent: 0.20,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 55,
    lifetimeMs: 500,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'HOLD_AND_WIN_LOCK',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.30,
    deadzone: 0.03,
    maxPan: 0.90,
    smoothingTauMs: 45,
    lifetimeMs: 400,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'HOLD_AND_WIN_UPGRADE',
    wAnchor: 0.80,
    wMotion: 0.10,
    wIntent: 0.10,
    width: 0.40,
    deadzone: 0.04,
    maxPan: 0.80,
    smoothingTauMs: 55,
    lifetimeMs: 500,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'HOLD_AND_WIN_RESET',
    defaultAnchorId: 'respins_counter',
    wAnchor: 0.70,
    wMotion: 0.05,
    wIntent: 0.25,
    width: 0.35,
    deadzone: 0.04,
    maxPan: 0.65,
    smoothingTauMs: 60,
    lifetimeMs: 350,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.25 },
  },
  {
    intent: 'LIGHTNING_STRIKE',
    wAnchor: 0.75,
    wMotion: 0.15,
    wIntent: 0.10,
    width: 0.45,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 40,
    lifetimeMs: 350,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },

  // ========================================================================
  // CASCADE / TUMBLE MECHANICS
  // ========================================================================
  {
    intent: 'CASCADE_START',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.65,
    wMotion: 0.20,
    wIntent: 0.15,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 60,
    lifetimeMs: 400,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CASCADE_SYMBOL_REMOVE',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.30,
    deadzone: 0.03,
    maxPan: 0.90,
    smoothingTauMs: 45,
    lifetimeMs: 250,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CASCADE_SYMBOL_FALL',
    wAnchor: 0.70,
    wMotion: 0.25,
    wIntent: 0.05,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.85,
    yToLPF: { minHz: 800, maxHz: 16000 },
    smoothingTauMs: 50,
    lifetimeMs: 300,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.4 },
  },
  {
    intent: 'CASCADE_NEW_SYMBOLS',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.60,
    wMotion: 0.30,
    wIntent: 0.10,
    width: 0.50,
    deadzone: 0.04,
    maxPan: 0.80,
    yToLPF: { minHz: 1000, maxHz: 18000 },
    smoothingTauMs: 55,
    lifetimeMs: 350,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.3 },
  },
  {
    intent: 'CASCADE_WIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.55,
    wMotion: 0.15,
    wIntent: 0.30,
    width: 0.50,
    deadzone: 0.04,
    maxPan: 0.70,
    smoothingTauMs: 70,
    lifetimeMs: 600,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CASCADE_CHAIN',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.40,
    wMotion: 0.10,
    wIntent: 0.50,
    width: 0.60,
    deadzone: 0.05,
    maxPan: 0.55,
    smoothingTauMs: 80,
    lifetimeMs: 800,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },

  // ========================================================================
  // CLUSTER PAYS
  // ========================================================================
  {
    intent: 'CLUSTER_FORM',
    wAnchor: 0.75,
    wMotion: 0.15,
    wIntent: 0.10,
    width: 0.50,
    deadzone: 0.04,
    maxPan: 0.80,
    smoothingTauMs: 65,
    lifetimeMs: 500,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CLUSTER_GROW',
    wAnchor: 0.70,
    wMotion: 0.20,
    wIntent: 0.10,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 60,
    lifetimeMs: 400,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CLUSTER_PAY',
    wAnchor: 0.60,
    wMotion: 0.15,
    wIntent: 0.25,
    width: 0.55,
    deadzone: 0.05,
    maxPan: 0.70,
    smoothingTauMs: 75,
    lifetimeMs: 700,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'CLUSTER_EXPLOSION',
    wAnchor: 0.50,
    wMotion: 0.25,
    wIntent: 0.25,
    width: 0.65,
    deadzone: 0.05,
    maxPan: 0.75,
    smoothingTauMs: 55,
    lifetimeMs: 450,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },

  // ========================================================================
  // MEGAWAYS / VARIABLE REELS
  // ========================================================================
  {
    intent: 'MEGAWAYS_REEL_CHANGE',
    wAnchor: 0.80,
    wMotion: 0.10,
    wIntent: 0.10,
    width: 0.40,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 8,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'MEGAWAYS_MAX_WAYS',
    defaultAnchorId: 'ways_counter',
    wAnchor: 0.35,
    wMotion: 0.05,
    wIntent: 0.60,
    width: 0.70,
    deadzone: 0.06,
    maxPan: 0.40,
    smoothingTauMs: 90,
    lifetimeMs: 1500,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.3 },
  },
  {
    intent: 'WAYS_WIN',
    wAnchor: 0.65,
    wMotion: 0.15,
    wIntent: 0.20,
    width: 0.55,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 65,
    lifetimeMs: 600,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },

  // ========================================================================
  // EXPANDING / STICKY WILDS
  // ========================================================================
  {
    intent: 'WILD_EXPAND',
    wAnchor: 0.80,
    wMotion: 0.10,
    wIntent: 0.10,
    width: 0.45,
    deadzone: 0.03,
    maxPan: 0.80,
    smoothingTauMs: 55,
    lifetimeMs: 600,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'WILD_STICKY',
    wAnchor: 0.85,
    wMotion: 0.05,
    wIntent: 0.10,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 400,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'WILD_WALKING',
    wAnchor: 0.70,
    wMotion: 0.25,
    wIntent: 0.05,
    width: 0.45,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 55,
    lifetimeMs: 500,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'WILD_MULTIPLIER',
    wAnchor: 0.75,
    wMotion: 0.10,
    wIntent: 0.15,
    width: 0.40,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 60,
    lifetimeMs: 500,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },

  // ========================================================================
  // SYMBOL TRANSFORMATIONS
  // ========================================================================
  {
    intent: 'SYMBOL_TRANSFORM',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 50,
    lifetimeMs: 400,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'SYMBOL_UPGRADE',
    wAnchor: 0.80,
    wMotion: 0.10,
    wIntent: 0.10,
    width: 0.40,
    deadzone: 0.04,
    maxPan: 0.80,
    smoothingTauMs: 55,
    lifetimeMs: 450,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },
  {
    intent: 'MYSTERY_REVEAL',
    wAnchor: 0.80,
    wMotion: 0.05,
    wIntent: 0.15,
    width: 0.45,
    deadzone: 0.04,
    maxPan: 0.75,
    smoothingTauMs: 65,
    lifetimeMs: 600,
    priority: 11,
    intentDefaultPos: { x: 0.5, y: 0.55 },
  },

  // ========================================================================
  // JACKPOT & PROGRESSIVES
  // ========================================================================
  {
    intent: 'JACKPOT_TRIGGER',
    defaultAnchorId: 'reels_center',
    wAnchor: 0.10,
    wMotion: 0.00,
    wIntent: 0.90,
    width: 0.85,
    deadzone: 0.10,
    maxPan: 0.10,
    smoothingTauMs: 150,
    lifetimeMs: 8000,
    priority: 20,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'JACKPOT_MINI',
    defaultAnchorId: 'jackpot_mini',
    wAnchor: 0.75,
    wMotion: 0.05,
    wIntent: 0.20,
    width: 0.50,
    deadzone: 0.05,
    maxPan: 0.70,
    smoothingTauMs: 80,
    lifetimeMs: 3000,
    priority: 16,
    intentDefaultPos: { x: 0.2, y: 0.15 },
  },
  {
    intent: 'JACKPOT_MINOR',
    defaultAnchorId: 'jackpot_minor',
    wAnchor: 0.70,
    wMotion: 0.05,
    wIntent: 0.25,
    width: 0.55,
    deadzone: 0.05,
    maxPan: 0.65,
    smoothingTauMs: 90,
    lifetimeMs: 3500,
    priority: 17,
    intentDefaultPos: { x: 0.4, y: 0.15 },
  },
  {
    intent: 'JACKPOT_MAJOR',
    defaultAnchorId: 'jackpot_major',
    wAnchor: 0.65,
    wMotion: 0.05,
    wIntent: 0.30,
    width: 0.60,
    deadzone: 0.06,
    maxPan: 0.55,
    smoothingTauMs: 100,
    lifetimeMs: 4000,
    priority: 18,
    intentDefaultPos: { x: 0.6, y: 0.15 },
  },
  {
    intent: 'JACKPOT_GRAND',
    defaultAnchorId: 'jackpot_grand',
    wAnchor: 0.20,
    wMotion: 0.00,
    wIntent: 0.80,
    width: 0.80,
    deadzone: 0.08,
    maxPan: 0.20,
    smoothingTauMs: 120,
    lifetimeMs: 6000,
    priority: 19,
    intentDefaultPos: { x: 0.8, y: 0.15 },
  },
  {
    intent: 'PROGRESSIVE_TICK',
    defaultAnchorId: 'jackpot_display',
    wAnchor: 0.85,
    wMotion: 0.05,
    wIntent: 0.10,
    width: 0.30,
    deadzone: 0.03,
    maxPan: 0.80,
    smoothingTauMs: 40,
    lifetimeMs: 200,
    priority: 3,
    intentDefaultPos: { x: 0.5, y: 0.1 },
  },

  // ========================================================================
  // COLLECTOR / METER MECHANICS
  // ========================================================================
  {
    intent: 'COLLECTOR_ADD',
    defaultAnchorId: 'collector_meter',
    wAnchor: 0.75,
    wMotion: 0.15,
    wIntent: 0.10,
    width: 0.40,
    deadzone: 0.04,
    maxPan: 0.80,
    smoothingTauMs: 55,
    lifetimeMs: 400,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.25 },
  },
  {
    intent: 'COLLECTOR_FILL',
    defaultAnchorId: 'collector_meter',
    wAnchor: 0.60,
    wMotion: 0.10,
    wIntent: 0.30,
    width: 0.55,
    deadzone: 0.05,
    maxPan: 0.65,
    smoothingTauMs: 75,
    lifetimeMs: 800,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.25 },
  },
  {
    intent: 'COLLECTOR_PAYOUT',
    defaultAnchorId: 'collector_meter',
    wAnchor: 0.40,
    wMotion: 0.10,
    wIntent: 0.50,
    width: 0.65,
    deadzone: 0.06,
    maxPan: 0.50,
    smoothingTauMs: 90,
    lifetimeMs: 1500,
    priority: 14,
    intentDefaultPos: { x: 0.5, y: 0.3 },
  },
  {
    intent: 'METER_INCREASE',
    defaultAnchorId: 'meter_display',
    wAnchor: 0.80,
    wMotion: 0.10,
    wIntent: 0.10,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.75,
    smoothingTauMs: 50,
    lifetimeMs: 350,
    priority: 9,
    intentDefaultPos: { x: 0.5, y: 0.2 },
  },
  {
    intent: 'METER_FULL',
    defaultAnchorId: 'meter_display',
    wAnchor: 0.50,
    wMotion: 0.05,
    wIntent: 0.45,
    width: 0.60,
    deadzone: 0.05,
    maxPan: 0.55,
    smoothingTauMs: 80,
    lifetimeMs: 1200,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.2 },
  },

  // ========================================================================
  // GAMBLE / DOUBLE UP
  // ========================================================================
  {
    intent: 'GAMBLE_START',
    defaultAnchorId: 'gamble_panel',
    wAnchor: 0.60,
    wMotion: 0.05,
    wIntent: 0.35,
    width: 0.55,
    deadzone: 0.05,
    maxPan: 0.60,
    smoothingTauMs: 75,
    lifetimeMs: 1000,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'GAMBLE_WIN',
    defaultAnchorId: 'gamble_panel',
    wAnchor: 0.50,
    wMotion: 0.10,
    wIntent: 0.40,
    width: 0.60,
    deadzone: 0.05,
    maxPan: 0.55,
    smoothingTauMs: 70,
    lifetimeMs: 1200,
    priority: 13,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'GAMBLE_LOSE',
    defaultAnchorId: 'gamble_panel',
    wAnchor: 0.50,
    wMotion: 0.05,
    wIntent: 0.45,
    width: 0.50,
    deadzone: 0.05,
    maxPan: 0.50,
    smoothingTauMs: 80,
    lifetimeMs: 800,
    priority: 12,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'CARD_FLIP',
    defaultAnchorId: 'gamble_card',
    wAnchor: 0.85,
    wMotion: 0.10,
    wIntent: 0.05,
    width: 0.35,
    deadzone: 0.03,
    maxPan: 0.85,
    smoothingTauMs: 45,
    lifetimeMs: 400,
    priority: 10,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },

  // ========================================================================
  // AMBIENT / BACKGROUND
  // ========================================================================
  {
    intent: 'AMBIENT_LOOP',
    wAnchor: 0.00,
    wMotion: 0.00,
    wIntent: 1.00,
    width: 0.90,
    deadzone: 0.10,
    maxPan: 0.10,
    smoothingTauMs: 200,
    lifetimeMs: 60000,
    priority: 1,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
  {
    intent: 'MUSIC_LAYER',
    wAnchor: 0.00,
    wMotion: 0.00,
    wIntent: 1.00,
    width: 0.85,
    deadzone: 0.15,
    maxPan: 0.08,
    smoothingTauMs: 250,
    lifetimeMs: 120000,
    priority: 0,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },

  // ========================================================================
  // FALLBACK
  // ========================================================================
  {
    intent: 'DEFAULT',
    wAnchor: 0.50,
    wMotion: 0.25,
    wIntent: 0.25,
    width: 0.45,
    deadzone: 0.05,
    maxPan: 0.75,
    smoothingTauMs: 80,
    lifetimeMs: 1000,
    priority: 5,
    intentDefaultPos: { x: 0.5, y: 0.5 },
  },
];

/**
 * Intent rules manager.
 * Uses exact match with cached partial matches for O(1) average lookup.
 */
export class IntentRulesManager {
  /** Rules indexed by intent */
  private rules = new Map<string, IntentRule>();

  /** Default rule for unknown intents */
  private defaultRule: IntentRule;

  /** Cached partial match results for O(1) subsequent lookups */
  private partialMatchCache = new Map<string, IntentRule>();

  /** Sorted partial match keys (longer patterns first for greedy matching) */
  private sortedPartialKeys: string[] = [];

  constructor(rules?: IntentRule[]) {
    // Load default rules
    for (const rule of DEFAULT_INTENT_RULES) {
      this.rules.set(rule.intent, rule);
    }

    // Override with custom rules
    if (rules) {
      for (const rule of rules) {
        this.rules.set(rule.intent, rule);
      }
    }

    // Get DEFAULT rule
    this.defaultRule = this.rules.get('DEFAULT') ?? DEFAULT_INTENT_RULES.find(r => r.intent === 'DEFAULT')!;

    // Build sorted partial keys (exclude DEFAULT, sort by length descending for greedy match)
    this.rebuildPartialKeys();
  }

  /**
   * Rebuild sorted partial keys after rule changes.
   * Sorts by length descending so longer matches are found first.
   */
  private rebuildPartialKeys(): void {
    this.sortedPartialKeys = Array.from(this.rules.keys())
      .filter(k => k !== 'DEFAULT')
      .sort((a, b) => b.length - a.length);
    this.partialMatchCache.clear();
  }

  /**
   * Get rule for intent.
   * Falls back to DEFAULT if not found.
   * Uses caching for O(1) average case after first lookup.
   */
  getRule(intent: string): IntentRule {
    // Exact match (O(1))
    const exact = this.rules.get(intent);
    if (exact) return exact;

    // Check partial match cache (O(1))
    const cached = this.partialMatchCache.get(intent);
    if (cached) return cached;

    // Try partial match using sorted keys (O(n) worst case, but cached after)
    for (const key of this.sortedPartialKeys) {
      if (intent.includes(key)) {
        const rule = this.rules.get(key)!;
        // Cache for future O(1) lookup
        this.partialMatchCache.set(intent, rule);
        return rule;
      }
    }

    // Cache the fallback too to avoid re-searching
    this.partialMatchCache.set(intent, this.defaultRule);
    return this.defaultRule;
  }

  /**
   * Add or update rule.
   */
  setRule(rule: IntentRule): void {
    this.rules.set(rule.intent, rule);
    this.rebuildPartialKeys();
  }

  /**
   * Remove rule.
   */
  removeRule(intent: string): void {
    if (intent !== 'DEFAULT') {
      this.rules.delete(intent);
      this.rebuildPartialKeys();
    }
  }

  /**
   * Get all rules.
   */
  getAllRules(): IntentRule[] {
    return Array.from(this.rules.values());
  }

  /**
   * Get rules for bus.
   */
  getRulesForBus(_bus: SpatialBus): IntentRule[] {
    // Rules don't have bus directly - this is for filtering if needed
    return this.getAllRules();
  }

  /**
   * Clear all custom rules (keep defaults).
   */
  resetToDefaults(): void {
    this.rules.clear();
    for (const rule of DEFAULT_INTENT_RULES) {
      this.rules.set(rule.intent, rule);
    }
    this.rebuildPartialKeys();
  }

  /**
   * Clear partial match cache.
   * Call when rules change externally or for memory management.
   */
  clearCache(): void {
    this.partialMatchCache.clear();
  }

  /**
   * Get cache statistics for debugging.
   */
  getCacheStats(): { cacheSize: number; rulesCount: number } {
    return {
      cacheSize: this.partialMatchCache.size,
      rulesCount: this.rules.size,
    };
  }
}

/**
 * Create intent rules manager with optional custom rules.
 */
export function createIntentRulesManager(customRules?: IntentRule[]): IntentRulesManager {
  return new IntentRulesManager(customRules);
}

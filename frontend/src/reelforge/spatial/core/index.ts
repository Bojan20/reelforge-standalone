/**
 * ReelForge Spatial System - Core Modules
 * @module reelforge/spatial/core
 */

export { MotionField, createMotionField } from './MotionField';
export {
  IntentRulesManager,
  createIntentRulesManager,
  DEFAULT_INTENT_RULES,
} from './IntentRules';
export {
  FusionEngine,
  createFusionEngine,
  getDefaultFusionEngine,
  fuseTargets,
} from './FusionEngine';
export {
  AlphaBeta2D,
  createAlphaBeta2D,
  createAlphaBeta2DFromPreset,
  ALPHA_BETA_PRESETS,
} from './AlphaBeta2D';
export type { AlphaBetaConfig } from './AlphaBeta2D';

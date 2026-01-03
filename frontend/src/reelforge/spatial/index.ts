/**
 * ReelForge Perceptual Spatial Audio System
 *
 * A production-grade spatial audio system for slot games that:
 * - Tracks UI elements and animations across DOM/Pixi/Unity
 * - Provides smooth, low-latency stereo panning
 * - Uses confidence-weighted fusion from multiple data sources
 * - Applies predictive smoothing to reduce perceived latency
 * - Supports bus-specific mixing policies
 *
 * @module reelforge/spatial
 * @version 1.0.0
 *
 * @example
 * ```typescript
 * import { createSpatialEngine, createWebAudioAdapter } from './reelforge/spatial';
 *
 * // Create engine
 * const engine = createSpatialEngine({
 *   predictiveLeadMs: 20,
 *   debugOverlay: true,
 * });
 *
 * // Set audio adapter
 * const ctx = new AudioContext();
 * const adapter = createWebAudioAdapter(ctx);
 * engine.setAudioAdapter(adapter);
 *
 * // Start engine
 * engine.start();
 *
 * // Send events
 * engine.onEvent({
 *   id: 'coin_1',
 *   name: 'COIN_FLY',
 *   intent: 'COIN_FLY_TO_BALANCE',
 *   bus: 'FX',
 *   timeMs: performance.now(),
 *   startAnchorId: 'reels_center',
 *   endAnchorId: 'balance_value',
 *   progress01: 0.5,
 *   voiceId: 'coin_sound_1',
 * });
 * ```
 */

// Types
export type {
  // Core types
  SpatialBus,
  AnchorAdapterType,
  RFSpatialEvent,
  AnchorFrame,
  AnchorHandle,
  IAnchorAdapter,
  MotionFrame,
  MotionSource,
  IntentRule,
  SpatialTarget,
  SmoothedSpatial,
  SpatialMixParams,
  BusPolicy,
  IAudioSpatialAdapter,
  SpatialEngineConfig,
  EventTracker,
  SpatialDebugFrame,
} from './types';

// Constants
export { DEFAULT_BUS_POLICIES, DEFAULT_ENGINE_CONFIG } from './types';

// Main engine
export { SpatialEngine, createSpatialEngine } from './SpatialEngine';
export type { SpatialEventCallback } from './SpatialEngine';

// Adapters
export {
  AnchorRegistry,
  createAnchorRegistry,
  BaseAnchorAdapter,
  DOMAdapter,
  createDOMAdapter,
  PixiAdapter,
  createPixiAdapter,
  UnityAdapter,
  createUnityAdapter,
} from './adapters';

// Core modules
export {
  MotionField,
  createMotionField,
  IntentRulesManager,
  createIntentRulesManager,
  DEFAULT_INTENT_RULES,
  FusionEngine,
  createFusionEngine,
  getDefaultFusionEngine,
  fuseTargets,
  AlphaBeta2D,
  createAlphaBeta2D,
  createAlphaBeta2DFromPreset,
  ALPHA_BETA_PRESETS,
} from './core';
export type { AlphaBetaConfig } from './core';

// Mixers
export {
  SpatialMixer,
  createSpatialMixer,
  BaseAudioAdapter,
  WebAudioAdapter,
  HowlerAdapter,
  NullAudioAdapter,
  createWebAudioAdapter,
  createHowlerAdapter,
  createNullAudioAdapter,
} from './mixers';
export type { SpatialMixerConfig } from './mixers';

// Utils
export * from './utils/math';

// Debug
export { DebugOverlay, createDebugOverlay } from './debug';
export type { DebugOverlayConfig } from './debug';

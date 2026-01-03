/**
 * ReelForge Perceptual Spatial Audio System
 * Core Type Definitions
 *
 * @module reelforge/spatial
 * @version 1.0.0
 */

// ============================================================================
// SPATIAL BUS DEFINITIONS
// ============================================================================

/**
 * Audio bus categories for spatial mixing policies.
 * Each bus has distinct panning behavior and priority.
 */
export type SpatialBus = 'UI' | 'REELS' | 'FX' | 'VO' | 'MUSIC' | 'AMBIENT';

/**
 * Adapter type for anchor resolution.
 * Determines which rendering system provides position data.
 */
export type AnchorAdapterType = 'DOM' | 'PIXI' | 'UNITY' | 'CUSTOM';

// ============================================================================
// EVENT PAYLOAD
// ============================================================================

/**
 * Spatial event payload from game engine.
 * This is the primary input to the spatial system.
 */
export interface RFSpatialEvent {
  /** Unique event instance ID (for tracking lifecycle) */
  readonly id: string;

  /** Event name (e.g., "COIN_FLY", "REEL_STOP") */
  readonly name: string;

  /** Intent identifier for rule matching (e.g., "COIN_FLY_TO_BALANCE") */
  readonly intent: string;

  /** Audio bus for mixing policy */
  readonly bus: SpatialBus;

  /** Event timestamp (ms) */
  readonly timeMs: number;

  // --- Anchor-driven positioning ---

  /** Primary anchor ID */
  anchorId?: string;

  /** Start anchor for motion path */
  startAnchorId?: string;

  /** End anchor for motion path */
  endAnchorId?: string;

  // --- Motion-driven positioning ---

  /** Animation progress 0..1 (if engine provides) */
  progress01?: number;

  // --- Explicit coordinates (best case) ---

  /** Normalized X position 0..1 (left to right) */
  xNorm?: number;

  /** Normalized Y position 0..1 (top to bottom) */
  yNorm?: number;

  // --- Control parameters ---

  /** Importance for mixing priority 0..1 */
  importance?: number;

  /** Tracking lifetime in ms */
  lifetimeMs?: number;

  /** Voice/sound instance ID for audio adapter */
  voiceId?: string;

  /** Optional velocity hint (norm/sec) */
  velocityHint?: { vx: number; vy: number };
}

// ============================================================================
// ANCHOR SYSTEM
// ============================================================================

/**
 * Resolved anchor frame with position, size, velocity, and confidence.
 * Output from AnchorRegistry adapters.
 */
export interface AnchorFrame {
  /** Is anchor currently visible/valid */
  readonly visible: boolean;

  /** Normalized X center position 0..1 */
  readonly xNorm: number;

  /** Normalized Y center position 0..1 */
  readonly yNorm: number;

  /** Normalized width (AABB) 0..1 */
  readonly wNorm: number;

  /** Normalized height (AABB) 0..1 */
  readonly hNorm: number;

  /** X velocity estimate (norm/sec) */
  readonly vxNormPerS: number;

  /** Y velocity estimate (norm/sec) */
  readonly vyNormPerS: number;

  /** Confidence score 0..1 */
  readonly confidence: number;

  /** Timestamp of this frame */
  readonly timestamp: number;
}

/**
 * Anchor handle for adapter-agnostic reference.
 */
export interface AnchorHandle {
  readonly id: string;
  readonly adapterType: AnchorAdapterType;
  readonly element?: unknown; // DOM Element, Pixi DisplayObject, Unity GameObject ref
}

/**
 * Anchor registry adapter interface.
 * Implementations: DOMAdapter, PixiAdapter, UnityAdapter
 */
export interface IAnchorAdapter {
  readonly type: AnchorAdapterType;

  /** Resolve anchor by ID */
  resolve(anchorId: string): AnchorHandle | null;

  /** Get current frame for anchor */
  getFrame(anchorId: string, dtSec: number, prev?: AnchorFrame): AnchorFrame | null;

  /** Invalidate cache (on resize/orientation change) */
  invalidateCache(): void;

  /** Dispose adapter */
  dispose(): void;
}

// ============================================================================
// MOTION SYSTEM
// ============================================================================

/**
 * Motion frame from MotionField.
 * Represents estimated position and velocity from various sources.
 */
export interface MotionFrame {
  /** Normalized X position 0..1 */
  readonly xNorm: number;

  /** Normalized Y position 0..1 */
  readonly yNorm: number;

  /** X velocity (norm/sec) */
  readonly vxNormPerS: number;

  /** Y velocity (norm/sec) */
  readonly vyNormPerS: number;

  /** Confidence 0..1 (higher = more reliable source) */
  readonly confidence: number;

  /** Source of this motion data */
  readonly source: MotionSource;
}

export type MotionSource =
  | 'EXPLICIT_COORDS'      // Best: game provided xNorm/yNorm
  | 'PROGRESS_INTERPOLATION' // Good: start/end + progress01
  | 'ANCHOR_TRACKING'      // OK: anchor movement over time
  | 'TRANSFORM_HARVEST'    // OK: reading animation transforms
  | 'HEURISTIC'           // Fallback: state machine guess
  | 'NONE';               // No data

// ============================================================================
// INTENT RULES
// ============================================================================

/**
 * Intent rule defines spatial behavior for event types.
 */
export interface IntentRule {
  /** Intent identifier to match */
  readonly intent: string;

  // --- Anchor fallbacks ---

  /** Default anchor if event has none */
  defaultAnchorId?: string;

  /** Fallback start anchor for motion */
  startAnchorFallback?: string;

  /** Fallback end anchor for motion */
  endAnchorFallback?: string;

  // --- Fusion weights (baseline, before confidence scaling) ---

  /** Weight for anchor data 0..1 */
  wAnchor: number;

  /** Weight for motion data 0..1 */
  wMotion: number;

  /** Weight for intent default 0..1 */
  wIntent: number;

  // --- Panning style ---

  /** Stereo spread 0..1 */
  width: number;

  /** Dead zone around center 0..0.2 typical */
  deadzone: number;

  /** Maximum pan value <= 1 */
  maxPan: number;

  /** Smoothing time constant (ms) */
  smoothingTauMs: number;

  // --- Optional tonal spatialization ---

  /** Y position to lowpass filter mapping */
  yToLPF?: { minHz: number; maxHz: number };

  /** Y position to gain mapping */
  yToGainDb?: { minDb: number; maxDb: number };

  /** Distance-based attenuation (future) */
  distanceModel?: 'linear' | 'exponential' | 'inverse';

  // --- Lifecycle ---

  /** Default tracking lifetime (ms) */
  lifetimeMs: number;

  /** Priority for bus limiting */
  priority?: number;

  // --- Intent-specific defaults ---

  /** Default position if no anchor/motion */
  intentDefaultPos?: { x: number; y: number };
}

// ============================================================================
// FUSION & SPATIAL TARGET
// ============================================================================

/**
 * Fused spatial target - output of FusionEngine.
 */
export interface SpatialTarget {
  /** Normalized X position 0..1 */
  xNorm: number;

  /** Normalized Y position 0..1 */
  yNorm: number;

  /** Stereo width 0..1 */
  width: number;

  /** Combined confidence 0..1 */
  confidence: number;

  /** Contributing sources */
  sources: MotionSource[];
}

/**
 * Smoothed spatial output - after predictive filter.
 */
export interface SmoothedSpatial {
  /** Smoothed X position */
  x: number;

  /** Smoothed Y position */
  y: number;

  /** Predicted X (with lead time) */
  predictedX: number;

  /** Predicted Y (with lead time) */
  predictedY: number;

  /** Estimated velocity X */
  vx: number;

  /** Estimated velocity Y */
  vy: number;
}

// ============================================================================
// MIXER OUTPUT
// ============================================================================

/**
 * Final spatial mix parameters for audio adapter.
 */
export interface SpatialMixParams {
  /** Stereo pan -1 (left) to +1 (right) */
  pan: number;

  /** Stereo width 0..1 */
  width: number;

  /** Lowpass filter cutoff Hz (optional) */
  lpfHz?: number;

  /** Gain adjustment dB (optional) */
  gainDb?: number;

  /** Left channel gain (equal-power) */
  gainL: number;

  /** Right channel gain (equal-power) */
  gainR: number;
}

// ============================================================================
// BUS POLICY
// ============================================================================

/**
 * Per-bus spatial mixing policy.
 */
export interface BusPolicy {
  /** Width multiplier */
  widthMul: number;

  /** Max pan multiplier */
  maxPanMul: number;

  /** Smoothing tau multiplier */
  tauMul: number;

  /** Maximum concurrent tracked events */
  maxConcurrent: number;

  /** LPF range for y-axis spatialization */
  yLpfRange?: { minHz: number; maxHz: number };
}

export const DEFAULT_BUS_POLICIES: Record<SpatialBus, BusPolicy> = {
  UI: {
    widthMul: 1.0,
    maxPanMul: 1.0,
    tauMul: 1.0,
    maxConcurrent: 8,
  },
  REELS: {
    widthMul: 0.6,
    maxPanMul: 0.85,
    tauMul: 1.15,
    maxConcurrent: 15,
    yLpfRange: { minHz: 800, maxHz: 16000 },
  },
  FX: {
    widthMul: 0.8,
    maxPanMul: 0.95,
    tauMul: 1.05,
    maxConcurrent: 12,
  },
  VO: {
    widthMul: 0.2,
    maxPanMul: 0.25,
    tauMul: 1.3,
    maxConcurrent: 2,
  },
  MUSIC: {
    widthMul: 0.7,
    maxPanMul: 0.20,
    tauMul: 1.4,
    maxConcurrent: 4,
  },
  AMBIENT: {
    widthMul: 0.9,
    maxPanMul: 0.15,
    tauMul: 2.0,
    maxConcurrent: 6,
  },
};

// ============================================================================
// AUDIO ADAPTER INTERFACE
// ============================================================================

/**
 * Audio adapter interface for backend-agnostic spatial control.
 */
export interface IAudioSpatialAdapter {
  /** Set stereo pan for voice */
  setPan(voiceId: string, pan: number): void;

  /** Set stereo width */
  setWidth(voiceId: string, width: number): void;

  /** Set lowpass filter cutoff */
  setLPF?(voiceId: string, hz: number): void;

  /** Set gain adjustment */
  setGain?(voiceId: string, db: number): void;

  /** Set left/right gains directly (equal-power) */
  setChannelGains?(voiceId: string, gainL: number, gainR: number): void;

  /** Check if voice is still active */
  isActive?(voiceId: string): boolean;
}

// ============================================================================
// ENGINE CONFIGURATION
// ============================================================================

/**
 * Spatial engine configuration.
 */
export interface SpatialEngineConfig {
  /** Update rate (Hz), default 60 */
  updateRate: number;

  /** Predictive lead time (ms), default 20 */
  predictiveLeadMs: number;

  /** Alpha for alpha-beta filter, default 0.85 */
  filterAlpha: number;

  /** Beta for alpha-beta filter, default 0.005 */
  filterBeta: number;

  /** Enable debug overlay */
  debugOverlay: boolean;

  /** Bus policies override */
  busPolicies?: Partial<Record<SpatialBus, Partial<BusPolicy>>>;

  /** Custom intent rules */
  intentRules?: IntentRule[];

  /** Viewport reference (for normalization) */
  viewport?: { width: number; height: number };
}

export const DEFAULT_ENGINE_CONFIG: SpatialEngineConfig = {
  updateRate: 60,
  predictiveLeadMs: 20,
  filterAlpha: 0.85,
  filterBeta: 0.005,
  debugOverlay: false,
};

// ============================================================================
// EVENT TRACKER STATE
// ============================================================================

/**
 * Alpha-beta smoother state.
 */
export interface SmootherState {
  x: number;
  y: number;
  vx: number;
  vy: number;
  initialized: boolean;
}

/**
 * Internal tracker state for active spatial events.
 */
export interface EventTracker {
  /** Original event */
  event: RFSpatialEvent;

  /** Intent rule */
  rule: IntentRule;

  /** Alpha-beta smoother state */
  smootherState: SmootherState;

  /** Last anchor frame */
  lastAnchor?: AnchorFrame;

  /** Last motion frame */
  lastMotion?: MotionFrame;

  /** Expiration timestamp */
  expiresAt: number;

  /** Creation timestamp */
  createdAt: number;

  /** Last update timestamp */
  lastUpdateAt: number;
}

// ============================================================================
// DEBUG / VISUALIZATION
// ============================================================================

/**
 * Debug frame for visualization overlay.
 */
export interface SpatialDebugFrame {
  readonly eventId: string;
  readonly intent: string;
  readonly bus: SpatialBus;

  /** Raw fused position */
  readonly rawX: number;
  readonly rawY: number;

  /** Smoothed position */
  readonly smoothX: number;
  readonly smoothY: number;

  /** Predicted position */
  readonly predictX: number;
  readonly predictY: number;

  /** Final pan value */
  readonly pan: number;

  /** Confidence */
  readonly confidence: number;

  /** Active sources */
  readonly sources: MotionSource[];
}

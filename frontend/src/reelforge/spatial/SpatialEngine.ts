/**
 * ReelForge Spatial System - Main Engine
 * Orchestrates all spatial audio components.
 *
 * @module reelforge/spatial
 */

import type {
  RFSpatialEvent,
  SpatialEngineConfig,
  EventTracker,
  SpatialTarget,
  SmoothedSpatial,
  SpatialDebugFrame,
  IAudioSpatialAdapter,
  SpatialBus,
  SmootherState,
} from './types';
import { DEFAULT_ENGINE_CONFIG, DEFAULT_BUS_POLICIES } from './types';
import { AnchorRegistry, createAnchorRegistry } from './adapters';
import { MotionField, createMotionField } from './core/MotionField';
import { IntentRulesManager, createIntentRulesManager } from './core/IntentRules';
import { FusionEngine, createFusionEngine } from './core/FusionEngine';
import { ALPHA_BETA_PRESETS } from './core/AlphaBeta2D';
import { SpatialMixer, createSpatialMixer } from './mixers/SpatialMixer';
import { clamp01 } from './utils/math';

// ============================================================================
// OBJECT POOL - Reduces GC pressure for high-frequency allocations
// ============================================================================

/**
 * Simple object pool for EventTracker instances.
 * Avoids allocation per onEvent call.
 */
class TrackerPool {
  private pool: EventTracker[] = [];
  private maxSize = 100;

  acquire(): EventTracker {
    if (this.pool.length > 0) {
      return this.pool.pop()!;
    }
    return this.createTracker();
  }

  release(tracker: EventTracker): void {
    if (this.pool.length < this.maxSize) {
      this.resetTracker(tracker);
      this.pool.push(tracker);
    }
  }

  private createTracker(): EventTracker {
    return {
      event: null as unknown as RFSpatialEvent,
      rule: null as unknown as import('./types').IntentRule,
      smootherState: this.createSmootherState(),
      expiresAt: 0,
      createdAt: 0,
      lastUpdateAt: 0,
    };
  }

  private createSmootherState(): SmootherState {
    return { x: 0.5, y: 0.5, vx: 0, vy: 0, initialized: false };
  }

  private resetTracker(tracker: EventTracker): void {
    tracker.smootherState.x = 0.5;
    tracker.smootherState.y = 0.5;
    tracker.smootherState.vx = 0;
    tracker.smootherState.vy = 0;
    tracker.smootherState.initialized = false;
    tracker.lastAnchor = undefined;
    tracker.lastMotion = undefined;
  }
}

// ============================================================================
// RATE LIMITER - Prevents event flooding / DoS
// ============================================================================

/**
 * Circular buffer for O(1) rate limiting.
 * Avoids O(n) shift() operations on arrays.
 */
class CircularTimestampBuffer {
  private buffer: number[];
  private head = 0;  // Next write position
  private count = 0; // Current number of valid entries
  private readonly capacity: number;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.buffer = new Array(capacity).fill(0);
  }

  /**
   * Add timestamp to buffer (overwrites oldest if full).
   */
  push(timestamp: number): void {
    this.buffer[this.head] = timestamp;
    this.head = (this.head + 1) % this.capacity;
    if (this.count < this.capacity) {
      this.count++;
    }
  }

  /**
   * Count entries newer than cutoff.
   * O(n) but n is bounded by capacity (typically 100-200).
   */
  countSince(cutoff: number): number {
    let count = 0;
    for (let i = 0; i < this.count; i++) {
      if (this.buffer[i] >= cutoff) {
        count++;
      }
    }
    return count;
  }

  /**
   * Check if buffer is at capacity with valid (non-expired) entries.
   */
  isFullWithValidEntries(cutoff: number): boolean {
    if (this.count < this.capacity) return false;
    // Check if oldest entry is still valid
    const oldestIdx = (this.head - this.count + this.capacity) % this.capacity;
    return this.buffer[oldestIdx] >= cutoff;
  }

  /**
   * Reset buffer.
   */
  clear(): void {
    this.head = 0;
    this.count = 0;
  }
}

/**
 * Sliding window rate limiter per bus.
 * Protects against event flooding.
 * Uses circular buffer for O(1) amortized operations.
 */
class EventRateLimiter {
  private windowMs: number;
  private maxEventsPerWindow: number;
  private buffers = new Map<SpatialBus, CircularTimestampBuffer>();

  constructor(windowMs = 1000, maxEventsPerWindow = 100) {
    this.windowMs = windowMs;
    this.maxEventsPerWindow = maxEventsPerWindow;
  }

  /**
   * Get or create buffer for bus.
   */
  private getBuffer(bus: SpatialBus): CircularTimestampBuffer {
    let buffer = this.buffers.get(bus);
    if (!buffer) {
      buffer = new CircularTimestampBuffer(this.maxEventsPerWindow);
      this.buffers.set(bus, buffer);
    }
    return buffer;
  }

  /**
   * Check if event is allowed (not rate limited).
   * Returns true if allowed, false if rate limited.
   * O(1) amortized complexity.
   */
  allow(bus: SpatialBus): boolean {
    const now = performance.now();
    const cutoff = now - this.windowMs;
    const buffer = this.getBuffer(bus);

    // Check if we're at limit with all valid entries
    if (buffer.isFullWithValidEntries(cutoff)) {
      return false;
    }

    // Record this event
    buffer.push(now);
    return true;
  }

  /**
   * Get current rate for bus (events per second).
   */
  getRate(bus: SpatialBus): number {
    const buffer = this.buffers.get(bus);
    if (!buffer) return 0;

    const now = performance.now();
    const cutoff = now - this.windowMs;
    const recentCount = buffer.countSince(cutoff);
    return (recentCount / this.windowMs) * 1000;
  }

  /**
   * Clear rate limiter state.
   */
  clear(): void {
    for (const buffer of this.buffers.values()) {
      buffer.clear();
    }
  }
}

/**
 * Event callback for debug/visualization.
 */
export type SpatialEventCallback = (frame: SpatialDebugFrame) => void;

/**
 * SpatialEngine is the main orchestrator for the perceptual panning system.
 *
 * It manages:
 * - Event lifecycle (creation, tracking, expiration)
 * - Anchor resolution via multi-adapter registry
 * - Motion extraction from various sources
 * - Confidence-weighted fusion
 * - Predictive smoothing
 * - Audio parameter output
 */
export class SpatialEngine {
  /** Configuration */
  private config: SpatialEngineConfig;

  /** Anchor registry (multi-adapter) */
  private anchorRegistry: AnchorRegistry;

  /** Motion field extractor */
  private motionField: MotionField;

  /** Intent rules manager */
  private intentRules: IntentRulesManager;

  /** Fusion engine */
  private fusion: FusionEngine;

  /** Spatial mixer */
  private mixer: SpatialMixer;

  /** Audio adapter */
  private audioAdapter: IAudioSpatialAdapter | null = null;

  /** Active event trackers */
  private trackers = new Map<string, EventTracker>();

  /** Events by ID (for lookup) */
  private events = new Map<string, RFSpatialEvent>();

  /** Bus event counts (for limiting) */
  private busEventCounts = new Map<SpatialBus, number>();

  /** Last update timestamp */
  private lastUpdateTime = 0;

  /** Debug callback */
  private debugCallback: SpatialEventCallback | null = null;

  /** Error callback for tracker processing errors */
  private errorCallback: ((eventId: string, error: unknown) => void) | null = null;

  /** Is engine running */
  private running = false;

  /** RAF handle */
  private rafHandle: number | null = null;

  /** Object pool for trackers (reduces GC pressure) */
  private trackerPool = new TrackerPool();

  /** Rate limiter (prevents event flooding) */
  private rateLimiter = new EventRateLimiter(1000, 100); // 100 events/sec per bus

  /** Rate limited event count (for diagnostics) */
  private rateLimitedCount = 0;

  constructor(config?: Partial<SpatialEngineConfig>) {
    // Validate and merge config
    const mergedConfig = { ...DEFAULT_ENGINE_CONFIG, ...config };
    this.validateConfig(mergedConfig);
    this.config = mergedConfig;

    // Create components
    this.anchorRegistry = createAnchorRegistry();
    this.motionField = createMotionField(this.anchorRegistry);
    this.intentRules = createIntentRulesManager(this.config.intentRules);
    this.fusion = createFusionEngine();
    this.mixer = createSpatialMixer({
      busPolicies: this.config.busPolicies,
    });

    // Initialize bus counts
    for (const bus of Object.keys(DEFAULT_BUS_POLICIES) as SpatialBus[]) {
      this.busEventCounts.set(bus, 0);
    }
  }

  /**
   * Validate engine configuration.
   * Throws if config is invalid.
   */
  private validateConfig(config: SpatialEngineConfig): void {
    // updateRate must be positive and reasonable (1-240 Hz)
    if (typeof config.updateRate !== 'number' || config.updateRate < 1 || config.updateRate > 240) {
      throw new Error(`Invalid updateRate: ${config.updateRate}. Must be between 1 and 240.`);
    }

    // predictiveLeadMs must be non-negative and reasonable (0-500ms)
    if (typeof config.predictiveLeadMs !== 'number' || config.predictiveLeadMs < 0 || config.predictiveLeadMs > 500) {
      throw new Error(`Invalid predictiveLeadMs: ${config.predictiveLeadMs}. Must be between 0 and 500.`);
    }

    // filterAlpha must be between 0 and 1
    if (typeof config.filterAlpha !== 'number' || config.filterAlpha < 0 || config.filterAlpha > 1) {
      throw new Error(`Invalid filterAlpha: ${config.filterAlpha}. Must be between 0 and 1.`);
    }

    // filterBeta must be between 0 and 1
    if (typeof config.filterBeta !== 'number' || config.filterBeta < 0 || config.filterBeta > 1) {
      throw new Error(`Invalid filterBeta: ${config.filterBeta}. Must be between 0 and 1.`);
    }

    // viewport dimensions must be positive if provided
    if (config.viewport) {
      if (typeof config.viewport.width !== 'number' || config.viewport.width <= 0) {
        throw new Error(`Invalid viewport.width: ${config.viewport.width}. Must be positive.`);
      }
      if (typeof config.viewport.height !== 'number' || config.viewport.height <= 0) {
        throw new Error(`Invalid viewport.height: ${config.viewport.height}. Must be positive.`);
      }
    }

    // intentRules validation (if provided)
    if (config.intentRules) {
      if (!Array.isArray(config.intentRules)) {
        throw new Error('intentRules must be an array');
      }
      for (const rule of config.intentRules) {
        if (typeof rule.intent !== 'string' || rule.intent.length === 0) {
          throw new Error('Each intent rule must have a non-empty intent string');
        }
      }
    }
  }

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  /**
   * Set audio adapter.
   */
  setAudioAdapter(adapter: IAudioSpatialAdapter): void {
    this.audioAdapter = adapter;
  }

  /**
   * Get anchor registry (for adapter configuration).
   */
  getAnchorRegistry(): AnchorRegistry {
    return this.anchorRegistry;
  }

  /**
   * Get intent rules manager (for rule customization).
   */
  getIntentRules(): IntentRulesManager {
    return this.intentRules;
  }

  /**
   * Get mixer (for policy customization).
   */
  getMixer(): SpatialMixer {
    return this.mixer;
  }

  /**
   * Start the update loop.
   */
  start(): void {
    if (this.running) return;
    this.running = true;
    this.lastUpdateTime = performance.now();
    this.scheduleUpdate();
  }

  /**
   * Stop the update loop.
   */
  stop(): void {
    this.running = false;
    if (this.rafHandle !== null) {
      cancelAnimationFrame(this.rafHandle);
      this.rafHandle = null;
    }
  }

  /**
   * Schedule next update.
   */
  private scheduleUpdate(): void {
    if (!this.running) return;

    this.rafHandle = requestAnimationFrame((now) => {
      this.update(now);
      this.scheduleUpdate();
    });
  }

  /**
   * Dispose engine and cleanup.
   */
  dispose(): void {
    this.stop();
    this.trackers.clear();
    this.events.clear();
    this.motionField.dispose();
    this.anchorRegistry.dispose();
    this.audioAdapter = null;
  }

  // ==========================================================================
  // EVENT HANDLING
  // ==========================================================================

  /**
   * Handle incoming spatial event.
   * Returns false if event was rate limited or invalid.
   */
  onEvent(event: RFSpatialEvent): boolean {
    // Input validation (prevents crashes from malformed events)
    if (!this.validateEvent(event)) {
      return false;
    }

    // Rate limiting check (prevents DoS / flooding)
    if (!this.rateLimiter.allow(event.bus)) {
      this.rateLimitedCount++;
      return false;
    }

    const rule = this.intentRules.getRule(event.intent);
    const now = performance.now();

    // Check bus limit
    let currentCount = this.busEventCounts.get(event.bus) ?? 0;
    if (!this.mixer.canAcceptEvent(event.bus, currentCount)) {
      // Find lowest priority event on this bus and evict
      this.evictLowestPriority(event.bus);
      // Re-read count after eviction
      currentCount = this.busEventCounts.get(event.bus) ?? 0;
    }

    // Check if tracker already exists
    let tracker = this.trackers.get(event.id);

    if (tracker) {
      // Update existing tracker
      tracker.event = event;
      tracker.rule = rule;
      tracker.expiresAt = now + (event.lifetimeMs ?? rule.lifetimeMs);
      tracker.lastUpdateAt = now;
    } else {
      // Acquire from pool (reduces GC pressure)
      tracker = this.trackerPool.acquire();
      tracker.event = event;
      tracker.rule = rule;
      tracker.expiresAt = now + (event.lifetimeMs ?? rule.lifetimeMs);
      tracker.createdAt = now;
      tracker.lastUpdateAt = now;

      this.trackers.set(event.id, tracker);
      this.busEventCounts.set(event.bus, currentCount + 1);
    }

    this.events.set(event.id, event);
    return true;
  }

  /**
   * Remove event by ID.
   */
  removeEvent(eventId: string): void {
    const tracker = this.trackers.get(eventId);
    if (tracker) {
      const count = this.busEventCounts.get(tracker.event.bus) ?? 0;
      this.busEventCounts.set(tracker.event.bus, Math.max(0, count - 1));

      // Return to pool for reuse
      this.trackerPool.release(tracker);
    }

    this.trackers.delete(eventId);
    this.events.delete(eventId);
    this.motionField.clearEvent(eventId);
  }

  /**
   * Evict lowest priority event from bus.
   */
  private evictLowestPriority(bus: SpatialBus): void {
    let lowestPriority = Infinity;
    let lowestId: string | null = null;

    for (const [id, tracker] of this.trackers) {
      if (tracker.event.bus !== bus) continue;
      const priority = tracker.rule.priority ?? 5;
      if (priority < lowestPriority) {
        lowestPriority = priority;
        lowestId = id;
      }
    }

    if (lowestId) {
      this.removeEvent(lowestId);
    }
  }

  /**
   * Validate incoming event structure.
   * Returns true if event is valid and safe to process.
   */
  private validateEvent(event: RFSpatialEvent): boolean {
    // Check required fields exist
    if (!event || typeof event !== 'object') {
      return false;
    }

    // Validate id (required, non-empty string)
    if (typeof event.id !== 'string' || event.id.length === 0 || event.id.length > 256) {
      return false;
    }

    // Validate name (required, non-empty string)
    if (typeof event.name !== 'string' || event.name.length === 0 || event.name.length > 128) {
      return false;
    }

    // Validate intent (required, non-empty string)
    if (typeof event.intent !== 'string' || event.intent.length === 0 || event.intent.length > 128) {
      return false;
    }

    // Validate bus (required, must be valid SpatialBus)
    const validBuses = ['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT'];
    if (!validBuses.includes(event.bus)) {
      return false;
    }

    // Validate timeMs (required, finite number)
    if (typeof event.timeMs !== 'number' || !Number.isFinite(event.timeMs)) {
      return false;
    }

    // Validate optional numeric fields if present
    if (event.xNorm !== undefined && (typeof event.xNorm !== 'number' || !Number.isFinite(event.xNorm))) {
      return false;
    }
    if (event.yNorm !== undefined && (typeof event.yNorm !== 'number' || !Number.isFinite(event.yNorm))) {
      return false;
    }
    if (event.progress01 !== undefined && (typeof event.progress01 !== 'number' || !Number.isFinite(event.progress01))) {
      return false;
    }
    if (event.importance !== undefined && (typeof event.importance !== 'number' || !Number.isFinite(event.importance))) {
      return false;
    }
    if (event.lifetimeMs !== undefined && (typeof event.lifetimeMs !== 'number' || !Number.isFinite(event.lifetimeMs) || event.lifetimeMs < 0)) {
      return false;
    }

    // Validate optional string fields if present
    if (event.anchorId !== undefined && (typeof event.anchorId !== 'string' || event.anchorId.length > 256)) {
      return false;
    }
    if (event.startAnchorId !== undefined && (typeof event.startAnchorId !== 'string' || event.startAnchorId.length > 256)) {
      return false;
    }
    if (event.endAnchorId !== undefined && (typeof event.endAnchorId !== 'string' || event.endAnchorId.length > 256)) {
      return false;
    }
    if (event.voiceId !== undefined && (typeof event.voiceId !== 'string' || event.voiceId.length > 256)) {
      return false;
    }

    return true;
  }

  // ==========================================================================
  // UPDATE LOOP
  // ==========================================================================

  /**
   * Main update loop.
   * Protected by error boundaries to ensure single tracker failure
   * doesn't crash entire spatial system.
   */
  update(nowMs: number): void {
    const dtMs = nowMs - this.lastUpdateTime;
    const dtSec = dtMs / 1000;
    this.lastUpdateTime = nowMs;

    // Guard against large dt (tab was inactive)
    if (dtSec > 0.5) {
      return; // Skip this frame
    }

    // Process each tracker with error boundary
    for (const [eventId, tracker] of this.trackers) {
      // Check expiration
      if (nowMs > tracker.expiresAt) {
        this.removeEvent(eventId);
        continue;
      }

      try {
        this.processTracker(tracker, dtSec, nowMs);
      } catch (error) {
        // Error boundary: Log and remove problematic tracker
        // Prevents single bad event from crashing entire spatial system
        this.handleTrackerError(eventId, error);
      }
    }
  }

  /**
   * Handle error during tracker processing.
   * Removes problematic tracker and logs error (production-safe).
   */
  private handleTrackerError(eventId: string, error: unknown): void {
    // Remove tracker to prevent repeated errors
    this.removeEvent(eventId);

    // Optionally emit to error callback if configured
    // This is the preferred way to handle errors - user can log as needed
    if (this.errorCallback) {
      this.errorCallback(eventId, error);
    }
  }

  /**
   * Process a single event tracker.
   */
  private processTracker(tracker: EventTracker, dtSec: number, nowMs: number): void {
    const { event, rule } = tracker;

    // 1. Extract motion
    const motion = this.motionField.extract(event, dtSec);

    // 2. Get anchor frame
    const anchorId = event.anchorId ?? rule.defaultAnchorId;
    const anchor = anchorId ? this.anchorRegistry.getFrame(anchorId, dtSec) : null;
    tracker.lastAnchor = anchor ?? undefined;
    tracker.lastMotion = motion;

    // 3. Fuse targets
    const target = this.fusion.fuse({
      anchor,
      motion,
      rule,
      event,
    });

    // 4. Smooth with alpha-beta filter
    const smoothed = this.applySmoother(tracker, target, dtSec);

    // 5. Mix to audio params
    const mixParams = this.mixer.mix(target, smoothed, event.bus, rule);

    // 6. Apply to audio
    const voiceId = event.voiceId ?? event.id;
    if (this.audioAdapter) {
      this.audioAdapter.setPan(voiceId, mixParams.pan);
      this.audioAdapter.setWidth(voiceId, mixParams.width);

      if (mixParams.lpfHz !== undefined && this.audioAdapter.setLPF) {
        this.audioAdapter.setLPF(voiceId, mixParams.lpfHz);
      }

      if (mixParams.gainDb !== undefined && this.audioAdapter.setGain) {
        this.audioAdapter.setGain(voiceId, mixParams.gainDb);
      }

      if (this.audioAdapter.setChannelGains) {
        this.audioAdapter.setChannelGains(voiceId, mixParams.gainL, mixParams.gainR);
      }
    }

    // 7. Debug callback
    if (this.debugCallback) {
      const debugFrame: SpatialDebugFrame = {
        eventId: event.id,
        intent: event.intent,
        bus: event.bus,
        rawX: target.xNorm,
        rawY: target.yNorm,
        smoothX: smoothed.x,
        smoothY: smoothed.y,
        predictX: smoothed.predictedX,
        predictY: smoothed.predictedY,
        pan: mixParams.pan,
        confidence: target.confidence,
        sources: target.sources,
      };
      this.debugCallback(debugFrame);
    }

    tracker.lastUpdateAt = nowMs;
  }

  /**
   * Apply alpha-beta smoother to target.
   */
  private applySmoother(
    tracker: EventTracker,
    target: SpatialTarget,
    dtSec: number
  ): SmoothedSpatial {
    const state = tracker.smootherState;
    const { rule, event } = tracker;

    // Get filter config based on bus
    const preset = ALPHA_BETA_PRESETS[event.bus] ?? ALPHA_BETA_PRESETS.DEFAULT;
    const adjustedTau = this.mixer.getAdjustedSmoothingTau(rule.smoothingTauMs, event.bus);

    // Calculate effective alpha (more responsive for shorter tau)
    // STABILITY FIX: Clamp alpha to [0.15, 0.95] range
    // - Min 0.15 ensures some smoothing even with very short tau (prevents jitter)
    // - Max 0.95 ensures some responsiveness even with very long tau
    const rawAlpha = 1 - Math.exp(-16.67 / Math.max(adjustedTau, 1));
    const alpha = clamp01(Math.max(0.15, Math.min(0.95, rawAlpha)));
    const beta = preset.beta;

    // Initialize if needed
    if (!state.initialized) {
      state.x = target.xNorm;
      state.y = target.yNorm;
      state.vx = 0;
      state.vy = 0;
      state.initialized = true;

      return {
        x: state.x,
        y: state.y,
        predictedX: state.x,
        predictedY: state.y,
        vx: 0,
        vy: 0,
      };
    }

    // Predict
    let predX = state.x + state.vx * dtSec;
    let predY = state.y + state.vy * dtSec;

    // Residual
    const residualX = target.xNorm - predX;
    const residualY = target.yNorm - predY;

    // Apply deadzone
    const deadzone = rule.deadzone;
    const effectiveRx = Math.abs(residualX) < deadzone ? 0 : residualX;
    const effectiveRy = Math.abs(residualY) < deadzone ? 0 : residualY;

    // Correct position
    state.x = clamp01(predX + alpha * effectiveRx);
    state.y = clamp01(predY + alpha * effectiveRy);

    // Correct velocity
    // STABILITY FIX: Use minimum dtSec to prevent velocity explosion on lag spikes
    const safeDt = Math.max(dtSec, 0.001); // Minimum 1ms
    state.vx = (state.vx + (beta * effectiveRx) / safeDt) * 0.96;
    state.vy = (state.vy + (beta * effectiveRy) / safeDt) * 0.96;

    // Clamp velocity
    const maxV = 5;
    state.vx = Math.max(-maxV, Math.min(maxV, state.vx));
    state.vy = Math.max(-maxV, Math.min(maxV, state.vy));

    // Predict ahead
    const leadSec = this.config.predictiveLeadMs / 1000;
    const predictedX = clamp01(state.x + state.vx * leadSec);
    const predictedY = clamp01(state.y + state.vy * leadSec);

    return {
      x: state.x,
      y: state.y,
      predictedX,
      predictedY,
      vx: state.vx,
      vy: state.vy,
    };
  }

  // ==========================================================================
  // DEBUG & VISUALIZATION
  // ==========================================================================

  /**
   * Set debug callback for visualization.
   */
  setDebugCallback(callback: SpatialEventCallback | null): void {
    this.debugCallback = callback;
  }

  /**
   * Set error callback for tracker processing errors.
   * Called when a tracker throws during update processing.
   * Useful for error logging/reporting in production.
   */
  setErrorCallback(callback: ((eventId: string, error: unknown) => void) | null): void {
    this.errorCallback = callback;
  }

  /**
   * Get all active event IDs.
   */
  getActiveEventIds(): string[] {
    return Array.from(this.trackers.keys());
  }

  /**
   * Get tracker for event.
   */
  getTracker(eventId: string): EventTracker | undefined {
    return this.trackers.get(eventId);
  }

  /**
   * Get event count per bus.
   */
  getEventCountByBus(): Map<SpatialBus, number> {
    return new Map(this.busEventCounts);
  }

  /**
   * Check if engine is running.
   */
  isRunning(): boolean {
    return this.running;
  }

  /**
   * Get rate limited event count (diagnostics).
   */
  getRateLimitedCount(): number {
    return this.rateLimitedCount;
  }

  /**
   * Get current event rate per bus (events/sec).
   */
  getEventRate(bus: SpatialBus): number {
    return this.rateLimiter.getRate(bus);
  }

  /**
   * Reset rate limiter (e.g., after pause).
   */
  resetRateLimiter(): void {
    this.rateLimiter.clear();
    this.rateLimitedCount = 0;
  }

  // ==========================================================================
  // ORIENTATION / RESIZE HANDLING
  // ==========================================================================

  /**
   * Handle orientation/resize change.
   * Should be called when viewport changes.
   */
  onViewportChange(): void {
    this.anchorRegistry.invalidateCache();

    // Optionally crossfade all trackers
    for (const tracker of this.trackers.values()) {
      // Reduce confidence during transition
      tracker.smootherState.vx *= 0.5;
      tracker.smootherState.vy *= 0.5;
    }
  }
}

// ============================================================================
// FACTORY
// ============================================================================

/**
 * Create spatial engine with optional config.
 */
export function createSpatialEngine(
  config?: Partial<SpatialEngineConfig>
): SpatialEngine {
  return new SpatialEngine(config);
}

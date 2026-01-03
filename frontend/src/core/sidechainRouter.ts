/**
 * Sidechain Routing System
 *
 * Professional sidechain architecture for slot audio:
 * - Multiple sidechain sources per destination
 * - Envelope follower with attack/release
 * - Frequency-selective sidechaining (filtered key)
 * - Ducking automation curves
 * - Priority-based routing (wins > music > ambience)
 * - Visual feedback for gain reduction
 */

// ============ TYPES ============

export type SidechainMode = 'peak' | 'rms' | 'envelope';
export type FilterType = 'none' | 'lowpass' | 'highpass' | 'bandpass';
export type DuckingCurve = 'linear' | 'exponential' | 'logarithmic' | 'scurve';

export interface SidechainSource {
  /** Source bus ID */
  sourceId: string;
  /** Source bus name */
  sourceName: string;
  /** Is enabled */
  enabled: boolean;
  /** Priority (higher = more influence) */
  priority: number;
  /** Gain before envelope detection (dB) */
  preGain: number;
}

export interface SidechainFilter {
  /** Filter type */
  type: FilterType;
  /** Cutoff frequency (Hz) */
  frequency: number;
  /** Q factor */
  q: number;
  /** Filter enabled */
  enabled: boolean;
}

export interface EnvelopeFollower {
  /** Detection mode */
  mode: SidechainMode;
  /** Attack time (ms) */
  attackMs: number;
  /** Release time (ms) */
  releaseMs: number;
  /** Hold time before release (ms) */
  holdMs: number;
  /** RMS window size (ms) - only for RMS mode */
  rmsWindowMs: number;
}

export interface DuckingConfig {
  /** Threshold to start ducking (dB) */
  threshold: number;
  /** Maximum gain reduction (dB) */
  range: number;
  /** Ducking curve shape */
  curve: DuckingCurve;
  /** Ratio for compression-style ducking */
  ratio: number;
  /** Depth (0-1, how much of range to apply) */
  depth: number;
}

export interface SidechainRoute {
  /** Unique route ID */
  id: string;
  /** Route name */
  name: string;
  /** Target bus to duck */
  targetBusId: string;
  /** Target bus name */
  targetBusName: string;
  /** Sidechain sources */
  sources: SidechainSource[];
  /** Key filter (frequency-selective) */
  filter: SidechainFilter;
  /** Envelope follower settings */
  envelope: EnvelopeFollower;
  /** Ducking configuration */
  ducking: DuckingConfig;
  /** Mix (0-1, dry/wet) */
  mix: number;
  /** Is route enabled */
  enabled: boolean;
  /** Is route soloed */
  solo: boolean;
  /** Current gain reduction (dB) - for metering */
  currentGR: number;
}

export interface SidechainRouterConfig {
  /** Global enable */
  enabled: boolean;
  /** Sample rate */
  sampleRate: number;
  /** Block size for processing */
  blockSize: number;
  /** Look-ahead (ms) */
  lookaheadMs: number;
  /** Maximum routes */
  maxRoutes: number;
  /** GR meter update rate (Hz) */
  meterUpdateRate: number;
}

export interface SidechainMeter {
  /** Route ID */
  routeId: string;
  /** Current input level (dB) */
  inputLevel: number;
  /** Current envelope value (0-1) */
  envelopeValue: number;
  /** Current gain reduction (dB) */
  gainReduction: number;
  /** Peak GR in last second */
  peakGR: number;
  /** Timestamp */
  timestamp: number;
}

// ============ DEFAULT CONFIG ============

const DEFAULT_CONFIG: SidechainRouterConfig = {
  enabled: true,
  sampleRate: 48000,
  blockSize: 128,
  lookaheadMs: 5,
  maxRoutes: 16,
  meterUpdateRate: 30,
};

const DEFAULT_ENVELOPE: EnvelopeFollower = {
  mode: 'peak',
  attackMs: 5,
  releaseMs: 100,
  holdMs: 0,
  rmsWindowMs: 50,
};

const DEFAULT_FILTER: SidechainFilter = {
  type: 'none',
  frequency: 1000,
  q: 0.707,
  enabled: false,
};

const DEFAULT_DUCKING: DuckingConfig = {
  threshold: -20,
  range: -12,
  curve: 'exponential',
  ratio: 4,
  depth: 1,
};

// ============ SIDECHAIN ROUTER ============

export class SidechainRouter {
  private config: SidechainRouterConfig;
  private routes: Map<string, SidechainRoute> = new Map();
  private meters: Map<string, SidechainMeter> = new Map();
  private envelopeStates: Map<string, EnvelopeState> = new Map();
  private meterCallbacks: Set<(meters: SidechainMeter[]) => void> = new Set();
  private meterInterval: number | null = null;

  constructor(config: Partial<SidechainRouterConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  // ============ ROUTE MANAGEMENT ============

  /**
   * Create a new sidechain route
   */
  createRoute(
    targetBusId: string,
    targetBusName: string,
    sources: Array<{ id: string; name: string; priority?: number }>,
    options: Partial<{
      name: string;
      filter: Partial<SidechainFilter>;
      envelope: Partial<EnvelopeFollower>;
      ducking: Partial<DuckingConfig>;
      mix: number;
    }> = {}
  ): SidechainRoute {
    const id = this.generateId();

    const route: SidechainRoute = {
      id,
      name: options.name || `${sources[0]?.name || 'Source'} → ${targetBusName}`,
      targetBusId,
      targetBusName,
      sources: sources.map((s, i) => ({
        sourceId: s.id,
        sourceName: s.name,
        enabled: true,
        priority: s.priority ?? (10 - i),
        preGain: 0,
      })),
      filter: { ...DEFAULT_FILTER, ...options.filter },
      envelope: { ...DEFAULT_ENVELOPE, ...options.envelope },
      ducking: { ...DEFAULT_DUCKING, ...options.ducking },
      mix: options.mix ?? 1,
      enabled: true,
      solo: false,
      currentGR: 0,
    };

    this.routes.set(id, route);
    this.envelopeStates.set(id, this.createEnvelopeState());
    this.initMeter(id);

    return route;
  }

  /**
   * Get route by ID
   */
  getRoute(id: string): SidechainRoute | undefined {
    return this.routes.get(id);
  }

  /**
   * Get all routes
   */
  getAllRoutes(): SidechainRoute[] {
    return Array.from(this.routes.values());
  }

  /**
   * Get routes for a target bus
   */
  getRoutesForTarget(targetBusId: string): SidechainRoute[] {
    return this.getAllRoutes().filter(r => r.targetBusId === targetBusId);
  }

  /**
   * Get routes from a source bus
   */
  getRoutesFromSource(sourceBusId: string): SidechainRoute[] {
    return this.getAllRoutes().filter(r =>
      r.sources.some(s => s.sourceId === sourceBusId)
    );
  }

  /**
   * Update route
   */
  updateRoute(id: string, updates: Partial<SidechainRoute>): boolean {
    const route = this.routes.get(id);
    if (!route) return false;

    Object.assign(route, updates);
    return true;
  }

  /**
   * Delete route
   */
  deleteRoute(id: string): boolean {
    this.envelopeStates.delete(id);
    this.meters.delete(id);
    return this.routes.delete(id);
  }

  /**
   * Enable/disable route
   */
  setRouteEnabled(id: string, enabled: boolean): void {
    const route = this.routes.get(id);
    if (route) {
      route.enabled = enabled;
      if (!enabled) {
        route.currentGR = 0;
      }
    }
  }

  /**
   * Solo route
   */
  setRouteSolo(id: string, solo: boolean): void {
    const route = this.routes.get(id);
    if (route) {
      route.solo = solo;
    }
  }

  // ============ SOURCE MANAGEMENT ============

  /**
   * Add source to route
   */
  addSource(routeId: string, sourceId: string, sourceName: string, priority?: number): boolean {
    const route = this.routes.get(routeId);
    if (!route) return false;

    const existingIndex = route.sources.findIndex(s => s.sourceId === sourceId);
    if (existingIndex >= 0) return false;

    route.sources.push({
      sourceId,
      sourceName,
      enabled: true,
      priority: priority ?? route.sources.length,
      preGain: 0,
    });

    return true;
  }

  /**
   * Remove source from route
   */
  removeSource(routeId: string, sourceId: string): boolean {
    const route = this.routes.get(routeId);
    if (!route) return false;

    const index = route.sources.findIndex(s => s.sourceId === sourceId);
    if (index < 0) return false;

    route.sources.splice(index, 1);
    return true;
  }

  /**
   * Set source enabled
   */
  setSourceEnabled(routeId: string, sourceId: string, enabled: boolean): void {
    const route = this.routes.get(routeId);
    if (!route) return;

    const source = route.sources.find(s => s.sourceId === sourceId);
    if (source) {
      source.enabled = enabled;
    }
  }

  /**
   * Set source pre-gain
   */
  setSourcePreGain(routeId: string, sourceId: string, gainDb: number): void {
    const route = this.routes.get(routeId);
    if (!route) return;

    const source = route.sources.find(s => s.sourceId === sourceId);
    if (source) {
      source.preGain = Math.max(-24, Math.min(24, gainDb));
    }
  }

  // ============ ENVELOPE & DUCKING ============

  /**
   * Update envelope settings
   */
  setEnvelope(routeId: string, envelope: Partial<EnvelopeFollower>): void {
    const route = this.routes.get(routeId);
    if (route) {
      Object.assign(route.envelope, envelope);
    }
  }

  /**
   * Update ducking settings
   */
  setDucking(routeId: string, ducking: Partial<DuckingConfig>): void {
    const route = this.routes.get(routeId);
    if (route) {
      Object.assign(route.ducking, ducking);
    }
  }

  /**
   * Update filter settings
   */
  setFilter(routeId: string, filter: Partial<SidechainFilter>): void {
    const route = this.routes.get(routeId);
    if (route) {
      Object.assign(route.filter, filter);
    }
  }

  /**
   * Set mix amount
   */
  setMix(routeId: string, mix: number): void {
    const route = this.routes.get(routeId);
    if (route) {
      route.mix = Math.max(0, Math.min(1, mix));
    }
  }

  // ============ PROCESSING ============

  /**
   * Process a block of audio
   * Returns gain reduction amount for the target bus
   */
  processBlock(routeId: string, sidechainInput: Float32Array): number {
    const route = this.routes.get(routeId);
    if (!route || !route.enabled) return 0;

    const state = this.envelopeStates.get(routeId);
    if (!state) return 0;

    // Apply key filter if enabled
    let filteredInput = sidechainInput;
    if (route.filter.enabled && route.filter.type !== 'none') {
      filteredInput = this.applyFilter(sidechainInput, route.filter, state);
    }

    // Detect envelope
    const envelope = this.detectEnvelope(filteredInput, route.envelope, state);

    // Calculate gain reduction
    const grDb = this.calculateGainReduction(envelope, route.ducking);

    // Apply mix
    const finalGR = grDb * route.mix;

    // Update route's current GR for metering
    route.currentGR = finalGR;

    // Update meter
    this.updateMeter(routeId, filteredInput, envelope, finalGR);

    return finalGR;
  }

  /**
   * Get gain reduction for multiple sources (priority-weighted)
   */
  processCombinedSources(
    routeId: string,
    sourceInputs: Map<string, Float32Array>
  ): number {
    const route = this.routes.get(routeId);
    if (!route || !route.enabled) return 0;

    // Combine sources based on priority
    const combinedSignal = this.combineSourceSignals(route, sourceInputs);

    return this.processBlock(routeId, combinedSignal);
  }

  /**
   * Combine source signals with priority weighting
   */
  private combineSourceSignals(
    route: SidechainRoute,
    sourceInputs: Map<string, Float32Array>
  ): Float32Array {
    const blockSize = this.config.blockSize;
    const combined = new Float32Array(blockSize);

    // Calculate total priority weight
    const enabledSources = route.sources.filter(s => s.enabled && sourceInputs.has(s.sourceId));
    const totalPriority = enabledSources.reduce((sum, s) => sum + s.priority, 0);

    if (totalPriority === 0) return combined;

    for (const source of enabledSources) {
      const input = sourceInputs.get(source.sourceId);
      if (!input) continue;

      const weight = source.priority / totalPriority;
      const preGainLinear = Math.pow(10, source.preGain / 20);

      for (let i = 0; i < Math.min(blockSize, input.length); i++) {
        combined[i] += input[i] * preGainLinear * weight;
      }
    }

    return combined;
  }

  /**
   * Apply filter to sidechain signal
   */
  private applyFilter(
    input: Float32Array,
    filter: SidechainFilter,
    state: EnvelopeState
  ): Float32Array {
    const output = new Float32Array(input.length);

    // Simple biquad filter implementation
    const { b0, b1, b2, a1, a2 } = this.calculateFilterCoeffs(filter);

    for (let i = 0; i < input.length; i++) {
      const x0 = input[i];
      const y0 = b0 * x0 + b1 * state.filterX1 + b2 * state.filterX2
                - a1 * state.filterY1 - a2 * state.filterY2;

      state.filterX2 = state.filterX1;
      state.filterX1 = x0;
      state.filterY2 = state.filterY1;
      state.filterY1 = y0;

      output[i] = y0;
    }

    return output;
  }

  /**
   * Calculate biquad filter coefficients
   */
  private calculateFilterCoeffs(filter: SidechainFilter): {
    b0: number; b1: number; b2: number; a1: number; a2: number;
  } {
    const omega = 2 * Math.PI * filter.frequency / this.config.sampleRate;
    const sinOmega = Math.sin(omega);
    const cosOmega = Math.cos(omega);
    const alpha = sinOmega / (2 * filter.q);

    let b0 = 0, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;

    switch (filter.type) {
      case 'lowpass':
        b0 = (1 - cosOmega) / 2;
        b1 = 1 - cosOmega;
        b2 = (1 - cosOmega) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'highpass':
        b0 = (1 + cosOmega) / 2;
        b1 = -(1 + cosOmega);
        b2 = (1 + cosOmega) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      case 'bandpass':
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha;
        break;

      default:
        // Passthrough
        return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
    }

    // Normalize
    return {
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    };
  }

  /**
   * Detect envelope from input signal
   */
  private detectEnvelope(
    input: Float32Array,
    envelope: EnvelopeFollower,
    state: EnvelopeState
  ): number {
    const attackCoeff = Math.exp(-1 / (this.config.sampleRate * envelope.attackMs / 1000));
    const releaseCoeff = Math.exp(-1 / (this.config.sampleRate * envelope.releaseMs / 1000));

    let currentEnvelope = state.envelope;

    for (let i = 0; i < input.length; i++) {
      let inputLevel: number;

      switch (envelope.mode) {
        case 'peak':
          inputLevel = Math.abs(input[i]);
          break;

        case 'rms':
          // Add to RMS buffer
          state.rmsBuffer[state.rmsIndex] = input[i] * input[i];
          state.rmsIndex = (state.rmsIndex + 1) % state.rmsBuffer.length;

          // Calculate RMS
          const sum = state.rmsBuffer.reduce((a, b) => a + b, 0);
          inputLevel = Math.sqrt(sum / state.rmsBuffer.length);
          break;

        case 'envelope':
        default:
          inputLevel = Math.abs(input[i]);
          break;
      }

      // Attack/release
      if (inputLevel > currentEnvelope) {
        currentEnvelope = attackCoeff * currentEnvelope + (1 - attackCoeff) * inputLevel;
        state.holdCounter = Math.floor(this.config.sampleRate * envelope.holdMs / 1000);
      } else {
        if (state.holdCounter > 0) {
          state.holdCounter--;
        } else {
          currentEnvelope = releaseCoeff * currentEnvelope + (1 - releaseCoeff) * inputLevel;
        }
      }
    }

    state.envelope = currentEnvelope;
    return currentEnvelope;
  }

  /**
   * Calculate gain reduction based on envelope and ducking config
   */
  private calculateGainReduction(envelope: number, ducking: DuckingConfig): number {
    // Convert envelope to dB
    const envelopeDb = 20 * Math.log10(Math.max(envelope, 1e-10));

    // Below threshold? No reduction
    if (envelopeDb <= ducking.threshold) {
      return 0;
    }

    // Calculate how much over threshold
    const overThreshold = envelopeDb - ducking.threshold;

    // Calculate raw reduction based on curve
    let reduction: number;
    const maxReduction = Math.abs(ducking.range);

    switch (ducking.curve) {
      case 'linear':
        reduction = Math.min(overThreshold * (ducking.ratio - 1) / ducking.ratio, maxReduction);
        break;

      case 'exponential':
        reduction = maxReduction * (1 - Math.exp(-overThreshold / 10));
        break;

      case 'logarithmic':
        reduction = maxReduction * Math.log10(1 + overThreshold) / Math.log10(11);
        break;

      case 'scurve':
        // S-curve using tanh
        const normalized = overThreshold / 20; // Normalize to ~0-1 range
        reduction = maxReduction * Math.tanh(normalized * 2);
        break;

      default:
        reduction = 0;
    }

    // Apply depth
    reduction *= ducking.depth;

    // Return as negative dB
    return -reduction;
  }

  // ============ METERING ============

  /**
   * Initialize meter for route
   */
  private initMeter(routeId: string): void {
    this.meters.set(routeId, {
      routeId,
      inputLevel: -Infinity,
      envelopeValue: 0,
      gainReduction: 0,
      peakGR: 0,
      timestamp: Date.now(),
    });
  }

  /**
   * Update meter
   */
  private updateMeter(
    routeId: string,
    input: Float32Array,
    envelope: number,
    grDb: number
  ): void {
    const meter = this.meters.get(routeId);
    if (!meter) return;

    // Calculate input level
    let peak = 0;
    for (let i = 0; i < input.length; i++) {
      peak = Math.max(peak, Math.abs(input[i]));
    }

    meter.inputLevel = 20 * Math.log10(Math.max(peak, 1e-10));
    meter.envelopeValue = envelope;
    meter.gainReduction = grDb;
    meter.peakGR = Math.min(meter.peakGR, grDb);
    meter.timestamp = Date.now();
  }

  /**
   * Get meter for route
   */
  getMeter(routeId: string): SidechainMeter | undefined {
    return this.meters.get(routeId);
  }

  /**
   * Get all meters
   */
  getAllMeters(): SidechainMeter[] {
    return Array.from(this.meters.values());
  }

  /**
   * Subscribe to meter updates
   */
  onMeterUpdate(callback: (meters: SidechainMeter[]) => void): () => void {
    this.meterCallbacks.add(callback);

    // Start meter interval if not running
    if (this.meterInterval === null) {
      this.meterInterval = window.setInterval(() => {
        const meters = this.getAllMeters();
        this.meterCallbacks.forEach(cb => cb(meters));
      }, 1000 / this.config.meterUpdateRate);
    }

    return () => {
      this.meterCallbacks.delete(callback);
      if (this.meterCallbacks.size === 0 && this.meterInterval !== null) {
        clearInterval(this.meterInterval);
        this.meterInterval = null;
      }
    };
  }

  /**
   * Reset peak GR for route
   */
  resetPeakGR(routeId: string): void {
    const meter = this.meters.get(routeId);
    if (meter) {
      meter.peakGR = 0;
    }
  }

  /**
   * Reset all peak GR
   */
  resetAllPeakGR(): void {
    this.meters.forEach(m => m.peakGR = 0);
  }

  // ============ ENVELOPE STATE ============

  private createEnvelopeState(): EnvelopeState {
    const rmsWindowSamples = Math.floor(
      this.config.sampleRate * DEFAULT_ENVELOPE.rmsWindowMs / 1000
    );

    return {
      envelope: 0,
      holdCounter: 0,
      rmsBuffer: new Float32Array(rmsWindowSamples),
      rmsIndex: 0,
      filterX1: 0,
      filterX2: 0,
      filterY1: 0,
      filterY2: 0,
    };
  }

  // ============ UTILITIES ============

  private generateId(): string {
    return `sc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  // ============ CONFIGURATION ============

  setConfig(config: Partial<SidechainRouterConfig>): void {
    this.config = { ...this.config, ...config };
  }

  getConfig(): SidechainRouterConfig {
    return { ...this.config };
  }

  // ============ DISPOSAL ============

  dispose(): void {
    if (this.meterInterval !== null) {
      clearInterval(this.meterInterval);
      this.meterInterval = null;
    }
    this.routes.clear();
    this.meters.clear();
    this.envelopeStates.clear();
    this.meterCallbacks.clear();
  }
}

// ============ INTERNAL TYPES ============

interface EnvelopeState {
  envelope: number;
  holdCounter: number;
  rmsBuffer: Float32Array;
  rmsIndex: number;
  filterX1: number;
  filterX2: number;
  filterY1: number;
  filterY2: number;
}

// ============ SLOT SIDECHAIN PRESETS ============

export const SLOT_SIDECHAIN_PRESETS = {
  /** Duck music when win sounds play */
  win_ducks_music: {
    name: 'Win → Music Ducking',
    envelope: {
      mode: 'peak' as SidechainMode,
      attackMs: 2,
      releaseMs: 200,
      holdMs: 50,
    },
    ducking: {
      threshold: -24,
      range: -10,
      curve: 'exponential' as DuckingCurve,
      ratio: 6,
      depth: 0.8,
    },
    filter: {
      type: 'none' as FilterType,
      enabled: false,
    },
  },

  /** Duck ambience when any dialog plays */
  dialog_priority: {
    name: 'Dialog Priority',
    envelope: {
      mode: 'rms' as SidechainMode,
      attackMs: 10,
      releaseMs: 300,
      holdMs: 100,
    },
    ducking: {
      threshold: -30,
      range: -18,
      curve: 'scurve' as DuckingCurve,
      ratio: 8,
      depth: 1,
    },
    filter: {
      type: 'bandpass' as FilterType,
      frequency: 2000,
      q: 1,
      enabled: true,
    },
  },

  /** Gentle ducking for spin sounds */
  spin_subtle: {
    name: 'Spin Subtle Duck',
    envelope: {
      mode: 'peak' as SidechainMode,
      attackMs: 5,
      releaseMs: 150,
      holdMs: 0,
    },
    ducking: {
      threshold: -18,
      range: -4,
      curve: 'linear' as DuckingCurve,
      ratio: 2,
      depth: 0.5,
    },
    filter: {
      type: 'none' as FilterType,
      enabled: false,
    },
  },

  /** Jackpot announcement ducks everything */
  jackpot_announcement: {
    name: 'Jackpot Full Duck',
    envelope: {
      mode: 'peak' as SidechainMode,
      attackMs: 1,
      releaseMs: 500,
      holdMs: 200,
    },
    ducking: {
      threshold: -40,
      range: -24,
      curve: 'exponential' as DuckingCurve,
      ratio: 10,
      depth: 1,
    },
    filter: {
      type: 'none' as FilterType,
      enabled: false,
    },
  },

  /** Low-frequency pumping effect */
  bass_pump: {
    name: 'Bass Pump',
    envelope: {
      mode: 'peak' as SidechainMode,
      attackMs: 1,
      releaseMs: 80,
      holdMs: 0,
    },
    ducking: {
      threshold: -12,
      range: -8,
      curve: 'exponential' as DuckingCurve,
      ratio: 4,
      depth: 1,
    },
    filter: {
      type: 'lowpass' as FilterType,
      frequency: 200,
      q: 0.707,
      enabled: true,
    },
  },
};

// ============ FACTORY FUNCTION ============

export function createSlotSidechainRoute(
  router: SidechainRouter,
  presetName: keyof typeof SLOT_SIDECHAIN_PRESETS,
  targetBusId: string,
  targetBusName: string,
  sources: Array<{ id: string; name: string; priority?: number }>
): SidechainRoute {
  const preset = SLOT_SIDECHAIN_PRESETS[presetName];

  return router.createRoute(targetBusId, targetBusName, sources, {
    name: preset.name,
    envelope: preset.envelope,
    ducking: preset.ducking,
    filter: preset.filter as Partial<SidechainFilter>,
    mix: 1,
  });
}

/**
 * Parameter Modifiers System
 *
 * Dynamic modulation of audio parameters over time.
 * Inspired by Wwise RTPC curves and synthesizer modulation.
 *
 * Modifiers:
 * - LFO: Periodic oscillation (sine, triangle, square, saw)
 * - Envelope: ADSR-style attack/decay/sustain/release
 * - Curve: Custom automation curves with keyframes
 */

// ============ TYPES ============

export type LFOWaveform = 'sine' | 'triangle' | 'square' | 'saw' | 'random';

export type EnvelopeState = 'idle' | 'attack' | 'decay' | 'sustain' | 'release';

export type CurveInterpolation = 'linear' | 'exponential' | 'bezier' | 'step';

export interface LFOConfig {
  /** Unique identifier */
  id: string;
  /** Waveform type */
  waveform: LFOWaveform;
  /** Frequency in Hz */
  frequency: number;
  /** Amplitude (0-1) */
  amplitude: number;
  /** Phase offset (0-1) */
  phase?: number;
  /** Center value to oscillate around */
  center?: number;
  /** Sync to BPM (uses beat divisions instead of Hz) */
  syncToBpm?: boolean;
  /** Beat division if synced (1 = quarter, 0.5 = eighth, etc.) */
  beatDivision?: number;
}

export interface EnvelopeConfig {
  /** Unique identifier */
  id: string;
  /** Attack time in ms */
  attackMs: number;
  /** Decay time in ms */
  decayMs: number;
  /** Sustain level (0-1) */
  sustainLevel: number;
  /** Release time in ms */
  releaseMs: number;
  /** Attack curve (0 = linear, positive = exponential, negative = logarithmic) */
  attackCurve?: number;
  /** Decay curve */
  decayCurve?: number;
  /** Release curve */
  releaseCurve?: number;
  /** Peak level */
  peakLevel?: number;
}

export interface CurveKeyframe {
  /** Time position (0-1 normalized or absolute ms) */
  time: number;
  /** Value at this keyframe */
  value: number;
  /** Interpolation to next keyframe */
  interpolation?: CurveInterpolation;
  /** Bezier control points (for bezier interpolation) */
  controlPoints?: [number, number, number, number];
}

export interface CurveConfig {
  /** Unique identifier */
  id: string;
  /** Keyframes defining the curve */
  keyframes: CurveKeyframe[];
  /** Total duration in ms */
  durationMs: number;
  /** Loop the curve */
  loop?: boolean;
  /** Ping-pong loop (reverse on each iteration) */
  pingPong?: boolean;
}

export interface ModifierTarget {
  /** Target type */
  type: 'bus' | 'sound' | 'parameter';
  /** Target ID (bus name, sound ID, or parameter path) */
  targetId: string;
  /** Property to modulate */
  property: 'volume' | 'pan' | 'pitch' | 'lowpass' | 'highpass' | 'custom';
  /** Custom property path (for 'custom' type) */
  customPath?: string;
  /** Modulation depth (how much the modifier affects the value) */
  depth: number;
  /** Additive or multiplicative modulation */
  mode: 'add' | 'multiply';
}

export interface ActiveModifier {
  id: string;
  type: 'lfo' | 'envelope' | 'curve';
  config: LFOConfig | EnvelopeConfig | CurveConfig;
  targets: ModifierTarget[];
  startTime: number;
  state: EnvelopeState | 'running';
  currentValue: number;
  releaseStartTime?: number;
  releaseStartValue?: number;
}

// ============ LFO ============

export class LFO {
  private config: LFOConfig;
  private startTime: number = 0;
  private bpm: number = 120;
  private randomValue: number = 0;
  private lastRandomTime: number = 0;

  constructor(config: LFOConfig) {
    this.config = config;
  }

  start(): void {
    this.startTime = performance.now();
    this.randomValue = Math.random() * 2 - 1;
    this.lastRandomTime = this.startTime;
  }

  setBpm(bpm: number): void {
    this.bpm = bpm;
  }

  getValue(time?: number): number {
    const now = time ?? performance.now();
    const elapsed = (now - this.startTime) / 1000; // seconds

    let frequency = this.config.frequency;
    if (this.config.syncToBpm && this.config.beatDivision) {
      // Convert beat division to frequency
      // beatDivision 1 = quarter note, at 120 BPM = 2 Hz
      frequency = (this.bpm / 60) * this.config.beatDivision;
    }

    const phase = (this.config.phase ?? 0) * Math.PI * 2;
    const t = elapsed * frequency * Math.PI * 2 + phase;
    const center = this.config.center ?? 0;
    const amplitude = this.config.amplitude;

    let value: number;

    switch (this.config.waveform) {
      case 'sine':
        value = Math.sin(t);
        break;

      case 'triangle':
        value = 2 * Math.abs(2 * ((t / (Math.PI * 2)) % 1) - 1) - 1;
        break;

      case 'square':
        value = Math.sin(t) >= 0 ? 1 : -1;
        break;

      case 'saw':
        value = 2 * ((t / (Math.PI * 2)) % 1) - 1;
        break;

      case 'random':
        // Sample and hold random
        const period = 1000 / frequency;
        if (now - this.lastRandomTime >= period) {
          this.randomValue = Math.random() * 2 - 1;
          this.lastRandomTime = now;
        }
        value = this.randomValue;
        break;

      default:
        value = 0;
    }

    return center + value * amplitude;
  }

  getConfig(): LFOConfig {
    return this.config;
  }

  updateConfig(config: Partial<LFOConfig>): void {
    this.config = { ...this.config, ...config };
  }
}

// ============ ENVELOPE ============

export class Envelope {
  private config: EnvelopeConfig;
  private state: EnvelopeState = 'idle';
  private startTime: number = 0;
  private releaseStartTime: number = 0;
  private releaseStartValue: number = 0;
  private currentValue: number = 0;

  constructor(config: EnvelopeConfig) {
    this.config = config;
  }

  trigger(): void {
    this.state = 'attack';
    this.startTime = performance.now();
    this.currentValue = 0;
  }

  release(): void {
    if (this.state !== 'idle') {
      this.state = 'release';
      this.releaseStartTime = performance.now();
      this.releaseStartValue = this.currentValue;
    }
  }

  getValue(time?: number): number {
    const now = time ?? performance.now();
    const peak = this.config.peakLevel ?? 1;

    switch (this.state) {
      case 'idle':
        this.currentValue = 0;
        break;

      case 'attack': {
        const attackElapsed = now - this.startTime;
        if (attackElapsed >= this.config.attackMs) {
          this.state = 'decay';
          this.startTime = now;
          this.currentValue = peak;
        } else {
          const t = attackElapsed / this.config.attackMs;
          this.currentValue = this.applyCurve(t, this.config.attackCurve ?? 0) * peak;
        }
        break;
      }

      case 'decay': {
        const decayElapsed = now - this.startTime;
        if (decayElapsed >= this.config.decayMs) {
          this.state = 'sustain';
          this.currentValue = this.config.sustainLevel * peak;
        } else {
          const t = decayElapsed / this.config.decayMs;
          const curved = this.applyCurve(t, this.config.decayCurve ?? 0);
          this.currentValue = peak - (peak - this.config.sustainLevel * peak) * curved;
        }
        break;
      }

      case 'sustain':
        this.currentValue = this.config.sustainLevel * peak;
        break;

      case 'release': {
        const releaseElapsed = now - this.releaseStartTime;
        if (releaseElapsed >= this.config.releaseMs) {
          this.state = 'idle';
          this.currentValue = 0;
        } else {
          const t = releaseElapsed / this.config.releaseMs;
          const curved = this.applyCurve(t, this.config.releaseCurve ?? 0);
          this.currentValue = this.releaseStartValue * (1 - curved);
        }
        break;
      }
    }

    return this.currentValue;
  }

  private applyCurve(t: number, curve: number): number {
    if (curve === 0) {
      return t; // Linear
    } else if (curve > 0) {
      // Exponential
      return Math.pow(t, 1 + curve);
    } else {
      // Logarithmic
      return 1 - Math.pow(1 - t, 1 - curve);
    }
  }

  getState(): EnvelopeState {
    return this.state;
  }

  isActive(): boolean {
    return this.state !== 'idle';
  }

  getConfig(): EnvelopeConfig {
    return this.config;
  }

  updateConfig(config: Partial<EnvelopeConfig>): void {
    this.config = { ...this.config, ...config };
  }
}

// ============ CURVE ============

export class AutomationCurve {
  private config: CurveConfig;
  private startTime: number = 0;
  private isRunning: boolean = false;
  private direction: 1 | -1 = 1;
  private loopCount: number = 0;

  constructor(config: CurveConfig) {
    this.config = config;
  }

  start(): void {
    this.startTime = performance.now();
    this.isRunning = true;
    this.direction = 1;
    this.loopCount = 0;
  }

  stop(): void {
    this.isRunning = false;
  }

  getValue(time?: number): number {
    if (!this.isRunning) {
      return this.config.keyframes[0]?.value ?? 0;
    }

    const now = time ?? performance.now();
    let elapsed = now - this.startTime;
    const duration = this.config.durationMs;

    if (elapsed >= duration) {
      if (this.config.loop) {
        if (this.config.pingPong) {
          this.loopCount++;
          this.direction = this.loopCount % 2 === 0 ? 1 : -1;
        }
        elapsed = elapsed % duration;
        this.startTime = now - elapsed;
      } else {
        this.isRunning = false;
        return this.config.keyframes[this.config.keyframes.length - 1]?.value ?? 0;
      }
    }

    // Normalize time (0-1)
    let t = elapsed / duration;
    if (this.direction === -1) {
      t = 1 - t;
    }

    return this.interpolateKeyframes(t);
  }

  private interpolateKeyframes(t: number): number {
    const keyframes = this.config.keyframes;
    if (keyframes.length === 0) return 0;
    if (keyframes.length === 1) return keyframes[0].value;

    // Find surrounding keyframes
    let prevIndex = 0;
    for (let i = 0; i < keyframes.length - 1; i++) {
      if (keyframes[i + 1].time > t) {
        prevIndex = i;
        break;
      }
      prevIndex = i;
    }

    const prev = keyframes[prevIndex];
    const next = keyframes[Math.min(prevIndex + 1, keyframes.length - 1)];

    if (prev === next || prev.time === next.time) {
      return prev.value;
    }

    // Local t within this segment
    const localT = (t - prev.time) / (next.time - prev.time);
    const interpolation = prev.interpolation ?? 'linear';

    switch (interpolation) {
      case 'linear':
        return prev.value + (next.value - prev.value) * localT;

      case 'exponential':
        return prev.value + (next.value - prev.value) * (1 - Math.pow(1 - localT, 3));

      case 'step':
        return prev.value;

      case 'bezier':
        if (prev.controlPoints) {
          return this.bezierInterpolate(localT, prev.value, next.value, prev.controlPoints);
        }
        return prev.value + (next.value - prev.value) * localT;

      default:
        return prev.value + (next.value - prev.value) * localT;
    }
  }

  private bezierInterpolate(
    t: number,
    start: number,
    end: number,
    controlPoints: [number, number, number, number]
  ): number {
    const [_cx1, cy1, _cx2, cy2] = controlPoints;
    // Cubic bezier (cx1/cx2 are x-axis control points, not used for y interpolation)
    const t2 = t * t;
    const t3 = t2 * t;
    const mt = 1 - t;
    const mt2 = mt * mt;
    const mt3 = mt2 * mt;

    const y = mt3 * start + 3 * mt2 * t * (start + cy1 * (end - start)) +
              3 * mt * t2 * (end + cy2 * (start - end)) + t3 * end;

    return y;
  }

  isActive(): boolean {
    return this.isRunning;
  }

  getConfig(): CurveConfig {
    return this.config;
  }

  updateConfig(config: Partial<CurveConfig>): void {
    this.config = { ...this.config, ...config };
  }
}

// ============ MODIFIER MANAGER ============

export class ParameterModifierManager {
  private lfos: Map<string, LFO> = new Map();
  private envelopes: Map<string, Envelope> = new Map();
  private curves: Map<string, AutomationCurve> = new Map();
  private activeModifiers: Map<string, ActiveModifier> = new Map();
  private targets: Map<string, ModifierTarget[]> = new Map();
  private bpm: number = 120;
  private animationFrame: number | null = null;
  private updateCallback: ((modifierId: string, value: number, targets: ModifierTarget[]) => void) | null = null;

  constructor(updateCallback?: (modifierId: string, value: number, targets: ModifierTarget[]) => void) {
    this.updateCallback = updateCallback ?? null;
  }

  /**
   * Create and register an LFO
   */
  createLFO(config: LFOConfig): LFO {
    const lfo = new LFO(config);
    lfo.setBpm(this.bpm);
    this.lfos.set(config.id, lfo);
    return lfo;
  }

  /**
   * Create and register an envelope
   */
  createEnvelope(config: EnvelopeConfig): Envelope {
    const envelope = new Envelope(config);
    this.envelopes.set(config.id, envelope);
    return envelope;
  }

  /**
   * Create and register a curve
   */
  createCurve(config: CurveConfig): AutomationCurve {
    const curve = new AutomationCurve(config);
    this.curves.set(config.id, curve);
    return curve;
  }

  /**
   * Start an LFO with targets
   */
  startLFO(id: string, targets: ModifierTarget[]): boolean {
    const lfo = this.lfos.get(id);
    if (!lfo) return false;

    lfo.start();
    this.targets.set(id, targets);
    this.activeModifiers.set(id, {
      id,
      type: 'lfo',
      config: lfo.getConfig(),
      targets,
      startTime: performance.now(),
      state: 'running',
      currentValue: 0,
    });

    this.ensureAnimationLoop();
    return true;
  }

  /**
   * Trigger an envelope with targets
   */
  triggerEnvelope(id: string, targets: ModifierTarget[]): boolean {
    const envelope = this.envelopes.get(id);
    if (!envelope) return false;

    envelope.trigger();
    this.targets.set(id, targets);
    this.activeModifiers.set(id, {
      id,
      type: 'envelope',
      config: envelope.getConfig(),
      targets,
      startTime: performance.now(),
      state: 'attack',
      currentValue: 0,
    });

    this.ensureAnimationLoop();
    return true;
  }

  /**
   * Release an envelope
   */
  releaseEnvelope(id: string): boolean {
    const envelope = this.envelopes.get(id);
    if (!envelope) return false;

    envelope.release();
    const active = this.activeModifiers.get(id);
    if (active) {
      active.state = 'release';
      active.releaseStartTime = performance.now();
      active.releaseStartValue = active.currentValue;
    }
    return true;
  }

  /**
   * Start a curve with targets
   */
  startCurve(id: string, targets: ModifierTarget[]): boolean {
    const curve = this.curves.get(id);
    if (!curve) return false;

    curve.start();
    this.targets.set(id, targets);
    this.activeModifiers.set(id, {
      id,
      type: 'curve',
      config: curve.getConfig(),
      targets,
      startTime: performance.now(),
      state: 'running',
      currentValue: 0,
    });

    this.ensureAnimationLoop();
    return true;
  }

  /**
   * Stop a modifier
   */
  stopModifier(id: string): void {
    const curve = this.curves.get(id);
    if (curve) curve.stop();

    this.activeModifiers.delete(id);
    this.targets.delete(id);

    if (this.activeModifiers.size === 0) {
      this.stopAnimationLoop();
    }
  }

  /**
   * Stop all modifiers
   */
  stopAll(): void {
    this.curves.forEach(c => c.stop());
    this.activeModifiers.clear();
    this.targets.clear();
    this.stopAnimationLoop();
  }

  /**
   * Set BPM for synced LFOs
   */
  setBpm(bpm: number): void {
    this.bpm = bpm;
    this.lfos.forEach(lfo => lfo.setBpm(bpm));
  }

  /**
   * Get current value of a modifier
   */
  getValue(id: string): number {
    const lfo = this.lfos.get(id);
    if (lfo) return lfo.getValue();

    const envelope = this.envelopes.get(id);
    if (envelope) return envelope.getValue();

    const curve = this.curves.get(id);
    if (curve) return curve.getValue();

    return 0;
  }

  /**
   * Ensure animation loop is running
   */
  private ensureAnimationLoop(): void {
    if (this.animationFrame === null) {
      this.animationFrame = requestAnimationFrame(() => this.update());
    }
  }

  /**
   * Stop animation loop
   */
  private stopAnimationLoop(): void {
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  }

  /**
   * Update all active modifiers
   */
  private update(): void {
    const now = performance.now();
    const toRemove: string[] = [];

    this.activeModifiers.forEach((active, id) => {
      let value = 0;

      switch (active.type) {
        case 'lfo': {
          const lfo = this.lfos.get(id);
          if (lfo) value = lfo.getValue(now);
          break;
        }

        case 'envelope': {
          const envelope = this.envelopes.get(id);
          if (envelope) {
            value = envelope.getValue(now);
            active.state = envelope.getState();
            if (!envelope.isActive()) {
              toRemove.push(id);
            }
          }
          break;
        }

        case 'curve': {
          const curve = this.curves.get(id);
          if (curve) {
            value = curve.getValue(now);
            if (!curve.isActive()) {
              toRemove.push(id);
            }
          }
          break;
        }
      }

      active.currentValue = value;

      // Notify callback
      if (this.updateCallback && active.targets.length > 0) {
        this.updateCallback(id, value, active.targets);
      }
    });

    // Remove finished modifiers
    toRemove.forEach(id => {
      this.activeModifiers.delete(id);
      this.targets.delete(id);
    });

    // Continue loop if there are active modifiers
    if (this.activeModifiers.size > 0) {
      this.animationFrame = requestAnimationFrame(() => this.update());
    } else {
      this.animationFrame = null;
    }
  }

  /**
   * Get all active modifiers
   */
  getActiveModifiers(): ActiveModifier[] {
    return Array.from(this.activeModifiers.values());
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopAll();
    this.lfos.clear();
    this.envelopes.clear();
    this.curves.clear();
  }
}

// ============ DEFAULT CONFIGS ============

export const DEFAULT_LFO_CONFIGS: LFOConfig[] = [
  {
    id: 'wobble_slow',
    waveform: 'sine',
    frequency: 0.5,
    amplitude: 0.1,
    center: 1.0,
  },
  {
    id: 'wobble_fast',
    waveform: 'sine',
    frequency: 4,
    amplitude: 0.05,
    center: 1.0,
  },
  {
    id: 'tremolo',
    waveform: 'triangle',
    frequency: 6,
    amplitude: 0.3,
    center: 0.7,
  },
  {
    id: 'pan_sweep',
    waveform: 'sine',
    frequency: 0.25,
    amplitude: 1.0,
    center: 0,
  },
  {
    id: 'beat_sync_pulse',
    waveform: 'square',
    frequency: 2,
    amplitude: 0.5,
    center: 0.5,
    syncToBpm: true,
    beatDivision: 1,
  },
];

export const DEFAULT_ENVELOPE_CONFIGS: EnvelopeConfig[] = [
  {
    id: 'win_swell',
    attackMs: 100,
    decayMs: 200,
    sustainLevel: 0.8,
    releaseMs: 500,
    peakLevel: 1.2,
  },
  {
    id: 'anticipation_build',
    attackMs: 2000,
    decayMs: 0,
    sustainLevel: 1.0,
    releaseMs: 100,
    attackCurve: 2,
  },
  {
    id: 'impact_punch',
    attackMs: 10,
    decayMs: 100,
    sustainLevel: 0.3,
    releaseMs: 200,
    peakLevel: 1.5,
    decayCurve: 1,
  },
  {
    id: 'fade_in',
    attackMs: 500,
    decayMs: 0,
    sustainLevel: 1.0,
    releaseMs: 0,
  },
  {
    id: 'duck_envelope',
    attackMs: 50,
    decayMs: 100,
    sustainLevel: 0.3,
    releaseMs: 300,
    attackCurve: -1,
  },
];

export const DEFAULT_CURVE_CONFIGS: CurveConfig[] = [
  {
    id: 'volume_automation',
    durationMs: 5000,
    loop: false,
    keyframes: [
      { time: 0, value: 0, interpolation: 'exponential' },
      { time: 0.3, value: 1, interpolation: 'linear' },
      { time: 0.7, value: 0.8, interpolation: 'linear' },
      { time: 1, value: 0, interpolation: 'exponential' },
    ],
  },
  {
    id: 'intensity_ramp',
    durationMs: 10000,
    loop: false,
    keyframes: [
      { time: 0, value: 0, interpolation: 'bezier', controlPoints: [0.4, 0, 0.2, 1] },
      { time: 1, value: 1 },
    ],
  },
  {
    id: 'pulse_pattern',
    durationMs: 1000,
    loop: true,
    keyframes: [
      { time: 0, value: 1, interpolation: 'step' },
      { time: 0.25, value: 0.5, interpolation: 'step' },
      { time: 0.5, value: 1, interpolation: 'step' },
      { time: 0.75, value: 0.5, interpolation: 'step' },
      { time: 1, value: 1 },
    ],
  },
];

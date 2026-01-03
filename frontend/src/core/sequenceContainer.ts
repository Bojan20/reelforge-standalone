/**
 * Sequence Container System
 *
 * Plays sounds in order with configurable timing between steps.
 * Use cases:
 * - Multi-part win celebrations (ding → fanfare → voice)
 * - Reel stop sequences (stop1 → stop2 → stop3 → stop4 → stop5)
 * - Intro/outro sequences
 * - Cascading sound effects
 */

import type { BusId } from './types';

// ============ TYPES ============

export type SequenceStepTiming = 'immediate' | 'after-previous' | 'with-previous';

export interface SequenceStep {
  /** Sound asset ID to play */
  assetId: string;
  /** Bus to play on */
  bus?: BusId;
  /** Volume multiplier (0-1) */
  volume?: number;
  /** Delay before this step starts (ms) */
  delayMs?: number;
  /** Timing relative to previous step */
  timing?: SequenceStepTiming;
  /** Crossfade with previous step (ms) - only for 'after-previous' */
  crossfadeMs?: number;
  /** Pitch multiplier */
  pitchMultiplier?: number;
  /** Optional callback when step starts */
  onStart?: () => void;
  /** Optional callback when step ends */
  onEnd?: () => void;
}

export interface SequenceContainer {
  /** Unique identifier */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Ordered list of steps */
  steps: SequenceStep[];
  /** Loop the entire sequence */
  loop?: boolean;
  /** Number of times to loop (undefined = infinite) */
  loopCount?: number;
  /** Delay before restarting loop (ms) */
  loopDelayMs?: number;
  /** Can be interrupted by another sequence */
  interruptible?: boolean;
  /** Priority for interruption (higher = harder to interrupt) */
  priority?: number;
  /** Callback when sequence completes */
  onComplete?: () => void;
}

export interface SequencePlaybackState {
  containerId: string;
  currentStepIndex: number;
  loopsRemaining: number | null;
  isPlaying: boolean;
  isPaused: boolean;
  startTime: number;
  stepStartTime: number;
}

export interface SequencePlayOptions {
  /** Override loop setting */
  loop?: boolean;
  /** Override loop count */
  loopCount?: number;
  /** Start from specific step */
  startStep?: number;
  /** Volume multiplier for entire sequence */
  volumeMultiplier?: number;
  /** Callback for each step */
  onStepStart?: (stepIndex: number, step: SequenceStep) => void;
  /** Callback when sequence completes */
  onComplete?: () => void;
}

// ============ SEQUENCE MANAGER ============

export class SequenceContainerManager {
  private containers: Map<string, SequenceContainer> = new Map();
  private activeSequences: Map<string, SequencePlaybackState> = new Map();
  private timers: Map<string, number[]> = new Map();
  private playCallback: (assetId: string, bus: BusId, volume: number, pitch: number) => string | null;
  private stopCallback: (voiceId: string) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number, pitch: number) => string | null,
    stopCallback: (voiceId: string) => void,
    containers?: SequenceContainer[]
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;

    // Register default containers
    DEFAULT_SEQUENCE_CONTAINERS.forEach(c => this.registerContainer(c));

    // Register custom containers
    if (containers) {
      containers.forEach(c => this.registerContainer(c));
    }
  }

  /**
   * Register a sequence container
   */
  registerContainer(container: SequenceContainer): void {
    this.containers.set(container.id, container);
  }

  /**
   * Unregister a sequence container
   */
  unregisterContainer(containerId: string): void {
    this.stopSequence(containerId);
    this.containers.delete(containerId);
  }

  /**
   * Play a sequence
   */
  playSequence(containerId: string, options?: SequencePlayOptions): boolean {
    const container = this.containers.get(containerId);
    if (!container) {
      console.warn(`[SEQUENCE] Container not found: ${containerId}`);
      return false;
    }

    // Check if already playing
    const existing = this.activeSequences.get(containerId);
    if (existing?.isPlaying) {
      if (!container.interruptible) {
        console.warn(`[SEQUENCE] ${containerId} is not interruptible`);
        return false;
      }
      this.stopSequence(containerId);
    }

    // Create playback state
    const state: SequencePlaybackState = {
      containerId,
      currentStepIndex: options?.startStep ?? 0,
      loopsRemaining: options?.loopCount ?? container.loopCount ?? null,
      isPlaying: true,
      isPaused: false,
      startTime: performance.now(),
      stepStartTime: performance.now(),
    };

    this.activeSequences.set(containerId, state);
    this.timers.set(containerId, []);

    // Start playing
    this.playStep(containerId, state.currentStepIndex, options);

    return true;
  }

  /**
   * Play a specific step
   */
  private playStep(containerId: string, stepIndex: number, options?: SequencePlayOptions): void {
    const container = this.containers.get(containerId);
    const state = this.activeSequences.get(containerId);

    if (!container || !state || !state.isPlaying || state.isPaused) {
      return;
    }

    // Check if sequence complete
    if (stepIndex >= container.steps.length) {
      this.handleSequenceEnd(containerId, options);
      return;
    }

    const step = container.steps[stepIndex];
    state.currentStepIndex = stepIndex;
    state.stepStartTime = performance.now();

    // Calculate delay
    let delay = step.delayMs ?? 0;

    // Handle timing modes
    if (stepIndex > 0 && step.timing === 'with-previous') {
      // Play immediately with previous (delay is relative to previous step start)
      delay = step.delayMs ?? 0;
    } else if (stepIndex > 0 && step.timing === 'after-previous') {
      // Delay is already accounted for by the previous step's duration
      // Crossfade handled separately
    }

    const executeStep = () => {
      if (!state.isPlaying || state.isPaused) return;

      // Callbacks
      step.onStart?.();
      options?.onStepStart?.(stepIndex, step);

      // Play the sound
      const volume = (step.volume ?? 1.0) * (options?.volumeMultiplier ?? 1.0);
      const bus = step.bus ?? 'sfx';
      const pitch = step.pitchMultiplier ?? 1.0;

      this.playCallback(step.assetId, bus, volume, pitch);

      // Schedule next step
      this.scheduleNextStep(containerId, stepIndex, options);
    };

    if (delay > 0) {
      const timerId = window.setTimeout(executeStep, delay);
      this.timers.get(containerId)?.push(timerId);
    } else {
      executeStep();
    }
  }

  /**
   * Schedule the next step based on timing
   */
  private scheduleNextStep(containerId: string, currentIndex: number, options?: SequencePlayOptions): void {
    const container = this.containers.get(containerId);
    const state = this.activeSequences.get(containerId);

    if (!container || !state) return;

    const nextIndex = currentIndex + 1;
    if (nextIndex >= container.steps.length) {
      // Will be handled by playStep
      this.playStep(containerId, nextIndex, options);
      return;
    }

    const currentStep = container.steps[currentIndex];
    const nextStep = container.steps[nextIndex];

    let nextDelay = 0;

    switch (nextStep.timing) {
      case 'immediate':
        // Next step handles its own delay
        nextDelay = 0;
        break;

      case 'with-previous':
        // Play at same time as current (with optional offset)
        nextDelay = nextStep.delayMs ?? 0;
        break;

      case 'after-previous':
      default:
        // Wait for current to finish (estimated duration or explicit delay)
        // Since we don't have duration info, use crossfade or a default gap
        const crossfade = nextStep.crossfadeMs ?? 0;
        const gap = nextStep.delayMs ?? 100; // Default 100ms gap
        nextDelay = Math.max(0, gap - crossfade);
        break;
    }

    const timerId = window.setTimeout(() => {
      currentStep.onEnd?.();
      this.playStep(containerId, nextIndex, options);
    }, nextDelay);

    this.timers.get(containerId)?.push(timerId);
  }

  /**
   * Handle sequence end (loop or complete)
   */
  private handleSequenceEnd(containerId: string, options?: SequencePlayOptions): void {
    const container = this.containers.get(containerId);
    const state = this.activeSequences.get(containerId);

    if (!container || !state) return;

    const shouldLoop = options?.loop ?? container.loop ?? false;

    if (shouldLoop) {
      // Check loop count
      if (state.loopsRemaining !== null) {
        state.loopsRemaining--;
        if (state.loopsRemaining <= 0) {
          this.completeSequence(containerId, options);
          return;
        }
      }

      // Loop with delay
      const loopDelay = container.loopDelayMs ?? 0;
      const timerId = window.setTimeout(() => {
        state.currentStepIndex = 0;
        this.playStep(containerId, 0, options);
      }, loopDelay);

      this.timers.get(containerId)?.push(timerId);
    } else {
      this.completeSequence(containerId, options);
    }
  }

  /**
   * Complete a sequence
   */
  private completeSequence(containerId: string, options?: SequencePlayOptions): void {
    const container = this.containers.get(containerId);
    const state = this.activeSequences.get(containerId);

    if (state) {
      state.isPlaying = false;
    }

    // Callbacks
    options?.onComplete?.();
    container?.onComplete?.();

    // Cleanup
    this.clearTimers(containerId);
    this.activeSequences.delete(containerId);
  }

  /**
   * Stop a sequence
   */
  stopSequence(containerId: string): void {
    const state = this.activeSequences.get(containerId);
    if (state) {
      state.isPlaying = false;
      // Stop any playing sounds from this sequence
      const container = this.containers.get(containerId);
      if (container && state.currentStepIndex < container.steps.length) {
        const currentStep = container.steps[state.currentStepIndex];
        this.stopCallback(currentStep.assetId);
      }
    }

    this.clearTimers(containerId);
    this.activeSequences.delete(containerId);
  }

  /**
   * Pause a sequence
   */
  pauseSequence(containerId: string): void {
    const state = this.activeSequences.get(containerId);
    if (state) {
      state.isPaused = true;
    }
    // Note: Timers continue but steps check isPaused
  }

  /**
   * Resume a paused sequence
   */
  resumeSequence(containerId: string): void {
    const state = this.activeSequences.get(containerId);
    if (state && state.isPaused) {
      state.isPaused = false;
      // Continue from current step
      this.playStep(containerId, state.currentStepIndex);
    }
  }

  /**
   * Stop all sequences
   */
  stopAll(): void {
    this.activeSequences.forEach((_, containerId) => {
      this.stopSequence(containerId);
    });
  }

  /**
   * Clear timers for a sequence
   */
  private clearTimers(containerId: string): void {
    const timers = this.timers.get(containerId);
    if (timers) {
      timers.forEach(t => window.clearTimeout(t));
      this.timers.delete(containerId);
    }
  }

  /**
   * Get playback state
   */
  getPlaybackState(containerId: string): SequencePlaybackState | null {
    return this.activeSequences.get(containerId) ?? null;
  }

  /**
   * Check if sequence is playing
   */
  isPlaying(containerId: string): boolean {
    const state = this.activeSequences.get(containerId);
    return state?.isPlaying ?? false;
  }

  /**
   * Get all registered containers
   */
  getContainers(): SequenceContainer[] {
    return Array.from(this.containers.values());
  }

  /**
   * Get a specific container
   */
  getContainer(containerId: string): SequenceContainer | undefined {
    return this.containers.get(containerId);
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopAll();
    this.containers.clear();
  }
}

// ============ DEFAULT CONTAINERS ============

export const DEFAULT_SEQUENCE_CONTAINERS: SequenceContainer[] = [
  {
    id: 'reel_stop_sequence',
    name: 'Reel Stop Sequence',
    description: 'Sequential reel stop sounds with cascade timing',
    interruptible: true,
    priority: 5,
    steps: [
      { assetId: 'reel_stop_1', bus: 'sfx', volume: 1.0, timing: 'immediate' },
      { assetId: 'reel_stop_2', bus: 'sfx', volume: 1.0, timing: 'after-previous', delayMs: 150 },
      { assetId: 'reel_stop_3', bus: 'sfx', volume: 1.0, timing: 'after-previous', delayMs: 150 },
      { assetId: 'reel_stop_4', bus: 'sfx', volume: 1.0, timing: 'after-previous', delayMs: 150 },
      { assetId: 'reel_stop_5', bus: 'sfx', volume: 1.0, timing: 'after-previous', delayMs: 150 },
    ],
  },
  {
    id: 'win_celebration',
    name: 'Win Celebration',
    description: 'Multi-part win celebration sequence',
    interruptible: false,
    priority: 10,
    steps: [
      { assetId: 'win_ding', bus: 'sfx', volume: 1.0, timing: 'immediate' },
      { assetId: 'win_fanfare', bus: 'music', volume: 0.8, timing: 'after-previous', delayMs: 200 },
      { assetId: 'win_coins', bus: 'sfx', volume: 0.7, timing: 'with-previous', delayMs: 500 },
    ],
  },
  {
    id: 'big_win_sequence',
    name: 'Big Win Sequence',
    description: 'Extended big win celebration',
    interruptible: false,
    priority: 15,
    steps: [
      { assetId: 'bigwin_impact', bus: 'sfx', volume: 1.0, timing: 'immediate' },
      { assetId: 'bigwin_buildup', bus: 'music', volume: 0.9, timing: 'after-previous', delayMs: 100 },
      { assetId: 'bigwin_explosion', bus: 'sfx', volume: 1.0, timing: 'after-previous', delayMs: 800 },
      { assetId: 'bigwin_coins_shower', bus: 'sfx', volume: 0.8, timing: 'with-previous', delayMs: 200 },
      { assetId: 'bigwin_voice', bus: 'voice', volume: 1.0, timing: 'after-previous', delayMs: 500 },
    ],
  },
  {
    id: 'freespins_intro',
    name: 'Free Spins Intro',
    description: 'Free spins feature start sequence',
    interruptible: false,
    priority: 12,
    steps: [
      { assetId: 'fs_whoosh', bus: 'sfx', volume: 1.0, timing: 'immediate' },
      { assetId: 'fs_transition', bus: 'sfx', volume: 0.9, timing: 'after-previous', delayMs: 300 },
      { assetId: 'fs_music_start', bus: 'music', volume: 0.8, timing: 'after-previous', delayMs: 500, crossfadeMs: 200 },
      { assetId: 'fs_voice_announce', bus: 'voice', volume: 1.0, timing: 'with-previous', delayMs: 100 },
    ],
  },
  {
    id: 'countdown_sequence',
    name: 'Countdown Sequence',
    description: 'Feature countdown (3, 2, 1, GO!)',
    interruptible: false,
    priority: 8,
    loop: false,
    steps: [
      { assetId: 'countdown_3', bus: 'voice', volume: 1.0, timing: 'immediate' },
      { assetId: 'countdown_2', bus: 'voice', volume: 1.0, timing: 'after-previous', delayMs: 1000 },
      { assetId: 'countdown_1', bus: 'voice', volume: 1.0, timing: 'after-previous', delayMs: 1000 },
      { assetId: 'countdown_go', bus: 'voice', volume: 1.2, timing: 'after-previous', delayMs: 1000 },
      { assetId: 'countdown_burst', bus: 'sfx', volume: 1.0, timing: 'with-previous', delayMs: 0 },
    ],
  },
];

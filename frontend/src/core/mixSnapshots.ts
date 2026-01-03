/**
 * ReelForge Mix Snapshots
 *
 * Unity-inspired instant mix state presets.
 * Allows transitioning the entire audio mix to predefined states
 * with smooth crossfades.
 *
 * Use cases:
 * - Idle → BigWin (duck music, boost SFX)
 * - BaseGame → FreeSpins (switch music layer, adjust ambience)
 * - Normal → Muted (quick fade all)
 */

import type { MixSnapshot, BusId } from './types';

// Default snapshots for slot games
export const DEFAULT_SNAPSHOTS: MixSnapshot[] = [
  {
    id: 'idle',
    name: 'Idle',
    description: 'Default idle state',
    buses: {
      music: { volume: 0.7 },
      sfx: { volume: 1.0 },
      ambience: { volume: 0.5 },
      voice: { volume: 1.0 },
    },
    master: { volume: 1.0 },
    transitionMs: 500,
  },
  {
    id: 'bigwin',
    name: 'Big Win',
    description: 'Celebration mode - boost SFX, duck music',
    buses: {
      music: { volume: 0.4 },
      sfx: { volume: 1.2 },
      ambience: { volume: 0.1 },
      voice: { volume: 1.0 },
    },
    master: { volume: 1.0 },
    transitionMs: 300,
  },
  {
    id: 'freespins',
    name: 'Free Spins',
    description: 'Feature mode - intense music, no ambience',
    buses: {
      music: { volume: 0.85 },
      sfx: { volume: 1.0 },
      ambience: { volume: 0.0 },
      voice: { volume: 1.0 },
    },
    master: { volume: 1.0 },
    musicLayer: 'feature',
    transitionMs: 800,
  },
  {
    id: 'anticipation',
    name: 'Anticipation',
    description: 'Building tension - lower music, prepare for reveal',
    buses: {
      music: { volume: 0.5 },
      sfx: { volume: 0.8 },
      ambience: { volume: 0.3 },
      voice: { volume: 1.0 },
    },
    master: { volume: 1.0 },
    transitionMs: 200,
  },
  {
    id: 'muted',
    name: 'Muted',
    description: 'All audio muted',
    buses: {
      music: { volume: 0, muted: true },
      sfx: { volume: 0, muted: true },
      ambience: { volume: 0, muted: true },
      voice: { volume: 0, muted: true },
    },
    master: { volume: 0, muted: true },
    transitionMs: 200,
  },
];

export interface SnapshotTransitionOptions {
  /** Override the snapshot's default transition duration */
  durationMs?: number;
  /** Easing function */
  easing?: 'linear' | 'easeIn' | 'easeOut' | 'easeInOut';
  /** Callback when transition completes */
  onComplete?: () => void;
}

interface ActiveTransition {
  snapshotId: string;
  startTime: number;
  durationMs: number;
  fromState: Map<string, number>;
  toState: Map<string, number>;
  easing: 'linear' | 'easeIn' | 'easeOut' | 'easeInOut';
  onComplete?: () => void;
  animationFrame?: number;
}

type SetBusVolumeCallback = (bus: BusId | 'master', volume: number) => void;
type SetMusicLayerCallback = (layer: string) => void;

export class SnapshotManager {
  private snapshots: Map<string, MixSnapshot> = new Map();
  private currentSnapshotId: string | null = null;
  private activeTransition: ActiveTransition | null = null;
  private setBusVolume: SetBusVolumeCallback;
  private setMusicLayer?: SetMusicLayerCallback;

  constructor(
    setBusVolume: SetBusVolumeCallback,
    setMusicLayer?: SetMusicLayerCallback,
    initialSnapshots?: MixSnapshot[]
  ) {
    this.setBusVolume = setBusVolume;
    this.setMusicLayer = setMusicLayer;

    // Load default snapshots
    DEFAULT_SNAPSHOTS.forEach(s => this.snapshots.set(s.id, s));

    // Add custom snapshots
    if (initialSnapshots) {
      initialSnapshots.forEach(s => this.snapshots.set(s.id, s));
    }
  }

  /**
   * Register a new snapshot or update existing
   */
  registerSnapshot(snapshot: MixSnapshot): void {
    this.snapshots.set(snapshot.id, snapshot);
  }

  /**
   * Remove a snapshot
   */
  removeSnapshot(id: string): boolean {
    return this.snapshots.delete(id);
  }

  /**
   * Get all registered snapshots
   */
  getSnapshots(): MixSnapshot[] {
    return Array.from(this.snapshots.values());
  }

  /**
   * Get current snapshot ID
   */
  getCurrentSnapshotId(): string | null {
    return this.currentSnapshotId;
  }

  /**
   * Transition to a snapshot with smooth crossfade
   */
  transitionTo(
    snapshotId: string,
    options: SnapshotTransitionOptions = {}
  ): boolean {
    const snapshot = this.snapshots.get(snapshotId);
    if (!snapshot) {
      console.warn(`[SnapshotManager] Snapshot not found: ${snapshotId}`);
      return false;
    }

    // Cancel any active transition
    this.cancelTransition();

    const durationMs = options.durationMs ?? snapshot.transitionMs ?? 500;
    const easing = options.easing ?? 'easeOut';

    // If instant transition (0ms), apply immediately
    if (durationMs === 0) {
      this.applySnapshotImmediate(snapshot);
      this.currentSnapshotId = snapshotId;
      options.onComplete?.();
      return true;
    }

    // Capture current state
    const fromState = new Map<string, number>();
    const toState = new Map<string, number>();

    // Build target state map
    if (snapshot.master) {
      toState.set('master.volume', snapshot.master.volume);
    }

    const busIds: BusId[] = ['music', 'sfx', 'ambience', 'voice'];
    busIds.forEach(busId => {
      const busState = snapshot.buses[busId];
      if (busState) {
        toState.set(`${busId}.volume`, busState.volume);
      }
    });

    // Start transition
    this.activeTransition = {
      snapshotId,
      startTime: performance.now(),
      durationMs,
      fromState,
      toState,
      easing,
      onComplete: options.onComplete,
    };

    // Start animation loop
    this.animateTransition();

    // Handle music layer change
    if (snapshot.musicLayer && this.setMusicLayer) {
      this.setMusicLayer(snapshot.musicLayer);
    }

    return true;
  }

  /**
   * Apply snapshot immediately without transition
   */
  applySnapshotImmediate(snapshot: MixSnapshot): void {
    // Apply master
    if (snapshot.master) {
      this.setBusVolume('master', snapshot.master.volume);
    }

    // Apply buses
    const busIds: BusId[] = ['music', 'sfx', 'ambience', 'voice'];
    busIds.forEach(busId => {
      const busState = snapshot.buses[busId];
      if (busState) {
        this.setBusVolume(busId, busState.volume);
      }
    });

    // Apply music layer
    if (snapshot.musicLayer && this.setMusicLayer) {
      this.setMusicLayer(snapshot.musicLayer);
    }

    this.currentSnapshotId = snapshot.id;
  }

  /**
   * Cancel active transition
   */
  cancelTransition(): void {
    if (this.activeTransition?.animationFrame) {
      cancelAnimationFrame(this.activeTransition.animationFrame);
    }
    this.activeTransition = null;
  }

  /**
   * Animation loop for smooth transitions
   */
  private animateTransition = (): void => {
    if (!this.activeTransition) return;

    const { startTime, durationMs, toState, easing, snapshotId, onComplete } = this.activeTransition;
    const elapsed = performance.now() - startTime;
    const progress = Math.min(1, elapsed / durationMs);

    // Apply easing
    const easedProgress = this.applyEasing(progress, easing);

    // Interpolate and apply values
    toState.forEach((targetValue, path) => {
      const [busId, param] = path.split('.');
      if (param === 'volume') {
        // Get current value (we'll interpolate from current)
        const currentValue = this.getCurrentBusVolume(busId as BusId | 'master');
        const newValue = currentValue + (targetValue - currentValue) * easedProgress;
        this.setBusVolume(busId as BusId | 'master', newValue);
      }
    });

    // Continue or complete
    if (progress < 1) {
      this.activeTransition.animationFrame = requestAnimationFrame(this.animateTransition);
    } else {
      // Transition complete
      this.currentSnapshotId = snapshotId;
      this.activeTransition = null;
      onComplete?.();
    }
  };

  /**
   * Get current bus volume (for interpolation)
   * This is a simplified version - in real implementation,
   * this should query the actual audio engine state
   */
  private getCurrentBusVolume(_busId: BusId | 'master'): number {
    // Default to 1.0 - in real use, this queries audioEngine
    return 1.0;
  }

  /**
   * Apply easing function
   */
  private applyEasing(t: number, easing: 'linear' | 'easeIn' | 'easeOut' | 'easeInOut'): number {
    switch (easing) {
      case 'linear':
        return t;
      case 'easeIn':
        return t * t;
      case 'easeOut':
        return 1 - (1 - t) * (1 - t);
      case 'easeInOut':
        return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      default:
        return t;
    }
  }

  /**
   * Create snapshot from current state
   */
  captureCurrentState(id: string, name: string, getBusVolume: (bus: BusId | 'master') => number): MixSnapshot {
    const snapshot: MixSnapshot = {
      id,
      name,
      buses: {
        music: { volume: getBusVolume('music') },
        sfx: { volume: getBusVolume('sfx') },
        ambience: { volume: getBusVolume('ambience') },
        voice: { volume: getBusVolume('voice') },
      },
      master: { volume: getBusVolume('master') },
      transitionMs: 500,
    };

    this.registerSnapshot(snapshot);
    return snapshot;
  }

  /**
   * Dispose and cleanup
   */
  dispose(): void {
    this.cancelTransition();
    this.snapshots.clear();
    this.currentSnapshotId = null;
  }
}

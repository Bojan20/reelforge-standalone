/**
 * Blend Container System
 *
 * Crossfade between multiple sounds based on a parameter value.
 * Similar to Wwise Blend Containers and Unity Audio Mixer snapshots.
 *
 * Use cases:
 * - Engine sounds (RPM-based crossfade)
 * - Intensity-based music (calm → medium → intense)
 * - Distance-based ambience
 * - Win tier celebration sounds
 */

import type { BusId } from './types';

// ============ TYPES ============

export type BlendCurveType = 'linear' | 'equal-power' | 'exponential' | 'logarithmic' | 'custom';

export interface BlendTrack {
  /** Unique track ID */
  id: string;
  /** Sound asset ID to play */
  assetId: string;
  /** Bus to play on */
  bus?: BusId;
  /** Base volume (0-1) */
  baseVolume?: number;
  /** Blend start point (0-1 normalized) */
  blendStart: number;
  /** Blend end point (0-1 normalized) */
  blendEnd: number;
  /** Fade in range (parameter units) */
  fadeInRange?: number;
  /** Fade out range (parameter units) */
  fadeOutRange?: number;
  /** Custom volume curve keyframes (optional) */
  volumeCurve?: Array<{ position: number; volume: number }>;
  /** Loop this track */
  loop?: boolean;
}

export interface BlendContainer {
  /** Unique container ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Tracks in this container */
  tracks: BlendTrack[];
  /** Default crossfade curve type */
  curveType?: BlendCurveType;
  /** Current parameter value (0-1) */
  currentValue?: number;
  /** Smoothing time for parameter changes (ms) */
  smoothingMs?: number;
  /** Auto-start all tracks when container starts */
  autoStart?: boolean;
}

export interface BlendContainerState {
  containerId: string;
  parameterValue: number;
  targetValue: number;
  isPlaying: boolean;
  trackVolumes: Map<string, number>;
  activeVoices: Map<string, string>; // trackId → voiceId
}

export interface BlendPlayOptions {
  /** Initial parameter value */
  initialValue?: number;
  /** Fade in time (ms) */
  fadeInMs?: number;
  /** Volume multiplier */
  volumeMultiplier?: number;
}

// ============ BLEND FUNCTIONS ============

/**
 * Calculate volume for a track at a given parameter position
 */
function calculateTrackVolume(
  track: BlendTrack,
  parameterValue: number,
  curveType: BlendCurveType
): number {
  const { blendStart, blendEnd, fadeInRange = 0.1, fadeOutRange = 0.1 } = track;
  const baseVolume = track.baseVolume ?? 1.0;

  // Check if parameter is in range
  if (parameterValue < blendStart - fadeInRange || parameterValue > blendEnd + fadeOutRange) {
    return 0;
  }

  let volume = baseVolume;

  // Fade in region
  if (parameterValue < blendStart) {
    const fadeProgress = (parameterValue - (blendStart - fadeInRange)) / fadeInRange;
    volume = baseVolume * applyCurve(fadeProgress, curveType);
  }
  // Fade out region
  else if (parameterValue > blendEnd) {
    const fadeProgress = 1 - (parameterValue - blendEnd) / fadeOutRange;
    volume = baseVolume * applyCurve(fadeProgress, curveType);
  }
  // Full volume region
  else {
    volume = baseVolume;
  }

  // Apply custom curve if defined
  if (track.volumeCurve && track.volumeCurve.length >= 2) {
    volume *= interpolateCurve(track.volumeCurve, parameterValue);
  }

  return Math.max(0, Math.min(1, volume));
}

/**
 * Apply curve function to a 0-1 value
 */
function applyCurve(t: number, curveType: BlendCurveType): number {
  t = Math.max(0, Math.min(1, t));

  switch (curveType) {
    case 'linear':
      return t;

    case 'equal-power':
      // Equal power crossfade (constant loudness)
      return Math.sqrt(t);

    case 'exponential':
      return t * t * t;

    case 'logarithmic':
      return 1 - Math.pow(1 - t, 3);

    case 'custom':
      return t; // Custom handled separately

    default:
      return t;
  }
}

/**
 * Interpolate a custom volume curve
 */
function interpolateCurve(
  curve: Array<{ position: number; volume: number }>,
  position: number
): number {
  if (curve.length === 0) return 1;
  if (curve.length === 1) return curve[0].volume;

  // Find surrounding keyframes
  let prevIndex = 0;
  for (let i = 0; i < curve.length - 1; i++) {
    if (curve[i + 1].position > position) {
      prevIndex = i;
      break;
    }
    prevIndex = i;
  }

  const prev = curve[prevIndex];
  const next = curve[Math.min(prevIndex + 1, curve.length - 1)];

  if (prev.position === next.position) {
    return prev.volume;
  }

  const t = (position - prev.position) / (next.position - prev.position);
  return prev.volume + (next.volume - prev.volume) * t;
}

// ============ BLEND CONTAINER MANAGER ============

export class BlendContainerManager {
  private containers: Map<string, BlendContainer> = new Map();
  private states: Map<string, BlendContainerState> = new Map();
  private smoothingTimers: Map<string, number> = new Map();
  private playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null;
  private stopCallback: (voiceId: string) => void;
  private setVolumeCallback: (voiceId: string, volume: number) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null,
    stopCallback: (voiceId: string) => void,
    setVolumeCallback: (voiceId: string, volume: number) => void,
    containers?: BlendContainer[]
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.setVolumeCallback = setVolumeCallback;

    // Register default containers
    DEFAULT_BLEND_CONTAINERS.forEach(c => this.registerContainer(c));

    // Register custom containers
    if (containers) {
      containers.forEach(c => this.registerContainer(c));
    }
  }

  /**
   * Register a blend container
   */
  registerContainer(container: BlendContainer): void {
    this.containers.set(container.id, container);
  }

  /**
   * Unregister a blend container
   */
  unregisterContainer(containerId: string): void {
    this.stopContainer(containerId);
    this.containers.delete(containerId);
  }

  /**
   * Start playing a blend container
   */
  startContainer(containerId: string, options?: BlendPlayOptions): boolean {
    const container = this.containers.get(containerId);
    if (!container) {
      console.warn(`[BLEND] Container not found: ${containerId}`);
      return false;
    }

    // Stop if already playing
    if (this.states.has(containerId)) {
      this.stopContainer(containerId);
    }

    const initialValue = options?.initialValue ?? container.currentValue ?? 0;
    const volumeMultiplier = options?.volumeMultiplier ?? 1.0;
    const curveType = container.curveType ?? 'equal-power';

    // Create state
    const state: BlendContainerState = {
      containerId,
      parameterValue: initialValue,
      targetValue: initialValue,
      isPlaying: true,
      trackVolumes: new Map(),
      activeVoices: new Map(),
    };

    this.states.set(containerId, state);

    // Start all tracks
    container.tracks.forEach(track => {
      const volume = calculateTrackVolume(track, initialValue, curveType) * volumeMultiplier;
      state.trackVolumes.set(track.id, volume);

      // Only start if volume > 0 or autoStart
      if (volume > 0.001 || container.autoStart) {
        const voiceId = this.playCallback(
          track.assetId,
          track.bus ?? 'music',
          volume,
          track.loop ?? true
        );
        if (voiceId) {
          state.activeVoices.set(track.id, voiceId);
        }
      }
    });

    return true;
  }

  /**
   * Stop a blend container
   */
  stopContainer(containerId: string): void {
    const state = this.states.get(containerId);
    if (!state) return;

    // Stop all active voices
    state.activeVoices.forEach(voiceId => {
      this.stopCallback(voiceId);
    });

    // Clear timers
    const timer = this.smoothingTimers.get(containerId);
    if (timer) {
      cancelAnimationFrame(timer);
      this.smoothingTimers.delete(containerId);
    }

    state.isPlaying = false;
    this.states.delete(containerId);
  }

  /**
   * Set the blend parameter value
   */
  setParameterValue(containerId: string, value: number, immediate: boolean = false): void {
    const container = this.containers.get(containerId);
    const state = this.states.get(containerId);

    if (!container || !state) return;

    value = Math.max(0, Math.min(1, value));
    state.targetValue = value;

    if (immediate || !container.smoothingMs) {
      state.parameterValue = value;
      this.updateTrackVolumes(containerId);
    } else {
      this.startSmoothing(containerId);
    }
  }

  /**
   * Start parameter smoothing
   */
  private startSmoothing(containerId: string): void {
    // Cancel existing smoothing
    const existing = this.smoothingTimers.get(containerId);
    if (existing) {
      cancelAnimationFrame(existing);
    }

    const smooth = () => {
      const container = this.containers.get(containerId);
      const state = this.states.get(containerId);

      if (!container || !state || !state.isPlaying) {
        this.smoothingTimers.delete(containerId);
        return;
      }

      const smoothingMs = container.smoothingMs ?? 100;
      const smoothingFactor = 1 - Math.exp(-16.67 / smoothingMs); // ~60fps

      const diff = state.targetValue - state.parameterValue;
      if (Math.abs(diff) < 0.001) {
        state.parameterValue = state.targetValue;
        this.updateTrackVolumes(containerId);
        this.smoothingTimers.delete(containerId);
        return;
      }

      state.parameterValue += diff * smoothingFactor;
      this.updateTrackVolumes(containerId);

      const timer = requestAnimationFrame(smooth);
      this.smoothingTimers.set(containerId, timer);
    };

    const timer = requestAnimationFrame(smooth);
    this.smoothingTimers.set(containerId, timer);
  }

  /**
   * Update track volumes based on current parameter
   */
  private updateTrackVolumes(containerId: string): void {
    const container = this.containers.get(containerId);
    const state = this.states.get(containerId);

    if (!container || !state) return;

    const curveType = container.curveType ?? 'equal-power';

    container.tracks.forEach(track => {
      const newVolume = calculateTrackVolume(track, state.parameterValue, curveType);
      const oldVolume = state.trackVolumes.get(track.id) ?? 0;
      const voiceId = state.activeVoices.get(track.id);

      // Track needs to start
      if (newVolume > 0.001 && !voiceId) {
        const newVoiceId = this.playCallback(
          track.assetId,
          track.bus ?? 'music',
          newVolume,
          track.loop ?? true
        );
        if (newVoiceId) {
          state.activeVoices.set(track.id, newVoiceId);
        }
      }
      // Track needs to stop
      else if (newVolume < 0.001 && voiceId) {
        this.stopCallback(voiceId);
        state.activeVoices.delete(track.id);
      }
      // Track needs volume update
      else if (voiceId && Math.abs(newVolume - oldVolume) > 0.001) {
        this.setVolumeCallback(voiceId, newVolume);
      }

      state.trackVolumes.set(track.id, newVolume);
    });
  }

  /**
   * Get current parameter value
   */
  getParameterValue(containerId: string): number {
    return this.states.get(containerId)?.parameterValue ?? 0;
  }

  /**
   * Get track volumes for a container
   */
  getTrackVolumes(containerId: string): Map<string, number> {
    return this.states.get(containerId)?.trackVolumes ?? new Map();
  }

  /**
   * Check if container is playing
   */
  isPlaying(containerId: string): boolean {
    return this.states.get(containerId)?.isPlaying ?? false;
  }

  /**
   * Get all registered containers
   */
  getContainers(): BlendContainer[] {
    return Array.from(this.containers.values());
  }

  /**
   * Get a specific container
   */
  getContainer(containerId: string): BlendContainer | undefined {
    return this.containers.get(containerId);
  }

  /**
   * Stop all containers
   */
  stopAll(): void {
    this.states.forEach((_, containerId) => {
      this.stopContainer(containerId);
    });
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

export const DEFAULT_BLEND_CONTAINERS: BlendContainer[] = [
  {
    id: 'music_intensity',
    name: 'Music Intensity',
    description: 'Three-layer intensity blend for base game music',
    curveType: 'equal-power',
    smoothingMs: 500,
    autoStart: true,
    tracks: [
      {
        id: 'calm',
        assetId: 'music_base_calm',
        bus: 'music',
        blendStart: 0,
        blendEnd: 0.3,
        fadeOutRange: 0.2,
        loop: true,
      },
      {
        id: 'medium',
        assetId: 'music_base_medium',
        bus: 'music',
        blendStart: 0.2,
        blendEnd: 0.7,
        fadeInRange: 0.2,
        fadeOutRange: 0.2,
        loop: true,
      },
      {
        id: 'intense',
        assetId: 'music_base_intense',
        bus: 'music',
        blendStart: 0.6,
        blendEnd: 1.0,
        fadeInRange: 0.2,
        loop: true,
      },
    ],
  },
  {
    id: 'win_tier',
    name: 'Win Tier Celebration',
    description: 'Blend between win celebration tiers',
    curveType: 'linear',
    smoothingMs: 100,
    tracks: [
      {
        id: 'small_win',
        assetId: 'win_small_loop',
        bus: 'music',
        blendStart: 0,
        blendEnd: 0.25,
        fadeOutRange: 0.1,
        loop: true,
      },
      {
        id: 'medium_win',
        assetId: 'win_medium_loop',
        bus: 'music',
        blendStart: 0.2,
        blendEnd: 0.5,
        fadeInRange: 0.1,
        fadeOutRange: 0.1,
        loop: true,
      },
      {
        id: 'big_win',
        assetId: 'win_big_loop',
        bus: 'music',
        blendStart: 0.45,
        blendEnd: 0.75,
        fadeInRange: 0.1,
        fadeOutRange: 0.1,
        loop: true,
      },
      {
        id: 'mega_win',
        assetId: 'win_mega_loop',
        bus: 'music',
        blendStart: 0.7,
        blendEnd: 1.0,
        fadeInRange: 0.1,
        loop: true,
      },
    ],
  },
  {
    id: 'anticipation_layers',
    name: 'Anticipation Intensity',
    description: 'Layered anticipation sounds based on nearness to trigger',
    curveType: 'exponential',
    smoothingMs: 200,
    tracks: [
      {
        id: 'tension_low',
        assetId: 'anticipation_tension_low',
        bus: 'sfx',
        blendStart: 0,
        blendEnd: 0.5,
        fadeOutRange: 0.15,
        loop: true,
      },
      {
        id: 'tension_high',
        assetId: 'anticipation_tension_high',
        bus: 'sfx',
        blendStart: 0.4,
        blendEnd: 1.0,
        fadeInRange: 0.15,
        loop: true,
      },
      {
        id: 'heartbeat',
        assetId: 'anticipation_heartbeat',
        bus: 'sfx',
        blendStart: 0.7,
        blendEnd: 1.0,
        fadeInRange: 0.1,
        baseVolume: 0.6,
        loop: true,
      },
    ],
  },
  {
    id: 'freespins_music',
    name: 'Free Spins Music Layers',
    description: 'Progressive free spins music intensity',
    curveType: 'equal-power',
    smoothingMs: 300,
    autoStart: true,
    tracks: [
      {
        id: 'fs_base',
        assetId: 'music_freespins_base',
        bus: 'music',
        blendStart: 0,
        blendEnd: 1.0,
        baseVolume: 0.8,
        loop: true,
      },
      {
        id: 'fs_layer1',
        assetId: 'music_freespins_layer1',
        bus: 'music',
        blendStart: 0.25,
        blendEnd: 1.0,
        fadeInRange: 0.15,
        baseVolume: 0.7,
        loop: true,
      },
      {
        id: 'fs_layer2',
        assetId: 'music_freespins_layer2',
        bus: 'music',
        blendStart: 0.5,
        blendEnd: 1.0,
        fadeInRange: 0.15,
        baseVolume: 0.7,
        loop: true,
      },
      {
        id: 'fs_climax',
        assetId: 'music_freespins_climax',
        bus: 'music',
        blendStart: 0.75,
        blendEnd: 1.0,
        fadeInRange: 0.15,
        loop: true,
      },
    ],
  },
];

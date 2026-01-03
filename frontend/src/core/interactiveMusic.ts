/**
 * Interactive Music Controller
 *
 * High-level music system for slot games combining:
 * - Horizontal layers (intensity-based mixing)
 * - Vertical segments (state-based transitions)
 * - Dynamic mixing based on game state
 * - Automatic win celebrations
 * - Feature-specific music handling
 */

import type { BusId } from './types';

// ============ TYPES ============

export type MusicState =
  | 'idle'
  | 'spinning'
  | 'anticipation'
  | 'evaluating'
  | 'win_small'
  | 'win_medium'
  | 'win_big'
  | 'win_mega'
  | 'win_epic'
  | 'freespins_intro'
  | 'freespins_main'
  | 'freespins_outro'
  | 'bonus_intro'
  | 'bonus_main'
  | 'bonus_outro'
  | 'custom';

export interface MusicLayer {
  /** Layer ID */
  id: string;
  /** Asset ID */
  assetId: string;
  /** Base volume (0-1) */
  baseVolume: number;
  /** Current volume */
  currentVolume: number;
  /** Intensity threshold (0-1) - layer plays when intensity >= this */
  intensityThreshold: number;
  /** Fade in time when activated (ms) */
  fadeInMs?: number;
  /** Fade out time when deactivated (ms) */
  fadeOutMs?: number;
  /** Is looping */
  loop: boolean;
  /** Voice ID if playing */
  voiceId?: string;
}

export interface MusicSegment {
  /** Segment ID */
  id: string;
  /** Music state this segment is for */
  state: MusicState;
  /** Layers in this segment */
  layers: MusicLayer[];
  /** BPM */
  bpm?: number;
  /** Entry cue (seconds) */
  entryCue?: number;
  /** Exit cue (seconds) */
  exitCue?: number;
  /** Transition to next segment config */
  transitionOut?: {
    fadeMs: number;
    syncToBeat: boolean;
  };
}

export interface InteractiveMusicConfig {
  /** Config ID */
  id: string;
  /** Display name */
  name: string;
  /** All segments */
  segments: MusicSegment[];
  /** Default intensity */
  defaultIntensity: number;
  /** Intensity smoothing time (ms) */
  intensitySmoothingMs: number;
  /** Auto-duck music during wins */
  autoDuckOnWin: boolean;
  /** Duck level during wins (0-1) */
  winDuckLevel: number;
}

export interface ActiveMusicState {
  currentState: MusicState;
  previousState: MusicState | null;
  currentSegment: MusicSegment | null;
  intensity: number;
  targetIntensity: number;
  isDucked: boolean;
  startTime: number;
}

// ============ INTERACTIVE MUSIC CONTROLLER ============

export class InteractiveMusicController {
  private configs: Map<string, InteractiveMusicConfig> = new Map();
  private activeConfig: InteractiveMusicConfig | null = null;
  private state: ActiveMusicState;
  private updateInterval: number | null = null;
  private _pendingStateChange: MusicState | null = null; // Reserved for beat-sync

  // Callbacks
  private playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null;
  private stopCallback: (voiceId: string, fadeMs?: number) => void;
  private setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void;
  private onStateChange?: (from: MusicState, to: MusicState) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null,
    stopCallback: (voiceId: string, fadeMs?: number) => void,
    setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void,
    onStateChange?: (from: MusicState, to: MusicState) => void,
    configs?: InteractiveMusicConfig[]
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.setVolumeCallback = setVolumeCallback;
    this.onStateChange = onStateChange;

    // Initial state
    this.state = {
      currentState: 'idle',
      previousState: null,
      currentSegment: null,
      intensity: 0.5,
      targetIntensity: 0.5,
      isDucked: false,
      startTime: performance.now(),
    };

    // Register default config
    DEFAULT_INTERACTIVE_MUSIC_CONFIGS.forEach(c => this.registerConfig(c));

    // Register custom configs
    configs?.forEach(c => this.registerConfig(c));

    this.startUpdateLoop();
  }

  /**
   * Register a music config
   */
  registerConfig(config: InteractiveMusicConfig): void {
    this.configs.set(config.id, config);
  }

  /**
   * Activate a config
   */
  activateConfig(configId: string): boolean {
    const config = this.configs.get(configId);
    if (!config) return false;

    // Stop current music
    this.stopAll();

    this.activeConfig = config;
    this.state.intensity = config.defaultIntensity;
    this.state.targetIntensity = config.defaultIntensity;

    // Start in idle state
    this.setState('idle');

    return true;
  }

  /**
   * Set music state
   */
  setState(newState: MusicState, immediate: boolean = false): boolean {
    if (!this.activeConfig) return false;
    if (this.state.currentState === newState) return true;

    // Find segment for new state
    const segment = this.activeConfig.segments.find(s => s.state === newState);
    if (!segment && newState !== 'custom') {
      // Fall back to idle
      return this.setState('idle', immediate);
    }

    const oldState = this.state.currentState;
    const currentSegment = this.state.currentSegment;

    // Handle transition
    if (!immediate && currentSegment?.transitionOut?.syncToBeat) {
      // Schedule state change for next beat
      this._pendingStateChange = newState;
      return true;
    }

    // Stop current segment layers
    if (currentSegment) {
      const fadeMs = currentSegment.transitionOut?.fadeMs ?? 500;
      currentSegment.layers.forEach(layer => {
        if (layer.voiceId) {
          this.stopCallback(layer.voiceId, fadeMs);
          layer.voiceId = undefined;
        }
      });
    }

    // Update state
    this.state.previousState = oldState;
    this.state.currentState = newState;
    this.state.currentSegment = segment ?? null;
    this.state.startTime = performance.now();
    this._pendingStateChange = null;

    // Start new segment layers
    if (segment) {
      segment.layers.forEach(layer => {
        const shouldPlay = this.state.intensity >= layer.intensityThreshold;
        if (shouldPlay) {
          const voiceId = this.playCallback(layer.assetId, 'music', 0, layer.loop);
          layer.voiceId = voiceId ?? undefined;
          layer.currentVolume = 0;

          // Fade in
          if (layer.voiceId) {
            const targetVol = this.calculateLayerVolume(layer);
            this.setVolumeCallback(layer.voiceId, targetVol, layer.fadeInMs ?? 500);
            layer.currentVolume = targetVol;
          }
        }
      });
    }

    // Notify
    this.onStateChange?.(oldState, newState);

    return true;
  }

  /**
   * Set music intensity (0-1)
   */
  setIntensity(intensity: number, immediate: boolean = false): void {
    this.state.targetIntensity = Math.max(0, Math.min(1, intensity));

    if (immediate) {
      this.state.intensity = this.state.targetIntensity;
      this.updateLayerVolumes();
    }
  }

  /**
   * Get current intensity
   */
  getIntensity(): number {
    return this.state.intensity;
  }

  /**
   * Duck music for wins
   */
  duck(level?: number): void {
    if (!this.activeConfig) return;

    const duckLevel = level ?? this.activeConfig.winDuckLevel ?? 0.3;
    this.state.isDucked = true;

    // Reduce all layer volumes
    this.state.currentSegment?.layers.forEach(layer => {
      if (layer.voiceId) {
        const targetVol = layer.currentVolume * duckLevel;
        this.setVolumeCallback(layer.voiceId, targetVol, 200);
      }
    });
  }

  /**
   * Unduck music
   */
  unduck(fadeMs: number = 500): void {
    this.state.isDucked = false;
    this.updateLayerVolumes(fadeMs);
  }

  /**
   * Handle win event - triggers appropriate state and ducking
   */
  handleWin(winTier: 'small' | 'medium' | 'big' | 'mega' | 'epic'): void {
    const stateMap: Record<string, MusicState> = {
      small: 'win_small',
      medium: 'win_medium',
      big: 'win_big',
      mega: 'win_mega',
      epic: 'win_epic',
    };

    this.setState(stateMap[winTier]);

    if (this.activeConfig?.autoDuckOnWin) {
      this.duck();
    }
  }

  /**
   * Handle win end - returns to previous state
   */
  handleWinEnd(): void {
    this.unduck();

    // Return to appropriate state
    const prevState = this.state.previousState;
    if (prevState && !prevState.startsWith('win_')) {
      this.setState(prevState);
    } else {
      this.setState('idle');
    }
  }

  /**
   * Handle feature start
   */
  handleFeatureStart(feature: 'freespins' | 'bonus'): void {
    this.setState(feature === 'freespins' ? 'freespins_intro' : 'bonus_intro');

    // Auto-transition to main after intro
    // Would need timing info from the asset
  }

  /**
   * Handle feature main phase
   */
  handleFeatureMain(feature: 'freespins' | 'bonus'): void {
    this.setState(feature === 'freespins' ? 'freespins_main' : 'bonus_main');
  }

  /**
   * Handle feature end
   */
  handleFeatureEnd(feature: 'freespins' | 'bonus'): void {
    this.setState(feature === 'freespins' ? 'freespins_outro' : 'bonus_outro');
  }

  /**
   * Handle spin start
   */
  handleSpinStart(): void {
    if (this.state.currentState === 'idle') {
      this.setState('spinning');
    }
  }

  /**
   * Handle spin end
   */
  handleSpinEnd(hasWin: boolean): void {
    if (!hasWin && this.state.currentState === 'spinning') {
      this.setState('idle');
    }
  }

  /**
   * Handle anticipation (near-win)
   */
  handleAnticipation(level: number): void {
    // Increase intensity based on anticipation level
    this.setIntensity(0.5 + level * 0.5);

    if (level > 0.5 && this.state.currentState !== 'anticipation') {
      this.setState('anticipation');
    }
  }

  /**
   * Calculate layer volume based on intensity
   */
  private calculateLayerVolume(layer: MusicLayer): number {
    const aboveThreshold = this.state.intensity >= layer.intensityThreshold;
    if (!aboveThreshold) return 0;

    // Calculate how far above threshold
    const range = 1 - layer.intensityThreshold;
    const position = (this.state.intensity - layer.intensityThreshold) / range;

    // Apply curve
    return layer.baseVolume * Math.min(1, position * 2);
  }

  /**
   * Update all layer volumes based on current intensity
   */
  private updateLayerVolumes(fadeMs: number = 100): void {
    if (!this.state.currentSegment) return;
    if (this.state.isDucked) return; // Don't update while ducked

    this.state.currentSegment.layers.forEach(layer => {
      const targetVol = this.calculateLayerVolume(layer);

      if (layer.voiceId) {
        if (targetVol > 0) {
          this.setVolumeCallback(layer.voiceId, targetVol, fadeMs);
          layer.currentVolume = targetVol;
        } else if (layer.currentVolume > 0) {
          // Fade out this layer
          this.setVolumeCallback(layer.voiceId, 0, layer.fadeOutMs ?? 300);
          layer.currentVolume = 0;
        }
      } else if (targetVol > 0) {
        // Need to start this layer
        const voiceId = this.playCallback(layer.assetId, 'music', 0, layer.loop);
        layer.voiceId = voiceId ?? undefined;
        if (layer.voiceId) {
          this.setVolumeCallback(layer.voiceId, targetVol, layer.fadeInMs ?? 300);
          layer.currentVolume = targetVol;
        }
      }
    });
  }

  /**
   * Update loop
   */
  private startUpdateLoop(): void {
    const update = () => {
      if (!this.activeConfig) {
        this.updateInterval = requestAnimationFrame(update);
        return;
      }

      // Smooth intensity towards target
      const smoothingMs = this.activeConfig.intensitySmoothingMs || 500;
      const delta = 16; // Approximate frame time
      const smoothingFactor = Math.min(1, delta / smoothingMs);

      if (Math.abs(this.state.intensity - this.state.targetIntensity) > 0.001) {
        this.state.intensity += (this.state.targetIntensity - this.state.intensity) * smoothingFactor;
        this.updateLayerVolumes();
      }

      // Process pending state change (reserved for beat-sync)
      if (this._pendingStateChange) {
        // TODO: Check if on beat boundary and execute
      }

      this.updateInterval = requestAnimationFrame(update);
    };

    this.updateInterval = requestAnimationFrame(update);
  }

  /**
   * Stop update loop
   */
  private stopUpdateLoop(): void {
    if (this.updateInterval !== null) {
      cancelAnimationFrame(this.updateInterval);
      this.updateInterval = null;
    }
  }

  /**
   * Stop all music
   */
  stopAll(fadeMs: number = 500): void {
    this.state.currentSegment?.layers.forEach(layer => {
      if (layer.voiceId) {
        this.stopCallback(layer.voiceId, fadeMs);
        layer.voiceId = undefined;
        layer.currentVolume = 0;
      }
    });
  }

  /**
   * Get current state
   */
  getState(): ActiveMusicState {
    return { ...this.state };
  }

  /**
   * Get available configs
   */
  getConfigs(): InteractiveMusicConfig[] {
    return Array.from(this.configs.values());
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.stopUpdateLoop();
    this.stopAll(0);
    this.configs.clear();
    this.activeConfig = null;
  }
}

// ============ DEFAULT CONFIGS ============

export const DEFAULT_INTERACTIVE_MUSIC_CONFIGS: InteractiveMusicConfig[] = [
  {
    id: 'default_slot',
    name: 'Default Slot Music',
    defaultIntensity: 0.5,
    intensitySmoothingMs: 500,
    autoDuckOnWin: true,
    winDuckLevel: 0.3,
    segments: [
      {
        id: 'idle_segment',
        state: 'idle',
        bpm: 120,
        layers: [
          {
            id: 'base_layer',
            assetId: 'music_base_layer_1',
            baseVolume: 0.8,
            currentVolume: 0,
            intensityThreshold: 0,
            fadeInMs: 1000,
            fadeOutMs: 500,
            loop: true,
          },
          {
            id: 'mid_layer',
            assetId: 'music_base_layer_2',
            baseVolume: 0.7,
            currentVolume: 0,
            intensityThreshold: 0.3,
            fadeInMs: 500,
            fadeOutMs: 500,
            loop: true,
          },
          {
            id: 'high_layer',
            assetId: 'music_base_layer_3',
            baseVolume: 0.6,
            currentVolume: 0,
            intensityThreshold: 0.6,
            fadeInMs: 300,
            fadeOutMs: 300,
            loop: true,
          },
        ],
        transitionOut: { fadeMs: 500, syncToBeat: false },
      },
      {
        id: 'spinning_segment',
        state: 'spinning',
        bpm: 120,
        layers: [
          {
            id: 'spin_base',
            assetId: 'music_spin_layer_1',
            baseVolume: 0.8,
            currentVolume: 0,
            intensityThreshold: 0,
            loop: true,
          },
          {
            id: 'spin_energy',
            assetId: 'music_spin_layer_2',
            baseVolume: 0.7,
            currentVolume: 0,
            intensityThreshold: 0.4,
            loop: true,
          },
        ],
        transitionOut: { fadeMs: 300, syncToBeat: true },
      },
      {
        id: 'anticipation_segment',
        state: 'anticipation',
        bpm: 120,
        layers: [
          {
            id: 'anticipation_base',
            assetId: 'music_anticipation',
            baseVolume: 0.9,
            currentVolume: 0,
            intensityThreshold: 0,
            loop: true,
          },
        ],
        transitionOut: { fadeMs: 200, syncToBeat: false },
      },
      {
        id: 'win_big_segment',
        state: 'win_big',
        bpm: 130,
        layers: [
          {
            id: 'win_music',
            assetId: 'music_big_win',
            baseVolume: 1.0,
            currentVolume: 0,
            intensityThreshold: 0,
            loop: false,
          },
        ],
        transitionOut: { fadeMs: 1000, syncToBeat: false },
      },
      {
        id: 'freespins_main_segment',
        state: 'freespins_main',
        bpm: 125,
        layers: [
          {
            id: 'fs_base',
            assetId: 'music_freespins_layer_1',
            baseVolume: 0.8,
            currentVolume: 0,
            intensityThreshold: 0,
            loop: true,
          },
          {
            id: 'fs_mid',
            assetId: 'music_freespins_layer_2',
            baseVolume: 0.7,
            currentVolume: 0,
            intensityThreshold: 0.3,
            loop: true,
          },
          {
            id: 'fs_high',
            assetId: 'music_freespins_layer_3',
            baseVolume: 0.6,
            currentVolume: 0,
            intensityThreshold: 0.7,
            loop: true,
          },
        ],
        transitionOut: { fadeMs: 1000, syncToBeat: true },
      },
    ],
  },
];

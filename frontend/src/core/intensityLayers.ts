/**
 * ReelForge Intensity Layer System
 *
 * Slot-specific music layering based on intensity/excitement level.
 * Crossfades between multiple pre-composed layers based on a 0-1 intensity value.
 *
 * Use cases:
 * - Base game: calm layer at 0, building at 0.5, intense at 1.0
 * - Free spins: feature layer always at high intensity
 * - Win celebrations: temporary intensity spike
 *
 * Unlike tempo-matched crossfade (for switching songs),
 * this blends SIMULTANEOUS layers that are already in sync.
 */

import type { BusId } from './types';

export interface MusicLayer {
  id: string;
  /** Sprite/asset ID to play */
  assetId: string;
  /** Intensity range where this layer is audible [min, max] */
  intensityRange: [number, number];
  /** Base volume at peak (when intensity is in sweet spot) */
  baseVolume: number;
  /** Current volume (runtime) */
  currentVolume?: number;
  /** Audio nodes (runtime) */
  source?: AudioBufferSourceNode;
  gainNode?: GainNode;
  /** Is currently playing */
  isPlaying?: boolean;
}

export interface IntensityLayerConfig {
  id: string;
  name: string;
  /** Layers ordered by intensity (calm → intense) */
  layers: MusicLayer[];
  /** Bus to route through */
  bus: BusId;
  /** Crossfade curve */
  crossfadeCurve: 'linear' | 'cosine' | 'equal-power';
  /** Default transition time in ms */
  transitionMs: number;
}

// Default slot intensity layer configs
export const DEFAULT_LAYER_CONFIGS: IntensityLayerConfig[] = [
  {
    id: 'base_game',
    name: 'Base Game Music',
    layers: [
      { id: 'calm', assetId: 'music_base_calm', intensityRange: [0, 0.4], baseVolume: 1.0 },
      { id: 'medium', assetId: 'music_base_medium', intensityRange: [0.3, 0.7], baseVolume: 1.0 },
      { id: 'intense', assetId: 'music_base_intense', intensityRange: [0.6, 1.0], baseVolume: 1.0 },
    ],
    bus: 'music',
    crossfadeCurve: 'equal-power',
    transitionMs: 500,
  },
  {
    id: 'free_spins',
    name: 'Free Spins Music',
    layers: [
      { id: 'feature', assetId: 'music_freespins', intensityRange: [0, 1.0], baseVolume: 1.0 },
    ],
    bus: 'music',
    crossfadeCurve: 'linear',
    transitionMs: 800,
  },
];

type LoadBufferCallback = (assetId: string) => Promise<AudioBuffer>;
type GetBusGainCallback = (bus: BusId) => GainNode | null;

export class IntensityLayerSystem {
  private audioContext: AudioContext;
  private configs: Map<string, IntensityLayerConfig> = new Map();
  private activeConfigId: string | null = null;
  private currentIntensity: number = 0;
  private targetIntensity: number = 0;
  private isTransitioning: boolean = false;
  private transitionAnimationFrame: number | null = null;
  private loadBuffer: LoadBufferCallback;
  private getBusGain: GetBusGainCallback;

  constructor(
    audioContext: AudioContext,
    loadBuffer: LoadBufferCallback,
    getBusGain: GetBusGainCallback,
    initialConfigs?: IntensityLayerConfig[]
  ) {
    this.audioContext = audioContext;
    this.loadBuffer = loadBuffer;
    this.getBusGain = getBusGain;

    // Register default configs
    DEFAULT_LAYER_CONFIGS.forEach(config => this.configs.set(config.id, config));

    // Add custom configs
    if (initialConfigs) {
      initialConfigs.forEach(config => this.configs.set(config.id, config));
    }
  }

  /**
   * Register a layer configuration
   */
  registerConfig(config: IntensityLayerConfig): void {
    this.configs.set(config.id, config);
  }

  /**
   * Start a layer configuration (loads and plays all layers)
   */
  async startConfig(configId: string, initialIntensity: number = 0): Promise<boolean> {
    const config = this.configs.get(configId);
    if (!config) {
      console.warn(`[IntensityLayers] Config not found: ${configId}`);
      return false;
    }

    // Stop current config if any
    if (this.activeConfigId) {
      await this.stopConfig();
    }

    const busGain = this.getBusGain(config.bus);
    if (!busGain) {
      console.warn(`[IntensityLayers] Bus gain not found: ${config.bus}`);
      return false;
    }

    // Load and start all layers
    for (const layer of config.layers) {
      try {
        const buffer = await this.loadBuffer(layer.assetId);

        const source = this.audioContext.createBufferSource();
        source.buffer = buffer;
        source.loop = true;

        const gainNode = this.audioContext.createGain();
        gainNode.gain.value = 0; // Start silent

        source.connect(gainNode);
        gainNode.connect(busGain);

        source.start(0);

        layer.source = source;
        layer.gainNode = gainNode;
        layer.currentVolume = 0;
        layer.isPlaying = true;
      } catch (err) {
        console.error(`[IntensityLayers] Failed to load layer ${layer.id}:`, err);
      }
    }

    this.activeConfigId = configId;
    this.currentIntensity = initialIntensity;
    this.targetIntensity = initialIntensity;

    // Apply initial intensity
    this.applyIntensityImmediate(initialIntensity);

    console.log(`[IntensityLayers] Started config: ${configId} at intensity ${initialIntensity}`);
    return true;
  }

  /**
   * Stop current layer configuration
   */
  async stopConfig(fadeOutMs: number = 500): Promise<void> {
    if (!this.activeConfigId) return;

    const config = this.configs.get(this.activeConfigId);
    if (!config) return;

    // Cancel any transition
    if (this.transitionAnimationFrame) {
      cancelAnimationFrame(this.transitionAnimationFrame);
      this.transitionAnimationFrame = null;
    }

    const now = this.audioContext.currentTime;
    const fadeSeconds = fadeOutMs / 1000;

    // Fade out and stop all layers
    for (const layer of config.layers) {
      if (layer.gainNode && layer.isPlaying) {
        layer.gainNode.gain.setValueAtTime(layer.gainNode.gain.value, now);
        layer.gainNode.gain.linearRampToValueAtTime(0, now + fadeSeconds);
      }
    }

    // Wait for fade then cleanup
    await new Promise(resolve => setTimeout(resolve, fadeOutMs + 50));

    for (const layer of config.layers) {
      if (layer.source) {
        try {
          layer.source.stop();
          layer.source.disconnect();
        } catch { /* ignore */ }
      }
      if (layer.gainNode) {
        layer.gainNode.disconnect();
      }
      layer.source = undefined;
      layer.gainNode = undefined;
      layer.isPlaying = false;
      layer.currentVolume = 0;
    }

    this.activeConfigId = null;
    this.currentIntensity = 0;
    this.targetIntensity = 0;
    this.isTransitioning = false;
  }

  /**
   * Set intensity with smooth transition
   */
  setIntensity(intensity: number, transitionMs?: number): void {
    if (!this.activeConfigId) return;

    const config = this.configs.get(this.activeConfigId);
    if (!config) return;

    this.targetIntensity = Math.max(0, Math.min(1, intensity));
    const duration = transitionMs ?? config.transitionMs;

    if (duration === 0) {
      this.applyIntensityImmediate(this.targetIntensity);
      return;
    }

    // Start transition animation
    if (!this.isTransitioning) {
      this.isTransitioning = true;
      this.animateIntensityTransition(duration);
    }
  }

  /**
   * Apply intensity immediately without transition
   */
  applyIntensityImmediate(intensity: number): void {
    if (!this.activeConfigId) return;

    const config = this.configs.get(this.activeConfigId);
    if (!config) return;

    this.currentIntensity = intensity;
    this.targetIntensity = intensity;

    for (const layer of config.layers) {
      if (!layer.gainNode) continue;

      const volume = this.calculateLayerVolume(layer, intensity, config.crossfadeCurve);
      layer.gainNode.gain.value = volume;
      layer.currentVolume = volume;
    }
  }

  /**
   * Calculate layer volume based on intensity
   */
  private calculateLayerVolume(
    layer: MusicLayer,
    intensity: number,
    curve: 'linear' | 'cosine' | 'equal-power'
  ): number {
    const [minI, maxI] = layer.intensityRange;

    // Outside range = silent
    if (intensity < minI || intensity > maxI) {
      // Gradual fade at edges
      const fadeRange = 0.1;
      if (intensity < minI - fadeRange || intensity > maxI + fadeRange) {
        return 0;
      }
      // In fade zone
      if (intensity < minI) {
        const t = (intensity - (minI - fadeRange)) / fadeRange;
        return this.applyCurve(t, curve) * layer.baseVolume;
      } else {
        const t = ((maxI + fadeRange) - intensity) / fadeRange;
        return this.applyCurve(t, curve) * layer.baseVolume;
      }
    }

    // In range = calculate crossfade position
    const rangeWidth = maxI - minI;
    const center = (minI + maxI) / 2;

    // Distance from center (0 = at center, 1 = at edge)
    const distFromCenter = Math.abs(intensity - center) / (rangeWidth / 2);

    // Closer to center = louder
    const volumeMultiplier = 1 - (distFromCenter * 0.3); // Max 30% reduction at edges

    return this.applyCurve(volumeMultiplier, curve) * layer.baseVolume;
  }

  /**
   * Apply curve to value
   */
  private applyCurve(t: number, curve: 'linear' | 'cosine' | 'equal-power'): number {
    switch (curve) {
      case 'linear':
        return t;
      case 'cosine':
        return (1 - Math.cos(t * Math.PI)) / 2;
      case 'equal-power':
        return Math.sqrt(t);
      default:
        return t;
    }
  }

  /**
   * Animate intensity transition
   */
  private animateIntensityTransition(durationMs: number): void {
    const startIntensity = this.currentIntensity;
    const startTime = performance.now();

    const animate = () => {
      const elapsed = performance.now() - startTime;
      const progress = Math.min(1, elapsed / durationMs);

      // Interpolate intensity
      this.currentIntensity = startIntensity + (this.targetIntensity - startIntensity) * progress;

      // Apply to layers
      this.applyIntensityImmediate(this.currentIntensity);

      if (progress < 1) {
        this.transitionAnimationFrame = requestAnimationFrame(animate);
      } else {
        this.isTransitioning = false;
        this.transitionAnimationFrame = null;
      }
    };

    this.transitionAnimationFrame = requestAnimationFrame(animate);
  }

  /**
   * Get current intensity
   */
  getCurrentIntensity(): number {
    return this.currentIntensity;
  }

  /**
   * Get active config ID
   */
  getActiveConfigId(): string | null {
    return this.activeConfigId;
  }

  /**
   * Switch to different config with crossfade
   */
  async switchConfig(newConfigId: string, crossfadeMs: number = 1000): Promise<boolean> {
    const oldIntensity = this.currentIntensity;

    // Fade out current
    if (this.activeConfigId) {
      await this.stopConfig(crossfadeMs / 2);
    }

    // Start new
    return this.startConfig(newConfigId, oldIntensity);
  }

  /**
   * Dispose and cleanup
   */
  dispose(): void {
    if (this.transitionAnimationFrame) {
      cancelAnimationFrame(this.transitionAnimationFrame);
    }
    // Immediate stop without fade
    if (this.activeConfigId) {
      const config = this.configs.get(this.activeConfigId);
      if (config) {
        for (const layer of config.layers) {
          if (layer.source) {
            try { layer.source.stop(); } catch { /* ignore */ }
          }
        }
      }
    }
    this.configs.clear();
    this.activeConfigId = null;
  }
}

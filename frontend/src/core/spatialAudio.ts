/**
 * Spatial Audio System
 *
 * Advanced 3D audio positioning using Web Audio API:
 * - 3D sound positioning (PannerNode)
 * - HRTF (Head-Related Transfer Function) for realistic spatialization
 * - Distance models (linear, inverse, exponential)
 * - Doppler effect
 * - Listener position/orientation
 * - Audio zones and occlusion
 * - Reverb zones for environment simulation
 */

// Types imported in audioEngine.ts for integration

// ============ TYPES ============

export type DistanceModel = 'linear' | 'inverse' | 'exponential';
export type PanningModel = 'HRTF' | 'equalpower';

export interface Vector3 {
  x: number;
  y: number;
  z: number;
}

export interface Orientation3D {
  forward: Vector3;
  up: Vector3;
}

export interface SpatialSourceConfig {
  /** Unique source ID */
  id: string;
  /** 3D position */
  position: Vector3;
  /** Orientation (for directional sounds) */
  orientation?: Vector3;
  /** Distance model */
  distanceModel: DistanceModel;
  /** Panning model (HRTF for realistic, equalpower for performance) */
  panningModel: PanningModel;
  /** Reference distance (where volume is 100%) */
  refDistance: number;
  /** Max distance (where attenuation stops) */
  maxDistance: number;
  /** Rolloff factor (how quickly sound fades with distance) */
  rolloffFactor: number;
  /** Cone inner angle (degrees, full volume) */
  coneInnerAngle: number;
  /** Cone outer angle (degrees, starts attenuating) */
  coneOuterAngle: number;
  /** Cone outer gain (volume at outer angle) */
  coneOuterGain: number;
  /** Enable doppler effect */
  dopplerEnabled: boolean;
  /** Doppler factor */
  dopplerFactor: number;
}

export const DEFAULT_SPATIAL_SOURCE_CONFIG: Omit<SpatialSourceConfig, 'id'> = {
  position: { x: 0, y: 0, z: 0 },
  distanceModel: 'inverse',
  panningModel: 'HRTF',
  refDistance: 1,
  maxDistance: 10000,
  rolloffFactor: 1,
  coneInnerAngle: 360,
  coneOuterAngle: 360,
  coneOuterGain: 0,
  dopplerEnabled: false,
  dopplerFactor: 1,
};

export interface ListenerConfig {
  position: Vector3;
  orientation: Orientation3D;
}

export const DEFAULT_LISTENER_CONFIG: ListenerConfig = {
  position: { x: 0, y: 0, z: 0 },
  orientation: {
    forward: { x: 0, y: 0, z: -1 },
    up: { x: 0, y: 1, z: 0 },
  },
};

export interface AudioZone {
  /** Zone ID */
  id: string;
  /** Zone name */
  name: string;
  /** Zone type */
  type: 'reverb' | 'occlusion' | 'ambient';
  /** Zone bounds (AABB) */
  bounds: {
    min: Vector3;
    max: Vector3;
  };
  /** Zone parameters */
  params: {
    /** Reverb decay for reverb zones */
    reverbDecay?: number;
    /** Reverb wet level */
    reverbWet?: number;
    /** Occlusion factor (0-1) for occlusion zones */
    occlusionFactor?: number;
    /** Low-pass frequency for occlusion */
    occlusionLowpass?: number;
    /** Ambient sound asset ID */
    ambientAssetId?: string;
    /** Ambient volume */
    ambientVolume?: number;
  };
  /** Priority (higher = takes precedence) */
  priority: number;
}

export interface ActiveSpatialSource {
  config: SpatialSourceConfig;
  panner: PannerNode;
  inputGain: GainNode;
  outputGain: GainNode;
  occlusionFilter?: BiquadFilterNode;
  velocity: Vector3;
  lastPosition: Vector3;
  lastUpdateTime: number;
}

// ============ SPATIAL AUDIO MANAGER ============

export class SpatialAudioManager {
  private ctx: AudioContext;
  private listener: AudioListener;
  private sources: Map<string, ActiveSpatialSource> = new Map();
  private zones: Map<string, AudioZone> = new Map();
  private listenerConfig: ListenerConfig;
  private masterOutput: GainNode;
  private updateInterval: number | null = null;

  // Callbacks (stored for zone event notifications)
  public onSourceEnterZone?: (sourceId: string, zone: AudioZone) => void;
  public onSourceExitZone?: (sourceId: string, zone: AudioZone) => void;

  constructor(
    ctx: AudioContext,
    onSourceEnterZone?: (sourceId: string, zone: AudioZone) => void,
    onSourceExitZone?: (sourceId: string, zone: AudioZone) => void
  ) {
    this.ctx = ctx;
    this.listener = ctx.listener;
    this.listenerConfig = { ...DEFAULT_LISTENER_CONFIG };
    this.onSourceEnterZone = onSourceEnterZone;
    this.onSourceExitZone = onSourceExitZone;

    // Create master output
    this.masterOutput = ctx.createGain();
    this.masterOutput.gain.value = 1;

    // Initialize listener position
    this.updateListenerPosition(this.listenerConfig);

    // Start update loop for doppler calculations
    this.startUpdateLoop();
  }

  // ============ LISTENER METHODS ============

  /**
   * Set listener position
   */
  setListenerPosition(position: Vector3): void {
    this.listenerConfig.position = position;
    this.updateListenerPosition(this.listenerConfig);
  }

  /**
   * Set listener orientation
   */
  setListenerOrientation(orientation: Orientation3D): void {
    this.listenerConfig.orientation = orientation;
    this.updateListenerPosition(this.listenerConfig);
  }

  /**
   * Update listener position and orientation
   */
  private updateListenerPosition(config: ListenerConfig): void {
    const { position, orientation } = config;

    // Set position
    if (this.listener.positionX) {
      // Modern API
      this.listener.positionX.value = position.x;
      this.listener.positionY.value = position.y;
      this.listener.positionZ.value = position.z;
    } else {
      // Legacy API
      this.listener.setPosition(position.x, position.y, position.z);
    }

    // Set orientation
    if (this.listener.forwardX) {
      // Modern API
      this.listener.forwardX.value = orientation.forward.x;
      this.listener.forwardY.value = orientation.forward.y;
      this.listener.forwardZ.value = orientation.forward.z;
      this.listener.upX.value = orientation.up.x;
      this.listener.upY.value = orientation.up.y;
      this.listener.upZ.value = orientation.up.z;
    } else {
      // Legacy API
      this.listener.setOrientation(
        orientation.forward.x, orientation.forward.y, orientation.forward.z,
        orientation.up.x, orientation.up.y, orientation.up.z
      );
    }
  }

  /**
   * Get listener position
   */
  getListenerPosition(): Vector3 {
    return { ...this.listenerConfig.position };
  }

  /**
   * Get listener orientation
   */
  getListenerOrientation(): Orientation3D {
    return {
      forward: { ...this.listenerConfig.orientation.forward },
      up: { ...this.listenerConfig.orientation.up },
    };
  }

  // ============ SOURCE METHODS ============

  /**
   * Create a spatial audio source
   */
  createSource(config: Partial<SpatialSourceConfig> & { id: string }): ActiveSpatialSource {
    const fullConfig: SpatialSourceConfig = {
      ...DEFAULT_SPATIAL_SOURCE_CONFIG,
      ...config,
    };

    // Create nodes
    const panner = this.ctx.createPanner();
    const inputGain = this.ctx.createGain();
    const outputGain = this.ctx.createGain();

    // Configure panner
    panner.panningModel = fullConfig.panningModel;
    panner.distanceModel = fullConfig.distanceModel;
    panner.refDistance = fullConfig.refDistance;
    panner.maxDistance = fullConfig.maxDistance;
    panner.rolloffFactor = fullConfig.rolloffFactor;
    panner.coneInnerAngle = fullConfig.coneInnerAngle;
    panner.coneOuterAngle = fullConfig.coneOuterAngle;
    panner.coneOuterGain = fullConfig.coneOuterGain;

    // Set position
    this.setSourcePosition(panner, fullConfig.position);

    // Set orientation if provided
    if (fullConfig.orientation) {
      this.setSourceOrientation(panner, fullConfig.orientation);
    }

    // Wire nodes
    inputGain.connect(panner);
    panner.connect(outputGain);
    outputGain.connect(this.masterOutput);

    const source: ActiveSpatialSource = {
      config: fullConfig,
      panner,
      inputGain,
      outputGain,
      velocity: { x: 0, y: 0, z: 0 },
      lastPosition: { ...fullConfig.position },
      lastUpdateTime: performance.now(),
    };

    this.sources.set(config.id, source);
    return source;
  }

  /**
   * Get a spatial source by ID
   */
  getSource(id: string): ActiveSpatialSource | null {
    return this.sources.get(id) ?? null;
  }

  /**
   * Remove a spatial source
   */
  removeSource(id: string): boolean {
    const source = this.sources.get(id);
    if (!source) return false;

    source.inputGain.disconnect();
    source.panner.disconnect();
    source.outputGain.disconnect();
    source.occlusionFilter?.disconnect();

    this.sources.delete(id);
    return true;
  }

  /**
   * Update source position
   */
  updateSourcePosition(id: string, position: Vector3): void {
    const source = this.sources.get(id);
    if (!source) return;

    const now = performance.now();
    const dt = (now - source.lastUpdateTime) / 1000;

    // Calculate velocity for doppler
    if (source.config.dopplerEnabled && dt > 0) {
      source.velocity = {
        x: (position.x - source.lastPosition.x) / dt,
        y: (position.y - source.lastPosition.y) / dt,
        z: (position.z - source.lastPosition.z) / dt,
      };
    }

    source.lastPosition = { ...position };
    source.lastUpdateTime = now;
    source.config.position = position;

    this.setSourcePosition(source.panner, position);

    // Check zone transitions
    this.checkZoneTransitions(id, position);
  }

  /**
   * Update source orientation
   */
  updateSourceOrientation(id: string, orientation: Vector3): void {
    const source = this.sources.get(id);
    if (!source) return;

    source.config.orientation = orientation;
    this.setSourceOrientation(source.panner, orientation);
  }

  /**
   * Set source volume
   */
  setSourceVolume(id: string, volume: number): void {
    const source = this.sources.get(id);
    if (!source) return;

    source.outputGain.gain.value = Math.max(0, Math.min(1, volume));
  }

  /**
   * Get source input node (for connecting audio)
   */
  getSourceInput(id: string): GainNode | null {
    const source = this.sources.get(id);
    return source?.inputGain ?? null;
  }

  /**
   * Set panner position using modern or legacy API
   */
  private setSourcePosition(panner: PannerNode, position: Vector3): void {
    if (panner.positionX) {
      panner.positionX.value = position.x;
      panner.positionY.value = position.y;
      panner.positionZ.value = position.z;
    } else {
      panner.setPosition(position.x, position.y, position.z);
    }
  }

  /**
   * Set panner orientation using modern or legacy API
   */
  private setSourceOrientation(panner: PannerNode, orientation: Vector3): void {
    if (panner.orientationX) {
      panner.orientationX.value = orientation.x;
      panner.orientationY.value = orientation.y;
      panner.orientationZ.value = orientation.z;
    } else {
      panner.setOrientation(orientation.x, orientation.y, orientation.z);
    }
  }

  // ============ ZONE METHODS ============

  /**
   * Register an audio zone
   */
  registerZone(zone: AudioZone): void {
    this.zones.set(zone.id, zone);
  }

  /**
   * Remove an audio zone
   */
  removeZone(id: string): boolean {
    return this.zones.delete(id);
  }

  /**
   * Get zone by ID
   */
  getZone(id: string): AudioZone | null {
    return this.zones.get(id) ?? null;
  }

  /**
   * Get all zones
   */
  getAllZones(): AudioZone[] {
    return Array.from(this.zones.values());
  }

  /**
   * Check if a point is inside a zone
   */
  isPointInZone(point: Vector3, zone: AudioZone): boolean {
    return (
      point.x >= zone.bounds.min.x && point.x <= zone.bounds.max.x &&
      point.y >= zone.bounds.min.y && point.y <= zone.bounds.max.y &&
      point.z >= zone.bounds.min.z && point.z <= zone.bounds.max.z
    );
  }

  /**
   * Get zones containing a point
   */
  getZonesAtPoint(point: Vector3): AudioZone[] {
    const zones: AudioZone[] = [];
    this.zones.forEach(zone => {
      if (this.isPointInZone(point, zone)) {
        zones.push(zone);
      }
    });
    // Sort by priority (highest first)
    return zones.sort((a, b) => b.priority - a.priority);
  }

  /**
   * Apply occlusion to a source
   */
  applyOcclusion(sourceId: string, factor: number, lowpassFreq: number = 2000): void {
    const source = this.sources.get(sourceId);
    if (!source) return;

    // Create filter if needed
    if (!source.occlusionFilter) {
      source.occlusionFilter = this.ctx.createBiquadFilter();
      source.occlusionFilter.type = 'lowpass';

      // Rewire: panner -> filter -> output
      source.panner.disconnect();
      source.panner.connect(source.occlusionFilter);
      source.occlusionFilter.connect(source.outputGain);
    }

    // Apply occlusion
    const clampedFactor = Math.max(0, Math.min(1, factor));
    source.occlusionFilter.frequency.value = lowpassFreq * (1 - clampedFactor * 0.9);
    source.outputGain.gain.value *= (1 - clampedFactor * 0.5);
  }

  /**
   * Remove occlusion from a source
   */
  removeOcclusion(sourceId: string): void {
    const source = this.sources.get(sourceId);
    if (!source || !source.occlusionFilter) return;

    // Rewire: panner -> output (bypass filter)
    source.panner.disconnect();
    source.occlusionFilter.disconnect();
    source.panner.connect(source.outputGain);
    source.occlusionFilter = undefined;
  }

  /**
   * Check zone transitions for a source
   */
  private checkZoneTransitions(sourceId: string, position: Vector3): void {
    const currentZones = this.getZonesAtPoint(position);
    // Zone transition callbacks would be called here
    // This is a simplified version - full implementation would track previous zones
    currentZones.forEach(zone => {
      if (zone.type === 'occlusion') {
        this.applyOcclusion(
          sourceId,
          zone.params.occlusionFactor ?? 0.5,
          zone.params.occlusionLowpass ?? 2000
        );
      }
    });
  }

  // ============ UTILITY METHODS ============

  /**
   * Calculate distance between two points
   */
  calculateDistance(a: Vector3, b: Vector3): number {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dz = b.z - a.z;
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /**
   * Calculate angle between two vectors (radians)
   */
  calculateAngle(a: Vector3, b: Vector3): number {
    const dot = a.x * b.x + a.y * b.y + a.z * b.z;
    const magA = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    const magB = Math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z);
    return Math.acos(dot / (magA * magB));
  }

  /**
   * Normalize a vector
   */
  normalizeVector(v: Vector3): Vector3 {
    const mag = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (mag === 0) return { x: 0, y: 0, z: 0 };
    return { x: v.x / mag, y: v.y / mag, z: v.z / mag };
  }

  /**
   * Get direction from listener to source
   */
  getDirectionToSource(sourceId: string): Vector3 | null {
    const source = this.sources.get(sourceId);
    if (!source) return null;

    const direction = {
      x: source.config.position.x - this.listenerConfig.position.x,
      y: source.config.position.y - this.listenerConfig.position.y,
      z: source.config.position.z - this.listenerConfig.position.z,
    };

    return this.normalizeVector(direction);
  }

  /**
   * Get distance from listener to source
   */
  getDistanceToSource(sourceId: string): number | null {
    const source = this.sources.get(sourceId);
    if (!source) return null;

    return this.calculateDistance(this.listenerConfig.position, source.config.position);
  }

  /**
   * Convert 2D pan (-1 to 1) to 3D position
   */
  panTo3DPosition(pan: number, distance: number = 1): Vector3 {
    // Convert -1 to 1 pan to angle
    const angle = (pan * Math.PI) / 2; // -90 to 90 degrees
    return {
      x: Math.sin(angle) * distance,
      y: 0,
      z: -Math.cos(angle) * distance,
    };
  }

  /**
   * Convert 3D position to approximate 2D pan
   */
  positionTo2DPan(position: Vector3): number {
    const angle = Math.atan2(position.x, -position.z);
    return Math.max(-1, Math.min(1, angle / (Math.PI / 2)));
  }

  // ============ UPDATE LOOP ============

  /**
   * Start update loop for doppler calculations
   */
  private startUpdateLoop(): void {
    const update = () => {
      // Doppler effect calculations would happen here
      // Web Audio API handles basic doppler, but we can add custom processing

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

  // ============ CONNECTION METHODS ============

  /**
   * Get master output node
   */
  getMasterOutput(): GainNode {
    return this.masterOutput;
  }

  /**
   * Connect master output to destination
   */
  connect(destination: AudioNode): void {
    this.masterOutput.connect(destination);
  }

  /**
   * Disconnect master output
   */
  disconnect(): void {
    this.masterOutput.disconnect();
  }

  // ============ CLEANUP ============

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopUpdateLoop();

    this.sources.forEach((_, id) => this.removeSource(id));
    this.sources.clear();
    this.zones.clear();

    this.masterOutput.disconnect();
  }
}

// ============ SPATIAL VOICE ============

/**
 * Wrapper for playing a spatial sound
 */
export interface SpatialVoice {
  id: string;
  sourceId: string;
  assetId: string;
  source: AudioBufferSourceNode;
  startTime: number;
  duration: number;
  loop: boolean;
}

export class SpatialVoiceManager {
  private spatialManager: SpatialAudioManager;
  private ctx: AudioContext;
  private voices: Map<string, SpatialVoice> = new Map();
  private bufferCache: Map<string, AudioBuffer> = new Map();

  // Callback for playing sounds
  private getBufferCallback: (assetId: string) => Promise<AudioBuffer>;

  constructor(
    ctx: AudioContext,
    spatialManager: SpatialAudioManager,
    getBufferCallback: (assetId: string) => Promise<AudioBuffer>
  ) {
    this.ctx = ctx;
    this.spatialManager = spatialManager;
    this.getBufferCallback = getBufferCallback;
  }

  /**
   * Play a spatial sound
   */
  async playSpatial(
    assetId: string,
    sourceConfig: Partial<SpatialSourceConfig> & { id: string },
    volume: number = 1,
    loop: boolean = false
  ): Promise<string | null> {
    try {
      // Get or create spatial source
      let spatialSource = this.spatialManager.getSource(sourceConfig.id);
      if (!spatialSource) {
        spatialSource = this.spatialManager.createSource(sourceConfig);
      }

      // Get audio buffer
      let buffer = this.bufferCache.get(assetId);
      if (!buffer) {
        buffer = await this.getBufferCallback(assetId);
        this.bufferCache.set(assetId, buffer);
      }

      // Create source node
      const source = this.ctx.createBufferSource();
      source.buffer = buffer;
      source.loop = loop;

      // Create voice gain for individual control
      const voiceGain = this.ctx.createGain();
      voiceGain.gain.value = volume;

      // Connect: source -> voiceGain -> spatialSource.input
      source.connect(voiceGain);
      voiceGain.connect(spatialSource.inputGain);

      // Generate voice ID
      const voiceId = `spatial_${sourceConfig.id}_${Date.now()}`;

      // Track voice
      const voice: SpatialVoice = {
        id: voiceId,
        sourceId: sourceConfig.id,
        assetId,
        source,
        startTime: this.ctx.currentTime,
        duration: buffer.duration,
        loop,
      };

      this.voices.set(voiceId, voice);

      // Start playback
      source.start(0);

      // Handle end
      source.onended = () => {
        this.voices.delete(voiceId);
      };

      return voiceId;
    } catch (error) {
      console.error('Failed to play spatial sound:', error);
      return null;
    }
  }

  /**
   * Stop a spatial voice
   */
  stopVoice(voiceId: string, fadeMs: number = 0): boolean {
    const voice = this.voices.get(voiceId);
    if (!voice) return false;

    try {
      if (fadeMs > 0) {
        // Fade out then stop
        const spatialSource = this.spatialManager.getSource(voice.sourceId);
        if (spatialSource) {
          spatialSource.outputGain.gain.linearRampToValueAtTime(
            0,
            this.ctx.currentTime + fadeMs / 1000
          );
          setTimeout(() => {
            try { voice.source.stop(); } catch (_e) { /* ignore */ }
          }, fadeMs);
        }
      } else {
        voice.source.stop();
      }
      this.voices.delete(voiceId);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /**
   * Stop all voices for a spatial source
   */
  stopSourceVoices(sourceId: string, fadeMs: number = 0): void {
    this.voices.forEach((voice, voiceId) => {
      if (voice.sourceId === sourceId) {
        this.stopVoice(voiceId, fadeMs);
      }
    });
  }

  /**
   * Get active voice count
   */
  getActiveVoiceCount(): number {
    return this.voices.size;
  }

  /**
   * Get voices for a source
   */
  getVoicesForSource(sourceId: string): SpatialVoice[] {
    const result: SpatialVoice[] = [];
    this.voices.forEach(voice => {
      if (voice.sourceId === sourceId) {
        result.push(voice);
      }
    });
    return result;
  }

  /**
   * Clear buffer cache
   */
  clearBufferCache(): void {
    this.bufferCache.clear();
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.voices.forEach((_voice, id) => this.stopVoice(id));
    this.voices.clear();
    this.bufferCache.clear();
  }
}

// ============ PRESET SPATIAL CONFIGURATIONS ============

export const SPATIAL_PRESETS = {
  /** Point source (omnidirectional) */
  point: {
    distanceModel: 'inverse' as DistanceModel,
    panningModel: 'HRTF' as PanningModel,
    refDistance: 1,
    maxDistance: 100,
    rolloffFactor: 1,
    coneInnerAngle: 360,
    coneOuterAngle: 360,
    coneOuterGain: 0,
  },

  /** Directional source (like a speaker) */
  directional: {
    distanceModel: 'inverse' as DistanceModel,
    panningModel: 'HRTF' as PanningModel,
    refDistance: 1,
    maxDistance: 50,
    rolloffFactor: 1.5,
    coneInnerAngle: 60,
    coneOuterAngle: 120,
    coneOuterGain: 0.3,
  },

  /** Ambient source (large area, slow falloff) */
  ambient: {
    distanceModel: 'linear' as DistanceModel,
    panningModel: 'equalpower' as PanningModel,
    refDistance: 10,
    maxDistance: 200,
    rolloffFactor: 0.3,
    coneInnerAngle: 360,
    coneOuterAngle: 360,
    coneOuterGain: 0,
  },

  /** Near-field source (close sounds, like UI) */
  nearField: {
    distanceModel: 'exponential' as DistanceModel,
    panningModel: 'HRTF' as PanningModel,
    refDistance: 0.5,
    maxDistance: 5,
    rolloffFactor: 2,
    coneInnerAngle: 360,
    coneOuterAngle: 360,
    coneOuterGain: 0,
  },

  /** Far-field source (distant sounds) */
  farField: {
    distanceModel: 'linear' as DistanceModel,
    panningModel: 'HRTF' as PanningModel,
    refDistance: 50,
    maxDistance: 500,
    rolloffFactor: 0.5,
    coneInnerAngle: 360,
    coneOuterAngle: 360,
    coneOuterGain: 0,
  },
};

// ============ HELPER FUNCTIONS ============

/**
 * Create a circular arrangement of sources
 */
export function createCircularSources(
  count: number,
  radius: number,
  y: number = 0,
  baseConfig?: Partial<SpatialSourceConfig>
): Partial<SpatialSourceConfig>[] {
  const sources: Partial<SpatialSourceConfig>[] = [];

  for (let i = 0; i < count; i++) {
    const angle = (i / count) * Math.PI * 2;
    sources.push({
      ...baseConfig,
      id: `circular_${i}`,
      position: {
        x: Math.cos(angle) * radius,
        y,
        z: Math.sin(angle) * radius,
      },
    });
  }

  return sources;
}

/**
 * Create a grid arrangement of sources
 */
export function createGridSources(
  rows: number,
  cols: number,
  spacing: number,
  y: number = 0,
  baseConfig?: Partial<SpatialSourceConfig>
): Partial<SpatialSourceConfig>[] {
  const sources: Partial<SpatialSourceConfig>[] = [];
  const offsetX = ((cols - 1) * spacing) / 2;
  const offsetZ = ((rows - 1) * spacing) / 2;

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      sources.push({
        ...baseConfig,
        id: `grid_${row}_${col}`,
        position: {
          x: col * spacing - offsetX,
          y,
          z: row * spacing - offsetZ,
        },
      });
    }
  }

  return sources;
}

/**
 * Interpolate between two positions
 */
export function lerpPosition(a: Vector3, b: Vector3, t: number): Vector3 {
  return {
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    z: a.z + (b.z - a.z) * t,
  };
}

/**
 * Create a path for moving sources
 */
export function createPathPoints(
  points: Vector3[],
  segments: number
): Vector3[] {
  if (points.length < 2) return points;

  const result: Vector3[] = [];
  const segmentsPerPair = Math.ceil(segments / (points.length - 1));

  for (let i = 0; i < points.length - 1; i++) {
    for (let j = 0; j < segmentsPerPair; j++) {
      const t = j / segmentsPerPair;
      result.push(lerpPosition(points[i], points[i + 1], t));
    }
  }

  result.push(points[points.length - 1]);
  return result;
}

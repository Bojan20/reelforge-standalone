// ============================================================================
// FluxForge WASM TypeScript Wrapper
// High-level API for FluxForge audio middleware in web browsers
// ============================================================================

import init, {
  FluxForgeAudio,
  AudioBus,
  VoiceStealMode,
  VoiceHandle,
  get_version,
  db_to_linear,
  linear_to_db,
  equal_power_crossfade,
} from '../pkg/rf_wasm';

// Re-export enums
export { AudioBus, VoiceStealMode };

// ============================================================================
// TYPES
// ============================================================================

export interface AudioEvent {
  id: string;
  name: string;
  stages: string[];
  layers: AudioLayer[];
  priority: number;
}

export interface AudioLayer {
  audio_path: string;
  volume: number;
  pan: number;
  delay_ms: number;
  offset_ms: number;
  bus: AudioBus;
  loop_enabled: boolean;
}

export interface RtpcDefinition {
  name: string;
  min: number;
  max: number;
  default: number;
}

export interface StateGroup {
  name: string;
  states: string[];
  default_state: string;
}

export interface FluxForgeConfig {
  maxVoices?: number;
  maxVoicesPerEvent?: number;
  voiceStealMode?: VoiceStealMode;
  autoResume?: boolean;
}

// ============================================================================
// FLUXFORGE AUDIO WRAPPER
// ============================================================================

let wasmInitialized = false;
let initPromise: Promise<void> | null = null;

/**
 * Initialize the WASM module (call once before using any features)
 */
export async function initFluxForge(): Promise<void> {
  if (wasmInitialized) return;

  if (initPromise) {
    await initPromise;
    return;
  }

  initPromise = init();
  await initPromise;
  wasmInitialized = true;
  console.log(`[FluxForge] WASM initialized, version ${get_version()}`);
}

/**
 * Main FluxForge audio manager class
 */
export class FluxForgeAudioManager {
  private audio: FluxForgeAudio | null = null;
  private config: FluxForgeConfig;
  private audioBuffers: Map<string, AudioBuffer> = new Map();
  private loadingPromises: Map<string, Promise<AudioBuffer>> = new Map();

  constructor(config: FluxForgeConfig = {}) {
    this.config = {
      maxVoices: config.maxVoices ?? 32,
      maxVoicesPerEvent: config.maxVoicesPerEvent ?? 4,
      voiceStealMode: config.voiceStealMode ?? VoiceStealMode.Oldest,
      autoResume: config.autoResume ?? true,
    };
  }

  /**
   * Initialize the audio context (must be called from user gesture)
   */
  async init(): Promise<void> {
    await initFluxForge();

    this.audio = new FluxForgeAudio();
    this.audio.init();

    // Apply config
    this.audio.set_max_voices(this.config.maxVoices!);
    this.audio.set_max_voices_per_event(this.config.maxVoicesPerEvent!);
    this.audio.set_voice_steal_mode(this.config.voiceStealMode!);

    // Auto-resume on user interaction
    if (this.config.autoResume) {
      const resumeHandler = async () => {
        await this.resume();
        document.removeEventListener('click', resumeHandler);
        document.removeEventListener('keydown', resumeHandler);
        document.removeEventListener('touchstart', resumeHandler);
      };
      document.addEventListener('click', resumeHandler);
      document.addEventListener('keydown', resumeHandler);
      document.addEventListener('touchstart', resumeHandler);
    }

    console.log('[FluxForge] Audio manager initialized');
  }

  /**
   * Resume audio context (for auto-play policy)
   */
  async resume(): Promise<void> {
    if (this.audio) {
      await this.audio.resume();
    }
  }

  /**
   * Load events from JSON string or object
   */
  loadEvents(eventsOrJson: string | AudioEvent[]): number {
    if (!this.audio) throw new Error('Not initialized');

    const json = typeof eventsOrJson === 'string'
      ? eventsOrJson
      : JSON.stringify(eventsOrJson);

    return this.audio.load_events_json(json);
  }

  /**
   * Load RTPC definitions from JSON string or object
   */
  loadRtpc(rtpcOrJson: string | RtpcDefinition[]): number {
    if (!this.audio) throw new Error('Not initialized');

    const json = typeof rtpcOrJson === 'string'
      ? rtpcOrJson
      : JSON.stringify(rtpcOrJson);

    return this.audio.load_rtpc_json(json);
  }

  /**
   * Load state groups from JSON string or object
   */
  loadStateGroups(groupsOrJson: string | StateGroup[]): number {
    if (!this.audio) throw new Error('Not initialized');

    const json = typeof groupsOrJson === 'string'
      ? groupsOrJson
      : JSON.stringify(groupsOrJson);

    return this.audio.load_state_groups_json(json);
  }

  /**
   * Preload an audio file
   */
  async preloadAudio(path: string): Promise<void> {
    if (this.audioBuffers.has(path)) return;
    if (this.loadingPromises.has(path)) {
      await this.loadingPromises.get(path);
      return;
    }

    const promise = this.loadAudioBuffer(path);
    this.loadingPromises.set(path, promise);

    const buffer = await promise;
    this.audioBuffers.set(path, buffer);
    this.loadingPromises.delete(path);
  }

  private async loadAudioBuffer(path: string): Promise<AudioBuffer> {
    const response = await fetch(path);
    const arrayBuffer = await response.arrayBuffer();

    // Note: In real implementation, would decode using AudioContext
    // For now, return a placeholder
    throw new Error('Audio buffer loading requires AudioContext integration');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYBACK
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * Play an event by ID
   */
  playEvent(eventId: string, volume: number = 1.0, pitch: number = 1.0): VoiceHandle | null {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.play_event(eventId, volume, pitch);
  }

  /**
   * Trigger a stage
   */
  triggerStage(stage: string, volume: number = 1.0): VoiceHandle | null {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.trigger_stage(stage, volume);
  }

  /**
   * Trigger reel stop by index (0-4)
   */
  triggerReelStop(reelIndex: number, volume: number = 1.0): VoiceHandle | null {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.trigger_reel_stop(reelIndex, volume);
  }

  /**
   * Stop an event
   */
  stopEvent(eventId: string, fadeTimeMs: number = 100): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.stop_event(eventId, fadeTimeMs);
  }

  /**
   * Stop a specific voice
   */
  stopVoice(voiceHandle: VoiceHandle, fadeTimeMs: number = 100): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.stop_voice(voiceHandle.id, fadeTimeMs);
  }

  /**
   * Stop all sounds
   */
  stopAll(fadeTimeMs: number = 500): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.stop_all(fadeTimeMs);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUS CONTROL
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * Set bus volume (0-2)
   */
  setBusVolume(bus: AudioBus, volume: number): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.set_bus_volume(bus, volume);
  }

  /**
   * Get bus volume
   */
  getBusVolume(bus: AudioBus): number {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.get_bus_volume(bus);
  }

  /**
   * Set bus mute
   */
  setBusMute(bus: AudioBus, mute: boolean): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.set_bus_mute(bus, mute);
  }

  /**
   * Check if bus is muted
   */
  isBusMuted(bus: AudioBus): boolean {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.is_bus_muted(bus);
  }

  /**
   * Set master volume (0-2)
   */
  setMasterVolume(volume: number): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.set_master_volume(volume);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RTPC
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * Set RTPC value
   */
  setRtpc(name: string, value: number): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.set_rtpc(name, value);
  }

  /**
   * Get RTPC value
   */
  getRtpc(name: string): number {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.get_rtpc(name);
  }

  /**
   * Get RTPC normalized (0-1)
   */
  getRtpcNormalized(name: string): number {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.get_rtpc_normalized(name);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STATE SYSTEM
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * Set state
   */
  setState(group: string, state: string): void {
    if (!this.audio) throw new Error('Not initialized');
    this.audio.set_state(group, state);
  }

  /**
   * Get current state
   */
  getState(group: string): string | null {
    if (!this.audio) throw new Error('Not initialized');
    return this.audio.get_state(group) ?? null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STATS & INFO
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * Get active voice count
   */
  get activeVoiceCount(): number {
    return this.audio?.get_active_voice_count() ?? 0;
  }

  /**
   * Get loaded event count
   */
  get eventCount(): number {
    return this.audio?.get_event_count() ?? 0;
  }

  /**
   * Get loaded RTPC count
   */
  get rtpcCount(): number {
    return this.audio?.get_rtpc_count() ?? 0;
  }

  /**
   * Check if initialized
   */
  get isInitialized(): boolean {
    return this.audio?.is_initialized() ?? false;
  }

  /**
   * Get current audio time
   */
  get currentTime(): number {
    return this.audio?.get_current_time() ?? 0;
  }

  /**
   * Get sample rate
   */
  get sampleRate(): number {
    return this.audio?.get_sample_rate() ?? 44100;
  }

  /**
   * Cleanup voices (call periodically, e.g., in requestAnimationFrame)
   */
  update(): void {
    this.audio?.cleanup_voices();
  }

  /**
   * Dispose and cleanup
   */
  dispose(): void {
    if (this.audio) {
      this.audio.dispose();
      this.audio = null;
    }
    this.audioBuffers.clear();
    this.loadingPromises.clear();
  }
}

// ============================================================================
// CONVENIENCE EXPORTS
// ============================================================================

export { get_version as getVersion };
export { db_to_linear as dbToLinear };
export { linear_to_db as linearToDb };
export { equal_power_crossfade as equalPowerCrossfade };

// Singleton instance for simple usage
let defaultManager: FluxForgeAudioManager | null = null;

/**
 * Get the default audio manager instance
 */
export function getDefaultManager(): FluxForgeAudioManager {
  if (!defaultManager) {
    defaultManager = new FluxForgeAudioManager();
  }
  return defaultManager;
}

/**
 * Initialize the default manager (convenience function)
 */
export async function initDefaultManager(config?: FluxForgeConfig): Promise<FluxForgeAudioManager> {
  const manager = config ? new FluxForgeAudioManager(config) : getDefaultManager();
  await manager.init();
  if (config) {
    defaultManager = manager;
  }
  return manager;
}

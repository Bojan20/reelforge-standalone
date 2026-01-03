/**
 * VoiceManager - Audio Voice Pooling and Limits
 *
 * Manages audio voice allocation with:
 * - Configurable voice limits
 * - Priority-based voice stealing
 * - Automatic cleanup of finished voices
 * - Voice pooling for reduced GC pressure
 *
 * @module core/VoiceManager
 */

// ============ Types ============

export interface Voice {
  id: string;
  source: AudioBufferSourceNode;
  gainNode: GainNode;
  priority: VoicePriority;
  startTime: number;
  duration: number;
  assetId: string;
  busId: string;
  isPlaying: boolean;
  onEnded?: () => void;
}

export type VoicePriority = 'critical' | 'high' | 'normal' | 'low' | 'background';

export interface VoiceConfig {
  maxVoices: number;
  maxVoicesPerBus: number;
  voiceTimeout: number; // ms
  stealingEnabled: boolean;
}

export interface VoiceManagerStats {
  activeVoices: number;
  totalAllocated: number;
  voicesStolen: number;
  voicesTimedOut: number;
}

// ============ Priority Values ============

const PRIORITY_VALUES: Record<VoicePriority, number> = {
  critical: 100,
  high: 75,
  normal: 50,
  low: 25,
  background: 0,
};

// ============ Default Config ============

export const DEFAULT_VOICE_CONFIG: VoiceConfig = {
  maxVoices: 256,
  maxVoicesPerBus: 32,
  voiceTimeout: 30000, // 30 seconds
  stealingEnabled: true,
};

// ============ Voice Manager ============

export class VoiceManager {
  private config: VoiceConfig;
  private audioContext: AudioContext;
  private voices: Map<string, Voice> = new Map();
  private voicesByBus: Map<string, Set<string>> = new Map();
  private stats: VoiceManagerStats = {
    activeVoices: 0,
    totalAllocated: 0,
    voicesStolen: 0,
    voicesTimedOut: 0,
  };
  private timeoutChecker: ReturnType<typeof setInterval> | null = null;
  private idCounter = 0;

  constructor(audioContext: AudioContext, config: Partial<VoiceConfig> = {}) {
    this.audioContext = audioContext;
    this.config = { ...DEFAULT_VOICE_CONFIG, ...config };
    this.startTimeoutChecker();
  }

  /**
   * Allocate a new voice.
   * Returns null if limits reached and no voice can be stolen.
   */
  allocate(
    buffer: AudioBuffer,
    busGainNode: GainNode,
    options: {
      assetId: string;
      busId: string;
      priority?: VoicePriority;
      gain?: number;
      loop?: boolean;
      startOffset?: number;
      duration?: number;
      onEnded?: () => void;
    }
  ): Voice | null {
    const {
      assetId,
      busId,
      priority = 'normal',
      gain = 1,
      loop = false,
      startOffset = 0,
      duration,
      onEnded,
    } = options;

    // Check bus limit
    const busVoices = this.voicesByBus.get(busId);
    if (busVoices && busVoices.size >= this.config.maxVoicesPerBus) {
      if (!this.stealVoice(busId, priority)) {
        console.warn(`[VoiceManager] Bus ${busId} at limit, cannot allocate`);
        return null;
      }
    }

    // Check global limit
    if (this.voices.size >= this.config.maxVoices) {
      if (!this.stealVoice(null, priority)) {
        console.warn(`[VoiceManager] Global limit reached, cannot allocate`);
        return null;
      }
    }

    // Create voice
    const id = `voice-${++this.idCounter}`;
    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.loop = loop;

    const gainNode = this.audioContext.createGain();
    gainNode.gain.value = gain;

    // Connect: source → gainNode → busGain
    source.connect(gainNode);
    gainNode.connect(busGainNode);

    const voice: Voice = {
      id,
      source,
      gainNode,
      priority,
      startTime: this.audioContext.currentTime,
      duration: duration || buffer.duration,
      assetId,
      busId,
      isPlaying: true,
      onEnded,
    };

    // Track voice
    this.voices.set(id, voice);
    if (!this.voicesByBus.has(busId)) {
      this.voicesByBus.set(busId, new Set());
    }
    this.voicesByBus.get(busId)!.add(id);

    // Setup end handler
    source.onended = () => {
      this.release(id);
      onEnded?.();
    };

    // Start playback
    if (duration !== undefined) {
      source.start(0, startOffset, duration);
    } else {
      source.start(0, startOffset);
    }

    this.stats.activeVoices = this.voices.size;
    this.stats.totalAllocated++;

    return voice;
  }

  /**
   * Release a voice.
   */
  release(voiceId: string, fadeTime = 0): void {
    const voice = this.voices.get(voiceId);
    if (!voice) return;

    voice.isPlaying = false;

    if (fadeTime > 0) {
      voice.gainNode.gain.setValueAtTime(
        voice.gainNode.gain.value,
        this.audioContext.currentTime
      );
      voice.gainNode.gain.linearRampToValueAtTime(
        0,
        this.audioContext.currentTime + fadeTime
      );

      setTimeout(() => this.cleanup(voice), fadeTime * 1000 + 50);
    } else {
      this.cleanup(voice);
    }
  }

  /**
   * Release all voices for an asset.
   */
  releaseAsset(assetId: string, fadeTime = 0): void {
    for (const [id, voice] of this.voices) {
      if (voice.assetId === assetId) {
        this.release(id, fadeTime);
      }
    }
  }

  /**
   * Release all voices on a bus.
   */
  releaseBus(busId: string, fadeTime = 0): void {
    const busVoices = this.voicesByBus.get(busId);
    if (!busVoices) return;

    for (const id of Array.from(busVoices)) {
      this.release(id, fadeTime);
    }
  }

  /**
   * Release all voices.
   */
  releaseAll(fadeTime = 0): void {
    for (const id of Array.from(this.voices.keys())) {
      this.release(id, fadeTime);
    }
  }

  /**
   * Get current stats.
   */
  getStats(): VoiceManagerStats {
    return { ...this.stats, activeVoices: this.voices.size };
  }

  /**
   * Get voice count.
   */
  getVoiceCount(): number {
    return this.voices.size;
  }

  /**
   * Get voices for a bus.
   */
  getVoicesForBus(busId: string): Voice[] {
    const busVoices = this.voicesByBus.get(busId);
    if (!busVoices) return [];

    return Array.from(busVoices)
      .map(id => this.voices.get(id))
      .filter((v): v is Voice => v !== undefined);
  }

  /**
   * Update configuration.
   */
  setConfig(updates: Partial<VoiceConfig>): void {
    Object.assign(this.config, updates);
  }

  /**
   * Dispose the manager.
   */
  dispose(): void {
    this.releaseAll(0);
    if (this.timeoutChecker) {
      clearInterval(this.timeoutChecker);
      this.timeoutChecker = null;
    }
  }

  // ============ Private Methods ============

  private cleanup(voice: Voice): void {
    try {
      voice.source.stop();
      voice.source.disconnect();
      voice.gainNode.disconnect();
    } catch {
      // Already stopped
    }

    this.voices.delete(voice.id);
    const busVoices = this.voicesByBus.get(voice.busId);
    if (busVoices) {
      busVoices.delete(voice.id);
      if (busVoices.size === 0) {
        this.voicesByBus.delete(voice.busId);
      }
    }

    this.stats.activeVoices = this.voices.size;
  }

  private stealVoice(preferBusId: string | null, newPriority: VoicePriority): boolean {
    if (!this.config.stealingEnabled) return false;

    const newPriorityValue = PRIORITY_VALUES[newPriority];

    // Find candidate voices to steal
    let candidates: Voice[] = [];

    if (preferBusId) {
      const busVoices = this.voicesByBus.get(preferBusId);
      if (busVoices) {
        candidates = Array.from(busVoices)
          .map(id => this.voices.get(id))
          .filter((v): v is Voice => v !== undefined);
      }
    } else {
      candidates = Array.from(this.voices.values());
    }

    // Sort by priority (lowest first), then by age (oldest first)
    candidates.sort((a, b) => {
      const priorityDiff = PRIORITY_VALUES[a.priority] - PRIORITY_VALUES[b.priority];
      if (priorityDiff !== 0) return priorityDiff;
      return a.startTime - b.startTime;
    });

    // Find a voice with lower priority
    const victim = candidates.find(v =>
      PRIORITY_VALUES[v.priority] < newPriorityValue
    );

    if (victim) {
      this.release(victim.id, 0.01); // Quick fade
      this.stats.voicesStolen++;
      return true;
    }

    return false;
  }

  private startTimeoutChecker(): void {
    this.timeoutChecker = setInterval(() => {
      const now = this.audioContext.currentTime;
      const timeoutSec = this.config.voiceTimeout / 1000;

      for (const [id, voice] of this.voices) {
        const elapsed = now - voice.startTime;
        if (!voice.source.loop && elapsed > voice.duration + 1) {
          // Voice should have ended
          this.cleanup(voice);
          this.stats.voicesTimedOut++;
        } else if (elapsed > timeoutSec) {
          // Voice exceeded timeout
          console.warn(`[VoiceManager] Voice ${id} timed out after ${timeoutSec}s`);
          this.release(id, 0.1);
          this.stats.voicesTimedOut++;
        }
      }
    }, 5000); // Check every 5 seconds
  }
}

// ============ Singleton Instance ============

let globalVoiceManager: VoiceManager | null = null;

export function getVoiceManager(audioContext: AudioContext): VoiceManager {
  if (!globalVoiceManager) {
    globalVoiceManager = new VoiceManager(audioContext);
  }
  return globalVoiceManager;
}

export function disposeVoiceManager(): void {
  if (globalVoiceManager) {
    globalVoiceManager.dispose();
    globalVoiceManager = null;
  }
}

export default VoiceManager;

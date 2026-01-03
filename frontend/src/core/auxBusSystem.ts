/**
 * Aux Send/Return Bus System
 *
 * Professional aux bus routing for shared effects:
 * - Multiple aux buses (reverb, delay, etc.)
 * - Pre/post fader sends
 * - Per-voice send levels
 * - Aux bus effect chains
 * - Wet/dry control
 */

import type { BusId } from './types';

// ============ TYPES ============

export type SendPosition = 'pre-fader' | 'post-fader';

export interface AuxSend {
  /** Source voice ID */
  voiceId: string;
  /** Aux bus target */
  auxBusId: string;
  /** Send level (0-1) */
  level: number;
  /** Pre or post fader */
  position: SendPosition;
  /** Send gain node */
  gainNode: GainNode;
}

export interface AuxBusConfig {
  /** Unique ID */
  id: string;
  /** Display name */
  name: string;
  /** Output volume (0-1) */
  volume: number;
  /** Mute state */
  muted: boolean;
  /** Solo state */
  soloed: boolean;
  /** Panning (-1 to 1) */
  pan: number;
  /** Output destination bus */
  outputBus: BusId;
}

export interface AuxBus {
  /** Configuration */
  config: AuxBusConfig;
  /** Input gain node (receives sends) */
  inputNode: GainNode;
  /** Effect chain nodes */
  effectNodes: AudioNode[];
  /** Output gain node */
  outputNode: GainNode;
  /** Panner node */
  pannerNode: StereoPannerNode;
  /** Active sends to this bus */
  sends: Map<string, AuxSend>;
  /** Metering analyzer */
  analyzer: AnalyserNode;
}

export interface VoiceSendConfig {
  /** Voice ID */
  voiceId: string;
  /** Voice source node (pre-fader tap point) */
  sourceNode: AudioNode;
  /** Voice gain node (post-fader tap point) */
  gainNode: GainNode;
}

// ============ AUX BUS MANAGER ============

export class AuxBusManager {
  private ctx: AudioContext;
  private auxBuses: Map<string, AuxBus> = new Map();
  private sends: Map<string, AuxSend[]> = new Map(); // voiceId → sends
  private voiceConfigs: Map<string, VoiceSendConfig> = new Map();
  private masterOutput: AudioNode;
  private busOutputs: Map<BusId, GainNode> = new Map();

  // Solo state management
  private anySoloed: boolean = false;

  constructor(
    ctx: AudioContext,
    masterOutput: AudioNode,
    busOutputs?: Map<BusId, GainNode>
  ) {
    this.ctx = ctx;
    this.masterOutput = masterOutput;
    if (busOutputs) {
      this.busOutputs = busOutputs;
    }
  }

  // ============ AUX BUS CREATION ============

  /**
   * Create an aux bus
   */
  createAuxBus(config: Partial<AuxBusConfig> & { id: string; name: string }): AuxBus {
    if (this.auxBuses.has(config.id)) {
      throw new Error(`Aux bus already exists: ${config.id}`);
    }

    const fullConfig: AuxBusConfig = {
      volume: 1,
      muted: false,
      soloed: false,
      pan: 0,
      outputBus: 'master',
      ...config,
    };

    // Create nodes
    const inputNode = this.ctx.createGain();
    const outputNode = this.ctx.createGain();
    const pannerNode = this.ctx.createStereoPanner();
    const analyzer = this.ctx.createAnalyser();
    analyzer.fftSize = 256;

    // Wire nodes: input → (effects) → panner → output → analyzer → destination
    inputNode.connect(pannerNode);
    pannerNode.connect(outputNode);
    outputNode.connect(analyzer);

    // Connect to destination bus
    const destination = this.busOutputs.get(fullConfig.outputBus) ?? this.masterOutput;
    analyzer.connect(destination);

    // Apply initial settings
    outputNode.gain.value = fullConfig.volume;
    pannerNode.pan.value = fullConfig.pan;

    const auxBus: AuxBus = {
      config: fullConfig,
      inputNode,
      effectNodes: [],
      outputNode,
      pannerNode,
      sends: new Map(),
      analyzer,
    };

    this.auxBuses.set(config.id, auxBus);
    return auxBus;
  }

  /**
   * Remove an aux bus
   */
  removeAuxBus(auxBusId: string): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    // Remove all sends to this bus
    bus.sends.forEach((send) => {
      this.removeSend(send.voiceId, auxBusId);
    });

    // Disconnect nodes
    bus.inputNode.disconnect();
    bus.outputNode.disconnect();
    bus.pannerNode.disconnect();
    bus.analyzer.disconnect();
    bus.effectNodes.forEach(node => node.disconnect());

    this.auxBuses.delete(auxBusId);
    this.updateSoloState();
  }

  /**
   * Get aux bus by ID
   */
  getAuxBus(auxBusId: string): AuxBus | undefined {
    return this.auxBuses.get(auxBusId);
  }

  /**
   * Get all aux buses
   */
  getAllAuxBuses(): AuxBus[] {
    return Array.from(this.auxBuses.values());
  }

  // ============ EFFECT CHAIN ============

  /**
   * Insert effect into aux bus chain
   */
  insertEffect(auxBusId: string, effect: AudioNode, index?: number): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    // Disconnect current chain
    bus.inputNode.disconnect();
    bus.effectNodes.forEach(node => node.disconnect());

    // Insert at index or end
    const insertIndex = index ?? bus.effectNodes.length;
    bus.effectNodes.splice(insertIndex, 0, effect);

    // Rebuild chain
    this.rebuildEffectChain(bus);
  }

  /**
   * Remove effect from aux bus chain
   */
  removeEffect(auxBusId: string, effectIndex: number): AudioNode | null {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus || effectIndex < 0 || effectIndex >= bus.effectNodes.length) return null;

    // Disconnect current chain
    bus.inputNode.disconnect();
    bus.effectNodes.forEach(node => node.disconnect());

    // Remove effect
    const [removed] = bus.effectNodes.splice(effectIndex, 1);

    // Rebuild chain
    this.rebuildEffectChain(bus);

    return removed;
  }

  /**
   * Rebuild effect chain after modification
   */
  private rebuildEffectChain(bus: AuxBus): void {
    if (bus.effectNodes.length === 0) {
      // Direct connection
      bus.inputNode.connect(bus.pannerNode);
    } else {
      // Chain through effects
      bus.inputNode.connect(bus.effectNodes[0]);
      for (let i = 0; i < bus.effectNodes.length - 1; i++) {
        bus.effectNodes[i].connect(bus.effectNodes[i + 1]);
      }
      bus.effectNodes[bus.effectNodes.length - 1].connect(bus.pannerNode);
    }
  }

  // ============ SEND MANAGEMENT ============

  /**
   * Register a voice for send capability
   */
  registerVoice(config: VoiceSendConfig): void {
    this.voiceConfigs.set(config.voiceId, config);
    this.sends.set(config.voiceId, []);
  }

  /**
   * Unregister a voice (removes all its sends)
   */
  unregisterVoice(voiceId: string): void {
    const voiceSends = this.sends.get(voiceId);
    if (voiceSends) {
      // Remove all sends for this voice
      voiceSends.forEach(send => {
        send.gainNode.disconnect();
        const bus = this.auxBuses.get(send.auxBusId);
        if (bus) {
          bus.sends.delete(`${voiceId}_${send.auxBusId}`);
        }
      });
    }
    this.sends.delete(voiceId);
    this.voiceConfigs.delete(voiceId);
  }

  /**
   * Set send level from voice to aux bus
   */
  setSend(
    voiceId: string,
    auxBusId: string,
    level: number,
    position: SendPosition = 'post-fader'
  ): void {
    const voiceConfig = this.voiceConfigs.get(voiceId);
    const bus = this.auxBuses.get(auxBusId);

    if (!voiceConfig || !bus) {
      console.warn(`Cannot create send: voice=${voiceId}, bus=${auxBusId}`);
      return;
    }

    const sendId = `${voiceId}_${auxBusId}`;
    let send = bus.sends.get(sendId);

    if (!send) {
      // Create new send
      const gainNode = this.ctx.createGain();
      gainNode.gain.value = level;

      // Connect from appropriate tap point
      const tapPoint = position === 'pre-fader'
        ? voiceConfig.sourceNode
        : voiceConfig.gainNode;
      tapPoint.connect(gainNode);
      gainNode.connect(bus.inputNode);

      send = {
        voiceId,
        auxBusId,
        level,
        position,
        gainNode,
      };

      bus.sends.set(sendId, send);

      // Track in voice sends
      const voiceSends = this.sends.get(voiceId) ?? [];
      voiceSends.push(send);
      this.sends.set(voiceId, voiceSends);
    } else {
      // Update existing send
      send.level = level;
      send.gainNode.gain.setValueAtTime(level, this.ctx.currentTime);

      // Check if position changed
      if (send.position !== position) {
        // Reconnect to different tap point
        send.gainNode.disconnect();
        const tapPoint = position === 'pre-fader'
          ? voiceConfig.sourceNode
          : voiceConfig.gainNode;
        tapPoint.connect(send.gainNode);
        send.position = position;
      }
    }
  }

  /**
   * Remove a send
   */
  removeSend(voiceId: string, auxBusId: string): void {
    const bus = this.auxBuses.get(auxBusId);
    const sendId = `${voiceId}_${auxBusId}`;

    if (bus) {
      const send = bus.sends.get(sendId);
      if (send) {
        send.gainNode.disconnect();
        bus.sends.delete(sendId);
      }
    }

    // Remove from voice sends array
    const voiceSends = this.sends.get(voiceId);
    if (voiceSends) {
      const index = voiceSends.findIndex(s => s.auxBusId === auxBusId);
      if (index !== -1) {
        voiceSends.splice(index, 1);
      }
    }
  }

  /**
   * Get send level
   */
  getSendLevel(voiceId: string, auxBusId: string): number {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return 0;

    const sendId = `${voiceId}_${auxBusId}`;
    const send = bus.sends.get(sendId);
    return send?.level ?? 0;
  }

  /**
   * Set send position (pre/post fader)
   */
  setSendPosition(voiceId: string, auxBusId: string, position: SendPosition): void {
    const currentLevel = this.getSendLevel(voiceId, auxBusId);
    if (currentLevel > 0) {
      this.setSend(voiceId, auxBusId, currentLevel, position);
    }
  }

  /**
   * Get all sends for a voice
   */
  getVoiceSends(voiceId: string): AuxSend[] {
    return this.sends.get(voiceId) ?? [];
  }

  // ============ BUS CONTROL ============

  /**
   * Set aux bus volume
   */
  setVolume(auxBusId: string, volume: number, fadeMs: number = 0): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    bus.config.volume = volume;

    if (fadeMs > 0) {
      bus.outputNode.gain.linearRampToValueAtTime(
        volume,
        this.ctx.currentTime + fadeMs / 1000
      );
    } else {
      bus.outputNode.gain.setValueAtTime(volume, this.ctx.currentTime);
    }
  }

  /**
   * Set aux bus pan
   */
  setPan(auxBusId: string, pan: number): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    bus.config.pan = Math.max(-1, Math.min(1, pan));
    bus.pannerNode.pan.setValueAtTime(bus.config.pan, this.ctx.currentTime);
  }

  /**
   * Mute aux bus
   */
  setMuted(auxBusId: string, muted: boolean): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    bus.config.muted = muted;
    this.updateBusGain(bus);
  }

  /**
   * Solo aux bus
   */
  setSoloed(auxBusId: string, soloed: boolean): void {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return;

    bus.config.soloed = soloed;
    this.updateSoloState();
  }

  /**
   * Update solo state across all buses
   */
  private updateSoloState(): void {
    this.anySoloed = Array.from(this.auxBuses.values()).some(b => b.config.soloed);
    this.auxBuses.forEach(bus => this.updateBusGain(bus));
  }

  /**
   * Update bus gain based on mute/solo state
   */
  private updateBusGain(bus: AuxBus): void {
    let gain = bus.config.volume;

    if (bus.config.muted) {
      gain = 0;
    } else if (this.anySoloed && !bus.config.soloed) {
      gain = 0;
    }

    bus.outputNode.gain.setValueAtTime(gain, this.ctx.currentTime);
  }

  // ============ METERING ============

  /**
   * Get aux bus level (RMS)
   */
  getLevel(auxBusId: string): number {
    const bus = this.auxBuses.get(auxBusId);
    if (!bus) return 0;

    const dataArray = new Float32Array(bus.analyzer.fftSize);
    bus.analyzer.getFloatTimeDomainData(dataArray);

    // Calculate RMS
    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i] * dataArray[i];
    }
    return Math.sqrt(sum / dataArray.length);
  }

  /**
   * Get all bus levels
   */
  getAllLevels(): Map<string, number> {
    const levels = new Map<string, number>();
    this.auxBuses.forEach((_, id) => {
      levels.set(id, this.getLevel(id));
    });
    return levels;
  }

  // ============ PRESETS ============

  /**
   * Create common aux bus presets
   */
  createPreset(preset: 'reverb' | 'delay' | 'chorus'): AuxBus {
    switch (preset) {
      case 'reverb':
        return this.createAuxBus({
          id: 'aux_reverb',
          name: 'Reverb Send',
          volume: 0.5,
          outputBus: 'master',
        });

      case 'delay':
        return this.createAuxBus({
          id: 'aux_delay',
          name: 'Delay Send',
          volume: 0.3,
          outputBus: 'master',
        });

      case 'chorus':
        return this.createAuxBus({
          id: 'aux_chorus',
          name: 'Chorus Send',
          volume: 0.4,
          outputBus: 'master',
        });

      default:
        throw new Error(`Unknown preset: ${preset}`);
    }
  }

  // ============ SERIALIZATION ============

  /**
   * Export aux bus configuration
   */
  exportConfig(): string {
    const configs = Array.from(this.auxBuses.values()).map(bus => bus.config);
    return JSON.stringify(configs, null, 2);
  }

  /**
   * Import aux bus configuration
   */
  importConfig(json: string): void {
    const configs = JSON.parse(json) as AuxBusConfig[];
    configs.forEach(config => {
      if (!this.auxBuses.has(config.id)) {
        this.createAuxBus(config);
      }
    });
  }

  // ============ DISPOSAL ============

  /**
   * Dispose manager
   */
  dispose(): void {
    // Remove all buses
    const busIds = Array.from(this.auxBuses.keys());
    busIds.forEach(id => this.removeAuxBus(id));

    this.voiceConfigs.clear();
    this.sends.clear();
  }
}

// ============ PRESET AUX CONFIGURATIONS ============

export const PRESET_AUX_CONFIGS: Record<string, Omit<AuxBusConfig, 'id'>> = {
  reverb_hall: {
    name: 'Hall Reverb',
    volume: 0.4,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  reverb_room: {
    name: 'Room Reverb',
    volume: 0.5,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  reverb_plate: {
    name: 'Plate Reverb',
    volume: 0.35,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  delay_stereo: {
    name: 'Stereo Delay',
    volume: 0.3,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  delay_pingpong: {
    name: 'Ping Pong Delay',
    volume: 0.25,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  chorus: {
    name: 'Chorus',
    volume: 0.4,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
  parallel_comp: {
    name: 'Parallel Compression',
    volume: 0.5,
    muted: false,
    soloed: false,
    pan: 0,
    outputBus: 'master',
  },
};

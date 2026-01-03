/**
 * Custom Aux Bus System
 *
 * Extends the fixed bus architecture with user-defined aux buses.
 * Supports arbitrary routing, insert chains, and send/return workflows.
 *
 * Architecture:
 * ```
 * [Voice] → [Send] → [Aux Bus Input] → [Insert Chain] → [Aux Bus Output] → [Parent Bus/Master]
 *
 * Standard Buses (fixed):
 *   master, music, sfx, ambience, voice
 *
 * Custom Aux Buses (user-defined):
 *   aux:reverb, aux:delay, aux:parallel-comp, etc.
 * ```
 *
 * Use Cases:
 * - Shared reverb/delay for multiple sources
 * - Parallel compression buses
 * - Submix groups (drums, vocals, etc.)
 * - Sidechain routing
 * - Effect returns from SendReturnBus
 *
 * @module core/CustomAuxBus
 */

import type { InsertChain } from '../insert/types';
import { sendReturnBus, type SendBusConfig } from './SendReturnBus';
import { rfDebug } from './dspMetrics';
import { pluginPool } from '../plugin/PluginInstancePool';
import { getPluginDefinition } from '../plugin/pluginRegistry';
import type { PluginDSPInstance } from '../plugin/PluginDefinition';

// ============ Types ============

export type CustomAuxBusId = `aux:${string}`;

export interface CustomAuxBusConfig {
  /** Unique ID (format: "aux:name") */
  id: CustomAuxBusId;
  /** Display name */
  name: string;
  /** Output destination (standard bus or another aux) */
  outputBusId: string;
  /** Volume (0-1, default 1) */
  volume?: number;
  /** Pan (-1 to 1, default 0) */
  pan?: number;
  /** Muted state */
  muted?: boolean;
  /** Solo state (handled at mixer level) */
  solo?: boolean;
  /** Insert chain for this bus */
  insertChain?: InsertChain;
  /** Color for UI (hex) */
  color?: string;
  /** Whether this is a send/return bus (auto-created from SendReturnBus) */
  isSendReturn?: boolean;
  /** Associated SendBusConfig if this is a send/return bus */
  sendBusConfig?: SendBusConfig;
}

interface AuxBusGraph {
  id: CustomAuxBusId;
  config: CustomAuxBusConfig;
  /** Input gain node */
  inputGain: GainNode;
  /** Insert chain processing (simplified - single plugin for now) */
  insertDSP: PluginDSPInstance | null;
  insertPluginId: string | null;
  /** Output gain node (volume control) */
  outputGain: GainNode;
  /** Stereo panner */
  panner: StereoPannerNode;
  /** Connected to output */
  isConnected: boolean;
}

interface AuxBusSend {
  sourceId: string;
  busId: CustomAuxBusId;
  sendGain: GainNode;
}

// ============ Custom Aux Bus Manager ============

/**
 * Manages custom aux buses for flexible routing.
 */
class CustomAuxBusManagerClass {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private standardBuses: Map<string, GainNode> = new Map();
  private auxBuses: Map<CustomAuxBusId, AuxBusGraph> = new Map();
  private sends: Map<string, AuxBusSend[]> = new Map();

  /**
   * Initialize with AudioContext and master/standard bus references.
   */
  init(
    ctx: AudioContext,
    masterGain: GainNode,
    standardBuses?: Map<string, GainNode>
  ): void {
    this.ctx = ctx;
    this.masterGain = masterGain;

    // Store references to standard buses for routing
    if (standardBuses) {
      this.standardBuses = new Map(standardBuses);
    }

    // Ensure master is in the map
    this.standardBuses.set('master', masterGain);

    rfDebug('CustomAuxBus', 'Initialized');
  }

  /**
   * Register a standard bus for routing.
   * Called when standard buses are created.
   */
  registerStandardBus(busId: string, gainNode: GainNode): void {
    this.standardBuses.set(busId, gainNode);
    rfDebug('CustomAuxBus', `Registered standard bus: ${busId}`);
  }

  /**
   * Create a custom aux bus.
   */
  createAuxBus(config: CustomAuxBusConfig): boolean {
    if (!this.ctx || !this.masterGain) {
      rfDebug('CustomAuxBus', 'Cannot create aux bus - not initialized');
      return false;
    }

    if (this.auxBuses.has(config.id)) {
      rfDebug('CustomAuxBus', `Aux bus ${config.id} already exists`);
      return false;
    }

    // Validate output exists
    const outputNode = this.getOutputNode(config.outputBusId);
    if (!outputNode) {
      rfDebug('CustomAuxBus', `Output bus ${config.outputBusId} not found`);
      return false;
    }

    // Create bus nodes
    const inputGain = this.ctx.createGain();
    inputGain.gain.value = 1;

    const outputGain = this.ctx.createGain();
    outputGain.gain.value = config.volume ?? 1;

    const panner = this.ctx.createStereoPanner();
    panner.pan.value = config.pan ?? 0;

    // Create insert DSP if specified
    let insertDSP: PluginDSPInstance | null = null;
    let insertPluginId: string | null = null;

    if (config.insertChain?.inserts && config.insertChain.inserts.length > 0) {
      // For simplicity, use first enabled insert
      const firstInsert = config.insertChain.inserts.find(i => i.enabled);
      if (firstInsert) {
        const pluginDef = getPluginDefinition(firstInsert.pluginId);
        if (pluginDef) {
          insertDSP = pluginPool.acquire(firstInsert.pluginId, this.ctx);
          if (insertDSP && firstInsert.params) {
            insertDSP.applyParams(firstInsert.params as Record<string, number>);
          }
          insertPluginId = firstInsert.pluginId;
        }
      }
    }

    // Wire the graph
    if (insertDSP) {
      // With insert: input → insert → panner → output → destination
      inputGain.connect(insertDSP.getInputNode());
      insertDSP.connect(panner);
    } else {
      // No insert: input → panner → output
      inputGain.connect(panner);
    }

    panner.connect(outputGain);

    // Apply mute
    if (config.muted) {
      outputGain.gain.value = 0;
    }

    // Connect to output
    outputGain.connect(outputNode);

    const graph: AuxBusGraph = {
      id: config.id,
      config,
      inputGain,
      insertDSP,
      insertPluginId,
      outputGain,
      panner,
      isConnected: true,
    };

    this.auxBuses.set(config.id, graph);
    rfDebug('CustomAuxBus', `Created aux bus: ${config.id} → ${config.outputBusId}`);

    return true;
  }

  /**
   * Create an aux bus from a SendReturnBus configuration.
   * Links the send/return system with the aux bus system.
   */
  createFromSendBus(sendConfig: SendBusConfig): CustomAuxBusId | null {
    const auxId: CustomAuxBusId = `aux:${sendConfig.id}`;

    // First create the send bus
    const created = sendReturnBus.createSendBus(sendConfig);
    if (!created) {
      return null;
    }

    // Create corresponding aux bus config
    const auxConfig: CustomAuxBusConfig = {
      id: auxId,
      name: sendConfig.name,
      outputBusId: 'master',
      volume: sendConfig.returnLevel ?? 1,
      isSendReturn: true,
      sendBusConfig: sendConfig,
    };

    // Store config (actual audio is handled by SendReturnBus)
    // We just track it here for UI/management purposes
    this.auxBuses.set(auxId, {
      id: auxId,
      config: auxConfig,
      inputGain: null as unknown as GainNode, // Managed by SendReturnBus
      insertDSP: null,
      insertPluginId: null,
      outputGain: null as unknown as GainNode,
      panner: null as unknown as StereoPannerNode,
      isConnected: true,
    });

    rfDebug('CustomAuxBus', `Created aux bus from send: ${auxId}`);
    return auxId;
  }

  /**
   * Remove a custom aux bus.
   */
  removeAuxBus(busId: CustomAuxBusId): void {
    const bus = this.auxBuses.get(busId);
    if (!bus) return;

    // Remove all sends to this bus
    for (const [sourceId, sends] of this.sends) {
      const remaining = sends.filter(s => {
        if (s.busId === busId) {
          try {
            s.sendGain.disconnect();
          } catch { /* ignore */ }
          return false;
        }
        return true;
      });

      if (remaining.length > 0) {
        this.sends.set(sourceId, remaining);
      } else {
        this.sends.delete(sourceId);
      }
    }

    // If this is a send/return bus, remove from SendReturnBus too
    if (bus.config.isSendReturn && bus.config.sendBusConfig) {
      sendReturnBus.removeSendBus(bus.config.sendBusConfig.id);
    }

    // Disconnect graph
    try {
      bus.inputGain?.disconnect();
      bus.outputGain?.disconnect();
      bus.panner?.disconnect();
      if (bus.insertDSP && bus.insertPluginId) {
        pluginPool.release(bus.insertPluginId, bus.insertDSP);
      }
    } catch { /* ignore */ }

    this.auxBuses.delete(busId);
    rfDebug('CustomAuxBus', `Removed aux bus: ${busId}`);
  }

  /**
   * Create a send from a source to an aux bus.
   */
  createSend(
    sourceId: string,
    sourceNode: AudioNode,
    busId: CustomAuxBusId,
    level: number = 0.5
  ): GainNode | null {
    if (!this.ctx) return null;

    const bus = this.auxBuses.get(busId);
    if (!bus) {
      rfDebug('CustomAuxBus', `Cannot create send - aux bus ${busId} not found`);
      return null;
    }

    // If this is a send/return bus, delegate to SendReturnBus
    if (bus.config.isSendReturn && bus.config.sendBusConfig) {
      return sendReturnBus.createSend(
        sourceId,
        sourceNode,
        bus.config.sendBusConfig.id,
        level
      );
    }

    // Create send gain
    const sendGain = this.ctx.createGain();
    sendGain.gain.value = Math.max(0, Math.min(1, level));

    // Connect: source → sendGain → bus input
    sourceNode.connect(sendGain);
    sendGain.connect(bus.inputGain);

    // Track send
    const send: AuxBusSend = { sourceId, busId, sendGain };
    const existing = this.sends.get(sourceId) ?? [];
    existing.push(send);
    this.sends.set(sourceId, existing);

    rfDebug('CustomAuxBus', `Created send: ${sourceId} → ${busId} @ ${level}`);
    return sendGain;
  }

  /**
   * Remove all sends from a source.
   */
  removeSends(sourceId: string): void {
    const sends = this.sends.get(sourceId);
    if (!sends) return;

    for (const send of sends) {
      // If send/return bus, delegate
      const bus = this.auxBuses.get(send.busId);
      if (bus?.config.isSendReturn && bus.config.sendBusConfig) {
        sendReturnBus.removeSend(sourceId, bus.config.sendBusConfig.id);
      } else {
        try {
          send.sendGain.disconnect();
        } catch { /* ignore */ }
      }
    }

    this.sends.delete(sourceId);
    rfDebug('CustomAuxBus', `Removed all sends from: ${sourceId}`);
  }

  /**
   * Set aux bus volume.
   */
  setVolume(busId: CustomAuxBusId, volume: number): void {
    const bus = this.auxBuses.get(busId);
    if (!bus || !this.ctx) return;

    // If send/return, update return level
    if (bus.config.isSendReturn && bus.config.sendBusConfig) {
      sendReturnBus.setReturnLevel(bus.config.sendBusConfig.id, volume);
      bus.config.volume = volume;
      return;
    }

    const now = this.ctx.currentTime;
    bus.outputGain.gain.cancelScheduledValues(now);
    bus.outputGain.gain.setValueAtTime(bus.outputGain.gain.value, now);
    bus.outputGain.gain.linearRampToValueAtTime(
      bus.config.muted ? 0 : Math.max(0, Math.min(2, volume)),
      now + 0.01
    );
    bus.config.volume = volume;
  }

  /**
   * Set aux bus pan.
   */
  setPan(busId: CustomAuxBusId, pan: number): void {
    const bus = this.auxBuses.get(busId);
    if (!bus?.panner || !this.ctx) return;

    const now = this.ctx.currentTime;
    bus.panner.pan.cancelScheduledValues(now);
    bus.panner.pan.setValueAtTime(bus.panner.pan.value, now);
    bus.panner.pan.linearRampToValueAtTime(
      Math.max(-1, Math.min(1, pan)),
      now + 0.01
    );
    bus.config.pan = pan;
  }

  /**
   * Set aux bus mute state.
   */
  setMuted(busId: CustomAuxBusId, muted: boolean): void {
    const bus = this.auxBuses.get(busId);
    if (!bus || !this.ctx) return;

    bus.config.muted = muted;

    // If send/return, delegate
    if (bus.config.isSendReturn && bus.config.sendBusConfig) {
      sendReturnBus.setBypass(bus.config.sendBusConfig.id, muted);
      return;
    }

    const now = this.ctx.currentTime;
    const targetVolume = muted ? 0 : (bus.config.volume ?? 1);

    bus.outputGain.gain.cancelScheduledValues(now);
    bus.outputGain.gain.setValueAtTime(bus.outputGain.gain.value, now);
    bus.outputGain.gain.linearRampToValueAtTime(targetVolume, now + 0.02);
  }

  /**
   * Update insert chain on an aux bus.
   */
  updateInsertChain(busId: CustomAuxBusId, chain: InsertChain): void {
    const bus = this.auxBuses.get(busId);
    if (!bus || !this.ctx) return;

    // If send/return, update effect params
    if (bus.config.isSendReturn && bus.config.sendBusConfig) {
      const firstInsert = chain.inserts?.find(i => i.enabled);
      if (firstInsert?.params) {
        sendReturnBus.updateEffectParams(
          bus.config.sendBusConfig.id,
          firstInsert.params as Record<string, number>
        );
      }
      return;
    }

    // Release old DSP
    if (bus.insertDSP && bus.insertPluginId) {
      pluginPool.release(bus.insertPluginId, bus.insertDSP);
      bus.insertDSP = null;
      bus.insertPluginId = null;
    }

    // Create new DSP from first enabled insert
    const firstInsert = chain.inserts?.find(i => i.enabled);
    if (firstInsert) {
      const pluginDef = getPluginDefinition(firstInsert.pluginId);
      if (pluginDef) {
        bus.insertDSP = pluginPool.acquire(firstInsert.pluginId, this.ctx);
        if (bus.insertDSP && firstInsert.params) {
          bus.insertDSP.applyParams(firstInsert.params as Record<string, number>);
        }
        bus.insertPluginId = firstInsert.pluginId;
      }
    }

    // Rewire graph
    try {
      bus.inputGain.disconnect();
    } catch { /* ignore */ }

    if (bus.insertDSP) {
      bus.inputGain.connect(bus.insertDSP.getInputNode());
      bus.insertDSP.connect(bus.panner);
    } else {
      bus.inputGain.connect(bus.panner);
    }

    bus.config.insertChain = chain;
    rfDebug('CustomAuxBus', `Updated insert chain on ${busId}`);
  }

  /**
   * Get aux bus configuration.
   */
  getAuxBus(busId: CustomAuxBusId): CustomAuxBusConfig | undefined {
    return this.auxBuses.get(busId)?.config;
  }

  /**
   * Get all aux bus IDs.
   */
  getAuxBusIds(): CustomAuxBusId[] {
    return Array.from(this.auxBuses.keys());
  }

  /**
   * Get all aux bus configs.
   */
  getAllAuxBuses(): CustomAuxBusConfig[] {
    return Array.from(this.auxBuses.values()).map(b => b.config);
  }

  /**
   * Check if a bus ID is a custom aux bus.
   */
  isAuxBus(busId: string): busId is CustomAuxBusId {
    return busId.startsWith('aux:');
  }

  /**
   * Dispose all aux buses.
   */
  dispose(): void {
    // Remove all sends
    for (const sourceId of Array.from(this.sends.keys())) {
      this.removeSends(sourceId);
    }

    // Remove all aux buses
    for (const busId of Array.from(this.auxBuses.keys())) {
      this.removeAuxBus(busId);
    }

    this.standardBuses.clear();
    this.ctx = null;
    this.masterGain = null;

    rfDebug('CustomAuxBus', 'Disposed');
  }

  // ============ Private Methods ============

  private getOutputNode(busId: string): AudioNode | null {
    // Check standard buses first
    const standard = this.standardBuses.get(busId);
    if (standard) return standard;

    // Check custom aux buses (for chaining)
    if (this.isAuxBus(busId)) {
      const aux = this.auxBuses.get(busId as CustomAuxBusId);
      return aux?.inputGain ?? null;
    }

    // Fallback to master
    return this.masterGain;
  }
}

// ============ Singleton Export ============

/**
 * Global custom aux bus manager.
 */
export const customAuxBus = new CustomAuxBusManagerClass();

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    customAuxBus.dispose();
  });
}

export default customAuxBus;

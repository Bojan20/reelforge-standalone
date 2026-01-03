/**
 * Send/Return Bus Architecture
 *
 * Provides aux send/return routing for shared effects processing.
 * Classic DAW pattern: multiple sources can send to a shared effect bus,
 * which processes audio and returns it to the master.
 *
 * Signal Flow:
 * ```
 * [Voice/Bus] ──┬── [Direct] ────────────────────────┬──► [Master]
 *               │                                     │
 *               └── [Send Gain] ──► [FX Bus] ──► [Return Gain] ──┘
 * ```
 *
 * Use Cases:
 * - Shared reverb for multiple sources
 * - Delay sends
 * - Parallel compression
 * - Sidechain ducking
 *
 * @module core/SendReturnBus
 */

import type { PluginDSPInstance } from '../plugin/PluginDefinition';
import { pluginPool } from '../plugin/PluginInstancePool';
import { getPluginDefinition } from '../plugin/pluginRegistry';
import { rfDebug } from './dspMetrics';

// ============ Types ============

export type SendBusId = string;

export interface SendBusConfig {
  id: SendBusId;
  name: string;
  /** Plugin ID for the effect (e.g., 'reverb', 'delay') */
  pluginId: string;
  /** Plugin parameters */
  params?: Record<string, number>;
  /** Return level (0-1, default 1) */
  returnLevel?: number;
  /** Pre/Post fader send (default: post) */
  preFader?: boolean;
  /** Bypass the effect */
  bypassed?: boolean;
}

export interface SendConfig {
  /** Target send bus ID */
  busId: SendBusId;
  /** Send level (0-1) */
  level: number;
  /** Pre/Post fader (overrides bus default) */
  preFader?: boolean;
}

interface SendBusGraph {
  id: SendBusId;
  config: SendBusConfig;
  /** Input node where sends connect */
  inputNode: GainNode;
  /** Effect processing node */
  effectDSP: PluginDSPInstance | null;
  /** Return gain (controls wet level back to master) */
  returnGain: GainNode;
  /** Bypass dry path */
  dryGain: GainNode;
  /** Currently connected to master */
  connectedToMaster: boolean;
}

interface SendConnection {
  /** Source identifier */
  sourceId: string;
  /** Send bus target */
  busId: SendBusId;
  /** Send gain node */
  sendGain: GainNode;
  /** Source node (for reconnection) */
  sourceNode: AudioNode;
}

// ============ Send/Return Bus Manager ============

/**
 * Manages send/return buses for aux effect routing.
 */
class SendReturnBusManager {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private sendBuses: Map<SendBusId, SendBusGraph> = new Map();
  private sendConnections: Map<string, SendConnection[]> = new Map();

  /**
   * Initialize with AudioContext and master output.
   */
  init(ctx: AudioContext, masterGain: GainNode): void {
    this.ctx = ctx;
    this.masterGain = masterGain;
    pluginPool.setAudioContext(ctx);
    rfDebug('SendReturnBus', 'Initialized');
  }

  /**
   * Create a send bus with effect processing.
   */
  createSendBus(config: SendBusConfig): boolean {
    if (!this.ctx || !this.masterGain) {
      rfDebug('SendReturnBus', 'Cannot create bus - not initialized');
      return false;
    }

    if (this.sendBuses.has(config.id)) {
      rfDebug('SendReturnBus', `Bus ${config.id} already exists`);
      return false;
    }

    // Create bus input node
    const inputNode = this.ctx.createGain();
    inputNode.gain.value = 1;

    // Create return gain
    const returnGain = this.ctx.createGain();
    returnGain.gain.value = config.returnLevel ?? 1;

    // Create dry bypass path
    const dryGain = this.ctx.createGain();
    dryGain.gain.value = config.bypassed ? 1 : 0;

    // Try to create effect DSP
    let effectDSP: PluginDSPInstance | null = null;
    const pluginDef = getPluginDefinition(config.pluginId);

    if (pluginDef) {
      effectDSP = pluginPool.acquire(config.pluginId, this.ctx);
      if (effectDSP) {
        if (config.params) {
          effectDSP.applyParams(config.params);
        }
        rfDebug('SendReturnBus', `Created effect DSP for ${config.id}: ${config.pluginId}`);
      }
    }

    // Wire the graph
    if (effectDSP && !config.bypassed) {
      // Wet path: input -> effect -> return -> master
      inputNode.connect(effectDSP.getInputNode());
      effectDSP.connect(returnGain);
    } else {
      // No effect or bypassed: input -> return
      inputNode.connect(returnGain);
    }

    // Dry bypass path (for smooth bypass transitions)
    inputNode.connect(dryGain);
    dryGain.connect(returnGain);

    // Connect return to master
    returnGain.connect(this.masterGain);

    const graph: SendBusGraph = {
      id: config.id,
      config,
      inputNode,
      effectDSP,
      returnGain,
      dryGain,
      connectedToMaster: true,
    };

    this.sendBuses.set(config.id, graph);
    rfDebug('SendReturnBus', `Created send bus: ${config.id} (${config.name})`);

    return true;
  }

  /**
   * Remove a send bus.
   */
  removeSendBus(busId: SendBusId): void {
    const bus = this.sendBuses.get(busId);
    if (!bus) return;

    // Disconnect all sends to this bus
    for (const [sourceId, connections] of this.sendConnections) {
      const remaining = connections.filter(conn => {
        if (conn.busId === busId) {
          try {
            conn.sendGain.disconnect();
          } catch { /* ignore */ }
          return false;
        }
        return true;
      });

      if (remaining.length > 0) {
        this.sendConnections.set(sourceId, remaining);
      } else {
        this.sendConnections.delete(sourceId);
      }
    }

    // Disconnect bus graph
    try {
      bus.inputNode.disconnect();
      bus.returnGain.disconnect();
      bus.dryGain.disconnect();
      if (bus.effectDSP) {
        pluginPool.release(bus.config.pluginId, bus.effectDSP);
      }
    } catch { /* ignore */ }

    this.sendBuses.delete(busId);
    rfDebug('SendReturnBus', `Removed send bus: ${busId}`);
  }

  /**
   * Create a send from a source to a send bus.
   *
   * @param sourceId Unique identifier for the source
   * @param sourceNode The audio node to send from
   * @param busId Target send bus
   * @param level Send level (0-1)
   * @returns The send gain node for parameter control
   */
  createSend(
    sourceId: string,
    sourceNode: AudioNode,
    busId: SendBusId,
    level: number = 0.5
  ): GainNode | null {
    if (!this.ctx) return null;

    const bus = this.sendBuses.get(busId);
    if (!bus) {
      rfDebug('SendReturnBus', `Cannot create send - bus ${busId} not found`);
      return null;
    }

    // Create send gain
    const sendGain = this.ctx.createGain();
    sendGain.gain.value = Math.max(0, Math.min(1, level));

    // Connect: source -> sendGain -> bus input
    sourceNode.connect(sendGain);
    sendGain.connect(bus.inputNode);

    // Track connection
    const connection: SendConnection = {
      sourceId,
      busId,
      sendGain,
      sourceNode,
    };

    const existing = this.sendConnections.get(sourceId) ?? [];
    existing.push(connection);
    this.sendConnections.set(sourceId, existing);

    rfDebug('SendReturnBus', `Created send: ${sourceId} -> ${busId} @ ${level}`);
    return sendGain;
  }

  /**
   * Remove all sends from a source.
   */
  removeSends(sourceId: string): void {
    const connections = this.sendConnections.get(sourceId);
    if (!connections) return;

    for (const conn of connections) {
      try {
        conn.sendGain.disconnect();
      } catch { /* ignore */ }
    }

    this.sendConnections.delete(sourceId);
    rfDebug('SendReturnBus', `Removed all sends from: ${sourceId}`);
  }

  /**
   * Remove a specific send.
   */
  removeSend(sourceId: string, busId: SendBusId): void {
    const connections = this.sendConnections.get(sourceId);
    if (!connections) return;

    const remaining = connections.filter(conn => {
      if (conn.busId === busId) {
        try {
          conn.sendGain.disconnect();
        } catch { /* ignore */ }
        return false;
      }
      return true;
    });

    if (remaining.length > 0) {
      this.sendConnections.set(sourceId, remaining);
    } else {
      this.sendConnections.delete(sourceId);
    }
  }

  /**
   * Set send level.
   */
  setSendLevel(sourceId: string, busId: SendBusId, level: number): void {
    const connections = this.sendConnections.get(sourceId);
    if (!connections) return;

    for (const conn of connections) {
      if (conn.busId === busId && this.ctx) {
        const now = this.ctx.currentTime;
        conn.sendGain.gain.cancelScheduledValues(now);
        conn.sendGain.gain.setValueAtTime(conn.sendGain.gain.value, now);
        conn.sendGain.gain.linearRampToValueAtTime(
          Math.max(0, Math.min(1, level)),
          now + 0.01
        );
      }
    }
  }

  /**
   * Set return level for a send bus.
   */
  setReturnLevel(busId: SendBusId, level: number): void {
    const bus = this.sendBuses.get(busId);
    if (!bus || !this.ctx) return;

    const now = this.ctx.currentTime;
    bus.returnGain.gain.cancelScheduledValues(now);
    bus.returnGain.gain.setValueAtTime(bus.returnGain.gain.value, now);
    bus.returnGain.gain.linearRampToValueAtTime(
      Math.max(0, Math.min(2, level)), // Allow up to 2x for boost
      now + 0.01
    );
  }

  /**
   * Set bypass state for a send bus.
   */
  setBypass(busId: SendBusId, bypassed: boolean): void {
    const bus = this.sendBuses.get(busId);
    if (!bus || !this.ctx) return;

    const now = this.ctx.currentTime;
    bus.config.bypassed = bypassed;

    // Crossfade between wet and dry
    bus.dryGain.gain.cancelScheduledValues(now);
    bus.dryGain.gain.setValueAtTime(bus.dryGain.gain.value, now);
    bus.dryGain.gain.linearRampToValueAtTime(
      bypassed ? 1 : 0,
      now + 0.02
    );

    // Also notify effect DSP if it supports bypass
    if (bus.effectDSP?.setBypass) {
      bus.effectDSP.setBypass(bypassed);
    }
  }

  /**
   * Update effect parameters.
   */
  updateEffectParams(busId: SendBusId, params: Record<string, number>): void {
    const bus = this.sendBuses.get(busId);
    if (!bus?.effectDSP) return;

    bus.effectDSP.applyParams(params);
    bus.config.params = { ...bus.config.params, ...params };
  }

  /**
   * Get send bus config.
   */
  getSendBus(busId: SendBusId): SendBusConfig | undefined {
    return this.sendBuses.get(busId)?.config;
  }

  /**
   * Get all send bus IDs.
   */
  getSendBusIds(): SendBusId[] {
    return Array.from(this.sendBuses.keys());
  }

  /**
   * Get sends from a source.
   */
  getSends(sourceId: string): Array<{ busId: SendBusId; level: number }> {
    const connections = this.sendConnections.get(sourceId);
    if (!connections) return [];

    return connections.map(conn => ({
      busId: conn.busId,
      level: conn.sendGain.gain.value,
    }));
  }

  /**
   * Dispose all send buses.
   */
  dispose(): void {
    // Remove all sends
    for (const sourceId of Array.from(this.sendConnections.keys())) {
      this.removeSends(sourceId);
    }

    // Remove all buses
    for (const busId of Array.from(this.sendBuses.keys())) {
      this.removeSendBus(busId);
    }

    this.ctx = null;
    this.masterGain = null;
    rfDebug('SendReturnBus', 'Disposed');
  }
}

// ============ Singleton Export ============

/**
 * Global send/return bus manager.
 */
export const sendReturnBus = new SendReturnBusManager();

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    sendReturnBus.dispose();
  });
}

export default sendReturnBus;

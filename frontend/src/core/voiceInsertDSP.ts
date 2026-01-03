/**
 * ReelForge M8.5 Voice Insert DSP
 *
 * Per-voice WebAudio DSP implementation for asset insert chains.
 * Each playing voice/channel gets its own DSP chain instance.
 *
 * Signal flow (per voice):
 * [Source] → [PanNode] → [LocalGain] → [ASSET INSERTS] → [Bus Gain] → ...
 *
 * Uses click-free transitions via linearRampToValueAtTime().
 * NO PDC at asset level (out of scope for M8.5).
 *
 * Implements InsertChainHost interface (src/insert/InsertChainHost.ts)
 * for per-voice chains. Unlike Bus/Master hosts, voice chains are
 * created/disposed dynamically as sounds play.
 *
 * @see InsertChainHost - Core chain host interface
 */

import type {
  InsertChain,
  Insert,
  InsertId,
} from './masterInsertTypes';
import { dspMetrics, rfDebug } from './dspMetrics';
import { getPluginDefinition } from '../plugin/pluginRegistry';
import type { PluginDSPInstance } from '../plugin/PluginDefinition';
import { pluginPool } from '../plugin/PluginInstancePool';
import { voiceChainPool } from './VoiceChainPool';

/** Click-free bypass ramp time in seconds */
const BYPASS_RAMP_TIME = 0.01; // 10ms

/** Performance guardrail: warn if more than this many voice chains are active */
const VOICE_CHAIN_WARN_THRESHOLD = 16;

/** Single insert node graph */
interface InsertNodeGraph {
  insertId: InsertId;
  pluginId: string;
  inputGain: GainNode;
  outputGain: GainNode;
  dryGain: GainNode; // For bypass routing
  processingNodes: AudioNode[]; // Legacy nodes (unused, kept for interface compat)
  /** Plugin Framework DSP instance (for Pro plugins like vaneq, vancomp, vanlimit) */
  pluginDSP: PluginDSPInstance | null;
  enabled: boolean;
}

/** Voice chain node graph - one per playing voice */
interface VoiceChainGraph {
  voiceKey: string; // Unique key for this voice instance
  assetId: string;
  chainInput: GainNode;
  chainOutput: GainNode;
  insertGraphs: Map<InsertId, InsertNodeGraph>;
  insertOrder: InsertId[];
}

/**
 * Voice Insert DSP Processor
 *
 * Manages WebAudio node graphs for per-voice asset insert chains.
 * Each voice gets its own chain instance (no shared nodes between voices).
 */
export class VoiceInsertDSP {
  private ctx: AudioContext | null = null;
  private voiceChains: Map<string, VoiceChainGraph> = new Map();
  private assetInsertChains: Record<string, InsertChain> = {};

  /**
   * Set the AudioContext for DSP operations.
   */
  setAudioContext(ctx: AudioContext): void {
    this.ctx = ctx;
    // Set context for pools as well
    pluginPool.setAudioContext(ctx);
    voiceChainPool.setAudioContext(ctx);
  }

  /**
   * Update the asset insert chains configuration.
   * This doesn't rebuild existing voice chains - they use the chain
   * config that was active when they were created.
   */
  setAssetInsertChains(chains: Record<string, InsertChain>): void {
    this.assetInsertChains = chains;
  }

  /**
   * Check if an asset has insert chains defined.
   * Used to skip chain creation for assets without inserts.
   */
  hasAssetInserts(assetId: string): boolean {
    const chain = this.assetInsertChains[assetId];
    return chain !== undefined && chain.inserts.length > 0;
  }

  /**
   * Create a voice chain for a specific voice/asset.
   * Returns the chainOutput node that should be connected to the bus.
   *
   * @param voiceKey Unique key for this voice instance (e.g., soundId:eventId:timestamp)
   * @param assetId The asset ID (soundId) being played
   * @param sourceNode The audio source node (connects to chainInput)
   * @returns The chainOutput node to connect to bus, or null if no chain needed
   */
  createVoiceChain(
    voiceKey: string,
    assetId: string,
    sourceNode: AudioNode
  ): GainNode | null {
    if (!this.ctx) {
      rfDebug('VoiceInsertDSP', 'No AudioContext set');
      return null;
    }

    // Check if asset has inserts defined
    const chain = this.assetInsertChains[assetId];
    if (!chain || chain.inserts.length === 0) {
      // No inserts for this asset - return null, caller will connect directly to bus
      return null;
    }

    // Performance guardrail
    if (this.voiceChains.size >= VOICE_CHAIN_WARN_THRESHOLD) {
      rfDebug('VoiceInsertDSP', `Warning: ${this.voiceChains.size} active voice chains (threshold: ${VOICE_CHAIN_WARN_THRESHOLD})`);
    }

    // Acquire chain input/output nodes from pool
    const chainPair = voiceChainPool.acquireGainPair();
    if (!chainPair) {
      rfDebug('VoiceInsertDSP', 'Failed to acquire GainNode pair from pool');
      return null;
    }
    const [chainInput, chainOutput] = chainPair;

    // Create the voice chain graph
    const voiceChainGraph: VoiceChainGraph = {
      voiceKey,
      assetId,
      chainInput,
      chainOutput,
      insertGraphs: new Map(),
      insertOrder: [],
    };

    // Add inserts from the chain configuration
    for (const insert of chain.inserts) {
      const graph = this.createInsertGraph(insert);
      voiceChainGraph.insertGraphs.set(insert.id, graph);
      voiceChainGraph.insertOrder.push(insert.id);
    }

    // Build the connections
    this.rebuildChainConnections(voiceChainGraph);

    // Connect source to chainInput
    sourceNode.connect(chainInput);

    // Store the voice chain
    this.voiceChains.set(voiceKey, voiceChainGraph);

    // Track metrics
    dspMetrics.graphCreated('voiceChain');
    for (const _ of chain.inserts) {
      dspMetrics.graphCreated('voiceInsert');
    }
    rfDebug('VoiceInsertDSP', `Created voice chain: ${voiceKey} with ${chain.inserts.length} inserts`);

    return chainOutput;
  }

  /**
   * Dispose a voice chain when the voice ends.
   */
  disposeVoiceChain(voiceKey: string): void {
    const chain = this.voiceChains.get(voiceKey);
    if (!chain) return;

    const insertCount = chain.insertGraphs.size;

    // Disconnect all insert graphs
    for (const graph of chain.insertGraphs.values()) {
      this.disconnectInsertGraph(graph);
      dspMetrics.graphDisposed('voiceInsert');
    }

    // Release chain nodes back to pool
    voiceChainPool.releaseGains([chain.chainInput, chain.chainOutput]);

    this.voiceChains.delete(voiceKey);
    dspMetrics.graphDisposed('voiceChain');
    rfDebug('VoiceInsertDSP', `Released voice chain to pool: ${voiceKey} with ${insertCount} inserts`);
  }

  /**
   * Dispose all voice chains (called on StopAll).
   */
  disposeAllVoiceChains(): void {
    for (const voiceKey of Array.from(this.voiceChains.keys())) {
      this.disposeVoiceChain(voiceKey);
    }
  }

  /**
   * Toggle insert bypass for a specific voice chain with click-free crossfade.
   */
  setInsertEnabled(
    voiceKey: string,
    insertId: InsertId,
    enabled: boolean
  ): void {
    const chain = this.voiceChains.get(voiceKey);
    if (!chain || !this.ctx) return;

    const graph = chain.insertGraphs.get(insertId);
    if (!graph) return;

    if (graph.enabled === enabled) return;

    const now = this.ctx.currentTime;
    const currentValue = graph.dryGain.gain.value;
    graph.enabled = enabled;

    // Use click-free ramp pattern: cancel → set → ramp
    graph.dryGain.gain.cancelScheduledValues(now);
    graph.dryGain.gain.setValueAtTime(currentValue, now);

    if (enabled) {
      // Fade out dry (wet path is always connected at unity gain)
      graph.dryGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
    } else {
      // Fade in dry (bypassed - both paths audible, but dry dominates)
      graph.dryGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
    }

    // Also notify Plugin Framework DSP if present
    if (graph.pluginDSP && typeof graph.pluginDSP.setBypass === 'function') {
      graph.pluginDSP.setBypass(!enabled);
    }
  }

  /**
   * Update insert parameters in real-time for a specific voice chain.
   */
  updateInsertParams(voiceKey: string, insert: Insert): void {
    const chain = this.voiceChains.get(voiceKey);
    if (!chain || !this.ctx) return;

    const graph = chain.insertGraphs.get(insert.id);
    if (!graph) return;

    // All Van* plugins use Plugin Framework DSP with flat params
    if (graph.pluginDSP && insert.params) {
      graph.pluginDSP.applyParams(insert.params as Record<string, number>);
    }
  }

  /**
   * Update insert params across all voice chains for a given asset.
   * Used when the user edits asset insert chain params in the UI.
   */
  updateAllVoiceChainsForAsset(assetId: string, insert: Insert): void {
    for (const chain of this.voiceChains.values()) {
      if (chain.assetId === assetId) {
        this.updateInsertParams(chain.voiceKey, insert);
      }
    }
  }

  /**
   * Toggle bypass across all voice chains for a given asset.
   */
  setInsertEnabledForAsset(
    assetId: string,
    insertId: InsertId,
    enabled: boolean
  ): void {
    for (const chain of this.voiceChains.values()) {
      if (chain.assetId === assetId) {
        this.setInsertEnabled(chain.voiceKey, insertId, enabled);
      }
    }
  }

  /**
   * Get count of active voice chains.
   */
  getActiveVoiceChainCount(): number {
    return this.voiceChains.size;
  }

  /**
   * Get active voice chain keys for an asset.
   */
  getActiveVoiceKeysForAsset(assetId: string): string[] {
    const keys: string[] = [];
    for (const chain of this.voiceChains.values()) {
      if (chain.assetId === assetId) {
        keys.push(chain.voiceKey);
      }
    }
    return keys;
  }

  // ============ Private Methods ============

  private createInsertGraph(insert: Insert): InsertNodeGraph {
    const ctx = this.ctx!;

    const inputGain = ctx.createGain();
    inputGain.gain.value = 1;

    const outputGain = ctx.createGain();
    outputGain.gain.value = 1;

    const dryGain = ctx.createGain();
    // Start with dry at 0 if enabled, 1 if bypassed
    dryGain.gain.value = insert.enabled ? 0 : 1;

    const processingNodes: AudioNode[] = [];
    let pluginDSP: PluginDSPInstance | null = null;

    // All plugins use Plugin Framework (vaneq, vancomp, vanlimit)
    const pluginDef = getPluginDefinition(insert.pluginId);
    if (pluginDef) {
      // Use pool for Plugin Framework DSP instances
      pluginDSP = pluginPool.acquire(insert.pluginId, ctx);
      if (pluginDSP) {
        // Apply initial params
        if (insert.params && typeof insert.params === 'object') {
          pluginDSP.applyParams(insert.params as Record<string, number>);
        }
        rfDebug('VoiceInsertDSP', `Acquired Plugin DSP from pool for ${insert.pluginId}`);
      } else {
        rfDebug('VoiceInsertDSP', `Failed to acquire Plugin DSP for ${insert.pluginId}`);
      }
    } else {
      rfDebug('VoiceInsertDSP', `Unknown plugin: ${insert.pluginId}, using passthrough`);
    }

    // Wire internal graph:
    // inputGain -> processingNodes chain -> outputGain (wet path)
    // inputGain -> dryGain -> outputGain (dry path for bypass)

    if (pluginDSP) {
      // Plugin Framework DSP: use its input/output nodes
      inputGain.connect(pluginDSP.getInputNode());
      pluginDSP.connect(outputGain);
    } else {
      // No processing - direct passthrough
      inputGain.connect(outputGain);
    }

    // Dry bypass path
    inputGain.connect(dryGain);
    dryGain.connect(outputGain);

    return {
      insertId: insert.id,
      pluginId: insert.pluginId,
      inputGain,
      outputGain,
      dryGain,
      processingNodes,
      pluginDSP,
      enabled: insert.enabled,
    };
  }

  private disconnectInsertGraph(graph: InsertNodeGraph): void {
    try {
      graph.inputGain.disconnect();
      graph.outputGain.disconnect();
      graph.dryGain.disconnect();
      graph.processingNodes.forEach((node) => {
        try {
          node.disconnect();
        } catch {
          // Ignore
        }
      });
      // Release Plugin Framework DSP back to pool (instead of dispose)
      if (graph.pluginDSP) {
        pluginPool.release(graph.pluginId, graph.pluginDSP);
        rfDebug('VoiceInsertDSP', `Released Plugin DSP back to pool: ${graph.pluginId}`);
      }
    } catch {
      // Ignore
    }
  }

  private rebuildChainConnections(chain: VoiceChainGraph): void {
    // Disconnect chainInput from everything
    try {
      chain.chainInput.disconnect();
    } catch {
      // Ignore
    }

    // Also disconnect all insert outputs
    for (const graph of chain.insertGraphs.values()) {
      try {
        graph.outputGain.disconnect();
      } catch {
        // Ignore
      }
    }

    if (chain.insertOrder.length === 0) {
      // Empty chain: direct connection
      chain.chainInput.connect(chain.chainOutput);
      return;
    }

    // Build chain: chainInput -> insert[0] -> insert[1] -> ... -> chainOutput
    let previousOutput: AudioNode = chain.chainInput;

    for (const insertId of chain.insertOrder) {
      const graph = chain.insertGraphs.get(insertId);
      if (graph) {
        previousOutput.connect(graph.inputGain);
        previousOutput = graph.outputGain;
      }
    }

    previousOutput.connect(chain.chainOutput);
  }
}

/**
 * Singleton instance for the voice insert DSP.
 */
export const voiceInsertDSP = new VoiceInsertDSP();

/**
 * Helper function to wire up a voice with asset inserts.
 * Returns the output node that should be connected to the bus.
 *
 * Usage in audioEngine:
 * ```
 * const output = wireVoiceWithInserts(voiceKey, assetId, localGain);
 * output.connect(busGain);
 * ```
 *
 * @param voiceKey Unique key for this voice instance
 * @param assetId The asset ID (soundId) being played
 * @param sourceNode The source node to connect (typically the localGain after pan)
 * @returns The output node to connect to bus (chainOutput if inserts exist, or sourceNode if no inserts)
 */
export function wireVoiceWithInserts(
  voiceKey: string,
  assetId: string,
  sourceNode: GainNode
): AudioNode {
  // Check if this asset has inserts
  if (!voiceInsertDSP.hasAssetInserts(assetId)) {
    // No inserts - return the source node directly
    return sourceNode;
  }

  // Create voice chain and get the output
  const chainOutput = voiceInsertDSP.createVoiceChain(voiceKey, assetId, sourceNode);
  if (chainOutput) {
    return chainOutput;
  }

  // Fallback to source node if chain creation failed
  return sourceNode;
}

/**
 * Helper function to dispose a voice chain when the voice ends.
 */
export function disposeVoiceInserts(voiceKey: string): void {
  voiceInsertDSP.disposeVoiceChain(voiceKey);
}

/**
 * Helper function to dispose all voice chains (on StopAll).
 */
export function disposeAllVoiceInserts(): void {
  voiceInsertDSP.disposeAllVoiceChains();
}

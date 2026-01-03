/**
 * ReelForge M8.0 Master Insert DSP
 *
 * WebAudio DSP implementation for master bus insert chain.
 * Sits between master gain and AudioContext destination.
 *
 * Signal flow (PDC disabled):
 * [Master Gain] → chainInput → [Insert 1] → [Insert 2] → ... → chainOutput → [Destination]
 *
 * Signal flow (PDC enabled):
 * [Master Gain] → [Compensation Delay] → chainInput → [Insert 1] → ... → chainOutput → [Destination]
 *
 * PDC (Preview Delay Compensation) adds a delay before the insert chain to
 * compensate for insert latency, keeping preview timing aligned with runtime.
 *
 * Implements InsertChainHostWithPDC interface (src/insert/InsertChainHost.ts).
 * This enables unified chain management and future plugin framework integration.
 *
 * @see InsertChainHost - Core chain host interface
 * @see InsertChainHostWithPDC - PDC-enabled host interface
 */

import type {
  MasterInsertChain,
  MasterInsert,
  InsertId,
} from './masterInsertTypes';
import { sanitizeInserts } from './masterInsertTypes';
import { dspMetrics, rfDebug } from './dspMetrics';
import { getPluginDefinition } from '../plugin/pluginRegistry';
import type { PluginDSPInstance } from '../plugin/PluginDefinition';
import { pluginPool } from '../plugin/PluginInstancePool';
import { sendReturnBus } from './SendReturnBus';
import { customAuxBus } from './CustomAuxBus';

/** Click-free bypass ramp time in seconds */
const BYPASS_RAMP_TIME = 0.01; // 10ms

/** Click-free delay update ramp time in seconds */
const DELAY_RAMP_TIME = 0.01; // 10ms

/**
 * Maximum delay time in seconds (for DelayNode buffer).
 * Set to 500ms to handle extreme cases (many stacked dynamics processors).
 * At 48kHz: 500ms = ~24000 samples = ~187 compressor/limiters worth.
 * This is a hard limit - latency beyond this will be clamped with a warning.
 */
const MAX_DELAY_TIME = 0.5; // 500ms max compensation

/** Single insert node graph */
interface InsertNodeGraph {
  insertId: InsertId;
  pluginId: string;
  inputGain: GainNode;
  outputGain: GainNode;
  dryGain: GainNode; // For bypass routing
  wetGain: GainNode; // For wet/processed signal
  processingNodes: AudioNode[]; // Legacy nodes (unused, kept for interface compat)
  /** Plugin Framework DSP instance (for Pro plugins like vaneq, vancomp, vanlimit) */
  pluginDSP: PluginDSPInstance | null;
  enabled: boolean;
}

/**
 * Master Insert DSP Processor
 *
 * Manages WebAudio node graph for master bus inserts.
 * Provides click-free bypass and real-time parameter updates.
 *
 * Conforms to InsertChainHostWithPDC interface:
 * - applyChain(chain) - Apply complete chain configuration
 * - getLatencySamples() - Get chain latency for PDC
 * - dispose() - Cleanup all DSP resources
 * - setInsertEnabled(id, enabled) - Toggle bypass
 * - updateInsertParams(insert) - Real-time param updates
 * - setPdcEnabled(enabled) - Toggle PDC
 * - isPdcEnabled() - Check PDC state
 * - getCompensationDelayMs() - Get current delay
 * - isCompensationClamped() - Check if clamped
 *
 * M9.1+ Extension Point: This class manages the node graph topology.
 * Future plugins will provide their own processing nodes via
 * PluginDefinition.createDSP(), which this host will wire up.
 */
export class MasterInsertDSP {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private chainInput: GainNode | null = null;
  private chainOutput: GainNode | null = null;
  private insertGraphs: Map<InsertId, InsertNodeGraph> = new Map();
  private insertOrder: InsertId[] = [];
  private isConnected = false;

  // PDC (Preview Delay Compensation)
  private compensationDelay: DelayNode | null = null;
  private pdcEnabled = false;
  private currentDelayTime = 0; // Current delay in seconds

  /**
   * Initialize the DSP chain.
   * Call after AudioContext and masterGain are available.
   */
  initialize(ctx: AudioContext, masterGain: GainNode): void {
    if (this.isConnected) {
      rfDebug('MasterInsertDSP', 'Already initialized, skipping');
      return;
    }

    rfDebug('MasterInsertDSP', `initialize() - ctx.state=${ctx.state}, sampleRate=${ctx.sampleRate}`);

    this.ctx = ctx;
    this.masterGain = masterGain;

    // Create chain input/output nodes
    this.chainInput = ctx.createGain();
    this.chainInput.gain.value = 1;

    this.chainOutput = ctx.createGain();
    this.chainOutput.gain.value = 1;

    // Create compensation delay node for PDC
    // Starts at 0 delay (no compensation until enabled)
    this.compensationDelay = ctx.createDelay(MAX_DELAY_TIME);
    this.compensationDelay.delayTime.value = 0;
    this.currentDelayTime = 0;

    // Disconnect master from destination and rewire through us
    // CRITICAL: Must disconnect ALL outputs from masterGain before rewiring
    try {
      masterGain.disconnect();
    } catch {
      // masterGain was not connected - this is fine
    }

    // Wire: Master → compensationDelay → chainInput → chainOutput → destination
    masterGain.connect(this.compensationDelay);
    this.compensationDelay.connect(this.chainInput);
    this.chainInput.connect(this.chainOutput);
    this.chainOutput.connect(ctx.destination);

    this.isConnected = true;

    // Initialize Send/Return Bus system with our master output
    // This allows aux sends (reverb, delay, etc.) to route back to master
    sendReturnBus.init(ctx, this.chainOutput);

    // Initialize Custom Aux Bus system
    // Provides user-defined routing and submix capabilities
    customAuxBus.init(ctx, this.chainOutput);

    dspMetrics.graphCreated('masterChain');
    rfDebug('MasterInsertDSP', 'Initialized: masterGain → compensationDelay → chainInput → chainOutput → destination');
  }

  /**
   * Disconnect and cleanup.
   */
  dispose(): void {
    if (!this.isConnected || !this.ctx || !this.masterGain) {
      return;
    }

    const insertCount = this.insertGraphs.size;

    // Disconnect all insert graphs
    this.insertGraphs.forEach((graph) => {
      this.disconnectInsertGraph(graph);
      dspMetrics.graphDisposed('masterInsert');
    });
    this.insertGraphs.clear();
    this.insertOrder = [];

    // Dispose custom aux buses (which also cleans up linked send/return buses)
    customAuxBus.dispose();

    // Dispose send/return buses
    sendReturnBus.dispose();

    // Disconnect chain nodes
    try {
      this.chainInput?.disconnect();
      this.chainOutput?.disconnect();
      this.compensationDelay?.disconnect();
    } catch {
      // Ignore
    }

    // Reconnect master directly to destination
    try {
      this.masterGain.disconnect();
      this.masterGain.connect(this.ctx.destination);
    } catch {
      // Ignore
    }

    this.chainInput = null;
    this.chainOutput = null;
    this.compensationDelay = null;
    this.pdcEnabled = false;
    this.currentDelayTime = 0;
    this.isConnected = false;
    dspMetrics.graphDisposed('masterChain');
    rfDebug('MasterInsertDSP', `Disposed (had ${insertCount} inserts)`);
  }

  // Track last chain state to skip redundant applyChain calls
  private lastChainHash: string = '';

  /**
   * Apply a complete insert chain configuration.
   * Rebuilds the node graph as needed.
   * Sanitizes inserts to prevent undefined crashes.
   *
   * OPTIMIZATION: Skips processing if chain hasn't changed (prevents infinite loops
   * when plugin windows send rapid param updates that trigger zustand state changes).
   */
  applyChain(chain: MasterInsertChain): void {
    // Create a simple hash of the chain state to detect real changes
    const chainHash = this.computeChainHash(chain);
    if (chainHash === this.lastChainHash) {
      // Chain is identical to last time - skip processing to prevent infinite loops
      return;
    }

    // DEBUG: Log hash change to diagnose spam
    if (this.lastChainHash && chainHash !== this.lastChainHash) {
      // Only log first 100 chars of each hash to reduce spam
      rfDebug('MasterInsertDSP', `Hash changed: ${this.lastChainHash.slice(0, 100)}... → ${chainHash.slice(0, 100)}...`);
    }

    this.lastChainHash = chainHash;

    rfDebug('MasterInsertDSP', `applyChain processing: ${chain.inserts?.length ?? 0} inserts`);

    if (!this.ctx || !this.isConnected) {
      // Log warning only if there are inserts to apply (not just empty chain)
      if (chain.inserts && chain.inserts.length > 0) {
        console.warn('[MasterInsertDSP] Not initialized, cannot apply chain with inserts:', chain.inserts.map(i => i?.id));
      }
      rfDebug('MasterInsertDSP', 'Not initialized, cannot apply chain');
      return;
    }

    // Sanitize inserts - filter out any null/undefined/invalid entries
    const validInserts = sanitizeInserts(chain.inserts, 'master');

    const newIds = new Set(validInserts.map((ins) => ins.id));
    const existingIds = new Set(this.insertOrder);

    // Remove inserts that are no longer in the chain
    for (const id of existingIds) {
      if (!newIds.has(id)) {
        this.removeInsert(id);
      }
    }

    // Add or update inserts
    for (const insert of validInserts) {
      if (this.insertGraphs.has(insert.id)) {
        // Update existing insert
        this.updateInsertParams(insert);
        this.setInsertEnabled(insert.id, insert.enabled);
      } else {
        // Add new insert
        this.addInsert(insert);
      }
    }

    // Reorder if needed
    const newOrder = validInserts.map((ins) => ins.id);
    if (!this.arraysEqual(this.insertOrder, newOrder)) {
      this.reorderInserts(newOrder);
    }

    // Update compensation delay for PDC (chain latency may have changed)
    this.updateCompensationDelay();
  }

  /**
   * Add a new insert to the chain.
   */
  addInsert(insert: MasterInsert): void {
    if (!this.ctx || !this.isConnected) {
      console.warn('[MasterInsertDSP] addInsert called but not connected:', insert.id);
      return;
    }

    // Check if already exists (shouldn't happen but let's verify)
    if (this.insertGraphs.has(insert.id)) {
      console.warn('[MasterInsertDSP] addInsert: INSERT ALREADY EXISTS!', insert.id);
      return;
    }

    rfDebug('MasterInsertDSP', `Adding insert: ${insert.id} (${insert.pluginId}), existing: ${this.insertGraphs.size}`);

    const graph = this.createInsertGraph(insert);
    this.insertGraphs.set(insert.id, graph);
    this.insertOrder.push(insert.id);

    this.rebuildChainConnections();
    dspMetrics.graphCreated('masterInsert');
    rfDebug('MasterInsertDSP', `Added insert: ${insert.id} (${insert.pluginId})`);
  }

  /**
   * Remove an insert from the chain.
   */
  removeInsert(insertId: InsertId): void {
    const graph = this.insertGraphs.get(insertId);
    if (!graph) return;

    this.disconnectInsertGraph(graph);
    this.insertGraphs.delete(insertId);
    this.insertOrder = this.insertOrder.filter((id) => id !== insertId);

    this.rebuildChainConnections();
    dspMetrics.graphDisposed('masterInsert');
    rfDebug('MasterInsertDSP', `Removed insert: ${insertId}`);
  }

  /**
   * Toggle insert bypass with click-free crossfade.
   */
  setInsertEnabled(insertId: InsertId, enabled: boolean): void {
    const graph = this.insertGraphs.get(insertId);
    if (!graph || !this.ctx) return;

    if (graph.enabled === enabled) return;

    const now = this.ctx.currentTime;
    graph.enabled = enabled;

    // Get current values for smooth crossfade
    const dryValue = graph.dryGain.gain.value;
    const wetValue = graph.wetGain.gain.value;

    // Use click-free ramp pattern: cancel → set → ramp
    graph.dryGain.gain.cancelScheduledValues(now);
    graph.wetGain.gain.cancelScheduledValues(now);
    graph.dryGain.gain.setValueAtTime(dryValue, now);
    graph.wetGain.gain.setValueAtTime(wetValue, now);

    if (enabled) {
      // Processing active: fade in wet, fade out dry
      graph.wetGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
      graph.dryGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
    } else {
      // Bypassed: fade out wet, fade in dry
      graph.wetGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
      graph.dryGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
    }

    // NOTE: We do NOT call pluginDSP.setBypass() here.
    // masterInsertDSP handles bypass entirely via wetGain/dryGain crossfade.
    // Calling pluginDSP.setBypass would cause duplicate signal paths.

    // Update compensation delay (bypass affects latency calculation)
    this.updateCompensationDelay();

    rfDebug('MasterInsertDSP', `Insert ${insertId} enabled: ${enabled}`);
  }

  /**
   * Update insert parameters in real-time.
   */
  updateInsertParams(insert: MasterInsert): void {
    const graph = this.insertGraphs.get(insert.id);
    if (!graph || !this.ctx) return;

    // All Van* plugins use Plugin Framework DSP with flat params
    if (graph.pluginDSP && insert.params) {
      const params = insert.params as Record<string, number>;
      graph.pluginDSP.applyParams(params);
    }
  }

  /**
   * Reorder inserts in the chain.
   */
  reorderInserts(newOrder: InsertId[]): void {
    // Validate all IDs exist
    for (const id of newOrder) {
      if (!this.insertGraphs.has(id)) {
        rfDebug('MasterInsertDSP', `Unknown insert ID in reorder: ${id}`);
        return;
      }
    }

    this.insertOrder = [...newOrder];
    this.rebuildChainConnections();
    rfDebug('MasterInsertDSP', `Reordered inserts: ${newOrder.join(' → ')}`);
  }

  /**
   * Get current chain latency in samples.
   * Queries plugin registry for accurate latency values.
   */
  getLatencySamples(): number {
    let total = 0;
    for (const id of this.insertOrder) {
      const graph = this.insertGraphs.get(id);
      if (graph && graph.enabled) {
        // Query latency from plugin registry
        const pluginDef = getPluginDefinition(graph.pluginId);
        total += pluginDef?.latencySamples ?? 0;
      }
    }
    return total;
  }

  /**
   * Get current chain latency in milliseconds.
   */
  getLatencyMs(): number {
    if (!this.ctx) return 0;
    return (this.getLatencySamples() / this.ctx.sampleRate) * 1000;
  }

  /**
   * Get the AudioContext sample rate.
   * Used by UI components (like EQ graphs) to ensure filter calculations
   * match the actual DSP processing sample rate.
   *
   * @returns Sample rate in Hz, or 48000 if context not initialized
   */
  getSampleRate(): number {
    return this.ctx?.sampleRate ?? 48000;
  }

  // ============ PDC (Preview Delay Compensation) Methods ============

  /**
   * Enable or disable PDC.
   * When enabled, adds delay before insert chain to compensate for insert latency.
   */
  setPdcEnabled(enabled: boolean): void {
    if (this.pdcEnabled === enabled) return;

    this.pdcEnabled = enabled;
    this.updateCompensationDelay();
    rfDebug('MasterInsertDSP', `PDC ${enabled ? 'enabled' : 'disabled'}`);
  }

  /**
   * Check if PDC is currently enabled.
   */
  isPdcEnabled(): boolean {
    return this.pdcEnabled;
  }

  /**
   * Get current compensation delay in milliseconds.
   */
  getCompensationDelayMs(): number {
    return this.currentDelayTime * 1000;
  }

  /**
   * Check if compensation delay is currently clamped to max.
   * Returns true if chain latency exceeds MAX_DELAY_TIME.
   */
  isCompensationClamped(): boolean {
    if (!this.pdcEnabled) return false;
    const targetDelay = this.getLatencyMs() / 1000;
    return targetDelay > MAX_DELAY_TIME;
  }

  /**
   * Get max supported compensation delay in milliseconds.
   */
  getMaxCompensationDelayMs(): number {
    return MAX_DELAY_TIME * 1000;
  }

  /**
   * Update compensation delay based on current chain latency.
   * Called when chain changes or PDC is toggled.
   * Uses click-free ramping for smooth transitions.
   */
  private updateCompensationDelay(): void {
    if (!this.ctx || !this.compensationDelay) return;

    const targetDelay = this.pdcEnabled ? this.getLatencyMs() / 1000 : 0;

    // Clamp to max delay time with warning
    const clampedDelay = Math.min(targetDelay, MAX_DELAY_TIME);

    if (targetDelay > MAX_DELAY_TIME) {
      rfDebug('MasterInsertDSP', `PDC latency ${(targetDelay * 1000).toFixed(1)}ms exceeds max ${MAX_DELAY_TIME * 1000}ms. Clamped.`);
    }

    if (clampedDelay === this.currentDelayTime) return;

    const now = this.ctx.currentTime;

    // Click-free ramp to new delay value
    this.compensationDelay.delayTime.cancelScheduledValues(now);
    this.compensationDelay.delayTime.setValueAtTime(this.currentDelayTime, now);
    this.compensationDelay.delayTime.linearRampToValueAtTime(
      clampedDelay,
      now + DELAY_RAMP_TIME
    );

    this.currentDelayTime = clampedDelay;
    rfDebug('MasterInsertDSP', `Compensation delay: ${(clampedDelay * 1000).toFixed(2)}ms`);
  }

  // ============ Private Methods ============

  private createInsertGraph(insert: MasterInsert): InsertNodeGraph {
    const ctx = this.ctx!;

    const inputGain = ctx.createGain();
    inputGain.gain.value = 1;

    const outputGain = ctx.createGain();
    outputGain.gain.value = 1;

    const dryGain = ctx.createGain();
    const wetGain = ctx.createGain();
    // Start with dry at 0 and wet at 1 if enabled (processing active)
    // Start with dry at 1 and wet at 0 if bypassed
    dryGain.gain.value = insert.enabled ? 0 : 1;
    wetGain.gain.value = insert.enabled ? 1 : 0;

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
        rfDebug('MasterInsertDSP', `Acquired Plugin DSP from pool for ${insert.pluginId}`);
      } else {
        rfDebug('MasterInsertDSP', `Failed to acquire Plugin DSP for ${insert.pluginId}`);
      }
    } else {
      rfDebug('MasterInsertDSP', `Unknown plugin: ${insert.pluginId}, using passthrough`);
    }

    // Wire internal graph:
    // inputGain → processingNodes chain → wetGain → outputGain (wet path)
    // inputGain → dryGain → outputGain (dry path for bypass)
    // IMPORTANT: wetGain and dryGain are crossfaded for click-free bypass

    if (pluginDSP) {
      // Plugin Framework DSP: use its input/output nodes
      // inputGain → pluginDSP.input → pluginDSP.output → wetGain → outputGain
      const pluginInput = pluginDSP.getInputNode();
      inputGain.connect(pluginInput);
      pluginDSP.connect(wetGain);
      wetGain.connect(outputGain);
    } else {
      // No processing - direct passthrough (wet path goes through wetGain for bypass control)
      inputGain.connect(wetGain);
      wetGain.connect(outputGain);
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
      wetGain,
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
      graph.wetGain.disconnect();
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
        rfDebug('MasterInsertDSP', `Released Plugin DSP back to pool: ${graph.pluginId}`);
      }
    } catch {
      // Ignore
    }
  }

  private rebuildChainConnections(): void {
    if (!this.chainInput || !this.chainOutput) return;

    // Disconnect chainInput from everything
    try {
      this.chainInput.disconnect();
    } catch {
      // Ignore
    }

    // Also disconnect all insert outputs
    for (const graph of this.insertGraphs.values()) {
      try {
        graph.outputGain.disconnect();
      } catch {
        // Ignore
      }
    }

    if (this.insertOrder.length === 0) {
      // Empty chain: direct connection
      this.chainInput.connect(this.chainOutput);
      rfDebug('MasterInsertDSP', 'Empty chain - direct bypass: chainInput → chainOutput');
      return;
    }

    // Build chain: chainInput → insert[0] → insert[1] → ... → chainOutput
    let previousOutput: AudioNode = this.chainInput;

    for (const insertId of this.insertOrder) {
      const graph = this.insertGraphs.get(insertId);
      if (graph) {
        previousOutput.connect(graph.inputGain);

        // CRITICAL FIX: Re-wire ALL internal graph connections after rebuild
        // This ensures both wet (plugin DSP) and dry (bypass) paths are connected.
        // Note: Web Audio connect() is additive - multiple calls just add connections,
        // so this is safe even if connections already exist.
        if (graph.pluginDSP) {
          // Wet path: graph.inputGain → pluginDSP.input → pluginDSP.output → wetGain → graph.outputGain
          const pluginInput = graph.pluginDSP.getInputNode();
          graph.inputGain.connect(pluginInput);
          graph.pluginDSP.connect(graph.wetGain);
          graph.wetGain.connect(graph.outputGain);
        } else {
          // Passthrough - wet path through wetGain for bypass control
          graph.inputGain.connect(graph.wetGain);
          graph.wetGain.connect(graph.outputGain);
        }

        // Dry bypass path: graph.inputGain → graph.dryGain → graph.outputGain
        graph.inputGain.connect(graph.dryGain);
        graph.dryGain.connect(graph.outputGain);

        previousOutput = graph.outputGain;
      }
    }

    previousOutput.connect(this.chainOutput);

    // Re-ensure chainOutput → destination is connected
    // Note: WebAudio doesn't have a way to check connections directly,
    // but connect() is additive so this is safe
    try {
      this.chainOutput.connect(this.ctx!.destination);
    } catch (err) {
      console.error('[MasterInsertDSP] Failed to connect chainOutput to destination:', err);
    }

    rfDebug('MasterInsertDSP', `Chain rebuilt with ${this.insertOrder.length} inserts`);
  }

  private arraysEqual(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }

  /**
   * Compute a hash string representing the current chain state.
   * Used to skip redundant applyChain calls when state hasn't changed.
   *
   * IMPORTANT: Uses sorted keys for params to ensure stable hashing
   * regardless of property insertion order.
   */
  private computeChainHash(chain: MasterInsertChain): string {
    const inserts = chain.inserts ?? [];
    // Create a simple hash from insert ids, enabled states, and params
    const parts: string[] = [];
    for (const insert of inserts) {
      if (!insert?.id) continue;
      // Include id, pluginId, enabled, and stringified params with SORTED keys
      let paramsStr = '';
      if (insert.params) {
        // Sort keys for stable hash regardless of property order
        const sortedKeys = Object.keys(insert.params).sort();
        const sortedParams: Record<string, unknown> = {};
        for (const key of sortedKeys) {
          sortedParams[key] = (insert.params as Record<string, unknown>)[key];
        }
        paramsStr = JSON.stringify(sortedParams);
      }
      parts.push(`${insert.id}:${insert.pluginId}:${insert.enabled}:${paramsStr}`);
    }
    return parts.join('|');
  }

  /**
   * Get the Plugin Framework DSP instance for an insert.
   * Used for advanced operations like metering.
   */
  getPluginDSP(insertId: InsertId): PluginDSPInstance | null {
    const graph = this.insertGraphs.get(insertId);
    return graph?.pluginDSP ?? null;
  }

  /**
   * Check if DSP is initialized.
   */
  isInitialized(): boolean {
    return this.isConnected;
  }
}

/**
 * Singleton instance for the master insert DSP.
 */
export const masterInsertDSP = new MasterInsertDSP();

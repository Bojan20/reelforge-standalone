/**
 * ReelForge M8.2.2 Bus Insert DSP
 *
 * WebAudio DSP implementation for per-bus insert chains.
 * Sits between each bus gain and master gain.
 *
 * Signal flow (per bus):
 * [Bus Gain] → chainInput → [Insert 1] → ... → chainOutput → [pdcDelay] → duckGain → [Master Gain]
 *
 * Ducking is implemented via duckGain nodes that sit between pdcDelay and masterGain.
 * When voice starts on the ducker bus (VO), the ducked bus (music) duckGain is ramped down.
 * Uses click-free transitions via linearRampToValueAtTime().
 *
 * PDC (Plugin Delay Compensation):
 * - Each bus has its own DelayNode for latency compensation
 * - PDC is OFF by default for backwards compatibility
 * - SFX/Voice should typically stay OFF for tight responsive feel
 * - Delay updates use click-free ramps (cancel → set → ramp)
 *
 * Implements InsertChainHostWithPDC interface (src/insert/InsertChainHost.ts)
 * for each bus. This enables unified chain management and future plugin framework.
 *
 * @see InsertChainHost - Core chain host interface
 * @see InsertChainHostWithPDC - PDC-enabled host interface
 */

import type {
  InsertChain,
  Insert,
  InsertId,
} from './masterInsertTypes';
import { sanitizeInserts } from './masterInsertTypes';
import type { BusId } from './types';
import type { InsertableBusId } from '../project/projectTypes';
import { dspMetrics, rfDebug } from './dspMetrics';
import { getPluginDefinition } from '../plugin/pluginRegistry';
import type { PluginDSPInstance } from '../plugin/PluginDefinition';
import { pluginPool } from '../plugin/PluginInstancePool';

/** Click-free bypass ramp time in seconds */
const BYPASS_RAMP_TIME = 0.01; // 10ms

/** PDC (Plugin Delay Compensation) configuration */
export const BUS_PDC_CONFIG = {
  /** Maximum delay time in seconds */
  MAX_DELAY_TIME: 0.5, // 500ms - matches Master PDC
  /** Ramp time for click-free delay updates in seconds */
  RAMP_TIME: 0.01, // 10ms
} as const;

/** Ducking configuration (exported for use in UI) */
export const DUCKING_CONFIG = {
  /** Gain multiplier applied to ducked bus when ducking is active */
  DUCK_RATIO: 0.35,
  /** Bus that triggers ducking when voices are active */
  DUCKER_BUS: 'voice' as InsertableBusId,
  /** Bus whose gain is reduced when ducking is active */
  DUCKED_BUS: 'music' as InsertableBusId,
  /** Ramp time for duck-in (voice starts) in seconds */
  DUCK_IN_RAMP: 0.03, // 30ms - fast duck
  /** Ramp time for duck-out (voice ends) in seconds */
  DUCK_OUT_RAMP: 0.05, // 50ms - slower recovery
} as const;

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

/** Bus chain node graph */
interface BusChainGraph {
  busId: InsertableBusId;
  chainInput: GainNode;
  chainOutput: GainNode;
  /** DelayNode for PDC, sits between chainOutput and duckGain */
  pdcDelay: DelayNode;
  /** Gain node for ducking, sits between pdcDelay and masterGain */
  duckGain: GainNode;
  insertGraphs: Map<InsertId, InsertNodeGraph>;
  insertOrder: InsertId[];
  /** Whether PDC is enabled for this bus */
  pdcEnabled: boolean;
  /** Whether PDC delay is currently clamped */
  pdcClamped: boolean;
  /** Target delay in seconds (may be clamped) */
  pdcDelaySeconds: number;
}

/**
 * Bus Insert DSP Processor
 *
 * Manages WebAudio node graphs for per-bus insert chains.
 * Provides click-free bypass and real-time parameter updates.
 *
 * Per-bus interface conformance to InsertChainHostWithPDC:
 * - applyChain(busId, chain) - Apply chain to specific bus
 * - getLatencySamples(busId) - Get chain latency for PDC
 * - dispose() - Cleanup all DSP resources
 * - setInsertEnabled(busId, id, enabled) - Toggle bypass
 * - updateInsertParams(busId, insert) - Real-time param updates
 * - setBusPdcEnabled(busId, enabled) - Toggle PDC per bus
 * - isBusPdcEnabled(busId) - Check PDC state per bus
 * - getBusPdcDelayMs(busId) - Get current delay per bus
 * - isBusPdcClamped(busId) - Check if clamped per bus
 *
 * Additional bus-specific features:
 * - Ducking (voice → music, ratio 0.35)
 * - Per-bus PDC (each bus has own delay node)
 *
 * M9.1+ Extension Point: This class manages the node graph topology.
 * Future plugins will provide their own processing nodes via
 * PluginDefinition.createDSP(), which this host will wire up.
 */
export class BusInsertDSP {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private busGains: Record<BusId, GainNode> | null = null;
  private busChains: Map<InsertableBusId, BusChainGraph> = new Map();
  private isConnected = false;

  /** Voice count on ducker bus (VO) - used to determine ducking state */
  private duckerVoiceCount = 0;
  /** Current ducking state (true = ducked) */
  private isDucking = false;
  /** Track which buses have logged clamp warnings (to avoid spam) */
  private clampWarningLogged: Set<InsertableBusId> = new Set();

  /**
   * Valid bus IDs for insert chains (all except 'master').
   */
  private static readonly INSERTABLE_BUS_IDS: InsertableBusId[] = [
    'music',
    'sfx',
    'ambience',
    'voice',
  ];

  /**
   * Initialize the DSP chains for all buses.
   * Call after AudioContext, busGains, and masterGain are available.
   * Safe to call multiple times - subsequent calls are no-ops.
   */
  initialize(
    ctx: AudioContext,
    busGains: Record<BusId, GainNode>,
    masterGain: GainNode
  ): void {
    // Hard guard - silently return if already initialized
    // This handles React StrictMode double-mounting in dev
    if (this.isConnected) {
      return;
    }

    this.ctx = ctx;
    this.busGains = busGains;
    this.masterGain = masterGain;

    // Create chain nodes for each insertable bus
    for (const busId of BusInsertDSP.INSERTABLE_BUS_IDS) {
      const busGain = busGains[busId];
      if (!busGain) {
        rfDebug('BusInsertDSP', `Bus gain not found for: ${busId}`);
        continue;
      }

      // Create chain input/output nodes
      const chainInput = ctx.createGain();
      chainInput.gain.value = 1;

      const chainOutput = ctx.createGain();
      chainOutput.gain.value = 1;

      // Create PDC delay node (sits between chainOutput and duckGain)
      const pdcDelay = ctx.createDelay(BUS_PDC_CONFIG.MAX_DELAY_TIME);
      pdcDelay.delayTime.value = 0; // Start with no delay

      // Create duck gain node (sits between pdcDelay and masterGain)
      const duckGain = ctx.createGain();
      duckGain.gain.value = 1; // Start at full gain (no ducking)

      // Disconnect bus from master and rewire through chain
      try {
        busGain.disconnect();
      } catch {
        // May not be connected yet
      }

      // Bus → chainInput → chainOutput → pdcDelay → duckGain → Master
      busGain.connect(chainInput);
      chainInput.connect(chainOutput); // Empty chain initially
      chainOutput.connect(pdcDelay);
      pdcDelay.connect(duckGain);
      duckGain.connect(masterGain);

      this.busChains.set(busId, {
        busId,
        chainInput,
        chainOutput,
        pdcDelay,
        duckGain,
        insertGraphs: new Map(),
        insertOrder: [],
        pdcEnabled: false, // OFF by default
        pdcClamped: false,
        pdcDelaySeconds: 0,
      });

      dspMetrics.graphCreated('busChain');
    }

    // Reset ducking state
    this.duckerVoiceCount = 0;
    this.isDucking = false;

    this.isConnected = true;
    rfDebug('BusInsertDSP', 'Initialized');
  }

  /**
   * Disconnect and cleanup.
   */
  dispose(): void {
    if (!this.isConnected || !this.ctx || !this.masterGain || !this.busGains) {
      return;
    }

    // Disconnect all bus chains
    for (const [busId, chain] of this.busChains) {
      // Disconnect all insert graphs
      for (const graph of chain.insertGraphs.values()) {
        this.disconnectInsertGraph(graph);
        dspMetrics.graphDisposed('busInsert');
      }

      // Disconnect chain nodes
      try {
        chain.chainInput.disconnect();
        chain.chainOutput.disconnect();
        chain.pdcDelay.disconnect();
        chain.duckGain.disconnect();
      } catch {
        // Ignore
      }

      // Reconnect bus directly to master
      const busGain = this.busGains[busId];
      if (busGain) {
        try {
          busGain.disconnect();
          busGain.connect(this.masterGain);
        } catch {
          // Ignore
        }
      }

      dspMetrics.graphDisposed('busChain');
    }

    this.busChains.clear();
    this.duckerVoiceCount = 0;
    this.isDucking = false;
    this.isConnected = false;
    rfDebug('BusInsertDSP', 'Disposed');
  }

  /**
   * Apply insert chains for all buses.
   * @param chains Map of busId to InsertChain
   */
  applyAllChains(chains: Partial<Record<InsertableBusId, InsertChain>>): void {
    if (!this.ctx || !this.isConnected) {
      rfDebug('BusInsertDSP', 'Not initialized, cannot apply chains');
      return;
    }

    // Apply chain for each bus
    for (const busId of BusInsertDSP.INSERTABLE_BUS_IDS) {
      const chain = chains[busId];
      if (chain) {
        this.applyChain(busId, chain);
      } else {
        // Clear chain if not present
        this.applyChain(busId, { inserts: [] });
      }
    }
  }

  /**
   * Apply a complete insert chain configuration for a specific bus.
   * Rebuilds the node graph as needed.
   * Sanitizes inserts to prevent undefined crashes.
   */
  applyChain(busId: InsertableBusId, chain: InsertChain): void {
    if (!this.ctx || !this.isConnected) {
      rfDebug('BusInsertDSP', 'Not initialized, cannot apply chain');
      return;
    }

    const busChain = this.busChains.get(busId);
    if (!busChain) {
      rfDebug('BusInsertDSP', `Bus chain not found: ${busId}`);
      return;
    }

    // Sanitize inserts - filter out any null/undefined/invalid entries
    const validInserts = sanitizeInserts(chain.inserts, `bus:${busId}`);

    const newIds = new Set(validInserts.map((ins) => ins.id));
    const existingIds = new Set(busChain.insertOrder);

    // Remove inserts that are no longer in the chain
    for (const id of existingIds) {
      if (!newIds.has(id)) {
        this.removeInsert(busId, id);
      }
    }

    // Add or update inserts
    for (const insert of validInserts) {
      if (busChain.insertGraphs.has(insert.id)) {
        // Update existing insert
        this.updateInsertParams(busId, insert);
        this.setInsertEnabled(busId, insert.id, insert.enabled);
      } else {
        // Add new insert
        this.addInsert(busId, insert);
      }
    }

    // Reorder if needed
    const newOrder = validInserts.map((ins) => ins.id);
    if (!this.arraysEqual(busChain.insertOrder, newOrder)) {
      this.reorderInserts(busId, newOrder);
    }

    // Recalculate PDC delay after chain update
    this.recalculateBusPdc(busId);
  }

  /**
   * Add a new insert to a bus chain.
   */
  addInsert(busId: InsertableBusId, insert: Insert): void {
    if (!this.ctx || !this.isConnected) return;

    const busChain = this.busChains.get(busId);
    if (!busChain) return;

    const graph = this.createInsertGraph(insert);
    busChain.insertGraphs.set(insert.id, graph);
    busChain.insertOrder.push(insert.id);

    this.rebuildChainConnections(busId);
    this.recalculateBusPdc(busId);

    dspMetrics.graphCreated('busInsert');
    rfDebug('BusInsertDSP', `Added insert ${insert.id} (${insert.pluginId}) to ${busId}`);
  }

  /**
   * Remove an insert from a bus chain.
   */
  removeInsert(busId: InsertableBusId, insertId: InsertId): void {
    const busChain = this.busChains.get(busId);
    if (!busChain) return;

    const graph = busChain.insertGraphs.get(insertId);
    if (!graph) return;

    this.disconnectInsertGraph(graph);
    busChain.insertGraphs.delete(insertId);
    busChain.insertOrder = busChain.insertOrder.filter((id) => id !== insertId);

    this.rebuildChainConnections(busId);
    this.recalculateBusPdc(busId);

    dspMetrics.graphDisposed('busInsert');
    rfDebug('BusInsertDSP', `Removed insert ${insertId} from ${busId}`);
  }

  /**
   * Toggle insert bypass with click-free crossfade.
   */
  setInsertEnabled(
    busId: InsertableBusId,
    insertId: InsertId,
    enabled: boolean
  ): void {
    const busChain = this.busChains.get(busId);
    if (!busChain || !this.ctx) return;

    const graph = busChain.insertGraphs.get(insertId);
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

    // Recalculate PDC since enabled state affects latency calculation
    this.recalculateBusPdc(busId);
  }

  /**
   * Update insert parameters in real-time.
   */
  updateInsertParams(busId: InsertableBusId, insert: Insert): void {
    const busChain = this.busChains.get(busId);
    if (!busChain || !this.ctx) return;

    const graph = busChain.insertGraphs.get(insert.id);
    if (!graph) return;

    // All Van* plugins use Plugin Framework DSP with flat params
    if (graph.pluginDSP && insert.params) {
      graph.pluginDSP.applyParams(insert.params as Record<string, number>);
    }
  }

  /**
   * Reorder inserts in a bus chain.
   */
  reorderInserts(busId: InsertableBusId, newOrder: InsertId[]): void {
    const busChain = this.busChains.get(busId);
    if (!busChain) return;

    // Validate all IDs exist
    for (const id of newOrder) {
      if (!busChain.insertGraphs.has(id)) {
        rfDebug('BusInsertDSP', `Unknown insert ID in reorder: ${id}`);
        return;
      }
    }

    busChain.insertOrder = [...newOrder];
    this.rebuildChainConnections(busId);
    rfDebug('BusInsertDSP', `Reordered inserts on ${busId}: ${newOrder.join(' → ')}`);
  }

  /**
   * Get current chain latency in samples for a specific bus.
   * Queries plugin registry for accurate latency values.
   */
  getLatencySamples(busId: InsertableBusId): number {
    const busChain = this.busChains.get(busId);
    if (!busChain) return 0;

    let total = 0;
    for (const id of busChain.insertOrder) {
      const graph = busChain.insertGraphs.get(id);
      if (graph && graph.enabled) {
        // Query latency from plugin registry
        const pluginDef = getPluginDefinition(graph.pluginId);
        total += pluginDef?.latencySamples ?? 0;
      }
    }
    return total;
  }

  /**
   * Get current chain latency in milliseconds for a specific bus.
   */
  getLatencyMs(busId: InsertableBusId): number {
    if (!this.ctx) return 0;
    return (this.getLatencySamples(busId) / this.ctx.sampleRate) * 1000;
  }

  /**
   * Get total latency across all bus chains in samples.
   */
  getTotalLatencySamples(): number {
    let total = 0;
    for (const busId of BusInsertDSP.INSERTABLE_BUS_IDS) {
      total = Math.max(total, this.getLatencySamples(busId));
    }
    return total;
  }

  /**
   * Get total latency across all bus chains in milliseconds.
   */
  getTotalLatencyMs(): number {
    if (!this.ctx) return 0;
    return (this.getTotalLatencySamples() / this.ctx.sampleRate) * 1000;
  }

  // ============ Ducking Control Methods ============

  /**
   * Called when a voice starts on the ducker bus (VO).
   * Triggers ducking on the ducked bus (music).
   */
  onDuckerVoiceStart(): void {
    this.duckerVoiceCount++;
    this.updateDuckingState();
  }

  /**
   * Called when a voice ends on the ducker bus (VO).
   * Removes ducking when no ducker voices are active.
   */
  onDuckerVoiceEnd(): void {
    this.duckerVoiceCount = Math.max(0, this.duckerVoiceCount - 1);
    this.updateDuckingState();
  }

  /**
   * Set the ducker voice count directly.
   * Useful for syncing with external voice counts.
   */
  setDuckerVoiceCount(count: number): void {
    this.duckerVoiceCount = Math.max(0, count);
    this.updateDuckingState();
  }

  /**
   * Reset ducking state (called on StopAll).
   * Immediately resets duck gains without ramp.
   */
  resetDucking(): void {
    if (!this.ctx) return;

    this.duckerVoiceCount = 0;
    this.isDucking = false;

    // Reset all duck gains to 1.0 immediately
    const now = this.ctx.currentTime;
    for (const chain of this.busChains.values()) {
      chain.duckGain.gain.cancelScheduledValues(now);
      chain.duckGain.gain.setValueAtTime(1, now);
    }
  }

  /**
   * Get current ducking state.
   */
  getDuckingState(): { isDucking: boolean; duckerVoiceCount: number } {
    return {
      isDucking: this.isDucking,
      duckerVoiceCount: this.duckerVoiceCount,
    };
  }

  /**
   * Get the current duck gain value for a bus.
   * Returns 1.0 if bus is not ducked, DUCK_RATIO if ducked.
   */
  getDuckGainValue(busId: InsertableBusId): number {
    const chain = this.busChains.get(busId);
    if (!chain) return 1;
    return chain.duckGain.gain.value;
  }

  // ============ PDC (Plugin Delay Compensation) Methods ============

  /**
   * Set PDC enabled state for a specific bus.
   * When enabled, applies delay compensation based on chain latency.
   * Uses click-free delay ramp.
   */
  setBusPdcEnabled(busId: InsertableBusId, enabled: boolean): void {
    const chain = this.busChains.get(busId);
    if (!chain || !this.ctx) return;

    if (chain.pdcEnabled === enabled) return;

    chain.pdcEnabled = enabled;
    this.updateBusPdcDelay(busId);
  }

  /**
   * Get PDC enabled state for a specific bus.
   */
  isBusPdcEnabled(busId: InsertableBusId): boolean {
    const chain = this.busChains.get(busId);
    return chain?.pdcEnabled ?? false;
  }

  /**
   * Check if PDC delay is clamped for a specific bus.
   * Clamped means required delay exceeds max delay time.
   */
  isBusPdcClamped(busId: InsertableBusId): boolean {
    const chain = this.busChains.get(busId);
    return chain?.pdcClamped ?? false;
  }

  /**
   * Get current PDC delay in milliseconds for a specific bus.
   * Returns 0 if PDC is disabled.
   */
  getBusPdcDelayMs(busId: InsertableBusId): number {
    const chain = this.busChains.get(busId);
    if (!chain || !chain.pdcEnabled) return 0;
    return chain.pdcDelaySeconds * 1000;
  }

  /**
   * Get maximum PDC delay in milliseconds.
   */
  getBusPdcMaxMs(): number {
    return BUS_PDC_CONFIG.MAX_DELAY_TIME * 1000;
  }

  /**
   * Apply all PDC enabled states from project settings.
   * @param pdcEnabled Map of busId to enabled state
   */
  applyAllBusPdc(pdcEnabled: Partial<Record<InsertableBusId, boolean>>): void {
    for (const busId of BusInsertDSP.INSERTABLE_BUS_IDS) {
      const enabled = pdcEnabled[busId] ?? false;
      this.setBusPdcEnabled(busId, enabled);
    }
  }

  /**
   * Get PDC state for all buses.
   * Returns map of busId to { enabled, delayMs, clamped }.
   */
  getAllBusPdcState(): Record<InsertableBusId, { enabled: boolean; delayMs: number; clamped: boolean }> {
    const state = {} as Record<InsertableBusId, { enabled: boolean; delayMs: number; clamped: boolean }>;
    for (const busId of BusInsertDSP.INSERTABLE_BUS_IDS) {
      state[busId] = {
        enabled: this.isBusPdcEnabled(busId),
        delayMs: this.getBusPdcDelayMs(busId),
        clamped: this.isBusPdcClamped(busId),
      };
    }
    return state;
  }

  /**
   * Force recalculation of PDC delay for a bus.
   * Call after chain changes (add/remove/reorder/toggle inserts).
   */
  recalculateBusPdc(busId: InsertableBusId): void {
    this.updateBusPdcDelay(busId);
  }

  /**
   * Update PDC delay for a specific bus based on current chain latency.
   * Uses click-free ramp: cancel → set → ramp.
   */
  private updateBusPdcDelay(busId: InsertableBusId): void {
    const chain = this.busChains.get(busId);
    if (!chain || !this.ctx) return;

    const now = this.ctx.currentTime;
    const delayParam = chain.pdcDelay.delayTime;

    if (!chain.pdcEnabled) {
      // PDC disabled: ramp delay to 0
      chain.pdcClamped = false;
      chain.pdcDelaySeconds = 0;

      delayParam.cancelScheduledValues(now);
      delayParam.setValueAtTime(delayParam.value, now);
      delayParam.linearRampToValueAtTime(0, now + BUS_PDC_CONFIG.RAMP_TIME);

      // Clear clamp warning tracking
      this.clampWarningLogged.delete(busId);
      return;
    }

    // Calculate required delay from chain latency
    const latencySamples = this.getLatencySamples(busId);
    const requiredDelay = latencySamples / this.ctx.sampleRate;

    // Check if clamping is needed
    const maxDelay = BUS_PDC_CONFIG.MAX_DELAY_TIME;
    const isClamped = requiredDelay > maxDelay;
    const targetDelay = isClamped ? maxDelay : requiredDelay;

    // Update state
    chain.pdcClamped = isClamped;
    chain.pdcDelaySeconds = targetDelay;

    // Log warning on clamp (once per bus) - this stays as warn since it's significant
    if (isClamped && !this.clampWarningLogged.has(busId)) {
      rfDebug('BusInsertDSP', `PDC clamped for ${busId}: required ${(requiredDelay * 1000).toFixed(1)}ms, max ${(maxDelay * 1000).toFixed(1)}ms`);
      this.clampWarningLogged.add(busId);
    } else if (!isClamped) {
      this.clampWarningLogged.delete(busId);
    }

    // Apply click-free delay update
    delayParam.cancelScheduledValues(now);
    delayParam.setValueAtTime(delayParam.value, now);
    delayParam.linearRampToValueAtTime(targetDelay, now + BUS_PDC_CONFIG.RAMP_TIME);
  }

  /**
   * Update ducking state based on ducker voice count.
   * Uses click-free ramps for gain changes.
   */
  private updateDuckingState(): void {
    if (!this.ctx) return;

    const shouldDuck = this.duckerVoiceCount > 0;
    if (shouldDuck === this.isDucking) return;

    this.isDucking = shouldDuck;
    const now = this.ctx.currentTime;

    // Get the ducked bus chain
    const duckedChain = this.busChains.get(DUCKING_CONFIG.DUCKED_BUS);
    if (!duckedChain) return;

    const duckGain = duckedChain.duckGain;
    const currentValue = duckGain.gain.value;

    if (shouldDuck) {
      // Duck in: ramp to DUCK_RATIO
      duckGain.gain.cancelScheduledValues(now);
      duckGain.gain.setValueAtTime(currentValue, now);
      duckGain.gain.linearRampToValueAtTime(
        DUCKING_CONFIG.DUCK_RATIO,
        now + DUCKING_CONFIG.DUCK_IN_RAMP
      );
    } else {
      // Duck out: ramp back to 1.0
      duckGain.gain.cancelScheduledValues(now);
      duckGain.gain.setValueAtTime(currentValue, now);
      duckGain.gain.linearRampToValueAtTime(
        1,
        now + DUCKING_CONFIG.DUCK_OUT_RAMP
      );
    }
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
        rfDebug('BusInsertDSP', `Acquired Plugin DSP from pool for ${insert.pluginId}`);
      } else {
        rfDebug('BusInsertDSP', `Failed to acquire Plugin DSP for ${insert.pluginId}`);
      }
    } else {
      rfDebug('BusInsertDSP', `Unknown plugin: ${insert.pluginId}, using passthrough`);
    }

    // Wire internal graph:
    // inputGain -> processingNodes chain -> outputGain (wet path)
    // inputGain -> dryGain -> outputGain (dry path for bypass)

    if (pluginDSP) {
      // Plugin Framework DSP: use its input/output nodes
      // Wire: inputGain -> pluginDSP.input ... pluginDSP.output -> outputGain
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
        rfDebug('BusInsertDSP', `Released Plugin DSP back to pool: ${graph.pluginId}`);
      }
    } catch {
      // Ignore
    }
  }

  private rebuildChainConnections(busId: InsertableBusId): void {
    const busChain = this.busChains.get(busId);
    if (!busChain) return;

    // Disconnect chainInput from everything
    try {
      busChain.chainInput.disconnect();
    } catch {
      // Ignore
    }

    // Also disconnect all insert outputs
    for (const graph of busChain.insertGraphs.values()) {
      try {
        graph.outputGain.disconnect();
      } catch {
        // Ignore
      }
    }

    if (busChain.insertOrder.length === 0) {
      // Empty chain: direct connection
      busChain.chainInput.connect(busChain.chainOutput);
      return;
    }

    // Build chain: chainInput -> insert[0] -> insert[1] -> ... -> chainOutput
    let previousOutput: AudioNode = busChain.chainInput;

    for (const insertId of busChain.insertOrder) {
      const graph = busChain.insertGraphs.get(insertId);
      if (graph) {
        previousOutput.connect(graph.inputGain);
        previousOutput = graph.outputGain;
      }
    }

    previousOutput.connect(busChain.chainOutput);
  }

  private arraysEqual(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }
}

/**
 * Singleton instance for the bus insert DSP.
 */
export const busInsertDSP = new BusInsertDSP();

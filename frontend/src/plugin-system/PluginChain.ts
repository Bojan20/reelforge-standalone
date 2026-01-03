/**
 * ReelForge Plugin Chain
 *
 * Manages chains of plugins for insert/send processing.
 * Supports reordering, bypass, and parallel processing.
 *
 * @module plugin-system/PluginChain
 */

import type { PluginInstance } from './PluginRegistry';
import { PluginRegistry } from './PluginRegistry';

// ============ Types ============

export interface PluginSlot {
  id: string;
  position: number;
  instanceId: string | null;
  isBypassed: boolean;
  isEnabled: boolean;
  dryWetMix: number; // 0-1 (0 = dry, 1 = wet)
  inputGain: number; // Linear
  outputGain: number; // Linear
}

export interface PluginChainConfig {
  id: string;
  name: string;
  type: 'insert' | 'send' | 'master';
  maxSlots: number;
  slots: PluginSlot[];
  isActive: boolean;
  parallelMode: boolean;
}

export interface ChainProcessingResult {
  peakLevel: number;
  clipDetected: boolean;
  latencySamples: number;
}

// ============ Plugin Chain ============

export class PluginChain {
  private config: PluginChainConfig;
  private instances = new Map<string, PluginInstance>();
  private listeners = new Set<(event: ChainEvent) => void>();

  constructor(config: Partial<PluginChainConfig> & { id: string }) {
    this.config = {
      id: config.id,
      name: config.name ?? 'Plugin Chain',
      type: config.type ?? 'insert',
      maxSlots: config.maxSlots ?? 8,
      slots: config.slots ?? [],
      isActive: config.isActive ?? true,
      parallelMode: config.parallelMode ?? false,
    };

    // Initialize empty slots
    while (this.config.slots.length < this.config.maxSlots) {
      this.config.slots.push(this.createEmptySlot(this.config.slots.length));
    }
  }

  // ============ Getters ============

  getId(): string {
    return this.config.id;
  }

  getName(): string {
    return this.config.name;
  }

  getType(): 'insert' | 'send' | 'master' {
    return this.config.type;
  }

  getSlots(): PluginSlot[] {
    return [...this.config.slots];
  }

  getSlot(position: number): PluginSlot | undefined {
    return this.config.slots[position];
  }

  getActiveSlots(): PluginSlot[] {
    return this.config.slots.filter(s => s.instanceId !== null && s.isEnabled);
  }

  getInstance(slotPosition: number): PluginInstance | undefined {
    const slot = this.config.slots[slotPosition];
    if (!slot?.instanceId) return undefined;
    return this.instances.get(slot.instanceId);
  }

  isActive(): boolean {
    return this.config.isActive;
  }

  isParallel(): boolean {
    return this.config.parallelMode;
  }

  // ============ Slot Management ============

  /**
   * Insert plugin into slot.
   */
  async insertPlugin(
    position: number,
    pluginId: string
  ): Promise<PluginInstance | undefined> {
    if (position < 0 || position >= this.config.maxSlots) {
      return undefined;
    }

    // Remove existing plugin
    const slot = this.config.slots[position];
    if (slot.instanceId) {
      this.removePlugin(position);
    }

    // Create new instance
    const instance = await PluginRegistry.createInstance(pluginId);
    if (!instance) return undefined;

    // Update slot
    slot.instanceId = instance.id;
    slot.isEnabled = true;
    slot.isBypassed = false;

    this.instances.set(instance.id, instance);
    this.emit({ type: 'pluginInserted', position, instanceId: instance.id });

    return instance;
  }

  /**
   * Remove plugin from slot.
   */
  removePlugin(position: number): boolean {
    const slot = this.config.slots[position];
    if (!slot?.instanceId) return false;

    const instanceId = slot.instanceId;
    const instance = this.instances.get(instanceId);

    if (instance) {
      instance.dispose();
      this.instances.delete(instanceId);
    }

    // Reset slot
    slot.instanceId = null;
    slot.isBypassed = false;
    slot.isEnabled = true;

    this.emit({ type: 'pluginRemoved', position, instanceId });
    return true;
  }

  /**
   * Move plugin to new position.
   */
  movePlugin(fromPosition: number, toPosition: number): boolean {
    if (fromPosition === toPosition) return false;
    if (fromPosition < 0 || fromPosition >= this.config.maxSlots) return false;
    if (toPosition < 0 || toPosition >= this.config.maxSlots) return false;

    const fromSlot = this.config.slots[fromPosition];
    const toSlot = this.config.slots[toPosition];

    // Swap slots
    const tempInstanceId = fromSlot.instanceId;
    const tempBypassed = fromSlot.isBypassed;
    const tempEnabled = fromSlot.isEnabled;
    const tempDryWet = fromSlot.dryWetMix;

    fromSlot.instanceId = toSlot.instanceId;
    fromSlot.isBypassed = toSlot.isBypassed;
    fromSlot.isEnabled = toSlot.isEnabled;
    fromSlot.dryWetMix = toSlot.dryWetMix;

    toSlot.instanceId = tempInstanceId;
    toSlot.isBypassed = tempBypassed;
    toSlot.isEnabled = tempEnabled;
    toSlot.dryWetMix = tempDryWet;

    this.emit({ type: 'pluginMoved', fromPosition, toPosition });
    return true;
  }

  /**
   * Swap two plugins.
   */
  swapPlugins(positionA: number, positionB: number): boolean {
    return this.movePlugin(positionA, positionB);
  }

  // ============ Slot Control ============

  /**
   * Bypass slot.
   */
  bypassSlot(position: number, bypassed: boolean): void {
    const slot = this.config.slots[position];
    if (!slot) return;

    slot.isBypassed = bypassed;
    this.emit({ type: 'slotBypassed', position, bypassed });
  }

  /**
   * Toggle bypass.
   */
  toggleBypass(position: number): boolean {
    const slot = this.config.slots[position];
    if (!slot) return false;

    slot.isBypassed = !slot.isBypassed;
    this.emit({ type: 'slotBypassed', position, bypassed: slot.isBypassed });
    return slot.isBypassed;
  }

  /**
   * Enable/disable slot.
   */
  setEnabled(position: number, enabled: boolean): void {
    const slot = this.config.slots[position];
    if (!slot) return;

    slot.isEnabled = enabled;
    this.emit({ type: 'slotEnabled', position, enabled });
  }

  /**
   * Set dry/wet mix.
   */
  setDryWetMix(position: number, mix: number): void {
    const slot = this.config.slots[position];
    if (!slot) return;

    slot.dryWetMix = Math.max(0, Math.min(1, mix));
    this.emit({ type: 'mixChanged', position, mix: slot.dryWetMix });
  }

  /**
   * Set input gain.
   */
  setInputGain(position: number, gain: number): void {
    const slot = this.config.slots[position];
    if (!slot) return;

    slot.inputGain = Math.max(0, gain);
  }

  /**
   * Set output gain.
   */
  setOutputGain(position: number, gain: number): void {
    const slot = this.config.slots[position];
    if (!slot) return;

    slot.outputGain = Math.max(0, gain);
  }

  // ============ Chain Control ============

  /**
   * Set chain active state.
   */
  setActive(active: boolean): void {
    this.config.isActive = active;
    this.emit({ type: 'chainActiveChanged', active });
  }

  /**
   * Toggle chain active state.
   */
  toggleActive(): boolean {
    this.config.isActive = !this.config.isActive;
    this.emit({ type: 'chainActiveChanged', active: this.config.isActive });
    return this.config.isActive;
  }

  /**
   * Set parallel mode.
   */
  setParallelMode(parallel: boolean): void {
    this.config.parallelMode = parallel;
    this.emit({ type: 'parallelModeChanged', parallel });
  }

  /**
   * Bypass all plugins.
   */
  bypassAll(bypassed: boolean): void {
    for (let i = 0; i < this.config.slots.length; i++) {
      if (this.config.slots[i].instanceId) {
        this.bypassSlot(i, bypassed);
      }
    }
  }

  // ============ Processing ============

  /**
   * Process audio through chain.
   * Serial mode: input -> plugin1 -> plugin2 -> ... -> output
   * Parallel mode: input -> all plugins -> sum -> output
   */
  process(
    inputs: Float32Array[][],
    outputs: Float32Array[][]
  ): ChainProcessingResult {
    if (!this.config.isActive) {
      // Pass through
      for (let ch = 0; ch < inputs.length; ch++) {
        for (let i = 0; i < inputs[ch].length; i++) {
          if (outputs[ch] && outputs[ch][i] !== undefined) {
            outputs[ch][i].set(inputs[ch][i]);
          }
        }
      }
      return { peakLevel: 0, clipDetected: false, latencySamples: 0 };
    }

    let peakLevel = 0;
    let clipDetected = false;
    let totalLatency = 0;

    const activeSlots = this.getActiveSlots();

    if (activeSlots.length === 0) {
      // No plugins, pass through
      for (let ch = 0; ch < inputs.length; ch++) {
        for (let i = 0; i < inputs[ch].length; i++) {
          if (outputs[ch] && outputs[ch][i] !== undefined) {
            outputs[ch][i].set(inputs[ch][i]);
          }
        }
      }
      return { peakLevel: 0, clipDetected: false, latencySamples: 0 };
    }

    if (this.config.parallelMode) {
      // Parallel processing
      const parallelOutputs: Float32Array[][][] = [];

      for (const slot of activeSlots) {
        if (slot.isBypassed) continue;

        const instance = this.instances.get(slot.instanceId!);
        if (!instance) continue;

        // Create output buffers for this plugin
        const pluginOutputs = outputs.map(ch =>
          ch.map(buf => new Float32Array(buf.length))
        );

        // Apply input gain
        const scaledInputs = inputs.map(ch =>
          ch.map(buf => {
            const scaled = new Float32Array(buf.length);
            for (let i = 0; i < buf.length; i++) {
              scaled[i] = buf[i] * slot.inputGain;
            }
            return scaled;
          })
        );

        instance.process(scaledInputs, pluginOutputs);

        // Apply dry/wet and output gain
        for (let ch = 0; ch < pluginOutputs.length; ch++) {
          for (let bufIdx = 0; bufIdx < pluginOutputs[ch].length; bufIdx++) {
            const buf = pluginOutputs[ch][bufIdx];
            const dryBuf = inputs[ch]?.[bufIdx];

            for (let i = 0; i < buf.length; i++) {
              const wet = buf[i] * slot.outputGain;
              const dry = dryBuf?.[i] ?? 0;
              buf[i] = dry * (1 - slot.dryWetMix) + wet * slot.dryWetMix;
            }
          }
        }

        parallelOutputs.push(pluginOutputs);
      }

      // Sum parallel outputs
      for (let ch = 0; ch < outputs.length; ch++) {
        for (let bufIdx = 0; bufIdx < outputs[ch].length; bufIdx++) {
          outputs[ch][bufIdx].fill(0);

          for (const pOut of parallelOutputs) {
            if (pOut[ch]?.[bufIdx]) {
              for (let i = 0; i < outputs[ch][bufIdx].length; i++) {
                outputs[ch][bufIdx][i] += pOut[ch][bufIdx][i];
              }
            }
          }

          // Normalize by number of parallel paths
          if (parallelOutputs.length > 0) {
            const scale = 1 / parallelOutputs.length;
            for (let i = 0; i < outputs[ch][bufIdx].length; i++) {
              outputs[ch][bufIdx][i] *= scale;
            }
          }
        }
      }
    } else {
      // Serial processing
      let currentBuffers = inputs;

      for (const slot of activeSlots) {
        if (slot.isBypassed) continue;

        const instance = this.instances.get(slot.instanceId!);
        if (!instance) continue;

        // Get plugin latency
        const descriptor = PluginRegistry.get(instance.descriptorId);
        if (descriptor?.latencySamples) {
          totalLatency += descriptor.latencySamples;
        }

        // Create temp outputs
        const tempOutputs = currentBuffers.map(ch =>
          ch.map(buf => new Float32Array(buf.length))
        );

        // Apply input gain
        for (let ch = 0; ch < currentBuffers.length; ch++) {
          for (let bufIdx = 0; bufIdx < currentBuffers[ch].length; bufIdx++) {
            for (let i = 0; i < currentBuffers[ch][bufIdx].length; i++) {
              currentBuffers[ch][bufIdx][i] *= slot.inputGain;
            }
          }
        }

        // Process
        instance.process(currentBuffers, tempOutputs);

        // Apply dry/wet and output gain
        for (let ch = 0; ch < tempOutputs.length; ch++) {
          for (let bufIdx = 0; bufIdx < tempOutputs[ch].length; bufIdx++) {
            const buf = tempOutputs[ch][bufIdx];
            const dryBuf = currentBuffers[ch]?.[bufIdx];

            for (let i = 0; i < buf.length; i++) {
              const wet = buf[i] * slot.outputGain;
              const dry = dryBuf?.[i] ?? 0;
              buf[i] = dry * (1 - slot.dryWetMix) + wet * slot.dryWetMix;

              // Track peak
              const abs = Math.abs(buf[i]);
              if (abs > peakLevel) peakLevel = abs;
              if (abs > 1.0) clipDetected = true;
            }
          }
        }

        currentBuffers = tempOutputs;
      }

      // Copy to output
      for (let ch = 0; ch < outputs.length; ch++) {
        for (let bufIdx = 0; bufIdx < outputs[ch].length; bufIdx++) {
          if (currentBuffers[ch]?.[bufIdx]) {
            outputs[ch][bufIdx].set(currentBuffers[ch][bufIdx]);
          }
        }
      }
    }

    return { peakLevel, clipDetected, latencySamples: totalLatency };
  }

  // ============ State ============

  /**
   * Get chain state for serialization.
   */
  getState(): PluginChainConfig {
    return JSON.parse(JSON.stringify(this.config));
  }

  /**
   * Restore chain from state.
   */
  async restoreState(state: PluginChainConfig): Promise<void> {
    // Clear current instances
    for (const instance of this.instances.values()) {
      instance.dispose();
    }
    this.instances.clear();

    // Restore config
    this.config = { ...state };

    // Recreate instances
    for (const slot of this.config.slots) {
      if (slot.instanceId) {
        // TODO: Need to restore plugin instances from saved state
        // This requires having the plugin state saved alongside
      }
    }
  }

  // ============ Helpers ============

  private createEmptySlot(position: number): PluginSlot {
    return {
      id: `slot_${this.config.id}_${position}`,
      position,
      instanceId: null,
      isBypassed: false,
      isEnabled: true,
      dryWetMix: 1.0,
      inputGain: 1.0,
      outputGain: 1.0,
    };
  }

  /**
   * Calculate total chain latency.
   */
  getTotalLatency(): number {
    let latency = 0;

    for (const slot of this.getActiveSlots()) {
      if (slot.isBypassed) continue;

      const instance = this.instances.get(slot.instanceId!);
      if (!instance) continue;

      const descriptor = PluginRegistry.get(instance.descriptorId);
      if (descriptor?.latencySamples) {
        latency += descriptor.latencySamples;
      }
    }

    return latency;
  }

  // ============ Events ============

  subscribe(callback: (event: ChainEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: ChainEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Cleanup ============

  dispose(): void {
    for (const instance of this.instances.values()) {
      instance.dispose();
    }
    this.instances.clear();
    this.listeners.clear();
  }
}

// ============ Event Types ============

export type ChainEvent =
  | { type: 'pluginInserted'; position: number; instanceId: string }
  | { type: 'pluginRemoved'; position: number; instanceId: string }
  | { type: 'pluginMoved'; fromPosition: number; toPosition: number }
  | { type: 'slotBypassed'; position: number; bypassed: boolean }
  | { type: 'slotEnabled'; position: number; enabled: boolean }
  | { type: 'mixChanged'; position: number; mix: number }
  | { type: 'chainActiveChanged'; active: boolean }
  | { type: 'parallelModeChanged'; parallel: boolean };

// ============ Chain Manager ============

class PluginChainManagerImpl {
  private chains = new Map<string, PluginChain>();

  /**
   * Create new chain.
   */
  createChain(config: Partial<PluginChainConfig> & { id: string }): PluginChain {
    const chain = new PluginChain(config);
    this.chains.set(chain.getId(), chain);
    return chain;
  }

  /**
   * Get chain.
   */
  getChain(id: string): PluginChain | undefined {
    return this.chains.get(id);
  }

  /**
   * Get all chains.
   */
  getAllChains(): PluginChain[] {
    return Array.from(this.chains.values());
  }

  /**
   * Delete chain.
   */
  deleteChain(id: string): boolean {
    const chain = this.chains.get(id);
    if (!chain) return false;

    chain.dispose();
    this.chains.delete(id);
    return true;
  }

  /**
   * Clear all chains.
   */
  clearAll(): void {
    for (const chain of this.chains.values()) {
      chain.dispose();
    }
    this.chains.clear();
  }
}

export const PluginChainManager = new PluginChainManagerImpl();

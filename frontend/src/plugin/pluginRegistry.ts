/**
 * ReelForge M9.1 Plugin Registry
 *
 * Central registry for audio processing plugins.
 * Contains Van* series plugins (VanEQ Pro, VanComp Pro, VanLimit Pro)
 * with full definitions including createDSP factories and Editor components.
 *
 * @module plugin/pluginRegistry
 */

import type { PluginDefinition } from './PluginDefinition';
import type { ParamDescriptor } from './ParamDescriptor';

// VanEQ imports
import { VANEQ_PARAM_DESCRIPTORS } from './vaneqDescriptors';
import { createVanEqDSP } from './vaneqDSP';
import VanEQProEditor from './vaneq-pro/VanEQProEditor';

// VanComp Pro imports
import { VANCOMP_PARAM_DESCRIPTORS } from './vancomp-pro/vancompDescriptors';
import { createVanCompDSP } from './vancomp-pro/vancompDSP';
import { VanCompProEditor } from './vancomp-pro/VanCompProEditor';

// VanLimit Pro imports
import { VANLIMIT_PARAM_DESCRIPTORS } from './vanlimit-pro/vanlimitDescriptors';
import { createVanLimitDSP } from './vanlimit-pro/vanlimitDSP';
import { VanLimitProEditor } from './vanlimit-pro/VanLimitProEditor';

// DSP Plugin Adapters (Reverb, Delay, Chorus, etc.)
import { DSP_PLUGINS } from './dspPluginAdapters';

// ============ Van* Series Plugin Definitions ============

/**
 * VanEQ Pro plugin definition.
 * 6-band parametric equalizer with AudioWorklet processing.
 */
const VANEQ_PLUGIN: PluginDefinition = {
  id: 'vaneq',
  displayName: 'VanEQ Pro',
  shortName: 'VanEQ',
  version: '1.0.0',
  category: 'eq',
  description: '6-band parametric equalizer with professional filter types',
  icon: '🎛️',
  params: VANEQ_PARAM_DESCRIPTORS,
  latencySamples: 0, // No lookahead latency
  createDSP: createVanEqDSP,
  Editor: VanEQProEditor,
  supportsBypass: true,
  opensInWindow: false, // Inline panel, not popup window
};

/**
 * VanComp Pro plugin definition.
 * Professional dynamics compressor with GR visualization.
 */
const VANCOMP_PLUGIN: PluginDefinition = {
  id: 'vancomp',
  displayName: 'VanComp Pro',
  shortName: 'VanComp',
  version: '1.0.0',
  category: 'dynamics',
  description: 'Professional compressor with GR meter and sidechain HPF',
  icon: '📉',
  params: VANCOMP_PARAM_DESCRIPTORS,
  latencySamples: 0,
  createDSP: createVanCompDSP,
  Editor: VanCompProEditor,
  supportsBypass: true,
  opensInWindow: true, // Opens in standalone window
};

/**
 * VanLimit Pro plugin definition.
 * Professional brick-wall limiter with waveform visualization.
 */
const VANLIMIT_PLUGIN: PluginDefinition = {
  id: 'vanlimit',
  displayName: 'VanLimit Pro',
  shortName: 'VanLimit',
  version: '1.0.0',
  category: 'dynamics',
  description: 'Brick-wall limiter with true peak limiting and oversampling',
  icon: '🧱',
  params: VANLIMIT_PARAM_DESCRIPTORS,
  latencySamples: 0,
  createDSP: createVanLimitDSP,
  Editor: VanLimitProEditor,
  supportsBypass: true,
  opensInWindow: true, // Opens in standalone window
};

// ============ Registry Implementation ============

/**
 * Internal plugin registry map.
 */
const pluginRegistry = new Map<string, PluginDefinition>();

/**
 * Initialize the registry with Van* series plugins.
 */
function initializeBuiltins(): void {
  if (pluginRegistry.size > 0) return; // Already initialized

  // Van* Series - Professional plugins
  pluginRegistry.set('vaneq', VANEQ_PLUGIN);
  pluginRegistry.set('vancomp', VANCOMP_PLUGIN);
  pluginRegistry.set('vanlimit', VANLIMIT_PLUGIN);

  // Register DSP plugins (Reverb, Delay, Chorus, Phaser, Flanger, Tremolo, Distortion, Filter)
  for (const plugin of DSP_PLUGINS) {
    pluginRegistry.set(plugin.id, plugin);
  }
}

// Initialize on module load
initializeBuiltins();

// ============ Public API ============

/**
 * Register a plugin definition.
 *
 * Registers a new plugin with the framework. The plugin must have:
 * - Unique ID (not already registered)
 * - Valid createDSP factory function
 * - Valid Editor component
 *
 * @param def - The plugin definition to register
 * @throws Error if plugin ID is already registered
 */
export function registerPlugin(def: PluginDefinition): void {
  if (pluginRegistry.has(def.id)) {
    console.warn(`[PluginRegistry] Plugin '${def.id}' is already registered`);
    return;
  }

  // Validate plugin definition
  if (!def.createDSP || typeof def.createDSP !== 'function') {
    console.error(`[PluginRegistry] Plugin '${def.id}' missing createDSP factory`);
    return;
  }

  if (!def.Editor) {
    console.error(`[PluginRegistry] Plugin '${def.id}' missing Editor component`);
    return;
  }

  pluginRegistry.set(def.id, def);

  // Notify listeners
  listeners.forEach((listener) => listener('registered', def.id));
}

/**
 * Get a plugin definition by ID.
 *
 * @param id - The plugin ID
 * @returns The plugin definition or undefined if not found
 */
export function getPluginDefinition(id: string): PluginDefinition | undefined {
  return pluginRegistry.get(id);
}

/**
 * Get all registered plugin definitions.
 *
 * @returns Array of all plugin definitions
 */
export function getAllPluginDefinitions(): PluginDefinition[] {
  return Array.from(pluginRegistry.values());
}

/**
 * Get all plugin IDs.
 *
 * @returns Array of registered plugin IDs
 */
export function getRegisteredPluginIds(): string[] {
  return Array.from(pluginRegistry.keys());
}

/**
 * Check if a plugin is registered.
 *
 * @param id - The plugin ID to check
 * @returns True if plugin is registered
 */
export function isPluginRegistered(id: string): boolean {
  return pluginRegistry.has(id);
}

/**
 * Get parameter descriptors for a plugin.
 *
 * @param pluginId - The plugin ID
 * @returns Array of parameter descriptors, or empty array if not found
 */
export function getPluginParamDescriptors(pluginId: string): ParamDescriptor[] {
  const def = pluginRegistry.get(pluginId);
  return def?.params ?? [];
}

/**
 * Get plugin latency in samples.
 *
 * @param pluginId - The plugin ID
 * @returns Latency in samples, or 0 if not found
 */
export function getPluginLatency(pluginId: string): number {
  const def = pluginRegistry.get(pluginId);
  return def?.latencySamples ?? 0;
}

/**
 * Get plugins by category.
 *
 * @param category - The category to filter by
 * @returns Array of matching plugin definitions
 */
export function getPluginsByCategory(
  category: PluginDefinition['category']
): PluginDefinition[] {
  return getAllPluginDefinitions().filter((p) => p.category === category);
}

// ============ Registry Event Stubs (M9.1) ============

/**
 * Future M9.1: Subscribe to plugin registration events.
 */
export type PluginRegistryListener = (event: 'registered' | 'unregistered', id: string) => void;

const listeners: PluginRegistryListener[] = [];

/**
 * Subscribe to registry events.
 * NOTE: Stub for M9.0.
 */
export function onPluginRegistryChange(listener: PluginRegistryListener): () => void {
  listeners.push(listener);
  return () => {
    const idx = listeners.indexOf(listener);
    if (idx >= 0) listeners.splice(idx, 1);
  };
}

/**
 * ReelForge M8.0 Master Insert Chain Types
 *
 * Studio-only insert processing for master bus preview.
 * NO runtime schema changes - this is purely studio preview.
 */

// VanEQ imports for default params
import {
  DEFAULT_VANEQ_PARAMS,
  flattenVanEqParams,
} from '../plugin/vaneqTypes';

// VanComp and VanLimit imports for default params
import { getVanCompDefaultParams } from '../plugin/vancomp-pro/vancompDescriptors';
import { getVanLimitDefaultParams } from '../plugin/vanlimit-pro/vanlimitDescriptors';

// Plugin IDs - Van* series only
// NOTE: This list must be kept in sync with registered plugins
export type PluginId = 'vaneq' | 'vancomp' | 'vanlimit';

// Stable unique ID for each insert instance
export type InsertId = string; // e.g., 'ins_1703012345678_abc123'

/**
 * Generate a stable, unique insert ID.
 * Format: ins_{timestamp}_{random4chars}
 */
export function generateInsertId(): InsertId {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 6);
  return `ins_${timestamp}_${random}`;
}

// ============ Parameter Types ============
// Van* plugins use flat Record<string, number> params defined in their descriptors

// ============ Insert Definition ============

/** Base insert definition */
export interface BaseInsert {
  /** Stable unique ID */
  id: InsertId;
  /** Plugin type */
  pluginId: PluginId;
  /** Whether insert is processing (true) or bypassed (false) */
  enabled: boolean;
}

/** VanEQ Insert - uses flat params for framework compatibility */
export interface VanEqInsert extends BaseInsert {
  pluginId: 'vaneq';
  params: Record<string, number>; // Flat params format
}

/** VanComp Pro Insert - uses flat params */
export interface VanCompInsert extends BaseInsert {
  pluginId: 'vancomp';
  params: Record<string, number>; // Flat params format
}

/** VanLimit Pro Insert - uses flat params */
export interface VanLimitInsert extends BaseInsert {
  pluginId: 'vanlimit';
  params: Record<string, number>; // Flat params format
}

/** Union of all insert types */
export type MasterInsert = VanEqInsert | VanCompInsert | VanLimitInsert;

/**
 * Generic insert type - same as MasterInsert but with a more generic name
 * for use in bus insert chains. The insert structure is identical.
 */
export type Insert = MasterInsert;

// ============ Chain Definition ============

/**
 * Generic insert chain (ordered array).
 * Used for both master and bus insert chains.
 */
export interface InsertChain {
  /** Ordered list of inserts (first = closest to input) */
  inserts: Insert[];
}

/** Master insert chain (ordered array) - alias for backwards compatibility */
export interface MasterInsertChain {
  /** Ordered list of inserts (first = closest to master gain) */
  inserts: MasterInsert[];
}

// ============ Default Parameter Values ============

export const EMPTY_INSERT_CHAIN: MasterInsertChain = {
  inserts: [],
};

// ============ Parameter Constraints ============
// Van* plugins use their own descriptor-based constraints

/** Valid plugin IDs - must match registered plugins in pluginRegistry */
export const VALID_PLUGIN_IDS: PluginId[] = ['vaneq', 'vancomp', 'vanlimit'];

// ============ Latency Calculation ============

/** Estimated latency per plugin type (samples @ 48kHz) */
export const PLUGIN_LATENCY_SAMPLES: Record<PluginId, number> = {
  vaneq: 0, // VanEQ AudioWorklet has no lookahead
  vancomp: 0, // VanComp Pro has no lookahead
  vanlimit: 64, // VanLimit Pro has 64-sample lookahead
};

/** Calculate total chain latency in samples */
export function calculateChainLatencySamples(chain: MasterInsertChain): number {
  return chain.inserts
    .filter((ins) => ins.enabled)
    .reduce((sum, ins) => sum + PLUGIN_LATENCY_SAMPLES[ins.pluginId], 0);
}

/** Calculate total chain latency in milliseconds */
export function calculateChainLatencyMs(
  chain: MasterInsertChain,
  sampleRate = 48000
): number {
  const samples = calculateChainLatencySamples(chain);
  return (samples / sampleRate) * 1000;
}

// ============ Factory Functions ============

/**
 * Create a default insert for a given plugin type.
 * @throws Error if pluginId is not a valid PluginId
 */
export function createDefaultInsert(pluginId: PluginId): MasterInsert {
  // Validate pluginId at runtime to prevent undefined inserts
  if (!VALID_PLUGIN_IDS.includes(pluginId)) {
    throw new Error(
      `RF_ERR_INVALID_PLUGIN: Unknown plugin ID "${pluginId}". Valid IDs: ${VALID_PLUGIN_IDS.join(', ')}`
    );
  }

  const id = generateInsertId();

  switch (pluginId) {
    case 'vaneq':
      return {
        id,
        pluginId: 'vaneq',
        enabled: true,
        params: flattenVanEqParams(structuredClone(DEFAULT_VANEQ_PARAMS)),
      };
    case 'vancomp':
      return {
        id,
        pluginId: 'vancomp',
        enabled: true,
        params: getVanCompDefaultParams(),
      };
    case 'vanlimit':
      return {
        id,
        pluginId: 'vanlimit',
        enabled: true,
        params: getVanLimitDefaultParams(),
      };
    default: {
      // Exhaustive check - this should never happen due to validation above
      const _exhaustive: never = pluginId;
      throw new Error(`RF_ERR_INVALID_PLUGIN: Unhandled plugin ID "${_exhaustive}"`);
    }
  }
}

/** Create an empty insert chain */
export function createEmptyChain(): MasterInsertChain {
  return { inserts: [] };
}

// ============ Validation Helpers ============

/**
 * Validate an insert is not null/undefined and has required fields.
 * @returns true if valid, false otherwise
 */
export function isValidInsert(insert: unknown): insert is Insert {
  if (!insert || typeof insert !== 'object') return false;
  const ins = insert as Record<string, unknown>;
  return (
    typeof ins.id === 'string' &&
    ins.id.length > 0 &&
    typeof ins.pluginId === 'string' &&
    VALID_PLUGIN_IDS.includes(ins.pluginId as PluginId) &&
    typeof ins.enabled === 'boolean' &&
    ins.params !== undefined &&
    ins.params !== null
  );
}

/**
 * Filter and sanitize inserts array, removing any invalid entries.
 * Logs RF_ERR_INVALID_INSERT for each invalid entry found.
 * @param inserts - Array that may contain null/undefined/invalid inserts
 * @param chainId - Identifier for error messages (e.g., 'master', 'bus:music')
 * @returns Array with only valid inserts
 */
export function sanitizeInserts(
  inserts: (Insert | null | undefined)[],
  chainId: string
): Insert[] {
  const valid: Insert[] = [];

  for (let i = 0; i < inserts.length; i++) {
    const insert = inserts[i];
    if (isValidInsert(insert)) {
      valid.push(insert);
    } else {
      // Log detailed error for debugging
      console.error(
        `RF_ERR_INVALID_INSERT: Invalid insert at index ${i} in chain "${chainId}". ` +
        `Value: ${JSON.stringify(insert)}. Skipping.`
      );
    }
  }

  return valid;
}

// ============ UI Display Config ============

/** Plugin display configuration for UI components */
export interface PluginDisplayConfig {
  /** Icon to display (emoji or icon class) */
  icon: string;
  /** Short label for the plugin */
  label: string;
  /** Full name (optional) */
  fullName?: string;
}

/**
 * Shared plugin display config for all insert panel components.
 * Keeps icons and labels consistent across Master, Bus, and Asset panels.
 */
export const PLUGIN_DISPLAY_CONFIG: Record<PluginId, PluginDisplayConfig> = {
  vaneq: { icon: '🎛️', label: 'VanEQ', fullName: 'VanEQ Pro' },
  vancomp: { icon: '📉', label: 'VanComp', fullName: 'VanComp Pro' },
  vanlimit: { icon: '🧱', label: 'VanLimit', fullName: 'VanLimit Pro' },
};

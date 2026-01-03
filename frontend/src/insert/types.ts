/**
 * ReelForge M9.1 Insert Chain Types
 *
 * Core types for the insert chain system.
 * Re-exports from masterInsertTypes for backwards compatibility
 * while establishing clear module boundary.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 *
 * @module insert/types
 */

// Re-export all insert types from the original module
export type {
  PluginId,
  InsertId,
  BaseInsert,
  VanEqInsert,
  VanCompInsert,
  VanLimitInsert,
  MasterInsert,
  Insert,
  InsertChain,
  MasterInsertChain,
} from '../core/masterInsertTypes';

// Re-export constants
export {
  EMPTY_INSERT_CHAIN,
  VALID_PLUGIN_IDS,
  PLUGIN_LATENCY_SAMPLES,
} from '../core/masterInsertTypes';

// Re-export functions
export {
  generateInsertId,
  calculateChainLatencySamples,
  calculateChainLatencyMs,
  createDefaultInsert,
  createEmptyChain,
} from '../core/masterInsertTypes';

// Plugin latency samples for backwards compatibility
export const PLUGIN_LATENCY_SAMPLES_COMPAT = {
  vaneq: 0,
  vancomp: 0,
  vanlimit: 64,
} as const;

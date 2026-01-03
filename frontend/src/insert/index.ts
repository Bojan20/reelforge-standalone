/**
 * ReelForge M9.0 Insert Module
 *
 * Central exports for the insert chain system.
 * This is the public API for the insert infrastructure.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 *
 * @module insert
 */

// Core types
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
} from './types';

// Constants
export {
  EMPTY_INSERT_CHAIN,
  VALID_PLUGIN_IDS,
  PLUGIN_LATENCY_SAMPLES,
} from './types';

// Type factory functions
export {
  generateInsertId,
  createDefaultInsert,
  createEmptyChain,
} from './types';

// Host interfaces
export type {
  InsertChainHost,
  InsertChainHostWithBypass,
  InsertChainHostWithPDC,
} from './InsertChainHost';

export { hostSupportssBypass, hostSupportsPDC } from './InsertChainHost';

// Latency utilities
export {
  DEFAULT_SAMPLE_RATE,
  MAX_PDC_DELAY_SECONDS,
  MAX_PDC_DELAY_MS,
  PDC_RAMP_TIME_SECONDS,
  BYPASS_RAMP_TIME_SECONDS,
  getPluginLatencySamples,
  getPluginLatencyMs,
  calculateChainLatency,
  calculateChainLatencyMs,
  calculatePdcDelaySeconds,
  isPdcClamped,
  getLatencyInfo,
} from './latency';

export type { LatencyInfo } from './latency';

// Clone utilities
export {
  cloneChain,
  cloneInsert,
  cloneInsertWithNewId,
  cloneChainWithNewIds,
  chainsEqual,
  insertsEqual,
} from './clone';

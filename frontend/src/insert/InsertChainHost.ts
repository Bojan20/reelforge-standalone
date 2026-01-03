/**
 * ReelForge M9.0 Insert Chain Host Interface
 *
 * Shared interface for all insert chain hosts (Asset, Bus, Master).
 * This abstraction enables future plugin framework integration
 * and unified chain management.
 *
 * @module insert/InsertChainHost
 */

import type { InsertChain, Insert, InsertId } from './types';

/**
 * Common interface for insert chain hosts.
 *
 * Implemented by:
 * - VoiceInsertDSP (per-voice chains)
 * - BusInsertDSP (per-bus chains)
 * - MasterInsertDSP (master chain)
 *
 * Each host manages WebAudio nodes for processing inserts
 * but the interface abstracts away the specific node topology.
 *
 * @example
 * ```typescript
 * // All hosts share the same core operations:
 * host.applyChain(chain);
 * const latency = host.getLatencySamples();
 * host.dispose();
 * ```
 */
export interface InsertChainHost {
  /**
   * Apply a complete insert chain configuration.
   * Rebuilds the node graph as needed (add/remove/reorder).
   *
   * @param chain - The insert chain to apply
   */
  applyChain(chain: InsertChain): void;

  /**
   * Get current chain latency in samples.
   * Used for PDC (Preview Delay Compensation) calculations.
   *
   * @returns Total latency of enabled inserts in samples
   */
  getLatencySamples(): number;

  /**
   * Dispose of all DSP resources.
   * Disconnects all nodes and clears internal state.
   * Safe to call multiple times (idempotent).
   */
  dispose(): void;
}

/**
 * Extended host interface with bypass control.
 * Used by hosts that support per-insert bypass toggling.
 */
export interface InsertChainHostWithBypass extends InsertChainHost {
  /**
   * Toggle insert bypass with click-free crossfade.
   *
   * @param insertId - The insert to toggle
   * @param enabled - True for processing, false for bypass
   */
  setInsertEnabled(insertId: InsertId, enabled: boolean): void;

  /**
   * Update insert parameters in real-time.
   *
   * @param insert - Insert with updated params
   */
  updateInsertParams(insert: Insert): void;
}

/**
 * Host interface with PDC (Preview Delay Compensation) support.
 * Used by Bus and Master hosts.
 */
export interface InsertChainHostWithPDC extends InsertChainHostWithBypass {
  /**
   * Enable or disable PDC.
   * When enabled, adds delay before chain to compensate for latency.
   *
   * @param enabled - Whether PDC is enabled
   */
  setPdcEnabled(enabled: boolean): void;

  /**
   * Check if PDC is currently enabled.
   *
   * @returns True if PDC is enabled
   */
  isPdcEnabled(): boolean;

  /**
   * Get current compensation delay in milliseconds.
   *
   * @returns Delay time in ms (0 if PDC disabled)
   */
  getCompensationDelayMs(): number;

  /**
   * Check if compensation is clamped to max.
   *
   * @returns True if latency exceeds max delay
   */
  isCompensationClamped(): boolean;
}

/**
 * Type guard to check if host supports bypass control.
 */
export function hostSupportssBypass(
  host: InsertChainHost
): host is InsertChainHostWithBypass {
  return (
    'setInsertEnabled' in host &&
    'updateInsertParams' in host &&
    typeof (host as InsertChainHostWithBypass).setInsertEnabled === 'function'
  );
}

/**
 * Type guard to check if host supports PDC.
 */
export function hostSupportsPDC(
  host: InsertChainHost
): host is InsertChainHostWithPDC {
  return (
    'setPdcEnabled' in host &&
    'isPdcEnabled' in host &&
    typeof (host as InsertChainHostWithPDC).setPdcEnabled === 'function'
  );
}

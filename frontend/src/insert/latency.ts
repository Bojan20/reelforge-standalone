/**
 * ReelForge M9.0 Latency Utilities
 *
 * Shared utilities for latency calculation and PDC management.
 * Used by all insert chain hosts for consistent latency handling.
 *
 * @module insert/latency
 */

import type { InsertChain, PluginId } from './types';
import { PLUGIN_LATENCY_SAMPLES } from './types';

/**
 * Default sample rate for latency calculations when AudioContext unavailable.
 */
export const DEFAULT_SAMPLE_RATE = 48000;

/**
 * Maximum PDC delay time in seconds.
 * Shared across all hosts (Bus, Master).
 */
export const MAX_PDC_DELAY_SECONDS = 0.5; // 500ms

/**
 * Maximum PDC delay time in milliseconds.
 */
export const MAX_PDC_DELAY_MS = MAX_PDC_DELAY_SECONDS * 1000;

/**
 * Click-free ramp time for delay updates in seconds.
 */
export const PDC_RAMP_TIME_SECONDS = 0.01; // 10ms

/**
 * Click-free ramp time for bypass transitions in seconds.
 */
export const BYPASS_RAMP_TIME_SECONDS = 0.01; // 10ms

/**
 * Get latency in samples for a plugin type.
 *
 * @param pluginId - The plugin type
 * @returns Latency in samples
 */
export function getPluginLatencySamples(pluginId: PluginId): number {
  return PLUGIN_LATENCY_SAMPLES[pluginId] ?? 0;
}

/**
 * Get latency in milliseconds for a plugin type.
 *
 * @param pluginId - The plugin type
 * @param sampleRate - Sample rate (defaults to 48kHz)
 * @returns Latency in milliseconds
 */
export function getPluginLatencyMs(
  pluginId: PluginId,
  sampleRate = DEFAULT_SAMPLE_RATE
): number {
  const samples = getPluginLatencySamples(pluginId);
  return (samples / sampleRate) * 1000;
}

/**
 * Calculate total chain latency in samples.
 * Only counts enabled inserts.
 *
 * @param chain - The insert chain
 * @returns Total latency in samples
 */
export function calculateChainLatency(chain: InsertChain): number {
  let total = 0;
  for (const insert of chain.inserts) {
    if (insert.enabled) {
      total += getPluginLatencySamples(insert.pluginId);
    }
  }
  return total;
}

/**
 * Calculate total chain latency in milliseconds.
 *
 * @param chain - The insert chain
 * @param sampleRate - Sample rate (defaults to 48kHz)
 * @returns Total latency in milliseconds
 */
export function calculateChainLatencyMs(
  chain: InsertChain,
  sampleRate = DEFAULT_SAMPLE_RATE
): number {
  const samples = calculateChainLatency(chain);
  return (samples / sampleRate) * 1000;
}

/**
 * Calculate PDC delay needed for a chain.
 * Returns 0 if chain has no latency.
 * Clamps to MAX_PDC_DELAY_SECONDS if latency exceeds limit.
 *
 * @param chain - The insert chain
 * @param sampleRate - Sample rate
 * @returns Delay time in seconds, clamped to max
 */
export function calculatePdcDelaySeconds(
  chain: InsertChain,
  sampleRate = DEFAULT_SAMPLE_RATE
): number {
  const latencySamples = calculateChainLatency(chain);
  const latencySeconds = latencySamples / sampleRate;
  return Math.min(latencySeconds, MAX_PDC_DELAY_SECONDS);
}

/**
 * Check if chain latency exceeds PDC maximum.
 *
 * @param chain - The insert chain
 * @param sampleRate - Sample rate
 * @returns True if latency exceeds max and will be clamped
 */
export function isPdcClamped(
  chain: InsertChain,
  sampleRate = DEFAULT_SAMPLE_RATE
): boolean {
  const latencySamples = calculateChainLatency(chain);
  const latencySeconds = latencySamples / sampleRate;
  return latencySeconds > MAX_PDC_DELAY_SECONDS;
}

/**
 * Latency calculation result with both samples and ms.
 */
export interface LatencyInfo {
  samples: number;
  ms: number;
  pdcDelaySeconds: number;
  pdcClamped: boolean;
}

/**
 * Calculate full latency info for a chain.
 *
 * @param chain - The insert chain
 * @param sampleRate - Sample rate
 * @returns Complete latency information
 */
export function getLatencyInfo(
  chain: InsertChain,
  sampleRate = DEFAULT_SAMPLE_RATE
): LatencyInfo {
  const samples = calculateChainLatency(chain);
  const ms = (samples / sampleRate) * 1000;
  const latencySeconds = samples / sampleRate;
  const pdcClamped = latencySeconds > MAX_PDC_DELAY_SECONDS;
  const pdcDelaySeconds = Math.min(latencySeconds, MAX_PDC_DELAY_SECONDS);

  return {
    samples,
    ms,
    pdcDelaySeconds,
    pdcClamped,
  };
}

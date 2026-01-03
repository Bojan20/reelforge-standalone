/**
 * ReelForge M8.6 Diagnostics Snapshot Hook
 *
 * Aggregates diagnostic data from all DSP modules into a single snapshot
 * for the Latency HUD. This is a read-only observability layer.
 *
 * Data sources:
 * - AssetInsertContext: voice chain counts
 * - BusInsertContext: bus latency, PDC state, ducking state
 * - MasterInsertContext: master latency, PDC state
 * - PreviewMixContext: voice counts per bus
 */

import { useState, useEffect, useCallback } from 'react';
import { useAssetInserts } from './AssetInsertContext';
import { useBusInserts } from './BusInsertContext';
import { useMasterInserts } from './MasterInsertContext';
import { usePreviewMix } from './PreviewMixContext';
import { dspMetrics, type DSPMetricsSnapshot } from './dspMetrics';
import type { BusId } from './types';
import type { InsertableBusId } from '../project/projectTypes';

/** Voice chain warning threshold (from voiceInsertDSP) */
export const VOICE_CHAIN_WARN_THRESHOLD = 16;

/** Insertable bus IDs for iteration */
export const INSERTABLE_BUS_IDS: InsertableBusId[] = ['music', 'sfx', 'ambience', 'voice'];

/** Per-bus latency snapshot */
export interface BusLatencySnapshot {
  busId: InsertableBusId;
  latencyMs: number;
  pdcEnabled: boolean;
  pdcDelayMs: number;
  pdcClamped: boolean;
  pdcMaxMs: number;
}

/** Ducking state snapshot */
export interface DuckingSnapshot {
  isDucking: boolean;
  duckerVoiceCount: number;
  duckerBus: InsertableBusId;
  duckedBus: InsertableBusId;
  duckRatio: number;
  currentDuckGain: number;
}

/** Voice health snapshot */
export interface VoiceHealthSnapshot {
  totalVoices: number;
  voicesByBus: Record<BusId, number>;
  activeAssetChains: number;
  chainThresholdExceeded: boolean;
}

/** Warning entry */
export interface DiagnosticsWarning {
  id: string;
  message: string;
  severity: 'warning' | 'error';
}

/** Complete diagnostics snapshot */
export interface DiagnosticsSnapshot {
  /** Timestamp of snapshot */
  timestamp: number;

  /** Asset/voice insert average latency (0 since no PDC at asset level) */
  assetLatencyMs: number;

  /** Per-bus latency and PDC state */
  busLatencies: BusLatencySnapshot[];

  /** Master insert latency and PDC state */
  masterLatencyMs: number;
  masterPdcEnabled: boolean;
  masterPdcDelayMs: number;
  masterPdcClamped: boolean;
  masterPdcMaxMs: number;

  /** Total latency for a given bus path (asset + bus + master) */
  totalLatencyByBus: Record<InsertableBusId, number>;

  /** Ducking state */
  ducking: DuckingSnapshot;

  /** Voice health */
  voiceHealth: VoiceHealthSnapshot;

  /** DSP resource metrics (optional, M8.8) */
  dspMetrics?: DSPMetricsSnapshot;

  /** Active warnings */
  warnings: DiagnosticsWarning[];
}

/** HUD refresh rate in ms (targeting ~12 Hz) */
const REFRESH_INTERVAL_MS = 83;

/** Ducking configuration constants */
const DUCKING_CONFIG = {
  DUCKER_BUS: 'voice' as InsertableBusId,
  DUCKED_BUS: 'music' as InsertableBusId,
  DUCK_RATIO: 0.35,
};

/**
 * Hook that provides a periodically-updated diagnostics snapshot.
 * Polls DSP state at ~12 Hz for smooth HUD updates.
 */
export function useDiagnosticsSnapshot(): DiagnosticsSnapshot {
  const assetInserts = useAssetInserts();
  const busInserts = useBusInserts();
  const masterInserts = useMasterInserts();
  const previewMix = usePreviewMix();

  const createSnapshot = useCallback((): DiagnosticsSnapshot => {
    const timestamp = Date.now();

    // Asset latency: 0ms since no PDC at asset level
    // (Each voice chain has latency but it's not compensated)
    const assetLatencyMs = 0;

    // Gather bus latencies
    const busLatencies: BusLatencySnapshot[] = INSERTABLE_BUS_IDS.map((busId) => ({
      busId,
      latencyMs: busInserts.getLatencyMs(busId),
      pdcEnabled: busInserts.isBusPdcEnabled(busId),
      pdcDelayMs: busInserts.getBusPdcDelayMs(busId),
      pdcClamped: busInserts.isBusPdcClamped(busId),
      pdcMaxMs: busInserts.getBusPdcMaxMs(),
    }));

    // Master latency
    const masterLatencyMs = masterInserts.latencyMs;
    const masterPdcEnabled = masterInserts.pdcEnabled;
    const masterPdcDelayMs = masterInserts.compensationDelayMs;
    const masterPdcClamped = masterInserts.pdcClamped;
    const masterPdcMaxMs = 500; // Same as BUS_PDC_CONFIG.MAX_DELAY_TIME * 1000

    // Calculate total latency per bus path
    const totalLatencyByBus: Record<InsertableBusId, number> = {} as Record<InsertableBusId, number>;
    for (const busLatency of busLatencies) {
      totalLatencyByBus[busLatency.busId] =
        assetLatencyMs + busLatency.latencyMs + masterLatencyMs;
    }

    // Ducking state
    const duckingState = busInserts.getDuckingState();
    const ducking: DuckingSnapshot = {
      isDucking: duckingState.isDucking,
      duckerVoiceCount: duckingState.duckerVoiceCount,
      duckerBus: DUCKING_CONFIG.DUCKER_BUS,
      duckedBus: DUCKING_CONFIG.DUCKED_BUS,
      duckRatio: DUCKING_CONFIG.DUCK_RATIO,
      currentDuckGain: busInserts.getDuckGainValue(DUCKING_CONFIG.DUCKED_BUS),
    };

    // Voice health
    const voicesByBus = previewMix.getVoicesByBus();
    const totalVoices = previewMix.getTotalVoices();
    const activeAssetChains = assetInserts.getActiveVoiceChainCount();
    const chainThresholdExceeded = activeAssetChains >= VOICE_CHAIN_WARN_THRESHOLD;

    const voiceHealth: VoiceHealthSnapshot = {
      totalVoices,
      voicesByBus,
      activeAssetChains,
      chainThresholdExceeded,
    };

    // Aggregate warnings
    const warnings: DiagnosticsWarning[] = [];

    // Check for PDC clamps
    for (const busLatency of busLatencies) {
      if (busLatency.pdcEnabled && busLatency.pdcClamped) {
        warnings.push({
          id: `pdc-clamp-${busLatency.busId}`,
          message: `${busLatency.busId.charAt(0).toUpperCase() + busLatency.busId.slice(1)} bus PDC clamped`,
          severity: 'warning',
        });
      }
    }

    if (masterPdcEnabled && masterPdcClamped) {
      warnings.push({
        id: 'pdc-clamp-master',
        message: 'Master PDC clamped',
        severity: 'warning',
      });
    }

    // Check voice chain threshold
    if (chainThresholdExceeded) {
      warnings.push({
        id: 'voice-chain-threshold',
        message: `Asset chain threshold exceeded (${activeAssetChains}/${VOICE_CHAIN_WARN_THRESHOLD})`,
        severity: 'warning',
      });
    }

    // Get DSP metrics snapshot
    const dspMetricsSnapshot = dspMetrics.getSnapshot();

    // Check for DSP anomalies
    if (dspMetricsSnapshot.hasAnomalies) {
      warnings.push({
        id: 'dsp-anomaly',
        message: 'DSP resource anomaly detected (check console)',
        severity: 'error',
      });
    }

    return {
      timestamp,
      assetLatencyMs,
      busLatencies,
      masterLatencyMs,
      masterPdcEnabled,
      masterPdcDelayMs,
      masterPdcClamped,
      masterPdcMaxMs,
      totalLatencyByBus,
      ducking,
      voiceHealth,
      dspMetrics: dspMetricsSnapshot,
      warnings,
    };
  }, [assetInserts, busInserts, masterInserts, previewMix]);

  const [snapshot, setSnapshot] = useState<DiagnosticsSnapshot>(() => createSnapshot());

  useEffect(() => {
    // Update immediately
    setSnapshot(createSnapshot());

    // Poll at refresh interval
    const interval = setInterval(() => {
      setSnapshot(createSnapshot());
    }, REFRESH_INTERVAL_MS);

    return () => clearInterval(interval);
  }, [createSnapshot]);

  return snapshot;
}

/**
 * Format latency value for display.
 */
export function formatLatency(ms: number): string {
  if (ms === 0) return '0.0 ms';
  if (ms < 0.1) return '<0.1 ms';
  return `${ms.toFixed(1)} ms`;
}

/**
 * Format PDC state for display.
 */
export function formatPdcState(enabled: boolean, clamped: boolean): string {
  if (!enabled) return 'OFF';
  if (clamped) return 'ON!';
  return 'ON';
}

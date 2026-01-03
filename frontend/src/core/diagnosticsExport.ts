/**
 * ReelForge M8.6 Diagnostics Export
 *
 * Export functionality for diagnostics snapshots:
 * - Stable JSON stringification with sorted keys
 * - Full export snapshot with header metadata
 * - Copy to clipboard
 * - Download as file
 * - Human-readable text summary
 */

import type {
  DiagnosticsSnapshot,
  DiagnosticsWarning,
} from './useDiagnosticsSnapshot';
import { VOICE_CHAIN_WARN_THRESHOLD } from './useDiagnosticsSnapshot';
import type { InsertableBusId } from '../project/projectTypes';

/** App version from package.json (injected at build time or fallback) */
const APP_VERSION = '0.9.0-m8.7';

/** Header metadata for export */
export interface ExportHeader {
  timestamp: string;
  timestampMs: number;
  appVersion: string;
  projectName: string | null;
  projectId: string | null;
  viewMode: string | null;
  sampleRate: number | null;
  audioContextState: string | null;
}

/** Latency section for export */
export interface ExportLatency {
  assetLatencyMs: number;
  busLatencyMs: Record<InsertableBusId, number>;
  masterLatencyMs: number;
  totalMusicPathMs: number;
  totalMaxPathMs: number;
}

/** PDC section for export */
export interface ExportPdc {
  master: {
    enabled: boolean;
    appliedMs: number;
    maxMs: number;
    clamped: boolean;
  };
  buses: Record<InsertableBusId, {
    enabled: boolean;
    appliedMs: number;
    maxMs: number;
    clamped: boolean;
  }>;
}

/** Ducking section for export */
export interface ExportDucking {
  policy: {
    duckerBus: InsertableBusId;
    duckedBus: InsertableBusId;
    ratio: number;
  };
  state: {
    active: boolean;
    currentDuckGain: number;
    duckerVoiceCount: number;
  };
}

/** Voices section for export */
export interface ExportVoices {
  totalActiveVoices: number;
  perBusVoiceCounts: Record<string, number>;
  activeAssetChains: number;
  chainThreshold: number;
  chainThresholdExceeded: boolean;
}

/** DSP metrics section for export */
export interface ExportDspMetrics {
  activeGraphs: number;
  peakActive: number;
  totalCreated: number;
  totalDisposed: number;
  hasAnomalies: boolean;
}

/** Full export snapshot */
export interface DiagnosticsExportSnapshot {
  header: ExportHeader;
  latency: ExportLatency;
  pdc: ExportPdc;
  ducking: ExportDucking;
  voices: ExportVoices;
  dspMetrics?: ExportDspMetrics;
  warnings: DiagnosticsWarning[];
}

/** Context for building export snapshots */
export interface ExportContext {
  projectName?: string | null;
  projectId?: string | null;
  viewMode?: string | null;
  audioContext?: AudioContext | null;
}

/**
 * Recursively sort object keys for deterministic output.
 * Arrays maintain their order, objects get sorted keys.
 */
export function sortObjectKeys<T>(obj: T): T {
  if (obj === null || obj === undefined) {
    return obj;
  }

  if (Array.isArray(obj)) {
    return obj.map(sortObjectKeys) as T;
  }

  if (typeof obj === 'object' && obj !== null) {
    const sorted: Record<string, unknown> = {};
    const keys = Object.keys(obj as Record<string, unknown>).sort();
    for (const key of keys) {
      sorted[key] = sortObjectKeys((obj as Record<string, unknown>)[key]);
    }
    return sorted as T;
  }

  return obj;
}

/**
 * Stringify with stable key ordering.
 * Two snapshots taken back-to-back differ only by timestamp and live values.
 */
export function stringifyStable(obj: unknown, pretty = true): string {
  const sorted = sortObjectKeys(obj);
  return pretty ? JSON.stringify(sorted, null, 2) : JSON.stringify(sorted);
}

/**
 * Build full export snapshot from diagnostics snapshot and context.
 */
export function buildExportSnapshot(
  snapshot: DiagnosticsSnapshot,
  context: ExportContext = {}
): DiagnosticsExportSnapshot {
  // Header
  const header: ExportHeader = {
    appVersion: APP_VERSION,
    audioContextState: context.audioContext?.state ?? null,
    projectId: context.projectId ?? null,
    projectName: context.projectName ?? null,
    sampleRate: context.audioContext?.sampleRate ?? null,
    timestamp: new Date(snapshot.timestamp).toISOString(),
    timestampMs: snapshot.timestamp,
    viewMode: context.viewMode ?? null,
  };

  // Latency
  const busLatencyMs: Record<InsertableBusId, number> = {} as Record<InsertableBusId, number>;
  for (const bus of snapshot.busLatencies) {
    busLatencyMs[bus.busId] = bus.latencyMs;
  }

  const totalMusicPathMs = snapshot.totalLatencyByBus['music'] ?? 0;
  const totalMaxPathMs = Math.max(...Object.values(snapshot.totalLatencyByBus), 0);

  const latency: ExportLatency = {
    assetLatencyMs: snapshot.assetLatencyMs,
    busLatencyMs,
    masterLatencyMs: snapshot.masterLatencyMs,
    totalMaxPathMs,
    totalMusicPathMs,
  };

  // PDC
  const pdcBuses: ExportPdc['buses'] = {} as ExportPdc['buses'];
  for (const bus of snapshot.busLatencies) {
    pdcBuses[bus.busId] = {
      appliedMs: bus.pdcDelayMs,
      clamped: bus.pdcClamped,
      enabled: bus.pdcEnabled,
      maxMs: bus.pdcMaxMs,
    };
  }

  const pdc: ExportPdc = {
    buses: pdcBuses,
    master: {
      appliedMs: snapshot.masterPdcDelayMs,
      clamped: snapshot.masterPdcClamped,
      enabled: snapshot.masterPdcEnabled,
      maxMs: snapshot.masterPdcMaxMs,
    },
  };

  // Ducking
  const ducking: ExportDucking = {
    policy: {
      duckedBus: snapshot.ducking.duckedBus,
      duckerBus: snapshot.ducking.duckerBus,
      ratio: snapshot.ducking.duckRatio,
    },
    state: {
      active: snapshot.ducking.isDucking,
      currentDuckGain: snapshot.ducking.currentDuckGain,
      duckerVoiceCount: snapshot.ducking.duckerVoiceCount,
    },
  };

  // Voices
  const voices: ExportVoices = {
    activeAssetChains: snapshot.voiceHealth.activeAssetChains,
    chainThreshold: VOICE_CHAIN_WARN_THRESHOLD,
    chainThresholdExceeded: snapshot.voiceHealth.chainThresholdExceeded,
    perBusVoiceCounts: { ...snapshot.voiceHealth.voicesByBus },
    totalActiveVoices: snapshot.voiceHealth.totalVoices,
  };

  // DSP metrics (optional, M8.8+)
  const dspMetrics: ExportDspMetrics | undefined = snapshot.dspMetrics
    ? {
        activeGraphs: snapshot.dspMetrics.activeGraphs,
        hasAnomalies: snapshot.dspMetrics.hasAnomalies,
        peakActive: snapshot.dspMetrics.peakActive,
        totalCreated: snapshot.dspMetrics.totalCreated,
        totalDisposed: snapshot.dspMetrics.totalDisposed,
      }
    : undefined;

  return {
    dspMetrics,
    ducking,
    header,
    latency,
    pdc,
    voices,
    warnings: snapshot.warnings.map(w => ({
      id: w.id,
      message: w.message,
      severity: w.severity,
    })),
  };
}

/**
 * Generate filename for snapshot download.
 * Format: reelforge-diagnostics-YYYYMMDD-HHMMSS.json
 */
export function generateFilename(timestamp: number = Date.now()): string {
  const d = new Date(timestamp);
  const pad = (n: number) => n.toString().padStart(2, '0');

  const date = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
  const time = `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;

  return `reelforge-diagnostics-${date}-${time}.json`;
}

/**
 * Copy JSON snapshot to clipboard.
 * Returns true on success, error message on failure.
 */
export async function copySnapshotToClipboard(
  snapshot: DiagnosticsSnapshot,
  context: ExportContext = {}
): Promise<{ success: true } | { success: false; error: string }> {
  try {
    const exportSnapshot = buildExportSnapshot(snapshot, context);
    const json = stringifyStable(exportSnapshot);

    if (!navigator.clipboard) {
      return { success: false, error: 'Clipboard API not available' };
    }

    await navigator.clipboard.writeText(json);
    return { success: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Download snapshot as JSON file.
 * Returns true on success, error message on failure.
 */
export function downloadSnapshot(
  snapshot: DiagnosticsSnapshot,
  context: ExportContext = {}
): { success: true; filename: string } | { success: false; error: string } {
  try {
    const exportSnapshot = buildExportSnapshot(snapshot, context);
    const json = stringifyStable(exportSnapshot);
    const filename = generateFilename(snapshot.timestamp);

    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    return { success: true, filename };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, error: message };
  }
}

/**
 * Format latency value for text summary.
 */
function formatMs(ms: number): string {
  if (ms === 0) return '0.0 ms';
  if (ms < 0.1) return '<0.1 ms';
  return `${ms.toFixed(1)} ms`;
}

/**
 * Generate human-readable text summary.
 */
export function generateTextSummary(
  snapshot: DiagnosticsSnapshot,
  context: ExportContext = {}
): string {
  const lines: string[] = [];

  // Header
  lines.push('=== ReelForge Diagnostics Snapshot ===');
  lines.push(`Timestamp: ${new Date(snapshot.timestamp).toISOString()}`);
  lines.push(`Version: ${APP_VERSION}`);
  if (context.projectName) {
    lines.push(`Project: ${context.projectName}`);
  }
  if (context.audioContext) {
    lines.push(`Sample Rate: ${context.audioContext.sampleRate} Hz`);
    lines.push(`Audio State: ${context.audioContext.state}`);
  }
  lines.push('');

  // Latency
  lines.push('--- LATENCY ---');
  lines.push(`Asset (avg): ${formatMs(snapshot.assetLatencyMs)}`);
  for (const bus of snapshot.busLatencies) {
    const pdcTag = bus.pdcEnabled ? (bus.pdcClamped ? ' [PDC!]' : ' [PDC]') : '';
    lines.push(`Bus ${bus.busId}: ${formatMs(bus.latencyMs)}${pdcTag}`);
  }
  const masterPdcTag = snapshot.masterPdcEnabled
    ? (snapshot.masterPdcClamped ? ' [PDC!]' : ' [PDC]')
    : '';
  lines.push(`Master: ${formatMs(snapshot.masterLatencyMs)}${masterPdcTag}`);
  const maxTotal = Math.max(...Object.values(snapshot.totalLatencyByBus), 0);
  lines.push(`Total (max): ${formatMs(maxTotal)}`);
  lines.push('');

  // PDC
  lines.push('--- PDC STATE ---');
  for (const bus of snapshot.busLatencies) {
    const state = bus.pdcEnabled ? 'ON' : 'OFF';
    const clamped = bus.pdcEnabled && bus.pdcClamped ? ' CLAMPED!' : '';
    lines.push(`${bus.busId}: ${state} (${bus.pdcDelayMs.toFixed(1)}/${bus.pdcMaxMs} ms)${clamped}`);
  }
  const masterState = snapshot.masterPdcEnabled ? 'ON' : 'OFF';
  const masterClamped = snapshot.masterPdcEnabled && snapshot.masterPdcClamped ? ' CLAMPED!' : '';
  lines.push(`master: ${masterState} (${snapshot.masterPdcDelayMs.toFixed(1)}/${snapshot.masterPdcMaxMs} ms)${masterClamped}`);
  lines.push('');

  // Ducking
  lines.push('--- DUCKING ---');
  const { ducking } = snapshot;
  lines.push(`Policy: ${ducking.duckerBus} -> ${ducking.duckedBus} (${ducking.duckRatio})`);
  lines.push(`Active: ${ducking.isDucking ? 'YES' : 'NO'}`);
  lines.push(`Duck Gain: ${ducking.currentDuckGain.toFixed(2)}`);
  lines.push(`Ducker Voices: ${ducking.duckerVoiceCount}`);
  lines.push('');

  // Voices
  lines.push('--- VOICES ---');
  const { voiceHealth } = snapshot;
  lines.push(`Total: ${voiceHealth.totalVoices}`);
  for (const [busId, count] of Object.entries(voiceHealth.voicesByBus)) {
    lines.push(`${busId}: ${count}`);
  }
  const chainWarn = voiceHealth.chainThresholdExceeded ? ' (EXCEEDED!)' : '';
  lines.push(`Asset Chains: ${voiceHealth.activeAssetChains}/${VOICE_CHAIN_WARN_THRESHOLD}${chainWarn}`);
  lines.push('');

  // DSP Metrics (M8.8+)
  if (snapshot.dspMetrics) {
    lines.push('--- DSP METRICS ---');
    const m = snapshot.dspMetrics;
    lines.push(`Active Graphs: ${m.activeGraphs}`);
    lines.push(`Peak Active: ${m.peakActive}`);
    lines.push(`Total Created: ${m.totalCreated}`);
    lines.push(`Total Disposed: ${m.totalDisposed}`);
    if (m.hasAnomalies) {
      lines.push(`Anomalies: YES (check console)`);
    }
    lines.push('');
  }

  // Warnings
  if (snapshot.warnings.length > 0) {
    lines.push('--- WARNINGS ---');
    for (const w of snapshot.warnings) {
      const prefix = w.severity === 'error' ? '[ERROR]' : '[WARN]';
      lines.push(`${prefix} ${w.message}`);
    }
    lines.push('');
  }

  lines.push('=== END ===');

  return lines.join('\n');
}

/**
 * Copy text summary to clipboard.
 */
export async function copyTextSummaryToClipboard(
  snapshot: DiagnosticsSnapshot,
  context: ExportContext = {}
): Promise<{ success: true } | { success: false; error: string }> {
  try {
    const summary = generateTextSummary(snapshot, context);

    if (!navigator.clipboard) {
      return { success: false, error: 'Clipboard API not available' };
    }

    await navigator.clipboard.writeText(summary);
    return { success: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, error: message };
  }
}

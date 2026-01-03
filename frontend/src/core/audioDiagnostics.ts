/**
 * Audio Diagnostics System
 *
 * Real-time monitoring and debugging for the audio engine:
 * - Voice count tracking
 * - Memory usage estimation
 * - Buffer cache stats
 * - Bus level metering
 * - Event history logging
 * - Performance metrics
 */

import type { BusId } from './types';

// ============ TYPES ============

export type DiagnosticEventType =
  | 'play'
  | 'stop'
  | 'fade'
  | 'voice-steal'
  | 'preempt'
  | 'error'
  | 'warning'
  | 'state-change'
  | 'rtpc-change'
  | 'transition';

export interface DiagnosticEvent {
  /** Event ID */
  id: string;
  /** Event type */
  type: DiagnosticEventType;
  /** Timestamp */
  timestamp: number;
  /** Source (asset ID, bus, manager) */
  source: string;
  /** Event details */
  details: string;
  /** Additional data */
  data?: Record<string, unknown>;
}

export interface VoiceStats {
  /** Total active voices */
  total: number;
  /** Voices per bus */
  perBus: Record<BusId, number>;
  /** Peak voice count this session */
  peak: number;
  /** Voices stolen this session */
  stolenCount: number;
  /** Voices preempted this session */
  preemptedCount: number;
}

export interface MemoryStats {
  /** Estimated buffer memory (bytes) */
  bufferMemory: number;
  /** Number of cached buffers */
  cachedBuffers: number;
  /** Audio context state */
  contextState: AudioContextState;
  /** Sample rate */
  sampleRate: number;
}

export interface BusLevelReading {
  bus: BusId;
  level: number;
  peak: number;
  timestamp: number;
}

export interface PerformanceMetrics {
  /** Average update loop time (ms) */
  avgUpdateTime: number;
  /** Max update loop time (ms) */
  maxUpdateTime: number;
  /** Updates per second */
  updatesPerSecond: number;
  /** Dropped frames */
  droppedFrames: number;
}

export interface DiagnosticsSnapshot {
  timestamp: number;
  voices: VoiceStats;
  memory: MemoryStats;
  busLevels: BusLevelReading[];
  performance: PerformanceMetrics;
  recentEvents: DiagnosticEvent[];
  activeManagers: string[];
}

// ============ DIAGNOSTICS MANAGER ============

export class AudioDiagnosticsManager {
  private eventLog: DiagnosticEvent[] = [];
  private maxEventLogSize: number = 1000;
  private voiceStats: VoiceStats;
  private memoryStats: MemoryStats;
  private performanceMetrics: PerformanceMetrics;
  private busLevels: Map<BusId, BusLevelReading> = new Map();
  private updateTimes: number[] = [];
  private lastUpdateTime: number = 0;
  private updateCount: number = 0;
  private sessionStartTime: number;
  private enabled: boolean = true;

  // Callbacks for fetching live data
  private getVoiceCountCallback: () => number;
  private getVoicesPerBusCallback: () => Record<BusId, number>;
  private getCacheStatsCallback: () => { count: number; memoryBytes: number };
  private getContextCallback: () => AudioContext | null;
  private getActiveManagersCallback: () => string[];

  constructor(
    getVoiceCountCallback: () => number,
    getVoicesPerBusCallback: () => Record<BusId, number>,
    getCacheStatsCallback: () => { count: number; memoryBytes: number },
    getContextCallback: () => AudioContext | null,
    getActiveManagersCallback: () => string[]
  ) {
    this.getVoiceCountCallback = getVoiceCountCallback;
    this.getVoicesPerBusCallback = getVoicesPerBusCallback;
    this.getCacheStatsCallback = getCacheStatsCallback;
    this.getContextCallback = getContextCallback;
    this.getActiveManagersCallback = getActiveManagersCallback;

    this.sessionStartTime = performance.now();

    this.voiceStats = {
      total: 0,
      perBus: { master: 0, music: 0, sfx: 0, ambience: 0, voice: 0 },
      peak: 0,
      stolenCount: 0,
      preemptedCount: 0,
    };

    this.memoryStats = {
      bufferMemory: 0,
      cachedBuffers: 0,
      contextState: 'suspended',
      sampleRate: 44100,
    };

    this.performanceMetrics = {
      avgUpdateTime: 0,
      maxUpdateTime: 0,
      updatesPerSecond: 0,
      droppedFrames: 0,
    };
  }

  /**
   * Enable/disable diagnostics
   */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  /**
   * Log a diagnostic event
   */
  logEvent(
    type: DiagnosticEventType,
    source: string,
    details: string,
    data?: Record<string, unknown>
  ): void {
    if (!this.enabled) return;

    const event: DiagnosticEvent = {
      id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type,
      timestamp: performance.now(),
      source,
      details,
      data,
    };

    this.eventLog.push(event);

    // Trim log if too large
    if (this.eventLog.length > this.maxEventLogSize) {
      this.eventLog = this.eventLog.slice(-this.maxEventLogSize / 2);
    }

    // Update stats based on event type
    if (type === 'voice-steal') {
      this.voiceStats.stolenCount++;
    } else if (type === 'preempt') {
      this.voiceStats.preemptedCount++;
    }
  }

  /**
   * Log play event
   */
  logPlay(assetId: string, bus: BusId, volume: number): void {
    this.logEvent('play', assetId, `Playing on ${bus} at volume ${volume.toFixed(2)}`, {
      bus,
      volume,
    });
  }

  /**
   * Log stop event
   */
  logStop(assetId: string, fadeMs?: number): void {
    this.logEvent('stop', assetId, fadeMs ? `Stopping with ${fadeMs}ms fade` : 'Stopping immediately', {
      fadeMs,
    });
  }

  /**
   * Log error
   */
  logError(source: string, message: string, error?: Error): void {
    this.logEvent('error', source, message, {
      errorMessage: error?.message,
      stack: error?.stack,
    });
  }

  /**
   * Log warning
   */
  logWarning(source: string, message: string): void {
    this.logEvent('warning', source, message);
  }

  /**
   * Log state change
   */
  logStateChange(manager: string, from: string, to: string): void {
    this.logEvent('state-change', manager, `${from} → ${to}`, { from, to });
  }

  /**
   * Log RTPC change
   */
  logRTPCChange(name: string, oldValue: number, newValue: number): void {
    this.logEvent('rtpc-change', name, `${oldValue.toFixed(3)} → ${newValue.toFixed(3)}`, {
      oldValue,
      newValue,
    });
  }

  /**
   * Update voice stats
   */
  updateVoiceStats(): void {
    if (!this.enabled) return;

    const total = this.getVoiceCountCallback();
    const perBus = this.getVoicesPerBusCallback();

    this.voiceStats.total = total;
    this.voiceStats.perBus = perBus;

    if (total > this.voiceStats.peak) {
      this.voiceStats.peak = total;
    }
  }

  /**
   * Update memory stats
   */
  updateMemoryStats(): void {
    if (!this.enabled) return;

    const cacheStats = this.getCacheStatsCallback();
    const ctx = this.getContextCallback();

    this.memoryStats.cachedBuffers = cacheStats.count;
    this.memoryStats.bufferMemory = cacheStats.memoryBytes;
    this.memoryStats.contextState = ctx?.state ?? 'closed';
    this.memoryStats.sampleRate = ctx?.sampleRate ?? 44100;
  }

  /**
   * Record update loop timing
   */
  recordUpdateTime(timeMs: number): void {
    if (!this.enabled) return;

    this.updateTimes.push(timeMs);
    this.updateCount++;

    // Keep last 100 samples
    if (this.updateTimes.length > 100) {
      this.updateTimes.shift();
    }

    // Calculate metrics
    const sum = this.updateTimes.reduce((a, b) => a + b, 0);
    this.performanceMetrics.avgUpdateTime = sum / this.updateTimes.length;
    this.performanceMetrics.maxUpdateTime = Math.max(...this.updateTimes);

    // Calculate updates per second
    const now = performance.now();
    if (now - this.lastUpdateTime >= 1000) {
      this.performanceMetrics.updatesPerSecond = this.updateCount;
      this.updateCount = 0;
      this.lastUpdateTime = now;
    }

    // Detect dropped frames (>33ms = less than 30fps)
    if (timeMs > 33) {
      this.performanceMetrics.droppedFrames++;
    }
  }

  /**
   * Update bus level reading
   */
  updateBusLevel(bus: BusId, level: number): void {
    if (!this.enabled) return;

    const existing = this.busLevels.get(bus);
    const peak = existing ? Math.max(existing.peak, level) : level;

    this.busLevels.set(bus, {
      bus,
      level,
      peak,
      timestamp: performance.now(),
    });
  }

  /**
   * Get full diagnostics snapshot
   */
  getSnapshot(): DiagnosticsSnapshot {
    this.updateVoiceStats();
    this.updateMemoryStats();

    return {
      timestamp: performance.now(),
      voices: { ...this.voiceStats },
      memory: { ...this.memoryStats },
      busLevels: Array.from(this.busLevels.values()),
      performance: { ...this.performanceMetrics },
      recentEvents: this.eventLog.slice(-50),
      activeManagers: this.getActiveManagersCallback(),
    };
  }

  /**
   * Get events by type
   */
  getEventsByType(type: DiagnosticEventType, limit: number = 100): DiagnosticEvent[] {
    return this.eventLog
      .filter(e => e.type === type)
      .slice(-limit);
  }

  /**
   * Get events by source
   */
  getEventsBySource(source: string, limit: number = 100): DiagnosticEvent[] {
    return this.eventLog
      .filter(e => e.source.includes(source))
      .slice(-limit);
  }

  /**
   * Get error count
   */
  getErrorCount(): number {
    return this.eventLog.filter(e => e.type === 'error').length;
  }

  /**
   * Get warning count
   */
  getWarningCount(): number {
    return this.eventLog.filter(e => e.type === 'warning').length;
  }

  /**
   * Get session duration
   */
  getSessionDuration(): number {
    return performance.now() - this.sessionStartTime;
  }

  /**
   * Clear event log
   */
  clearEventLog(): void {
    this.eventLog = [];
  }

  /**
   * Reset peak stats
   */
  resetPeaks(): void {
    this.voiceStats.peak = this.voiceStats.total;
    this.busLevels.forEach((reading, bus) => {
      this.busLevels.set(bus, { ...reading, peak: reading.level });
    });
  }

  /**
   * Export diagnostics as JSON
   */
  exportJSON(): string {
    return JSON.stringify({
      snapshot: this.getSnapshot(),
      sessionDuration: this.getSessionDuration(),
      totalEvents: this.eventLog.length,
      errorCount: this.getErrorCount(),
      warningCount: this.getWarningCount(),
    }, null, 2);
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.eventLog = [];
    this.busLevels.clear();
    this.updateTimes = [];
  }
}

// ============ CONSOLE LOGGER ============

export class AudioConsoleLogger {
  private enabled: boolean = false;
  private logLevel: 'verbose' | 'normal' | 'errors' = 'normal';
  private prefix: string = '[ReelForge Audio]';

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  setLogLevel(level: 'verbose' | 'normal' | 'errors'): void {
    this.logLevel = level;
  }

  verbose(message: string, ...args: unknown[]): void {
    if (this.enabled && this.logLevel === 'verbose') {
      console.log(`${this.prefix} ${message}`, ...args);
    }
  }

  info(message: string, ...args: unknown[]): void {
    if (this.enabled && this.logLevel !== 'errors') {
      console.info(`${this.prefix} ${message}`, ...args);
    }
  }

  warn(message: string, ...args: unknown[]): void {
    if (this.enabled) {
      console.warn(`${this.prefix} ⚠️ ${message}`, ...args);
    }
  }

  error(message: string, ...args: unknown[]): void {
    if (this.enabled) {
      console.error(`${this.prefix} ❌ ${message}`, ...args);
    }
  }

  group(label: string): void {
    if (this.enabled && this.logLevel === 'verbose') {
      console.group(`${this.prefix} ${label}`);
    }
  }

  groupEnd(): void {
    if (this.enabled && this.logLevel === 'verbose') {
      console.groupEnd();
    }
  }

  table(data: unknown): void {
    if (this.enabled && this.logLevel === 'verbose') {
      console.table(data);
    }
  }
}

// ============ GLOBAL LOGGER INSTANCE ============

export const audioLogger = new AudioConsoleLogger();

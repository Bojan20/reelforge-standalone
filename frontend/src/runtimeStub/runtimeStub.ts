/**
 * Runtime Stub - Simulates RuntimeCore for testing
 *
 * Maps game events to AdapterCommands and executes them via AudioBackend.
 * Measures recv→execute latency.
 * Includes optional seq dedupe to prevent duplicate event processing.
 */

import type { AdapterCommand, AudioBackend } from "./audioBackend/types";
import { getCommandsForEvent, getRequiredAssets, type GameEvent } from "./eventMap";
import { latencyMetrics, type LatencyMeasurement, type LatencyStats } from "./latencyMetrics";

/** Runtime stub configuration */
export interface RuntimeStubConfig {
  /** Enable latency logging */
  logLatency?: boolean;
  /** Enable command logging */
  logCommands?: boolean;
  /** Enable seq dedupe (ring buffer size, 0 = disabled) */
  seqDedupeSize?: number;
}

/**
 * Ring buffer for seq dedupe
 */
class SeqDedupeBuffer {
  private buffer: number[] = [];
  private size: number;
  private index: number = 0;

  constructor(size: number) {
    this.size = size;
    this.buffer = new Array(size).fill(-1);
  }

  /**
   * Check if seq was recently seen and add it
   * @returns true if duplicate, false if new
   */
  checkAndAdd(seq: number): boolean {
    // Check if exists in buffer
    if (this.buffer.includes(seq)) {
      return true; // Duplicate
    }

    // Add to buffer (overwrite oldest)
    this.buffer[this.index] = seq;
    this.index = (this.index + 1) % this.size;
    return false; // Not duplicate
  }

  clear(): void {
    this.buffer.fill(-1);
    this.index = 0;
  }
}

/**
 * Runtime Stub - Test implementation of RuntimeCore
 */
export class RuntimeStub {
  private backend: AudioBackend;
  private config: RuntimeStubConfig;
  private isPreloaded: boolean = false;
  private seqDedupe: SeqDedupeBuffer | null = null;

  constructor(backend: AudioBackend, config: RuntimeStubConfig = {}) {
    this.backend = backend;
    this.config = {
      logLatency: config.logLatency ?? false,
      logCommands: config.logCommands ?? false,
      seqDedupeSize: config.seqDedupeSize ?? 0,
    };

    // Initialize seq dedupe if enabled
    if (this.config.seqDedupeSize && this.config.seqDedupeSize > 0) {
      this.seqDedupe = new SeqDedupeBuffer(this.config.seqDedupeSize);
    }
  }

  /**
   * Preload all required assets
   */
  async preload(additionalAssets?: string[]): Promise<void> {
    const assets = [...getRequiredAssets(), ...(additionalAssets || [])];
    const uniqueAssets = [...new Set(assets)];

    if (this.config.logCommands) {
      console.log(`[RuntimeStub] Preloading assets:`, uniqueAssets);
    }

    await this.backend.preload(uniqueAssets);
    this.isPreloaded = true;

    if (this.config.logCommands) {
      console.log(`[RuntimeStub] Preload complete`);
    }
  }

  /**
   * Trigger a game event
   * @param event - Game event name
   * @param recvTime - Optional receive time (defaults to now)
   * @param seq - Optional sequence number for dedupe
   * @returns Latency measurement or null if deduped
   */
  triggerEvent(event: GameEvent, recvTime?: number, seq?: number): LatencyMeasurement | null {
    // Seq dedupe check
    if (seq !== undefined && this.seqDedupe) {
      if (this.seqDedupe.checkAndAdd(seq)) {
        if (this.config.logCommands) {
          console.log(`[RuntimeStub] Deduped event: ${event} (seq=${seq})`);
        }
        return null;
      }
    }

    const startTime = recvTime ?? latencyMetrics.startTiming();

    if (!this.isPreloaded) {
      console.warn(`[RuntimeStub] Assets not preloaded, call preload() first`);
    }

    const commands = getCommandsForEvent(event);

    if (this.config.logCommands) {
      console.log(`[RuntimeStub] Event: ${event} → Commands:`, commands);
    }

    // Execute commands
    this.backend.execute(commands);

    const executeTime = performance.now();
    const measurement = latencyMetrics.record(event, startTime, executeTime);

    if (this.config.logLatency) {
      console.log(
        `[RuntimeStub] ${event}: latency=${measurement.latencyMs.toFixed(2)}ms`
      );
    }

    return measurement;
  }

  /**
   * Trigger event by name string (for WS integration)
   */
  triggerEventByName(eventName: string, recvTime?: number, seq?: number): LatencyMeasurement | null {
    return this.triggerEvent(eventName as GameEvent, recvTime, seq);
  }

  /**
   * Execute raw commands (bypass event mapping)
   */
  executeCommands(commands: AdapterCommand[], recvTime?: number): LatencyMeasurement {
    const startTime = recvTime ?? latencyMetrics.startTiming();

    if (this.config.logCommands) {
      console.log(`[RuntimeStub] Raw commands:`, commands);
    }

    this.backend.execute(commands);

    const executeTime = performance.now();
    const measurement = latencyMetrics.record("raw", startTime, executeTime);

    if (this.config.logLatency) {
      console.log(
        `[RuntimeStub] raw: latency=${measurement.latencyMs.toFixed(2)}ms`
      );
    }

    return measurement;
  }

  /**
   * Get latency metrics instance
   */
  getMetrics() {
    return latencyMetrics;
  }

  /**
   * Get overall latency stats
   */
  getOverallStats(): LatencyStats {
    return latencyMetrics.getStats();
  }

  /**
   * Get stats for a specific event
   */
  getEventStats(event: string): LatencyStats {
    return latencyMetrics.getStatsForEvent(event);
  }

  /**
   * Log current latency stats
   */
  logStats(): void {
    latencyMetrics.logStats();
  }

  /**
   * Clear latency metrics and seq dedupe
   */
  clearStats(): void {
    latencyMetrics.clear();
    this.seqDedupe?.clear();
  }

  /**
   * Check if preloaded
   */
  isReady(): boolean {
    return this.isPreloaded;
  }
}

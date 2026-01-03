/**
 * Latency Metrics - Measures recv→execute latency
 *
 * Tracks timing from when an event is received to when it's executed.
 */

/** Single latency measurement */
export interface LatencyMeasurement {
  event: string;
  recvTime: number;
  executeTime: number;
  latencyMs: number;
}

/** Latency statistics */
export interface LatencyStats {
  count: number;
  minMs: number;
  maxMs: number;
  avgMs: number;
  lastMs: number;
  measurements: LatencyMeasurement[];
}

/**
 * Latency metrics tracker
 */
export class LatencyMetrics {
  private measurements: LatencyMeasurement[] = [];
  private maxMeasurements: number;

  constructor(maxMeasurements: number = 100) {
    this.maxMeasurements = maxMeasurements;
  }

  /**
   * Record a latency measurement
   * @param event - Event name
   * @param recvTime - Time when event was received (performance.now())
   * @param executeTime - Time when execution completed (performance.now())
   */
  record(event: string, recvTime: number, executeTime: number): LatencyMeasurement {
    const latencyMs = executeTime - recvTime;

    const measurement: LatencyMeasurement = {
      event,
      recvTime,
      executeTime,
      latencyMs,
    };

    this.measurements.push(measurement);

    // Keep only last N measurements
    if (this.measurements.length > this.maxMeasurements) {
      this.measurements.shift();
    }

    return measurement;
  }

  /**
   * Start timing for an event
   * @returns recvTime to pass to record()
   */
  startTiming(): number {
    return performance.now();
  }

  /**
   * Get latency statistics
   */
  getStats(): LatencyStats {
    if (this.measurements.length === 0) {
      return {
        count: 0,
        minMs: 0,
        maxMs: 0,
        avgMs: 0,
        lastMs: 0,
        measurements: [],
      };
    }

    const latencies = this.measurements.map((m) => m.latencyMs);
    const sum = latencies.reduce((a, b) => a + b, 0);

    return {
      count: this.measurements.length,
      minMs: Math.min(...latencies),
      maxMs: Math.max(...latencies),
      avgMs: sum / this.measurements.length,
      lastMs: latencies[latencies.length - 1],
      measurements: [...this.measurements],
    };
  }

  /**
   * Get stats for a specific event
   */
  getStatsForEvent(event: string): LatencyStats {
    const filtered = this.measurements.filter((m) => m.event === event);

    if (filtered.length === 0) {
      return {
        count: 0,
        minMs: 0,
        maxMs: 0,
        avgMs: 0,
        lastMs: 0,
        measurements: [],
      };
    }

    const latencies = filtered.map((m) => m.latencyMs);
    const sum = latencies.reduce((a, b) => a + b, 0);

    return {
      count: filtered.length,
      minMs: Math.min(...latencies),
      maxMs: Math.max(...latencies),
      avgMs: sum / filtered.length,
      lastMs: latencies[latencies.length - 1],
      measurements: filtered,
    };
  }

  /**
   * Clear all measurements
   */
  clear(): void {
    this.measurements = [];
  }

  /**
   * Log current stats to console
   */
  logStats(): void {
    const stats = this.getStats();
    console.log(
      `[LatencyMetrics] count=${stats.count} min=${stats.minMs.toFixed(2)}ms max=${stats.maxMs.toFixed(2)}ms avg=${stats.avgMs.toFixed(2)}ms last=${stats.lastMs.toFixed(2)}ms`
    );
  }
}

/** Singleton instance */
export const latencyMetrics = new LatencyMetrics();

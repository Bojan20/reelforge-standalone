/**
 * ReelForge M8.8 DSP Metrics
 *
 * Centralized resource tracking for DSP node lifecycle.
 * Tracks graph creation/disposal counts for leak detection.
 *
 * Usage:
 * - Call dspMetrics.graphCreated() when creating a node graph
 * - Call dspMetrics.graphDisposed() when disposing a node graph
 * - Check dspMetrics.getSnapshot() for current state
 * - In tests: dspMetrics.reset() to clear counters
 */

/** Debug logging flag - set via RF_DEBUG env or window.RF_DEBUG */
export const RF_DEBUG = (() => {
  // Check for build-time env variable
  if (typeof import.meta !== 'undefined' && (import.meta as any).env?.VITE_RF_DEBUG === 'true') {
    return true;
  }
  // Check for runtime window flag
  if (typeof window !== 'undefined' && (window as any).RF_DEBUG === true) {
    return true;
  }
  return false;
})();

/** Conditional debug logger */
export function rfDebug(category: string, ...args: unknown[]): void {
  if (RF_DEBUG) {
    console.log(`[RF:${category}]`, ...args);
  }
}

/** DSP graph types for categorized tracking */
export type DSPGraphType =
  | 'voiceChain'
  | 'voiceInsert'
  | 'busChain'
  | 'busInsert'
  | 'masterChain'
  | 'masterInsert';

/** Snapshot of DSP metrics at a point in time */
export interface DSPMetricsSnapshot {
  /** Timestamp of snapshot */
  timestamp: number;
  /** Total graphs created since reset */
  totalCreated: number;
  /** Total graphs disposed since reset */
  totalDisposed: number;
  /** Currently active graphs (created - disposed) */
  activeGraphs: number;
  /** Per-type breakdown */
  byType: Record<DSPGraphType, {
    created: number;
    disposed: number;
    active: number;
  }>;
  /** Warning: true if active < 0 or disposed > created (leak or double-dispose) */
  hasAnomalies: boolean;
  /** Peak active graphs seen */
  peakActive: number;
}

/**
 * DSP Metrics Tracker
 *
 * Thread-safe singleton for tracking DSP graph lifecycle.
 * Reports anomalies (leaks, double-dispose) via console.warn.
 */
class DSPMetricsTracker {
  private created: Record<DSPGraphType, number> = {
    voiceChain: 0,
    voiceInsert: 0,
    busChain: 0,
    busInsert: 0,
    masterChain: 0,
    masterInsert: 0,
  };

  private disposed: Record<DSPGraphType, number> = {
    voiceChain: 0,
    voiceInsert: 0,
    busChain: 0,
    busInsert: 0,
    masterChain: 0,
    masterInsert: 0,
  };

  private peakActive = 0;

  /**
   * Record a graph creation.
   */
  graphCreated(type: DSPGraphType): void {
    this.created[type]++;
    const active = this.getActiveCount();
    if (active > this.peakActive) {
      this.peakActive = active;
    }
    rfDebug('DSPMetrics', `created ${type}, active: ${active}`);
  }

  /**
   * Record a graph disposal.
   */
  graphDisposed(type: DSPGraphType): void {
    this.disposed[type]++;
    const activeForType = this.created[type] - this.disposed[type];
    if (activeForType < 0) {
      console.warn(
        `[DSPMetrics] ANOMALY: Double-dispose detected for ${type}! ` +
        `created=${this.created[type]}, disposed=${this.disposed[type]}`
      );
    }
    rfDebug('DSPMetrics', `disposed ${type}, active: ${this.getActiveCount()}`);
  }

  /**
   * Get total active graph count.
   */
  getActiveCount(): number {
    let active = 0;
    for (const type of Object.keys(this.created) as DSPGraphType[]) {
      active += this.created[type] - this.disposed[type];
    }
    return active;
  }

  /**
   * Get active count for a specific type.
   */
  getActiveCountByType(type: DSPGraphType): number {
    return this.created[type] - this.disposed[type];
  }

  /**
   * Get full metrics snapshot.
   */
  getSnapshot(): DSPMetricsSnapshot {
    const byType = {} as DSPMetricsSnapshot['byType'];
    let totalCreated = 0;
    let totalDisposed = 0;
    let hasAnomalies = false;

    for (const type of Object.keys(this.created) as DSPGraphType[]) {
      const created = this.created[type];
      const disposed = this.disposed[type];
      const active = created - disposed;

      byType[type] = { created, disposed, active };
      totalCreated += created;
      totalDisposed += disposed;

      if (active < 0 || disposed > created) {
        hasAnomalies = true;
      }
    }

    const activeGraphs = totalCreated - totalDisposed;
    if (activeGraphs < 0) {
      hasAnomalies = true;
    }

    return {
      timestamp: Date.now(),
      totalCreated,
      totalDisposed,
      activeGraphs,
      byType,
      hasAnomalies,
      peakActive: this.peakActive,
    };
  }

  /**
   * Reset all counters (for testing).
   */
  reset(): void {
    for (const type of Object.keys(this.created) as DSPGraphType[]) {
      this.created[type] = 0;
      this.disposed[type] = 0;
    }
    this.peakActive = 0;
    rfDebug('DSPMetrics', 'reset');
  }

  /**
   * Assert that all graphs have been disposed.
   * Throws if any active graphs remain.
   * Used in tests to verify cleanup.
   */
  assertAllDisposed(): void {
    const snapshot = this.getSnapshot();
    if (snapshot.activeGraphs !== 0) {
      const details = Object.entries(snapshot.byType)
        .filter(([, v]) => v.active !== 0)
        .map(([k, v]) => `${k}: ${v.active}`)
        .join(', ');
      throw new Error(
        `DSP leak detected! ${snapshot.activeGraphs} active graphs: ${details}`
      );
    }
    if (snapshot.hasAnomalies) {
      throw new Error('DSP anomalies detected! Check console for details.');
    }
  }

  /**
   * Log current state summary.
   */
  logSummary(): void {
    const snapshot = this.getSnapshot();
    console.log('[DSPMetrics] Summary:', {
      activeGraphs: snapshot.activeGraphs,
      peakActive: snapshot.peakActive,
      totalCreated: snapshot.totalCreated,
      totalDisposed: snapshot.totalDisposed,
      hasAnomalies: snapshot.hasAnomalies,
    });
  }
}

/**
 * Singleton instance for DSP metrics tracking.
 */
export const dspMetrics = new DSPMetricsTracker();

/**
 * Expose to window for debugging in console.
 * Usage in browser console: window.rfDspMetrics.getSnapshot()
 */
if (typeof window !== 'undefined') {
  (window as any).rfDspMetrics = dspMetrics;
  (window as any).RF_DEBUG_ENABLE = () => {
    (window as any).RF_DEBUG = true;
    console.log('[RF] Debug logging enabled. Refresh DSP operations to see logs.');
  };
  (window as any).RF_DEBUG_DISABLE = () => {
    (window as any).RF_DEBUG = false;
    console.log('[RF] Debug logging disabled.');
  };
}

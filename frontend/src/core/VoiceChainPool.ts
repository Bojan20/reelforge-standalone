/**
 * Voice Chain Pool
 *
 * Object pooling for voice chain infrastructure nodes.
 * Reduces GC pressure by recycling GainNodes used for voice chains
 * instead of creating/disposing them on every voice start/stop.
 *
 * Pools:
 * - GainNode pairs (chainInput/chainOutput)
 * - Dry/wet bypass GainNodes
 *
 * Note: Plugin DSP instances are pooled separately via PluginInstancePool.
 * This pool handles only the "infrastructure" nodes that connect them.
 *
 * @module core/VoiceChainPool
 */

import { AudioContextManager } from './AudioContextManager';

// ============ Types ============

interface PooledGainNode {
  node: GainNode;
  createdAt: number;
  lastUsed: number;
}

interface PoolConfig {
  /** Maximum GainNodes in pool (default: 64) */
  maxNodes: number;
  /** Time in ms before unused node is removed (default: 120000 = 2 min) */
  ttlMs: number;
  /** How often to run cleanup in ms (default: 60000 = 1 min) */
  cleanupIntervalMs: number;
}

// ============ Default Configuration ============

const DEFAULT_POOL_CONFIG: PoolConfig = {
  maxNodes: 64,
  ttlMs: 120_000, // 2 minutes
  cleanupIntervalMs: 60_000, // 1 minute
};

// ============ Pool Implementation ============

/**
 * Voice chain infrastructure node pool.
 */
class VoiceChainPoolClass {
  private gainPool: PooledGainNode[] = [];
  private config: PoolConfig;
  private cleanupTimer: ReturnType<typeof setInterval> | null = null;
  private audioContext: AudioContext | null = null;

  // Stats for monitoring
  private stats = {
    hits: 0,
    misses: 0,
    releases: 0,
    currentPooled: 0,
  };

  constructor(config: Partial<PoolConfig> = {}) {
    this.config = { ...DEFAULT_POOL_CONFIG, ...config };
    this.startCleanupTimer();
  }

  /**
   * Set the AudioContext to use for creating new nodes.
   */
  setAudioContext(ctx: AudioContext): void {
    // If context changed, dispose all pooled nodes
    if (this.audioContext && this.audioContext !== ctx) {
      this.disposeAll();
    }
    this.audioContext = ctx;
  }

  /**
   * Acquire a GainNode from the pool.
   * Returns a pooled node if available, otherwise creates new.
   */
  acquireGain(): GainNode | null {
    const context = this.audioContext ?? AudioContextManager.tryGetContext();
    if (!context) {
      return null;
    }

    // Try to get from pool
    if (this.gainPool.length > 0) {
      const pooled = this.gainPool.pop()!;
      pooled.lastUsed = Date.now();
      this.stats.hits++;
      this.stats.currentPooled = this.gainPool.length;

      // Reset node state
      this.resetGainNode(pooled.node);

      return pooled.node;
    }

    // Create new node
    this.stats.misses++;
    try {
      return context.createGain();
    } catch {
      return null;
    }
  }

  /**
   * Acquire a pair of GainNodes (for chainInput/chainOutput).
   */
  acquireGainPair(): [GainNode, GainNode] | null {
    const input = this.acquireGain();
    const output = this.acquireGain();

    if (!input || !output) {
      // Return any acquired nodes back to pool
      if (input) this.releaseGain(input);
      if (output) this.releaseGain(output);
      return null;
    }

    return [input, output];
  }

  /**
   * Acquire multiple GainNodes at once.
   */
  acquireGains(count: number): GainNode[] | null {
    const nodes: GainNode[] = [];

    for (let i = 0; i < count; i++) {
      const node = this.acquireGain();
      if (!node) {
        // Return any acquired nodes back to pool
        for (const n of nodes) {
          this.releaseGain(n);
        }
        return null;
      }
      nodes.push(node);
    }

    return nodes;
  }

  /**
   * Release a GainNode back to the pool.
   */
  releaseGain(node: GainNode): void {
    // Disconnect from audio graph
    try {
      node.disconnect();
    } catch {
      // May already be disconnected
    }

    // Check pool size limit
    if (this.gainPool.length >= this.config.maxNodes) {
      // Pool is full, let GC collect this node
      return;
    }

    // Add to pool
    this.gainPool.push({
      node,
      createdAt: Date.now(),
      lastUsed: Date.now(),
    });

    this.stats.releases++;
    this.stats.currentPooled = this.gainPool.length;
  }

  /**
   * Release multiple GainNodes back to the pool.
   */
  releaseGains(nodes: GainNode[]): void {
    for (const node of nodes) {
      this.releaseGain(node);
    }
  }

  /**
   * Dispose all pooled nodes.
   */
  disposeAll(): void {
    for (const pooled of this.gainPool) {
      try {
        pooled.node.disconnect();
      } catch {
        // Ignore
      }
    }
    this.gainPool = [];
    this.stats.currentPooled = 0;
  }

  /**
   * Get pool statistics.
   */
  getStats(): typeof this.stats & { hitRate: number } {
    const total = this.stats.hits + this.stats.misses;
    return {
      ...this.stats,
      hitRate: total > 0 ? this.stats.hits / total : 0,
    };
  }

  /**
   * Get current pool size.
   */
  getPoolSize(): number {
    return this.gainPool.length;
  }

  /**
   * Warm up the pool by pre-creating nodes.
   * Useful at app startup to avoid first-use latency.
   */
  warmup(count: number): void {
    const ctx = this.audioContext ?? AudioContextManager.tryGetContext();
    if (!ctx) {
      return;
    }

    const toCreate = Math.min(count, this.config.maxNodes - this.gainPool.length);

    for (let i = 0; i < toCreate; i++) {
      try {
        const node = ctx.createGain();
        this.gainPool.push({
          node,
          createdAt: Date.now(),
          lastUsed: Date.now(),
        });
      } catch {
        break;
      }
    }

    this.stats.currentPooled = this.gainPool.length;
  }

  /**
   * Configure pool settings.
   */
  configure(config: Partial<PoolConfig>): void {
    this.config = { ...this.config, ...config };

    // Restart cleanup timer with new interval
    if (config.cleanupIntervalMs) {
      this.stopCleanupTimer();
      this.startCleanupTimer();
    }
  }

  // ============ Private Methods ============

  private resetGainNode(node: GainNode): void {
    // Reset gain to unity
    node.gain.value = 1;

    // Cancel any scheduled automation
    try {
      node.gain.cancelScheduledValues(0);
    } catch {
      // Ignore
    }
  }

  private startCleanupTimer(): void {
    if (this.cleanupTimer) return;

    this.cleanupTimer = setInterval(() => {
      this.cleanup();
    }, this.config.cleanupIntervalMs);
  }

  private stopCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }
  }

  private cleanup(): void {
    const now = Date.now();
    const ttl = this.config.ttlMs;

    // Remove expired nodes
    this.gainPool = this.gainPool.filter((pooled) => {
      const age = now - pooled.lastUsed;
      if (age > ttl) {
        try {
          pooled.node.disconnect();
        } catch {
          // Ignore
        }
        return false;
      }
      return true;
    });

    this.stats.currentPooled = this.gainPool.length;
  }

  /**
   * Cleanup on module unload.
   */
  destroy(): void {
    this.stopCleanupTimer();
    this.disposeAll();
  }
}

// ============ Singleton Export ============

/**
 * Global voice chain node pool.
 */
export const voiceChainPool = new VoiceChainPoolClass();

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    voiceChainPool.destroy();
  });
}

export default voiceChainPool;

/**
 * Plugin Instance Pool
 *
 * Object pooling for DSP instances to reduce allocation overhead.
 * Instead of creating/disposing audio nodes on every insert add/remove,
 * the pool recycles disconnected instances.
 *
 * Benefits:
 * - Reduces GC pressure from frequent node creation
 * - Faster insert operations (no node creation latency)
 * - Better memory stability during live editing
 *
 * Usage:
 * ```typescript
 * // Acquire instance (creates new or recycles pooled)
 * const dsp = pluginPool.acquire('vaneq', audioContext);
 *
 * // Release instance back to pool (instead of dispose)
 * pluginPool.release('vaneq', dsp);
 * ```
 *
 * @module plugin/PluginInstancePool
 */

import type { PluginDSPInstance } from './PluginDefinition';
import { getPluginDefinition } from './pluginRegistry';

// ============ Types ============

interface PooledInstance {
  instance: PluginDSPInstance;
  createdAt: number;
  lastUsed: number;
  useCount: number;
}

interface PoolConfig {
  /** Maximum instances per plugin type (default: 8) */
  maxPerPlugin: number;
  /** Time in ms before unused instance is disposed (default: 60000 = 1 min) */
  ttlMs: number;
  /** How often to run cleanup in ms (default: 30000 = 30s) */
  cleanupIntervalMs: number;
}

// ============ Default Configuration ============

const DEFAULT_POOL_CONFIG: PoolConfig = {
  maxPerPlugin: 8,
  ttlMs: 60_000, // 1 minute
  cleanupIntervalMs: 30_000, // 30 seconds
};

// ============ Pool Implementation ============

/**
 * Plugin instance pool for recycling DSP instances.
 */
class PluginInstancePoolClass {
  private pools = new Map<string, PooledInstance[]>();
  private config: PoolConfig;
  private cleanupTimer: ReturnType<typeof setInterval> | null = null;
  private audioContext: AudioContext | null = null;

  // Stats for monitoring
  private stats = {
    hits: 0,
    misses: 0,
    releases: 0,
    evictions: 0,
    currentPooled: 0,
  };

  constructor(config: Partial<PoolConfig> = {}) {
    this.config = { ...DEFAULT_POOL_CONFIG, ...config };
    this.startCleanupTimer();
  }

  /**
   * Set the AudioContext to use for creating new instances.
   */
  setAudioContext(ctx: AudioContext): void {
    // If context changed, dispose all pooled instances
    if (this.audioContext && this.audioContext !== ctx) {
      this.disposeAll();
    }
    this.audioContext = ctx;
  }

  /**
   * Acquire a DSP instance for a plugin.
   * Returns a pooled instance if available, otherwise creates new.
   *
   * @param pluginId - The plugin type ID
   * @param ctx - AudioContext (optional if already set)
   * @returns A DSP instance ready for use
   */
  acquire(pluginId: string, ctx?: AudioContext): PluginDSPInstance | null {
    const context = ctx ?? this.audioContext;
    if (!context) {
      console.error('[PluginPool] No AudioContext available');
      return null;
    }

    // Try to get from pool
    const pool = this.pools.get(pluginId);
    if (pool && pool.length > 0) {
      const pooled = pool.pop()!;
      pooled.lastUsed = Date.now();
      pooled.useCount++;
      this.stats.hits++;
      this.stats.currentPooled = this.getTotalPooled();

      // Reset instance state before returning
      this.resetInstance(pooled.instance);

      return pooled.instance;
    }

    // Create new instance
    this.stats.misses++;
    return this.createInstance(pluginId, context);
  }

  /**
   * Release a DSP instance back to the pool.
   * The instance will be recycled for future use.
   *
   * @param pluginId - The plugin type ID
   * @param instance - The DSP instance to release
   */
  release(pluginId: string, instance: PluginDSPInstance): void {
    // Disconnect from audio graph
    try {
      instance.disconnect();
    } catch {
      // May already be disconnected
    }

    const pool = this.pools.get(pluginId) ?? [];

    // Check pool size limit
    if (pool.length >= this.config.maxPerPlugin) {
      // Pool is full, dispose oldest
      const oldest = pool.shift();
      if (oldest) {
        this.disposeInstance(oldest.instance);
        this.stats.evictions++;
      }
    }

    // Add to pool
    pool.push({
      instance,
      createdAt: Date.now(),
      lastUsed: Date.now(),
      useCount: 1,
    });

    this.pools.set(pluginId, pool);
    this.stats.releases++;
    this.stats.currentPooled = this.getTotalPooled();
  }

  /**
   * Dispose a specific instance (won't be pooled).
   * Use when instance is corrupted or context is closing.
   */
  dispose(instance: PluginDSPInstance): void {
    this.disposeInstance(instance);
  }

  /**
   * Dispose all pooled instances.
   * Call when AudioContext changes or app unmounts.
   */
  disposeAll(): void {
    for (const pool of this.pools.values()) {
      for (const pooled of pool) {
        this.disposeInstance(pooled.instance);
      }
    }
    this.pools.clear();
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
   * Get pool size for a specific plugin.
   */
  getPoolSize(pluginId: string): number {
    return this.pools.get(pluginId)?.length ?? 0;
  }

  /**
   * Get total pooled instances across all plugins.
   */
  getTotalPooled(): number {
    let total = 0;
    for (const pool of this.pools.values()) {
      total += pool.length;
    }
    return total;
  }

  /**
   * Warm up the pool by pre-creating instances.
   * Useful at app startup to avoid first-use latency.
   *
   * @param pluginId - The plugin type ID
   * @param count - Number of instances to pre-create
   */
  warmup(pluginId: string, count: number): void {
    const ctx = this.audioContext;
    if (!ctx) {
      console.warn('[PluginPool] Cannot warmup without AudioContext');
      return;
    }

    const pool = this.pools.get(pluginId) ?? [];
    const toCreate = Math.min(count, this.config.maxPerPlugin - pool.length);

    for (let i = 0; i < toCreate; i++) {
      const instance = this.createInstance(pluginId, ctx);
      if (instance) {
        pool.push({
          instance,
          createdAt: Date.now(),
          lastUsed: Date.now(),
          useCount: 0,
        });
      }
    }

    this.pools.set(pluginId, pool);
    this.stats.currentPooled = this.getTotalPooled();
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

  private createInstance(pluginId: string, ctx: AudioContext): PluginDSPInstance | null {
    const def = getPluginDefinition(pluginId);
    if (!def) {
      console.error(`[PluginPool] Unknown plugin: ${pluginId}`);
      return null;
    }

    try {
      return def.createDSP(ctx);
    } catch (error) {
      console.error(`[PluginPool] Failed to create ${pluginId}:`, error);
      return null;
    }
  }

  private disposeInstance(instance: PluginDSPInstance): void {
    try {
      instance.disconnect();
      instance.dispose();
    } catch {
      // Instance may be in invalid state
    }
  }

  private resetInstance(instance: PluginDSPInstance): void {
    // Reset bypass state
    if (instance.setBypass) {
      instance.setBypass(false);
    }

    // Reset to default params would be nice but we don't have them here
    // The caller should apply params after acquiring
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

    for (const [pluginId, pool] of this.pools.entries()) {
      // Remove expired instances
      const remaining = pool.filter((pooled) => {
        const age = now - pooled.lastUsed;
        if (age > ttl) {
          this.disposeInstance(pooled.instance);
          this.stats.evictions++;
          return false;
        }
        return true;
      });

      if (remaining.length > 0) {
        this.pools.set(pluginId, remaining);
      } else {
        this.pools.delete(pluginId);
      }
    }

    this.stats.currentPooled = this.getTotalPooled();
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
 * Global plugin instance pool.
 */
export const pluginPool = new PluginInstancePoolClass();

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    pluginPool.destroy();
  });
}

export default pluginPool;

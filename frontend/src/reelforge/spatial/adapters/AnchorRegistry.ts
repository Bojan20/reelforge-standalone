/**
 * ReelForge Spatial System - Unified Anchor Registry
 * Multi-adapter anchor resolution with priority and fallback.
 *
 * @module reelforge/spatial/adapters
 */

import type {
  IAnchorAdapter,
  AnchorAdapterType,
  AnchorHandle,
  AnchorFrame,
} from '../types';
import { DOMAdapter } from './DOMAdapter';
import { PixiAdapter } from './PixiAdapter';
import { UnityAdapter } from './UnityAdapter';

/**
 * Adapter priority for resolution order.
 */
const DEFAULT_PRIORITY: AnchorAdapterType[] = ['PIXI', 'UNITY', 'DOM', 'CUSTOM'];

/**
 * Unified anchor registry that delegates to multiple adapters.
 * Resolves anchors using priority order with fallback.
 */
export class AnchorRegistry {
  /** Registered adapters */
  private adapters = new Map<AnchorAdapterType, IAnchorAdapter>();

  /** Resolution priority order */
  private priority: AnchorAdapterType[];

  /** Anchor -> adapter type mapping (for consistent resolution) */
  private anchorAdapterMap = new Map<string, AnchorAdapterType>();

  /** Previous frames for velocity calculation */
  private prevFrames = new Map<string, AnchorFrame>();

  /** Last access time per anchor (for cleanup) */
  private prevFramesLastAccess = new Map<string, number>();

  /** Max age for stale frame entries (ms) */
  private static readonly STALE_FRAME_TTL_MS = 10000;

  /** Cleanup interval (ms) */
  private static readonly CLEANUP_INTERVAL_MS = 5000;

  /** Last cleanup time */
  private lastCleanupTime = 0;

  /** Last update time */
  private lastUpdateTime = 0;

  constructor(options: {
    priority?: AnchorAdapterType[];
    autoDetect?: boolean;
  } = {}) {
    this.priority = options.priority ?? DEFAULT_PRIORITY;

    if (options.autoDetect !== false) {
      this.autoDetectAdapters();
    }
  }

  /**
   * Auto-detect and register available adapters.
   */
  private autoDetectAdapters(): void {
    // Always register DOM adapter
    if (typeof document !== 'undefined') {
      this.registerAdapter(new DOMAdapter());
    }

    // Pixi adapter (will be inactive until setStage is called)
    this.registerAdapter(new PixiAdapter());

    // Unity adapter (will be inactive until bridge is set)
    if (typeof window !== 'undefined' && (window as any).unityInstance) {
      this.registerAdapter(new UnityAdapter());
    }
  }

  /**
   * Register an adapter.
   */
  registerAdapter(adapter: IAnchorAdapter): void {
    this.adapters.set(adapter.type, adapter);
  }

  /**
   * Get adapter by type.
   */
  getAdapter<T extends IAnchorAdapter>(type: AnchorAdapterType): T | undefined {
    return this.adapters.get(type) as T | undefined;
  }

  /**
   * Remove adapter.
   */
  removeAdapter(type: AnchorAdapterType): void {
    const adapter = this.adapters.get(type);
    if (adapter) {
      adapter.dispose();
      this.adapters.delete(type);
    }

    // Clear anchor mappings for this adapter
    for (const [anchorId, adapterType] of this.anchorAdapterMap) {
      if (adapterType === type) {
        this.anchorAdapterMap.delete(anchorId);
      }
    }
  }

  /**
   * Resolve anchor by ID.
   * Tries adapters in priority order, caches successful adapter.
   */
  resolve(anchorId: string): AnchorHandle | null {
    // Check if we already know which adapter handles this anchor
    const knownAdapter = this.anchorAdapterMap.get(anchorId);
    if (knownAdapter) {
      const adapter = this.adapters.get(knownAdapter);
      if (adapter) {
        const handle = adapter.resolve(anchorId);
        if (handle) return handle;
        // Adapter no longer has it, clear mapping
        this.anchorAdapterMap.delete(anchorId);
      }
    }

    // Try adapters in priority order
    for (const type of this.priority) {
      const adapter = this.adapters.get(type);
      if (!adapter) continue;

      const handle = adapter.resolve(anchorId);
      if (handle) {
        // Remember which adapter resolved this
        this.anchorAdapterMap.set(anchorId, type);
        return handle;
      }
    }

    return null;
  }

  /**
   * Get frame for anchor.
   */
  getFrame(anchorId: string, dtSec?: number): AnchorFrame | null {
    const now = performance.now();
    const actualDt = dtSec ?? (this.lastUpdateTime > 0 ? (now - this.lastUpdateTime) / 1000 : 0);
    this.lastUpdateTime = now;

    // Periodic cleanup of stale entries
    this.maybeCleanupStaleFrames(now);

    // Find adapter
    const knownAdapter = this.anchorAdapterMap.get(anchorId);
    let adapter: IAnchorAdapter | undefined;

    if (knownAdapter) {
      adapter = this.adapters.get(knownAdapter);
    }

    if (!adapter) {
      // Try to resolve first
      const handle = this.resolve(anchorId);
      if (!handle) return null;
      adapter = this.adapters.get(handle.adapterType);
    }

    if (!adapter) return null;

    // Get previous frame for velocity
    const prev = this.prevFrames.get(anchorId);
    const frame = adapter.getFrame(anchorId, actualDt, prev);

    if (frame) {
      this.prevFrames.set(anchorId, frame);
      this.prevFramesLastAccess.set(anchorId, now);
    }

    return frame;
  }

  /**
   * Clean up stale prevFrames entries to prevent memory leaks.
   * Called periodically from getFrame.
   */
  private maybeCleanupStaleFrames(now: number): void {
    if (now - this.lastCleanupTime < AnchorRegistry.CLEANUP_INTERVAL_MS) {
      return;
    }
    this.lastCleanupTime = now;

    const staleThreshold = now - AnchorRegistry.STALE_FRAME_TTL_MS;
    const toDelete: string[] = [];

    for (const [anchorId, lastAccess] of this.prevFramesLastAccess) {
      if (lastAccess < staleThreshold) {
        toDelete.push(anchorId);
      }
    }

    for (const anchorId of toDelete) {
      this.prevFrames.delete(anchorId);
      this.prevFramesLastAccess.delete(anchorId);
    }
  }

  /**
   * Check if anchor exists.
   */
  exists(anchorId: string): boolean {
    return this.resolve(anchorId) !== null;
  }

  /**
   * Get all known anchor IDs across all adapters.
   */
  getAllAnchorIds(): string[] {
    const ids = new Set<string>();

    for (const adapter of this.adapters.values()) {
      if ('getAllAnchorIds' in adapter) {
        const adapterIds = (adapter as any).getAllAnchorIds() as string[];
        adapterIds.forEach((id) => ids.add(id));
      }
    }

    return Array.from(ids);
  }

  /**
   * Invalidate all adapter caches.
   */
  invalidateCache(): void {
    for (const adapter of this.adapters.values()) {
      adapter.invalidateCache();
    }
    this.prevFrames.clear();
    this.prevFramesLastAccess.clear();
    this.anchorAdapterMap.clear();
  }

  /**
   * Get frames for multiple anchors.
   */
  getFrames(anchorIds: string[], dtSec?: number): Map<string, AnchorFrame> {
    const frames = new Map<string, AnchorFrame>();

    for (const id of anchorIds) {
      const frame = this.getFrame(id, dtSec);
      if (frame) {
        frames.set(id, frame);
      }
    }

    return frames;
  }

  /**
   * Interpolate position between two anchors.
   */
  interpolate(
    startAnchorId: string,
    endAnchorId: string,
    progress01: number,
    dtSec?: number
  ): AnchorFrame | null {
    const startFrame = this.getFrame(startAnchorId, dtSec);
    const endFrame = this.getFrame(endAnchorId, dtSec);

    if (!startFrame || !endFrame) {
      return startFrame || endFrame;
    }

    const t = Math.max(0, Math.min(1, progress01));

    return {
      visible: startFrame.visible && endFrame.visible,
      xNorm: startFrame.xNorm + (endFrame.xNorm - startFrame.xNorm) * t,
      yNorm: startFrame.yNorm + (endFrame.yNorm - startFrame.yNorm) * t,
      wNorm: startFrame.wNorm + (endFrame.wNorm - startFrame.wNorm) * t,
      hNorm: startFrame.hNorm + (endFrame.hNorm - startFrame.hNorm) * t,
      vxNormPerS: startFrame.vxNormPerS + (endFrame.vxNormPerS - startFrame.vxNormPerS) * t,
      vyNormPerS: startFrame.vyNormPerS + (endFrame.vyNormPerS - startFrame.vyNormPerS) * t,
      confidence: Math.min(startFrame.confidence, endFrame.confidence),
      timestamp: performance.now(),
    };
  }

  /**
   * Dispose all adapters.
   */
  dispose(): void {
    for (const adapter of this.adapters.values()) {
      adapter.dispose();
    }
    this.adapters.clear();
    this.anchorAdapterMap.clear();
    this.prevFrames.clear();
    this.prevFramesLastAccess.clear();
  }
}

/**
 * Create anchor registry with auto-detection.
 */
export function createAnchorRegistry(options?: {
  priority?: AnchorAdapterType[];
  autoDetect?: boolean;
}): AnchorRegistry {
  return new AnchorRegistry(options);
}

// Re-export adapters
export { DOMAdapter, createDOMAdapter } from './DOMAdapter';
export { PixiAdapter, createPixiAdapter } from './PixiAdapter';
export { UnityAdapter, createUnityAdapter } from './UnityAdapter';
export { BaseAnchorAdapter } from './BaseAnchorAdapter';

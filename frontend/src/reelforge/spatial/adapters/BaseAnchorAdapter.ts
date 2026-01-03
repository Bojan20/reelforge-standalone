/**
 * ReelForge Spatial System - Base Anchor Adapter
 * Abstract base class for anchor resolution adapters.
 *
 * @module reelforge/spatial/adapters
 */

import type {
  IAnchorAdapter,
  AnchorAdapterType,
  AnchorHandle,
  AnchorFrame,
} from '../types';
import { clamp01, calculateVelocity } from '../utils/math';

/**
 * Cache entry for resolved anchors.
 */
interface CacheEntry {
  handle: AnchorHandle;
  lastFrame?: AnchorFrame;
  lastResolveTime: number;
}

/**
 * Abstract base class for anchor adapters.
 * Provides caching, velocity estimation, and confidence calculation.
 */
export abstract class BaseAnchorAdapter implements IAnchorAdapter {
  abstract readonly type: AnchorAdapterType;

  /** Anchor cache */
  protected cache = new Map<string, CacheEntry>();

  /** Cache TTL in ms (re-resolve after this time) */
  protected cacheTTL: number;

  /** Viewport dimensions for normalization */
  protected viewportWidth: number = 1;
  protected viewportHeight: number = 1;

  constructor(cacheTTL: number = 1000) {
    this.cacheTTL = cacheTTL;
    this.updateViewport();
  }

  /**
   * Update viewport dimensions.
   * Called on resize/orientation change.
   */
  abstract updateViewport(): void;

  /**
   * Resolve anchor by ID (implementation-specific).
   * Returns raw element/object reference.
   */
  protected abstract resolveElement(anchorId: string): unknown | null;

  /**
   * Get bounding rect for element (implementation-specific).
   * Returns pixel coordinates relative to viewport.
   */
  protected abstract getElementBounds(element: unknown): {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null;

  /**
   * Check if element is visible (implementation-specific).
   */
  protected abstract isElementVisible(element: unknown): boolean;

  /**
   * Resolve anchor handle.
   */
  resolve(anchorId: string): AnchorHandle | null {
    const now = performance.now();
    const cached = this.cache.get(anchorId);

    // Check cache validity
    if (cached && now - cached.lastResolveTime < this.cacheTTL) {
      return cached.handle;
    }

    // Resolve fresh
    const element = this.resolveElement(anchorId);
    if (!element) {
      // Remove stale cache
      this.cache.delete(anchorId);
      return null;
    }

    const handle: AnchorHandle = {
      id: anchorId,
      adapterType: this.type,
      element,
    };

    // Update cache
    if (cached) {
      cached.handle = handle;
      cached.lastResolveTime = now;
    } else {
      this.cache.set(anchorId, {
        handle,
        lastResolveTime: now,
      });
    }

    return handle;
  }

  /**
   * Get current frame for anchor.
   */
  getFrame(anchorId: string, dtSec: number, prev?: AnchorFrame): AnchorFrame | null {
    const handle = this.resolve(anchorId);
    if (!handle?.element) return null;

    const bounds = this.getElementBounds(handle.element);
    if (!bounds) return null;

    const visible = this.isElementVisible(handle.element);

    // Calculate center in normalized coordinates
    const cx = bounds.x + bounds.width * 0.5;
    const cy = bounds.y + bounds.height * 0.5;

    const xNorm = clamp01(cx / this.viewportWidth);
    const yNorm = clamp01(cy / this.viewportHeight);
    const wNorm = clamp01(bounds.width / this.viewportWidth);
    const hNorm = clamp01(bounds.height / this.viewportHeight);

    // Estimate velocity from previous frame
    let vxNormPerS = 0;
    let vyNormPerS = 0;

    if (prev && dtSec > 0) {
      vxNormPerS = calculateVelocity(xNorm, prev.xNorm, dtSec);
      vyNormPerS = calculateVelocity(yNorm, prev.yNorm, dtSec);
    }

    // Calculate confidence
    const confidence = this.calculateConfidence(visible, wNorm, hNorm, prev);

    const frame: AnchorFrame = {
      visible,
      xNorm,
      yNorm,
      wNorm,
      hNorm,
      vxNormPerS,
      vyNormPerS,
      confidence,
      timestamp: performance.now(),
    };

    // Store for next velocity calculation
    const cached = this.cache.get(anchorId);
    if (cached) {
      cached.lastFrame = frame;
    }

    return frame;
  }

  /**
   * Calculate confidence score for anchor.
   */
  protected calculateConfidence(
    visible: boolean,
    wNorm: number,
    hNorm: number,
    prev?: AnchorFrame
  ): number {
    let conf = 0;

    // Visibility is primary factor
    if (visible) {
      conf += 0.5;
    }

    // Larger elements are more reliable
    const sizeScore = Math.min(0.25, (wNorm + hNorm) * 0.5);
    conf += sizeScore;

    // Stability bonus (if previous frame exists and position is stable)
    if (prev) {
      conf += 0.15;
    }

    // Base confidence for successful resolution
    conf += 0.1;

    return clamp01(conf);
  }

  /**
   * Invalidate all cached anchors.
   */
  invalidateCache(): void {
    // Don't clear entirely - just mark for re-resolve
    const now = performance.now();
    for (const entry of this.cache.values()) {
      entry.lastResolveTime = now - this.cacheTTL - 1;
    }
    this.updateViewport();
  }

  /**
   * Dispose adapter and clear cache.
   */
  dispose(): void {
    this.cache.clear();
  }

  /**
   * Get cached frame for anchor (without re-resolving).
   */
  getCachedFrame(anchorId: string): AnchorFrame | undefined {
    return this.cache.get(anchorId)?.lastFrame;
  }

  /**
   * Get all cached anchor IDs.
   */
  getCachedAnchorIds(): string[] {
    return Array.from(this.cache.keys());
  }
}

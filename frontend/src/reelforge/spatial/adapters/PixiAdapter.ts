/**
 * ReelForge Spatial System - PixiJS Anchor Adapter
 * Resolves anchors from PixiJS DisplayObjects.
 *
 * @module reelforge/spatial/adapters
 */

import type { AnchorAdapterType } from '../types';
import { BaseAnchorAdapter } from './BaseAnchorAdapter';

/**
 * PixiJS DisplayObject interface (minimal required).
 * We don't import PIXI directly to avoid hard dependency.
 */
interface PixiDisplayObject {
  name?: string;
  visible: boolean;
  worldVisible: boolean;
  worldAlpha: number;
  worldTransform: {
    tx: number;
    ty: number;
  };
  getBounds(): {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  getGlobalPosition?(point?: { x: number; y: number }): { x: number; y: number };
}

/**
 * PixiJS Container interface.
 */
interface PixiContainer extends PixiDisplayObject {
  children: PixiDisplayObject[];
  getChildByName?(name: string): PixiDisplayObject | null;
}

/**
 * PixiJS Renderer interface.
 */
interface PixiRenderer {
  width: number;
  height: number;
  resolution: number;
  view: HTMLCanvasElement;
}

/**
 * PixiJS-based anchor adapter.
 * Resolves DisplayObjects by name or custom registry.
 */
export class PixiAdapter extends BaseAnchorAdapter {
  readonly type: AnchorAdapterType = 'PIXI';

  /** Root container (stage) */
  private stage: PixiContainer | null = null;

  /** Renderer reference */
  private renderer: PixiRenderer | null = null;

  /** Custom anchor registry (name -> object) */
  private registry = new Map<string, PixiDisplayObject>();

  /** Canvas offset relative to page */
  private canvasOffset = { x: 0, y: 0 };

  constructor(options: {
    stage?: PixiContainer;
    renderer?: PixiRenderer;
    cacheTTL?: number;
  } = {}) {
    super(options.cacheTTL ?? 100); // Shorter TTL for game objects
    this.stage = options.stage ?? null;
    this.renderer = options.renderer ?? null;
    this.updateViewport();
  }

  /**
   * Set the Pixi stage (call when app is ready).
   */
  setStage(stage: PixiContainer): void {
    this.stage = stage;
    this.invalidateCache();
  }

  /**
   * Set the Pixi renderer.
   */
  setRenderer(renderer: PixiRenderer): void {
    this.renderer = renderer;
    this.updateViewport();
  }

  /**
   * Update viewport dimensions from renderer.
   */
  updateViewport(): void {
    if (this.renderer) {
      this.viewportWidth = this.renderer.width / (this.renderer.resolution || 1);
      this.viewportHeight = this.renderer.height / (this.renderer.resolution || 1);

      // Update canvas offset
      if (this.renderer.view) {
        const rect = this.renderer.view.getBoundingClientRect();
        this.canvasOffset = { x: rect.left, y: rect.top };
      }
    } else if (typeof window !== 'undefined') {
      this.viewportWidth = window.innerWidth;
      this.viewportHeight = window.innerHeight;
    }
  }

  /**
   * Register a DisplayObject as anchor.
   */
  registerAnchor(anchorId: string, displayObject: PixiDisplayObject): void {
    this.registry.set(anchorId, displayObject);
    // Also set name for lookup
    if (!displayObject.name) {
      displayObject.name = anchorId;
    }
  }

  /**
   * Unregister anchor.
   */
  unregisterAnchor(anchorId: string): void {
    this.registry.delete(anchorId);
    this.cache.delete(anchorId);
  }

  /**
   * Resolve DisplayObject by anchor ID.
   */
  protected resolveElement(anchorId: string): PixiDisplayObject | null {
    // Check registry first
    const registered = this.registry.get(anchorId);
    if (registered) return registered;

    // Search in stage by name
    if (this.stage) {
      const found = this.findByName(this.stage, anchorId);
      if (found) return found;
    }

    return null;
  }

  /**
   * Recursively find DisplayObject by name.
   */
  private findByName(
    container: PixiContainer,
    name: string
  ): PixiDisplayObject | null {
    // Try built-in getChildByName if available
    if (container.getChildByName) {
      const found = container.getChildByName(name);
      if (found) return found;
    }

    // Manual search
    for (const child of container.children) {
      if (child.name === name) return child;

      // Recurse into containers
      if ('children' in child && Array.isArray((child as PixiContainer).children)) {
        const found = this.findByName(child as PixiContainer, name);
        if (found) return found;
      }
    }

    return null;
  }

  /**
   * Get bounding rect for DisplayObject.
   */
  protected getElementBounds(element: unknown): {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null {
    const obj = element as PixiDisplayObject;
    if (!obj || typeof obj.getBounds !== 'function') return null;

    try {
      const bounds = obj.getBounds();

      // Validate bounds
      if (
        !isFinite(bounds.x) ||
        !isFinite(bounds.y) ||
        bounds.width <= 0 ||
        bounds.height <= 0
      ) {
        return null;
      }

      return bounds;
    } catch {
      return null;
    }
  }

  /**
   * Check if DisplayObject is visible.
   */
  protected isElementVisible(element: unknown): boolean {
    const obj = element as PixiDisplayObject;
    if (!obj) return false;

    // Check visibility flags
    if (!obj.visible || !obj.worldVisible) return false;

    // Check alpha
    if (obj.worldAlpha <= 0) return false;

    // Check if in viewport
    const bounds = this.getElementBounds(obj);
    if (!bounds) return false;

    const inViewport = (
      bounds.x + bounds.width >= 0 &&
      bounds.y + bounds.height >= 0 &&
      bounds.x <= this.viewportWidth &&
      bounds.y <= this.viewportHeight
    );

    return inViewport;
  }

  /**
   * Get global position for object (uses center).
   */
  getGlobalPosition(anchorId: string): { x: number; y: number } | null {
    const obj = this.resolveElement(anchorId);
    if (!obj) return null;

    if (obj.getGlobalPosition) {
      return obj.getGlobalPosition();
    }

    // Fallback to bounds center
    const bounds = this.getElementBounds(obj);
    if (!bounds) return null;

    return {
      x: bounds.x + bounds.width * 0.5,
      y: bounds.y + bounds.height * 0.5,
    };
  }

  /**
   * Convert Pixi coordinates to page coordinates.
   * Useful when mixing DOM and Pixi anchors.
   */
  pixiToPage(x: number, y: number): { x: number; y: number } {
    return {
      x: x + this.canvasOffset.x,
      y: y + this.canvasOffset.y,
    };
  }

  /**
   * Get all registered anchor IDs.
   */
  getAllAnchorIds(): string[] {
    return Array.from(this.registry.keys());
  }

  /**
   * Dispose adapter.
   */
  override dispose(): void {
    super.dispose();
    this.registry.clear();
    this.stage = null;
    this.renderer = null;
  }
}

/**
 * Create Pixi adapter with optional stage and renderer.
 */
export function createPixiAdapter(options?: {
  stage?: PixiContainer;
  renderer?: PixiRenderer;
  cacheTTL?: number;
}): PixiAdapter {
  return new PixiAdapter(options);
}

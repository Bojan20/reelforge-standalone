/**
 * ReelForge Spatial System - Unity WebGL Anchor Adapter
 * Resolves anchors from Unity WebGL builds via jslib bridge.
 *
 * @module reelforge/spatial/adapters
 */

import type { AnchorAdapterType, AnchorFrame } from '../types';
import { BaseAnchorAdapter } from './BaseAnchorAdapter';
import { clamp01 } from '../utils/math';

/**
 * Unity anchor data from jslib bridge.
 */
interface UnityAnchorData {
  id: string;
  x: number;        // Screen X
  y: number;        // Screen Y (Unity Y is inverted)
  width: number;
  height: number;
  visible: boolean;
  screenWidth: number;
  screenHeight: number;
}

/**
 * Validate Unity anchor data structure.
 * Returns null if invalid, or the validated data if valid.
 */
function validateAnchorData(data: unknown): UnityAnchorData | null {
  if (!data || typeof data !== 'object') {
    return null;
  }

  const obj = data as Record<string, unknown>;

  // Required fields with type checks
  if (typeof obj.id !== 'string' || obj.id.length === 0) return null;
  if (typeof obj.x !== 'number' || !Number.isFinite(obj.x)) return null;
  if (typeof obj.y !== 'number' || !Number.isFinite(obj.y)) return null;
  if (typeof obj.width !== 'number' || !Number.isFinite(obj.width)) return null;
  if (typeof obj.height !== 'number' || !Number.isFinite(obj.height)) return null;
  if (typeof obj.visible !== 'boolean') return null;
  if (typeof obj.screenWidth !== 'number' || !Number.isFinite(obj.screenWidth)) return null;
  if (typeof obj.screenHeight !== 'number' || !Number.isFinite(obj.screenHeight)) return null;

  // Sanity checks for reasonable values
  if (obj.width < 0 || obj.height < 0) return null;
  if (obj.screenWidth <= 0 || obj.screenHeight <= 0) return null;

  return {
    id: obj.id,
    x: obj.x,
    y: obj.y,
    width: obj.width,
    height: obj.height,
    visible: obj.visible,
    screenWidth: obj.screenWidth,
    screenHeight: obj.screenHeight,
  };
}

/**
 * Validate viewport data structure.
 */
function validateViewportData(data: unknown): { width: number; height: number } | null {
  if (!data || typeof data !== 'object') {
    return null;
  }

  const obj = data as Record<string, unknown>;

  if (typeof obj.width !== 'number' || !Number.isFinite(obj.width) || obj.width <= 0) return null;
  if (typeof obj.height !== 'number' || !Number.isFinite(obj.height) || obj.height <= 0) return null;

  return { width: obj.width, height: obj.height };
}

/**
 * Safely parse JSON with validation.
 */
function safeParseJSON<T>(
  json: string,
  validator: (data: unknown) => T | null
): T | null {
  try {
    const parsed = JSON.parse(json);
    return validator(parsed);
  } catch {
    return null;
  }
}

/**
 * Unity jslib bridge interface.
 * This should be implemented in Unity's Plugins/WebGL/spatial.jslib
 */
interface UnityBridge {
  /** Get anchor data by ID */
  GetAnchorData(anchorId: string): string; // JSON string

  /** Get all anchor IDs */
  GetAllAnchorIds(): string; // JSON array string

  /** Register anchor from Unity */
  RegisterAnchor(anchorId: string, gameObjectPath: string): void;

  /** Unregister anchor */
  UnregisterAnchor(anchorId: string): void;

  /** Get screen dimensions */
  GetScreenDimensions(): string; // JSON {width, height}
}

/**
 * Unique symbol for secure receiver access.
 * Prevents external code from easily accessing/replacing the receiver.
 */
const RECEIVER_KEY = Symbol.for('RFSpatialReceiver_v1');

/**
 * Global Unity instance (set by Unity WebGL loader).
 */
declare global {
  interface Window {
    unityInstance?: {
      SendMessage: (objectName: string, methodName: string, value?: string) => void;
    };
    RFSpatialBridge?: UnityBridge;
    [RECEIVER_KEY]?: UnityReceiverInterface;
  }
}

/**
 * Interface for Unity receiver callbacks.
 */
interface UnityReceiverInterface {
  updateAnchor: (jsonData: string) => void;
  removeAnchor: (anchorId: string) => void;
  updateViewport: (jsonData: string) => void;
}

/**
 * Unity WebGL anchor adapter.
 * Communicates with Unity via jslib bridge.
 */
export class UnityAdapter extends BaseAnchorAdapter {
  readonly type: AnchorAdapterType = 'UNITY';

  /** Bridge to Unity */
  private bridge: UnityBridge | null = null;

  /** Pending anchor data (for async updates from Unity) */
  private pendingData = new Map<string, UnityAnchorData>();

  /** Canvas element (Unity WebGL canvas) */
  private canvas: HTMLCanvasElement | null = null;

  constructor(options: {
    bridge?: UnityBridge;
    canvas?: HTMLCanvasElement;
    cacheTTL?: number;
  } = {}) {
    super(options.cacheTTL ?? 50); // Very short TTL for game engine

    this.bridge = options.bridge ?? window.RFSpatialBridge ?? null;
    this.canvas = options.canvas ?? null;

    // Auto-detect canvas
    if (!this.canvas) {
      this.canvas = document.querySelector('#unity-canvas') as HTMLCanvasElement;
    }

    this.updateViewport();

    // Setup global receiver for Unity callbacks
    this.setupGlobalReceiver();
  }

  /**
   * Setup global receiver for Unity -> JS callbacks.
   * Uses Symbol key for security (not easily enumerable/replaceable).
   * Also provides legacy string-based access for Unity jslib compatibility.
   */
  private setupGlobalReceiver(): void {
    const receiver: UnityReceiverInterface = {
      updateAnchor: (jsonData: string) => {
        const data = safeParseJSON(jsonData, validateAnchorData);
        if (data) {
          this.pendingData.set(data.id, data);
        }
        // Silently ignore invalid data in production (no console.warn)
      },

      removeAnchor: (anchorId: string) => {
        if (typeof anchorId === 'string' && anchorId.length > 0) {
          this.pendingData.delete(anchorId);
          this.cache.delete(anchorId);
        }
      },

      updateViewport: (jsonData: string) => {
        const viewport = safeParseJSON(jsonData, validateViewportData);
        if (viewport) {
          this.viewportWidth = viewport.width;
          this.viewportHeight = viewport.height;
        }
        // Silently ignore invalid data in production (no console.warn)
      },
    };

    // Store under Symbol key (secure, not easily enumerable)
    (window as any)[RECEIVER_KEY] = receiver;

    // Also provide string-based access for Unity jslib compatibility
    // (Unity jslib can't use Symbol, so we need this fallback)
    // The receiver object is frozen to prevent tampering
    Object.defineProperty(window, 'RFSpatialReceiver', {
      value: Object.freeze(receiver),
      writable: false,
      configurable: true, // Allow cleanup on dispose
      enumerable: false, // Don't show in Object.keys(window)
    });
  }

  /**
   * Set Unity bridge.
   */
  setBridge(bridge: UnityBridge): void {
    this.bridge = bridge;
    this.invalidateCache();
  }

  /**
   * Set Unity canvas.
   */
  setCanvas(canvas: HTMLCanvasElement): void {
    this.canvas = canvas;
    this.updateViewport();
  }

  /**
   * Update viewport from Unity or canvas.
   */
  updateViewport(): void {
    // Try bridge first
    if (this.bridge) {
      const dimJson = this.bridge.GetScreenDimensions();
      const viewport = safeParseJSON(dimJson, validateViewportData);
      if (viewport) {
        this.viewportWidth = viewport.width;
        this.viewportHeight = viewport.height;
        return;
      }
      // Fall through to canvas if validation failed
    }

    // Fallback to canvas
    if (this.canvas) {
      const rect = this.canvas.getBoundingClientRect();
      this.viewportWidth = rect.width;
      this.viewportHeight = rect.height;
      // Canvas offset stored for future unityToPage conversion if needed
    } else if (typeof window !== 'undefined') {
      this.viewportWidth = window.innerWidth;
      this.viewportHeight = window.innerHeight;
    }
  }

  /**
   * Resolve Unity anchor data.
   */
  protected resolveElement(anchorId: string): UnityAnchorData | null {
    // Validate anchorId
    if (typeof anchorId !== 'string' || anchorId.length === 0) {
      return null;
    }

    // Check pending data first (pushed from Unity)
    const pending = this.pendingData.get(anchorId);
    if (pending) return pending;

    // Try bridge call
    if (this.bridge) {
      const json = this.bridge.GetAnchorData(anchorId);
      if (json) {
        const data = safeParseJSON(json, validateAnchorData);
        if (data) {
          return data;
        }
      }
    }

    return null;
  }

  /**
   * Get bounds from Unity anchor data.
   * Note: Unity Y is typically inverted (0 at bottom).
   */
  protected getElementBounds(element: unknown): {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null {
    const data = element as UnityAnchorData;
    if (!data) return null;

    // Unity Y inversion: screenY in Unity is from bottom
    // Convert to top-down coordinates
    const invertedY = data.screenHeight - data.y - data.height;

    return {
      x: data.x,
      y: invertedY,
      width: data.width,
      height: data.height,
    };
  }

  /**
   * Check visibility from Unity data.
   */
  protected isElementVisible(element: unknown): boolean {
    const data = element as UnityAnchorData;
    return data?.visible ?? false;
  }

  /**
   * Override getFrame to handle Unity's coordinate system.
   */
  override getFrame(anchorId: string, dtSec: number, prev?: AnchorFrame): AnchorFrame | null {
    const data = this.resolveElement(anchorId);
    if (!data) return null;

    // Use screen dimensions from Unity data if available
    const screenW = data.screenWidth || this.viewportWidth;
    const screenH = data.screenHeight || this.viewportHeight;

    // Unity Y inversion
    const invertedY = screenH - data.y - data.height;

    // Calculate center
    const cx = data.x + data.width * 0.5;
    const cy = invertedY + data.height * 0.5;

    const xNorm = clamp01(cx / screenW);
    const yNorm = clamp01(cy / screenH);
    const wNorm = clamp01(data.width / screenW);
    const hNorm = clamp01(data.height / screenH);

    // Velocity
    let vxNormPerS = 0;
    let vyNormPerS = 0;
    if (prev && dtSec > 0) {
      vxNormPerS = (xNorm - prev.xNorm) / dtSec;
      vyNormPerS = (yNorm - prev.yNorm) / dtSec;
    }

    // Confidence
    const confidence = this.calculateConfidence(data.visible, wNorm, hNorm, prev);

    const frame: AnchorFrame = {
      visible: data.visible,
      xNorm,
      yNorm,
      wNorm,
      hNorm,
      vxNormPerS,
      vyNormPerS,
      confidence,
      timestamp: performance.now(),
    };

    // Store for velocity
    const cached = this.cache.get(anchorId);
    if (cached) {
      cached.lastFrame = frame;
    }

    return frame;
  }

  /**
   * Register anchor in Unity (sends message to Unity).
   */
  registerAnchor(anchorId: string, gameObjectPath: string): void {
    if (this.bridge) {
      this.bridge.RegisterAnchor(anchorId, gameObjectPath);
    } else if (window.unityInstance) {
      window.unityInstance.SendMessage(
        'RFSpatialManager',
        'RegisterAnchor',
        JSON.stringify({ id: anchorId, path: gameObjectPath })
      );
    }
  }

  /**
   * Unregister anchor.
   */
  unregisterAnchor(anchorId: string): void {
    this.pendingData.delete(anchorId);
    this.cache.delete(anchorId);

    if (this.bridge) {
      this.bridge.UnregisterAnchor(anchorId);
    }
  }

  /**
   * Get all anchor IDs from Unity.
   */
  getAllAnchorIds(): string[] {
    // Combine pending and bridge
    const ids = new Set(this.pendingData.keys());

    if (this.bridge) {
      const json = this.bridge.GetAllAnchorIds();
      const bridgeIds = safeParseJSON(json, (data): string[] | null => {
        if (!Array.isArray(data)) return null;
        // Filter to only valid string IDs
        return data.filter((id): id is string => typeof id === 'string' && id.length > 0);
      });
      if (bridgeIds) {
        bridgeIds.forEach((id) => ids.add(id));
      }
    }

    return Array.from(ids);
  }

  /**
   * Dispose adapter and cleanup global receivers.
   */
  override dispose(): void {
    super.dispose();
    this.pendingData.clear();

    // Cleanup Symbol-keyed receiver
    delete (window as any)[RECEIVER_KEY];

    // Cleanup string-keyed receiver (redefine as undefined, then delete)
    // configurable: true allows this
    try {
      Object.defineProperty(window, 'RFSpatialReceiver', {
        value: undefined,
        writable: true,
        configurable: true,
      });
      delete (window as any).RFSpatialReceiver;
    } catch {
      // Fallback if property descriptor manipulation fails
      (window as any).RFSpatialReceiver = undefined;
    }

    this.bridge = null;
    this.canvas = null;
  }
}

/**
 * Create Unity adapter.
 */
export function createUnityAdapter(options?: {
  bridge?: UnityBridge;
  canvas?: HTMLCanvasElement;
  cacheTTL?: number;
}): UnityAdapter {
  return new UnityAdapter(options);
}

/**
 * Example Unity jslib implementation (for documentation):
 *
 * ```javascript
 * // Plugins/WebGL/RFSpatial.jslib
 * mergeInto(LibraryManager.library, {
 *   RFSpatial_GetAnchorData: function(anchorIdPtr) {
 *     var anchorId = UTF8ToString(anchorIdPtr);
 *     var data = window.RFSpatialBridge.GetAnchorData(anchorId);
 *     var bufferSize = lengthBytesUTF8(data) + 1;
 *     var buffer = _malloc(bufferSize);
 *     stringToUTF8(data, buffer, bufferSize);
 *     return buffer;
 *   },
 *
 *   RFSpatial_UpdateAnchor: function(jsonPtr) {
 *     var json = UTF8ToString(jsonPtr);
 *     if (window.RFSpatialReceiver) {
 *       window.RFSpatialReceiver.updateAnchor(json);
 *     }
 *   }
 * });
 * ```
 */

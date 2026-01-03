/**
 * ReelForge Native RuntimeCore Integration
 *
 * Wrapper for the native RuntimeCore addon.
 * Provides a fallback when native addon is not available (web build).
 */

// Types matching the native addon
export interface NativeGameEvent {
  name: string;
  seq?: number;
  engineTimeMs?: number;
}

export interface NativePlayCommand {
  type: 'Play';
  assetId: string;
  bus: string;
  gain: number;
  loop: boolean;
  startTimeMs?: number;
}

export interface NativeStopCommand {
  type: 'Stop';
  voiceId: string;
}

export interface NativeStopAllCommand {
  type: 'StopAll';
}

export interface NativeSetBusGainCommand {
  type: 'SetBusGain';
  bus: string;
  gain: number;
}

export type NativeAdapterCommand =
  | NativePlayCommand
  | NativeStopCommand
  | NativeStopAllCommand
  | NativeSetBusGainCommand;

/**
 * RuntimeStats from native core (M6.5)
 */
export interface NativeRuntimeStats {
  // Gauges
  activeVoices: number;
  activeMusic: number;
  activeSfx: number;
  activeUi: number;
  activeVo: number;
  activeAmbience: number;

  // Counters
  plays: number;
  stops: number;
  stopAlls: number;
  steals: number;
  drops: number;

  // Ducking state
  musicDucked: boolean;
  duckEngageCount: number;
  duckReleaseCount: number;
}

/**
 * Routes info from native core (M6.6)
 */
export interface NativeRoutesInfo {
  dataDriven: boolean;
  version: number;
  eventCount: number;
}

export interface NativeRuntimeCoreOptions {
  manifestPath: string;
  routesPath?: string;
  distRoot?: string;
  seed?: number;
}

/**
 * Interface for the native RuntimeCore.
 */
export interface INativeRuntimeCore {
  submitEvent(event: NativeGameEvent): NativeAdapterCommand[];
  reset(options?: { seed?: number }): void;
  getEventCount(): number;
  getManifestVersion(): string;
  getAssetCount(): number;
  getStats(): NativeRuntimeStats;
  resetStats(): void;
  getRoutesInfo(): NativeRoutesInfo;
  // M6.8: Hot reload
  reloadRoutesFromFile(path: string): void;
  reloadRoutesFromString(json: string): void;
}

// Lazy-loaded native addon
let nativeAddon: { RuntimeCoreNative: new (options: NativeRuntimeCoreOptions) => INativeRuntimeCore } | null = null;
let loadAttempted = false;
let loadError: Error | null = null;

/**
 * Check if native RuntimeCore is available.
 */
export function isNativeRuntimeCoreAvailable(): boolean {
  if (!loadAttempted) {
    tryLoadNativeAddon();
  }
  return nativeAddon !== null;
}

/**
 * Get the load error if native addon failed to load.
 */
export function getNativeLoadError(): Error | null {
  if (!loadAttempted) {
    tryLoadNativeAddon();
  }
  return loadError;
}

// Declare require for environments where it exists (Electron/Node)
declare const require: ((module: string) => unknown) | undefined;

/**
 * Try to load the native addon.
 */
function tryLoadNativeAddon(): void {
  if (loadAttempted) return;
  loadAttempted = true;

  try {
    // This will only work in Electron/Node environment
    // In browser, require is not available
    if (typeof require !== 'undefined' && require !== null) {
      // Try to load the native addon
      // Path is relative to the built app location
      nativeAddon = require('../../runtime_bindings/node/lib/index.js') as typeof nativeAddon;
      console.log('[NativeRuntimeCore] Native addon loaded successfully');
    } else {
      loadError = new Error('require() not available - running in browser context');
    }
  } catch (e) {
    loadError = e as Error;
    console.warn('[NativeRuntimeCore] Failed to load native addon:', (e as Error).message);
  }
}

/**
 * Create a native RuntimeCore instance.
 *
 * @throws Error if native addon is not available
 */
export function createNativeRuntimeCore(options: NativeRuntimeCoreOptions): INativeRuntimeCore {
  if (!isNativeRuntimeCoreAvailable()) {
    throw new Error(
      'Native RuntimeCore is not available: ' +
      (loadError?.message || 'Unknown error')
    );
  }

  return new nativeAddon!.RuntimeCoreNative(options);
}

/**
 * Wrapper class that provides a consistent interface whether native or not.
 */
export class NativeRuntimeCoreWrapper {
  private core: INativeRuntimeCore | null = null;
  private enabled = false;
  private manifestPath: string;
  private routesPath?: string;
  private seed: number;

  constructor(manifestPath: string, seed = 1, routesPath?: string) {
    this.manifestPath = manifestPath;
    this.seed = seed;
    this.routesPath = routesPath;
  }

  /**
   * Enable native RuntimeCore.
   * @returns true if successfully enabled, false otherwise
   */
  enable(): boolean {
    if (this.enabled && this.core) {
      return true;
    }

    if (!isNativeRuntimeCoreAvailable()) {
      console.warn('[NativeRuntimeCore] Cannot enable - native addon not available');
      return false;
    }

    try {
      console.log(`[NativeRuntimeCore] Loading manifest: ${this.manifestPath}`);
      console.log(`[NativeRuntimeCore] Loading routes: ${this.routesPath || '(fallback mode)'}`);
      this.core = createNativeRuntimeCore({
        manifestPath: this.manifestPath,
        routesPath: this.routesPath,
        seed: this.seed,
      });
      this.enabled = true;
      const routesInfo = this.core.getRoutesInfo();
      console.log(`[NativeRuntimeCore] Enabled - Routes: dataDriven=${routesInfo.dataDriven} version=${routesInfo.version} events=${routesInfo.eventCount}`);
      return true;
    } catch (e) {
      console.error('[NativeRuntimeCore] Failed to enable:', (e as Error).message);
      return false;
    }
  }

  /**
   * Disable native RuntimeCore.
   */
  disable(): void {
    this.core = null;
    this.enabled = false;
    console.log('[NativeRuntimeCore] Disabled');
  }

  /**
   * Check if native RuntimeCore is enabled.
   */
  isEnabled(): boolean {
    return this.enabled && this.core !== null;
  }

  /**
   * Submit an event to the native core.
   * @returns Commands array, or null if not enabled
   */
  submitEvent(event: NativeGameEvent): NativeAdapterCommand[] | null {
    if (!this.core) {
      return null;
    }
    return this.core.submitEvent(event);
  }

  /**
   * Reset the core.
   */
  reset(options?: { seed?: number }): void {
    if (options?.seed !== undefined) {
      this.seed = options.seed;
    }
    this.core?.reset(options);
  }

  /**
   * Get event count.
   */
  getEventCount(): number {
    return this.core?.getEventCount() ?? 0;
  }

  /**
   * Get manifest version.
   */
  getManifestVersion(): string {
    return this.core?.getManifestVersion() ?? 'N/A';
  }

  /**
   * Get runtime statistics (M6.5).
   */
  getStats(): NativeRuntimeStats | null {
    return this.core?.getStats() ?? null;
  }

  /**
   * Reset statistics counters (M6.5).
   */
  resetStats(): void {
    this.core?.resetStats();
  }

  /**
   * Get routes configuration info (M6.6).
   */
  getRoutesInfo(): NativeRoutesInfo | null {
    return this.core?.getRoutesInfo() ?? null;
  }

  /**
   * Hot-reload routes from file (M6.8).
   *
   * Atomic swap: Core stays enabled, only routes are replaced.
   * On failure, existing routes remain unchanged.
   *
   * @param path Path to runtime_routes.json
   * @throws Error with RF_ERR code if validation fails
   */
  reloadRoutesFromFile(path: string): void {
    if (!this.core) {
      throw new Error('Native RuntimeCore not enabled');
    }
    this.core.reloadRoutesFromFile(path);
    // Update stored path on success
    this.routesPath = path;
  }

  /**
   * Hot-reload routes from JSON string (M6.8).
   *
   * Atomic swap: Core stays enabled, only routes are replaced.
   * On failure, existing routes remain unchanged.
   *
   * @param json JSON content of routes
   * @throws Error with RF_ERR code if validation fails
   */
  reloadRoutesFromString(json: string): void {
    if (!this.core) {
      throw new Error('Native RuntimeCore not enabled');
    }
    this.core.reloadRoutesFromString(json);
  }
}

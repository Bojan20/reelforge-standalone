/**
 * ReelForge M6.7 Routes Storage
 *
 * Abstraction for loading/saving routes in browser vs Electron environments.
 * Browser: Load from URL, save via download
 * Electron: Load/save directly to filesystem
 */

import type { RoutesConfig } from './routesTypes';
import { createEmptyRoutesConfig } from './routesTypes';
import type { RouteValidationResult } from './validateRoutes';
import { parseRoutesJson, stringifyRoutes } from './validateRoutes';

/**
 * Storage abstraction interface.
 */
export interface IRoutesStorage {
  /**
   * Load routes from storage.
   * @returns Routes config and validation result
   */
  load(): Promise<{
    config: RoutesConfig;
    validation: RouteValidationResult;
    source: string;
  }>;

  /**
   * Save routes to storage.
   * @param config Routes config to save
   * @returns True if saved successfully
   */
  save(config: RoutesConfig): Promise<boolean>;

  /**
   * Check if we can save directly to filesystem.
   */
  canSaveDirect(): boolean;

  /**
   * Get the current routes file path (for display).
   */
  getPath(): string;
}

/**
 * Browser-based routes storage.
 * Loads from URL, saves via download.
 */
export class BrowserRoutesStorage implements IRoutesStorage {
  private routesUrl: string;
  private assetIds?: Set<string>;

  constructor(routesUrl: string, assetIds?: Set<string>) {
    this.routesUrl = routesUrl;
    this.assetIds = assetIds;
  }

  async load(): Promise<{
    config: RoutesConfig;
    validation: RouteValidationResult;
    source: string;
  }> {
    try {
      const response = await fetch(this.routesUrl);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      const json = await response.text();
      const { config, validation } = parseRoutesJson(json, this.assetIds);

      return {
        config: config ?? createEmptyRoutesConfig(),
        validation,
        source: this.routesUrl,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        config: createEmptyRoutesConfig(),
        validation: {
          valid: false,
          errors: [{
            type: 'error',
            message: `Failed to load routes: ${message}`,
          }],
          warnings: [],
        },
        source: this.routesUrl,
      };
    }
  }

  async save(config: RoutesConfig): Promise<boolean> {
    // Browser can only download
    const json = stringifyRoutes(config);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = 'runtime_routes.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    return true;
  }

  canSaveDirect(): boolean {
    return false;
  }

  getPath(): string {
    return this.routesUrl;
  }
}

/**
 * Electron-based routes storage.
 * Loads and saves directly to filesystem via Node.js fs.
 */
export class ElectronRoutesStorage implements IRoutesStorage {
  private routesPath: string;
  private assetIds?: Set<string>;

  constructor(routesPath: string, assetIds?: Set<string>) {
    this.routesPath = routesPath;
    this.assetIds = assetIds;
  }

  async load(): Promise<{
    config: RoutesConfig;
    validation: RouteValidationResult;
    source: string;
  }> {
    try {
      // Use Node.js fs module via require (available in Electron renderer with nodeIntegration)
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const fs = (window as any).require?.('fs');
      if (!fs) {
        throw new Error('fs module not available');
      }

      const json = fs.readFileSync(this.routesPath, 'utf-8');
      const { config, validation } = parseRoutesJson(json, this.assetIds);

      return {
        config: config ?? createEmptyRoutesConfig(),
        validation,
        source: this.routesPath,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        config: createEmptyRoutesConfig(),
        validation: {
          valid: false,
          errors: [{
            type: 'error',
            message: `Failed to load routes: ${message}`,
          }],
          warnings: [],
        },
        source: this.routesPath,
      };
    }
  }

  async save(config: RoutesConfig): Promise<boolean> {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const fs = (window as any).require?.('fs');
      if (!fs) {
        throw new Error('fs module not available');
      }

      const json = stringifyRoutes(config);
      fs.writeFileSync(this.routesPath, json, 'utf-8');
      return true;
    } catch (error) {
      console.error('[RoutesStorage] Failed to save:', error);
      return false;
    }
  }

  canSaveDirect(): boolean {
    return true;
  }

  getPath(): string {
    return this.routesPath;
  }
}

/**
 * Create appropriate storage based on environment.
 */
export function createRoutesStorage(
  routesPath: string,
  assetIds?: Set<string>
): IRoutesStorage {
  // Check if we're in Electron with nodeIntegration
  const hasNodeFs = typeof (window as any).require === 'function';

  if (hasNodeFs) {
    try {
      const fs = (window as any).require('fs');
      if (fs && typeof fs.readFileSync === 'function') {
        console.log('[RoutesStorage] Using ElectronRoutesStorage');
        return new ElectronRoutesStorage(routesPath, assetIds);
      }
    } catch {
      // Fall through to browser storage
    }
  }

  console.log('[RoutesStorage] Using BrowserRoutesStorage');
  return new BrowserRoutesStorage(routesPath, assetIds);
}

/**
 * Create a backup of the current routes for rollback.
 */
export function createRoutesBackup(config: RoutesConfig): string {
  return stringifyRoutes(config);
}

/**
 * Restore routes from a backup string.
 */
export function restoreRoutesBackup(
  backup: string,
  assetIds?: Set<string>
): { config: RoutesConfig | null; validation: RouteValidationResult } {
  return parseRoutesJson(backup, assetIds);
}

/**
 * ReelForge M8.0 Project Storage
 *
 * Storage abstraction for project files.
 * Supports browser (download/upload) and is Electron-ready.
 */

import type { ProjectFileV1 } from './projectTypes';
import { validateProjectFile } from './validateProjectFile';
import { migrateProject } from './migrateProject';

/**
 * Storage interface for project files.
 */
export interface IProjectStorage {
  /** Save project to storage */
  save(project: ProjectFileV1, filename?: string): Promise<void>;
  /** Load project from storage (browser: opens file picker) */
  load(): Promise<ProjectFileV1 | null>;
  /** Check if storage is available */
  isAvailable(): boolean;
}

/**
 * Deterministic JSON serialization for project files.
 * Ensures stable output for clean git diffs.
 *
 * Rules:
 * - Sorted keys
 * - 2-space indentation
 * - Newline at end
 * - Consistent number formatting
 */
export function stringifyProject(project: ProjectFileV1): string {
  // Define key order for top-level
  const keyOrder = [
    'projectVersion',
    'name',
    'createdAt',
    'updatedAt',
    'paths',
    'routes',
    'studio',
  ];

  // Custom replacer for stable serialization
  const sortedProject = sortObjectKeys(project, keyOrder);

  // Serialize with 2-space indentation
  const json = JSON.stringify(sortedProject, null, 2);

  // Ensure newline at end
  return json + '\n';
}

/**
 * Sort object keys according to a specified order.
 * Keys not in order are sorted alphabetically at the end.
 */
function sortObjectKeys(obj: unknown, keyOrder?: string[]): unknown {
  if (obj === null || typeof obj !== 'object') {
    return obj;
  }

  if (Array.isArray(obj)) {
    return obj.map((item) => sortObjectKeys(item));
  }

  const record = obj as Record<string, unknown>;
  const keys = Object.keys(record);

  // Sort keys
  const sortedKeys = keys.sort((a, b) => {
    if (keyOrder) {
      const aIndex = keyOrder.indexOf(a);
      const bIndex = keyOrder.indexOf(b);

      // Both in order list
      if (aIndex !== -1 && bIndex !== -1) {
        return aIndex - bIndex;
      }
      // Only a in order list
      if (aIndex !== -1) {
        return -1;
      }
      // Only b in order list
      if (bIndex !== -1) {
        return 1;
      }
    }
    // Neither in order list, sort alphabetically
    return a.localeCompare(b);
  });

  // Build new object with sorted keys
  const sorted: Record<string, unknown> = {};
  for (const key of sortedKeys) {
    // Recursively sort nested objects
    const value = record[key];

    // Define nested key orders
    let nestedOrder: string[] | undefined;
    if (key === 'paths') {
      nestedOrder = ['manifestPath', 'routesPath'];
    } else if (key === 'routes') {
      nestedOrder = ['embed', 'data'];
    } else if (key === 'studio') {
      nestedOrder = ['selectedTab', 'routesUi', 'masterInsertChain', 'pdcEnabled', 'busInsertChains', 'busPdcEnabled', 'assetInsertChains'];
    } else if (key === 'busInsertChains' || key === 'busPdcEnabled') {
      // Sort bus IDs alphabetically: ambience, music, sfx, voice
      nestedOrder = ['ambience', 'music', 'sfx', 'voice'];
    } else if (key === 'assetInsertChains') {
      // Asset insert chains: sort asset IDs alphabetically for determinism
      // No predefined order - alphabetical sort will be applied automatically
      nestedOrder = undefined;
    } else if (key === 'routesUi') {
      nestedOrder = ['selectedEventName', 'searchQuery'];
    } else if (key === 'data') {
      // Routes data
      nestedOrder = ['routesVersion', 'defaultBus', 'events'];
    } else if (key === 'masterInsertChain') {
      nestedOrder = ['inserts'];
    } else if (key === 'inserts') {
      // Array of inserts - ordering handled per item
      nestedOrder = undefined;
    }

    // Handle insert objects in arrays
    if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'object' && value[0] !== null) {
      const firstItem = value[0] as Record<string, unknown>;
      // Detect insert objects by presence of pluginId
      if ('pluginId' in firstItem) {
        // Insert array - apply insert key ordering to each item
        sorted[key] = value.map((item) =>
          sortObjectKeys(item, ['id', 'pluginId', 'enabled', 'params'])
        );
        continue;
      }
      // Detect EQ bands by presence of frequency
      if ('frequency' in firstItem && 'gain' in firstItem) {
        // EQ band array
        sorted[key] = value.map((item) =>
          sortObjectKeys(item, ['type', 'frequency', 'gain', 'q'])
        );
        continue;
      }
    }

    // Handle params objects (detect by parent context)
    if (key === 'params' && typeof value === 'object' && value !== null) {
      const params = value as Record<string, unknown>;
      if ('bands' in params) {
        // EQ params
        nestedOrder = ['bands'];
      } else if ('threshold' in params && 'ratio' in params) {
        // Compressor params
        nestedOrder = ['threshold', 'knee', 'ratio', 'attack', 'release'];
      } else if ('threshold' in params && 'release' in params) {
        // Limiter params
        nestedOrder = ['threshold', 'knee', 'release'];
      }
    }

    sorted[key] = sortObjectKeys(value, nestedOrder);
  }

  return sorted;
}

/**
 * Browser-based project storage using download/upload.
 */
export class BrowserProjectStorage implements IProjectStorage {
  private lastFilename: string = 'reelforge_project.json';

  isAvailable(): boolean {
    return typeof window !== 'undefined' && typeof document !== 'undefined';
  }

  async save(project: ProjectFileV1, filename?: string): Promise<void> {
    if (!this.isAvailable()) {
      throw new Error('Browser storage not available');
    }

    const name = filename || this.lastFilename;
    this.lastFilename = name;

    // Update timestamp before saving
    const projectToSave: ProjectFileV1 = {
      ...project,
      updatedAt: new Date().toISOString(),
    };

    // Serialize deterministically
    const json = stringifyProject(projectToSave);

    // Create blob and download
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    URL.revokeObjectURL(url);
  }

  async load(): Promise<ProjectFileV1 | null> {
    if (!this.isAvailable()) {
      throw new Error('Browser storage not available');
    }

    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.json,application/json';

      input.onchange = async (e) => {
        const file = (e.target as HTMLInputElement).files?.[0];
        if (!file) {
          resolve(null);
          return;
        }

        this.lastFilename = file.name;

        try {
          const text = await file.text();
          const parsed = JSON.parse(text);

          // Try migration first
          const migrationResult = migrateProject(parsed);
          if (!migrationResult.success) {
            console.error('[ProjectStorage] Migration failed:', migrationResult.error);
            resolve(null);
            return;
          }

          // Validate
          const validation = validateProjectFile(migrationResult.project);
          if (!validation.valid) {
            console.error('[ProjectStorage] Validation failed:', validation.errors);
            resolve(null);
            return;
          }

          resolve(migrationResult.project);
        } catch (err) {
          console.error('[ProjectStorage] Load failed:', err);
          resolve(null);
        }
      };

      input.oncancel = () => {
        resolve(null);
      };

      input.click();
    });
  }

  /**
   * Get the last used filename.
   */
  getLastFilename(): string {
    return this.lastFilename;
  }

  /**
   * Set the filename for next save.
   */
  setFilename(filename: string): void {
    this.lastFilename = filename;
  }
}

/**
 * Electron-ready project storage (stub for future implementation).
 */
export class ElectronProjectStorage implements IProjectStorage {
  isAvailable(): boolean {
    // Check if running in Electron
    return typeof window !== 'undefined' &&
           'require' in window &&
           typeof (window as unknown as { require?: unknown }).require === 'function';
  }

  async save(_project: ProjectFileV1, _filename?: string): Promise<void> {
    // Future: Use Electron's dialog.showSaveDialog and fs.writeFile
    throw new Error('Electron storage not yet implemented. Use browser storage.');
  }

  async load(): Promise<ProjectFileV1 | null> {
    // Future: Use Electron's dialog.showOpenDialog and fs.readFile
    throw new Error('Electron storage not yet implemented. Use browser storage.');
  }
}

/**
 * Create the appropriate project storage for the current environment.
 */
export function createProjectStorage(): IProjectStorage {
  // For now, always use browser storage
  // Future: detect Electron and use ElectronProjectStorage
  return new BrowserProjectStorage();
}

/**
 * Load external routes from a URL (for embed=false mode).
 */
export async function loadExternalRoutes(routesPath: string): Promise<{
  success: boolean;
  data?: unknown;
  error?: string;
}> {
  try {
    const response = await fetch(routesPath);
    if (!response.ok) {
      return {
        success: false,
        error: `Failed to load routes: ${response.status} ${response.statusText}`,
      };
    }

    const data = await response.json();
    return { success: true, data };
  } catch (err) {
    return {
      success: false,
      error: `Failed to load routes: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/**
 * Save external routes to a file (browser download).
 * Used when embed=false and routes have been modified.
 */
export function saveExternalRoutes(routes: unknown, filename: string): void {
  const json = JSON.stringify(routes, null, 2) + '\n';
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);

  URL.revokeObjectURL(url);
}

/**
 * Load manifest assets from a URL.
 */
export async function loadManifestAssets(manifestPath: string): Promise<{
  success: boolean;
  assetIds?: Set<string>;
  error?: string;
}> {
  try {
    const response = await fetch(manifestPath);
    if (!response.ok) {
      return {
        success: false,
        error: `Failed to load manifest: ${response.status} ${response.statusText}`,
      };
    }

    const manifest = await response.json();
    if (!manifest.assets || !Array.isArray(manifest.assets)) {
      return {
        success: false,
        error: 'Invalid manifest: missing assets array',
      };
    }

    const assetIds = new Set<string>(
      manifest.assets.map((a: { id: string }) => a.id)
    );

    return { success: true, assetIds };
  } catch (err) {
    return {
      success: false,
      error: `Failed to load manifest: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

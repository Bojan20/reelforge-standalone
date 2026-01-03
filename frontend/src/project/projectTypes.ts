/**
 * ReelForge M8.1 Project Types
 *
 * Defines the project file schema (v1).
 * The project file is the single source of truth for Studio state.
 */

import type { RoutesConfig } from '../core/routesTypes';
import type { MasterInsertChain, InsertChain } from '../core/masterInsertTypes';
import { EMPTY_INSERT_CHAIN } from '../core/masterInsertTypes';
import type { BusId } from '../core/types';

/**
 * Project file paths configuration.
 */
export interface ProjectPaths {
  /** Path to runtime_manifest.json (required) */
  manifestPath: string;
  /** Path to runtime_routes.json (required if embed=false) */
  routesPath?: string;
}

/**
 * Routes configuration in project.
 */
export interface ProjectRoutes {
  /** If true, routes are embedded in project file. If false, loaded from routesPath. */
  embed: boolean;
  /** Embedded routes data (required if embed=true) */
  data?: RoutesConfig;
}

/**
 * Routes editor UI state.
 */
export interface RoutesUiState {
  /** Currently selected event name */
  selectedEventName?: string;
  /** Search query in event list */
  searchQuery?: string;
}

/**
 * Bus IDs that support insert chains (all except 'master').
 * Master bus uses masterInsertChain instead.
 */
export type InsertableBusId = Exclude<BusId, 'master'>;

/**
 * Asset ID type for asset insert chains.
 * Must match an asset ID from the manifest.
 */
export type AssetId = string;

/**
 * Studio UI preferences.
 */
export interface StudioPreferences {
  /** Selected tab in Engine view */
  selectedTab?: 'Monitor' | 'Routes';
  /** Routes editor UI state */
  routesUi?: RoutesUiState;
  /** Master bus insert chain (Studio preview only) */
  masterInsertChain?: MasterInsertChain;
  /**
   * Preview Delay Compensation enabled for Master (Studio preview only).
   * When ON, adds delay to compensate for master insert chain latency.
   * Default: false (OFF) for backwards compatibility.
   */
  pdcEnabled?: boolean;
  /**
   * Per-bus insert chains (Studio preview only).
   * Signal path: Bus Gain → [BUS INSERT CHAIN] → [BUS PDC] → Ducking → Master Gain
   * Keys are bus IDs (music, sfx, ambience, voice - NOT master).
   */
  busInsertChains?: Partial<Record<InsertableBusId, InsertChain>>;
  /**
   * Per-bus Preview Delay Compensation enabled (Studio preview only).
   * When ON for a bus, adds DelayNode to compensate for that bus's insert chain latency.
   * Signal path: Bus Inserts → [BUS PDC Delay] → Duck Gain → Master
   * Default: all OFF for backwards compatibility.
   * Note: SFX/Voice should typically stay OFF for tight responsive feel.
   */
  busPdcEnabled?: Partial<Record<InsertableBusId, boolean>>;
  /**
   * Per-asset insert chains (Studio preview only).
   * Keyed by asset ID from manifest. Each asset can have its own insert chain.
   * Signal path: Source → [ASSET INSERTS] → Action Gain → Bus Gain → [BUS INSERTS]
   * Each voice/channel that plays the asset gets its own DSP chain instance.
   */
  assetInsertChains?: Record<AssetId, InsertChain>;
}

/**
 * Project file v1 schema.
 */
export interface ProjectFileV1 {
  /** Schema version (must be 1) */
  projectVersion: 1;
  /** Project name */
  name: string;
  /** Creation timestamp (ISO 8601) */
  createdAt: string;
  /** Last update timestamp (ISO 8601) */
  updatedAt: string;
  /** File paths */
  paths: ProjectPaths;
  /** Routes configuration */
  routes: ProjectRoutes;
  /** Studio preferences (optional) */
  studio?: StudioPreferences;
}

/**
 * Union of all project file versions (for migration support).
 */
export type ProjectFile = ProjectFileV1;

/**
 * Current project version.
 */
export const CURRENT_PROJECT_VERSION = 1;

/**
 * Default studio preferences.
 */
export const DEFAULT_STUDIO_PREFERENCES: StudioPreferences = {
  selectedTab: 'Monitor',
  routesUi: {
    selectedEventName: undefined,
    searchQuery: '',
  },
  masterInsertChain: EMPTY_INSERT_CHAIN,
  pdcEnabled: false, // OFF by default for backwards compatibility
};

/**
 * Create a new empty project with defaults.
 */
export function createEmptyProject(name: string, manifestPath: string): ProjectFileV1 {
  const now = new Date().toISOString();
  return {
    projectVersion: 1,
    name,
    createdAt: now,
    updatedAt: now,
    paths: {
      manifestPath,
    },
    routes: {
      embed: true,
      data: {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [],
      },
    },
    studio: { ...DEFAULT_STUDIO_PREFERENCES },
  };
}

/**
 * Create a default project using demo paths.
 * Used when no project is loaded.
 */
export function createDefaultProject(): ProjectFileV1 {
  const now = new Date().toISOString();
  return {
    projectVersion: 1,
    name: 'Untitled Project',
    createdAt: now,
    updatedAt: now,
    paths: {
      manifestPath: 'public/demo/runtime_manifest.json',
    },
    routes: {
      embed: true,
      data: {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [],
      },
    },
    studio: { ...DEFAULT_STUDIO_PREFERENCES },
  };
}

/**
 * Validation error for project files.
 */
export interface ProjectValidationError {
  type: 'error' | 'warning';
  message: string;
  field?: string;
}

/**
 * Validation result for project files.
 */
export interface ProjectValidationResult {
  valid: boolean;
  errors: ProjectValidationError[];
  warnings: ProjectValidationError[];
}

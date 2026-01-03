/**
 * ReelForge M7.0 Project Context
 *
 * React context providing project state as the single source of truth.
 * Manages project loading, saving, and routes synchronization.
 */

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useMemo,
  type ReactNode,
} from 'react';
import type { ProjectFileV1, StudioPreferences, RoutesUiState } from './projectTypes';
import { createDefaultProject, DEFAULT_STUDIO_PREFERENCES } from './projectTypes';
import type { RoutesConfig } from '../core/routesTypes';
import { validateRoutes } from '../core/validateRoutes';
import { AssetIndex } from '../core/assetIndex';
import {
  createProjectStorage,
  stringifyProject,
  loadExternalRoutes,
  loadManifestAssets,
  saveExternalRoutes,
} from './projectStorage';

/**
 * Project context state.
 */
export interface ProjectState {
  /** Current project */
  project: ProjectFileV1;
  /** Working copy of routes (may differ from saved) */
  workingRoutes: RoutesConfig | null;
  /** Asset IDs from manifest */
  assetIds: Set<string> | null;
  /** Asset index for AssetPicker */
  assetIndex: AssetIndex | null;
  /** Is the project modified since last save? */
  isDirty: boolean;
  /** Is the project currently loading? */
  isLoading: boolean;
  /** Error message if any */
  error: string | null;
  /** Last saved project JSON (for dirty detection) */
  lastSavedJson: string | null;
}

/**
 * Project context actions.
 */
export interface ProjectActions {
  /** Create a new empty project */
  newProject: (name: string, manifestPath: string) => Promise<void>;
  /** Open a project from file picker */
  openProject: () => Promise<boolean>;
  /** Save the current project */
  saveProject: (filename?: string) => Promise<void>;
  /** Save the current project with a new name */
  saveProjectAs: () => Promise<void>;
  /** Update project name */
  setProjectName: (name: string) => void;
  /** Update studio preferences */
  setStudioPreferences: (prefs: Partial<StudioPreferences>) => void;
  /** Update routes UI state */
  setRoutesUiState: (state: Partial<RoutesUiState>) => void;
  /** Update working routes (marks project dirty) */
  setWorkingRoutes: (routes: RoutesConfig) => void;
  /** Reload routes from external file (for embed=false) */
  reloadExternalRoutes: () => Promise<void>;
  /** Convert external routes to embedded */
  embedRoutes: () => void;
  /** Mark project as saved (clears dirty flag) */
  markSaved: () => void;
  /** Get routes config to use (embedded or external) */
  getRoutesConfig: () => RoutesConfig | null;
  /** Check if using embedded routes */
  isEmbedded: () => boolean;
}

/**
 * Full project context.
 */
export interface ProjectContextValue extends ProjectState, ProjectActions {}

const ProjectContext = createContext<ProjectContextValue | null>(null);

/**
 * Project context provider props.
 */
interface ProjectProviderProps {
  children: ReactNode;
}

/**
 * Project context provider.
 */
export function ProjectProvider({ children }: ProjectProviderProps) {
  // Storage instance
  const storage = useMemo(() => createProjectStorage(), []);

  // Core state
  const [project, setProject] = useState<ProjectFileV1>(createDefaultProject());
  const [workingRoutes, setWorkingRoutesInternal] = useState<RoutesConfig | null>(null);
  const [assetIds, setAssetIds] = useState<Set<string> | null>(null);
  const [assetIndex, setAssetIndex] = useState<AssetIndex | null>(null);
  const [isDirty, setIsDirty] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastSavedJson, setLastSavedJson] = useState<string | null>(null);

  /**
   * Load manifest assets for the current project.
   */
  const loadManifest = useCallback(async (manifestPath: string) => {
    const result = await loadManifestAssets(manifestPath);
    if (result.success && result.assetIds) {
      setAssetIds(result.assetIds);
      setAssetIndex(new AssetIndex(
        Array.from(result.assetIds).map((id) => ({ id }))
      ));
    } else {
      console.warn('[ProjectContext] Failed to load manifest:', result.error);
      setAssetIds(new Set());
      setAssetIndex(new AssetIndex([]));
    }
  }, []);

  /**
   * Load routes (embedded or external).
   */
  const loadRoutes = useCallback(async (proj: ProjectFileV1) => {
    if (proj.routes.embed && proj.routes.data) {
      setWorkingRoutesInternal(proj.routes.data);
    } else if (!proj.routes.embed && proj.paths.routesPath) {
      const result = await loadExternalRoutes(proj.paths.routesPath);
      if (result.success && result.data) {
        setWorkingRoutesInternal(result.data as RoutesConfig);
      } else {
        console.error('[ProjectContext] Failed to load external routes:', result.error);
        setError(result.error || 'Failed to load routes');
        setWorkingRoutesInternal(null);
      }
    } else {
      setWorkingRoutesInternal(null);
    }
  }, []);

  /**
   * Initialize with default project.
   */
  useEffect(() => {
    const initDefault = async () => {
      setIsLoading(true);
      setError(null);

      const defaultProj = createDefaultProject();

      // Load manifest
      await loadManifest(defaultProj.paths.manifestPath);

      // Load routes
      await loadRoutes(defaultProj);

      setProject(defaultProj);
      setLastSavedJson(null); // Never saved
      setIsDirty(false);
      setIsLoading(false);
    };

    initDefault();
  }, [loadManifest, loadRoutes]);

  /**
   * Create a new empty project.
   */
  const newProject = useCallback(async (name: string, manifestPath: string) => {
    setIsLoading(true);
    setError(null);

    const now = new Date().toISOString();
    const newProj: ProjectFileV1 = {
      projectVersion: 1,
      name,
      createdAt: now,
      updatedAt: now,
      paths: { manifestPath },
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

    await loadManifest(manifestPath);
    await loadRoutes(newProj);

    setProject(newProj);
    setLastSavedJson(null);
    setIsDirty(true);
    setIsLoading(false);
  }, [loadManifest, loadRoutes]);

  /**
   * Open a project from file picker.
   */
  const openProject = useCallback(async (): Promise<boolean> => {
    setIsLoading(true);
    setError(null);

    try {
      const loaded = await storage.load();
      if (!loaded) {
        setIsLoading(false);
        return false;
      }

      await loadManifest(loaded.paths.manifestPath);
      await loadRoutes(loaded);

      setProject(loaded);
      setLastSavedJson(stringifyProject(loaded));
      setIsDirty(false);
      setIsLoading(false);

      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setIsLoading(false);
      return false;
    }
  }, [storage, loadManifest, loadRoutes]);

  /**
   * Save the current project.
   *
   * - Embedded mode: saves project file with routes.data
   * - External mode: saves project file AND downloads routes to routesPath filename
   */
  const saveProject = useCallback(async (filename?: string) => {
    // Build project with current working routes if embedded
    const projectToSave: ProjectFileV1 = {
      ...project,
      updatedAt: new Date().toISOString(),
    };

    if (project.routes.embed && workingRoutes) {
      // Embedded: include routes data in project file
      projectToSave.routes = {
        embed: true,
        data: workingRoutes,
      };
    } else if (!project.routes.embed && workingRoutes && project.paths.routesPath) {
      // External: save routes to separate file (browser download)
      const routesFilename = project.paths.routesPath.split('/').pop() || 'runtime_routes.json';
      saveExternalRoutes(workingRoutes, routesFilename);
    }

    await storage.save(projectToSave, filename);

    // Update state
    setProject(projectToSave);
    setLastSavedJson(stringifyProject(projectToSave));
    setIsDirty(false);
  }, [project, workingRoutes, storage]);

  /**
   * Save with a new name (Save As).
   */
  const saveProjectAs = useCallback(async () => {
    const newName = prompt('Enter project name:', project.name);
    if (!newName) return;

    const projectToSave: ProjectFileV1 = {
      ...project,
      name: newName,
      updatedAt: new Date().toISOString(),
    };

    if (project.routes.embed && workingRoutes) {
      // Embedded: include routes data in project file
      projectToSave.routes = {
        embed: true,
        data: workingRoutes,
      };
    } else if (!project.routes.embed && workingRoutes && project.paths.routesPath) {
      // External: save routes to separate file (browser download)
      const routesFilename = project.paths.routesPath.split('/').pop() || 'runtime_routes.json';
      saveExternalRoutes(workingRoutes, routesFilename);
    }

    const filename = `${newName.replace(/[^a-zA-Z0-9_-]/g, '_')}_project.json`;
    await storage.save(projectToSave, filename);

    setProject(projectToSave);
    setLastSavedJson(stringifyProject(projectToSave));
    setIsDirty(false);
  }, [project, workingRoutes, storage]);

  /**
   * Update project name.
   */
  const setProjectName = useCallback((name: string) => {
    setProject((prev) => ({ ...prev, name }));
    setIsDirty(true);
  }, []);

  /**
   * Update studio preferences.
   */
  const setStudioPreferences = useCallback((prefs: Partial<StudioPreferences>) => {
    setProject((prev) => ({
      ...prev,
      studio: {
        ...DEFAULT_STUDIO_PREFERENCES,
        ...prev.studio,
        ...prefs,
      },
    }));
    // Studio preferences changes don't mark dirty (UI state only)
  }, []);

  /**
   * Update routes UI state.
   */
  const setRoutesUiState = useCallback((state: Partial<RoutesUiState>) => {
    setProject((prev) => ({
      ...prev,
      studio: {
        ...DEFAULT_STUDIO_PREFERENCES,
        ...prev.studio,
        routesUi: {
          ...prev.studio?.routesUi,
          ...state,
        },
      },
    }));
    // UI state changes don't mark dirty
  }, []);

  /**
   * Update working routes.
   */
  const setWorkingRoutes = useCallback((routes: RoutesConfig) => {
    setWorkingRoutesInternal(routes);
    setIsDirty(true);
  }, []);

  /**
   * Reload external routes.
   */
  const reloadExternalRoutes = useCallback(async () => {
    if (project.routes.embed || !project.paths.routesPath) {
      return;
    }

    setIsLoading(true);
    const result = await loadExternalRoutes(project.paths.routesPath);
    if (result.success && result.data) {
      setWorkingRoutesInternal(result.data as RoutesConfig);
      setError(null);
    } else {
      setError(result.error || 'Failed to reload routes');
    }
    setIsLoading(false);
  }, [project]);

  /**
   * Convert external routes to embedded.
   */
  const embedRoutes = useCallback(() => {
    if (!workingRoutes) return;

    setProject((prev) => ({
      ...prev,
      routes: {
        embed: true,
        data: workingRoutes,
      },
    }));
    setIsDirty(true);
  }, [workingRoutes]);

  /**
   * Mark as saved (used after native core reload).
   */
  const markSaved = useCallback(() => {
    setIsDirty(false);
  }, []);

  /**
   * Get the current routes config.
   */
  const getRoutesConfig = useCallback((): RoutesConfig | null => {
    return workingRoutes;
  }, [workingRoutes]);

  /**
   * Check if using embedded routes.
   */
  const isEmbedded = useCallback((): boolean => {
    return project.routes.embed;
  }, [project.routes.embed]);

  // Build context value
  const value: ProjectContextValue = {
    // State
    project,
    workingRoutes,
    assetIds,
    assetIndex,
    isDirty,
    isLoading,
    error,
    lastSavedJson,
    // Actions
    newProject,
    openProject,
    saveProject,
    saveProjectAs,
    setProjectName,
    setStudioPreferences,
    setRoutesUiState,
    setWorkingRoutes,
    reloadExternalRoutes,
    embedRoutes,
    markSaved,
    getRoutesConfig,
    isEmbedded,
  };

  return (
    <ProjectContext.Provider value={value}>
      {children}
    </ProjectContext.Provider>
  );
}

/**
 * Hook to use project context.
 */
export function useProject(): ProjectContextValue {
  const context = useContext(ProjectContext);
  if (!context) {
    throw new Error('useProject must be used within a ProjectProvider');
  }
  return context;
}

/**
 * Hook to get routes with validation.
 */
export function useProjectRoutes() {
  const { workingRoutes, assetIds } = useProject();

  const validation = useMemo(() => {
    if (!workingRoutes) {
      return { valid: false, errors: [], warnings: [] };
    }
    return validateRoutes(workingRoutes, assetIds ?? undefined);
  }, [workingRoutes, assetIds]);

  return { routes: workingRoutes, validation };
}

/**
 * Project Save/Load System
 *
 * Provides project persistence:
 * - Export project as JSON
 * - Import existing projects
 * - Recent projects list
 * - Auto-save with recovery
 * - Version migration
 *
 * @module core/projectPersistence
 */

// ============ TYPES ============

export interface ProjectMetadata {
  id: string;
  name: string;
  version: string;
  createdAt: string;
  updatedAt: string;
  author?: string;
  description?: string;
}

export interface ProjectData {
  metadata: ProjectMetadata;
  events: unknown[];
  buses: unknown[];
  audioFiles: Array<{ id: string; name: string; path?: string }>;
  settings: Record<string, unknown>;
  customData?: Record<string, unknown>;
}

export interface RecentProject {
  id: string;
  name: string;
  path?: string;
  lastOpened: string;
  thumbnail?: string;
}

export interface AutoSaveEntry {
  projectId: string;
  timestamp: string;
  data: string;
}

const CURRENT_VERSION = '1.0.0';
const STORAGE_KEYS = {
  recentProjects: 'reelforge-recent-projects',
  autoSave: 'reelforge-autosave',
  settings: 'reelforge-settings',
};

// ============ PROJECT PERSISTENCE MANAGER ============

class ProjectPersistenceClass {
  private autoSaveInterval: number | null = null;
  private currentProject: ProjectData | null = null;
  private isDirty: boolean = false;

  // ============ SAVE ============

  /**
   * Save project to JSON string
   */
  serialize(project: ProjectData): string {
    const projectToSave = {
      ...project,
      metadata: {
        ...project.metadata,
        version: CURRENT_VERSION,
        updatedAt: new Date().toISOString(),
      },
    };

    return JSON.stringify(projectToSave, null, 2);
  }

  /**
   * Save project to file download
   */
  saveToFile(project: ProjectData, filename?: string): void {
    const json = this.serialize(project);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = filename || `${project.metadata.name}.reelforge.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    this.markClean();
    this.addToRecentProjects({
      id: project.metadata.id,
      name: project.metadata.name,
      lastOpened: new Date().toISOString(),
    });
  }

  /**
   * Save project to localStorage (for web-only use)
   */
  saveToLocalStorage(project: ProjectData): void {
    const json = this.serialize(project);
    localStorage.setItem(`reelforge-project-${project.metadata.id}`, json);
    this.markClean();
  }

  // ============ LOAD ============

  /**
   * Parse project from JSON string
   */
  deserialize(json: string): ProjectData {
    const data = JSON.parse(json);

    // Validate structure
    if (!data.metadata?.id || !data.metadata?.name) {
      throw new Error('Invalid project file: missing metadata');
    }

    // Migrate if needed
    const migrated = this.migrate(data);

    return migrated;
  }

  /**
   * Load project from file
   */
  async loadFromFile(file: File): Promise<ProjectData> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();

      reader.onload = (e) => {
        try {
          const json = e.target?.result as string;
          const project = this.deserialize(json);
          this.currentProject = project;
          this.markClean();

          this.addToRecentProjects({
            id: project.metadata.id,
            name: project.metadata.name,
            lastOpened: new Date().toISOString(),
          });

          resolve(project);
        } catch (error) {
          reject(error);
        }
      };

      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsText(file);
    });
  }

  /**
   * Load project from localStorage
   */
  loadFromLocalStorage(projectId: string): ProjectData | null {
    const json = localStorage.getItem(`reelforge-project-${projectId}`);
    if (!json) return null;

    try {
      const project = this.deserialize(json);
      this.currentProject = project;
      this.markClean();
      return project;
    } catch {
      return null;
    }
  }

  // ============ MIGRATION ============

  /**
   * Migrate old project versions
   */
  private migrate(data: ProjectData): ProjectData {
    // Placeholder for future version migrations
    // Example: if (data.metadata.version < '2.0.0') { migrateTo2(data); }
    data.metadata.version = CURRENT_VERSION;
    return data;
  }

  // ============ RECENT PROJECTS ============

  /**
   * Get recent projects list
   */
  getRecentProjects(): RecentProject[] {
    try {
      const json = localStorage.getItem(STORAGE_KEYS.recentProjects);
      return json ? JSON.parse(json) : [];
    } catch {
      return [];
    }
  }

  /**
   * Add project to recent list
   */
  addToRecentProjects(project: RecentProject): void {
    const recent = this.getRecentProjects();

    // Remove if already exists
    const filtered = recent.filter(p => p.id !== project.id);

    // Add to front
    filtered.unshift(project);

    // Keep only last 10
    const trimmed = filtered.slice(0, 10);

    localStorage.setItem(STORAGE_KEYS.recentProjects, JSON.stringify(trimmed));
  }

  /**
   * Remove from recent projects
   */
  removeFromRecentProjects(projectId: string): void {
    const recent = this.getRecentProjects();
    const filtered = recent.filter(p => p.id !== projectId);
    localStorage.setItem(STORAGE_KEYS.recentProjects, JSON.stringify(filtered));
  }

  /**
   * Clear recent projects
   */
  clearRecentProjects(): void {
    localStorage.removeItem(STORAGE_KEYS.recentProjects);
  }

  // ============ AUTO-SAVE ============

  /**
   * Start auto-save (every 30 seconds by default)
   */
  startAutoSave(getProjectData: () => ProjectData, intervalMs: number = 30000): void {
    this.stopAutoSave();

    this.autoSaveInterval = window.setInterval(() => {
      if (this.isDirty) {
        const project = getProjectData();
        this.saveAutoSave(project);
      }
    }, intervalMs);
  }

  /**
   * Stop auto-save
   */
  stopAutoSave(): void {
    if (this.autoSaveInterval !== null) {
      clearInterval(this.autoSaveInterval);
      this.autoSaveInterval = null;
    }
  }

  /**
   * Save auto-save entry
   */
  private saveAutoSave(project: ProjectData): void {
    const entry: AutoSaveEntry = {
      projectId: project.metadata.id,
      timestamp: new Date().toISOString(),
      data: this.serialize(project),
    };

    // Keep only the latest auto-save per project
    const saves = this.getAutoSaves().filter(s => s.projectId !== project.metadata.id);
    saves.push(entry);

    // Keep max 5 auto-saves
    const trimmed = saves.slice(-5);

    localStorage.setItem(STORAGE_KEYS.autoSave, JSON.stringify(trimmed));
  }

  /**
   * Get all auto-saves
   */
  getAutoSaves(): AutoSaveEntry[] {
    try {
      const json = localStorage.getItem(STORAGE_KEYS.autoSave);
      return json ? JSON.parse(json) : [];
    } catch {
      return [];
    }
  }

  /**
   * Get auto-save for a project
   */
  getAutoSaveForProject(projectId: string): AutoSaveEntry | null {
    const saves = this.getAutoSaves();
    return saves.find(s => s.projectId === projectId) || null;
  }

  /**
   * Recover from auto-save
   */
  recoverFromAutoSave(projectId: string): ProjectData | null {
    const save = this.getAutoSaveForProject(projectId);
    if (!save) return null;

    try {
      return this.deserialize(save.data);
    } catch {
      return null;
    }
  }

  /**
   * Clear auto-save for project
   */
  clearAutoSave(projectId: string): void {
    const saves = this.getAutoSaves().filter(s => s.projectId !== projectId);
    localStorage.setItem(STORAGE_KEYS.autoSave, JSON.stringify(saves));
  }

  /**
   * Clear all auto-saves
   */
  clearAllAutoSaves(): void {
    localStorage.removeItem(STORAGE_KEYS.autoSave);
  }

  // ============ DIRTY STATE ============

  /**
   * Mark project as dirty (has unsaved changes)
   */
  markDirty(): void {
    this.isDirty = true;
  }

  /**
   * Mark project as clean (saved)
   */
  markClean(): void {
    this.isDirty = false;
  }

  /**
   * Check if project has unsaved changes
   */
  hasDirtyChanges(): boolean {
    return this.isDirty;
  }

  // ============ NEW PROJECT ============

  /**
   * Create a new project
   */
  createNewProject(name: string, author?: string): ProjectData {
    const project: ProjectData = {
      metadata: {
        id: `proj-${Date.now()}-${Math.random().toString(36).slice(2)}`,
        name,
        version: CURRENT_VERSION,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        author,
      },
      events: [],
      buses: [
        { id: 'master', name: 'Master', volume: 1, muted: false },
        { id: 'sfx', name: 'SFX', volume: 1, muted: false },
        { id: 'music', name: 'Music', volume: 0.8, muted: false },
        { id: 'voice', name: 'Voice', volume: 1, muted: false },
        { id: 'ambience', name: 'Ambience', volume: 0.6, muted: false },
      ],
      audioFiles: [],
      settings: {
        sampleRate: 44100,
        defaultVolume: 1,
      },
    };

    this.currentProject = project;
    this.markDirty();

    return project;
  }

  /**
   * Get current project
   */
  getCurrentProject(): ProjectData | null {
    return this.currentProject;
  }

  /**
   * Set current project
   */
  setCurrentProject(project: ProjectData): void {
    this.currentProject = project;
  }

  // ============ EXPORT/IMPORT ============

  /**
   * Export project as different formats
   */
  exportAs(project: ProjectData, format: 'json' | 'minimal'): string {
    switch (format) {
      case 'minimal':
        return JSON.stringify({
          name: project.metadata.name,
          events: project.events,
          buses: project.buses,
        });
      case 'json':
      default:
        return this.serialize(project);
    }
  }

  /**
   * Import events from another project
   */
  importEvents(targetProject: ProjectData, sourceJson: string): ProjectData {
    const source = this.deserialize(sourceJson);

    return {
      ...targetProject,
      events: [...targetProject.events, ...source.events],
      metadata: {
        ...targetProject.metadata,
        updatedAt: new Date().toISOString(),
      },
    };
  }

  /**
   * Import audio file references
   */
  importAudioFiles(
    targetProject: ProjectData,
    files: Array<{ id: string; name: string; path?: string }>
  ): ProjectData {
    return {
      ...targetProject,
      audioFiles: [...targetProject.audioFiles, ...files],
      metadata: {
        ...targetProject.metadata,
        updatedAt: new Date().toISOString(),
      },
    };
  }
}

// ============ SINGLETON EXPORT ============

export const ProjectPersistence = new ProjectPersistenceClass();

// ============ REACT HOOK ============

import { useState, useEffect, useCallback } from 'react';

export interface UseProjectReturn {
  project: ProjectData | null;
  isDirty: boolean;
  recentProjects: RecentProject[];
  save: () => void;
  saveAs: (filename?: string) => void;
  load: (file: File) => Promise<void>;
  newProject: (name: string, author?: string) => void;
  markDirty: () => void;
  hasAutoSave: () => boolean;
  recoverAutoSave: () => void;
}

export function useProject(): UseProjectReturn {
  const [project, setProject] = useState<ProjectData | null>(
    ProjectPersistence.getCurrentProject()
  );
  const [isDirty, setIsDirty] = useState(ProjectPersistence.hasDirtyChanges());
  const [recentProjects, setRecentProjects] = useState<RecentProject[]>(
    ProjectPersistence.getRecentProjects()
  );

  // Start auto-save
  useEffect(() => {
    if (project) {
      ProjectPersistence.startAutoSave(() => project);
    }
    return () => ProjectPersistence.stopAutoSave();
  }, [project]);

  const save = useCallback(() => {
    if (project) {
      ProjectPersistence.saveToLocalStorage(project);
      setIsDirty(false);
    }
  }, [project]);

  const saveAs = useCallback((filename?: string) => {
    if (project) {
      ProjectPersistence.saveToFile(project, filename);
      setIsDirty(false);
    }
  }, [project]);

  const load = useCallback(async (file: File) => {
    const loaded = await ProjectPersistence.loadFromFile(file);
    setProject(loaded);
    setIsDirty(false);
    setRecentProjects(ProjectPersistence.getRecentProjects());
  }, []);

  const newProject = useCallback((name: string, author?: string) => {
    const created = ProjectPersistence.createNewProject(name, author);
    setProject(created);
    setIsDirty(true);
  }, []);

  const markDirty = useCallback(() => {
    ProjectPersistence.markDirty();
    setIsDirty(true);
  }, []);

  const hasAutoSave = useCallback(() => {
    return project ? !!ProjectPersistence.getAutoSaveForProject(project.metadata.id) : false;
  }, [project]);

  const recoverAutoSave = useCallback(() => {
    if (project) {
      const recovered = ProjectPersistence.recoverFromAutoSave(project.metadata.id);
      if (recovered) {
        setProject(recovered);
        ProjectPersistence.setCurrentProject(recovered);
      }
    }
  }, [project]);

  return {
    project,
    isDirty,
    recentProjects,
    save,
    saveAs,
    load,
    newProject,
    markDirty,
    hasAutoSave,
    recoverAutoSave,
  };
}

// ============ BEFOREUNLOAD HANDLER ============

if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', (e) => {
    if (ProjectPersistence.hasDirtyChanges()) {
      e.preventDefault();
      e.returnValue = 'You have unsaved changes. Are you sure you want to leave?';
      return e.returnValue;
    }
  });
}

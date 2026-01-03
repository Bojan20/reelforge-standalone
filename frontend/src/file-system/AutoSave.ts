/**
 * ReelForge Auto-Save System
 *
 * Automatic project saving with:
 * - Configurable interval
 * - IndexedDB persistence
 * - Recovery on crash
 * - Multiple snapshots
 *
 * @module file-system/AutoSave
 */

// ============ Types ============

export interface AutoSaveEntry {
  id: string;
  projectName: string;
  timestamp: number;
  data: string; // JSON stringified project
  size: number;
}

export interface AutoSaveConfig {
  enabled: boolean;
  intervalMs: number; // Default: 60000 (1 min)
  maxSnapshots: number; // Default: 5
  compressData: boolean;
}

export interface RecoveryInfo {
  hasRecovery: boolean;
  entries: AutoSaveEntry[];
  newestEntry?: AutoSaveEntry;
}

type AutoSaveListener = (entry: AutoSaveEntry) => void;

// ============ IndexedDB Setup ============

const DB_NAME = 'reelforge-autosave';
const DB_VERSION = 1;
const STORE_NAME = 'snapshots';

async function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;

      if (!db.objectStoreNames.contains(STORE_NAME)) {
        const store = db.createObjectStore(STORE_NAME, { keyPath: 'id' });
        store.createIndex('timestamp', 'timestamp', { unique: false });
        store.createIndex('projectName', 'projectName', { unique: false });
      }
    };
  });
}

// ============ Auto-Save Manager Class ============

class AutoSaveManagerClass {
  private config: AutoSaveConfig = {
    enabled: true,
    intervalMs: 60000,
    maxSnapshots: 5,
    compressData: false,
  };

  private intervalId: number | null = null;
  private isDirty = false;
  private currentProjectName = 'Untitled';
  private getProjectData: (() => string) | null = null;
  private listeners = new Set<AutoSaveListener>();

  /**
   * Initialize auto-save with project data getter.
   */
  initialize(
    getProjectData: () => string,
    config?: Partial<AutoSaveConfig>
  ): void {
    this.getProjectData = getProjectData;

    if (config) {
      this.config = { ...this.config, ...config };
    }

    if (this.config.enabled) {
      this.start();
    }

    // Listen for beforeunload to save on close
    window.addEventListener('beforeunload', this.handleBeforeUnload);
  }

  /**
   * Start auto-save interval.
   */
  start(): void {
    if (this.intervalId !== null) return;

    this.intervalId = window.setInterval(() => {
      if (this.isDirty) {
        this.save();
      }
    }, this.config.intervalMs);
  }

  /**
   * Stop auto-save interval.
   */
  stop(): void {
    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /**
   * Mark project as dirty (needs save).
   */
  markDirty(): void {
    this.isDirty = true;
  }

  /**
   * Mark project as clean (just saved).
   */
  markClean(): void {
    this.isDirty = false;
  }

  /**
   * Set current project name.
   */
  setProjectName(name: string): void {
    this.currentProjectName = name;
  }

  /**
   * Update config.
   */
  setConfig(config: Partial<AutoSaveConfig>): void {
    this.config = { ...this.config, ...config };

    // Restart interval if changed
    if (config.intervalMs !== undefined || config.enabled !== undefined) {
      this.stop();
      if (this.config.enabled) {
        this.start();
      }
    }
  }

  /**
   * Save current project state.
   */
  async save(): Promise<AutoSaveEntry | null> {
    if (!this.getProjectData) return null;

    try {
      const data = this.getProjectData();
      const entry: AutoSaveEntry = {
        id: `autosave_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        projectName: this.currentProjectName,
        timestamp: Date.now(),
        data,
        size: data.length,
      };

      // Save to IndexedDB
      const db = await openDatabase();
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);

      await new Promise<void>((resolve, reject) => {
        const request = store.add(entry);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });

      // Cleanup old snapshots
      await this.cleanupOldSnapshots();

      this.isDirty = false;

      // Notify listeners
      this.listeners.forEach(fn => fn(entry));

      return entry;
    } catch (err) {
      console.error('Auto-save failed:', err);
      return null;
    }
  }

  /**
   * Force immediate save.
   */
  async forceSave(): Promise<AutoSaveEntry | null> {
    this.isDirty = true;
    return this.save();
  }

  /**
   * Get all auto-save entries.
   */
  async getEntries(): Promise<AutoSaveEntry[]> {
    try {
      const db = await openDatabase();
      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);
      const index = store.index('timestamp');

      return new Promise((resolve, reject) => {
        const request = index.openCursor(null, 'prev');
        const entries: AutoSaveEntry[] = [];

        request.onsuccess = (event) => {
          const cursor = (event.target as IDBRequest<IDBCursorWithValue>).result;
          if (cursor) {
            entries.push(cursor.value);
            cursor.continue();
          } else {
            resolve(entries);
          }
        };

        request.onerror = () => reject(request.error);
      });
    } catch {
      return [];
    }
  }

  /**
   * Get entries for specific project.
   */
  async getEntriesForProject(projectName: string): Promise<AutoSaveEntry[]> {
    const entries = await this.getEntries();
    return entries.filter(e => e.projectName === projectName);
  }

  /**
   * Get recovery info.
   */
  async getRecoveryInfo(): Promise<RecoveryInfo> {
    const entries = await this.getEntries();

    if (entries.length === 0) {
      return { hasRecovery: false, entries: [] };
    }

    return {
      hasRecovery: true,
      entries,
      newestEntry: entries[0],
    };
  }

  /**
   * Load entry by ID.
   */
  async loadEntry(id: string): Promise<AutoSaveEntry | null> {
    try {
      const db = await openDatabase();
      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);

      return new Promise((resolve, reject) => {
        const request = store.get(id);
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(request.error);
      });
    } catch {
      return null;
    }
  }

  /**
   * Delete entry by ID.
   */
  async deleteEntry(id: string): Promise<void> {
    try {
      const db = await openDatabase();
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);

      await new Promise<void>((resolve, reject) => {
        const request = store.delete(id);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });
    } catch (err) {
      console.error('Failed to delete auto-save entry:', err);
    }
  }

  /**
   * Clear all auto-save entries.
   */
  async clearAll(): Promise<void> {
    try {
      const db = await openDatabase();
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);

      await new Promise<void>((resolve, reject) => {
        const request = store.clear();
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });
    } catch (err) {
      console.error('Failed to clear auto-save:', err);
    }
  }

  /**
   * Cleanup old snapshots beyond maxSnapshots.
   */
  private async cleanupOldSnapshots(): Promise<void> {
    const entries = await this.getEntries();

    if (entries.length <= this.config.maxSnapshots) return;

    // Delete oldest entries
    const toDelete = entries.slice(this.config.maxSnapshots);

    for (const entry of toDelete) {
      await this.deleteEntry(entry.id);
    }
  }

  /**
   * Handle page unload.
   */
  private handleBeforeUnload = (): void => {
    if (this.isDirty && this.getProjectData) {
      // Try to save synchronously to localStorage as backup
      try {
        const data = this.getProjectData();
        localStorage.setItem('reelforge-emergency-save', JSON.stringify({
          projectName: this.currentProjectName,
          timestamp: Date.now(),
          data,
        }));
      } catch {
        // May fail if data is too large
      }
    }
  };

  /**
   * Check for emergency save from crash.
   */
  async checkEmergencySave(): Promise<{ projectName: string; data: string; timestamp: number } | null> {
    try {
      const saved = localStorage.getItem('reelforge-emergency-save');
      if (!saved) return null;

      localStorage.removeItem('reelforge-emergency-save');
      return JSON.parse(saved);
    } catch {
      return null;
    }
  }

  /**
   * Subscribe to auto-save events.
   */
  onSave(listener: AutoSaveListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Get current config.
   */
  getConfig(): Readonly<AutoSaveConfig> {
    return { ...this.config };
  }

  /**
   * Dispose and cleanup.
   */
  dispose(): void {
    this.stop();
    window.removeEventListener('beforeunload', this.handleBeforeUnload);
    this.listeners.clear();
    this.getProjectData = null;
  }
}

// Singleton instance
export const AutoSaveManager = new AutoSaveManagerClass();

// ============ Utility Functions ============

/**
 * Format auto-save timestamp for display.
 */
export function formatAutoSaveTime(timestamp: number): string {
  const date = new Date(timestamp);
  const now = new Date();

  // Same day
  if (date.toDateString() === now.toDateString()) {
    return `Today at ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
  }

  // Yesterday
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) {
    return `Yesterday at ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
  }

  // This week
  const weekAgo = new Date(now);
  weekAgo.setDate(weekAgo.getDate() - 7);
  if (date > weekAgo) {
    return date.toLocaleDateString([], { weekday: 'long', hour: '2-digit', minute: '2-digit' });
  }

  // Older
  return date.toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

/**
 * Format data size for display.
 */
export function formatDataSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

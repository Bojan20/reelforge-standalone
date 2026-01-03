/**
 * useSessionPersistence - Persist session state to IndexedDB
 *
 * Automatically saves and restores editor session state:
 * - Timeline clips and tracks
 * - Mixer bus settings
 * - Transport position
 * - UI panel states
 * - Undo history
 *
 * Features:
 * - Zod schema validation on load (prevents corrupt data from crashing app)
 * - Graceful degradation with default values for invalid fields
 * - Version migration support
 *
 * @module hooks/useSessionPersistence
 */

import { useEffect, useCallback, useRef } from 'react';
import {
  validateSessionState,
  parseSessionStateWithDefaults,
  needsMigration,
  migrateSessionState,
} from '../schemas/sessionSchema';

// ============ Types ============

export interface SessionState {
  version: number;
  timestamp: number;
  timeline: {
    clips: SerializedClip[];
    tracks: SerializedTrack[];
    zoom: number;
    scrollOffset: number;
  };
  transport: {
    currentTime: number;
    loopEnabled: boolean;
    loopStart: number;
    loopEnd: number;
    tempo: number;
  };
  mixer: {
    buses: SerializedBus[];
  };
  ui: {
    leftPanelOpen: boolean;
    rightPanelOpen: boolean;
    bottomPanelOpen: boolean;
    leftPanelWidth: number;
    rightPanelWidth: number;
    bottomPanelHeight: number;
    selectedBusId: string | null;
    selectedClipIds: string[];
  };
}

export interface SerializedClip {
  id: string;
  trackId: string;
  name: string;
  startTime: number;
  duration: number;
  color: string;
  audioFileId?: string;
}

export interface SerializedTrack {
  id: string;
  name: string;
  color: string;
  muted: boolean;
  solo: boolean;
  armed: boolean;
}

export interface SerializedBus {
  id: string;
  name: string;
  volume: number;
  pan: number;
  muted: boolean;
  solo: boolean;
  inserts: SerializedInsert[];
}

export interface SerializedInsert {
  id: string;
  pluginId: string;
  name: string;
  bypassed: boolean;
  params: Record<string, number>;
}

export interface UseSessionPersistenceOptions {
  /** Database name */
  dbName?: string;
  /** Store name */
  storeName?: string;
  /** Session key */
  sessionKey?: string;
  /** Auto-save interval in ms (0 to disable) */
  autoSaveInterval?: number;
  /** Debounce time for saves in ms */
  debounceMs?: number;
  /** On state restored callback */
  onRestore?: (state: SessionState) => void;
  /** On save error callback */
  onError?: (error: Error) => void;
}

const SESSION_VERSION = 1;
const DEFAULT_DB_NAME = 'reelforge-session';
const DEFAULT_STORE_NAME = 'sessions';
const DEFAULT_SESSION_KEY = 'current';

// ============ IndexedDB Helpers ============

async function openDatabase(dbName: string, storeName: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);

    request.onerror = () => reject(new Error('Failed to open database'));

    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName, { keyPath: 'key' });
      }
    };
  });
}

async function saveToIndexedDB(
  dbName: string,
  storeName: string,
  key: string,
  data: SessionState
): Promise<void> {
  const db = await openDatabase(dbName, storeName);
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    const request = store.put({ key, data });

    request.onerror = () => reject(new Error('Failed to save session'));
    request.onsuccess = () => resolve();

    tx.oncomplete = () => db.close();
  });
}

async function loadFromIndexedDB(
  dbName: string,
  storeName: string,
  key: string
): Promise<SessionState | null> {
  try {
    const db = await openDatabase(dbName, storeName);
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, 'readonly');
      const store = tx.objectStore(storeName);
      const request = store.get(key);

      request.onerror = () => reject(new Error('Failed to load session'));
      request.onsuccess = () => {
        const result = request.result;
        const rawData = result?.data;

        if (!rawData) {
          resolve(null);
          return;
        }

        // Validate loaded data with Zod schema
        const validation = validateSessionState(rawData);

        if (validation.success) {
          resolve(validation.data as SessionState);
          return;
        }

        // Data is invalid - log issues and attempt graceful recovery
        console.warn(
          '[SessionPersistence] Invalid session data detected:',
          validation.issues
        );

        // Check if migration is needed
        if (needsMigration(rawData, SESSION_VERSION)) {
          console.log('[SessionPersistence] Attempting migration...');
          const migrated = migrateSessionState(rawData, SESSION_VERSION);
          resolve(migrated as SessionState);
          return;
        }

        // Parse with defaults for partial recovery
        console.log('[SessionPersistence] Recovering with defaults...');
        const recovered = parseSessionStateWithDefaults(rawData);
        resolve(recovered as SessionState);
      };

      tx.oncomplete = () => db.close();
    });
  } catch {
    return null;
  }
}

async function deleteFromIndexedDB(
  dbName: string,
  storeName: string,
  key: string
): Promise<void> {
  const db = await openDatabase(dbName, storeName);
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);
    const request = store.delete(key);

    request.onerror = () => reject(new Error('Failed to delete session'));
    request.onsuccess = () => resolve();

    tx.oncomplete = () => db.close();
  });
}

// ============ Hook ============

export function useSessionPersistence(options: UseSessionPersistenceOptions = {}) {
  const {
    dbName = DEFAULT_DB_NAME,
    storeName = DEFAULT_STORE_NAME,
    sessionKey = DEFAULT_SESSION_KEY,
    autoSaveInterval = 30000, // 30 seconds
    debounceMs = 1000,
    onRestore,
    onError,
  } = options;

  const saveTimeoutRef = useRef<number | null>(null);
  const autoSaveIntervalRef = useRef<number | null>(null);
  const pendingStateRef = useRef<SessionState | null>(null);
  const lastSaveRef = useRef<number>(0);

  // Save state (debounced)
  const saveState = useCallback((state: SessionState) => {
    pendingStateRef.current = {
      ...state,
      version: SESSION_VERSION,
      timestamp: Date.now(),
    };

    // Debounce
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }

    saveTimeoutRef.current = window.setTimeout(async () => {
      const stateToSave = pendingStateRef.current;
      if (!stateToSave) return;

      try {
        await saveToIndexedDB(dbName, storeName, sessionKey, stateToSave);
        lastSaveRef.current = Date.now();
        console.log('[SessionPersistence] State saved');
      } catch (err) {
        onError?.(err as Error);
        console.error('[SessionPersistence] Save failed:', err);
      }

      pendingStateRef.current = null;
    }, debounceMs);
  }, [dbName, storeName, sessionKey, debounceMs, onError]);

  // Save immediately (no debounce)
  const saveNow = useCallback(async (state: SessionState): Promise<boolean> => {
    const stateToSave = {
      ...state,
      version: SESSION_VERSION,
      timestamp: Date.now(),
    };

    try {
      await saveToIndexedDB(dbName, storeName, sessionKey, stateToSave);
      lastSaveRef.current = Date.now();
      console.log('[SessionPersistence] State saved immediately');
      return true;
    } catch (err) {
      onError?.(err as Error);
      console.error('[SessionPersistence] Save failed:', err);
      return false;
    }
  }, [dbName, storeName, sessionKey, onError]);

  // Load state
  const loadState = useCallback(async (): Promise<SessionState | null> => {
    try {
      const state = await loadFromIndexedDB(dbName, storeName, sessionKey);

      if (state) {
        // Validate version
        if (state.version !== SESSION_VERSION) {
          console.warn('[SessionPersistence] Session version mismatch, may need migration');
        }

        onRestore?.(state);
        console.log('[SessionPersistence] State restored from', new Date(state.timestamp).toLocaleString());
        return state;
      }

      return null;
    } catch (err) {
      onError?.(err as Error);
      console.error('[SessionPersistence] Load failed:', err);
      return null;
    }
  }, [dbName, storeName, sessionKey, onRestore, onError]);

  // Clear saved state
  const clearState = useCallback(async (): Promise<boolean> => {
    try {
      await deleteFromIndexedDB(dbName, storeName, sessionKey);
      console.log('[SessionPersistence] State cleared');
      return true;
    } catch (err) {
      onError?.(err as Error);
      console.error('[SessionPersistence] Clear failed:', err);
      return false;
    }
  }, [dbName, storeName, sessionKey, onError]);

  // Setup auto-save
  useEffect(() => {
    if (autoSaveInterval <= 0) return;

    autoSaveIntervalRef.current = window.setInterval(() => {
      if (pendingStateRef.current) {
        // There's pending state, trigger save
        const state = pendingStateRef.current;
        saveNow(state);
      }
    }, autoSaveInterval);

    return () => {
      if (autoSaveIntervalRef.current) {
        clearInterval(autoSaveIntervalRef.current);
      }
    };
  }, [autoSaveInterval, saveNow]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
      }
      if (autoSaveIntervalRef.current) {
        clearInterval(autoSaveIntervalRef.current);
      }
    };
  }, []);

  // Save before unload
  useEffect(() => {
    const handleBeforeUnload = () => {
      if (pendingStateRef.current) {
        // Try to save synchronously (may not work in all browsers)
        const stateToSave = {
          ...pendingStateRef.current,
          version: SESSION_VERSION,
          timestamp: Date.now(),
        };

        // Use localStorage as fallback for last-second saves
        try {
          localStorage.setItem(
            `${dbName}:${sessionKey}:emergency`,
            JSON.stringify(stateToSave)
          );
        } catch {
          // Ignore
        }
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);

    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  }, [dbName, sessionKey]);

  // Load emergency backup from localStorage (with validation)
  const loadEmergencyBackup = useCallback((): SessionState | null => {
    const key = `${dbName}:${sessionKey}:emergency`;
    try {
      const raw = localStorage.getItem(key);
      if (!raw) return null;

      const parsed = JSON.parse(raw);
      const validation = validateSessionState(parsed);

      if (validation.success) {
        // Clear the emergency backup after successful load
        localStorage.removeItem(key);
        return validation.data as SessionState;
      }

      // Attempt recovery with defaults
      console.warn('[SessionPersistence] Emergency backup invalid, recovering:', validation.issues);
      const recovered = parseSessionStateWithDefaults(parsed);
      localStorage.removeItem(key);
      return recovered as SessionState;
    } catch {
      return null;
    }
  }, [dbName, sessionKey]);

  // Check if emergency backup exists
  const hasEmergencyBackup = useCallback((): boolean => {
    const key = `${dbName}:${sessionKey}:emergency`;
    return localStorage.getItem(key) !== null;
  }, [dbName, sessionKey]);

  return {
    saveState,
    saveNow,
    loadState,
    clearState,
    loadEmergencyBackup,
    hasEmergencyBackup,
    getLastSaveTime: () => lastSaveRef.current,
  };
}

// ============ Helper to create session state ============

export function createSessionState(params: {
  clips?: SerializedClip[];
  tracks?: SerializedTrack[];
  zoom?: number;
  scrollOffset?: number;
  currentTime?: number;
  loopEnabled?: boolean;
  loopStart?: number;
  loopEnd?: number;
  tempo?: number;
  buses?: SerializedBus[];
  leftPanelOpen?: boolean;
  rightPanelOpen?: boolean;
  bottomPanelOpen?: boolean;
  leftPanelWidth?: number;
  rightPanelWidth?: number;
  bottomPanelHeight?: number;
  selectedBusId?: string | null;
  selectedClipIds?: string[];
}): SessionState {
  return {
    version: SESSION_VERSION,
    timestamp: Date.now(),
    timeline: {
      clips: params.clips ?? [],
      tracks: params.tracks ?? [],
      zoom: params.zoom ?? 50,
      scrollOffset: params.scrollOffset ?? 0,
    },
    transport: {
      currentTime: params.currentTime ?? 0,
      loopEnabled: params.loopEnabled ?? false,
      loopStart: params.loopStart ?? 0,
      loopEnd: params.loopEnd ?? 60,
      tempo: params.tempo ?? 120,
    },
    mixer: {
      buses: params.buses ?? [],
    },
    ui: {
      leftPanelOpen: params.leftPanelOpen ?? true,
      rightPanelOpen: params.rightPanelOpen ?? true,
      bottomPanelOpen: params.bottomPanelOpen ?? true,
      leftPanelWidth: params.leftPanelWidth ?? 280,
      rightPanelWidth: params.rightPanelWidth ?? 320,
      bottomPanelHeight: params.bottomPanelHeight ?? 200,
      selectedBusId: params.selectedBusId ?? null,
      selectedClipIds: params.selectedClipIds ?? [],
    },
  };
}

export type SessionPersistenceReturn = ReturnType<typeof useSessionPersistence>;

// Re-export schema utilities for external use
export {
  validateSessionState,
  parseSessionStateWithDefaults,
  getDefaultSessionState,
  needsMigration,
  migrateSessionState,
} from '../schemas/sessionSchema';

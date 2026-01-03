/**
 * useAutoSave - React hook for auto-save integration
 *
 * Provides easy integration with AutoSaveManager:
 * - Automatic initialization
 * - Dirty state tracking
 * - Recovery check on mount
 * - Status indicator
 *
 * @module hooks/useAutoSave
 */

import { useEffect, useState, useCallback, useRef } from 'react';
import {
  AutoSaveManager,
  formatAutoSaveTime,
  type AutoSaveEntry,
  type AutoSaveConfig,
  type RecoveryInfo,
} from '../file-system/AutoSave';

// ============ Types ============

export interface AutoSaveStatus {
  /** Auto-save is enabled */
  enabled: boolean;
  /** Has unsaved changes */
  isDirty: boolean;
  /** Last save entry */
  lastSave: AutoSaveEntry | null;
  /** Last save time formatted */
  lastSaveTime: string | null;
  /** Is currently saving */
  isSaving: boolean;
  /** Has recovery available */
  hasRecovery: boolean;
  /** Recovery entries */
  recoveryEntries: AutoSaveEntry[];
}

export interface UseAutoSaveOptions {
  /** Project name */
  projectName?: string;
  /** Get project data as JSON string */
  getProjectData: () => string;
  /** Restore project from data */
  onRestore?: (data: string) => void;
  /** Auto-save interval in ms (default: 60000) */
  intervalMs?: number;
  /** Maximum snapshots to keep (default: 5) */
  maxSnapshots?: number;
  /** Enable auto-save (default: true) */
  enabled?: boolean;
}

export interface UseAutoSaveReturn {
  /** Current status */
  status: AutoSaveStatus;
  /** Mark project as dirty (needs save) */
  markDirty: () => void;
  /** Force immediate save */
  forceSave: () => Promise<void>;
  /** Load recovery entry */
  loadRecovery: (entryId: string) => Promise<boolean>;
  /** Dismiss recovery (clear entries) */
  dismissRecovery: () => Promise<void>;
  /** Update config */
  setConfig: (config: Partial<AutoSaveConfig>) => void;
  /** Check for emergency save */
  checkEmergencySave: () => Promise<{ projectName: string; data: string } | null>;
}

// ============ Hook ============

export function useAutoSave(options: UseAutoSaveOptions): UseAutoSaveReturn {
  const {
    projectName = 'Untitled',
    getProjectData,
    onRestore,
    intervalMs = 60000,
    maxSnapshots = 5,
    enabled = true,
  } = options;

  const [status, setStatus] = useState<AutoSaveStatus>({
    enabled,
    isDirty: false,
    lastSave: null,
    lastSaveTime: null,
    isSaving: false,
    hasRecovery: false,
    recoveryEntries: [],
  });

  const getProjectDataRef = useRef(getProjectData);
  getProjectDataRef.current = getProjectData;

  // Initialize auto-save on mount
  useEffect(() => {
    AutoSaveManager.initialize(
      () => getProjectDataRef.current(),
      {
        enabled,
        intervalMs,
        maxSnapshots,
        compressData: false,
      }
    );

    AutoSaveManager.setProjectName(projectName);

    // Subscribe to save events
    const unsubscribe = AutoSaveManager.onSave((entry) => {
      setStatus((prev) => ({
        ...prev,
        isDirty: false,
        lastSave: entry,
        lastSaveTime: formatAutoSaveTime(entry.timestamp),
        isSaving: false,
      }));
    });

    // Check for recovery
    AutoSaveManager.getRecoveryInfo().then((info: RecoveryInfo) => {
      setStatus((prev) => ({
        ...prev,
        hasRecovery: info.hasRecovery,
        recoveryEntries: info.entries,
      }));
    });

    return () => {
      unsubscribe();
      AutoSaveManager.dispose();
    };
  }, [enabled, intervalMs, maxSnapshots, projectName]);

  // Update project name when it changes
  useEffect(() => {
    AutoSaveManager.setProjectName(projectName);
  }, [projectName]);

  // Mark dirty
  const markDirty = useCallback(() => {
    AutoSaveManager.markDirty();
    setStatus((prev) => ({ ...prev, isDirty: true }));
  }, []);

  // Force save
  const forceSave = useCallback(async () => {
    setStatus((prev) => ({ ...prev, isSaving: true }));
    await AutoSaveManager.forceSave();
  }, []);

  // Load recovery
  const loadRecovery = useCallback(async (entryId: string): Promise<boolean> => {
    const entry = await AutoSaveManager.loadEntry(entryId);
    if (!entry || !onRestore) return false;

    try {
      onRestore(entry.data);
      return true;
    } catch {
      return false;
    }
  }, [onRestore]);

  // Dismiss recovery
  const dismissRecovery = useCallback(async () => {
    await AutoSaveManager.clearAll();
    setStatus((prev) => ({
      ...prev,
      hasRecovery: false,
      recoveryEntries: [],
    }));
  }, []);

  // Update config
  const setConfig = useCallback((config: Partial<AutoSaveConfig>) => {
    AutoSaveManager.setConfig(config);
    if (config.enabled !== undefined) {
      setStatus((prev) => ({ ...prev, enabled: config.enabled! }));
    }
  }, []);

  // Check emergency save
  const checkEmergencySave = useCallback(async () => {
    return AutoSaveManager.checkEmergencySave();
  }, []);

  return {
    status,
    markDirty,
    forceSave,
    loadRecovery,
    dismissRecovery,
    setConfig,
    checkEmergencySave,
  };
}

// ============ Re-export utilities ============

export { formatAutoSaveTime, formatDataSize } from '../file-system/AutoSave';
export type { AutoSaveEntry, AutoSaveConfig, RecoveryInfo } from '../file-system/AutoSave';

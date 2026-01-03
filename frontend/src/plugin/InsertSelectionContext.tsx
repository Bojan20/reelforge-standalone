/**
 * ReelForge M9.1 Insert Selection Context
 *
 * Manages the currently selected insert for editor display.
 * This is UI-only state - not persisted to project file.
 *
 * @module plugin/InsertSelectionContext
 */

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import type { InsertId, PluginId } from '../insert/types';
import type { InsertableBusId } from '../project/projectTypes';

/**
 * Scope of the selected insert.
 */
export type InsertScope = 'master' | 'bus' | 'asset';

/**
 * Reference to a selected insert.
 */
export interface InsertSelection {
  /** Scope: master, bus, or asset */
  scope: InsertScope;

  /** Bus ID (only for scope='bus') */
  busId?: InsertableBusId;

  /** Asset ID (only for scope='asset') */
  assetId?: string;

  /** The insert ID */
  insertId: InsertId;

  /** The plugin type */
  pluginId: PluginId;

  /** Current parameter values */
  params: Record<string, number>;

  /** Whether the insert is bypassed */
  bypassed: boolean;
}

/**
 * Callback type for parameter changes.
 */
export type OnParamChange = (paramId: string, value: number) => void;

/**
 * Callback type for parameter reset.
 */
export type OnParamReset = (paramId: string) => void;

/**
 * Callback type for bypass toggle.
 */
export type OnBypassChange = (bypassed: boolean) => void;

/**
 * Callback type for batch parameter changes (atomic update).
 * Use this when multiple params change together to avoid race conditions.
 */
export type OnParamBatch = (changes: Record<string, number>) => void;

/**
 * Context value interface.
 */
interface InsertSelectionContextValue {
  /** Currently selected insert, or null if none */
  selection: InsertSelection | null;

  /** Select an insert for editing */
  selectInsert: (selection: InsertSelection) => void;

  /** Clear the selection (close editor) */
  clearSelection: () => void;

  /** Update the current selection's params (call when params change externally) */
  updateSelectionParams: (params: Record<string, number>) => void;

  /** Update the current selection's bypass state */
  updateSelectionBypassed: (bypassed: boolean) => void;

  /** Callbacks for the editor to use */
  onParamChange: OnParamChange | null;
  onParamReset: OnParamReset | null;
  onBypassChange: OnBypassChange | null;
  onParamBatch: OnParamBatch | null;

  /** Set the callbacks (called by insert panels) */
  setCallbacks: (
    onParamChange: OnParamChange,
    onParamReset: OnParamReset,
    onBypassChange: OnBypassChange,
    onParamBatch?: OnParamBatch
  ) => void;

  /** Clear callbacks */
  clearCallbacks: () => void;
}

const InsertSelectionContext = createContext<InsertSelectionContextValue | null>(null);

interface InsertSelectionProviderProps {
  children: ReactNode;
}

export function InsertSelectionProvider({ children }: InsertSelectionProviderProps) {
  const [selection, setSelection] = useState<InsertSelection | null>(null);
  const [onParamChange, setOnParamChange] = useState<OnParamChange | null>(null);
  const [onParamReset, setOnParamReset] = useState<OnParamReset | null>(null);
  const [onBypassChange, setOnBypassChange] = useState<OnBypassChange | null>(null);
  const [onParamBatch, setOnParamBatch] = useState<OnParamBatch | null>(null);

  const selectInsert = useCallback((newSelection: InsertSelection) => {
    setSelection(newSelection);
  }, []);

  const clearSelection = useCallback(() => {
    setSelection(null);
    setOnParamChange(null);
    setOnParamReset(null);
    setOnBypassChange(null);
    setOnParamBatch(null);
  }, []);

  const updateSelectionParams = useCallback((params: Record<string, number>) => {
    setSelection((prev) => {
      if (!prev) return null;
      return { ...prev, params };
    });
  }, []);

  const updateSelectionBypassed = useCallback((bypassed: boolean) => {
    setSelection((prev) => {
      if (!prev) return null;
      return { ...prev, bypassed };
    });
  }, []);

  const setCallbacks = useCallback(
    (
      newOnParamChange: OnParamChange,
      newOnParamReset: OnParamReset,
      newOnBypassChange: OnBypassChange,
      newOnParamBatch?: OnParamBatch
    ) => {
      setOnParamChange(() => newOnParamChange);
      setOnParamReset(() => newOnParamReset);
      setOnBypassChange(() => newOnBypassChange);
      setOnParamBatch(() => newOnParamBatch ?? null);
    },
    []
  );

  const clearCallbacks = useCallback(() => {
    setOnParamChange(null);
    setOnParamReset(null);
    setOnBypassChange(null);
    setOnParamBatch(null);
  }, []);

  const value = useMemo<InsertSelectionContextValue>(
    () => ({
      selection,
      selectInsert,
      clearSelection,
      updateSelectionParams,
      updateSelectionBypassed,
      onParamChange,
      onParamReset,
      onBypassChange,
      onParamBatch,
      setCallbacks,
      clearCallbacks,
    }),
    [
      selection,
      selectInsert,
      clearSelection,
      updateSelectionParams,
      updateSelectionBypassed,
      onParamChange,
      onParamReset,
      onBypassChange,
      onParamBatch,
      setCallbacks,
      clearCallbacks,
    ]
  );

  return (
    <InsertSelectionContext.Provider value={value}>
      {children}
    </InsertSelectionContext.Provider>
  );
}

/**
 * Hook to access insert selection context.
 */
export function useInsertSelection(): InsertSelectionContextValue {
  const context = useContext(InsertSelectionContext);
  if (!context) {
    throw new Error('useInsertSelection must be used within InsertSelectionProvider');
  }
  return context;
}

/**
 * Hook to check if a specific insert is currently selected.
 */
export function useIsInsertSelected(
  scope: InsertScope,
  insertId: InsertId,
  scopeId?: string
): boolean {
  const context = useContext(InsertSelectionContext);
  if (!context?.selection) return false;

  const { selection } = context;
  if (selection.scope !== scope) return false;
  if (selection.insertId !== insertId) return false;

  // For bus scope, also check busId
  if (scope === 'bus' && selection.busId !== scopeId) return false;

  // For asset scope, also check assetId
  if (scope === 'asset' && selection.assetId !== scopeId) return false;

  return true;
}

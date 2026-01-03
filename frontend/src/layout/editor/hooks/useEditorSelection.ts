/**
 * useEditorSelection - Selection State Hook
 *
 * Manages all selection state in the editor:
 * - Selected event
 * - Selected action(s)
 * - Selected clip
 * - Selected bus
 * - Multi-select with Shift/Cmd
 *
 * @module layout/editor/hooks/useEditorSelection
 */

import { useState, useCallback, useEffect } from 'react';
import { STORAGE_KEYS } from '../constants';
import type { SessionState } from '../types';

// ============ Types ============

export interface UseEditorSelectionReturn {
  /** Selected event name */
  selectedEventName: string | null;
  /** Set selected event */
  setSelectedEventName: (name: string | null) => void;
  /** Selected action index (single) */
  selectedActionIndex: number | null;
  /** Set selected action index */
  setSelectedActionIndex: (index: number | null) => void;
  /** Selected action indices (multi-select) */
  selectedActionIndices: Set<number>;
  /** Set selected action indices */
  setSelectedActionIndices: React.Dispatch<React.SetStateAction<Set<number>>>;
  /** Handle action click with multi-select support */
  handleActionClick: (index: number, event: React.MouseEvent) => void;
  /** Clear action selection */
  clearActionSelection: () => void;
  /** Select all actions */
  selectAllActions: (count: number) => void;
  /** Selected clip ID */
  selectedClipId: string | null;
  /** Set selected clip */
  setSelectedClipId: (id: string | null) => void;
  /** Selected bus ID */
  selectedBusId: string | null;
  /** Set selected bus */
  setSelectedBusId: (id: string | null) => void;
  /** Drag state for action reordering */
  draggedActionIndex: number | null;
  /** Set dragged action index */
  setDraggedActionIndex: (index: number | null) => void;
  /** Drag over index */
  dragOverIndex: number | null;
  /** Set drag over index */
  setDragOverIndex: (index: number | null) => void;
}

// ============ Helper ============

function getInitialSession(): Partial<SessionState> {
  try {
    const saved = localStorage.getItem(STORAGE_KEYS.SESSION);
    if (saved) {
      const parsed = JSON.parse(saved) as SessionState;
      // Check if session is less than 24 hours old
      if (Date.now() - parsed.timestamp < 24 * 60 * 60 * 1000) {
        return parsed;
      }
    }
  } catch {
    // Ignore parse errors
  }
  return {};
}

// ============ Hook ============

export function useEditorSelection(): UseEditorSelectionReturn {
  const initialSession = getInitialSession();

  // Event selection
  const [selectedEventName, setSelectedEventName] = useState<string | null>(
    initialSession.selectedEventName ?? null
  );

  // Action selection (single)
  const [selectedActionIndex, setSelectedActionIndex] = useState<number | null>(
    initialSession.selectedActionIndex ?? null
  );

  // Action selection (multi)
  const [selectedActionIndices, setSelectedActionIndices] = useState<Set<number>>(new Set());

  // Clip selection
  const [selectedClipId, setSelectedClipId] = useState<string | null>(null);

  // Bus selection
  const [selectedBusId, setSelectedBusId] = useState<string | null>(null);

  // Drag state
  const [draggedActionIndex, setDraggedActionIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);

  // Handle action click with multi-select
  const handleActionClick = useCallback((index: number, event: React.MouseEvent) => {
    const isMeta = event.metaKey || event.ctrlKey;
    const isShift = event.shiftKey;

    if (isMeta) {
      // Toggle selection
      setSelectedActionIndices(prev => {
        const next = new Set(prev);
        if (next.has(index)) {
          next.delete(index);
        } else {
          next.add(index);
        }
        return next;
      });
      // Also update single selection
      setSelectedActionIndex(index);
    } else if (isShift && selectedActionIndex !== null) {
      // Range selection
      const start = Math.min(selectedActionIndex, index);
      const end = Math.max(selectedActionIndex, index);
      const range = new Set<number>();
      for (let i = start; i <= end; i++) {
        range.add(i);
      }
      setSelectedActionIndices(range);
    } else {
      // Single selection
      setSelectedActionIndex(index);
      setSelectedActionIndices(new Set([index]));
    }
  }, [selectedActionIndex]);

  // Clear action selection
  const clearActionSelection = useCallback(() => {
    setSelectedActionIndex(null);
    setSelectedActionIndices(new Set());
  }, []);

  // Select all actions
  const selectAllActions = useCallback((count: number) => {
    const all = new Set<number>();
    for (let i = 0; i < count; i++) {
      all.add(i);
    }
    setSelectedActionIndices(all);
    if (count > 0) {
      setSelectedActionIndex(0);
    }
  }, []);

  // Clear clip selection when event changes
  useEffect(() => {
    setSelectedClipId(null);
  }, [selectedEventName]);

  return {
    selectedEventName,
    setSelectedEventName,
    selectedActionIndex,
    setSelectedActionIndex,
    selectedActionIndices,
    setSelectedActionIndices,
    handleActionClick,
    clearActionSelection,
    selectAllActions,
    selectedClipId,
    setSelectedClipId,
    selectedBusId,
    setSelectedBusId,
    draggedActionIndex,
    setDraggedActionIndex,
    dragOverIndex,
    setDragOverIndex,
  };
}

export default useEditorSelection;

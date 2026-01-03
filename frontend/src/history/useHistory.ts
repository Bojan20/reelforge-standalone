/**
 * ReelForge History Hook
 *
 * Undo/redo state management:
 * - Action stack
 * - Undo/redo operations
 * - History branching
 * - Transaction grouping
 *
 * @module history/useHistory
 */

import { useState, useCallback, useMemo, useRef } from 'react';

// ============ Types ============

export interface HistoryAction<T = unknown> {
  /** Unique action ID */
  id: string;
  /** Action type/name */
  type: string;
  /** Human-readable description */
  description: string;
  /** Timestamp */
  timestamp: number;
  /** Data before action */
  before: T;
  /** Data after action */
  after: T;
  /** Group ID for transaction grouping */
  groupId?: string;
  /** Tags for filtering */
  tags?: string[];
}

export interface HistoryState<T = unknown> {
  /** Past actions (for undo) */
  past: HistoryAction<T>[];
  /** Future actions (for redo) */
  future: HistoryAction<T>[];
  /** Current action index */
  currentIndex: number;
  /** Is currently in transaction */
  inTransaction: boolean;
  /** Current transaction group ID */
  transactionGroupId: string | null;
}

export interface UseHistoryOptions {
  /** Maximum history size */
  maxSize?: number;
  /** On state change callback */
  onStateChange?: (state: HistoryState) => void;
}

export interface UseHistoryReturn<T = unknown> {
  /** Can undo */
  canUndo: boolean;
  /** Can redo */
  canRedo: boolean;
  /** Past actions */
  past: HistoryAction<T>[];
  /** Future actions */
  future: HistoryAction<T>[];
  /** Current index */
  currentIndex: number;
  /** Push new action */
  push: (action: Omit<HistoryAction<T>, 'id' | 'timestamp'>) => void;
  /** Undo last action */
  undo: () => HistoryAction<T> | null;
  /** Redo next action */
  redo: () => HistoryAction<T> | null;
  /** Undo to specific action */
  undoTo: (actionId: string) => HistoryAction<T>[];
  /** Redo to specific action */
  redoTo: (actionId: string) => HistoryAction<T>[];
  /** Clear all history */
  clear: () => void;
  /** Begin transaction (group multiple actions) */
  beginTransaction: (description?: string) => void;
  /** End transaction */
  endTransaction: () => void;
  /** Is in transaction */
  inTransaction: boolean;
  /** Get action by ID */
  getAction: (actionId: string) => HistoryAction<T> | null;
  /** Get all actions */
  getAllActions: () => HistoryAction<T>[];
}

// ============ Helpers ============

function generateId(): string {
  return `action-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// ============ Hook ============

export function useHistory<T = unknown>(
  options: UseHistoryOptions = {}
): UseHistoryReturn<T> {
  const { maxSize = 100, onStateChange } = options;

  const [state, setState] = useState<HistoryState<T>>({
    past: [],
    future: [],
    currentIndex: -1,
    inTransaction: false,
    transactionGroupId: null,
  });

  const transactionActionsRef = useRef<HistoryAction<T>[]>([]);

  // Notify state change
  const notifyChange = useCallback(
    (newState: HistoryState<T>) => {
      onStateChange?.(newState as HistoryState);
    },
    [onStateChange]
  );

  // Push new action
  const push = useCallback(
    (actionData: Omit<HistoryAction<T>, 'id' | 'timestamp'>) => {
      const action: HistoryAction<T> = {
        ...actionData,
        id: generateId(),
        timestamp: Date.now(),
        groupId: state.transactionGroupId || undefined,
      };

      if (state.inTransaction) {
        // Accumulate in transaction
        transactionActionsRef.current.push(action);
        return;
      }

      setState((prev) => {
        // Clear future on new action (linear history)
        let newPast = [...prev.past, action];

        // Trim to max size
        if (newPast.length > maxSize) {
          newPast = newPast.slice(newPast.length - maxSize);
        }

        const newState: HistoryState<T> = {
          ...prev,
          past: newPast,
          future: [],
          currentIndex: newPast.length - 1,
        };

        notifyChange(newState);
        return newState;
      });
    },
    [state.inTransaction, state.transactionGroupId, maxSize, notifyChange]
  );

  // Undo
  const undo = useCallback((): HistoryAction<T> | null => {
    if (state.past.length === 0) return null;

    let undoneAction: HistoryAction<T> | null = null;

    setState((prev) => {
      if (prev.past.length === 0) return prev;

      const lastAction = prev.past[prev.past.length - 1];
      undoneAction = lastAction;

      // If action is part of a group, undo entire group
      let actionsToUndo = [lastAction];
      if (lastAction.groupId) {
        actionsToUndo = [];
        const newPast = [...prev.past];
        while (newPast.length > 0) {
          const action = newPast[newPast.length - 1];
          if (action.groupId === lastAction.groupId) {
            actionsToUndo.unshift(newPast.pop()!);
          } else {
            break;
          }
        }

        const newState: HistoryState<T> = {
          ...prev,
          past: newPast,
          future: [...actionsToUndo, ...prev.future],
          currentIndex: newPast.length - 1,
        };
        notifyChange(newState);
        return newState;
      }

      const newState: HistoryState<T> = {
        ...prev,
        past: prev.past.slice(0, -1),
        future: [lastAction, ...prev.future],
        currentIndex: prev.past.length - 2,
      };

      notifyChange(newState);
      return newState;
    });

    return undoneAction;
  }, [state.past.length, notifyChange]);

  // Redo
  const redo = useCallback((): HistoryAction<T> | null => {
    if (state.future.length === 0) return null;

    let redoneAction: HistoryAction<T> | null = null;

    setState((prev) => {
      if (prev.future.length === 0) return prev;

      const nextAction = prev.future[0];
      redoneAction = nextAction;

      // If action is part of a group, redo entire group
      if (nextAction.groupId) {
        const actionsToRedo: HistoryAction<T>[] = [];
        const newFuture = [...prev.future];
        while (newFuture.length > 0) {
          const action = newFuture[0];
          if (action.groupId === nextAction.groupId) {
            actionsToRedo.push(newFuture.shift()!);
          } else {
            break;
          }
        }

        const newState: HistoryState<T> = {
          ...prev,
          past: [...prev.past, ...actionsToRedo],
          future: newFuture,
          currentIndex: prev.past.length + actionsToRedo.length - 1,
        };
        notifyChange(newState);
        return newState;
      }

      const newState: HistoryState<T> = {
        ...prev,
        past: [...prev.past, nextAction],
        future: prev.future.slice(1),
        currentIndex: prev.past.length,
      };

      notifyChange(newState);
      return newState;
    });

    return redoneAction;
  }, [state.future.length, notifyChange]);

  // Undo to specific action
  const undoTo = useCallback(
    (actionId: string): HistoryAction<T>[] => {
      const undone: HistoryAction<T>[] = [];

      setState((prev) => {
        const actionIndex = prev.past.findIndex((a) => a.id === actionId);
        if (actionIndex === -1) return prev;

        const actionsToUndo = prev.past.slice(actionIndex + 1);
        undone.push(...actionsToUndo);

        const newState: HistoryState<T> = {
          ...prev,
          past: prev.past.slice(0, actionIndex + 1),
          future: [...actionsToUndo.reverse(), ...prev.future],
          currentIndex: actionIndex,
        };

        notifyChange(newState);
        return newState;
      });

      return undone;
    },
    [notifyChange]
  );

  // Redo to specific action
  const redoTo = useCallback(
    (actionId: string): HistoryAction<T>[] => {
      const redone: HistoryAction<T>[] = [];

      setState((prev) => {
        const actionIndex = prev.future.findIndex((a) => a.id === actionId);
        if (actionIndex === -1) return prev;

        const actionsToRedo = prev.future.slice(0, actionIndex + 1);
        redone.push(...actionsToRedo);

        const newState: HistoryState<T> = {
          ...prev,
          past: [...prev.past, ...actionsToRedo],
          future: prev.future.slice(actionIndex + 1),
          currentIndex: prev.past.length + actionsToRedo.length - 1,
        };

        notifyChange(newState);
        return newState;
      });

      return redone;
    },
    [notifyChange]
  );

  // Clear history
  const clear = useCallback(() => {
    const newState: HistoryState<T> = {
      past: [],
      future: [],
      currentIndex: -1,
      inTransaction: false,
      transactionGroupId: null,
    };
    setState(newState);
    notifyChange(newState);
  }, [notifyChange]);

  // Begin transaction
  const beginTransaction = useCallback((_description?: string) => {
    const groupId = generateId();
    transactionActionsRef.current = [];

    setState((prev) => ({
      ...prev,
      inTransaction: true,
      transactionGroupId: groupId,
    }));
  }, []);

  // End transaction
  const endTransaction = useCallback(() => {
    const actions = transactionActionsRef.current;
    transactionActionsRef.current = [];

    setState((prev) => {
      if (!prev.inTransaction || actions.length === 0) {
        return {
          ...prev,
          inTransaction: false,
          transactionGroupId: null,
        };
      }

      let newPast = [...prev.past, ...actions];
      if (newPast.length > maxSize) {
        newPast = newPast.slice(newPast.length - maxSize);
      }

      const newState: HistoryState<T> = {
        ...prev,
        past: newPast,
        future: [],
        currentIndex: newPast.length - 1,
        inTransaction: false,
        transactionGroupId: null,
      };

      notifyChange(newState);
      return newState;
    });
  }, [maxSize, notifyChange]);

  // Get action by ID
  const getAction = useCallback(
    (actionId: string): HistoryAction<T> | null => {
      const allActions = [...state.past, ...state.future];
      return allActions.find((a) => a.id === actionId) || null;
    },
    [state.past, state.future]
  );

  // Get all actions
  const getAllActions = useCallback((): HistoryAction<T>[] => {
    return [...state.past, ...state.future];
  }, [state.past, state.future]);

  return useMemo(
    () => ({
      canUndo: state.past.length > 0,
      canRedo: state.future.length > 0,
      past: state.past,
      future: state.future,
      currentIndex: state.currentIndex,
      push,
      undo,
      redo,
      undoTo,
      redoTo,
      clear,
      beginTransaction,
      endTransaction,
      inTransaction: state.inTransaction,
      getAction,
      getAllActions,
    }),
    [
      state.past,
      state.future,
      state.currentIndex,
      state.inTransaction,
      push,
      undo,
      redo,
      undoTo,
      redoTo,
      clear,
      beginTransaction,
      endTransaction,
      getAction,
      getAllActions,
    ]
  );
}

export default useHistory;

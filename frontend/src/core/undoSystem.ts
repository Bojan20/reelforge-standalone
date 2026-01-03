/**
 * Undo/Redo System - Command Pattern Implementation
 *
 * Provides complete undo/redo capabilities for:
 * - All editor operations
 * - Grouped transactions
 * - History navigation
 * - State snapshots
 *
 * @module core/undoSystem
 */

// ============ TYPES ============

/**
 * Base interface for undoable commands
 */
export interface UndoableCommand {
  /** Unique command ID */
  id: string;
  /** Human-readable description */
  description: string;
  /** Timestamp when executed */
  timestamp: number;
  /** Execute/redo the command */
  execute: () => void;
  /** Undo the command */
  undo: () => void;
  /** Optional: merge with previous command of same type */
  merge?: (other: UndoableCommand) => boolean;
}

/**
 * Transaction for grouping multiple commands
 */
export interface Transaction {
  id: string;
  description: string;
  commands: UndoableCommand[];
  timestamp: number;
}

/**
 * History state
 */
export interface HistoryState {
  past: Transaction[];
  future: Transaction[];
  currentTransaction: Transaction | null;
  maxHistory: number;
  isTransactionOpen: boolean;
}

export type HistoryEventType = 'push' | 'undo' | 'redo' | 'clear' | 'transaction';

export interface HistoryEvent {
  type: HistoryEventType;
  transaction?: Transaction;
  command?: UndoableCommand;
}

type HistoryListener = (event: HistoryEvent) => void;

// ============ COMMAND FACTORIES ============

/**
 * Factory for creating property change commands
 */
export function createPropertyCommand<T extends object, K extends keyof T>(
  target: T,
  key: K,
  newValue: T[K],
  description?: string
): UndoableCommand {
  const oldValue = target[key];

  return {
    id: `prop-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || `Change ${String(key)}`,
    timestamp: Date.now(),
    execute: () => {
      target[key] = newValue;
    },
    undo: () => {
      target[key] = oldValue;
    },
    merge: (other: UndoableCommand) => {
      // Merge consecutive property changes on same target/key within 500ms
      if (
        other.id.startsWith('prop-') &&
        other.description === (description || `Change ${String(key)}`) &&
        Date.now() - other.timestamp < 500
      ) {
        // Update the newValue but keep the original oldValue
        return true;
      }
      return false;
    },
  };
}

/**
 * Factory for creating array push commands
 */
export function createArrayPushCommand<T>(
  array: T[],
  item: T,
  description?: string
): UndoableCommand {
  let index = -1;

  return {
    id: `push-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || 'Add item',
    timestamp: Date.now(),
    execute: () => {
      index = array.length;
      array.push(item);
    },
    undo: () => {
      if (index >= 0) {
        array.splice(index, 1);
      }
    },
  };
}

/**
 * Factory for creating array remove commands
 */
export function createArrayRemoveCommand<T>(
  array: T[],
  index: number,
  description?: string
): UndoableCommand {
  const item = array[index];
  const originalIndex = index;

  return {
    id: `remove-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || 'Remove item',
    timestamp: Date.now(),
    execute: () => {
      array.splice(originalIndex, 1);
    },
    undo: () => {
      array.splice(originalIndex, 0, item);
    },
  };
}

/**
 * Factory for creating array move commands
 */
export function createArrayMoveCommand<T>(
  array: T[],
  fromIndex: number,
  toIndex: number,
  description?: string
): UndoableCommand {
  return {
    id: `move-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || 'Move item',
    timestamp: Date.now(),
    execute: () => {
      const [item] = array.splice(fromIndex, 1);
      array.splice(toIndex, 0, item);
    },
    undo: () => {
      const [item] = array.splice(toIndex, 1);
      array.splice(fromIndex, 0, item);
    },
  };
}

/**
 * Factory for creating map set commands
 */
export function createMapSetCommand<K, V>(
  map: Map<K, V>,
  key: K,
  newValue: V,
  description?: string
): UndoableCommand {
  const oldValue = map.get(key);
  const hadKey = map.has(key);

  return {
    id: `mapset-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || `Set ${String(key)}`,
    timestamp: Date.now(),
    execute: () => {
      map.set(key, newValue);
    },
    undo: () => {
      if (hadKey) {
        map.set(key, oldValue!);
      } else {
        map.delete(key);
      }
    },
  };
}

/**
 * Factory for creating map delete commands
 */
export function createMapDeleteCommand<K, V>(
  map: Map<K, V>,
  key: K,
  description?: string
): UndoableCommand {
  const oldValue = map.get(key);
  const hadKey = map.has(key);

  return {
    id: `mapdel-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description: description || `Delete ${String(key)}`,
    timestamp: Date.now(),
    execute: () => {
      map.delete(key);
    },
    undo: () => {
      if (hadKey) {
        map.set(key, oldValue!);
      }
    },
  };
}

/**
 * Factory for creating composite commands (multiple operations as one)
 */
export function createCompositeCommand(
  commands: UndoableCommand[],
  description: string
): UndoableCommand {
  return {
    id: `composite-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    description,
    timestamp: Date.now(),
    execute: () => {
      commands.forEach(cmd => cmd.execute());
    },
    undo: () => {
      // Undo in reverse order
      [...commands].reverse().forEach(cmd => cmd.undo());
    },
  };
}

// ============ UNDO MANAGER CLASS ============

class UndoManagerClass {
  private state: HistoryState = {
    past: [],
    future: [],
    currentTransaction: null,
    maxHistory: 100,
    isTransactionOpen: false,
  };

  private listeners: Set<HistoryListener> = new Set();

  // ============ COMMAND EXECUTION ============

  /**
   * Execute a command and add to history
   */
  execute(command: UndoableCommand): void {
    // Execute the command
    command.execute();

    // If transaction is open, add to current transaction
    if (this.state.isTransactionOpen && this.state.currentTransaction) {
      // Check if we can merge with last command in transaction
      const lastCmd = this.state.currentTransaction.commands[
        this.state.currentTransaction.commands.length - 1
      ];
      if (lastCmd?.merge?.(command)) {
        // Merged - don't add
        return;
      }
      this.state.currentTransaction.commands.push(command);
      return;
    }

    // Create a single-command transaction
    const transaction: Transaction = {
      id: `tx-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      description: command.description,
      commands: [command],
      timestamp: Date.now(),
    };

    this.pushTransaction(transaction);
  }

  /**
   * Push a transaction to history
   */
  private pushTransaction(transaction: Transaction): void {
    // Clear future on new action
    this.state.future = [];

    // Check if we can merge with last transaction
    const lastTx = this.state.past[this.state.past.length - 1];
    if (lastTx?.commands.length === 1 && transaction.commands.length === 1) {
      const lastCmd = lastTx.commands[0];
      const newCmd = transaction.commands[0];
      if (lastCmd.merge?.(newCmd)) {
        // Merged - update timestamp but don't add new transaction
        lastTx.timestamp = transaction.timestamp;
        this.emit({ type: 'push', transaction: lastTx });
        return;
      }
    }

    // Add to history
    this.state.past.push(transaction);

    // Trim history if needed - use splice for O(1) instead of multiple shift() O(n)
    if (this.state.past.length > this.state.maxHistory) {
      const excess = this.state.past.length - this.state.maxHistory;
      this.state.past.splice(0, excess);
    }

    this.emit({ type: 'push', transaction });
  }

  // ============ TRANSACTIONS ============

  /**
   * Begin a transaction (group multiple commands)
   */
  beginTransaction(description: string): void {
    if (this.state.isTransactionOpen) {
      console.warn('Transaction already open, committing previous');
      this.commitTransaction();
    }

    this.state.isTransactionOpen = true;
    this.state.currentTransaction = {
      id: `tx-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      description,
      commands: [],
      timestamp: Date.now(),
    };

    this.emit({ type: 'transaction' });
  }

  /**
   * Commit the current transaction
   */
  commitTransaction(): void {
    if (!this.state.isTransactionOpen || !this.state.currentTransaction) {
      console.warn('No transaction to commit');
      return;
    }

    const transaction = this.state.currentTransaction;
    this.state.isTransactionOpen = false;
    this.state.currentTransaction = null;

    // Only add if there were actual commands
    if (transaction.commands.length > 0) {
      this.pushTransaction(transaction);
    }

    this.emit({ type: 'transaction' });
  }

  /**
   * Rollback the current transaction (undo all commands in it)
   */
  rollbackTransaction(): void {
    if (!this.state.isTransactionOpen || !this.state.currentTransaction) {
      console.warn('No transaction to rollback');
      return;
    }

    // Undo all commands in reverse order
    [...this.state.currentTransaction.commands]
      .reverse()
      .forEach(cmd => cmd.undo());

    this.state.isTransactionOpen = false;
    this.state.currentTransaction = null;

    this.emit({ type: 'transaction' });
  }

  // ============ UNDO/REDO ============

  /**
   * Undo the last transaction
   */
  undo(): boolean {
    if (this.state.past.length === 0) {
      return false;
    }

    const transaction = this.state.past.pop()!;

    // Undo all commands in reverse order
    [...transaction.commands].reverse().forEach(cmd => cmd.undo());

    // Move to future
    this.state.future.push(transaction);

    this.emit({ type: 'undo', transaction });
    return true;
  }

  /**
   * Redo the last undone transaction
   */
  redo(): boolean {
    if (this.state.future.length === 0) {
      return false;
    }

    const transaction = this.state.future.pop()!;

    // Execute all commands
    transaction.commands.forEach(cmd => cmd.execute());

    // Move to past
    this.state.past.push(transaction);

    this.emit({ type: 'redo', transaction });
    return true;
  }

  /**
   * Undo multiple transactions
   */
  undoMultiple(count: number): number {
    let undone = 0;
    for (let i = 0; i < count; i++) {
      if (this.undo()) {
        undone++;
      } else {
        break;
      }
    }
    return undone;
  }

  /**
   * Redo multiple transactions
   */
  redoMultiple(count: number): number {
    let redone = 0;
    for (let i = 0; i < count; i++) {
      if (this.redo()) {
        redone++;
      } else {
        break;
      }
    }
    return redone;
  }

  // ============ HISTORY MANAGEMENT ============

  /**
   * Clear all history
   */
  clear(): void {
    this.state.past = [];
    this.state.future = [];
    this.state.currentTransaction = null;
    this.state.isTransactionOpen = false;
    this.emit({ type: 'clear' });
  }

  /**
   * Get whether undo is available
   */
  canUndo(): boolean {
    return this.state.past.length > 0;
  }

  /**
   * Get whether redo is available
   */
  canRedo(): boolean {
    return this.state.future.length > 0;
  }

  /**
   * Get undo stack size
   */
  getUndoCount(): number {
    return this.state.past.length;
  }

  /**
   * Get redo stack size
   */
  getRedoCount(): number {
    return this.state.future.length;
  }

  /**
   * Get description of next undo action
   */
  getUndoDescription(): string | null {
    const last = this.state.past[this.state.past.length - 1];
    return last?.description ?? null;
  }

  /**
   * Get description of next redo action
   */
  getRedoDescription(): string | null {
    const last = this.state.future[this.state.future.length - 1];
    return last?.description ?? null;
  }

  /**
   * Get full undo history (most recent first)
   */
  getUndoHistory(): Array<{ id: string; description: string; timestamp: number }> {
    return [...this.state.past]
      .reverse()
      .map(tx => ({
        id: tx.id,
        description: tx.description,
        timestamp: tx.timestamp,
      }));
  }

  /**
   * Get full redo history (next to redo first)
   */
  getRedoHistory(): Array<{ id: string; description: string; timestamp: number }> {
    return [...this.state.future]
      .reverse()
      .map(tx => ({
        id: tx.id,
        description: tx.description,
        timestamp: tx.timestamp,
      }));
  }

  /**
   * Set max history size
   */
  setMaxHistory(max: number): void {
    this.state.maxHistory = max;
    // Use splice for O(1) instead of multiple shift() O(n)
    if (this.state.past.length > max) {
      const excess = this.state.past.length - max;
      this.state.past.splice(0, excess);
    }
  }

  // ============ STATE & EVENTS ============

  /**
   * Subscribe to history events
   */
  subscribe(listener: HistoryListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Emit event to all listeners
   */
  private emit(event: HistoryEvent): void {
    this.listeners.forEach(listener => {
      try {
        listener(event);
      } catch (error) {
        console.error('Undo listener error:', error);
      }
    });
  }

  /**
   * Check if a transaction is currently open
   */
  isInTransaction(): boolean {
    return this.state.isTransactionOpen;
  }
}

// ============ SINGLETON EXPORT ============

export const UndoManager = new UndoManagerClass();

// ============ REACT HOOK ============

import { useState, useEffect, useMemo } from 'react';

export interface UseUndoReturn {
  canUndo: boolean;
  canRedo: boolean;
  undoDescription: string | null;
  redoDescription: string | null;
  undoCount: number;
  redoCount: number;
  undo: () => void;
  redo: () => void;
  execute: (command: UndoableCommand) => void;
  beginTransaction: (description: string) => void;
  commitTransaction: () => void;
  rollbackTransaction: () => void;
  clear: () => void;
}

export function useUndo(): UseUndoReturn {
  const [, forceUpdate] = useState({});

  // Subscribe to history changes
  useEffect(() => {
    const unsubscribe = UndoManager.subscribe(() => {
      forceUpdate({});
    });
    return unsubscribe;
  }, []);

  // Memoized actions
  const actions = useMemo(() => ({
    undo: () => UndoManager.undo(),
    redo: () => UndoManager.redo(),
    execute: (command: UndoableCommand) => UndoManager.execute(command),
    beginTransaction: (description: string) => UndoManager.beginTransaction(description),
    commitTransaction: () => UndoManager.commitTransaction(),
    rollbackTransaction: () => UndoManager.rollbackTransaction(),
    clear: () => UndoManager.clear(),
  }), []);

  return {
    canUndo: UndoManager.canUndo(),
    canRedo: UndoManager.canRedo(),
    undoDescription: UndoManager.getUndoDescription(),
    redoDescription: UndoManager.getRedoDescription(),
    undoCount: UndoManager.getUndoCount(),
    redoCount: UndoManager.getRedoCount(),
    ...actions,
  };
}

// ============ KEYBOARD HANDLER (will be used by Keyboard Shortcuts System) ============

export function setupUndoKeyboardShortcuts(): () => void {
  const handleKeyDown = (e: KeyboardEvent) => {
    // Check for undo: Cmd+Z (Mac) or Ctrl+Z (Windows)
    if ((e.metaKey || e.ctrlKey) && e.key === 'z' && !e.shiftKey) {
      e.preventDefault();
      UndoManager.undo();
      return;
    }

    // Check for redo: Cmd+Shift+Z (Mac) or Ctrl+Y (Windows)
    if ((e.metaKey || e.ctrlKey) && e.key === 'z' && e.shiftKey) {
      e.preventDefault();
      UndoManager.redo();
      return;
    }

    // Also support Ctrl+Y for redo
    if (e.ctrlKey && e.key === 'y') {
      e.preventDefault();
      UndoManager.redo();
      return;
    }
  };

  window.addEventListener('keydown', handleKeyDown);
  return () => window.removeEventListener('keydown', handleKeyDown);
}

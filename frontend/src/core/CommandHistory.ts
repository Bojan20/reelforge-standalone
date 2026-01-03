/**
 * CommandHistory - Granular Undo/Redo System
 *
 * Implements the Command pattern for full undo/redo support:
 * - Granular operations (each parameter change is undoable)
 * - Command merging (rapid changes merged into single undo step)
 * - Batched commands (group related changes)
 * - History limits (prevent memory bloat)
 * - Persistence (optional save/restore)
 *
 * @module core/CommandHistory
 */

// ============ Types ============

export interface Command {
  /** Unique command ID */
  id: string;
  /** Human-readable description */
  description: string;
  /** Execute the command */
  execute: () => void;
  /** Undo the command */
  undo: () => void;
  /** Timestamp when created */
  timestamp: number;
  /** Command type for merging */
  type?: string;
  /** Target ID for merging (e.g., clip ID, bus ID) */
  targetId?: string;
  /** Whether this command can be merged with similar commands */
  mergeable?: boolean;
}

export interface CommandHistoryConfig {
  /** Maximum history size (default: 100) */
  maxHistorySize: number;
  /** Time window for merging similar commands in ms (default: 300) */
  mergeWindowMs: number;
  /** Enable debug logging */
  debug: boolean;
}

export interface CommandHistoryState {
  /** Can undo */
  canUndo: boolean;
  /** Can redo */
  canRedo: boolean;
  /** Undo stack size */
  undoCount: number;
  /** Redo stack size */
  redoCount: number;
  /** Last command description */
  lastCommand: string | null;
}

// ============ Default Config ============

const DEFAULT_CONFIG: CommandHistoryConfig = {
  maxHistorySize: 100,
  mergeWindowMs: 300,
  debug: false,
};

// ============ Command History ============

export class CommandHistory {
  private undoStack: Command[] = [];
  private redoStack: Command[] = [];
  private config: CommandHistoryConfig;
  private batchInProgress: Command[] | null = null;
  private batchDescription: string | null = null;
  private listeners: Set<(state: CommandHistoryState) => void> = new Set();
  private idCounter = 0;

  constructor(config: Partial<CommandHistoryConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * Execute a command and add to history.
   */
  execute(command: Omit<Command, 'id' | 'timestamp'>): void {
    const fullCommand: Command = {
      ...command,
      id: `cmd-${++this.idCounter}`,
      timestamp: Date.now(),
    };

    // Execute the command
    fullCommand.execute();

    // If batching, add to batch
    if (this.batchInProgress) {
      this.batchInProgress.push(fullCommand);
      this.log(`Batched: ${fullCommand.description}`);
      return;
    }

    // Check for merge opportunity
    if (this.shouldMerge(fullCommand)) {
      const last = this.undoStack[this.undoStack.length - 1];
      // Update the last command's execute to include this one
      const originalUndo = last.undo;
      last.undo = () => {
        fullCommand.undo();
        originalUndo();
      };
      last.timestamp = fullCommand.timestamp;
      last.description = fullCommand.description;
      this.log(`Merged: ${fullCommand.description}`);
    } else {
      // Add to undo stack
      this.undoStack.push(fullCommand);
      this.log(`Executed: ${fullCommand.description}`);
    }

    // Clear redo stack (new action invalidates redo history)
    this.redoStack = [];

    // Enforce history limit
    while (this.undoStack.length > this.config.maxHistorySize) {
      this.undoStack.shift();
    }

    this.notifyListeners();
  }

  /**
   * Undo the last command.
   */
  undo(): boolean {
    const command = this.undoStack.pop();
    if (!command) return false;

    command.undo();
    this.redoStack.push(command);

    this.log(`Undone: ${command.description}`);
    this.notifyListeners();
    return true;
  }

  /**
   * Redo the last undone command.
   */
  redo(): boolean {
    const command = this.redoStack.pop();
    if (!command) return false;

    command.execute();
    this.undoStack.push(command);

    this.log(`Redone: ${command.description}`);
    this.notifyListeners();
    return true;
  }

  /**
   * Start a batch of commands.
   * All commands until endBatch() are grouped as one undo step.
   */
  beginBatch(description: string): void {
    if (this.batchInProgress) {
      console.warn('[CommandHistory] Batch already in progress');
      return;
    }
    this.batchInProgress = [];
    this.batchDescription = description;
    this.log(`Batch started: ${description}`);
  }

  /**
   * End the current batch.
   */
  endBatch(): void {
    if (!this.batchInProgress) {
      console.warn('[CommandHistory] No batch in progress');
      return;
    }

    const commands = this.batchInProgress;
    const description = this.batchDescription || 'Batch operation';
    this.batchInProgress = null;
    this.batchDescription = null;

    if (commands.length === 0) {
      this.log('Batch ended (empty)');
      return;
    }

    // Create a composite command
    const batchCommand: Command = {
      id: `batch-${++this.idCounter}`,
      description,
      timestamp: Date.now(),
      execute: () => {
        for (const cmd of commands) {
          cmd.execute();
        }
      },
      undo: () => {
        // Undo in reverse order
        for (let i = commands.length - 1; i >= 0; i--) {
          commands[i].undo();
        }
      },
    };

    this.undoStack.push(batchCommand);
    this.redoStack = [];

    this.log(`Batch ended: ${description} (${commands.length} commands)`);
    this.notifyListeners();
  }

  /**
   * Cancel the current batch (discard all batched commands).
   */
  cancelBatch(): void {
    if (!this.batchInProgress) return;

    // Undo all batched commands in reverse
    for (let i = this.batchInProgress.length - 1; i >= 0; i--) {
      this.batchInProgress[i].undo();
    }

    this.batchInProgress = null;
    this.batchDescription = null;
    this.log('Batch cancelled');
  }

  /**
   * Get current state.
   */
  getState(): CommandHistoryState {
    return {
      canUndo: this.undoStack.length > 0,
      canRedo: this.redoStack.length > 0,
      undoCount: this.undoStack.length,
      redoCount: this.redoStack.length,
      lastCommand: this.undoStack.length > 0
        ? this.undoStack[this.undoStack.length - 1].description
        : null,
    };
  }

  /**
   * Subscribe to state changes.
   */
  subscribe(listener: (state: CommandHistoryState) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Clear all history.
   */
  clear(): void {
    this.undoStack = [];
    this.redoStack = [];
    this.batchInProgress = null;
    this.batchDescription = null;
    this.notifyListeners();
  }

  /**
   * Get undo stack descriptions (for UI).
   */
  getUndoDescriptions(limit = 10): string[] {
    return this.undoStack
      .slice(-limit)
      .reverse()
      .map(cmd => cmd.description);
  }

  /**
   * Get redo stack descriptions (for UI).
   */
  getRedoDescriptions(limit = 10): string[] {
    return this.redoStack
      .slice(-limit)
      .reverse()
      .map(cmd => cmd.description);
  }

  // ============ Private Methods ============

  private shouldMerge(newCommand: Command): boolean {
    if (!newCommand.mergeable) return false;
    if (this.undoStack.length === 0) return false;

    const last = this.undoStack[this.undoStack.length - 1];
    if (!last.mergeable) return false;
    if (last.type !== newCommand.type) return false;
    if (last.targetId !== newCommand.targetId) return false;

    // Check time window
    const timeDiff = newCommand.timestamp - last.timestamp;
    return timeDiff < this.config.mergeWindowMs;
  }

  private notifyListeners(): void {
    const state = this.getState();
    for (const listener of this.listeners) {
      listener(state);
    }
  }

  private log(message: string): void {
    if (this.config.debug) {
      console.log(`[CommandHistory] ${message}`);
    }
  }
}

// ============ Command Factories ============

/**
 * Create a command for changing a value.
 */
export function createValueCommand<T>(
  description: string,
  getCurrentValue: () => T,
  setValue: (value: T) => void,
  newValue: T,
  options: {
    type?: string;
    targetId?: string;
    mergeable?: boolean;
  } = {}
): Omit<Command, 'id' | 'timestamp'> {
  const oldValue = getCurrentValue();

  return {
    description,
    execute: () => setValue(newValue),
    undo: () => setValue(oldValue),
    type: options.type,
    targetId: options.targetId,
    mergeable: options.mergeable ?? true,
  };
}

/**
 * Create a command for adding an item to an array.
 */
export function createAddCommand<T>(
  description: string,
  getArray: () => T[],
  setArray: (arr: T[]) => void,
  item: T,
  options: { targetId?: string } = {}
): Omit<Command, 'id' | 'timestamp'> {
  return {
    description,
    execute: () => setArray([...getArray(), item]),
    undo: () => {
      const arr = getArray();
      setArray(arr.slice(0, -1));
    },
    type: 'add',
    targetId: options.targetId,
  };
}

/**
 * Create a command for removing an item from an array.
 */
export function createRemoveCommand<T>(
  description: string,
  getArray: () => T[],
  setArray: (arr: T[]) => void,
  index: number,
  options: { targetId?: string } = {}
): Omit<Command, 'id' | 'timestamp'> {
  let removedItem: T;
  let removedIndex: number;

  return {
    description,
    execute: () => {
      const arr = getArray();
      removedItem = arr[index];
      removedIndex = index;
      setArray(arr.filter((_, i) => i !== index));
    },
    undo: () => {
      const arr = getArray();
      const newArr = [...arr];
      newArr.splice(removedIndex, 0, removedItem);
      setArray(newArr);
    },
    type: 'remove',
    targetId: options.targetId,
  };
}

/**
 * Create a command for moving an item in an array.
 */
export function createMoveCommand<T>(
  description: string,
  getArray: () => T[],
  setArray: (arr: T[]) => void,
  fromIndex: number,
  toIndex: number,
  options: { targetId?: string } = {}
): Omit<Command, 'id' | 'timestamp'> {
  return {
    description,
    execute: () => {
      const arr = [...getArray()];
      const [item] = arr.splice(fromIndex, 1);
      arr.splice(toIndex, 0, item);
      setArray(arr);
    },
    undo: () => {
      const arr = [...getArray()];
      const [item] = arr.splice(toIndex, 1);
      arr.splice(fromIndex, 0, item);
      setArray(arr);
    },
    type: 'move',
    targetId: options.targetId,
  };
}

// ============ Singleton Instance ============

let globalHistory: CommandHistory | null = null;

export function getCommandHistory(): CommandHistory {
  if (!globalHistory) {
    globalHistory = new CommandHistory({ debug: process.env.NODE_ENV === 'development' });
  }
  return globalHistory;
}

export default CommandHistory;

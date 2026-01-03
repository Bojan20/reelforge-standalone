/**
 * Undo System Tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  UndoManager,
  createPropertyCommand,
  createArrayPushCommand,
  createArrayRemoveCommand,
  createCompositeCommand,
  type UndoableCommand,
} from '../undoSystem';

describe('UndoManager', () => {
  beforeEach(() => {
    UndoManager.clear();
  });

  describe('basic operations', () => {
    it('should start with empty history', () => {
      expect(UndoManager.canUndo()).toBe(false);
      expect(UndoManager.canRedo()).toBe(false);
    });

    it('should execute and track commands', () => {
      let value = 0;
      const command: UndoableCommand = {
        execute: () => { value = 1; },
        undo: () => { value = 0; },
        description: 'Set value to 1',
      };

      UndoManager.execute(command);

      expect(value).toBe(1);
      expect(UndoManager.canUndo()).toBe(true);
      expect(UndoManager.canRedo()).toBe(false);
    });

    it('should undo commands', () => {
      let value = 0;
      const command: UndoableCommand = {
        execute: () => { value = 1; },
        undo: () => { value = 0; },
        description: 'Set value to 1',
      };

      UndoManager.execute(command);
      UndoManager.undo();

      expect(value).toBe(0);
      expect(UndoManager.canUndo()).toBe(false);
      expect(UndoManager.canRedo()).toBe(true);
    });

    it('should redo commands', () => {
      let value = 0;
      const command: UndoableCommand = {
        execute: () => { value = 1; },
        undo: () => { value = 0; },
        description: 'Set value to 1',
      };

      UndoManager.execute(command);
      UndoManager.undo();
      UndoManager.redo();

      expect(value).toBe(1);
      expect(UndoManager.canUndo()).toBe(true);
      expect(UndoManager.canRedo()).toBe(false);
    });

    it('should clear redo stack on new command', () => {
      let value = 0;
      const cmd1: UndoableCommand = {
        execute: () => { value = 1; },
        undo: () => { value = 0; },
        description: 'Set to 1',
      };
      const cmd2: UndoableCommand = {
        execute: () => { value = 2; },
        undo: () => { value = 1; },
        description: 'Set to 2',
      };

      UndoManager.execute(cmd1);
      UndoManager.undo();
      expect(UndoManager.canRedo()).toBe(true);

      UndoManager.execute(cmd2);
      expect(UndoManager.canRedo()).toBe(false);
      expect(value).toBe(2);
    });
  });

  describe('command factories', () => {
    it('createPropertyCommand should work', () => {
      const obj = { name: 'original' };
      const command = createPropertyCommand(obj, 'name', 'updated');

      command.execute();
      expect(obj.name).toBe('updated');

      command.undo();
      expect(obj.name).toBe('original');
    });

    it('createArrayPushCommand should work', () => {
      const arr = [1, 2, 3];
      const command = createArrayPushCommand(arr, 4);

      command.execute();
      expect(arr).toEqual([1, 2, 3, 4]);

      command.undo();
      expect(arr).toEqual([1, 2, 3]);
    });

    it('createArrayRemoveCommand should work', () => {
      const arr = [1, 2, 3, 4];
      const command = createArrayRemoveCommand(arr, 2);

      command.execute();
      expect(arr).toEqual([1, 2, 4]);

      command.undo();
      expect(arr).toEqual([1, 2, 3, 4]);
    });

    it('createCompositeCommand should work', () => {
      const obj = { a: 1, b: 2 };
      const composite = createCompositeCommand([
        createPropertyCommand(obj, 'a', 10),
        createPropertyCommand(obj, 'b', 20),
      ], 'Update both');

      composite.execute();
      expect(obj).toEqual({ a: 10, b: 20 });

      composite.undo();
      expect(obj).toEqual({ a: 1, b: 2 });
    });
  });

  describe('history limits', () => {
    it('should handle many commands without error', () => {
      // Execute many commands to test stability
      for (let i = 0; i < 150; i++) {
        UndoManager.execute({
          execute: () => {},
          undo: () => {},
          description: `Command ${i}`,
        });
      }

      // Should still be able to undo
      expect(UndoManager.canUndo()).toBe(true);
    });
  });

  describe('event notifications', () => {
    it('should notify subscribers on changes', () => {
      let notifyCount = 0;
      const unsubscribe = UndoManager.subscribe(() => {
        notifyCount++;
      });

      UndoManager.execute({
        execute: () => {},
        undo: () => {},
        description: 'Test',
      });

      expect(notifyCount).toBe(1);

      UndoManager.undo();
      expect(notifyCount).toBe(2);

      unsubscribe();

      UndoManager.redo();
      expect(notifyCount).toBe(2); // No more notifications
    });
  });
});

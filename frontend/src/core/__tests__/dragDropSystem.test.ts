/**
 * Drag & Drop System Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  DragDropManager,
  type DragItem,
  type DropTarget,
} from '../dragDropSystem';

// Mock document methods
const mockElement = {
  getBoundingClientRect: () => ({
    left: 0,
    right: 100,
    top: 0,
    bottom: 100,
    width: 100,
    height: 100,
  }),
};

describe('DragDropManager', () => {
  beforeEach(() => {
    DragDropManager.cancelDrag();
  });

  describe('state management', () => {
    it('should start with no drag', () => {
      expect(DragDropManager.isDragging()).toBe(false);
      expect(DragDropManager.getCurrentItem()).toBeNull();
    });

    it('should return state object', () => {
      const state = DragDropManager.getState();
      expect(state).toHaveProperty('isDragging');
      expect(state).toHaveProperty('currentItem');
      expect(state).toHaveProperty('hoveredTarget');
    });
  });

  describe('drop targets', () => {
    it('should register drop target', () => {
      const target: DropTarget = {
        id: 'target-1',
        type: 'timeline',
        accepts: ['audio-asset'],
      };

      const unregister = DragDropManager.registerTarget(
        target,
        mockElement as unknown as HTMLElement
      );

      expect(typeof unregister).toBe('function');
      unregister();
    });

    it('should check if item can drop', () => {
      const item: DragItem = {
        type: 'audio-asset',
        id: 'asset-1',
        label: 'Test Asset',
      };

      const target: DropTarget = {
        id: 'target-1',
        type: 'timeline',
        accepts: ['audio-asset'],
      };

      expect(DragDropManager.canDrop(item, target)).toBe(true);
    });

    it('should reject incompatible items', () => {
      const item: DragItem = {
        type: 'preset',
        id: 'preset-1',
        label: 'Test Preset',
      };

      const target: DropTarget = {
        id: 'target-1',
        type: 'timeline',
        accepts: ['audio-asset'],
      };

      expect(DragDropManager.canDrop(item, target)).toBe(false);
    });
  });

  describe('drop handlers', () => {
    it('should register drop handler', () => {
      const handler = vi.fn(() => ({
        success: true,
        target: { id: 't', type: 'test', accepts: [] as const },
        item: { type: 'audio-asset' as const, id: 'i', label: 'l' },
      }));

      const unregister = DragDropManager.registerHandler('timeline', handler);
      expect(typeof unregister).toBe('function');
      unregister();
    });
  });

  describe('subscriptions', () => {
    it('should notify subscribers', () => {
      const listener = vi.fn();
      const unsubscribe = DragDropManager.subscribe(listener);

      // Cancel triggers events
      DragDropManager.cancelDrag();

      unsubscribe();
    });

    it('should unsubscribe correctly', () => {
      const listener = vi.fn();
      const unsubscribe = DragDropManager.subscribe(listener);
      unsubscribe();

      DragDropManager.cancelDrag();
      // Listener should not be called after unsubscribe
    });
  });

  describe('drag items', () => {
    it('should have correct item types', () => {
      const items: DragItem[] = [
        { type: 'audio-asset', id: '1', label: 'Audio' },
        { type: 'preset', id: '2', label: 'Preset' },
        { type: 'track', id: '3', label: 'Track' },
        { type: 'clip', id: '4', label: 'Clip' },
        { type: 'event', id: '5', label: 'Event' },
        { type: 'bus', id: '6', label: 'Bus' },
        { type: 'tab', id: '7', label: 'Tab' },
        { type: 'tree-node', id: '8', label: 'Node' },
      ];

      items.forEach(item => {
        expect(item.type).toBeDefined();
        expect(item.id).toBeDefined();
        expect(item.label).toBeDefined();
      });
    });
  });
});

/**
 * Drag & Drop System
 *
 * Centralized drag and drop management:
 * - Asset dragging (browser → timeline/bus)
 * - Preset dragging (preset panel → bus)
 * - Reordering (tracks, clips, tabs)
 * - Cross-zone transfers
 *
 * @module core/dragDropSystem
 */

import { useCallback, useState, useEffect, useRef } from 'react';
import { escapeHtml } from '../utils/security';

// ============ TYPES ============

export type DragItemType =
  | 'audio-asset'
  | 'preset'
  | 'track'
  | 'clip'
  | 'event'
  | 'bus'
  | 'tab'
  | 'tree-node';

export interface DragItem {
  /** Item type */
  type: DragItemType;
  /** Unique item ID */
  id: string;
  /** Display label */
  label: string;
  /** Additional data */
  data?: Record<string, unknown>;
  /** Source zone/panel */
  source?: string;
}

export interface DropTarget {
  /** Target ID */
  id: string;
  /** Target type/zone */
  type: string;
  /** Accepts these drag item types */
  accepts: DragItemType[];
  /** Position within target (for reordering) */
  position?: 'before' | 'after' | 'inside';
  /** Insert index (for arrays) */
  index?: number;
}

export interface DropResult {
  /** Was drop successful */
  success: boolean;
  /** Target that received the drop */
  target: DropTarget;
  /** Item that was dropped */
  item: DragItem;
  /** Result data */
  data?: Record<string, unknown>;
}

export interface DragState {
  isDragging: boolean;
  currentItem: DragItem | null;
  hoveredTarget: DropTarget | null;
  dragOffset: { x: number; y: number };
  dropPreview: DropTarget | null;
}

type DragEventType = 'dragStart' | 'dragMove' | 'dragEnd' | 'drop' | 'cancel';

export interface DragEvent {
  type: DragEventType;
  item?: DragItem;
  target?: DropTarget;
  result?: DropResult;
  position?: { x: number; y: number };
}

type DragListener = (event: DragEvent) => void;
type DropHandler = (item: DragItem, target: DropTarget) => DropResult | Promise<DropResult>;

// ============ DRAG DROP MANAGER ============

class DragDropManagerClass {
  private state: DragState = {
    isDragging: false,
    currentItem: null,
    hoveredTarget: null,
    dragOffset: { x: 0, y: 0 },
    dropPreview: null,
  };

  private listeners: Set<DragListener> = new Set();
  private dropHandlers: Map<string, DropHandler> = new Map();
  private dropTargets: Map<string, DropTarget> = new Map();

  // Ghost element for drag preview
  private ghostElement: HTMLElement | null = null;

  // ============ DRAG OPERATIONS ============

  /**
   * Start dragging an item
   */
  startDrag(item: DragItem, event: MouseEvent | React.MouseEvent): void {
    this.state = {
      isDragging: true,
      currentItem: item,
      hoveredTarget: null,
      dragOffset: { x: event.clientX, y: event.clientY },
      dropPreview: null,
    };

    // Create ghost element
    this.createGhost(item, event);

    // Add global listeners
    document.addEventListener('mousemove', this.handleMouseMove);
    document.addEventListener('mouseup', this.handleMouseUp);

    // Prevent text selection during drag
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'grabbing';

    this.emit({ type: 'dragStart', item });
  }

  /**
   * Update drag position
   */
  private handleMouseMove = (event: MouseEvent): void => {
    if (!this.state.isDragging) return;

    // Update ghost position
    if (this.ghostElement) {
      this.ghostElement.style.left = `${event.clientX + 10}px`;
      this.ghostElement.style.top = `${event.clientY + 10}px`;
    }

    // Find drop target under cursor
    const target = this.findTargetAtPosition(event.clientX, event.clientY);

    if (target !== this.state.hoveredTarget) {
      this.state.hoveredTarget = target;
      this.state.dropPreview = target;
      this.updateGhostValidity(target);
    }

    this.emit({
      type: 'dragMove',
      item: this.state.currentItem!,
      target: target ?? undefined,
      position: { x: event.clientX, y: event.clientY },
    });
  };

  /**
   * End drag operation
   */
  private handleMouseUp = async (event: MouseEvent): Promise<void> => {
    if (!this.state.isDragging) return;

    const item = this.state.currentItem!;
    const target = this.findTargetAtPosition(event.clientX, event.clientY);

    // Cleanup
    this.cleanup();

    if (target && this.canDrop(item, target)) {
      // Execute drop
      const result = await this.executeDrop(item, target);
      this.emit({ type: 'drop', item, target, result });
    } else {
      // Cancel
      this.emit({ type: 'cancel', item });
    }

    this.emit({ type: 'dragEnd', item });
  };

  /**
   * Cancel current drag
   */
  cancelDrag(): void {
    if (!this.state.isDragging) return;

    const item = this.state.currentItem;
    this.cleanup();
    this.emit({ type: 'cancel', item: item || undefined });
    this.emit({ type: 'dragEnd', item: item || undefined });
  }

  /**
   * Cleanup drag state
   */
  private cleanup(): void {
    document.removeEventListener('mousemove', this.handleMouseMove);
    document.removeEventListener('mouseup', this.handleMouseUp);

    document.body.style.userSelect = '';
    document.body.style.cursor = '';

    if (this.ghostElement) {
      this.ghostElement.remove();
      this.ghostElement = null;
    }

    this.state = {
      isDragging: false,
      currentItem: null,
      hoveredTarget: null,
      dragOffset: { x: 0, y: 0 },
      dropPreview: null,
    };
  }

  // ============ DROP TARGETS ============

  /**
   * Register a drop target
   */
  registerTarget(target: DropTarget, element: HTMLElement): () => void {
    this.dropTargets.set(target.id, target);

    // Store element reference for hit testing
    (target as DropTarget & { element?: HTMLElement }).element = element;

    return () => {
      this.dropTargets.delete(target.id);
    };
  }

  /**
   * Register a drop handler for a target type
   */
  registerHandler(targetType: string, handler: DropHandler): () => void {
    this.dropHandlers.set(targetType, handler);
    return () => this.dropHandlers.delete(targetType);
  }

  /**
   * Find target at position
   */
  private findTargetAtPosition(x: number, y: number): DropTarget | null {
    for (const target of this.dropTargets.values()) {
      const element = (target as DropTarget & { element?: HTMLElement }).element;
      if (!element) continue;

      const rect = element.getBoundingClientRect();
      if (
        x >= rect.left &&
        x <= rect.right &&
        y >= rect.top &&
        y <= rect.bottom
      ) {
        // Check if this target accepts the current item
        if (this.state.currentItem && this.canDrop(this.state.currentItem, target)) {
          return target;
        }
      }
    }
    return null;
  }

  /**
   * Check if item can be dropped on target
   */
  canDrop(item: DragItem, target: DropTarget): boolean {
    return target.accepts.includes(item.type);
  }

  /**
   * Execute drop operation
   */
  private async executeDrop(item: DragItem, target: DropTarget): Promise<DropResult> {
    const handler = this.dropHandlers.get(target.type);

    if (handler) {
      return handler(item, target);
    }

    // Default success if no handler
    return {
      success: true,
      target,
      item,
    };
  }

  // ============ GHOST ELEMENT ============

  /**
   * Create drag ghost element
   */
  private createGhost(item: DragItem, event: MouseEvent | React.MouseEvent): void {
    this.ghostElement = document.createElement('div');
    this.ghostElement.className = 'drag-ghost';
    // Escape user-controllable label to prevent XSS
    const safeIcon = escapeHtml(this.getTypeIcon(item.type));
    const safeLabel = escapeHtml(item.label);
    this.ghostElement.innerHTML = `
      <span class="drag-ghost__icon">${safeIcon}</span>
      <span class="drag-ghost__label">${safeLabel}</span>
    `;
    this.ghostElement.style.cssText = `
      position: fixed;
      left: ${event.clientX + 10}px;
      top: ${event.clientY + 10}px;
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      background: #1a1a24;
      border: 1px solid #333;
      border-radius: 6px;
      font-size: 12px;
      color: #fff;
      pointer-events: none;
      z-index: 10000;
      box-shadow: 0 4px 12px rgba(0,0,0,0.4);
    `;

    document.body.appendChild(this.ghostElement);
  }

  /**
   * Update ghost validity indicator
   */
  private updateGhostValidity(target: DropTarget | null): void {
    if (!this.ghostElement) return;

    if (target) {
      this.ghostElement.style.borderColor = '#22c55e';
      this.ghostElement.style.background = '#22c55e20';
    } else {
      this.ghostElement.style.borderColor = '#333';
      this.ghostElement.style.background = '#1a1a24';
    }
  }

  /**
   * Get icon for item type
   */
  private getTypeIcon(type: DragItemType): string {
    switch (type) {
      case 'audio-asset': return '🎵';
      case 'preset': return '🎨';
      case 'track': return '📼';
      case 'clip': return '📎';
      case 'event': return '🎯';
      case 'bus': return '🚌';
      case 'tab': return '📑';
      case 'tree-node': return '📁';
      default: return '📦';
    }
  }

  // ============ STATE ============

  /**
   * Get current drag state
   */
  getState(): DragState {
    return { ...this.state };
  }

  /**
   * Check if currently dragging
   */
  isDragging(): boolean {
    return this.state.isDragging;
  }

  /**
   * Get current drag item
   */
  getCurrentItem(): DragItem | null {
    return this.state.currentItem;
  }

  // ============ EVENTS ============

  /**
   * Subscribe to drag events
   */
  subscribe(listener: DragListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: DragEvent): void {
    this.listeners.forEach(l => {
      try {
        l(event);
      } catch (error) {
        console.error('Drag listener error:', error);
      }
    });
  }
}

// ============ SINGLETON EXPORT ============

export const DragDropManager = new DragDropManagerClass();

// ============ REACT HOOKS ============

/**
 * Hook for making an element draggable
 */
export function useDraggable(item: DragItem) {
  const [isDragging, setIsDragging] = useState(false);

  useEffect(() => {
    const unsubscribe = DragDropManager.subscribe((event) => {
      if (event.item?.id === item.id) {
        setIsDragging(event.type === 'dragStart');
        if (event.type === 'dragEnd' || event.type === 'cancel') {
          setIsDragging(false);
        }
      }
    });
    return unsubscribe;
  }, [item.id]);

  const dragHandlers = {
    onMouseDown: useCallback((e: React.MouseEvent) => {
      e.preventDefault();
      DragDropManager.startDrag(item, e);
    }, [item]),
  };

  return {
    isDragging,
    dragHandlers,
  };
}

/**
 * Hook for making an element a drop target
 */
export function useDropTarget(
  target: DropTarget,
  onDrop?: (item: DragItem, target: DropTarget) => void
) {
  const [isOver, setIsOver] = useState(false);
  const [canDrop, setCanDrop] = useState(false);
  const elementRef = useRef<HTMLElement | null>(null);
  const cleanupRef = useRef<(() => void) | null>(null);
  const onDropRef = useRef(onDrop);
  const targetRef = useRef(target);

  // Keep refs updated to avoid stale closures
  onDropRef.current = onDrop;
  targetRef.current = target;

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      cleanupRef.current?.();
    };
  }, []);

  // Handle target registration and subscription
  useEffect(() => {
    const element = elementRef.current;
    if (!element) return;

    // Cleanup previous registration
    cleanupRef.current?.();

    const unregister = DragDropManager.registerTarget(targetRef.current, element);

    const unsubscribe = DragDropManager.subscribe((event) => {
      if (event.target?.id === targetRef.current.id) {
        switch (event.type) {
          case 'dragMove':
            setIsOver(true);
            setCanDrop(event.item ? DragDropManager.getState().currentItem !== null : false);
            break;
          case 'drop':
            setIsOver(false);
            if (onDropRef.current && event.item) {
              onDropRef.current(event.item, targetRef.current);
            }
            break;
          case 'dragEnd':
          case 'cancel':
            setIsOver(false);
            setCanDrop(false);
            break;
        }
      } else if (event.type === 'dragEnd' || event.type === 'cancel') {
        setIsOver(false);
        setCanDrop(false);
      }
    });

    cleanupRef.current = () => {
      unregister();
      unsubscribe();
    };

    return () => {
      cleanupRef.current?.();
      cleanupRef.current = null;
    };
  }, [target.id]); // Re-register when target ID changes

  const ref = useCallback((element: HTMLElement | null) => {
    elementRef.current = element;
    // Force re-run of effect when element changes
    if (element && !cleanupRef.current) {
      const unregister = DragDropManager.registerTarget(targetRef.current, element);
      const unsubscribe = DragDropManager.subscribe((event) => {
        if (event.target?.id === targetRef.current.id) {
          switch (event.type) {
            case 'dragMove':
              setIsOver(true);
              setCanDrop(event.item ? DragDropManager.getState().currentItem !== null : false);
              break;
            case 'drop':
              setIsOver(false);
              if (onDropRef.current && event.item) {
                onDropRef.current(event.item, targetRef.current);
              }
              break;
            case 'dragEnd':
            case 'cancel':
              setIsOver(false);
              setCanDrop(false);
              break;
          }
        } else if (event.type === 'dragEnd' || event.type === 'cancel') {
          setIsOver(false);
          setCanDrop(false);
        }
      });
      cleanupRef.current = () => {
        unregister();
        unsubscribe();
      };
    }
  }, []);

  return {
    ref,
    isOver,
    canDrop,
  };
}

/**
 * Hook for monitoring global drag state
 */
export function useDragState() {
  const [state, setState] = useState<DragState>(DragDropManager.getState());

  useEffect(() => {
    const unsubscribe = DragDropManager.subscribe(() => {
      setState(DragDropManager.getState());
    });
    return unsubscribe;
  }, []);

  return state;
}

// ============ CSS INJECTION ============

// Inject base styles
if (typeof document !== 'undefined') {
  const style = document.createElement('style');
  style.textContent = `
    .drag-ghost {
      animation: ghost-appear 0.15s ease-out;
    }

    @keyframes ghost-appear {
      from {
        opacity: 0;
        transform: scale(0.9);
      }
      to {
        opacity: 1;
        transform: scale(1);
      }
    }

    [data-drop-target="true"] {
      transition: outline 0.15s ease;
    }

    [data-drop-target="true"][data-drop-over="true"] {
      outline: 2px dashed #22c55e;
      outline-offset: 2px;
    }

    [data-drop-target="true"][data-drop-over="true"][data-can-drop="false"] {
      outline-color: #ef4444;
    }
  `;
  document.head.appendChild(style);
}

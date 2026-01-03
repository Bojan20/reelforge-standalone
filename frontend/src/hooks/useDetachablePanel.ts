/**
 * ReelForge useDetachablePanel Hook
 *
 * Generic hook for managing detachable/draggable panel state.
 * Extracts common drag/resize logic from EventsPage inspectors.
 *
 * Usage:
 * ```tsx
 * const panel = useDetachablePanel({
 *   initialPosition: { x: 100, y: 100 },
 *   initialSize: { width: 350, height: 600 },
 *   minSize: { width: 280, height: 300 }
 * });
 *
 * // In JSX:
 * <div
 *   style={{
 *     left: panel.position.x,
 *     top: panel.position.y,
 *     width: panel.size.width,
 *     height: panel.size.height,
 *   }}
 * >
 *   <div onMouseDown={panel.startDrag}>Drag Handle</div>
 *   <div onMouseDown={panel.startResize}>Resize Handle</div>
 * </div>
 * ```
 */

import { useState, useEffect, useCallback } from 'react';

export interface PanelPosition {
  x: number;
  y: number;
}

export interface PanelSize {
  width: number;
  height: number;
}

export interface UseDetachablePanelOptions {
  /** Initial position when detached */
  initialPosition?: PanelPosition;
  /** Initial size when detached */
  initialSize?: PanelSize;
  /** Minimum allowed size */
  minSize?: PanelSize;
  /** Whether panel starts detached */
  initialDetached?: boolean;
  /** Whether panel starts open */
  initialOpen?: boolean;
}

export interface UseDetachablePanelReturn {
  // State
  isOpen: boolean;
  isDetached: boolean;
  position: PanelPosition;
  size: PanelSize;
  isDragging: boolean;
  isResizing: boolean;

  // Actions
  setIsOpen: (open: boolean) => void;
  setIsDetached: (detached: boolean) => void;
  toggle: () => void;
  detach: () => void;
  attach: () => void;

  // Drag handlers
  startDrag: (e: React.MouseEvent) => void;
  startResize: (e: React.MouseEvent) => void;
}

const DEFAULT_POSITION: PanelPosition = { x: 100, y: 100 };
const DEFAULT_SIZE: PanelSize = { width: 350, height: 600 };
const DEFAULT_MIN_SIZE: PanelSize = { width: 280, height: 300 };

export function useDetachablePanel(
  options: UseDetachablePanelOptions = {}
): UseDetachablePanelReturn {
  const {
    initialPosition = DEFAULT_POSITION,
    initialSize = DEFAULT_SIZE,
    minSize = DEFAULT_MIN_SIZE,
    initialDetached = false,
    initialOpen = true,
  } = options;

  // Panel state
  const [isOpen, setIsOpen] = useState(initialOpen);
  const [isDetached, setIsDetached] = useState(initialDetached);
  const [position, setPosition] = useState<PanelPosition>(initialPosition);
  const [size, setSize] = useState<PanelSize>(initialSize);

  // Drag state
  const [isDragging, setIsDragging] = useState(false);
  const [dragOffset, setDragOffset] = useState<PanelPosition>({ x: 0, y: 0 });

  // Resize state
  const [isResizing, setIsResizing] = useState(false);
  const [resizeStartPos, setResizeStartPos] = useState<PanelPosition>({ x: 0, y: 0 });
  const [resizeStartSize, setResizeStartSize] = useState<PanelSize>({ width: 0, height: 0 });

  // Drag effect
  useEffect(() => {
    if (!isDragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      setPosition({
        x: e.clientX - dragOffset.x,
        y: e.clientY - dragOffset.y,
      });
    };

    const handleMouseUp = () => {
      setIsDragging(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, dragOffset]);

  // Resize effect
  useEffect(() => {
    if (!isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - resizeStartPos.x;
      const deltaY = e.clientY - resizeStartPos.y;

      setSize({
        width: Math.max(minSize.width, resizeStartSize.width + deltaX),
        height: Math.max(minSize.height, resizeStartSize.height + deltaY),
      });
    };

    const handleMouseUp = () => {
      setIsResizing(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isResizing, resizeStartPos, resizeStartSize, minSize]);

  // Actions
  const toggle = useCallback(() => {
    setIsOpen((prev) => !prev);
  }, []);

  const detach = useCallback(() => {
    setIsDetached(true);
  }, []);

  const attach = useCallback(() => {
    setIsDetached(false);
  }, []);

  // Drag handler
  const startDrag = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsDragging(true);
    setDragOffset({
      x: e.clientX - position.x,
      y: e.clientY - position.y,
    });
  }, [position]);

  // Resize handler
  const startResize = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    setResizeStartPos({ x: e.clientX, y: e.clientY });
    setResizeStartSize({ ...size });
  }, [size]);

  return {
    // State
    isOpen,
    isDetached,
    position,
    size,
    isDragging,
    isResizing,

    // Actions
    setIsOpen,
    setIsDetached,
    toggle,
    detach,
    attach,

    // Drag handlers
    startDrag,
    startResize,
  };
}

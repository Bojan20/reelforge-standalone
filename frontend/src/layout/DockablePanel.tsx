/**
 * ReelForge Dockable Panel System
 *
 * Professional panel management with:
 * - Detach to floating window
 * - Drag to reposition
 * - Dock to zones
 * - Resize handles
 * - Minimize/maximize
 *
 * @module layout/DockablePanel
 */

import { memo, useState, useCallback, useRef, useEffect, type ReactNode } from 'react';

// ============ Types ============

export interface DockablePanelProps {
  id: string;
  title: string;
  icon?: string;
  children: ReactNode;
  /** Initial docked state */
  initialDocked?: boolean;
  /** Initial position when floating */
  initialPosition?: { x: number; y: number };
  /** Initial size */
  initialSize?: { width: number; height: number };
  /** Minimum size */
  minSize?: { width: number; height: number };
  /** Can be closed */
  closable?: boolean;
  /** On close */
  onClose?: () => void;
  /** On dock state change */
  onDockChange?: (docked: boolean) => void;
  /** Z-index when floating */
  zIndex?: number;
  /** On focus (for z-index management) */
  onFocus?: () => void;
}

export interface PanelManagerState {
  panels: Map<string, {
    docked: boolean;
    position: { x: number; y: number };
    size: { width: number; height: number };
    minimized: boolean;
    zIndex: number;
  }>;
}

// ============ Dockable Panel Component ============

export const DockablePanel = memo(function DockablePanel({
  id,
  title,
  icon,
  children,
  initialDocked = true,
  initialPosition = { x: 100, y: 100 },
  initialSize = { width: 400, height: 300 },
  minSize = { width: 200, height: 150 },
  closable = true,
  onClose,
  onDockChange,
  zIndex = 1000,
  onFocus,
}: DockablePanelProps) {
  const [isDocked, setIsDocked] = useState(initialDocked);
  const [isMinimized, setIsMinimized] = useState(false);
  const [position, setPosition] = useState(initialPosition);
  const [size, setSize] = useState(initialSize);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [dragPending, setDragPending] = useState(false);

  const panelRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef({ x: 0, y: 0, posX: 0, posY: 0 });
  const resizeStartRef = useRef({ x: 0, y: 0, width: 0, height: 0 });
  const dragThreshold = 5; // pixels to move before drag starts

  // Detach panel to floating
  const handleDetach = useCallback(() => {
    setIsDocked(false);
    onDockChange?.(false);
  }, [onDockChange]);

  // Dock panel back
  const handleDock = useCallback(() => {
    setIsDocked(true);
    setIsMinimized(false);
    onDockChange?.(true);
  }, [onDockChange]);

  // Toggle minimize
  const handleMinimize = useCallback(() => {
    setIsMinimized((v) => !v);
  }, []);

  // Start dragging - uses threshold to allow double-click to work
  const handleDragStart = useCallback((e: React.MouseEvent) => {
    if (isDocked) return;
    // Don't prevent default here - allows double-click to fire
    setDragPending(true);
    onFocus?.();
    dragStartRef.current = {
      x: e.clientX,
      y: e.clientY,
      posX: position.x,
      posY: position.y,
    };
  }, [isDocked, position, onFocus]);

  // Start resizing
  const handleResizeStart = useCallback((e: React.MouseEvent, _direction: string) => {
    if (isDocked) return;
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    onFocus?.();
    resizeStartRef.current = {
      x: e.clientX,
      y: e.clientY,
      width: size.width,
      height: size.height,
    };
  }, [isDocked, size, onFocus]);

  // Handle mouse move for drag/resize
  useEffect(() => {
    if (!isDragging && !isResizing && !dragPending) return;

    const handleMouseMove = (e: MouseEvent) => {
      // Check if we should start dragging (threshold crossed)
      if (dragPending && !isDragging) {
        const deltaX = Math.abs(e.clientX - dragStartRef.current.x);
        const deltaY = Math.abs(e.clientY - dragStartRef.current.y);
        if (deltaX > dragThreshold || deltaY > dragThreshold) {
          setDragPending(false);
          setIsDragging(true);
        }
        return;
      }

      if (isDragging) {
        const deltaX = e.clientX - dragStartRef.current.x;
        const deltaY = e.clientY - dragStartRef.current.y;
        setPosition({
          x: Math.max(0, dragStartRef.current.posX + deltaX),
          y: Math.max(0, dragStartRef.current.posY + deltaY),
        });
      }
      if (isResizing) {
        const deltaX = e.clientX - resizeStartRef.current.x;
        const deltaY = e.clientY - resizeStartRef.current.y;
        setSize({
          width: Math.max(minSize.width, resizeStartRef.current.width + deltaX),
          height: Math.max(minSize.height, resizeStartRef.current.height + deltaY),
        });
      }
    };

    const handleMouseUp = () => {
      setIsDragging(false);
      setIsResizing(false);
      setDragPending(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, isResizing, dragPending, minSize, dragThreshold]);

  // Docked mode - render inline
  if (isDocked) {
    return (
      <div className="rf-dockable-panel rf-dockable-panel--docked" data-panel-id={id}>
        <div className="rf-dockable-panel__header">
          {icon && <span className="rf-dockable-panel__icon">{icon}</span>}
          <span className="rf-dockable-panel__title">{title}</span>
          <div className="rf-dockable-panel__actions">
            <button
              className="rf-dockable-panel__btn"
              onClick={handleDetach}
              title="Detach to floating window"
            >
              ⧉
            </button>
            {closable && (
              <button
                className="rf-dockable-panel__btn rf-dockable-panel__btn--close"
                onClick={onClose}
                title="Close"
              >
                ×
              </button>
            )}
          </div>
        </div>
        <div className="rf-dockable-panel__content">{children}</div>
      </div>
    );
  }

  // Floating mode - render as draggable window
  return (
    <div
      ref={panelRef}
      className={`rf-dockable-panel rf-dockable-panel--floating ${isMinimized ? 'minimized' : ''} ${isDragging ? 'dragging' : ''}`}
      data-panel-id={id}
      style={{
        left: position.x,
        top: position.y,
        width: isMinimized ? 200 : size.width,
        height: isMinimized ? 'auto' : size.height,
        zIndex,
      }}
      onMouseDown={onFocus}
    >
      {/* Title Bar */}
      <div
        className="rf-dockable-panel__header rf-dockable-panel__header--draggable"
        onMouseDown={handleDragStart}
        onDoubleClick={handleMinimize}
      >
        {icon && <span className="rf-dockable-panel__icon">{icon}</span>}
        <span className="rf-dockable-panel__title">{title}</span>
        <div className="rf-dockable-panel__actions">
          <button
            className="rf-dockable-panel__btn"
            onClick={handleMinimize}
            title={isMinimized ? 'Restore' : 'Minimize'}
          >
            {isMinimized ? '□' : '−'}
          </button>
          <button
            className="rf-dockable-panel__btn"
            onClick={handleDock}
            title="Dock panel"
          >
            ⊞
          </button>
          {closable && (
            <button
              className="rf-dockable-panel__btn rf-dockable-panel__btn--close"
              onClick={onClose}
              title="Close"
            >
              ×
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      {!isMinimized && (
        <div className="rf-dockable-panel__content">{children}</div>
      )}

      {/* Resize Handles */}
      {!isMinimized && (
        <>
          <div
            className="rf-dockable-panel__resize rf-dockable-panel__resize--se"
            onMouseDown={(e) => handleResizeStart(e, 'se')}
          />
          <div
            className="rf-dockable-panel__resize rf-dockable-panel__resize--e"
            onMouseDown={(e) => handleResizeStart(e, 'e')}
          />
          <div
            className="rf-dockable-panel__resize rf-dockable-panel__resize--s"
            onMouseDown={(e) => handleResizeStart(e, 's')}
          />
        </>
      )}
    </div>
  );
});

// ============ Panel Manager Hook ============

export function usePanelManager(initialPanels: string[] = []) {
  const [panelStates, setPanelStates] = useState<Map<string, {
    visible: boolean;
    docked: boolean;
    zIndex: number;
  }>>(() => {
    const map = new Map();
    initialPanels.forEach((id, i) => {
      map.set(id, { visible: true, docked: true, zIndex: 1000 + i });
    });
    return map;
  });

  const [topZIndex, setTopZIndex] = useState(1000 + initialPanels.length);

  const bringToFront = useCallback((id: string) => {
    setTopZIndex((z) => z + 1);
    setPanelStates((prev) => {
      const next = new Map(prev);
      const state = next.get(id);
      if (state) {
        next.set(id, { ...state, zIndex: topZIndex + 1 });
      }
      return next;
    });
  }, [topZIndex]);

  const togglePanel = useCallback((id: string) => {
    setPanelStates((prev) => {
      const next = new Map(prev);
      const state = next.get(id);
      if (state) {
        next.set(id, { ...state, visible: !state.visible });
      } else {
        next.set(id, { visible: true, docked: false, zIndex: topZIndex + 1 });
        setTopZIndex((z) => z + 1);
      }
      return next;
    });
  }, [topZIndex]);

  const setDocked = useCallback((id: string, docked: boolean) => {
    setPanelStates((prev) => {
      const next = new Map(prev);
      const state = next.get(id);
      if (state) {
        next.set(id, { ...state, docked });
      }
      return next;
    });
  }, []);

  const closePanel = useCallback((id: string) => {
    setPanelStates((prev) => {
      const next = new Map(prev);
      const state = next.get(id);
      if (state) {
        next.set(id, { ...state, visible: false });
      }
      return next;
    });
  }, []);

  return {
    panelStates,
    bringToFront,
    togglePanel,
    setDocked,
    closePanel,
    getZIndex: (id: string) => panelStates.get(id)?.zIndex ?? 1000,
    isVisible: (id: string) => panelStates.get(id)?.visible ?? false,
    isDocked: (id: string) => panelStates.get(id)?.docked ?? true,
  };
}

export default DockablePanel;

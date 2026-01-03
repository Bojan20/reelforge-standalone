/**
 * ReelForge Plugin Window
 *
 * Floating window for hosting plugin UIs.
 * Features:
 * - Draggable header
 * - Resizable
 * - Minimize/Maximize
 * - Close button
 * - Bypass toggle
 * - A/B comparison
 *
 * @module plugin-host/PluginWindow
 */

import { useState, useCallback, useRef } from 'react';
import './PluginWindow.css';

// ============ Types ============

export interface PluginWindowProps {
  /** Plugin ID */
  id: string;
  /** Plugin name */
  name: string;
  /** Plugin vendor */
  vendor?: string;
  /** Initial position */
  initialPosition?: { x: number; y: number };
  /** Initial size */
  initialSize?: { width: number; height: number };
  /** Is bypassed */
  bypassed?: boolean;
  /** On bypass toggle */
  onBypassToggle?: () => void;
  /** On close */
  onClose?: () => void;
  /** On position change */
  onPositionChange?: (position: { x: number; y: number }) => void;
  /** On size change */
  onSizeChange?: (size: { width: number; height: number }) => void;
  /** Children (plugin UI content) */
  children?: React.ReactNode;
  /** Z-index for stacking */
  zIndex?: number;
  /** On focus (bring to front) */
  onFocus?: () => void;
}

// ============ Component ============

export function PluginWindow({
  id: _id,
  name,
  vendor,
  initialPosition = { x: 100, y: 100 },
  initialSize = { width: 400, height: 300 },
  bypassed = false,
  onBypassToggle,
  onClose,
  onPositionChange,
  onSizeChange,
  children,
  zIndex = 100,
  onFocus,
}: PluginWindowProps) {
  const [position, setPosition] = useState(initialPosition);
  const [size, setSize] = useState(initialSize);
  const [isMinimized, setIsMinimized] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [abState, setAbState] = useState<'A' | 'B'>('A');

  const windowRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef({ x: 0, y: 0, posX: 0, posY: 0 });
  const resizeStartRef = useRef({ x: 0, y: 0, width: 0, height: 0 });

  // Drag handling
  const handleDragStart = useCallback(
    (e: React.MouseEvent) => {
      if ((e.target as HTMLElement).closest('.plugin-window__btn')) return;

      e.preventDefault();
      setIsDragging(true);
      onFocus?.();

      dragStartRef.current = {
        x: e.clientX,
        y: e.clientY,
        posX: position.x,
        posY: position.y,
      };

      const handleMouseMove = (e: MouseEvent) => {
        const deltaX = e.clientX - dragStartRef.current.x;
        const deltaY = e.clientY - dragStartRef.current.y;

        const newPos = {
          x: Math.max(0, dragStartRef.current.posX + deltaX),
          y: Math.max(0, dragStartRef.current.posY + deltaY),
        };

        setPosition(newPos);
        onPositionChange?.(newPos);
      };

      const handleMouseUp = () => {
        setIsDragging(false);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [position, onPositionChange, onFocus]
  );

  // Resize handling
  const handleResizeStart = useCallback(
    (e: React.MouseEvent) => {
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

      const handleMouseMove = (e: MouseEvent) => {
        const deltaX = e.clientX - resizeStartRef.current.x;
        const deltaY = e.clientY - resizeStartRef.current.y;

        const newSize = {
          width: Math.max(300, resizeStartRef.current.width + deltaX),
          height: Math.max(200, resizeStartRef.current.height + deltaY),
        };

        setSize(newSize);
        onSizeChange?.(newSize);
      };

      const handleMouseUp = () => {
        setIsResizing(false);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [size, onSizeChange, onFocus]
  );

  // Focus on click
  const handleWindowClick = useCallback(() => {
    onFocus?.();
  }, [onFocus]);

  // Toggle minimize
  const handleMinimize = useCallback(() => {
    setIsMinimized((prev) => !prev);
  }, []);

  // Toggle A/B
  const handleAbToggle = useCallback(() => {
    setAbState((prev) => (prev === 'A' ? 'B' : 'A'));
  }, []);

  return (
    <div
      ref={windowRef}
      className={`plugin-window ${isMinimized ? 'plugin-window--minimized' : ''} ${
        bypassed ? 'plugin-window--bypassed' : ''
      } ${isDragging ? 'plugin-window--dragging' : ''} ${
        isResizing ? 'plugin-window--resizing' : ''
      }`}
      style={{
        left: position.x,
        top: position.y,
        width: isMinimized ? 300 : size.width,
        height: isMinimized ? 'auto' : size.height,
        zIndex,
      }}
      onClick={handleWindowClick}
    >
      {/* Header */}
      <div
        className="plugin-window__header"
        onMouseDown={handleDragStart}
      >
        <div className="plugin-window__title">
          <span className="plugin-window__name">{name}</span>
          {vendor && (
            <span className="plugin-window__vendor">{vendor}</span>
          )}
        </div>

        <div className="plugin-window__controls">
          {/* A/B Toggle */}
          <button
            className={`plugin-window__btn plugin-window__btn--ab ${
              abState === 'B' ? 'active' : ''
            }`}
            onClick={handleAbToggle}
            title="A/B Compare"
          >
            {abState}
          </button>

          {/* Bypass */}
          <button
            className={`plugin-window__btn plugin-window__btn--bypass ${
              bypassed ? 'active' : ''
            }`}
            onClick={onBypassToggle}
            title="Bypass"
          >
            BP
          </button>

          {/* Minimize */}
          <button
            className="plugin-window__btn plugin-window__btn--minimize"
            onClick={handleMinimize}
            title={isMinimized ? 'Expand' : 'Minimize'}
          >
            {isMinimized ? '▢' : '−'}
          </button>

          {/* Close */}
          <button
            className="plugin-window__btn plugin-window__btn--close"
            onClick={onClose}
            title="Close"
          >
            ×
          </button>
        </div>
      </div>

      {/* Content */}
      {!isMinimized && (
        <div className="plugin-window__content">
          {children}
        </div>
      )}

      {/* Resize Handle */}
      {!isMinimized && (
        <div
          className="plugin-window__resize-handle"
          onMouseDown={handleResizeStart}
        />
      )}
    </div>
  );
}

export default PluginWindow;

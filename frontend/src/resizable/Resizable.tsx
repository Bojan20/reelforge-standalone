/**
 * ReelForge Resizable
 *
 * Resizable panel:
 * - Drag to resize
 * - Min/max constraints
 * - Direction control
 *
 * @module resizable/Resizable
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import './Resizable.css';

// ============ Types ============

export type ResizeDirection = 'horizontal' | 'vertical' | 'both';
export type ResizeHandle = 'right' | 'bottom' | 'left' | 'top' | 'corner';

export interface ResizableProps {
  /** Initial width */
  defaultWidth?: number;
  /** Initial height */
  defaultHeight?: number;
  /** Min width */
  minWidth?: number;
  /** Max width */
  maxWidth?: number;
  /** Min height */
  minHeight?: number;
  /** Max height */
  maxHeight?: number;
  /** Resize direction */
  direction?: ResizeDirection;
  /** Handle position */
  handles?: ResizeHandle[];
  /** On resize */
  onResize?: (width: number, height: number) => void;
  /** On resize end */
  onResizeEnd?: (width: number, height: number) => void;
  /** Children */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Resizable({
  defaultWidth,
  defaultHeight,
  minWidth = 100,
  maxWidth = Infinity,
  minHeight = 100,
  maxHeight = Infinity,
  direction = 'both',
  handles = ['right', 'bottom', 'corner'],
  onResize,
  onResizeEnd,
  children,
  className = '',
}: ResizableProps) {
  const [size, setSize] = useState({
    width: defaultWidth,
    height: defaultHeight,
  });
  const [isResizing, setIsResizing] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const startRef = useRef({ x: 0, y: 0, width: 0, height: 0 });

  const handleMouseDown = useCallback(
    (handle: ResizeHandle) => (e: React.MouseEvent) => {
      e.preventDefault();
      const rect = containerRef.current?.getBoundingClientRect();
      if (!rect) return;

      startRef.current = {
        x: e.clientX,
        y: e.clientY,
        width: rect.width,
        height: rect.height,
      };
      setIsResizing(true);

      const handleMouseMove = (moveEvent: MouseEvent) => {
        const deltaX = moveEvent.clientX - startRef.current.x;
        const deltaY = moveEvent.clientY - startRef.current.y;

        let newWidth = startRef.current.width;
        let newHeight = startRef.current.height;

        if (handle === 'right' || handle === 'corner') {
          newWidth = Math.min(maxWidth, Math.max(minWidth, startRef.current.width + deltaX));
        }
        if (handle === 'left') {
          newWidth = Math.min(maxWidth, Math.max(minWidth, startRef.current.width - deltaX));
        }
        if (handle === 'bottom' || handle === 'corner') {
          newHeight = Math.min(maxHeight, Math.max(minHeight, startRef.current.height + deltaY));
        }
        if (handle === 'top') {
          newHeight = Math.min(maxHeight, Math.max(minHeight, startRef.current.height - deltaY));
        }

        setSize({ width: newWidth, height: newHeight });
        onResize?.(newWidth, newHeight);
      };

      const handleMouseUp = () => {
        setIsResizing(false);
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);

        const rect = containerRef.current?.getBoundingClientRect();
        if (rect) {
          onResizeEnd?.(rect.width, rect.height);
        }
      };

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [minWidth, maxWidth, minHeight, maxHeight, onResize, onResizeEnd]
  );

  // Prevent text selection while resizing
  useEffect(() => {
    if (isResizing) {
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'nwse-resize';
    } else {
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
    }
  }, [isResizing]);

  const style: React.CSSProperties = {};
  if (size.width !== undefined) style.width = size.width;
  if (size.height !== undefined) style.height = size.height;

  const showHorizontal = direction === 'horizontal' || direction === 'both';
  const showVertical = direction === 'vertical' || direction === 'both';

  return (
    <div
      ref={containerRef}
      className={`resizable ${isResizing ? 'resizable--resizing' : ''} ${className}`}
      style={style}
    >
      {children}

      {/* Handles */}
      {showHorizontal && handles.includes('right') && (
        <div
          className="resizable__handle resizable__handle--right"
          onMouseDown={handleMouseDown('right')}
        />
      )}
      {showHorizontal && handles.includes('left') && (
        <div
          className="resizable__handle resizable__handle--left"
          onMouseDown={handleMouseDown('left')}
        />
      )}
      {showVertical && handles.includes('bottom') && (
        <div
          className="resizable__handle resizable__handle--bottom"
          onMouseDown={handleMouseDown('bottom')}
        />
      )}
      {showVertical && handles.includes('top') && (
        <div
          className="resizable__handle resizable__handle--top"
          onMouseDown={handleMouseDown('top')}
        />
      )}
      {showHorizontal && showVertical && handles.includes('corner') && (
        <div
          className="resizable__handle resizable__handle--corner"
          onMouseDown={handleMouseDown('corner')}
        />
      )}
    </div>
  );
}

export default Resizable;

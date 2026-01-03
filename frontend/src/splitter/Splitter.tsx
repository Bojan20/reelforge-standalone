/**
 * ReelForge Splitter
 *
 * Resizable split panels:
 * - Horizontal/vertical splits
 * - Min/max constraints
 * - Collapsible panels
 * - Persistent sizes
 *
 * @module splitter/Splitter
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Splitter.css';

// ============ Types ============

export interface SplitterProps {
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
  /** Initial sizes (percentages or pixels) */
  initialSizes?: number[];
  /** Minimum sizes (pixels) */
  minSizes?: number[];
  /** Maximum sizes (pixels) */
  maxSizes?: number[];
  /** Gutter size (pixels) */
  gutterSize?: number;
  /** Collapsible panels (indices) */
  collapsible?: number[];
  /** Storage key for persisting sizes */
  storageKey?: string;
  /** On size change */
  onSizeChange?: (sizes: number[]) => void;
  /** Children (panels) */
  children: React.ReactNode[];
}

// ============ Component ============

export function Splitter({
  orientation = 'horizontal',
  initialSizes,
  minSizes = [],
  maxSizes = [],
  gutterSize = 6,
  collapsible = [],
  storageKey,
  onSizeChange,
  children,
}: SplitterProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const isDraggingRef = useRef(false);
  const dragIndexRef = useRef(-1);
  const startPosRef = useRef(0);
  const startSizesRef = useRef<number[]>([]);

  // Calculate default sizes
  const panelCount = children.length;
  const defaultSizes = initialSizes || Array(panelCount).fill(100 / panelCount);

  // Load persisted sizes
  const [sizes, setSizes] = useState<number[]>(() => {
    if (storageKey) {
      try {
        const stored = localStorage.getItem(storageKey);
        if (stored) {
          const parsed = JSON.parse(stored);
          if (Array.isArray(parsed) && parsed.length === panelCount) {
            return parsed;
          }
        }
      } catch {
        // Ignore
      }
    }
    return defaultSizes;
  });

  // Collapsed states
  const [collapsed, setCollapsed] = useState<boolean[]>(
    Array(panelCount).fill(false)
  );

  // Persist sizes
  useEffect(() => {
    if (storageKey) {
      localStorage.setItem(storageKey, JSON.stringify(sizes));
    }
  }, [sizes, storageKey]);

  // Notify size change
  useEffect(() => {
    onSizeChange?.(sizes);
  }, [sizes, onSizeChange]);

  // Get container dimension
  const getContainerSize = useCallback(() => {
    if (!containerRef.current) return 0;
    return orientation === 'horizontal'
      ? containerRef.current.offsetWidth
      : containerRef.current.offsetHeight;
  }, [orientation]);

  // Handle gutter drag start
  const handleDragStart = useCallback(
    (index: number, e: React.MouseEvent) => {
      e.preventDefault();
      isDraggingRef.current = true;
      dragIndexRef.current = index;
      startPosRef.current =
        orientation === 'horizontal' ? e.clientX : e.clientY;
      startSizesRef.current = [...sizes];

      document.body.style.cursor =
        orientation === 'horizontal' ? 'col-resize' : 'row-resize';
      document.body.style.userSelect = 'none';

      const handleMouseMove = (e: MouseEvent) => {
        if (!isDraggingRef.current) return;

        const currentPos =
          orientation === 'horizontal' ? e.clientX : e.clientY;
        const delta = currentPos - startPosRef.current;
        const containerSize = getContainerSize();
        const deltaPercent = (delta / containerSize) * 100;

        const newSizes = [...startSizesRef.current];
        const idx = dragIndexRef.current;

        // Adjust adjacent panels
        let newLeft = newSizes[idx] + deltaPercent;
        let newRight = newSizes[idx + 1] - deltaPercent;

        // Apply min constraints
        const minLeft = minSizes[idx]
          ? (minSizes[idx] / containerSize) * 100
          : 5;
        const minRight = minSizes[idx + 1]
          ? (minSizes[idx + 1] / containerSize) * 100
          : 5;

        // Apply max constraints
        const maxLeft = maxSizes[idx]
          ? (maxSizes[idx] / containerSize) * 100
          : 95;
        const maxRight = maxSizes[idx + 1]
          ? (maxSizes[idx + 1] / containerSize) * 100
          : 95;

        // Clamp values
        if (newLeft < minLeft) {
          newRight += newLeft - minLeft;
          newLeft = minLeft;
        }
        if (newRight < minRight) {
          newLeft += newRight - minRight;
          newRight = minRight;
        }
        if (newLeft > maxLeft) {
          newRight += newLeft - maxLeft;
          newLeft = maxLeft;
        }
        if (newRight > maxRight) {
          newLeft += newRight - maxRight;
          newRight = maxRight;
        }

        newSizes[idx] = newLeft;
        newSizes[idx + 1] = newRight;

        setSizes(newSizes);
      };

      const handleMouseUp = () => {
        isDraggingRef.current = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [orientation, sizes, minSizes, maxSizes, getContainerSize]
  );

  // Handle collapse toggle
  const handleCollapseToggle = useCallback(
    (index: number) => {
      if (!collapsible.includes(index)) return;

      setCollapsed((prev) => {
        const newCollapsed = [...prev];
        newCollapsed[index] = !newCollapsed[index];
        return newCollapsed;
      });
    },
    [collapsible]
  );

  // Handle double-click to collapse/expand
  const handleGutterDoubleClick = useCallback(
    (index: number) => {
      // Try to collapse/expand the panel to the right
      if (collapsible.includes(index + 1)) {
        handleCollapseToggle(index + 1);
      } else if (collapsible.includes(index)) {
        handleCollapseToggle(index);
      }
    },
    [collapsible, handleCollapseToggle]
  );

  return (
    <div
      ref={containerRef}
      className={`splitter splitter--${orientation}`}
      style={
        {
          '--gutter-size': `${gutterSize}px`,
        } as React.CSSProperties
      }
    >
      {children.map((child, index) => (
        <div key={index} className="splitter__panel-wrapper">
          {/* Panel */}
          <div
            className={`splitter__panel ${collapsed[index] ? 'splitter__panel--collapsed' : ''}`}
            style={{
              [orientation === 'horizontal' ? 'width' : 'height']: collapsed[index]
                ? 0
                : `calc(${sizes[index]}% - ${(gutterSize * (panelCount - 1)) / panelCount}px)`,
            }}
          >
            {child}
          </div>

          {/* Gutter */}
          {index < children.length - 1 && (
            <div
              className={`splitter__gutter splitter__gutter--${orientation}`}
              onMouseDown={(e) => handleDragStart(index, e)}
              onDoubleClick={() => handleGutterDoubleClick(index)}
            >
              <div className="splitter__gutter-handle" />
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

export default Splitter;

/**
 * ReelForge Masonry
 *
 * Masonry grid layout:
 * - Auto column calculation
 * - Responsive breakpoints
 * - Dynamic item heights
 * - Smooth animations
 *
 * @module masonry/Masonry
 */

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import './Masonry.css';

// ============ Types ============

export interface MasonryProps<T> {
  /** Items to render */
  items: T[];
  /** Render item */
  renderItem: (item: T, index: number) => React.ReactNode;
  /** Column width */
  columnWidth?: number;
  /** Gap between items */
  gap?: number;
  /** Minimum columns */
  minColumns?: number;
  /** Maximum columns */
  maxColumns?: number;
  /** Item key extractor */
  getKey?: (item: T, index: number) => string | number;
  /** Custom class */
  className?: string;
}

export interface MasonryItemProps {
  /** Children */
  children: React.ReactNode;
  /** Span columns */
  span?: number;
  /** Custom class */
  className?: string;
}

// ============ Masonry Component ============

export function Masonry<T>({
  items,
  renderItem,
  columnWidth = 300,
  gap = 16,
  minColumns = 1,
  maxColumns = Infinity,
  getKey,
  className = '',
}: MasonryProps<T>) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [columns, setColumns] = useState(1);
  const [columnHeights, setColumnHeights] = useState<number[]>([]);
  const itemRefs = useRef<Map<number, HTMLDivElement>>(new Map());

  // Calculate columns based on container width
  const updateColumns = useCallback(() => {
    if (!containerRef.current) return;

    const containerWidth = containerRef.current.offsetWidth;
    let cols = Math.floor((containerWidth + gap) / (columnWidth + gap));
    cols = Math.max(minColumns, Math.min(maxColumns, cols));
    setColumns(cols);
    setColumnHeights(new Array(cols).fill(0));
  }, [columnWidth, gap, minColumns, maxColumns]);

  // Observe container resize
  useEffect(() => {
    updateColumns();

    const observer = new ResizeObserver(updateColumns);
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }

    return () => observer.disconnect();
  }, [updateColumns]);

  // Distribute items into columns
  const distribution = useMemo(() => {
    const heights = new Array(columns).fill(0);
    const result: Array<{ item: T; index: number; column: number; top: number }> = [];

    items.forEach((item, index) => {
      // Find shortest column
      let shortestColumn = 0;
      let minHeight = heights[0];

      for (let i = 1; i < columns; i++) {
        if (heights[i] < minHeight) {
          minHeight = heights[i];
          shortestColumn = i;
        }
      }

      result.push({
        item,
        index,
        column: shortestColumn,
        top: heights[shortestColumn],
      });

      // Get actual item height from ref or estimate
      const itemEl = itemRefs.current.get(index);
      const itemHeight = itemEl?.offsetHeight || 200;
      heights[shortestColumn] += itemHeight + gap;
    });

    setColumnHeights(heights);
    return result;
  }, [items, columns, gap]);

  // Calculate container height
  const containerHeight = Math.max(...columnHeights, 0);

  // Column width percentage
  const columnWidthPercent = `calc((100% - ${(columns - 1) * gap}px) / ${columns})`;

  return (
    <div
      ref={containerRef}
      className={`masonry ${className}`}
      style={{ height: containerHeight }}
    >
      {distribution.map(({ item, index, column, top }) => (
        <div
          key={getKey ? getKey(item, index) : index}
          ref={(el) => {
            if (el) itemRefs.current.set(index, el);
          }}
          className="masonry__item"
          style={{
            width: columnWidthPercent,
            left: `calc(${column} * (${columnWidthPercent} + ${gap}px))`,
            top,
          }}
        >
          {renderItem(item, index)}
        </div>
      ))}
    </div>
  );
}

// ============ SimpleMasonry (CSS Grid based) ============

export interface SimpleMasonryProps {
  /** Children items */
  children: React.ReactNode;
  /** Column width */
  columnWidth?: number;
  /** Gap between items */
  gap?: number;
  /** Custom class */
  className?: string;
}

export function SimpleMasonry({
  children,
  columnWidth = 300,
  gap = 16,
  className = '',
}: SimpleMasonryProps) {
  return (
    <div
      className={`simple-masonry ${className}`}
      style={{
        columnWidth,
        columnGap: gap,
      }}
    >
      {children}
    </div>
  );
}

// ============ MasonryItem ============

export function MasonryItem({
  children,
  span = 1,
  className = '',
}: MasonryItemProps) {
  return (
    <div
      className={`masonry-item ${className}`}
      style={{
        breakInside: 'avoid',
        gridColumn: span > 1 ? `span ${span}` : undefined,
      }}
    >
      {children}
    </div>
  );
}

// ============ ResponsiveMasonry ============

export interface ResponsiveMasonryProps<T> {
  /** Items to render */
  items: T[];
  /** Render item */
  renderItem: (item: T, index: number) => React.ReactNode;
  /** Breakpoints: { containerWidth: columns } */
  breakpoints?: Record<number, number>;
  /** Gap between items */
  gap?: number;
  /** Item key extractor */
  getKey?: (item: T, index: number) => string | number;
  /** Custom class */
  className?: string;
}

const DEFAULT_BREAKPOINTS = {
  0: 1,
  520: 2,
  768: 3,
  1024: 4,
  1280: 5,
};

export function ResponsiveMasonry<T>({
  items,
  renderItem,
  breakpoints = DEFAULT_BREAKPOINTS,
  gap = 16,
  getKey,
  className = '',
}: ResponsiveMasonryProps<T>) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [columns, setColumns] = useState(1);

  // Calculate columns based on breakpoints
  const updateColumns = useCallback(() => {
    if (!containerRef.current) return;

    const containerWidth = containerRef.current.offsetWidth;
    const sortedBreakpoints = Object.entries(breakpoints)
      .map(([width, cols]) => [parseInt(width), cols] as [number, number])
      .sort((a, b) => b[0] - a[0]);

    for (const [width, cols] of sortedBreakpoints) {
      if (containerWidth >= width) {
        setColumns(cols);
        return;
      }
    }

    setColumns(1);
  }, [breakpoints]);

  useEffect(() => {
    updateColumns();

    const observer = new ResizeObserver(updateColumns);
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }

    return () => observer.disconnect();
  }, [updateColumns]);

  // Distribute items into column arrays
  const columnArrays = useMemo(() => {
    const result: T[][] = Array.from({ length: columns }, () => []);

    items.forEach((item, index) => {
      result[index % columns].push(item);
    });

    return result;
  }, [items, columns]);

  return (
    <div
      ref={containerRef}
      className={`responsive-masonry ${className}`}
      style={{
        display: 'flex',
        gap,
      }}
    >
      {columnArrays.map((column, colIndex) => (
        <div
          key={colIndex}
          className="responsive-masonry__column"
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            gap,
          }}
        >
          {column.map((item, itemIndex) => {
            const originalIndex = itemIndex * columns + colIndex;
            return (
              <div
                key={getKey ? getKey(item, originalIndex) : originalIndex}
                className="responsive-masonry__item"
              >
                {renderItem(item, originalIndex)}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

export default Masonry;

/**
 * ReelForge VirtualList
 *
 * Virtualized list for large datasets:
 * - Only renders visible items
 * - Dynamic item heights
 * - Smooth scrolling
 * - Overscan for smoother UX
 *
 * @module virtual-list/VirtualList
 */

import { useState, useRef, useCallback, useEffect, useMemo } from 'react';
import './VirtualList.css';

// ============ Types ============

export interface VirtualListProps<T> {
  /** Data items */
  items: T[];
  /** Item height (fixed) or function (dynamic) */
  itemHeight: number | ((item: T, index: number) => number);
  /** Render item */
  renderItem: (item: T, index: number) => React.ReactNode;
  /** Container height */
  height: number;
  /** Container width */
  width?: number | string;
  /** Items to render outside viewport */
  overscan?: number;
  /** Item key extractor */
  getKey?: (item: T, index: number) => string | number;
  /** On scroll callback */
  onScroll?: (scrollTop: number) => void;
  /** On reach end callback */
  onEndReached?: () => void;
  /** Threshold for end reached (px from bottom) */
  endReachedThreshold?: number;
  /** Custom class */
  className?: string;
}

export interface VirtualGridProps<T> {
  /** Data items */
  items: T[];
  /** Item width */
  itemWidth: number;
  /** Item height */
  itemHeight: number;
  /** Render item */
  renderItem: (item: T, index: number) => React.ReactNode;
  /** Container height */
  height: number;
  /** Container width */
  width: number;
  /** Gap between items */
  gap?: number;
  /** Items to render outside viewport (rows) */
  overscan?: number;
  /** Item key extractor */
  getKey?: (item: T, index: number) => string | number;
  /** Custom class */
  className?: string;
}

// ============ VirtualList Component ============

export function VirtualList<T>({
  items,
  itemHeight,
  renderItem,
  height,
  width = '100%',
  overscan = 3,
  getKey,
  onScroll,
  onEndReached,
  endReachedThreshold = 100,
  className = '',
}: VirtualListProps<T>) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scrollTop, setScrollTop] = useState(0);

  // Calculate item positions for dynamic heights
  const { itemPositions, totalHeight } = useMemo(() => {
    if (typeof itemHeight === 'number') {
      return {
        itemPositions: items.map((_, i) => i * itemHeight),
        totalHeight: items.length * itemHeight,
      };
    }

    const positions: number[] = [];
    let currentTop = 0;

    for (let i = 0; i < items.length; i++) {
      positions.push(currentTop);
      currentTop += itemHeight(items[i], i);
    }

    return {
      itemPositions: positions,
      totalHeight: currentTop,
    };
  }, [items, itemHeight]);

  // Get item height at index
  const getItemHeight = useCallback(
    (index: number): number => {
      if (typeof itemHeight === 'number') return itemHeight;
      return itemHeight(items[index], index);
    },
    [items, itemHeight]
  );

  // Find visible range
  const { startIndex, endIndex } = useMemo(() => {
    if (items.length === 0) return { startIndex: 0, endIndex: 0 };

    // Binary search for start
    let start = 0;
    let end = items.length - 1;

    while (start < end) {
      const mid = Math.floor((start + end) / 2);
      if (itemPositions[mid] + getItemHeight(mid) < scrollTop) {
        start = mid + 1;
      } else {
        end = mid;
      }
    }

    const startIdx = Math.max(0, start - overscan);

    // Find end index
    let endIdx = start;
    let accHeight = itemPositions[start] - scrollTop;

    while (endIdx < items.length && accHeight < height) {
      accHeight += getItemHeight(endIdx);
      endIdx++;
    }

    endIdx = Math.min(items.length - 1, endIdx + overscan);

    return { startIndex: startIdx, endIndex: endIdx };
  }, [items.length, itemPositions, scrollTop, height, overscan, getItemHeight]);

  // Handle scroll
  const handleScroll = useCallback(
    (e: React.UIEvent<HTMLDivElement>) => {
      const newScrollTop = e.currentTarget.scrollTop;
      setScrollTop(newScrollTop);
      onScroll?.(newScrollTop);

      // Check end reached
      if (onEndReached) {
        const scrollHeight = e.currentTarget.scrollHeight;
        const clientHeight = e.currentTarget.clientHeight;
        if (scrollHeight - newScrollTop - clientHeight < endReachedThreshold) {
          onEndReached();
        }
      }
    },
    [onScroll, onEndReached, endReachedThreshold]
  );

  // Scroll to index
  const scrollToIndex = useCallback(
    (index: number, align: 'start' | 'center' | 'end' = 'start') => {
      if (!containerRef.current || index < 0 || index >= items.length) return;

      const itemTop = itemPositions[index];
      const itemH = getItemHeight(index);

      let targetScroll = itemTop;

      if (align === 'center') {
        targetScroll = itemTop - height / 2 + itemH / 2;
      } else if (align === 'end') {
        targetScroll = itemTop - height + itemH;
      }

      containerRef.current.scrollTop = Math.max(0, targetScroll);
    },
    [itemPositions, getItemHeight, height, items.length]
  );

  // Expose scroll methods
  useEffect(() => {
    const container = containerRef.current;
    if (container) {
      (container as any).scrollToIndex = scrollToIndex;
    }
  }, [scrollToIndex]);

  // Visible items
  const visibleItems = useMemo(() => {
    const result: Array<{ item: T; index: number; style: React.CSSProperties }> = [];

    for (let i = startIndex; i <= endIndex && i < items.length; i++) {
      result.push({
        item: items[i],
        index: i,
        style: {
          position: 'absolute',
          top: itemPositions[i],
          left: 0,
          right: 0,
          height: getItemHeight(i),
        },
      });
    }

    return result;
  }, [items, startIndex, endIndex, itemPositions, getItemHeight]);

  return (
    <div
      ref={containerRef}
      className={`virtual-list ${className}`}
      style={{ height, width }}
      onScroll={handleScroll}
    >
      <div className="virtual-list__inner" style={{ height: totalHeight }}>
        {visibleItems.map(({ item, index, style }) => (
          <div
            key={getKey ? getKey(item, index) : index}
            className="virtual-list__item"
            style={style}
          >
            {renderItem(item, index)}
          </div>
        ))}
      </div>
    </div>
  );
}

// ============ VirtualGrid Component ============

export function VirtualGrid<T>({
  items,
  itemWidth,
  itemHeight,
  renderItem,
  height,
  width,
  gap = 0,
  overscan = 2,
  getKey,
  className = '',
}: VirtualGridProps<T>) {
  const [scrollTop, setScrollTop] = useState(0);

  // Calculate columns
  const columns = Math.max(1, Math.floor((width + gap) / (itemWidth + gap)));
  const rows = Math.ceil(items.length / columns);
  const rowHeight = itemHeight + gap;
  const totalHeight = rows * rowHeight - gap;

  // Visible rows
  const startRow = Math.max(0, Math.floor(scrollTop / rowHeight) - overscan);
  const endRow = Math.min(
    rows - 1,
    Math.ceil((scrollTop + height) / rowHeight) + overscan
  );

  // Visible items
  const visibleItems = useMemo(() => {
    const result: Array<{
      item: T;
      index: number;
      style: React.CSSProperties;
    }> = [];

    for (let row = startRow; row <= endRow; row++) {
      for (let col = 0; col < columns; col++) {
        const index = row * columns + col;
        if (index >= items.length) break;

        result.push({
          item: items[index],
          index,
          style: {
            position: 'absolute',
            top: row * rowHeight,
            left: col * (itemWidth + gap),
            width: itemWidth,
            height: itemHeight,
          },
        });
      }
    }

    return result;
  }, [items, startRow, endRow, columns, rowHeight, itemWidth, itemHeight, gap]);

  const handleScroll = useCallback((e: React.UIEvent<HTMLDivElement>) => {
    setScrollTop(e.currentTarget.scrollTop);
  }, []);

  return (
    <div
      className={`virtual-grid ${className}`}
      style={{ height, width }}
      onScroll={handleScroll}
    >
      <div className="virtual-grid__inner" style={{ height: totalHeight }}>
        {visibleItems.map(({ item, index, style }) => (
          <div
            key={getKey ? getKey(item, index) : index}
            className="virtual-grid__item"
            style={style}
          >
            {renderItem(item, index)}
          </div>
        ))}
      </div>
    </div>
  );
}

export default VirtualList;

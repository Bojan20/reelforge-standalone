/**
 * ReelForge Scrollbar
 *
 * Custom scrollbar component:
 * - Vertical and horizontal scrollbars
 * - Drag to scroll
 * - Click track to jump
 * - Keyboard support
 * - Auto-hide option
 *
 * @module scrollbar/Scrollbar
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Scrollbar.css';

// ============ Types ============

export interface ScrollbarProps {
  /** Scroll direction */
  direction?: 'vertical' | 'horizontal';
  /** Content size (total scrollable) */
  contentSize: number;
  /** Viewport size (visible area) */
  viewportSize: number;
  /** Current scroll position */
  scrollPosition: number;
  /** On scroll change */
  onScroll: (position: number) => void;
  /** Auto-hide when not scrolling */
  autoHide?: boolean;
  /** Auto-hide delay in ms */
  autoHideDelay?: number;
  /** Minimum thumb size in px */
  minThumbSize?: number;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Scrollbar({
  direction = 'vertical',
  contentSize,
  viewportSize,
  scrollPosition,
  onScroll,
  autoHide = false,
  autoHideDelay = 1000,
  minThumbSize = 30,
  className = '',
}: ScrollbarProps) {
  const [isDragging, setIsDragging] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
  const [isVisible, setIsVisible] = useState(!autoHide);
  const trackRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef({ position: 0, scroll: 0 });
  const hideTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const isVertical = direction === 'vertical';
  const maxScroll = Math.max(0, contentSize - viewportSize);
  const scrollRatio = maxScroll > 0 ? scrollPosition / maxScroll : 0;
  const thumbRatio = contentSize > 0 ? viewportSize / contentSize : 1;
  const canScroll = contentSize > viewportSize;

  // Calculate thumb size and position
  const trackSize = isVertical
    ? trackRef.current?.clientHeight ?? 0
    : trackRef.current?.clientWidth ?? 0;

  const thumbSize = Math.max(minThumbSize, trackSize * thumbRatio);
  const thumbPosition = (trackSize - thumbSize) * scrollRatio;

  // Auto-hide logic
  useEffect(() => {
    if (!autoHide) return;

    setIsVisible(true);

    if (hideTimeoutRef.current) {
      clearTimeout(hideTimeoutRef.current);
    }

    if (!isDragging && !isHovered) {
      hideTimeoutRef.current = setTimeout(() => {
        setIsVisible(false);
      }, autoHideDelay);
    }

    return () => {
      if (hideTimeoutRef.current) {
        clearTimeout(hideTimeoutRef.current);
      }
    };
  }, [scrollPosition, autoHide, autoHideDelay, isDragging, isHovered]);

  // Handle track click
  const handleTrackClick = useCallback(
    (e: React.MouseEvent) => {
      if (!trackRef.current || !canScroll) return;

      const rect = trackRef.current.getBoundingClientRect();
      const clickPosition = isVertical
        ? e.clientY - rect.top
        : e.clientX - rect.left;

      // Calculate target scroll based on click position
      const clickRatio = clickPosition / trackSize;
      const targetScroll = clickRatio * maxScroll;

      onScroll(Math.max(0, Math.min(maxScroll, targetScroll)));
    },
    [isVertical, trackSize, maxScroll, canScroll, onScroll]
  );

  // Handle thumb drag start
  const handleThumbMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (!canScroll) return;

      e.preventDefault();
      e.stopPropagation();

      setIsDragging(true);
      dragStartRef.current = {
        position: isVertical ? e.clientY : e.clientX,
        scroll: scrollPosition,
      };
    },
    [isVertical, scrollPosition, canScroll]
  );

  // Handle drag move
  useEffect(() => {
    if (!isDragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      const currentPosition = isVertical ? e.clientY : e.clientX;
      const delta = currentPosition - dragStartRef.current.position;
      const scrollDelta = (delta / (trackSize - thumbSize)) * maxScroll;
      const newScroll = dragStartRef.current.scroll + scrollDelta;

      onScroll(Math.max(0, Math.min(maxScroll, newScroll)));
    };

    const handleMouseUp = () => {
      setIsDragging(false);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, isVertical, trackSize, thumbSize, maxScroll, onScroll]);

  // Don't render if can't scroll
  if (!canScroll) return null;

  return (
    <div
      className={`scrollbar scrollbar--${direction} ${
        isDragging ? 'scrollbar--dragging' : ''
      } ${autoHide && !isVisible ? 'scrollbar--hidden' : ''} ${className}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <div
        ref={trackRef}
        className="scrollbar__track"
        onClick={handleTrackClick}
      >
        <div
          className="scrollbar__thumb"
          style={{
            [isVertical ? 'height' : 'width']: `${thumbSize}px`,
            [isVertical ? 'top' : 'left']: `${thumbPosition}px`,
          }}
          onMouseDown={handleThumbMouseDown}
        />
      </div>
    </div>
  );
}

// ============ Scrollable Container ============

export interface ScrollableProps {
  /** Children */
  children: React.ReactNode;
  /** Max height (enables vertical scroll) */
  maxHeight?: number | string;
  /** Max width (enables horizontal scroll) */
  maxWidth?: number | string;
  /** Show vertical scrollbar */
  vertical?: boolean;
  /** Show horizontal scrollbar */
  horizontal?: boolean;
  /** Auto-hide scrollbars */
  autoHide?: boolean;
  /** Custom class */
  className?: string;
  /** On scroll event */
  onScroll?: (scrollTop: number, scrollLeft: number) => void;
}

export function Scrollable({
  children,
  maxHeight,
  maxWidth,
  vertical = true,
  horizontal = false,
  autoHide = true,
  className = '',
  onScroll,
}: ScrollableProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const [scrollState, setScrollState] = useState({
    scrollTop: 0,
    scrollLeft: 0,
    scrollHeight: 0,
    scrollWidth: 0,
    clientHeight: 0,
    clientWidth: 0,
  });

  // Update scroll state
  const updateScrollState = useCallback(() => {
    if (!containerRef.current) return;

    const {
      scrollTop,
      scrollLeft,
      scrollHeight,
      scrollWidth,
      clientHeight,
      clientWidth,
    } = containerRef.current;

    setScrollState({
      scrollTop,
      scrollLeft,
      scrollHeight,
      scrollWidth,
      clientHeight,
      clientWidth,
    });
  }, []);

  // Handle native scroll
  const handleScroll = useCallback(() => {
    updateScrollState();

    if (containerRef.current && onScroll) {
      onScroll(
        containerRef.current.scrollTop,
        containerRef.current.scrollLeft
      );
    }
  }, [updateScrollState, onScroll]);

  // Handle custom scrollbar scroll
  const handleVerticalScroll = useCallback((position: number) => {
    if (containerRef.current) {
      containerRef.current.scrollTop = position;
    }
  }, []);

  const handleHorizontalScroll = useCallback((position: number) => {
    if (containerRef.current) {
      containerRef.current.scrollLeft = position;
    }
  }, []);

  // Observe content size changes
  useEffect(() => {
    updateScrollState();

    const resizeObserver = new ResizeObserver(() => {
      updateScrollState();
    });

    if (containerRef.current) {
      resizeObserver.observe(containerRef.current);
    }

    if (contentRef.current) {
      resizeObserver.observe(contentRef.current);
    }

    return () => {
      resizeObserver.disconnect();
    };
  }, [updateScrollState]);

  return (
    <div className={`scrollable ${className}`}>
      <div
        ref={containerRef}
        className="scrollable__viewport"
        style={{
          maxHeight,
          maxWidth,
        }}
        onScroll={handleScroll}
      >
        <div ref={contentRef} className="scrollable__content">
          {children}
        </div>
      </div>

      {vertical && (
        <Scrollbar
          direction="vertical"
          contentSize={scrollState.scrollHeight}
          viewportSize={scrollState.clientHeight}
          scrollPosition={scrollState.scrollTop}
          onScroll={handleVerticalScroll}
          autoHide={autoHide}
        />
      )}

      {horizontal && (
        <Scrollbar
          direction="horizontal"
          contentSize={scrollState.scrollWidth}
          viewportSize={scrollState.clientWidth}
          scrollPosition={scrollState.scrollLeft}
          onScroll={handleHorizontalScroll}
          autoHide={autoHide}
        />
      )}
    </div>
  );
}

export default Scrollbar;

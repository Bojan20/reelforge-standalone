/**
 * ReelForge InfiniteScroll
 *
 * Infinite scrolling container:
 * - Intersection Observer based
 * - Load more on scroll
 * - Loading state
 * - End of list detection
 *
 * @module infinite-scroll/InfiniteScroll
 */

import { useRef, useEffect, useCallback } from 'react';
import './InfiniteScroll.css';

// ============ Types ============

export interface InfiniteScrollProps {
  /** Children content */
  children: React.ReactNode;
  /** Load more callback */
  onLoadMore: () => void | Promise<void>;
  /** Has more data to load */
  hasMore: boolean;
  /** Currently loading */
  isLoading?: boolean;
  /** Loader element */
  loader?: React.ReactNode;
  /** End message when no more data */
  endMessage?: React.ReactNode;
  /** Root margin for intersection observer */
  rootMargin?: string;
  /** Threshold for intersection */
  threshold?: number;
  /** Scroll direction */
  direction?: 'down' | 'up';
  /** Custom class */
  className?: string;
}

export interface UseInfiniteScrollOptions {
  /** Load more callback */
  onLoadMore: () => void | Promise<void>;
  /** Has more data */
  hasMore: boolean;
  /** Is loading */
  isLoading?: boolean;
  /** Root margin */
  rootMargin?: string;
  /** Threshold */
  threshold?: number;
}

// ============ Hook ============

export function useInfiniteScroll({
  onLoadMore,
  hasMore,
  isLoading = false,
  rootMargin = '100px',
  threshold = 0,
}: UseInfiniteScrollOptions) {
  const sentinelRef = useRef<HTMLDivElement>(null);
  const loadingRef = useRef(false);

  const handleIntersect = useCallback(
    async (entries: IntersectionObserverEntry[]) => {
      const [entry] = entries;

      if (entry.isIntersecting && hasMore && !isLoading && !loadingRef.current) {
        loadingRef.current = true;
        try {
          await onLoadMore();
        } finally {
          loadingRef.current = false;
        }
      }
    },
    [hasMore, isLoading, onLoadMore]
  );

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(handleIntersect, {
      rootMargin,
      threshold,
    });

    observer.observe(sentinel);

    return () => observer.disconnect();
  }, [handleIntersect, rootMargin, threshold]);

  return { sentinelRef };
}

// ============ Component ============

export function InfiniteScroll({
  children,
  onLoadMore,
  hasMore,
  isLoading = false,
  loader,
  endMessage,
  rootMargin = '100px',
  threshold = 0,
  direction = 'down',
  className = '',
}: InfiniteScrollProps) {
  const { sentinelRef } = useInfiniteScroll({
    onLoadMore,
    hasMore,
    isLoading,
    rootMargin,
    threshold,
  });

  const defaultLoader = (
    <div className="infinite-scroll__loader">
      <div className="infinite-scroll__spinner" />
      <span>Loading...</span>
    </div>
  );

  const defaultEndMessage = (
    <div className="infinite-scroll__end">No more items</div>
  );

  const sentinel = (
    <div
      ref={sentinelRef}
      className="infinite-scroll__sentinel"
      aria-hidden="true"
    />
  );

  const loadingContent = isLoading && (loader || defaultLoader);
  const endContent = !hasMore && !isLoading && (endMessage || defaultEndMessage);

  return (
    <div className={`infinite-scroll infinite-scroll--${direction} ${className}`}>
      {direction === 'up' && sentinel}
      {direction === 'up' && loadingContent}

      {children}

      {direction === 'down' && loadingContent}
      {direction === 'down' && sentinel}

      {endContent}
    </div>
  );
}

// ============ InfiniteScrollTrigger ============

export interface InfiniteScrollTriggerProps {
  /** Callback when trigger becomes visible */
  onTrigger: () => void;
  /** Is active */
  enabled?: boolean;
  /** Root margin */
  rootMargin?: string;
  /** Custom class */
  className?: string;
}

export function InfiniteScrollTrigger({
  onTrigger,
  enabled = true,
  rootMargin = '100px',
  className = '',
}: InfiniteScrollTriggerProps) {
  const triggerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const trigger = triggerRef.current;
    if (!trigger || !enabled) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          onTrigger();
        }
      },
      { rootMargin }
    );

    observer.observe(trigger);

    return () => observer.disconnect();
  }, [onTrigger, enabled, rootMargin]);

  return (
    <div
      ref={triggerRef}
      className={`infinite-scroll-trigger ${className}`}
      aria-hidden="true"
    />
  );
}

export default InfiniteScroll;

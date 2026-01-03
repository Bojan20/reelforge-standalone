/**
 * ReelForge Pagination
 *
 * Pagination component:
 * - Page numbers
 * - Previous/Next buttons
 * - Jump to page
 * - Items per page
 * - Compact mode
 *
 * @module pagination/Pagination
 */

import { useState, useCallback, useMemo } from 'react';
import './Pagination.css';

// ============ Types ============

export interface PaginationProps {
  /** Current page (1-indexed) */
  page: number;
  /** Total items */
  total: number;
  /** Items per page */
  pageSize?: number;
  /** On page change */
  onChange: (page: number) => void;
  /** On page size change */
  onPageSizeChange?: (size: number) => void;
  /** Page size options */
  pageSizeOptions?: number[];
  /** Show page size selector */
  showPageSize?: boolean;
  /** Show total count */
  showTotal?: boolean;
  /** Show quick jump */
  showQuickJump?: boolean;
  /** Sibling count (pages shown around current) */
  siblingCount?: number;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Pagination({
  page,
  total,
  pageSize = 10,
  onChange,
  onPageSizeChange,
  pageSizeOptions = [10, 20, 50, 100],
  showPageSize = false,
  showTotal = false,
  showQuickJump = false,
  siblingCount = 1,
  size = 'medium',
  disabled = false,
  className = '',
}: PaginationProps) {
  const [jumpValue, setJumpValue] = useState('');

  const totalPages = Math.ceil(total / pageSize);

  // Generate page numbers
  const pageNumbers = useMemo(() => {
    const range = (start: number, end: number) =>
      Array.from({ length: end - start + 1 }, (_, i) => start + i);

    // Always show first, last, current, and siblings
    const leftSibling = Math.max(page - siblingCount, 1);
    const rightSibling = Math.min(page + siblingCount, totalPages);

    const showLeftEllipsis = leftSibling > 2;
    const showRightEllipsis = rightSibling < totalPages - 1;

    if (!showLeftEllipsis && !showRightEllipsis) {
      return range(1, totalPages);
    }

    if (!showLeftEllipsis && showRightEllipsis) {
      const leftCount = 3 + siblingCount * 2;
      return [...range(1, leftCount), 'ellipsis-right', totalPages];
    }

    if (showLeftEllipsis && !showRightEllipsis) {
      const rightCount = 3 + siblingCount * 2;
      return [1, 'ellipsis-left', ...range(totalPages - rightCount + 1, totalPages)];
    }

    return [
      1,
      'ellipsis-left',
      ...range(leftSibling, rightSibling),
      'ellipsis-right',
      totalPages,
    ];
  }, [page, totalPages, siblingCount]);

  // Handlers
  const goToPage = useCallback(
    (p: number) => {
      if (disabled || p < 1 || p > totalPages || p === page) return;
      onChange(p);
    },
    [disabled, totalPages, page, onChange]
  );

  const handlePageSizeChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const newSize = parseInt(e.target.value, 10);
    onPageSizeChange?.(newSize);
    // Reset to page 1 when changing size
    onChange(1);
  };

  const handleJump = () => {
    const p = parseInt(jumpValue, 10);
    if (!isNaN(p)) {
      goToPage(p);
      setJumpValue('');
    }
  };

  const handleJumpKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleJump();
    }
  };

  if (totalPages <= 1 && !showTotal && !showPageSize) {
    return null;
  }

  return (
    <div
      className={`pagination pagination--${size} ${
        disabled ? 'pagination--disabled' : ''
      } ${className}`}
    >
      {/* Total count */}
      {showTotal && (
        <span className="pagination__total">
          {total} items
        </span>
      )}

      {/* Page size selector */}
      {showPageSize && (
        <div className="pagination__page-size">
          <select
            value={pageSize}
            onChange={handlePageSizeChange}
            disabled={disabled}
            className="pagination__select"
          >
            {pageSizeOptions.map((size) => (
              <option key={size} value={size}>
                {size} / page
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Previous button */}
      <button
        type="button"
        className="pagination__btn pagination__btn--prev"
        onClick={() => goToPage(page - 1)}
        disabled={disabled || page <= 1}
        aria-label="Previous page"
      >
        ‹
      </button>

      {/* Page numbers */}
      <div className="pagination__pages">
        {pageNumbers.map((p) => {
          if (typeof p === 'string') {
            return (
              <span key={p} className="pagination__ellipsis">
                ...
              </span>
            );
          }

          return (
            <button
              key={p}
              type="button"
              className={`pagination__page ${
                p === page ? 'pagination__page--active' : ''
              }`}
              onClick={() => goToPage(p)}
              disabled={disabled}
              aria-label={`Page ${p}`}
              aria-current={p === page ? 'page' : undefined}
            >
              {p}
            </button>
          );
        })}
      </div>

      {/* Next button */}
      <button
        type="button"
        className="pagination__btn pagination__btn--next"
        onClick={() => goToPage(page + 1)}
        disabled={disabled || page >= totalPages}
        aria-label="Next page"
      >
        ›
      </button>

      {/* Quick jump */}
      {showQuickJump && (
        <div className="pagination__jump">
          <span>Go to</span>
          <input
            type="text"
            className="pagination__jump-input"
            value={jumpValue}
            onChange={(e) => setJumpValue(e.target.value)}
            onKeyDown={handleJumpKeyDown}
            onBlur={handleJump}
            disabled={disabled}
          />
        </div>
      )}
    </div>
  );
}

export default Pagination;

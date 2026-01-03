/**
 * ReelForge Breadcrumbs
 *
 * Breadcrumb navigation component:
 * - Path display
 * - Clickable items
 * - Custom separators
 * - Icons
 * - Overflow handling
 *
 * @module breadcrumbs/Breadcrumbs
 */

import './Breadcrumbs.css';

// ============ Types ============

export interface BreadcrumbItem {
  /** Unique key */
  key: string;
  /** Label */
  label: string;
  /** Icon */
  icon?: React.ReactNode;
  /** Href for link */
  href?: string;
  /** Disabled */
  disabled?: boolean;
}

export interface BreadcrumbsProps {
  /** Items */
  items: BreadcrumbItem[];
  /** Separator */
  separator?: React.ReactNode;
  /** Max visible items (collapses middle) */
  maxItems?: number;
  /** On item click */
  onItemClick?: (item: BreadcrumbItem, index: number) => void;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Breadcrumbs({
  items,
  separator = '/',
  maxItems,
  onItemClick,
  size = 'medium',
  className = '',
}: BreadcrumbsProps) {
  // Collapse items if needed
  const displayItems = (() => {
    if (!maxItems || items.length <= maxItems) {
      return items.map((item, index) => ({ item, index, isCollapsed: false }));
    }

    const start = items.slice(0, 1);
    const end = items.slice(-(maxItems - 2));

    return [
      { item: start[0], index: 0, isCollapsed: false },
      { item: { key: '__collapsed__', label: '...' }, index: -1, isCollapsed: true },
      ...end.map((item, i) => ({
        item,
        index: items.length - (maxItems - 2) + i,
        isCollapsed: false,
      })),
    ];
  })();

  const handleClick = (item: BreadcrumbItem, index: number, e: React.MouseEvent) => {
    if (item.disabled || index === items.length - 1) {
      e.preventDefault();
      return;
    }

    if (!item.href) {
      e.preventDefault();
    }

    onItemClick?.(item, index);
  };

  return (
    <nav
      className={`breadcrumbs breadcrumbs--${size} ${className}`}
      aria-label="Breadcrumb"
    >
      <ol className="breadcrumbs__list">
        {displayItems.map(({ item, index, isCollapsed }, displayIndex) => {
          const isLast = displayIndex === displayItems.length - 1;
          const isDisabled = item.disabled || isLast;

          return (
            <li key={item.key} className="breadcrumbs__item">
              {displayIndex > 0 && (
                <span className="breadcrumbs__separator" aria-hidden="true">
                  {separator}
                </span>
              )}

              {isCollapsed ? (
                <span className="breadcrumbs__collapsed">{item.label}</span>
              ) : item.href ? (
                <a
                  href={item.href}
                  className={`breadcrumbs__link ${
                    isDisabled ? 'breadcrumbs__link--disabled' : ''
                  } ${isLast ? 'breadcrumbs__link--current' : ''}`}
                  onClick={(e) => handleClick(item, index, e)}
                  aria-current={isLast ? 'page' : undefined}
                >
                  {item.icon && <span className="breadcrumbs__icon">{item.icon}</span>}
                  {item.label}
                </a>
              ) : (
                <button
                  type="button"
                  className={`breadcrumbs__button ${
                    isDisabled ? 'breadcrumbs__button--disabled' : ''
                  } ${isLast ? 'breadcrumbs__button--current' : ''}`}
                  onClick={(e) => handleClick(item, index, e)}
                  disabled={isDisabled}
                  aria-current={isLast ? 'page' : undefined}
                >
                  {item.icon && <span className="breadcrumbs__icon">{item.icon}</span>}
                  {item.label}
                </button>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

export default Breadcrumbs;

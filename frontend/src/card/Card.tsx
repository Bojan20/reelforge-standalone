/**
 * ReelForge Card
 *
 * Card component:
 * - Header, body, footer sections
 * - Cover image
 * - Actions
 * - Variants
 * - Hover effects
 *
 * @module card/Card
 */

import './Card.css';

// ============ Types ============

export interface CardProps {
  /** Children */
  children: React.ReactNode;
  /** Title */
  title?: React.ReactNode;
  /** Subtitle */
  subtitle?: React.ReactNode;
  /** Cover image */
  cover?: string;
  /** Cover alt text */
  coverAlt?: string;
  /** Header extra content */
  extra?: React.ReactNode;
  /** Footer content */
  footer?: React.ReactNode;
  /** Actions */
  actions?: React.ReactNode[];
  /** Variant */
  variant?: 'default' | 'outlined' | 'elevated';
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Hoverable */
  hoverable?: boolean;
  /** Clickable */
  onClick?: () => void;
  /** Custom class */
  className?: string;
  /** No padding */
  noPadding?: boolean;
}

// ============ Component ============

export function Card({
  children,
  title,
  subtitle,
  cover,
  coverAlt,
  extra,
  footer,
  actions,
  variant = 'default',
  size = 'medium',
  hoverable = false,
  onClick,
  className = '',
  noPadding = false,
}: CardProps) {
  const isClickable = hoverable || onClick;

  return (
    <div
      className={`card card--${variant} card--${size} ${
        hoverable ? 'card--hoverable' : ''
      } ${isClickable ? 'card--clickable' : ''} ${className}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
    >
      {/* Cover */}
      {cover && (
        <div className="card__cover">
          <img src={cover} alt={coverAlt || ''} className="card__cover-image" />
        </div>
      )}

      {/* Header */}
      {(title || subtitle || extra) && (
        <div className="card__header">
          <div className="card__header-content">
            {title && <div className="card__title">{title}</div>}
            {subtitle && <div className="card__subtitle">{subtitle}</div>}
          </div>
          {extra && <div className="card__extra">{extra}</div>}
        </div>
      )}

      {/* Body */}
      <div className={`card__body ${noPadding ? 'card__body--no-padding' : ''}`}>
        {children}
      </div>

      {/* Actions */}
      {actions && actions.length > 0 && (
        <div className="card__actions">
          {actions.map((action, index) => (
            <div key={index} className="card__action">
              {action}
            </div>
          ))}
        </div>
      )}

      {/* Footer */}
      {footer && <div className="card__footer">{footer}</div>}
    </div>
  );
}

// ============ Card Grid ============

export interface CardGridProps {
  /** Children cards */
  children: React.ReactNode;
  /** Columns */
  columns?: number | { xs?: number; sm?: number; md?: number; lg?: number };
  /** Gap */
  gap?: number | string;
  /** Custom class */
  className?: string;
}

export function CardGrid({
  children,
  columns = 3,
  gap = 16,
  className = '',
}: CardGridProps) {
  const colCount = typeof columns === 'number' ? columns : columns.md || 3;

  return (
    <div
      className={`card-grid ${className}`}
      style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${colCount}, 1fr)`,
        gap: typeof gap === 'number' ? `${gap}px` : gap,
      }}
    >
      {children}
    </div>
  );
}

export default Card;

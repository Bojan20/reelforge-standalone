/**
 * ReelForge Rating
 *
 * Rating component:
 * - Stars or custom icons
 * - Half values
 * - Read-only mode
 * - Customizable count
 *
 * @module rating/Rating
 */

import { useState } from 'react';
import './Rating.css';

// ============ Types ============

export interface RatingProps {
  /** Current value */
  value: number;
  /** On value change */
  onChange?: (value: number) => void;
  /** Maximum value */
  max?: number;
  /** Allow half values */
  allowHalf?: boolean;
  /** Read only */
  readOnly?: boolean;
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom empty icon */
  emptyIcon?: React.ReactNode;
  /** Custom filled icon */
  filledIcon?: React.ReactNode;
  /** Custom half icon */
  halfIcon?: React.ReactNode;
  /** Show value text */
  showValue?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Default Icons ============

const StarEmpty = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
    <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
  </svg>
);

const StarFilled = () => (
  <svg viewBox="0 0 24 24" fill="currentColor">
    <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
  </svg>
);

const StarHalf = () => (
  <svg viewBox="0 0 24 24">
    <defs>
      <linearGradient id="halfGrad">
        <stop offset="50%" stopColor="currentColor" />
        <stop offset="50%" stopColor="transparent" />
      </linearGradient>
    </defs>
    <polygon
      points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"
      fill="url(#halfGrad)"
      stroke="currentColor"
      strokeWidth="2"
    />
  </svg>
);

// ============ Component ============

export function Rating({
  value,
  onChange,
  max = 5,
  allowHalf = false,
  readOnly = false,
  disabled = false,
  size = 'medium',
  emptyIcon,
  filledIcon,
  halfIcon,
  showValue = false,
  className = '',
}: RatingProps) {
  const [hoverValue, setHoverValue] = useState<number | null>(null);

  const displayValue = hoverValue !== null ? hoverValue : value;
  const isInteractive = !readOnly && !disabled && onChange;

  const handleClick = (index: number, isHalf: boolean) => {
    if (!isInteractive) return;
    const newValue = isHalf && allowHalf ? index + 0.5 : index + 1;
    onChange(newValue);
  };

  const handleMouseMove = (e: React.MouseEvent, index: number) => {
    if (!isInteractive) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const isHalf = allowHalf && x < rect.width / 2;
    setHoverValue(isHalf ? index + 0.5 : index + 1);
  };

  const handleMouseLeave = () => {
    setHoverValue(null);
  };

  const renderIcon = (index: number) => {
    const filled = displayValue >= index + 1;
    const half = !filled && displayValue >= index + 0.5;

    if (filled) {
      return filledIcon || <StarFilled />;
    }
    if (half) {
      return halfIcon || <StarHalf />;
    }
    return emptyIcon || <StarEmpty />;
  };

  return (
    <div
      className={`rating rating--${size} ${disabled ? 'rating--disabled' : ''} ${
        isInteractive ? 'rating--interactive' : ''
      } ${className}`}
      onMouseLeave={handleMouseLeave}
      role="slider"
      aria-valuenow={value}
      aria-valuemin={0}
      aria-valuemax={max}
    >
      <div className="rating__stars">
        {Array.from({ length: max }).map((_, index) => (
          <span
            key={index}
            className={`rating__star ${displayValue >= index + 1 ? 'rating__star--filled' : ''} ${
              displayValue >= index + 0.5 && displayValue < index + 1 ? 'rating__star--half' : ''
            }`}
            onClick={() => handleClick(index, false)}
            onMouseMove={(e) => handleMouseMove(e, index)}
          >
            {renderIcon(index)}
          </span>
        ))}
      </div>
      {showValue && (
        <span className="rating__value">{value.toFixed(allowHalf ? 1 : 0)}</span>
      )}
    </div>
  );
}

// ============ Rate Display ============

export interface RateDisplayProps {
  /** Rating value */
  value: number;
  /** Maximum value */
  max?: number;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Show count */
  count?: number;
  /** Custom class */
  className?: string;
}

export function RateDisplay({
  value,
  max = 5,
  size = 'medium',
  count,
  className = '',
}: RateDisplayProps) {
  return (
    <div className={`rate-display rate-display--${size} ${className}`}>
      <Rating value={value} max={max} size={size} readOnly />
      <span className="rate-display__value">{value.toFixed(1)}</span>
      {count !== undefined && (
        <span className="rate-display__count">({count.toLocaleString()})</span>
      )}
    </div>
  );
}

export default Rating;

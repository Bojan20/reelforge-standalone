/**
 * ReelForge Skeleton
 *
 * Skeleton loading placeholder:
 * - Text, circular, rectangular shapes
 * - Pulse and wave animations
 * - Customizable dimensions
 * - Preset patterns
 *
 * @module skeleton/Skeleton
 */

import './Skeleton.css';

// ============ Types ============

export type SkeletonVariant = 'text' | 'circular' | 'rectangular' | 'rounded';
export type SkeletonAnimation = 'pulse' | 'wave' | 'none';

export interface SkeletonProps {
  /** Shape variant */
  variant?: SkeletonVariant;
  /** Animation type */
  animation?: SkeletonAnimation;
  /** Width (number = px, string = any CSS) */
  width?: number | string;
  /** Height (number = px, string = any CSS) */
  height?: number | string;
  /** Border radius for rounded variant */
  borderRadius?: number | string;
  /** Number of skeleton lines (for text) */
  lines?: number;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Skeleton({
  variant = 'text',
  animation = 'pulse',
  width,
  height,
  borderRadius,
  lines = 1,
  className = '',
}: SkeletonProps) {
  const style: React.CSSProperties = {};

  // Width
  if (width !== undefined) {
    style.width = typeof width === 'number' ? `${width}px` : width;
  }

  // Height
  if (height !== undefined) {
    style.height = typeof height === 'number' ? `${height}px` : height;
  }

  // Border radius
  if (borderRadius !== undefined) {
    style.borderRadius = typeof borderRadius === 'number' ? `${borderRadius}px` : borderRadius;
  }

  // Multiple lines for text variant
  if (variant === 'text' && lines > 1) {
    return (
      <div className={`skeleton-lines ${className}`}>
        {Array.from({ length: lines }).map((_, i) => (
          <div
            key={i}
            className={`skeleton skeleton--text skeleton--${animation}`}
            style={{
              ...style,
              width: i === lines - 1 ? '80%' : style.width, // Last line shorter
            }}
          />
        ))}
      </div>
    );
  }

  return (
    <div
      className={`skeleton skeleton--${variant} skeleton--${animation} ${className}`}
      style={style}
    />
  );
}

// ============ Skeleton Avatar ============

export interface SkeletonAvatarProps {
  /** Size */
  size?: 'small' | 'medium' | 'large' | number;
  /** Animation */
  animation?: SkeletonAnimation;
  /** Custom class */
  className?: string;
}

const AVATAR_SIZES = {
  small: 32,
  medium: 40,
  large: 56,
};

export function SkeletonAvatar({
  size = 'medium',
  animation = 'pulse',
  className = '',
}: SkeletonAvatarProps) {
  const sizeValue = typeof size === 'number' ? size : AVATAR_SIZES[size];

  return (
    <Skeleton
      variant="circular"
      width={sizeValue}
      height={sizeValue}
      animation={animation}
      className={className}
    />
  );
}

// ============ Skeleton Button ============

export interface SkeletonButtonProps {
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Width */
  width?: number | string;
  /** Animation */
  animation?: SkeletonAnimation;
  /** Custom class */
  className?: string;
}

const BUTTON_HEIGHTS = {
  small: 28,
  medium: 36,
  large: 44,
};

export function SkeletonButton({
  size = 'medium',
  width = 100,
  animation = 'pulse',
  className = '',
}: SkeletonButtonProps) {
  return (
    <Skeleton
      variant="rounded"
      width={width}
      height={BUTTON_HEIGHTS[size]}
      animation={animation}
      className={className}
    />
  );
}

// ============ Skeleton Card ============

export interface SkeletonCardProps {
  /** Show image placeholder */
  hasImage?: boolean;
  /** Image height */
  imageHeight?: number;
  /** Number of text lines */
  lines?: number;
  /** Animation */
  animation?: SkeletonAnimation;
  /** Custom class */
  className?: string;
}

export function SkeletonCard({
  hasImage = true,
  imageHeight = 140,
  lines = 3,
  animation = 'pulse',
  className = '',
}: SkeletonCardProps) {
  return (
    <div className={`skeleton-card ${className}`}>
      {hasImage && (
        <Skeleton
          variant="rectangular"
          width="100%"
          height={imageHeight}
          animation={animation}
        />
      )}
      <div className="skeleton-card__content">
        <Skeleton
          variant="text"
          width="60%"
          height={20}
          animation={animation}
        />
        <Skeleton
          variant="text"
          lines={lines}
          animation={animation}
        />
      </div>
    </div>
  );
}

// ============ Skeleton List ============

export interface SkeletonListProps {
  /** Number of items */
  count?: number;
  /** Show avatar */
  hasAvatar?: boolean;
  /** Number of text lines per item */
  lines?: number;
  /** Animation */
  animation?: SkeletonAnimation;
  /** Custom class */
  className?: string;
}

export function SkeletonList({
  count = 3,
  hasAvatar = true,
  lines = 2,
  animation = 'pulse',
  className = '',
}: SkeletonListProps) {
  return (
    <div className={`skeleton-list ${className}`}>
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="skeleton-list__item">
          {hasAvatar && (
            <SkeletonAvatar size="medium" animation={animation} />
          )}
          <div className="skeleton-list__content">
            <Skeleton
              variant="text"
              width="40%"
              height={16}
              animation={animation}
            />
            <Skeleton
              variant="text"
              lines={lines - 1}
              animation={animation}
            />
          </div>
        </div>
      ))}
    </div>
  );
}

// ============ Skeleton Table ============

export interface SkeletonTableProps {
  /** Number of rows */
  rows?: number;
  /** Number of columns */
  columns?: number;
  /** Show header */
  hasHeader?: boolean;
  /** Animation */
  animation?: SkeletonAnimation;
  /** Custom class */
  className?: string;
}

export function SkeletonTable({
  rows = 5,
  columns = 4,
  hasHeader = true,
  animation = 'pulse',
  className = '',
}: SkeletonTableProps) {
  return (
    <div className={`skeleton-table ${className}`}>
      {hasHeader && (
        <div className="skeleton-table__header">
          {Array.from({ length: columns }).map((_, i) => (
            <Skeleton
              key={i}
              variant="text"
              width={`${60 + Math.random() * 40}%`}
              height={14}
              animation={animation}
            />
          ))}
        </div>
      )}
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <div key={rowIndex} className="skeleton-table__row">
          {Array.from({ length: columns }).map((_, colIndex) => (
            <Skeleton
              key={colIndex}
              variant="text"
              width={`${50 + Math.random() * 50}%`}
              height={14}
              animation={animation}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

export default Skeleton;

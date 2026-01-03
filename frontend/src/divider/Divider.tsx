/**
 * ReelForge Divider
 *
 * Divider component:
 * - Horizontal and vertical orientation
 * - With or without label
 * - Dashed, dotted, solid styles
 * - Custom thickness
 *
 * @module divider/Divider
 */

import './Divider.css';

// ============ Types ============

export type DividerOrientation = 'horizontal' | 'vertical';
export type DividerVariant = 'solid' | 'dashed' | 'dotted';
export type DividerLabelPosition = 'start' | 'center' | 'end';

export interface DividerProps {
  /** Orientation */
  orientation?: DividerOrientation;
  /** Line variant */
  variant?: DividerVariant;
  /** Label text */
  label?: React.ReactNode;
  /** Label position */
  labelPosition?: DividerLabelPosition;
  /** Custom thickness (px) */
  thickness?: number;
  /** Custom color */
  color?: string;
  /** Spacing around divider */
  spacing?: 'none' | 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Divider({
  orientation = 'horizontal',
  variant = 'solid',
  label,
  labelPosition = 'center',
  thickness,
  color,
  spacing = 'medium',
  className = '',
}: DividerProps) {
  const style: React.CSSProperties = {};

  if (thickness) {
    if (orientation === 'horizontal') {
      style.borderTopWidth = `${thickness}px`;
    } else {
      style.borderLeftWidth = `${thickness}px`;
    }
  }

  if (color) {
    style.borderColor = color;
  }

  // Simple divider without label
  if (!label) {
    return (
      <div
        className={`divider divider--${orientation} divider--${variant} divider--spacing-${spacing} ${className}`}
        style={style}
        role="separator"
        aria-orientation={orientation}
      />
    );
  }

  // Divider with label (horizontal only makes sense)
  return (
    <div
      className={`divider-with-label divider-with-label--${labelPosition} divider--spacing-${spacing} ${className}`}
      role="separator"
    >
      <div
        className={`divider-with-label__line divider--${variant}`}
        style={style}
      />
      <span className="divider-with-label__text">{label}</span>
      <div
        className={`divider-with-label__line divider--${variant}`}
        style={style}
      />
    </div>
  );
}

// ============ Spacer Component ============

export interface SpacerProps {
  /** Size in pixels or CSS value */
  size?: number | string;
  /** Direction */
  direction?: 'horizontal' | 'vertical';
  /** Flex grow to fill space */
  flex?: boolean;
  /** Custom class */
  className?: string;
}

export function Spacer({
  size,
  direction = 'vertical',
  flex = false,
  className = '',
}: SpacerProps) {
  const style: React.CSSProperties = {};

  if (flex) {
    style.flex = 1;
  } else if (size !== undefined) {
    const sizeValue = typeof size === 'number' ? `${size}px` : size;
    if (direction === 'vertical') {
      style.height = sizeValue;
    } else {
      style.width = sizeValue;
    }
  }

  return (
    <div
      className={`spacer spacer--${direction} ${className}`}
      style={style}
      aria-hidden="true"
    />
  );
}

export default Divider;

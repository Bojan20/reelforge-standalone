/**
 * ReelForge Tag
 *
 * Tag/chip component:
 * - Labels and keywords
 * - Removable
 * - Selectable
 * - Icons
 * - Colors
 *
 * @module tag/Tag
 */

import './Tag.css';

// ============ Types ============

export type TagVariant = 'default' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
export type TagSize = 'small' | 'medium' | 'large';

export interface TagProps {
  /** Content */
  children: React.ReactNode;
  /** Variant */
  variant?: TagVariant;
  /** Size */
  size?: TagSize;
  /** Icon */
  icon?: React.ReactNode;
  /** Removable */
  onRemove?: () => void;
  /** Clickable */
  onClick?: () => void;
  /** Selected state */
  selected?: boolean;
  /** Disabled */
  disabled?: boolean;
  /** Outlined style */
  outlined?: boolean;
  /** Custom color */
  color?: string;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Tag({
  children,
  variant = 'default',
  size = 'medium',
  icon,
  onRemove,
  onClick,
  selected = false,
  disabled = false,
  outlined = false,
  color,
  className = '',
}: TagProps) {
  const isClickable = onClick && !disabled;

  const handleRemove = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!disabled && onRemove) {
      onRemove();
    }
  };

  return (
    <span
      className={`tag tag--${variant} tag--${size} ${
        outlined ? 'tag--outlined' : ''
      } ${selected ? 'tag--selected' : ''} ${
        disabled ? 'tag--disabled' : ''
      } ${isClickable ? 'tag--clickable' : ''} ${className}`}
      style={color ? { '--tag-color': color } as React.CSSProperties : undefined}
      onClick={isClickable ? onClick : undefined}
      role={isClickable ? 'button' : undefined}
      tabIndex={isClickable ? 0 : undefined}
    >
      {icon && <span className="tag__icon">{icon}</span>}
      <span className="tag__content">{children}</span>
      {onRemove && (
        <button
          type="button"
          className="tag__remove"
          onClick={handleRemove}
          disabled={disabled}
          aria-label="Remove"
        >
          ×
        </button>
      )}
    </span>
  );
}

// ============ Tag Group ============

export interface TagGroupProps {
  /** Children tags */
  children: React.ReactNode;
  /** Gap between tags */
  gap?: number;
  /** Wrap tags */
  wrap?: boolean;
  /** Custom class */
  className?: string;
}

export function TagGroup({
  children,
  gap = 8,
  wrap = true,
  className = '',
}: TagGroupProps) {
  return (
    <div
      className={`tag-group ${wrap ? 'tag-group--wrap' : ''} ${className}`}
      style={{ gap: `${gap}px` }}
    >
      {children}
    </div>
  );
}

// ============ Selectable Tag Group ============

export interface SelectableTagGroupProps {
  /** Options */
  options: { value: string; label: string; icon?: React.ReactNode }[];
  /** Selected values */
  value: string[];
  /** On change */
  onChange: (value: string[]) => void;
  /** Multiple selection */
  multiple?: boolean;
  /** Variant */
  variant?: TagVariant;
  /** Size */
  size?: TagSize;
  /** Custom class */
  className?: string;
}

export function SelectableTagGroup({
  options,
  value,
  onChange,
  multiple = true,
  variant = 'default',
  size = 'medium',
  className = '',
}: SelectableTagGroupProps) {
  const handleClick = (optionValue: string) => {
    if (multiple) {
      const newValue = value.includes(optionValue)
        ? value.filter((v) => v !== optionValue)
        : [...value, optionValue];
      onChange(newValue);
    } else {
      onChange(value.includes(optionValue) ? [] : [optionValue]);
    }
  };

  return (
    <TagGroup className={className}>
      {options.map((option) => (
        <Tag
          key={option.value}
          variant={variant}
          size={size}
          icon={option.icon}
          selected={value.includes(option.value)}
          onClick={() => handleClick(option.value)}
        >
          {option.label}
        </Tag>
      ))}
    </TagGroup>
  );
}

export default Tag;

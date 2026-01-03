/**
 * ReelForge ColorSwatch
 *
 * Color display and selection:
 * - Single color swatch
 * - Color palette
 * - Color picker integration
 * - Copy color value
 *
 * @module color-swatch/ColorSwatch
 */

import { useState, useCallback } from 'react';
import './ColorSwatch.css';

// ============ Types ============

export interface ColorSwatchProps {
  /** Color value (hex, rgb, hsl) */
  color: string;
  /** Swatch size */
  size?: 'small' | 'medium' | 'large' | number;
  /** Show color label */
  showLabel?: boolean;
  /** Label format */
  labelFormat?: 'hex' | 'rgb' | 'hsl' | 'name';
  /** Is selected */
  selected?: boolean;
  /** Click handler */
  onClick?: (color: string) => void;
  /** Show checkered background for transparency */
  showTransparency?: boolean;
  /** Custom label */
  label?: string;
  /** Tooltip */
  tooltip?: string;
  /** Shape */
  shape?: 'square' | 'circle';
  /** Disabled state */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface ColorPaletteProps {
  /** Colors in palette */
  colors: string[];
  /** Selected color */
  value?: string;
  /** On color select */
  onChange?: (color: string) => void;
  /** Swatch size */
  swatchSize?: 'small' | 'medium' | 'large' | number;
  /** Columns count */
  columns?: number;
  /** Gap between swatches */
  gap?: number;
  /** Swatch shape */
  shape?: 'square' | 'circle';
  /** Custom class */
  className?: string;
}

export interface ColorGradientProps {
  /** Gradient colors */
  colors: string[];
  /** Gradient direction (degrees) */
  direction?: number;
  /** Width */
  width?: number | string;
  /** Height */
  height?: number;
  /** Border radius */
  borderRadius?: number;
  /** Custom class */
  className?: string;
}

// ============ Size Mapping ============

const SIZE_MAP = {
  small: 24,
  medium: 32,
  large: 48,
};

// ============ Color Utilities ============

function hexToRgb(hex: string): { r: number; g: number; b: number } | null {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result
    ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16),
      }
    : null;
}

function getContrastColor(hex: string): string {
  const rgb = hexToRgb(hex);
  if (!rgb) return '#fff';

  // Calculate relative luminance
  const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255;
  return luminance > 0.5 ? '#000' : '#fff';
}

function formatColor(color: string, format: 'hex' | 'rgb' | 'hsl' | 'name'): string {
  if (format === 'hex') return color;

  const rgb = hexToRgb(color);
  if (!rgb) return color;

  if (format === 'rgb') {
    return `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`;
  }

  // HSL conversion
  const r = rgb.r / 255;
  const g = rgb.g / 255;
  const b = rgb.b / 255;

  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;

  let h = 0;
  let s = 0;

  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

    switch (max) {
      case r:
        h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
        break;
      case g:
        h = ((b - r) / d + 2) / 6;
        break;
      case b:
        h = ((r - g) / d + 4) / 6;
        break;
    }
  }

  return `hsl(${Math.round(h * 360)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`;
}

// ============ ColorSwatch Component ============

export function ColorSwatch({
  color,
  size = 'medium',
  showLabel = false,
  labelFormat = 'hex',
  selected = false,
  onClick,
  showTransparency = true,
  label,
  tooltip,
  shape = 'square',
  disabled = false,
  className = '',
}: ColorSwatchProps) {
  const sizeValue = typeof size === 'number' ? size : SIZE_MAP[size];
  const displayLabel = label || formatColor(color, labelFormat);
  const contrastColor = getContrastColor(color);

  const handleClick = () => {
    if (!disabled && onClick) {
      onClick(color);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if ((e.key === 'Enter' || e.key === ' ') && !disabled && onClick) {
      e.preventDefault();
      onClick(color);
    }
  };

  return (
    <div
      className={`color-swatch color-swatch--${shape} ${
        selected ? 'color-swatch--selected' : ''
      } ${disabled ? 'color-swatch--disabled' : ''} ${
        onClick ? 'color-swatch--clickable' : ''
      } ${className}`}
      style={{ width: sizeValue, height: sizeValue }}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick && !disabled ? 0 : undefined}
      title={tooltip || displayLabel}
      aria-label={`Color: ${displayLabel}`}
      aria-pressed={selected}
      aria-disabled={disabled}
    >
      {showTransparency && (
        <div className="color-swatch__transparency" aria-hidden="true" />
      )}
      <div
        className="color-swatch__color"
        style={{ backgroundColor: color }}
      />
      {selected && (
        <div className="color-swatch__check" style={{ color: contrastColor }}>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
            <polyline points="20 6 9 17 4 12" />
          </svg>
        </div>
      )}
      {showLabel && (
        <span className="color-swatch__label">{displayLabel}</span>
      )}
    </div>
  );
}

// ============ ColorPalette Component ============

export function ColorPalette({
  colors,
  value,
  onChange,
  swatchSize = 'medium',
  columns = 8,
  gap = 4,
  shape = 'square',
  className = '',
}: ColorPaletteProps) {
  return (
    <div
      className={`color-palette ${className}`}
      style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${columns}, 1fr)`,
        gap,
      }}
      role="radiogroup"
      aria-label="Color palette"
    >
      {colors.map((color) => (
        <ColorSwatch
          key={color}
          color={color}
          size={swatchSize}
          shape={shape}
          selected={value === color}
          onClick={onChange}
        />
      ))}
    </div>
  );
}

// ============ ColorGradient Component ============

export function ColorGradient({
  colors,
  direction = 90,
  width = '100%',
  height = 24,
  borderRadius = 4,
  className = '',
}: ColorGradientProps) {
  const gradient = `linear-gradient(${direction}deg, ${colors.join(', ')})`;

  return (
    <div
      className={`color-gradient ${className}`}
      style={{
        width,
        height,
        borderRadius,
        background: gradient,
      }}
      role="img"
      aria-label={`Gradient from ${colors[0]} to ${colors[colors.length - 1]}`}
    />
  );
}

// ============ ColorInput Component ============

export interface ColorInputProps {
  /** Current color value */
  value: string;
  /** On color change */
  onChange: (color: string) => void;
  /** Show native picker */
  showPicker?: boolean;
  /** Show text input */
  showInput?: boolean;
  /** Swatch size */
  swatchSize?: 'small' | 'medium' | 'large';
  /** Disabled state */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export function ColorInput({
  value,
  onChange,
  showPicker = true,
  showInput = true,
  swatchSize = 'medium',
  disabled = false,
  className = '',
}: ColorInputProps) {
  const [inputValue, setInputValue] = useState(value);

  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      setInputValue(newValue);

      // Validate hex
      if (/^#[0-9A-Fa-f]{6}$/.test(newValue)) {
        onChange(newValue);
      }
    },
    [onChange]
  );

  const handlePickerChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      setInputValue(newValue);
      onChange(newValue);
    },
    [onChange]
  );

  const sizeValue = typeof swatchSize === 'number' ? swatchSize : SIZE_MAP[swatchSize];

  return (
    <div className={`color-input ${disabled ? 'color-input--disabled' : ''} ${className}`}>
      <div
        className="color-input__swatch"
        style={{ width: sizeValue, height: sizeValue, backgroundColor: value }}
      >
        {showPicker && (
          <input
            type="color"
            value={value}
            onChange={handlePickerChange}
            disabled={disabled}
            className="color-input__picker"
            aria-label="Pick color"
          />
        )}
      </div>
      {showInput && (
        <input
          type="text"
          value={inputValue}
          onChange={handleInputChange}
          disabled={disabled}
          className="color-input__text"
          placeholder="#000000"
          maxLength={7}
          aria-label="Color hex value"
        />
      )}
    </div>
  );
}

// ============ Default Palettes ============

export const PALETTE_BASIC = [
  '#000000', '#ffffff', '#ff0000', '#00ff00',
  '#0000ff', '#ffff00', '#ff00ff', '#00ffff',
];

export const PALETTE_MATERIAL = [
  '#f44336', '#e91e63', '#9c27b0', '#673ab7',
  '#3f51b5', '#2196f3', '#03a9f4', '#00bcd4',
  '#009688', '#4caf50', '#8bc34a', '#cddc39',
  '#ffeb3b', '#ffc107', '#ff9800', '#ff5722',
];

export const PALETTE_TAILWIND = [
  '#ef4444', '#f97316', '#f59e0b', '#eab308',
  '#84cc16', '#22c55e', '#10b981', '#14b8a6',
  '#06b6d4', '#0ea5e9', '#3b82f6', '#6366f1',
  '#8b5cf6', '#a855f7', '#d946ef', '#ec4899',
];

export default ColorSwatch;

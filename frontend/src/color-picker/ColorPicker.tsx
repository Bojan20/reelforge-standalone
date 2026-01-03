/**
 * ReelForge Color Picker
 *
 * Color picker component:
 * - Saturation/brightness picker
 * - Hue slider
 * - Alpha slider
 * - HEX/RGB/HSL input
 * - Preset colors
 * - Eyedropper (if supported)
 *
 * @module color-picker/ColorPicker
 */

import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import './ColorPicker.css';

// ============ Types ============

export interface HSL {
  h: number; // 0-360
  s: number; // 0-100
  l: number; // 0-100
}

export interface RGB {
  r: number; // 0-255
  g: number; // 0-255
  b: number; // 0-255
}

export interface RGBA extends RGB {
  a: number; // 0-1
}

export interface ColorPickerProps {
  /** Current color (HEX) */
  value: string;
  /** On change */
  onChange: (color: string) => void;
  /** Show alpha slider */
  showAlpha?: boolean;
  /** Preset colors */
  presets?: string[];
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Color Utilities ============

function hexToRgb(hex: string): RGB {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) return { r: 0, g: 0, b: 0 };
  return {
    r: parseInt(result[1], 16),
    g: parseInt(result[2], 16),
    b: parseInt(result[3], 16),
  };
}

function rgbToHex(r: number, g: number, b: number): string {
  return '#' + [r, g, b].map((x) => {
    const hex = Math.round(x).toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }).join('');
}

function rgbToHsl(r: number, g: number, b: number): HSL {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h = 0;
  let s = 0;
  const l = (max + min) / 2;

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

  return { h: h * 360, s: s * 100, l: l * 100 };
}

function hslToRgb(h: number, s: number, l: number): RGB {
  h /= 360;
  s /= 100;
  l /= 100;

  if (s === 0) {
    const val = Math.round(l * 255);
    return { r: val, g: val, b: val };
  }

  const hue2rgb = (p: number, q: number, t: number) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };

  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;

  return {
    r: Math.round(hue2rgb(p, q, h + 1 / 3) * 255),
    g: Math.round(hue2rgb(p, q, h) * 255),
    b: Math.round(hue2rgb(p, q, h - 1 / 3) * 255),
  };
}

// ============ Component ============

const DEFAULT_PRESETS = [
  '#ff6b6b', '#ff922b', '#ffd43b', '#51cf66', '#20c997',
  '#4a9eff', '#7950f2', '#e64980', '#868e96', '#212529',
];

export function ColorPicker({
  value,
  onChange,
  showAlpha = false,
  presets = DEFAULT_PRESETS,
  disabled = false,
  className = '',
}: ColorPickerProps) {
  const [hexInput, setHexInput] = useState(value);
  const satBrightRef = useRef<HTMLDivElement>(null);
  const hueRef = useRef<HTMLDivElement>(null);
  const alphaRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState<'satBright' | 'hue' | 'alpha' | null>(null);
  const [alpha, setAlpha] = useState(1);

  // Parse current color
  const rgb = useMemo(() => hexToRgb(value), [value]);
  const hsl = useMemo(() => rgbToHsl(rgb.r, rgb.g, rgb.b), [rgb]);

  // Update hex input when value changes externally
  useEffect(() => {
    setHexInput(value);
  }, [value]);

  // Handle saturation/brightness change
  const handleSatBrightChange = useCallback(
    (clientX: number, clientY: number) => {
      if (!satBrightRef.current) return;

      const rect = satBrightRef.current.getBoundingClientRect();
      const s = Math.max(0, Math.min(100, ((clientX - rect.left) / rect.width) * 100));
      const l = Math.max(0, Math.min(100, 100 - ((clientY - rect.top) / rect.height) * 100));

      // Convert SV to SL (approximate)
      const newRgb = hslToRgb(hsl.h, Math.min(100, s), Math.max(0, Math.min(100, 50 + (l - 50) * (1 - s / 200))));
      onChange(rgbToHex(newRgb.r, newRgb.g, newRgb.b));
    },
    [hsl.h, onChange]
  );

  // Handle hue change
  const handleHueChange = useCallback(
    (clientX: number) => {
      if (!hueRef.current) return;

      const rect = hueRef.current.getBoundingClientRect();
      const h = Math.max(0, Math.min(360, ((clientX - rect.left) / rect.width) * 360));

      const newRgb = hslToRgb(h, hsl.s, hsl.l);
      onChange(rgbToHex(newRgb.r, newRgb.g, newRgb.b));
    },
    [hsl.s, hsl.l, onChange]
  );

  // Handle alpha change
  const handleAlphaChange = useCallback(
    (clientX: number) => {
      if (!alphaRef.current) return;

      const rect = alphaRef.current.getBoundingClientRect();
      const a = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
      setAlpha(a);
    },
    []
  );

  // Drag handlers
  useEffect(() => {
    if (!isDragging) return;

    const handleMove = (e: MouseEvent) => {
      switch (isDragging) {
        case 'satBright':
          handleSatBrightChange(e.clientX, e.clientY);
          break;
        case 'hue':
          handleHueChange(e.clientX);
          break;
        case 'alpha':
          handleAlphaChange(e.clientX);
          break;
      }
    };

    const handleUp = () => {
      setIsDragging(null);
    };

    document.addEventListener('mousemove', handleMove);
    document.addEventListener('mouseup', handleUp);

    return () => {
      document.removeEventListener('mousemove', handleMove);
      document.removeEventListener('mouseup', handleUp);
    };
  }, [isDragging, handleSatBrightChange, handleHueChange, handleAlphaChange]);

  // Handle hex input
  const handleHexChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newHex = e.target.value;
    setHexInput(newHex);

    if (/^#[0-9A-Fa-f]{6}$/.test(newHex)) {
      onChange(newHex);
    }
  };

  // Handle preset click
  const handlePresetClick = (color: string) => {
    onChange(color);
  };

  // Calculate positions
  const satBrightPos = {
    x: hsl.s,
    y: 100 - hsl.l,
  };

  return (
    <div className={`color-picker ${disabled ? 'color-picker--disabled' : ''} ${className}`}>
      {/* Saturation/Brightness area */}
      <div
        ref={satBrightRef}
        className="color-picker__sat-bright"
        style={{ backgroundColor: `hsl(${hsl.h}, 100%, 50%)` }}
        onMouseDown={(e) => {
          if (disabled) return;
          setIsDragging('satBright');
          handleSatBrightChange(e.clientX, e.clientY);
        }}
      >
        <div className="color-picker__sat-overlay" />
        <div className="color-picker__bright-overlay" />
        <div
          className="color-picker__cursor"
          style={{
            left: `${satBrightPos.x}%`,
            top: `${satBrightPos.y}%`,
          }}
        />
      </div>

      {/* Sliders */}
      <div className="color-picker__sliders">
        {/* Hue slider */}
        <div
          ref={hueRef}
          className="color-picker__hue"
          onMouseDown={(e) => {
            if (disabled) return;
            setIsDragging('hue');
            handleHueChange(e.clientX);
          }}
        >
          <div
            className="color-picker__slider-thumb"
            style={{ left: `${(hsl.h / 360) * 100}%` }}
          />
        </div>

        {/* Alpha slider */}
        {showAlpha && (
          <div
            ref={alphaRef}
            className="color-picker__alpha"
            style={{
              background: `linear-gradient(to right, transparent, ${value})`,
            }}
            onMouseDown={(e) => {
              if (disabled) return;
              setIsDragging('alpha');
              handleAlphaChange(e.clientX);
            }}
          >
            <div
              className="color-picker__slider-thumb"
              style={{ left: `${alpha * 100}%` }}
            />
          </div>
        )}
      </div>

      {/* Input */}
      <div className="color-picker__input-row">
        <div
          className="color-picker__preview"
          style={{ backgroundColor: value }}
        />
        <input
          type="text"
          className="color-picker__input"
          value={hexInput}
          onChange={handleHexChange}
          disabled={disabled}
          maxLength={7}
        />
      </div>

      {/* Presets */}
      {presets.length > 0 && (
        <div className="color-picker__presets">
          {presets.map((color) => (
            <button
              key={color}
              className={`color-picker__preset ${
                value.toLowerCase() === color.toLowerCase()
                  ? 'color-picker__preset--active'
                  : ''
              }`}
              style={{ backgroundColor: color }}
              onClick={() => handlePresetClick(color)}
              disabled={disabled}
              aria-label={`Select color ${color}`}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// Export utilities
export { hexToRgb, rgbToHex, rgbToHsl, hslToRgb };

export default ColorPicker;

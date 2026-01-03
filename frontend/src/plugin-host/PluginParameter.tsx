/**
 * ReelForge Plugin Parameter Controls
 *
 * UI components for plugin parameters:
 * - Knob (rotary)
 * - Slider (horizontal/vertical)
 * - Toggle (on/off)
 * - Select (dropdown)
 * - Meter (read-only display)
 *
 * @module plugin-host/PluginParameter
 */

import { useState, useCallback, useRef } from 'react';
import './PluginParameter.css';

// ============ Types ============

export type ParameterType = 'knob' | 'slider' | 'toggle' | 'select' | 'meter';

export interface ParameterOption {
  value: number;
  label: string;
}

export interface BaseParameterProps {
  /** Parameter ID */
  id: string;
  /** Display name */
  name: string;
  /** Current value (0-1 normalized) */
  value: number;
  /** Default value */
  defaultValue?: number;
  /** Display value string */
  displayValue?: string;
  /** Unit suffix */
  unit?: string;
  /** On value change */
  onChange?: (value: number) => void;
  /** On value commit (mouse up) */
  onCommit?: (value: number) => void;
  /** Is disabled */
  disabled?: boolean;
  /** Compact mode */
  compact?: boolean;
}

export interface KnobProps extends BaseParameterProps {
  type: 'knob';
  /** Size in pixels */
  size?: number;
  /** Min angle in degrees */
  minAngle?: number;
  /** Max angle in degrees */
  maxAngle?: number;
}

export interface SliderProps extends BaseParameterProps {
  type: 'slider';
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
  /** Show value label */
  showValue?: boolean;
}

export interface ToggleProps extends BaseParameterProps {
  type: 'toggle';
  /** On label */
  onLabel?: string;
  /** Off label */
  offLabel?: string;
}

export interface SelectProps extends BaseParameterProps {
  type: 'select';
  /** Options */
  options: ParameterOption[];
}

export interface MeterProps extends BaseParameterProps {
  type: 'meter';
  /** Peak value */
  peak?: number;
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
}

export type PluginParameterProps =
  | KnobProps
  | SliderProps
  | ToggleProps
  | SelectProps
  | MeterProps;

// ============ Knob Component ============

function Knob({
  id: _id,
  name,
  value,
  defaultValue = 0.5,
  displayValue,
  unit = '',
  onChange,
  onCommit,
  disabled = false,
  compact = false,
  size = 48,
  minAngle = -135,
  maxAngle = 135,
}: KnobProps) {
  const [isDragging, setIsDragging] = useState(false);
  const knobRef = useRef<HTMLDivElement>(null);
  const startYRef = useRef(0);
  const startValueRef = useRef(0);

  const angle = minAngle + value * (maxAngle - minAngle);

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (disabled) return;
      e.preventDefault();
      setIsDragging(true);
      startYRef.current = e.clientY;
      startValueRef.current = value;

      const handleMouseMove = (e: MouseEvent) => {
        const deltaY = startYRef.current - e.clientY;
        const sensitivity = e.shiftKey ? 0.001 : 0.005;
        const newValue = Math.max(
          0,
          Math.min(1, startValueRef.current + deltaY * sensitivity)
        );
        onChange?.(newValue);
      };

      const handleMouseUp = () => {
        setIsDragging(false);
        onCommit?.(value);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [value, onChange, onCommit, disabled]
  );

  const handleDoubleClick = useCallback(() => {
    if (disabled) return;
    onChange?.(defaultValue);
    onCommit?.(defaultValue);
  }, [defaultValue, onChange, onCommit, disabled]);

  return (
    <div
      className={`plugin-param plugin-param--knob ${compact ? 'plugin-param--compact' : ''} ${
        disabled ? 'plugin-param--disabled' : ''
      } ${isDragging ? 'plugin-param--dragging' : ''}`}
    >
      {!compact && <label className="plugin-param__label">{name}</label>}
      <div
        ref={knobRef}
        className="plugin-param__knob"
        style={{ width: size, height: size }}
        onMouseDown={handleMouseDown}
        onDoubleClick={handleDoubleClick}
        title={name}
      >
        <div className="plugin-param__knob-track" />
        <div
          className="plugin-param__knob-indicator"
          style={{ transform: `rotate(${angle}deg)` }}
        />
        <div className="plugin-param__knob-center" />
      </div>
      <span className="plugin-param__value">
        {displayValue ?? `${Math.round(value * 100)}${unit}`}
      </span>
    </div>
  );
}

// ============ Slider Component ============

function Slider({
  id: _id,
  name,
  value,
  defaultValue = 0.5,
  displayValue,
  unit = '',
  onChange,
  onCommit,
  disabled = false,
  compact = false,
  orientation = 'horizontal',
  showValue = true,
}: SliderProps) {
  const [isDragging, setIsDragging] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (disabled || !trackRef.current) return;
      e.preventDefault();
      setIsDragging(true);

      const updateValue = (clientX: number, clientY: number) => {
        if (!trackRef.current) return;
        const rect = trackRef.current.getBoundingClientRect();
        let newValue: number;

        if (orientation === 'horizontal') {
          newValue = (clientX - rect.left) / rect.width;
        } else {
          newValue = 1 - (clientY - rect.top) / rect.height;
        }

        newValue = Math.max(0, Math.min(1, newValue));
        onChange?.(newValue);
      };

      updateValue(e.clientX, e.clientY);

      const handleMouseMove = (e: MouseEvent) => {
        updateValue(e.clientX, e.clientY);
      };

      const handleMouseUp = () => {
        setIsDragging(false);
        onCommit?.(value);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [value, onChange, onCommit, disabled, orientation]
  );

  const handleDoubleClick = useCallback(() => {
    if (disabled) return;
    onChange?.(defaultValue);
    onCommit?.(defaultValue);
  }, [defaultValue, onChange, onCommit, disabled]);

  return (
    <div
      className={`plugin-param plugin-param--slider plugin-param--${orientation} ${
        compact ? 'plugin-param--compact' : ''
      } ${disabled ? 'plugin-param--disabled' : ''} ${
        isDragging ? 'plugin-param--dragging' : ''
      }`}
    >
      {!compact && <label className="plugin-param__label">{name}</label>}
      <div
        ref={trackRef}
        className="plugin-param__slider-track"
        onMouseDown={handleMouseDown}
        onDoubleClick={handleDoubleClick}
        title={name}
      >
        <div
          className="plugin-param__slider-fill"
          style={
            orientation === 'horizontal'
              ? { width: `${value * 100}%` }
              : { height: `${value * 100}%` }
          }
        />
        <div
          className="plugin-param__slider-thumb"
          style={
            orientation === 'horizontal'
              ? { left: `${value * 100}%` }
              : { bottom: `${value * 100}%` }
          }
        />
      </div>
      {showValue && (
        <span className="plugin-param__value">
          {displayValue ?? `${Math.round(value * 100)}${unit}`}
        </span>
      )}
    </div>
  );
}

// ============ Toggle Component ============

function Toggle({
  id: _id,
  name,
  value,
  onChange,
  onCommit,
  disabled = false,
  compact = false,
  onLabel = 'ON',
  offLabel = 'OFF',
}: ToggleProps) {
  const isOn = value >= 0.5;

  const handleClick = useCallback(() => {
    if (disabled) return;
    const newValue = isOn ? 0 : 1;
    onChange?.(newValue);
    onCommit?.(newValue);
  }, [isOn, onChange, onCommit, disabled]);

  return (
    <div
      className={`plugin-param plugin-param--toggle ${compact ? 'plugin-param--compact' : ''} ${
        disabled ? 'plugin-param--disabled' : ''
      }`}
    >
      {!compact && <label className="plugin-param__label">{name}</label>}
      <button
        className={`plugin-param__toggle ${isOn ? 'plugin-param__toggle--on' : ''}`}
        onClick={handleClick}
        disabled={disabled}
        title={name}
      >
        <span className="plugin-param__toggle-label">
          {isOn ? onLabel : offLabel}
        </span>
      </button>
    </div>
  );
}

// ============ Select Component ============

function Select({
  id: _id,
  name,
  value,
  options,
  onChange,
  onCommit,
  disabled = false,
  compact = false,
}: SelectProps) {
  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      const newValue = parseFloat(e.target.value);
      onChange?.(newValue);
      onCommit?.(newValue);
    },
    [onChange, onCommit]
  );

  // Find closest option
  const selectedValue = options.reduce((prev, curr) =>
    Math.abs(curr.value - value) < Math.abs(prev.value - value) ? curr : prev
  ).value;

  return (
    <div
      className={`plugin-param plugin-param--select ${compact ? 'plugin-param--compact' : ''} ${
        disabled ? 'plugin-param--disabled' : ''
      }`}
    >
      {!compact && <label className="plugin-param__label">{name}</label>}
      <select
        className="plugin-param__select"
        value={selectedValue}
        onChange={handleChange}
        disabled={disabled}
        title={name}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

// ============ Meter Component ============

function Meter({
  id: _id,
  name,
  value,
  peak = 0,
  compact = false,
  orientation = 'vertical',
}: MeterProps) {
  return (
    <div
      className={`plugin-param plugin-param--meter plugin-param--${orientation} ${
        compact ? 'plugin-param--compact' : ''
      }`}
    >
      {!compact && <label className="plugin-param__label">{name}</label>}
      <div className="plugin-param__meter">
        <div
          className="plugin-param__meter-fill"
          style={
            orientation === 'horizontal'
              ? { width: `${value * 100}%` }
              : { height: `${value * 100}%` }
          }
        />
        {peak > 0 && (
          <div
            className="plugin-param__meter-peak"
            style={
              orientation === 'horizontal'
                ? { left: `${peak * 100}%` }
                : { bottom: `${peak * 100}%` }
            }
          />
        )}
      </div>
    </div>
  );
}

// ============ Main Component ============

export function PluginParameter(props: PluginParameterProps) {
  switch (props.type) {
    case 'knob':
      return <Knob {...props} />;
    case 'slider':
      return <Slider {...props} />;
    case 'toggle':
      return <Toggle {...props} />;
    case 'select':
      return <Select {...props} />;
    case 'meter':
      return <Meter {...props} />;
    default:
      return null;
  }
}

export default PluginParameter;

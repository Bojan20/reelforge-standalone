/**
 * ReelForge TimePicker
 *
 * Time selection components:
 * - Hour/minute/second pickers
 * - 12/24 hour format
 * - Time range
 * - Keyboard navigation
 *
 * @module time-picker/TimePicker
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './TimePicker.css';

// ============ Types ============

export interface Time {
  hours: number;
  minutes: number;
  seconds?: number;
}

export interface TimePickerProps {
  /** Current time value */
  value?: Time | null;
  /** On time change */
  onChange?: (time: Time | null) => void;
  /** 12 or 24 hour format */
  format?: '12h' | '24h';
  /** Show seconds */
  showSeconds?: boolean;
  /** Minute step */
  minuteStep?: number;
  /** Second step */
  secondStep?: number;
  /** Minimum time */
  minTime?: Time;
  /** Maximum time */
  maxTime?: Time;
  /** Disabled state */
  disabled?: boolean;
  /** Placeholder text */
  placeholder?: string;
  /** Custom class */
  className?: string;
}

export interface TimeInputProps {
  /** Current time value */
  value?: Time | null;
  /** On time change */
  onChange?: (time: Time | null) => void;
  /** 12 or 24 hour format */
  format?: '12h' | '24h';
  /** Show seconds */
  showSeconds?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface TimeColumnProps {
  /** Values to display */
  values: number[];
  /** Selected value */
  selected: number;
  /** On select */
  onSelect: (value: number) => void;
  /** Format function */
  format?: (value: number) => string;
  /** Disabled values */
  disabled?: number[];
}

// ============ Time Utilities ============

function padZero(n: number): string {
  return n.toString().padStart(2, '0');
}

function formatTime(time: Time, format: '12h' | '24h', showSeconds: boolean): string {
  let hours = time.hours;
  let period = '';

  if (format === '12h') {
    period = hours >= 12 ? ' PM' : ' AM';
    hours = hours % 12 || 12;
  }

  let result = `${padZero(hours)}:${padZero(time.minutes)}`;
  if (showSeconds && time.seconds !== undefined) {
    result += `:${padZero(time.seconds)}`;
  }
  result += period;

  return result;
}

function parseTimeString(str: string): Time | null {
  const match = str.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*(AM|PM))?$/i);
  if (!match) return null;

  let hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  const seconds = match[3] ? parseInt(match[3], 10) : 0;
  const period = match[4]?.toUpperCase();

  if (period === 'PM' && hours < 12) hours += 12;
  if (period === 'AM' && hours === 12) hours = 0;

  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59) {
    return null;
  }

  return { hours, minutes, seconds };
}

function isTimeInRange(time: Time, min?: Time, max?: Time): boolean {
  const toMinutes = (t: Time) => t.hours * 60 + t.minutes;
  const value = toMinutes(time);

  if (min && value < toMinutes(min)) return false;
  if (max && value > toMinutes(max)) return false;

  return true;
}

// ============ TimeColumn Component ============

function TimeColumn({
  values,
  selected,
  onSelect,
  format = padZero,
  disabled = [],
}: TimeColumnProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  // Scroll to selected on mount
  useEffect(() => {
    if (containerRef.current) {
      const selectedEl = containerRef.current.querySelector('.time-column__item--selected');
      if (selectedEl) {
        selectedEl.scrollIntoView({ block: 'center', behavior: 'instant' });
      }
    }
  }, [selected]);

  return (
    <div ref={containerRef} className="time-column">
      {values.map((value) => {
        const isDisabled = disabled.includes(value);
        return (
          <button
            key={value}
            type="button"
            className={`time-column__item ${
              value === selected ? 'time-column__item--selected' : ''
            } ${isDisabled ? 'time-column__item--disabled' : ''}`}
            onClick={() => !isDisabled && onSelect(value)}
            disabled={isDisabled}
          >
            {format(value)}
          </button>
        );
      })}
    </div>
  );
}

// ============ TimePanel Component ============

interface TimePanelProps {
  value: Time;
  onChange: (time: Time) => void;
  format: '12h' | '24h';
  showSeconds: boolean;
  minuteStep: number;
  secondStep: number;
  minTime?: Time;
  maxTime?: Time;
}

function TimePanel({
  value,
  onChange,
  format,
  showSeconds,
  minuteStep,
  secondStep,
}: TimePanelProps) {
  const hours = format === '24h'
    ? Array.from({ length: 24 }, (_, i) => i)
    : Array.from({ length: 12 }, (_, i) => i + 1);

  const minutes = Array.from({ length: 60 / minuteStep }, (_, i) => i * minuteStep);
  const seconds = Array.from({ length: 60 / secondStep }, (_, i) => i * secondStep);

  const displayHour = format === '12h' ? (value.hours % 12 || 12) : value.hours;
  const isPM = value.hours >= 12;

  const handleHourChange = (hour: number) => {
    let newHour = hour;
    if (format === '12h') {
      if (isPM && hour !== 12) newHour = hour + 12;
      else if (!isPM && hour === 12) newHour = 0;
    }
    onChange({ ...value, hours: newHour });
  };

  const handleMinuteChange = (minute: number) => {
    onChange({ ...value, minutes: minute });
  };

  const handleSecondChange = (second: number) => {
    onChange({ ...value, seconds: second });
  };

  const handlePeriodChange = (pm: boolean) => {
    let newHour = value.hours;
    if (pm && newHour < 12) newHour += 12;
    else if (!pm && newHour >= 12) newHour -= 12;
    onChange({ ...value, hours: newHour });
  };

  return (
    <div className="time-panel">
      <TimeColumn
        values={hours}
        selected={displayHour}
        onSelect={handleHourChange}
        format={padZero}
      />
      <span className="time-panel__separator">:</span>
      <TimeColumn
        values={minutes}
        selected={value.minutes}
        onSelect={handleMinuteChange}
        format={padZero}
      />
      {showSeconds && (
        <>
          <span className="time-panel__separator">:</span>
          <TimeColumn
            values={seconds}
            selected={value.seconds || 0}
            onSelect={handleSecondChange}
            format={padZero}
          />
        </>
      )}
      {format === '12h' && (
        <div className="time-panel__period">
          <button
            type="button"
            className={`time-panel__period-btn ${!isPM ? 'time-panel__period-btn--active' : ''}`}
            onClick={() => handlePeriodChange(false)}
          >
            AM
          </button>
          <button
            type="button"
            className={`time-panel__period-btn ${isPM ? 'time-panel__period-btn--active' : ''}`}
            onClick={() => handlePeriodChange(true)}
          >
            PM
          </button>
        </div>
      )}
    </div>
  );
}

// ============ TimePicker Component ============

export function TimePicker({
  value,
  onChange,
  format = '24h',
  showSeconds = false,
  minuteStep = 1,
  secondStep = 1,
  minTime,
  maxTime,
  disabled = false,
  placeholder = 'Select time...',
  className = '',
}: TimePickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [localValue, setLocalValue] = useState<Time>(
    value || { hours: 12, minutes: 0, seconds: 0 }
  );

  const displayValue = value ? formatTime(value, format, showSeconds) : '';

  const handleSelect = (time: Time) => {
    if (!isTimeInRange(time, minTime, maxTime)) return;
    setLocalValue(time);
    onChange?.(time);
  };

  const handleConfirm = () => {
    onChange?.(localValue);
    setIsOpen(false);
  };

  const handleClear = () => {
    onChange?.(null);
    setIsOpen(false);
  };

  return (
    <div className={`time-picker ${isOpen ? 'time-picker--open' : ''} ${className}`}>
      <div
        className={`time-picker__input ${disabled ? 'time-picker__input--disabled' : ''}`}
        onClick={() => !disabled && setIsOpen(!isOpen)}
      >
        <span className="time-picker__value">{displayValue || placeholder}</span>
        <span className="time-picker__icon">🕐</span>
      </div>

      {isOpen && (
        <div className="time-picker__dropdown">
          <TimePanel
            value={localValue}
            onChange={handleSelect}
            format={format}
            showSeconds={showSeconds}
            minuteStep={minuteStep}
            secondStep={secondStep}
            minTime={minTime}
            maxTime={maxTime}
          />
          <div className="time-picker__actions">
            <button
              type="button"
              className="time-picker__action time-picker__action--clear"
              onClick={handleClear}
            >
              Clear
            </button>
            <button
              type="button"
              className="time-picker__action time-picker__action--confirm"
              onClick={handleConfirm}
            >
              OK
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ============ TimeInput Component ============

export function TimeInput({
  value,
  onChange,
  format = '24h',
  showSeconds = false,
  disabled = false,
  className = '',
}: TimeInputProps) {
  const [inputValue, setInputValue] = useState(
    value ? formatTime(value, format, showSeconds) : ''
  );

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const str = e.target.value;
      setInputValue(str);

      const parsed = parseTimeString(str);
      if (parsed) {
        onChange?.(parsed);
      }
    },
    [onChange]
  );

  const handleBlur = useCallback(() => {
    if (value) {
      setInputValue(formatTime(value, format, showSeconds));
    }
  }, [value, format, showSeconds]);

  return (
    <input
      type="text"
      className={`time-input ${className}`}
      value={inputValue}
      onChange={handleChange}
      onBlur={handleBlur}
      disabled={disabled}
      placeholder={format === '12h' ? '12:00 PM' : '12:00'}
    />
  );
}

// ============ Quick Time Presets ============

export interface TimePresetsProps {
  /** Preset times */
  presets: Array<{ label: string; time: Time }>;
  /** On select */
  onSelect: (time: Time) => void;
  /** Selected time for highlighting */
  value?: Time | null;
  /** Custom class */
  className?: string;
}

export function TimePresets({
  presets,
  onSelect,
  value,
  className = '',
}: TimePresetsProps) {
  const isSelected = (t: Time) =>
    value && t.hours === value.hours && t.minutes === value.minutes;

  return (
    <div className={`time-presets ${className}`}>
      {presets.map((preset) => (
        <button
          key={preset.label}
          type="button"
          className={`time-presets__item ${
            isSelected(preset.time) ? 'time-presets__item--selected' : ''
          }`}
          onClick={() => onSelect(preset.time)}
        >
          {preset.label}
        </button>
      ))}
    </div>
  );
}

// ============ Common Presets ============

export const COMMON_PRESETS = [
  { label: 'Morning', time: { hours: 9, minutes: 0 } },
  { label: 'Noon', time: { hours: 12, minutes: 0 } },
  { label: 'Afternoon', time: { hours: 15, minutes: 0 } },
  { label: 'Evening', time: { hours: 18, minutes: 0 } },
  { label: 'Night', time: { hours: 21, minutes: 0 } },
];

export default TimePicker;

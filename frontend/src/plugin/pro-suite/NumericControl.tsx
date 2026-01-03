/**
 * ReelForge Pro Suite - Numeric Control Component (Input Engine v2)
 *
 * DAW-grade numeric control with:
 * - Pointer capture for reliable drag
 * - Sensitivity curve (acceleration based on delta)
 * - Shift for fine control
 * - Alt+click to reset
 * - Double-click typing with Enter/Esc
 * - Throttled drag updates
 * - Commit on mouse up
 *
 * @module plugin/pro-suite/NumericControl
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import type { ProSuiteTheme } from './theme';

// ============ Throttle Utility ============

function createThrottle<Args extends unknown[]>(
  fn: (...args: Args) => void,
  intervalMs: number
): ((...args: Args) => void) & { flush: () => void; cancel: () => void } {
  let lastCall = 0;
  let pendingArgs: Args | null = null;
  let rafId: number | null = null;

  const throttled = ((...args: Args) => {
    const now = Date.now();
    const elapsed = now - lastCall;

    if (elapsed >= intervalMs) {
      lastCall = now;
      fn(...args);
    } else {
      pendingArgs = args;
      if (!rafId) {
        rafId = requestAnimationFrame(() => {
          if (pendingArgs) {
            lastCall = Date.now();
            fn(...pendingArgs);
            pendingArgs = null;
          }
          rafId = null;
        });
      }
    }
  }) as ((...args: Args) => void) & { flush: () => void; cancel: () => void };

  throttled.flush = () => {
    if (pendingArgs) {
      fn(...pendingArgs);
      pendingArgs = null;
    }
    if (rafId) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
  };

  throttled.cancel = () => {
    pendingArgs = null;
    if (rafId) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
  };

  return throttled;
}

// ============ Sensitivity Curve ============

/**
 * Apply sensitivity curve to drag delta.
 * Small movements = precise, large movements = faster.
 */
function applySensitivityCurve(deltaPixels: number, isFine: boolean): number {
  const absDelta = Math.abs(deltaPixels);
  const sign = deltaPixels >= 0 ? 1 : -1;

  // Base sensitivity (pixels per unit)
  const basePixelsPerUnit = isFine ? 8 : 2;

  // Apply acceleration curve for large movements
  let multiplier = 1;
  if (absDelta > 50) {
    multiplier = 1 + (absDelta - 50) * 0.02;
  }

  return sign * (absDelta / basePixelsPerUnit) * multiplier;
}

// ============ Types ============

export interface NumericControlProps {
  value: number;
  min: number;
  max: number;
  step?: number;
  fineStep?: number;
  defaultValue: number;
  label: string;
  unit?: string;
  decimals?: number;
  onChange: (value: number) => void;
  onReset?: () => void;
  theme: ProSuiteTheme;
  readOnly?: boolean;
  width?: number;
}

// ============ Component ============

export function NumericControl({
  value,
  min,
  max,
  step = 1,
  fineStep,
  defaultValue,
  label,
  unit = '',
  decimals = 1,
  onChange,
  onReset,
  theme,
  readOnly = false,
  width = 60,
}: NumericControlProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const valueRef = useRef<HTMLDivElement>(null);
  const dragStartRef = useRef<{ y: number; value: number; accumulatedDelta: number } | null>(null);
  const throttledOnChangeRef = useRef<ReturnType<typeof createThrottle<[number]>> | null>(null);

  // Format value for display
  const formatValue = useCallback((val: number) => {
    return val.toFixed(decimals);
  }, [decimals]);

  // Handle double-click to edit
  const handleDoubleClick = useCallback(() => {
    if (readOnly) return;
    setEditValue(formatValue(value));
    setIsEditing(true);
  }, [readOnly, value, formatValue]);

  // Focus input when editing starts
  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  // Handle input change
  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setEditValue(e.target.value);
  }, []);

  // Commit edit
  const commitEdit = useCallback(() => {
    const parsed = parseFloat(editValue);
    if (!isNaN(parsed)) {
      const clamped = Math.max(min, Math.min(max, parsed));
      onChange(clamped);
    }
    setIsEditing(false);
  }, [editValue, min, max, onChange]);

  // Cancel edit
  const cancelEdit = useCallback(() => {
    setIsEditing(false);
  }, []);

  // Handle key press in input
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      commitEdit();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      cancelEdit();
    }
  }, [commitEdit, cancelEdit]);

  // Handle blur
  const handleBlur = useCallback(() => {
    commitEdit();
  }, [commitEdit]);

  // Handle pointer down for dragging with pointer capture
  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    if (readOnly || isEditing) return;

    // Alt+click to reset
    if (e.altKey) {
      e.preventDefault();
      if (onReset) {
        onReset();
      } else {
        onChange(defaultValue);
      }
      return;
    }

    // Capture pointer for reliable tracking
    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);

    setIsDragging(true);
    dragStartRef.current = { y: e.clientY, value, accumulatedDelta: 0 };

    // Create throttled onChange for smooth updates
    throttledOnChangeRef.current = createThrottle((newValue: number) => {
      onChange(newValue);
    }, 16); // ~60fps
  }, [readOnly, isEditing, value, defaultValue, onChange, onReset]);

  // Handle pointer move during drag
  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!dragStartRef.current || !throttledOnChangeRef.current) return;

    const deltaY = dragStartRef.current.y - e.clientY;
    const isFine = e.shiftKey;
    const effectiveStep = isFine ? (fineStep ?? step * 0.1) : step;

    // Apply sensitivity curve
    const sensitivityDelta = applySensitivityCurve(deltaY, isFine);

    // Calculate new value
    const deltaValue = sensitivityDelta * effectiveStep;
    let newValue = dragStartRef.current.value + deltaValue;

    // Clamp to range
    newValue = Math.max(min, Math.min(max, newValue));

    // Round to step precision
    const stepPrecision = Math.max(0, -Math.floor(Math.log10(effectiveStep)));
    newValue = Math.round(newValue * Math.pow(10, stepPrecision)) / Math.pow(10, stepPrecision);

    throttledOnChangeRef.current(newValue);
  }, [min, max, step, fineStep]);

  // Handle pointer up - commit on mouse up
  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const target = e.currentTarget as HTMLElement;
    target.releasePointerCapture(e.pointerId);

    // Flush any pending throttled updates
    if (throttledOnChangeRef.current) {
      throttledOnChangeRef.current.flush();
      throttledOnChangeRef.current = null;
    }

    setIsDragging(false);
    dragStartRef.current = null;
  }, []);

  // Handle lost pointer capture
  const handleLostPointerCapture = useCallback(() => {
    if (throttledOnChangeRef.current) {
      throttledOnChangeRef.current.flush();
      throttledOnChangeRef.current = null;
    }
    setIsDragging(false);
    dragStartRef.current = null;
  }, []);

  // Focus/hover state for styling
  const handleMouseEnter = useCallback(() => {
    if (!readOnly) setIsFocused(true);
  }, [readOnly]);

  const handleMouseLeave = useCallback(() => {
    if (!isDragging) setIsFocused(false);
  }, [isDragging]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (throttledOnChangeRef.current) {
        throttledOnChangeRef.current.cancel();
      }
    };
  }, []);

  return (
    <div
      className={`vp-numeric-control ${isDragging ? 'dragging' : ''} ${readOnly ? 'readonly' : ''} ${isFocused ? 'focused' : ''}`}
      style={{ width }}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <div className="vp-numeric-label" style={{ color: theme.textSecondary }}>
        {label}
      </div>
      {isEditing ? (
        <input
          ref={inputRef}
          type="text"
          className="vp-numeric-input"
          value={editValue}
          onChange={handleInputChange}
          onKeyDown={handleKeyDown}
          onBlur={handleBlur}
          style={{
            backgroundColor: theme.inputBg,
            color: theme.textPrimary,
            borderColor: theme.inputBorderFocus,
          }}
        />
      ) : (
        <div
          ref={valueRef}
          className="vp-numeric-value"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onLostPointerCapture={handleLostPointerCapture}
          onDoubleClick={handleDoubleClick}
          style={{
            backgroundColor: theme.inputBg,
            color: theme.textPrimary,
            borderColor: isDragging ? theme.accentPrimary : (isFocused ? theme.inputBorderFocus : theme.inputBorder),
            cursor: readOnly ? 'default' : 'ns-resize',
            touchAction: 'none', // Prevent scroll during drag
          }}
        >
          {formatValue(value)}{unit}
        </div>
      )}
    </div>
  );
}

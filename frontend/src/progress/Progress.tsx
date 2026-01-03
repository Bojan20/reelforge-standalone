/**
 * ReelForge Progress
 *
 * Progress indicator components:
 * - Linear progress bar
 * - Circular progress
 * - Indeterminate mode
 * - Labels and percentages
 *
 * @module progress/Progress
 */

import './Progress.css';

// ============ Types ============

export type ProgressVariant = 'default' | 'primary' | 'success' | 'warning' | 'danger';
export type ProgressSize = 'small' | 'medium' | 'large';

export interface ProgressProps {
  /** Value (0-100) */
  value: number;
  /** Maximum value */
  max?: number;
  /** Variant */
  variant?: ProgressVariant;
  /** Size */
  size?: ProgressSize;
  /** Show percentage label */
  showLabel?: boolean;
  /** Custom label */
  label?: string;
  /** Indeterminate mode */
  indeterminate?: boolean;
  /** Striped background */
  striped?: boolean;
  /** Animated stripes */
  animated?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Linear Progress ============

export function Progress({
  value,
  max = 100,
  variant = 'primary',
  size = 'medium',
  showLabel = false,
  label,
  indeterminate = false,
  striped = false,
  animated = false,
  className = '',
}: ProgressProps) {
  const percent = Math.min(100, Math.max(0, (value / max) * 100));

  return (
    <div
      className={`progress progress--${variant} progress--${size} ${
        indeterminate ? 'progress--indeterminate' : ''
      } ${striped ? 'progress--striped' : ''} ${
        animated ? 'progress--animated' : ''
      } ${className}`}
      role="progressbar"
      aria-valuenow={indeterminate ? undefined : value}
      aria-valuemin={0}
      aria-valuemax={max}
    >
      <div className="progress__track">
        <div
          className="progress__fill"
          style={{ width: indeterminate ? undefined : `${percent}%` }}
        />
      </div>
      {showLabel && (
        <span className="progress__label">
          {label ?? `${Math.round(percent)}%`}
        </span>
      )}
    </div>
  );
}

// ============ Circular Progress ============

export interface CircularProgressProps {
  /** Value (0-100) */
  value: number;
  /** Maximum value */
  max?: number;
  /** Size in pixels */
  size?: number;
  /** Stroke width */
  strokeWidth?: number;
  /** Variant */
  variant?: ProgressVariant;
  /** Show percentage label */
  showLabel?: boolean;
  /** Custom label */
  label?: React.ReactNode;
  /** Indeterminate mode */
  indeterminate?: boolean;
  /** Custom class */
  className?: string;
}

export function CircularProgress({
  value,
  max = 100,
  size = 48,
  strokeWidth = 4,
  variant = 'primary',
  showLabel = false,
  label,
  indeterminate = false,
  className = '',
}: CircularProgressProps) {
  const percent = Math.min(100, Math.max(0, (value / max) * 100));
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percent / 100) * circumference;

  return (
    <div
      className={`circular-progress circular-progress--${variant} ${
        indeterminate ? 'circular-progress--indeterminate' : ''
      } ${className}`}
      style={{ width: size, height: size }}
      role="progressbar"
      aria-valuenow={indeterminate ? undefined : value}
      aria-valuemin={0}
      aria-valuemax={max}
    >
      <svg
        className="circular-progress__svg"
        viewBox={`0 0 ${size} ${size}`}
      >
        {/* Track */}
        <circle
          className="circular-progress__track"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
        />
        {/* Fill */}
        <circle
          className="circular-progress__fill"
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
          strokeDasharray={circumference}
          strokeDashoffset={indeterminate ? circumference * 0.75 : offset}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
        />
      </svg>
      {showLabel && (
        <span className="circular-progress__label">
          {label ?? `${Math.round(percent)}%`}
        </span>
      )}
    </div>
  );
}

// ============ Spinner ============

export interface SpinnerProps {
  /** Size in pixels */
  size?: number;
  /** Variant */
  variant?: ProgressVariant;
  /** Custom class */
  className?: string;
}

export function Spinner({
  size = 24,
  variant = 'primary',
  className = '',
}: SpinnerProps) {
  return (
    <div
      className={`spinner spinner--${variant} ${className}`}
      style={{ width: size, height: size }}
      role="status"
      aria-label="Loading"
    >
      <svg viewBox="0 0 24 24">
        <circle
          className="spinner__track"
          cx="12"
          cy="12"
          r="10"
          strokeWidth="3"
        />
        <circle
          className="spinner__fill"
          cx="12"
          cy="12"
          r="10"
          strokeWidth="3"
          strokeDasharray="31.4 31.4"
        />
      </svg>
    </div>
  );
}

export default Progress;

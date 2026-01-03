/**
 * Loading State Components
 *
 * Provides consistent loading indicators:
 * - Spinner
 * - Skeleton loaders
 * - Progress bars
 * - Loading overlays
 *
 * @module components/LoadingStates
 */

import { memo } from 'react';
import './LoadingStates.css';

// ============ SPINNER ============

export interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  color?: string;
  className?: string;
}

export const Spinner = memo(function Spinner({
  size = 'md',
  color,
  className = '',
}: SpinnerProps) {
  const sizeMap = { sm: 16, md: 24, lg: 40 };
  const dim = sizeMap[size];

  return (
    <svg
      className={`spinner spinner--${size} ${className}`}
      width={dim}
      height={dim}
      viewBox="0 0 24 24"
      style={{ color }}
    >
      <circle
        className="spinner__track"
        cx="12"
        cy="12"
        r="10"
        fill="none"
        strokeWidth="3"
      />
      <circle
        className="spinner__arc"
        cx="12"
        cy="12"
        r="10"
        fill="none"
        strokeWidth="3"
        strokeDasharray="60 200"
        strokeLinecap="round"
      />
    </svg>
  );
});

// ============ SKELETON ============

export interface SkeletonProps {
  width?: string | number;
  height?: string | number;
  variant?: 'text' | 'rect' | 'circle';
  animation?: 'pulse' | 'wave' | 'none';
  className?: string;
}

export const Skeleton = memo(function Skeleton({
  width = '100%',
  height = 16,
  variant = 'text',
  animation = 'pulse',
  className = '',
}: SkeletonProps) {
  return (
    <div
      className={`skeleton skeleton--${variant} skeleton--${animation} ${className}`}
      style={{
        width: typeof width === 'number' ? `${width}px` : width,
        height: typeof height === 'number' ? `${height}px` : height,
      }}
    />
  );
});

// Preset skeleton layouts
export const SkeletonText = memo(function SkeletonText({ lines = 3 }: { lines?: number }) {
  return (
    <div className="skeleton-text">
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton
          key={i}
          width={i === lines - 1 ? '60%' : '100%'}
          height={12}
        />
      ))}
    </div>
  );
});

export const SkeletonCard = memo(function SkeletonCard() {
  return (
    <div className="skeleton-card">
      <Skeleton variant="rect" height={120} />
      <div className="skeleton-card__content">
        <Skeleton width="80%" height={16} />
        <Skeleton width="60%" height={12} />
      </div>
    </div>
  );
});

export const SkeletonListItem = memo(function SkeletonListItem() {
  return (
    <div className="skeleton-list-item">
      <Skeleton variant="circle" width={32} height={32} />
      <div className="skeleton-list-item__text">
        <Skeleton width="70%" height={14} />
        <Skeleton width="40%" height={10} />
      </div>
    </div>
  );
});

// ============ PROGRESS BAR ============

export interface ProgressBarProps {
  value: number;       // 0-100
  max?: number;
  size?: 'sm' | 'md' | 'lg';
  color?: 'primary' | 'success' | 'warning' | 'error';
  showLabel?: boolean;
  indeterminate?: boolean;
  className?: string;
}

export const ProgressBar = memo(function ProgressBar({
  value,
  max = 100,
  size = 'md',
  color = 'primary',
  showLabel = false,
  indeterminate = false,
  className = '',
}: ProgressBarProps) {
  const percent = Math.min(100, Math.max(0, (value / max) * 100));

  return (
    <div className={`progress-bar progress-bar--${size} progress-bar--${color} ${className}`}>
      <div className="progress-bar__track">
        <div
          className={`progress-bar__fill ${indeterminate ? 'progress-bar__fill--indeterminate' : ''}`}
          style={{ width: indeterminate ? undefined : `${percent}%` }}
        />
      </div>
      {showLabel && !indeterminate && (
        <span className="progress-bar__label">{Math.round(percent)}%</span>
      )}
    </div>
  );
});

// ============ LOADING OVERLAY ============

export interface LoadingOverlayProps {
  visible: boolean;
  message?: string;
  progress?: number;
  blur?: boolean;
}

export const LoadingOverlay = memo(function LoadingOverlay({
  visible,
  message,
  progress,
  blur = true,
}: LoadingOverlayProps) {
  if (!visible) return null;

  return (
    <div className={`loading-overlay ${blur ? 'loading-overlay--blur' : ''}`}>
      <div className="loading-overlay__content">
        <Spinner size="lg" />
        {message && <p className="loading-overlay__message">{message}</p>}
        {progress !== undefined && (
          <ProgressBar value={progress} size="md" showLabel />
        )}
      </div>
    </div>
  );
});

// ============ LOADING BUTTON ============

export interface LoadingButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  loading?: boolean;
  loadingText?: string;
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
}

export const LoadingButton = memo(function LoadingButton({
  loading = false,
  loadingText,
  variant = 'primary',
  size = 'md',
  children,
  disabled,
  className = '',
  ...props
}: LoadingButtonProps) {
  return (
    <button
      className={`loading-btn loading-btn--${variant} loading-btn--${size} ${loading ? 'loading-btn--loading' : ''} ${className}`}
      disabled={disabled || loading}
      {...props}
    >
      {loading && <Spinner size="sm" />}
      <span className="loading-btn__text">
        {loading && loadingText ? loadingText : children}
      </span>
    </button>
  );
});

// ============ EMPTY STATE ============

export interface EmptyStateProps {
  icon?: string;
  title: string;
  description?: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

export const EmptyState = memo(function EmptyState({
  icon = '📭',
  title,
  description,
  action,
}: EmptyStateProps) {
  return (
    <div className="empty-state">
      <span className="empty-state__icon">{icon}</span>
      <h3 className="empty-state__title">{title}</h3>
      {description && <p className="empty-state__description">{description}</p>}
      {action && (
        <button className="empty-state__action" onClick={action.onClick}>
          {action.label}
        </button>
      )}
    </div>
  );
});

export default {
  Spinner,
  Skeleton,
  SkeletonText,
  SkeletonCard,
  SkeletonListItem,
  ProgressBar,
  LoadingOverlay,
  LoadingButton,
  EmptyState,
};

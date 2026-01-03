/**
 * ReelForge Stat
 *
 * Statistic display:
 * - Value with label
 * - Prefix/suffix
 * - Trend indicator
 * - Formatting
 *
 * @module stat/Stat
 */

import './Stat.css';

// ============ Types ============

export interface StatProps {
  /** Label/title */
  label: React.ReactNode;
  /** Value */
  value: React.ReactNode;
  /** Prefix (icon or text) */
  prefix?: React.ReactNode;
  /** Suffix (unit or icon) */
  suffix?: React.ReactNode;
  /** Description below value */
  description?: React.ReactNode;
  /** Trend direction */
  trend?: 'up' | 'down' | 'neutral';
  /** Trend value (e.g., "+12%") */
  trendValue?: React.ReactNode;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Layout */
  layout?: 'vertical' | 'horizontal';
  /** Loading state */
  loading?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Stat({
  label,
  value,
  prefix,
  suffix,
  description,
  trend,
  trendValue,
  size = 'medium',
  layout = 'vertical',
  loading = false,
  className = '',
}: StatProps) {
  return (
    <div className={`stat stat--${size} stat--${layout} ${className}`}>
      <div className="stat__label">{label}</div>

      <div className="stat__value-container">
        {loading ? (
          <div className="stat__skeleton" />
        ) : (
          <>
            {prefix && <span className="stat__prefix">{prefix}</span>}
            <span className="stat__value">{value}</span>
            {suffix && <span className="stat__suffix">{suffix}</span>}
          </>
        )}
      </div>

      {(description || trend) && (
        <div className="stat__footer">
          {trend && (
            <span className={`stat__trend stat__trend--${trend}`}>
              {trend === 'up' && (
                <svg viewBox="0 0 24 24" fill="currentColor">
                  <path d="M7 14l5-5 5 5H7z" />
                </svg>
              )}
              {trend === 'down' && (
                <svg viewBox="0 0 24 24" fill="currentColor">
                  <path d="M7 10l5 5 5-5H7z" />
                </svg>
              )}
              {trendValue && <span className="stat__trend-value">{trendValue}</span>}
            </span>
          )}
          {description && <span className="stat__description">{description}</span>}
        </div>
      )}
    </div>
  );
}

// ============ Stat Group ============

export interface StatGroupProps {
  /** Children stats */
  children: React.ReactNode;
  /** Columns */
  columns?: 1 | 2 | 3 | 4;
  /** Dividers between stats */
  dividers?: boolean;
  /** Custom class */
  className?: string;
}

export function StatGroup({
  children,
  columns = 3,
  dividers = false,
  className = '',
}: StatGroupProps) {
  return (
    <div
      className={`stat-group stat-group--cols-${columns} ${
        dividers ? 'stat-group--dividers' : ''
      } ${className}`}
    >
      {children}
    </div>
  );
}

// ============ Helpers ============

export function formatNumber(value: number): string {
  return value.toLocaleString();
}

export function formatCompact(value: number): string {
  if (value >= 1_000_000_000) {
    return `${(value / 1_000_000_000).toFixed(1)}B`;
  }
  if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(1)}M`;
  }
  if (value >= 1_000) {
    return `${(value / 1_000).toFixed(1)}K`;
  }
  return value.toString();
}

export function formatPercent(value: number, decimals = 1): string {
  return `${value.toFixed(decimals)}%`;
}

export default Stat;

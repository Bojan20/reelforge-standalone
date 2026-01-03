/**
 * ReelForge Statistic
 *
 * Big number display:
 * - Value formatting
 * - Prefix/suffix
 * - Trend indicators
 * - Countdown
 * - Loading state
 *
 * @module statistic/Statistic
 */

import { useState, useEffect, useCallback } from 'react';
import './Statistic.css';

// ============ Types ============

export interface StatisticProps {
  /** Title/label */
  title?: React.ReactNode;
  /** Value */
  value: number | string;
  /** Precision (decimals) */
  precision?: number;
  /** Prefix element */
  prefix?: React.ReactNode;
  /** Suffix element */
  suffix?: React.ReactNode;
  /** Value style */
  valueStyle?: React.CSSProperties;
  /** Formatter function */
  formatter?: (value: number | string) => React.ReactNode;
  /** Loading state */
  loading?: boolean;
  /** Group separator */
  groupSeparator?: string;
  /** Decimal separator */
  decimalSeparator?: string;
  /** Custom class */
  className?: string;
}

export interface StatisticTrendProps extends Omit<StatisticProps, 'value'> {
  /** Current value */
  value: number;
  /** Previous value for comparison */
  previousValue?: number;
  /** Show trend arrow */
  showTrend?: boolean;
  /** Trend color */
  trendColor?: 'default' | 'reverse';
}

export interface CountdownProps {
  /** Title/label */
  title?: React.ReactNode;
  /** Target timestamp (ms) */
  value: number;
  /** Format string (D d H:m:s) */
  format?: string;
  /** On finish callback */
  onFinish?: () => void;
  /** Prefix element */
  prefix?: React.ReactNode;
  /** Suffix element */
  suffix?: React.ReactNode;
  /** Value style */
  valueStyle?: React.CSSProperties;
  /** Custom class */
  className?: string;
}

// ============ Format Helpers ============

function formatNumber(
  value: number,
  precision?: number,
  groupSeparator = ',',
  decimalSeparator = '.'
): string {
  const fixed = precision !== undefined ? value.toFixed(precision) : String(value);
  const [intPart, decPart] = fixed.split('.');

  const formattedInt = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, groupSeparator);

  if (decPart !== undefined) {
    return `${formattedInt}${decimalSeparator}${decPart}`;
  }

  return formattedInt;
}

function formatCountdown(diff: number, format: string): string {
  if (diff <= 0) return format.replace(/[DHms]/g, '0');

  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((diff % (1000 * 60)) / 1000);

  return format
    .replace('D', String(days))
    .replace('H', String(hours).padStart(2, '0'))
    .replace('m', String(minutes).padStart(2, '0'))
    .replace('s', String(seconds).padStart(2, '0'));
}

// ============ Statistic Component ============

export function Statistic({
  title,
  value,
  precision,
  prefix,
  suffix,
  valueStyle,
  formatter,
  loading = false,
  groupSeparator = ',',
  decimalSeparator = '.',
  className = '',
}: StatisticProps) {
  const renderValue = () => {
    if (loading) {
      return <span className="statistic__loading">--</span>;
    }

    if (formatter) {
      return formatter(value);
    }

    if (typeof value === 'number') {
      return formatNumber(value, precision, groupSeparator, decimalSeparator);
    }

    return value;
  };

  return (
    <div className={`statistic ${className}`}>
      {title && <div className="statistic__title">{title}</div>}
      <div className="statistic__content" style={valueStyle}>
        {prefix && <span className="statistic__prefix">{prefix}</span>}
        <span className="statistic__value">{renderValue()}</span>
        {suffix && <span className="statistic__suffix">{suffix}</span>}
      </div>
    </div>
  );
}

// ============ StatisticTrend Component ============

export function StatisticTrend({
  value,
  previousValue,
  showTrend = true,
  trendColor = 'default',
  ...rest
}: StatisticTrendProps) {
  const trend = previousValue !== undefined ? value - previousValue : 0;
  const trendPercent =
    previousValue !== undefined && previousValue !== 0
      ? ((value - previousValue) / Math.abs(previousValue)) * 100
      : 0;

  const isUp = trend > 0;
  const isDown = trend < 0;

  // Color logic: default = up is green, down is red
  // reverse = up is red, down is green (for costs, etc.)
  const colorClass =
    trendColor === 'default'
      ? isUp
        ? 'statistic--trend-up'
        : isDown
        ? 'statistic--trend-down'
        : ''
      : isUp
      ? 'statistic--trend-down'
      : isDown
      ? 'statistic--trend-up'
      : '';

  return (
    <div className={`statistic ${colorClass} ${rest.className || ''}`}>
      {rest.title && <div className="statistic__title">{rest.title}</div>}
      <div className="statistic__content" style={rest.valueStyle}>
        {rest.prefix && <span className="statistic__prefix">{rest.prefix}</span>}
        <span className="statistic__value">
          {rest.formatter
            ? rest.formatter(value)
            : formatNumber(
                value,
                rest.precision,
                rest.groupSeparator,
                rest.decimalSeparator
              )}
        </span>
        {rest.suffix && <span className="statistic__suffix">{rest.suffix}</span>}
      </div>

      {showTrend && previousValue !== undefined && trend !== 0 && (
        <div className="statistic__trend">
          <span className="statistic__trend-arrow">{isUp ? '↑' : '↓'}</span>
          <span className="statistic__trend-value">
            {Math.abs(trendPercent).toFixed(1)}%
          </span>
        </div>
      )}
    </div>
  );
}

// ============ Countdown Component ============

export function Countdown({
  title,
  value,
  format = 'H:m:s',
  onFinish,
  prefix,
  suffix,
  valueStyle,
  className = '',
}: CountdownProps) {
  const [diff, setDiff] = useState(value - Date.now());
  const [finished, setFinished] = useState(false);

  const tick = useCallback(() => {
    const newDiff = value - Date.now();
    setDiff(newDiff);

    if (newDiff <= 0 && !finished) {
      setFinished(true);
      onFinish?.();
    }
  }, [value, finished, onFinish]);

  useEffect(() => {
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [tick]);

  return (
    <div className={`statistic statistic--countdown ${className}`}>
      {title && <div className="statistic__title">{title}</div>}
      <div className="statistic__content" style={valueStyle}>
        {prefix && <span className="statistic__prefix">{prefix}</span>}
        <span className="statistic__value">
          {formatCountdown(Math.max(0, diff), format)}
        </span>
        {suffix && <span className="statistic__suffix">{suffix}</span>}
      </div>
    </div>
  );
}

export default Statistic;

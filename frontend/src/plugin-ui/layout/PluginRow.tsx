/**
 * Plugin Row Component
 *
 * Simple flex row for plugin controls.
 *
 * @module plugin-ui/layout/PluginRow
 */

import { memo, type ReactNode } from 'react';
import './PluginRow.css';

export interface PluginRowProps {
  /** Row content */
  children: ReactNode;
  /** Gap between items */
  gap?: 'none' | 'small' | 'medium' | 'large';
  /** Align items */
  align?: 'start' | 'center' | 'end' | 'stretch' | 'baseline';
  /** Justify content */
  justify?: 'start' | 'center' | 'end' | 'between' | 'around' | 'evenly';
  /** Wrap items */
  wrap?: boolean;
  /** Custom class */
  className?: string;
}

function PluginRowInner({
  children,
  gap = 'medium',
  align = 'center',
  justify = 'start',
  wrap = false,
  className,
}: PluginRowProps) {
  const gapMap = {
    none: '0',
    small: '8px',
    medium: '12px',
    large: '16px',
  };

  const alignMap = {
    start: 'flex-start',
    center: 'center',
    end: 'flex-end',
    stretch: 'stretch',
    baseline: 'baseline',
  };

  const justifyMap = {
    start: 'flex-start',
    center: 'center',
    end: 'flex-end',
    between: 'space-between',
    around: 'space-around',
    evenly: 'space-evenly',
  };

  return (
    <div
      className={`plugin-row ${className ?? ''}`}
      style={{
        gap: gapMap[gap],
        alignItems: alignMap[align],
        justifyContent: justifyMap[justify],
        flexWrap: wrap ? 'wrap' : 'nowrap',
      }}
    >
      {children}
    </div>
  );
}

export const PluginRow = memo(PluginRowInner);
export default PluginRow;

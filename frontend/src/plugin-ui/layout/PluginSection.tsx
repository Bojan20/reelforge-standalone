/**
 * Plugin Section Component
 *
 * Logical section within a plugin UI.
 *
 * @module plugin-ui/layout/PluginSection
 */

import { memo, type ReactNode } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginSection.css';

export interface PluginSectionProps {
  /** Section content */
  children: ReactNode;
  /** Section label */
  label?: string;
  /** Horizontal or vertical layout */
  direction?: 'horizontal' | 'vertical';
  /** Gap between items */
  gap?: 'none' | 'small' | 'medium' | 'large';
  /** Align items */
  align?: 'start' | 'center' | 'end' | 'stretch';
  /** Justify content */
  justify?: 'start' | 'center' | 'end' | 'between' | 'around';
  /** Custom class */
  className?: string;
}

function PluginSectionInner({
  children,
  label,
  direction = 'horizontal',
  gap = 'medium',
  align = 'center',
  justify = 'start',
  className,
}: PluginSectionProps) {
  const theme = usePluginTheme();

  const justifyMap = {
    start: 'flex-start',
    center: 'center',
    end: 'flex-end',
    between: 'space-between',
    around: 'space-around',
  };

  const alignMap = {
    start: 'flex-start',
    center: 'center',
    end: 'flex-end',
    stretch: 'stretch',
  };

  const gapMap = {
    none: '0',
    small: '8px',
    medium: '12px',
    large: '16px',
  };

  return (
    <div className={`plugin-section ${className ?? ''}`}>
      {label && (
        <div className="plugin-section__label" style={{ color: theme.textMuted }}>
          {label}
        </div>
      )}
      <div
        className="plugin-section__content"
        style={{
          flexDirection: direction === 'horizontal' ? 'row' : 'column',
          gap: gapMap[gap],
          alignItems: alignMap[align],
          justifyContent: justifyMap[justify],
        }}
      >
        {children}
      </div>
    </div>
  );
}

export const PluginSection = memo(PluginSectionInner);
export default PluginSection;

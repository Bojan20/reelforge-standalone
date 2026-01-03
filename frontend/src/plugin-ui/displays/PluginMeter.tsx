/**
 * Plugin Meter Component
 *
 * Simple level meter for plugin UIs.
 *
 * @module plugin-ui/displays/PluginMeter
 */

import { memo, useMemo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginMeter.css';

export interface PluginMeterProps {
  /** Current level in dB */
  level: number;
  /** Peak level in dB */
  peak?: number;
  /** Minimum dB */
  min?: number;
  /** Maximum dB */
  max?: number;
  /** Orientation */
  orientation?: 'vertical' | 'horizontal';
  /** Length in pixels */
  length?: number;
  /** Thickness in pixels */
  thickness?: number;
  /** Show peak hold */
  showPeak?: boolean;
  /** Show segments (LED style) */
  segments?: number;
  /** Custom class */
  className?: string;
}

function PluginMeterInner({
  level,
  peak,
  min = -60,
  max = 6,
  orientation = 'vertical',
  length = 100,
  thickness = 8,
  showPeak = true,
  segments = 0,
  className,
}: PluginMeterProps) {
  const theme = usePluginTheme();
  const isVertical = orientation === 'vertical';

  // Normalize values
  const normalize = (db: number) => {
    const clamped = Math.max(min, Math.min(max, db));
    return (clamped - min) / (max - min);
  };

  const levelNorm = normalize(level);
  const peakNorm = peak !== undefined ? normalize(peak) : 0;

  // Get color based on level
  const getColor = (norm: number) => {
    if (norm > 0.9) return theme.meterRed;
    if (norm > 0.7) return theme.meterYellow;
    return theme.meterGreen;
  };

  // Segment rendering
  const segmentElements = useMemo(() => {
    if (segments <= 0) return null;

    const elements = [];
    const gap = 1;
    const segmentSize = (length - (segments - 1) * gap) / segments;

    for (let i = 0; i < segments; i++) {
      const segmentNorm = (i + 0.5) / segments;
      const isLit = levelNorm >= segmentNorm;
      const color = isLit ? getColor(segmentNorm) : theme.bgControl;

      const pos = i * (segmentSize + gap);
      const style = isVertical
        ? { bottom: pos, height: segmentSize, background: color }
        : { left: pos, width: segmentSize, background: color };

      elements.push(
        <div key={i} className="plugin-meter__segment" style={style} />
      );
    }

    return elements;
  }, [segments, levelNorm, isVertical, length, theme]);

  return (
    <div
      className={`plugin-meter plugin-meter--${orientation} ${className ?? ''}`}
      style={{
        [isVertical ? 'height' : 'width']: length,
        [isVertical ? 'width' : 'height']: thickness,
        background: theme.meterBg,
      }}
    >
      {segments > 0 ? (
        segmentElements
      ) : (
        <>
          <div
            className="plugin-meter__fill"
            style={{
              background: getColor(levelNorm),
              [isVertical ? 'height' : 'width']: `${levelNorm * 100}%`,
            }}
          />
          {showPeak && peak !== undefined && peakNorm > 0 && (
            <div
              className="plugin-meter__peak"
              style={{
                background: getColor(peakNorm),
                [isVertical ? 'bottom' : 'left']: `${peakNorm * 100}%`,
              }}
            />
          )}
        </>
      )}
    </div>
  );
}

export const PluginMeter = memo(PluginMeterInner);
export default PluginMeter;

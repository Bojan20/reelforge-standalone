/**
 * ReelForge Spin/Loader
 *
 * Loading spinner components:
 * - Multiple spinner types
 * - Size variants
 * - Custom colors
 * - Overlay mode
 *
 * @module spin/Spin
 */

import { useMemo } from 'react';
import './Spin.css';

// ============ Types ============

export type SpinSize = 'small' | 'default' | 'large';
export type SpinType = 'default' | 'dots' | 'bars' | 'ring' | 'pulse' | 'wave';

export interface SpinProps {
  /** Spinner type */
  type?: SpinType;
  /** Size */
  size?: SpinSize | number;
  /** Custom color */
  color?: string;
  /** Loading state */
  spinning?: boolean;
  /** Delay before showing (ms) */
  delay?: number;
  /** Tip text */
  tip?: string;
  /** Children to wrap */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface SpinOverlayProps extends SpinProps {
  /** Full screen overlay */
  fullscreen?: boolean;
  /** Background color */
  background?: string;
}

// ============ Size Map ============

const sizeMap: Record<SpinSize, number> = {
  small: 16,
  default: 24,
  large: 40,
};

// ============ Default Spinner ============

function DefaultSpinner({ size, color }: { size: number; color?: string }) {
  return (
    <svg
      className="spin__default"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      style={{ color }}
    >
      <circle
        className="spin__circle"
        cx="12"
        cy="12"
        r="10"
        fill="none"
        strokeWidth="3"
        stroke="currentColor"
      />
    </svg>
  );
}

// ============ Dots Spinner ============

function DotsSpinner({ size, color }: { size: number; color?: string }) {
  const dotSize = size / 4;
  return (
    <div className="spin__dots" style={{ width: size, height: size, color }}>
      {[0, 1, 2, 3].map((i) => (
        <span
          key={i}
          className="spin__dot"
          style={{
            width: dotSize,
            height: dotSize,
            animationDelay: `${i * 0.15}s`,
          }}
        />
      ))}
    </div>
  );
}

// ============ Bars Spinner ============

function BarsSpinner({ size, color }: { size: number; color?: string }) {
  const barWidth = size / 6;
  return (
    <div className="spin__bars" style={{ width: size, height: size, color }}>
      {[0, 1, 2, 3, 4].map((i) => (
        <span
          key={i}
          className="spin__bar"
          style={{
            width: barWidth,
            animationDelay: `${i * 0.1}s`,
          }}
        />
      ))}
    </div>
  );
}

// ============ Ring Spinner ============

function RingSpinner({ size, color }: { size: number; color?: string }) {
  return (
    <div
      className="spin__ring"
      style={{
        width: size,
        height: size,
        borderWidth: size / 8,
        borderTopColor: color,
      }}
    />
  );
}

// ============ Pulse Spinner ============

function PulseSpinner({ size, color }: { size: number; color?: string }) {
  return (
    <div className="spin__pulse" style={{ width: size, height: size }}>
      <span className="spin__pulse-inner" style={{ backgroundColor: color }} />
      <span className="spin__pulse-outer" style={{ borderColor: color }} />
    </div>
  );
}

// ============ Wave Spinner ============

function WaveSpinner({ size, color }: { size: number; color?: string }) {
  const barWidth = size / 8;
  return (
    <div className="spin__wave" style={{ width: size, height: size, color }}>
      {[0, 1, 2, 3, 4].map((i) => (
        <span
          key={i}
          className="spin__wave-bar"
          style={{
            width: barWidth,
            animationDelay: `${i * 0.1}s`,
          }}
        />
      ))}
    </div>
  );
}

// ============ Spin Component ============

export function Spin({
  type = 'default',
  size = 'default',
  color,
  spinning = true,
  tip,
  children,
  className = '',
}: SpinProps) {
  const resolvedSize = typeof size === 'number' ? size : sizeMap[size];

  const spinner = useMemo(() => {
    const props = { size: resolvedSize, color };

    switch (type) {
      case 'dots':
        return <DotsSpinner {...props} />;
      case 'bars':
        return <BarsSpinner {...props} />;
      case 'ring':
        return <RingSpinner {...props} />;
      case 'pulse':
        return <PulseSpinner {...props} />;
      case 'wave':
        return <WaveSpinner {...props} />;
      default:
        return <DefaultSpinner {...props} />;
    }
  }, [type, resolvedSize, color]);

  if (!spinning && !children) {
    return null;
  }

  if (children) {
    return (
      <div className={`spin-wrapper ${spinning ? 'spin-wrapper--spinning' : ''} ${className}`}>
        <div className="spin-wrapper__content">{children}</div>
        {spinning && (
          <div className="spin-wrapper__overlay">
            <div className="spin-wrapper__spinner">
              {spinner}
              {tip && <div className="spin__tip">{tip}</div>}
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className={`spin ${className}`}>
      {spinner}
      {tip && <div className="spin__tip">{tip}</div>}
    </div>
  );
}

// ============ SpinOverlay Component ============

export function SpinOverlay({
  fullscreen = false,
  background,
  ...props
}: SpinOverlayProps) {
  if (!props.spinning) return null;

  return (
    <div
      className={`spin-overlay ${fullscreen ? 'spin-overlay--fullscreen' : ''}`}
      style={{ backgroundColor: background }}
    >
      <Spin {...props} />
    </div>
  );
}

// ============ Loader Aliases ============

export const Loader = Spin;
export const Loading = Spin;

// ============ useSpin Hook ============

export interface UseSpinOptions {
  /** Initial spinning state */
  initial?: boolean;
  /** Minimum duration (ms) */
  minDuration?: number;
}

export function useSpin({ initial = false, minDuration = 0 }: UseSpinOptions = {}) {
  const [spinning, setSpinning] = useState(initial);
  const startTime = useRef<number>(0);

  const start = useCallback(() => {
    startTime.current = Date.now();
    setSpinning(true);
  }, []);

  const stop = useCallback(() => {
    const elapsed = Date.now() - startTime.current;
    const remaining = minDuration - elapsed;

    if (remaining > 0) {
      setTimeout(() => setSpinning(false), remaining);
    } else {
      setSpinning(false);
    }
  }, [minDuration]);

  const wrap = useCallback(
    async <T,>(promise: Promise<T>): Promise<T> => {
      start();
      try {
        return await promise;
      } finally {
        stop();
      }
    },
    [start, stop]
  );

  return { spinning, start, stop, wrap };
}

// Need to import these for the hook
import { useState, useRef, useCallback } from 'react';

export default Spin;

/**
 * ReelForge PeakMeter
 *
 * Audio level meter:
 * - VU/Peak/RMS modes
 * - Stereo display
 * - Peak hold
 * - Clip indicator
 * - Real-time analysis
 *
 * @module peak-meter/PeakMeter
 */

import { useRef, useEffect, useCallback, useState } from 'react';
import './PeakMeter.css';

// ============ Types ============

export type MeterMode = 'peak' | 'rms' | 'vu';
export type MeterOrientation = 'vertical' | 'horizontal';

export interface PeakMeterProps {
  /** Analyser node(s) */
  analyserNode?: AnalyserNode | [AnalyserNode, AnalyserNode] | null;
  /** Manual level (0-1) */
  level?: number | [number, number];
  /** Mode */
  mode?: MeterMode;
  /** Orientation */
  orientation?: MeterOrientation;
  /** Stereo mode */
  stereo?: boolean;
  /** Length in pixels */
  length?: number;
  /** Width per channel */
  channelWidth?: number;
  /** Peak hold time (ms) */
  peakHoldTime?: number;
  /** Decay rate (dB/second) */
  decayRate?: number;
  /** Show clip indicator */
  showClip?: boolean;
  /** Clip threshold (dB) */
  clipThreshold?: number;
  /** Show scale */
  showScale?: boolean;
  /** Scale marks (dB) */
  scaleMarks?: number[];
  /** Custom class */
  className?: string;
}

// ============ Color Gradient ============

const _getMeterColor = (level: number): string => {
  if (level > 0.95) return '#ef4444'; // Red (clip)
  if (level > 0.8) return '#f59e0b';  // Orange (hot)
  if (level > 0.6) return '#eab308';  // Yellow
  return '#22c55e';                    // Green
};
void _getMeterColor; // Reserved for future use

// ============ PeakMeter Component ============

export function PeakMeter({
  analyserNode,
  level: manualLevel,
  mode = 'peak',
  orientation = 'vertical',
  stereo = false,
  length = 200,
  channelWidth = 12,
  peakHoldTime = 1500,
  decayRate = 20,
  showClip = true,
  clipThreshold = -0.5,
  showScale = true,
  scaleMarks = [0, -6, -12, -24, -48, -60],
  className = '',
}: PeakMeterProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number>(undefined);
  const [clipped, setClipped] = useState([false, false]);
  const peakHoldRef = useRef<[number, number]>([0, 0]);
  const peakHoldTimeRef = useRef<[number, number]>([0, 0]);
  const smoothedLevelRef = useRef<[number, number]>([0, 0]);

  const isVertical = orientation === 'vertical';
  const channels = stereo ? 2 : 1;
  const width = isVertical ? channelWidth * channels + (channels - 1) * 2 : length;
  const height = isVertical ? length : channelWidth * channels + (channels - 1) * 2;

  // dB to linear
  const dbToLinear = useCallback((db: number): number => {
    return Math.pow(10, db / 20);
  }, []);

  // Linear to dB (reserved for future use)
  const _linearToDb = useCallback((linear: number): number => {
    if (linear <= 0) return -Infinity;
    return 20 * Math.log10(linear);
  }, []);
  void _linearToDb;

  // Get level from analyser
  // Includes noise gate: signal below -90dB is treated as silence
  const getLevelFromAnalyser = useCallback((analyser: AnalyserNode, meterMode: MeterMode): number => {
    const bufferLength = analyser.fftSize;
    const dataArray = new Float32Array(bufferLength);
    analyser.getFloatTimeDomainData(dataArray);

    // Noise gate threshold: -90dB = ~0.00003 linear
    const NOISE_FLOOR = 0.00003;

    let level = 0;

    if (meterMode === 'peak') {
      for (let i = 0; i < bufferLength; i++) {
        const abs = Math.abs(dataArray[i]);
        if (abs > level) level = abs;
      }
    } else if (meterMode === 'rms') {
      let sum = 0;
      for (let i = 0; i < bufferLength; i++) {
        sum += dataArray[i] * dataArray[i];
      }
      level = Math.sqrt(sum / bufferLength);
    } else {
      // VU: RMS with slower response
      let sum = 0;
      for (let i = 0; i < bufferLength; i++) {
        sum += dataArray[i] * dataArray[i];
      }
      level = Math.sqrt(sum / bufferLength) * 0.3 + smoothedLevelRef.current[0] * 0.7;
    }

    // Apply noise gate: below threshold = silence
    if (level < NOISE_FLOOR) {
      return 0;
    }

    return level;
  }, []);

  // Draw meter
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const now = performance.now();
    const dpr = window.devicePixelRatio || 1;

    // Clear
    ctx.clearRect(0, 0, canvas.width / dpr, canvas.height / dpr);

    // Get levels
    let levels: [number, number] = [0, 0];

    if (manualLevel !== undefined) {
      if (Array.isArray(manualLevel)) {
        levels = manualLevel;
      } else {
        levels = [manualLevel, manualLevel];
      }
    } else if (analyserNode) {
      if (Array.isArray(analyserNode)) {
        levels = [
          getLevelFromAnalyser(analyserNode[0], mode),
          getLevelFromAnalyser(analyserNode[1], mode),
        ];
      } else {
        const level = getLevelFromAnalyser(analyserNode, mode);
        levels = [level, level];
      }
    }

    // Draw each channel
    for (let ch = 0; ch < channels; ch++) {
      const level = levels[ch];
      const smoothed = smoothedLevelRef.current[ch];

      // Apply decay
      const decayed = Math.max(level, smoothed - (decayRate / 60) * 0.016);
      smoothedLevelRef.current[ch] = decayed;

      // Peak hold
      if (decayed >= peakHoldRef.current[ch]) {
        peakHoldRef.current[ch] = decayed;
        peakHoldTimeRef.current[ch] = now;
      } else if (now - peakHoldTimeRef.current[ch] > peakHoldTime) {
        peakHoldRef.current[ch] = Math.max(
          decayed,
          peakHoldRef.current[ch] - (decayRate / 60) * 0.016
        );
      }

      // Check clip
      if (level > dbToLinear(clipThreshold)) {
        setClipped((prev) => {
          const next = [...prev];
          next[ch] = true;
          return next as [boolean, boolean];
        });
      }

      // Calculate positions
      const meterLength = length - 20; // Leave room for scale
      const levelPx = Math.min(1, decayed) * meterLength;
      const peakPx = Math.min(1, peakHoldRef.current[ch]) * meterLength;

      const x = isVertical ? ch * (channelWidth + 2) : 0;
      const y = isVertical ? 0 : ch * (channelWidth + 2);

      // Draw background
      ctx.fillStyle = 'rgba(255, 255, 255, 0.05)';
      if (isVertical) {
        ctx.fillRect(x, 0, channelWidth, meterLength);
      } else {
        ctx.fillRect(0, y, meterLength, channelWidth);
      }

      // Draw level gradient
      const gradient = isVertical
        ? ctx.createLinearGradient(0, meterLength, 0, 0)
        : ctx.createLinearGradient(0, 0, meterLength, 0);

      gradient.addColorStop(0, '#22c55e');
      gradient.addColorStop(0.6, '#eab308');
      gradient.addColorStop(0.8, '#f59e0b');
      gradient.addColorStop(0.95, '#ef4444');

      ctx.fillStyle = gradient;
      if (isVertical) {
        ctx.fillRect(x, meterLength - levelPx, channelWidth, levelPx);
      } else {
        ctx.fillRect(0, y, levelPx, channelWidth);
      }

      // Draw peak hold line
      ctx.fillStyle = '#ffffff';
      if (isVertical) {
        ctx.fillRect(x, meterLength - peakPx - 2, channelWidth, 2);
      } else {
        ctx.fillRect(peakPx, y, 2, channelWidth);
      }
    }

    animationRef.current = requestAnimationFrame(draw);
  }, [
    analyserNode,
    manualLevel,
    mode,
    channels,
    isVertical,
    length,
    channelWidth,
    peakHoldTime,
    decayRate,
    clipThreshold,
    dbToLinear,
    getLevelFromAnalyser,
  ]);

  // Setup canvas and animation
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.scale(dpr, dpr);
    }

    draw();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [width, height, draw]);

  // Reset clip
  const resetClip = useCallback(() => {
    setClipped([false, false]);
  }, []);

  return (
    <div
      className={`peak-meter peak-meter--${orientation} ${className}`}
      style={{ width, height: height + (showClip ? 16 : 0) }}
    >
      {showClip && (
        <div className="peak-meter__clip-row">
          {Array.from({ length: channels }).map((_, ch) => (
            <button
              key={ch}
              type="button"
              className={`peak-meter__clip ${clipped[ch] ? 'peak-meter__clip--active' : ''}`}
              onClick={resetClip}
              style={{ width: channelWidth }}
            />
          ))}
        </div>
      )}

      <div className="peak-meter__body">
        <canvas ref={canvasRef} className="peak-meter__canvas" />

        {showScale && (
          <div className="peak-meter__scale">
            {scaleMarks.map((mark) => {
              const normalized = 1 - (mark - (-60)) / (0 - (-60));
              const position = normalized * (length - 20);

              return (
                <div
                  key={mark}
                  className="peak-meter__scale-mark"
                  style={isVertical ? { top: position } : { left: position }}
                >
                  <span className="peak-meter__scale-label">{mark}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// ============ usePeakMeter Hook ============

export function usePeakMeter(audioContext: AudioContext | null) {
  const [analyser, setAnalyser] = useState<AnalyserNode | null>(null);

  useEffect(() => {
    if (!audioContext) {
      setAnalyser(null);
      return;
    }

    const analyserNode = audioContext.createAnalyser();
    analyserNode.fftSize = 256;
    analyserNode.smoothingTimeConstant = 0;
    setAnalyser(analyserNode);
  }, [audioContext]);

  return analyser;
}

export default PeakMeter;

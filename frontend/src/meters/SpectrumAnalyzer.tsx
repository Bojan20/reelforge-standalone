/**
 * ReelForge Spectrum Analyzer
 *
 * FFT-based frequency spectrum display:
 * - Bar or line display
 * - Configurable frequency range
 * - Peak hold
 * - Logarithmic or linear scale
 *
 * @module meters/SpectrumAnalyzer
 */

import { useRef, useEffect, useCallback } from 'react';
import './SpectrumAnalyzer.css';

// ============ Types ============

export interface SpectrumAnalyzerProps {
  /** FFT data (magnitude values 0-255) */
  fftData: Uint8Array | Float32Array;
  /** Sample rate for frequency calculation */
  sampleRate?: number;
  /** FFT size */
  fftSize?: number;
  /** Display mode */
  mode?: 'bars' | 'line' | 'fill';
  /** Logarithmic frequency scale */
  logScale?: boolean;
  /** Show peak hold */
  showPeakHold?: boolean;
  /** Peak decay rate (0-1) */
  peakDecay?: number;
  /** Min frequency to display */
  minFreq?: number;
  /** Max frequency to display */
  maxFreq?: number;
  /** Min dB */
  minDB?: number;
  /** Max dB */
  maxDB?: number;
  /** Width */
  width?: number;
  /** Height */
  height?: number;
  /** Bar color */
  color?: string;
  /** Peak color */
  peakColor?: string;
  /** Background color */
  backgroundColor?: string;
  /** Show frequency labels */
  showLabels?: boolean;
}

// ============ Constants ============

const FREQ_LABELS = [20, 50, 100, 200, 500, '1k', '2k', '5k', '10k', '20k'];
const FREQ_VALUES = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

// ============ Helpers ============

function frequencyToPosition(
  freq: number,
  minFreq: number,
  maxFreq: number,
  logScale: boolean
): number {
  if (logScale) {
    const minLog = Math.log10(minFreq);
    const maxLog = Math.log10(maxFreq);
    const freqLog = Math.log10(Math.max(freq, minFreq));
    return (freqLog - minLog) / (maxLog - minLog);
  }
  return (freq - minFreq) / (maxFreq - minFreq);
}

function binToFrequency(bin: number, fftSize: number, sampleRate: number): number {
  return (bin * sampleRate) / fftSize;
}

// ============ Component ============

export function SpectrumAnalyzer({
  fftData,
  sampleRate = 44100,
  fftSize = 2048,
  mode = 'bars',
  logScale = true,
  showPeakHold = true,
  peakDecay = 0.98,
  minFreq = 20,
  maxFreq = 20000,
  minDB = -90,
  maxDB = 0,
  width = 400,
  height = 200,
  color = '#4a9eff',
  peakColor = '#ff6b6b',
  backgroundColor = '#1a1a1a',
  showLabels = true,
}: SpectrumAnalyzerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const peakHoldRef = useRef<Float32Array | null>(null);
  const animationRef = useRef<number>(0);

  // Initialize peak hold
  useEffect(() => {
    peakHoldRef.current = new Float32Array(width);
  }, [width]);

  // Draw spectrum
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const w = canvas.width;
    const h = canvas.height;
    const labelHeight = showLabels ? 20 : 0;
    const plotHeight = h - labelHeight;

    // Clear
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, w, h);

    // Draw grid lines
    ctx.strokeStyle = '#2a2a2a';
    ctx.lineWidth = 1;

    // Horizontal grid (dB)
    const dbSteps = [-72, -48, -24, -12, -6, 0];
    for (const db of dbSteps) {
      const y = plotHeight * (1 - (db - minDB) / (maxDB - minDB));
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }

    // Vertical grid (frequency)
    for (const freq of FREQ_VALUES) {
      if (freq >= minFreq && freq <= maxFreq) {
        const x = frequencyToPosition(freq, minFreq, maxFreq, logScale) * w;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, plotHeight);
        ctx.stroke();
      }
    }

    // Build spectrum data for display
    const numBins = fftData.length;
    const displayData: { x: number; value: number }[] = [];

    for (let i = 0; i < numBins; i++) {
      const freq = binToFrequency(i, fftSize, sampleRate);
      if (freq < minFreq || freq > maxFreq) continue;

      const x = frequencyToPosition(freq, minFreq, maxFreq, logScale) * w;

      // Convert to dB (assuming 0-255 input or 0-1 float)
      let value: number;
      if (fftData instanceof Uint8Array) {
        value = (fftData[i] / 255) * (maxDB - minDB) + minDB;
      } else {
        // Float array, assume dB values
        value = fftData[i];
      }

      const normalizedValue = Math.max(0, Math.min(1, (value - minDB) / (maxDB - minDB)));
      displayData.push({ x, value: normalizedValue });
    }

    // Draw based on mode
    if (mode === 'bars') {
      const barWidth = Math.max(1, w / displayData.length - 1);
      ctx.fillStyle = color;

      for (const point of displayData) {
        const barHeight = point.value * plotHeight;
        ctx.fillRect(point.x - barWidth / 2, plotHeight - barHeight, barWidth, barHeight);
      }
    } else if (mode === 'line' || mode === 'fill') {
      ctx.beginPath();
      ctx.moveTo(0, plotHeight);

      for (let i = 0; i < displayData.length; i++) {
        const point = displayData[i];
        const y = plotHeight - point.value * plotHeight;

        if (i === 0) {
          ctx.lineTo(point.x, y);
        } else {
          ctx.lineTo(point.x, y);
        }
      }

      if (mode === 'fill') {
        ctx.lineTo(w, plotHeight);
        ctx.closePath();
        ctx.fillStyle = color + '40'; // Semi-transparent
        ctx.fill();
      }

      ctx.strokeStyle = color;
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    // Peak hold
    if (showPeakHold && peakHoldRef.current) {
      const peaks = peakHoldRef.current;

      // Update peaks
      for (let i = 0; i < displayData.length; i++) {
        const x = Math.floor(displayData[i].x);
        if (x >= 0 && x < w) {
          if (displayData[i].value > peaks[x]) {
            peaks[x] = displayData[i].value;
          } else {
            peaks[x] *= peakDecay;
          }
        }
      }

      // Draw peaks
      ctx.fillStyle = peakColor;
      for (let x = 0; x < w; x++) {
        if (peaks[x] > 0.01) {
          const y = plotHeight - peaks[x] * plotHeight;
          ctx.fillRect(x, y - 1, 1, 2);
        }
      }
    }

    // Frequency labels
    if (showLabels) {
      ctx.fillStyle = '#666';
      ctx.font = '10px SF Mono, Consolas, monospace';
      ctx.textAlign = 'center';

      for (let i = 0; i < FREQ_VALUES.length; i++) {
        const freq = FREQ_VALUES[i];
        if (freq >= minFreq && freq <= maxFreq) {
          const x = frequencyToPosition(freq, minFreq, maxFreq, logScale) * w;
          ctx.fillText(String(FREQ_LABELS[i]), x, h - 4);
        }
      }
    }
  }, [
    fftData,
    sampleRate,
    fftSize,
    mode,
    logScale,
    showPeakHold,
    peakDecay,
    minFreq,
    maxFreq,
    minDB,
    maxDB,
    color,
    peakColor,
    backgroundColor,
    showLabels,
  ]);

  // Animation loop
  useEffect(() => {
    const animate = () => {
      draw();
      animationRef.current = requestAnimationFrame(animate);
    };

    animate();

    return () => {
      cancelAnimationFrame(animationRef.current);
    };
  }, [draw]);

  return (
    <div className="spectrum-analyzer" style={{ width, height }}>
      <canvas
        ref={canvasRef}
        width={width}
        height={height}
        className="spectrum-analyzer__canvas"
      />
    </div>
  );
}

export default SpectrumAnalyzer;

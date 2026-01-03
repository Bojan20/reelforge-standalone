/**
 * SpectrumCanvas.tsx - WOW Edition Canvas-based Spectrum Analyzer
 *
 * High-performance WebGL/Canvas spectrum visualizer:
 * - 60fps animation via requestAnimationFrame
 * - Attack/release smoothing for realistic response
 * - Peak hold with decay
 * - Gradient fill with glow effect
 * - Logarithmic frequency mapping
 * - Pink noise simulation when no audio input
 * - Pre-allocated buffers to avoid GC pressure
 *
 * @module plugin/vaneq-pro/SpectrumCanvas
 */

import { useEffect, useRef, useCallback, memo } from 'react';
import {
  FREQ_MIN,
  FREQ_MAX,
  SPECTRUM_DB_MIN,
  SPECTRUM_DB_MAX,
  freqToX,
} from './frequencyUtils';

// ============ Types ============

export interface SpectrumCanvasProps {
  width: number;
  height: number;
  /** FFT dB data from analyzer (optional - will simulate if not provided) */
  fftDb?: Float32Array | number[] | null;
  /** Sample rate for FFT bin mapping */
  sampleRate?: number;
  /** Whether analyzer is enabled */
  enabled?: boolean;
  /** Whether audio is playing (for simulation) */
  isPlaying?: boolean;
  /** Quality level affects resolution */
  quality?: 'low' | 'mid' | 'high';
  /** Padding from edges */
  padding?: { left: number; right: number; top: number; bottom: number };
}

// ============ Timing Constants ============

/** Attack time in seconds (12ms) */
const ATTACK_TIME = 0.012;

/** Release time in seconds (180ms) */
const RELEASE_TIME = 0.18;

/** Peak hold time in seconds */
const PEAK_HOLD_TIME = 1.2;

/** Peak decay rate in dB per frame after hold expires */
const PEAK_DECAY_RATE = 0.15;

// ============ Display Constants ============

/** Spectrum dB range (use constants from frequencyUtils) */
const DB_MIN = SPECTRUM_DB_MIN;
const DB_MAX = SPECTRUM_DB_MAX;

// ============ Colors (WOW Edition) ============

const SPECTRUM_COLOR = 'rgba(0, 210, 255, 0.7)';
const SPECTRUM_GLOW = 'rgba(0, 200, 255, 0.3)';
const FILL_TOP = 'rgba(0, 200, 255, 0.25)';
const FILL_BOTTOM = 'rgba(0, 180, 255, 0.02)';
const PEAK_COLOR = 'rgba(0, 220, 255, 0.9)';

// ============ Helpers ============

/**
 * Convert frequency to X using shared utility.
 * Wrapper for consistency with local naming.
 */
function logFreqToX(freq: number, width: number): number {
  return freqToX(freq, width, FREQ_MIN, FREQ_MAX);
}

/**
 * Convert dB to Y for spectrum display.
 * Uses inverted Y (0 = bottom = DB_MIN, height = top = DB_MAX)
 */
function spectrumDbToY(db: number, height: number): number {
  const clamped = Math.max(DB_MIN, Math.min(DB_MAX, db));
  const ratio = (clamped - DB_MIN) / (DB_MAX - DB_MIN);
  return height * (1 - ratio);
}

// ============ Pre-allocated Buffer Pool ============

/** Buffer pool to avoid allocations in animation loop */
const pinkNoiseBufferPool: Map<number, Float32Array> = new Map();

/**
 * Get or create a pre-allocated buffer for pink noise.
 * Avoids GC pressure during 60fps animation.
 */
function getPinkNoiseBuffer(size: number): Float32Array {
  let buffer = pinkNoiseBufferPool.get(size);
  if (!buffer) {
    buffer = new Float32Array(size);
    pinkNoiseBufferPool.set(size, buffer);
  }
  return buffer;
}

// Pink noise generator (-3dB/octave slope)
// Uses pre-allocated buffer to avoid GC pressure
function generatePinkNoise(numBins: number, baseLevel: number = -45): Float32Array {
  const result = getPinkNoiseBuffer(numBins);
  for (let i = 0; i < numBins; i++) {
    // Pink noise: -3dB per octave (log slope)
    const binFreq = (i / numBins) * (FREQ_MAX / 2);
    const freqFactor = Math.max(0.01, binFreq / 1000);
    const pinkSlope = -3 * Math.log2(freqFactor);

    // Random variation
    const noise = (Math.random() - 0.5) * 12;

    result[i] = baseLevel + pinkSlope + noise;
  }
  return result;
}

// ============ Component ============

function SpectrumCanvasInner({
  width,
  height,
  fftDb,
  sampleRate = 48000,
  enabled = true,
  isPlaying = false,
  quality = 'mid',
  padding = { left: 36, right: 12, top: 12, bottom: 20 },
}: SpectrumCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number | null>(null);

  // Smoothed values for attack/release
  const smoothedRef = useRef<Float32Array | null>(null);
  const peakRef = useRef<Float32Array | null>(null);
  const peakHoldRef = useRef<Float32Array | null>(null);
  const lastTimeRef = useRef<number>(0);

  // Resolution based on quality
  const numPoints = quality === 'high' ? 512 : quality === 'mid' ? 256 : 128;

  const graphWidth = width - padding.left - padding.right;
  const graphHeight = height - padding.top - padding.bottom;

  // Animation loop
  const animate = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !enabled) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const now = performance.now() / 1000;
    const dt = lastTimeRef.current > 0 ? now - lastTimeRef.current : 0.016;
    lastTimeRef.current = now;

    // Get or simulate FFT data
    let currentDb: Float32Array | number[];
    if (fftDb && fftDb.length > 0) {
      currentDb = fftDb;
    } else if (isPlaying) {
      // Simulate pink noise when playing but no real FFT
      currentDb = generatePinkNoise(numPoints, -40);
    } else {
      // Idle: very low noise floor
      currentDb = generatePinkNoise(numPoints, -75);
    }

    // Initialize smoothed arrays if needed
    if (!smoothedRef.current || smoothedRef.current.length !== numPoints) {
      smoothedRef.current = new Float32Array(numPoints).fill(DB_MIN);
      peakRef.current = new Float32Array(numPoints).fill(DB_MIN);
      peakHoldRef.current = new Float32Array(numPoints).fill(0);
    }

    const smoothed = smoothedRef.current;
    const peaks = peakRef.current!;
    const peakHold = peakHoldRef.current!;

    // Calculate attack/release coefficients
    const attackCoef = 1 - Math.exp(-dt / ATTACK_TIME);
    const releaseCoef = 1 - Math.exp(-dt / RELEASE_TIME);

    // Map FFT bins to our point resolution
    const binScale = currentDb.length / numPoints;

    for (let i = 0; i < numPoints; i++) {
      const binIdx = Math.floor(i * binScale);
      const targetDb = typeof currentDb[binIdx] === 'number'
        ? currentDb[binIdx]
        : DB_MIN;

      // Attack/release smoothing
      if (targetDb > smoothed[i]) {
        smoothed[i] += attackCoef * (targetDb - smoothed[i]);
      } else {
        smoothed[i] += releaseCoef * (targetDb - smoothed[i]);
      }

      // Peak hold
      if (smoothed[i] > peaks[i]) {
        peaks[i] = smoothed[i];
        peakHold[i] = now;
      } else if (now - peakHold[i] > PEAK_HOLD_TIME) {
        peaks[i] -= PEAK_DECAY_RATE;
      }
    }

    // Clear canvas
    ctx.clearRect(0, 0, width, height);

    // Create gradient fill
    const gradient = ctx.createLinearGradient(0, padding.top, 0, height - padding.bottom);
    gradient.addColorStop(0, FILL_TOP);
    gradient.addColorStop(1, FILL_BOTTOM);

    // Build spectrum path
    ctx.beginPath();
    ctx.moveTo(padding.left, height - padding.bottom);

    for (let i = 0; i < numPoints; i++) {
      const t = i / (numPoints - 1);
      const freq = FREQ_MIN * Math.pow(FREQ_MAX / FREQ_MIN, t);
      const x = logFreqToX(freq, graphWidth) + padding.left;
      const y = spectrumDbToY(smoothed[i], graphHeight) + padding.top;

      if (i === 0) {
        ctx.lineTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }

    // Close path for fill
    ctx.lineTo(width - padding.right, height - padding.bottom);
    ctx.closePath();

    // Fill with gradient
    ctx.fillStyle = gradient;
    ctx.fill();

    // Draw glow (blur effect)
    ctx.save();
    ctx.filter = 'blur(4px)';
    ctx.strokeStyle = SPECTRUM_GLOW;
    ctx.lineWidth = 6;
    ctx.beginPath();
    for (let i = 0; i < numPoints; i++) {
      const t = i / (numPoints - 1);
      const freq = FREQ_MIN * Math.pow(FREQ_MAX / FREQ_MIN, t);
      const x = logFreqToX(freq, graphWidth) + padding.left;
      const y = spectrumDbToY(smoothed[i], graphHeight) + padding.top;

      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.restore();

    // Draw main spectrum line
    ctx.strokeStyle = SPECTRUM_COLOR;
    ctx.lineWidth = 1.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    for (let i = 0; i < numPoints; i++) {
      const t = i / (numPoints - 1);
      const freq = FREQ_MIN * Math.pow(FREQ_MAX / FREQ_MIN, t);
      const x = logFreqToX(freq, graphWidth) + padding.left;
      const y = spectrumDbToY(smoothed[i], graphHeight) + padding.top;

      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Draw peak hold line (subtle)
    ctx.strokeStyle = PEAK_COLOR;
    ctx.lineWidth = 0.5;
    ctx.globalAlpha = 0.4;
    ctx.beginPath();
    for (let i = 0; i < numPoints; i++) {
      const t = i / (numPoints - 1);
      const freq = FREQ_MIN * Math.pow(FREQ_MAX / FREQ_MIN, t);
      const x = logFreqToX(freq, graphWidth) + padding.left;
      const y = spectrumDbToY(peaks[i], graphHeight) + padding.top;

      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.globalAlpha = 1;

    // Continue animation
    animationRef.current = requestAnimationFrame(animate);
  }, [width, height, fftDb, sampleRate, enabled, isPlaying, quality, padding, graphWidth, graphHeight, numPoints]);

  // Start/stop animation
  useEffect(() => {
    if (enabled) {
      lastTimeRef.current = 0;
      animationRef.current = requestAnimationFrame(animate);
    }

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [enabled, animate]);

  // Reset on dimension change
  useEffect(() => {
    smoothedRef.current = null;
    peakRef.current = null;
    peakHoldRef.current = null;
  }, [width, height]);

  if (!enabled) return null;

  return (
    <canvas
      ref={canvasRef}
      width={width}
      height={height}
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        pointerEvents: 'none',
        zIndex: 0,
      }}
    />
  );
}

/**
 * Memoized SpectrumCanvas - prevents re-render unless props change.
 * Important for 60fps canvas animations.
 */
export const SpectrumCanvas = memo(SpectrumCanvasInner);
export default SpectrumCanvas;

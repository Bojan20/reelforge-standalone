/**
 * VanEQ Pro - WebGL Spectrum Analyzer
 *
 * High-performance spectrum visualization using PixiJS:
 * - 60fps GPU-accelerated rendering
 * - Smooth attack/release envelope
 * - Gradient fills with glow
 * - Anti-aliased lines
 */

import { useRef, useEffect, useCallback } from 'react';
import * as PIXI from 'pixi.js';

// ============ Types ============

interface SpectrumWebGLProps {
  /** FFT data in dB */
  fftData: Float32Array | number[] | null;
  /** Sample rate for frequency mapping */
  sampleRate: number;
  /** Width of the canvas */
  width: number;
  /** Height of the canvas */
  height: number;
  /** Minimum frequency to display */
  freqMin?: number;
  /** Maximum frequency to display */
  freqMax?: number;
  /** Whether analyzer is active */
  active?: boolean;
  /** Left margin */
  marginLeft?: number;
  /** Right margin */
  marginRight?: number;
  /** Top margin */
  marginTop?: number;
  /** Bottom margin */
  marginBottom?: number;
}

// ============ Constants ============

const SPECTRUM_CONFIG = {
  barCount: 256,
  attack: 0.35,
  release: 0.12,
  minDb: -100,
  maxDb: 0,
  glowStrength: 0.4,
  lineWidth: 2,
};

// FabFilter Pro-Q4 spectrum colors - cyan/teal
const LINE_COLOR = 0x40c8ff;
const LINE_GLOW_COLOR = 0x60d8ff;
const FILL_COLOR = 0x2090c0;

// ============ Component ============

export function SpectrumWebGL({
  fftData,
  sampleRate,
  width,
  height,
  freqMin = 20,
  freqMax = 20000,
  active = true,
  marginLeft = 50,
  marginRight = 24,
  marginTop = 30,
  marginBottom = 30,
}: SpectrumWebGLProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const fillGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const lineGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const glowGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const smoothedRef = useRef<Float32Array>(new Float32Array(SPECTRUM_CONFIG.barCount));
  const rafRef = useRef<number>(0);
  const lastFftRef = useRef<Float32Array | number[] | null>(null);

  // Calculate working area
  const areaWidth = width - marginLeft - marginRight;
  const areaHeight = height - marginTop - marginBottom;

  // Convert frequency to X position (logarithmic)
  const freqToX = useCallback((freq: number): number => {
    const logMin = Math.log10(freqMin);
    const logMax = Math.log10(freqMax);
    return marginLeft + ((Math.log10(freq) - logMin) / (logMax - logMin)) * areaWidth;
  }, [freqMin, freqMax, marginLeft, areaWidth]);

  // Initialize PixiJS
  useEffect(() => {
    if (!containerRef.current || width <= 0 || height <= 0) return;

    let isMounted = true;

    const initPixi = async () => {
      // Create app
      const app = new PIXI.Application();
      await app.init({
        width,
        height,
        backgroundAlpha: 0,
        antialias: true,
        resolution: 1, // Fixed resolution - devicePixelRatio was causing offset issues
        autoDensity: false,
      });

      if (!isMounted) {
        app.destroy(true);
        return;
      }

      // Append canvas
      if (containerRef.current) {
        containerRef.current.appendChild(app.canvas as HTMLCanvasElement);
      }

      // Create graphics layers
      const glowGraphics = new PIXI.Graphics();
      const fillGraphics = new PIXI.Graphics();
      const lineGraphics = new PIXI.Graphics();

      // Add glow filter to glow layer
      glowGraphics.alpha = SPECTRUM_CONFIG.glowStrength;

      app.stage.addChild(glowGraphics);
      app.stage.addChild(fillGraphics);
      app.stage.addChild(lineGraphics);

      appRef.current = app;
      fillGraphicsRef.current = fillGraphics;
      lineGraphicsRef.current = lineGraphics;
      glowGraphicsRef.current = glowGraphics;
    };

    initPixi();

    return () => {
      isMounted = false;
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
      if (appRef.current) {
        appRef.current.destroy(true);
        appRef.current = null;
      }
    };
  }, [width, height]);

  // Update smoothed spectrum values
  const updateSmoothed = useCallback(() => {
    const data = lastFftRef.current;
    if (!data) return;

    const smoothed = smoothedRef.current;
    const binCount = data.length;
    const nyquist = sampleRate / 2;
    const logMin = Math.log10(freqMin);
    const logMax = Math.log10(freqMax);

    for (let i = 0; i < SPECTRUM_CONFIG.barCount; i++) {
      // Map bar index to frequency (logarithmic)
      const t = i / (SPECTRUM_CONFIG.barCount - 1);
      const freq = Math.pow(10, logMin + t * (logMax - logMin));

      // Map frequency to FFT bin
      const binIndex = Math.floor((freq / nyquist) * binCount);
      const clampedBin = Math.max(0, Math.min(binCount - 1, binIndex));

      // Get dB value
      const dbValue = data[clampedBin] ?? -100;

      // Attack/release smoothing
      const target = Math.max(0, Math.min(1, (dbValue - SPECTRUM_CONFIG.minDb) /
        (SPECTRUM_CONFIG.maxDb - SPECTRUM_CONFIG.minDb)));

      if (target > smoothed[i]) {
        smoothed[i] += (target - smoothed[i]) * SPECTRUM_CONFIG.attack;
      } else {
        smoothed[i] += (target - smoothed[i]) * SPECTRUM_CONFIG.release;
      }
    }
  }, [sampleRate, freqMin, freqMax]);

  // Draw spectrum
  const draw = useCallback(() => {
    const fillGraphics = fillGraphicsRef.current;
    const lineGraphics = lineGraphicsRef.current;
    const glowGraphics = glowGraphicsRef.current;

    if (!fillGraphics || !lineGraphics || !glowGraphics || !active) return;

    // Update smoothed values
    updateSmoothed();

    const smoothed = smoothedRef.current;

    // Build points array
    const points: { x: number; y: number }[] = [];
    const logMin = Math.log10(freqMin);
    const logMax = Math.log10(freqMax);

    for (let i = 0; i < SPECTRUM_CONFIG.barCount; i++) {
      const t = i / (SPECTRUM_CONFIG.barCount - 1);
      const freq = Math.pow(10, logMin + t * (logMax - logMin));
      const x = freqToX(freq);
      const y = marginTop + areaHeight - smoothed[i] * areaHeight * 0.9;
      points.push({ x, y });
    }

    // Clear previous drawings
    fillGraphics.clear();
    lineGraphics.clear();
    glowGraphics.clear();

    if (points.length < 2) return;

    // Draw gradient fill
    fillGraphics.moveTo(marginLeft, marginTop + areaHeight);
    for (const pt of points) {
      fillGraphics.lineTo(pt.x, pt.y);
    }
    fillGraphics.lineTo(marginLeft + areaWidth, marginTop + areaHeight);
    fillGraphics.closePath();

    // Create gradient fill (simulated with alpha)
    fillGraphics.fill({
      color: FILL_COLOR,
      alpha: 0.08,
    });

    // Draw glow line (thicker, more transparent)
    glowGraphics.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      glowGraphics.lineTo(points[i].x, points[i].y);
    }
    glowGraphics.stroke({
      color: LINE_GLOW_COLOR,
      width: SPECTRUM_CONFIG.lineWidth * 4,
      alpha: 0.3,
    });

    // Draw main line
    lineGraphics.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      lineGraphics.lineTo(points[i].x, points[i].y);
    }
    lineGraphics.stroke({
      color: LINE_COLOR,
      width: SPECTRUM_CONFIG.lineWidth,
      alpha: 0.6,
    });

    // Schedule next frame
    rafRef.current = requestAnimationFrame(draw);
  }, [active, updateSmoothed, freqToX, freqMin, freqMax, marginLeft, marginTop, areaWidth, areaHeight]);

  // Update FFT data and start animation
  useEffect(() => {
    lastFftRef.current = fftData;
  }, [fftData]);

  // Start/stop animation loop
  useEffect(() => {
    if (active && appRef.current) {
      rafRef.current = requestAnimationFrame(draw);
    }

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [active, draw]);

  return (
    <div
      ref={containerRef}
      className="spectrum-webgl"
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width,
        height,
        pointerEvents: 'none',
        zIndex: 1,
      }}
    />
  );
}

export default SpectrumWebGL;

/**
 * VanEQ Pro - WebGL EQ Curve Renderer
 *
 * High-quality anti-aliased EQ curve using PixiJS:
 * - Smooth bezier interpolation
 * - Gradient fills above/below zero
 * - Glow effect on curve line
 * - 60fps GPU-accelerated rendering
 */

import { useRef, useEffect, useCallback, useMemo, useState } from 'react';
import * as PIXI from 'pixi.js';

// ============ Types ============

interface Band {
  id: number;
  freq: number;
  gain: number;
  q: number;
  type: 'highpass' | 'lowshelf' | 'bell' | 'highshelf' | 'lowpass' | 'notch' | 'bandpass' | 'tilt';
  active: boolean;
}

interface EQCurveWebGLProps {
  /** EQ bands */
  bands: Band[];
  /** Width of the canvas */
  width: number;
  /** Height of the canvas */
  height: number;
  /** dB range (e.g., 24 means ±24 dB) */
  dbRange?: number;
  /** Minimum frequency */
  freqMin?: number;
  /** Maximum frequency */
  freqMax?: number;
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

const CURVE_CONFIG = {
  resolution: 512, // Number of points to calculate
  lineWidth: 2.5,
  glowWidth: 8,
  glowAlpha: 0.4,
  zeroLineWidth: 1,
  zeroLineAlpha: 0.3,
};

// Colors - FabFilter Pro-Q4 style
const CURVE_COLOR = 0xff9040;       // Orange primary
const GLOW_COLOR = 0xffb060;        // Lighter orange
const FILL_ABOVE_COLOR = 0xff9040;  // Orange for boost
const FILL_BELOW_COLOR = 0x40c8ff;  // Cyan for cut
const ZERO_LINE_COLOR = 0x606070;   // Subtle gray for 0dB line

// ============ Utility Functions ============

function calcBandResponse(band: Band, freq: number): number {
  if (!band.active) return 0;
  const octaves = Math.log2(freq / band.freq);

  switch (band.type) {
    case 'lowshelf':
      if (freq < band.freq) return band.gain;
      return band.gain * Math.max(0, 1 - octaves * band.q * 0.7);
    case 'highshelf':
      if (freq > band.freq) return band.gain;
      return band.gain * Math.max(0, 1 + octaves * band.q * 0.7);
    case 'lowpass':
      if (freq <= band.freq) return 0;
      const lpSlope = 12 + (band.q - 0.707) * 6;
      return -octaves * lpSlope;
    case 'highpass':
      if (freq >= band.freq) return 0;
      const hpSlope = 12 + (band.q - 0.707) * 6;
      return octaves * hpSlope;
    case 'notch':
      return -24 * Math.exp(-octaves * octaves * band.q * 3);
    case 'bandpass':
      return band.gain * Math.exp(-octaves * octaves * band.q * 1.2);
    case 'tilt':
      return band.gain * octaves * 0.5;
    case 'bell':
    default:
      return band.gain * Math.exp(-octaves * octaves * band.q * 1.5);
  }
}

// ============ Component ============

export function EQCurveWebGL({
  bands,
  width,
  height,
  dbRange = 24,
  freqMin = 20,
  freqMax = 20000,
  marginLeft = 50,
  marginRight = 24,
  marginTop = 30,
  marginBottom = 30,
}: EQCurveWebGLProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const zeroLineRef = useRef<PIXI.Graphics | null>(null);
  const fillAboveRef = useRef<PIXI.Graphics | null>(null);
  const fillBelowRef = useRef<PIXI.Graphics | null>(null);
  const glowRef = useRef<PIXI.Graphics | null>(null);
  const lineRef = useRef<PIXI.Graphics | null>(null);

  // Trigger state to force redraw after PixiJS init completes
  const [pixiReady, setPixiReady] = useState(0);

  // Calculate working area
  const areaWidth = width - marginLeft - marginRight;
  const areaHeight = height - marginTop - marginBottom;

  // Convert frequency to X position (logarithmic)
  const freqToX = useCallback((freq: number): number => {
    const logMin = Math.log10(freqMin);
    const logMax = Math.log10(freqMax);
    return marginLeft + ((Math.log10(freq) - logMin) / (logMax - logMin)) * areaWidth;
  }, [freqMin, freqMax, marginLeft, areaWidth]);

  // Convert gain to Y position
  const gainToY = useCallback((gain: number): number => {
    const fullRange = dbRange * 2;
    return marginTop + (1 - (gain + dbRange) / fullRange) * areaHeight;
  }, [dbRange, marginTop, areaHeight]);

  // Calculate curve points
  // Include exact band frequencies to ensure curve passes through node centers
  const curvePoints = useMemo(() => {
    const logMin = Math.log10(freqMin);
    const logMax = Math.log10(freqMax);

    // Build frequency list: regular samples + exact band frequencies
    const frequencies: number[] = [];

    // Regular samples
    for (let i = 0; i <= CURVE_CONFIG.resolution; i++) {
      const t = i / CURVE_CONFIG.resolution;
      frequencies.push(Math.pow(10, logMin + t * (logMax - logMin)));
    }

    // Add exact band frequencies for active bands
    for (const band of bands) {
      if (band.active && band.freq >= freqMin && band.freq <= freqMax) {
        frequencies.push(band.freq);
      }
    }

    // Sort and dedupe (remove frequencies too close together)
    frequencies.sort((a, b) => a - b);
    const uniqueFreqs: number[] = [];
    for (const f of frequencies) {
      if (uniqueFreqs.length === 0 || Math.abs(Math.log10(f) - Math.log10(uniqueFreqs[uniqueFreqs.length - 1])) > 0.001) {
        uniqueFreqs.push(f);
      }
    }

    // Calculate points
    const points: { x: number; y: number; gain: number }[] = [];
    for (const freq of uniqueFreqs) {
      const gain = bands.reduce((sum, band) => sum + calcBandResponse(band, freq), 0);
      points.push({
        x: freqToX(freq),
        y: gainToY(gain),
        gain,
      });
    }

    return points;
  }, [bands, freqMin, freqMax, freqToX, gainToY]);

  // Zero line Y position
  const zeroY = useMemo(() => gainToY(0), [gainToY]);

  // Initialize PixiJS - only creates app and graphics layers
  useEffect(() => {
    if (!containerRef.current || width <= 0 || height <= 0) return;

    let isMounted = true;

    const initPixi = async () => {
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

      if (containerRef.current) {
        containerRef.current.appendChild(app.canvas as HTMLCanvasElement);
      }

      // Create graphics layers (order matters - zero line first, then fills, then curve)
      const zeroLine = new PIXI.Graphics();
      const fillAbove = new PIXI.Graphics();
      const fillBelow = new PIXI.Graphics();
      const glow = new PIXI.Graphics();
      const line = new PIXI.Graphics();

      app.stage.addChild(zeroLine);
      app.stage.addChild(fillAbove);
      app.stage.addChild(fillBelow);
      app.stage.addChild(glow);
      app.stage.addChild(line);

      appRef.current = app;
      zeroLineRef.current = zeroLine;
      fillAboveRef.current = fillAbove;
      fillBelowRef.current = fillBelow;
      glowRef.current = glow;
      lineRef.current = line;

      // Trigger redraw now that graphics layers are ready
      setPixiReady(prev => prev + 1);
    };

    initPixi();

    return () => {
      isMounted = false;
      if (appRef.current) {
        appRef.current.destroy(true);
        appRef.current = null;
      }
    };
  }, [width, height]);

  // Draw curve
  useEffect(() => {
    const zeroLine = zeroLineRef.current;
    const fillAbove = fillAboveRef.current;
    const fillBelow = fillBelowRef.current;
    const glow = glowRef.current;
    const line = lineRef.current;

    if (!zeroLine || !fillAbove || !fillBelow || !glow || !line || curvePoints.length < 2) return;

    // Clear all graphics
    zeroLine.clear();
    fillAbove.clear();
    fillBelow.clear();
    glow.clear();
    line.clear();

    // Always draw 0dB line
    zeroLine.moveTo(marginLeft, zeroY);
    zeroLine.lineTo(marginLeft + areaWidth, zeroY);
    zeroLine.stroke({
      color: ZERO_LINE_COLOR,
      width: CURVE_CONFIG.zeroLineWidth,
      alpha: CURVE_CONFIG.zeroLineAlpha,
    });

    // Check if any band is active - if not, don't draw the EQ curve
    const hasActiveBands = bands.some(b => b.active);
    if (!hasActiveBands) return;

    // Build path for curve line
    const firstPoint = curvePoints[0];

    // Draw glow (thick, transparent line)
    glow.moveTo(firstPoint.x, firstPoint.y);
    for (let i = 1; i < curvePoints.length; i++) {
      glow.lineTo(curvePoints[i].x, curvePoints[i].y);
    }
    glow.stroke({
      color: GLOW_COLOR,
      width: CURVE_CONFIG.glowWidth,
      alpha: CURVE_CONFIG.glowAlpha,
    });

    // Draw main curve line
    line.moveTo(firstPoint.x, firstPoint.y);
    for (let i = 1; i < curvePoints.length; i++) {
      line.lineTo(curvePoints[i].x, curvePoints[i].y);
    }
    line.stroke({
      color: CURVE_COLOR,
      width: CURVE_CONFIG.lineWidth,
      alpha: 0.9,
    });

    // Fill above zero (boost)
    fillAbove.moveTo(firstPoint.x, zeroY);
    for (const pt of curvePoints) {
      fillAbove.lineTo(pt.x, Math.min(pt.y, zeroY));
    }
    fillAbove.lineTo(curvePoints[curvePoints.length - 1].x, zeroY);
    fillAbove.closePath();
    fillAbove.fill({
      color: FILL_ABOVE_COLOR,
      alpha: 0.12,
    });

    // Fill below zero (cut)
    fillBelow.moveTo(firstPoint.x, zeroY);
    for (const pt of curvePoints) {
      fillBelow.lineTo(pt.x, Math.max(pt.y, zeroY));
    }
    fillBelow.lineTo(curvePoints[curvePoints.length - 1].x, zeroY);
    fillBelow.closePath();
    fillBelow.fill({
      color: FILL_BELOW_COLOR,
      alpha: 0.1,
    });

  }, [curvePoints, zeroY, marginLeft, areaWidth, pixiReady, bands]);

  return (
    <div
      ref={containerRef}
      className="eq-curve-webgl"
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width,
        height,
        pointerEvents: 'none',
        zIndex: 2,
      }}
    />
  );
}

export default EQCurveWebGL;

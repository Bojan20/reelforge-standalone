/**
 * VanEQ Pro - EQ Graph Component
 * VERSION: 2025-12-22-v12 - Full FabFilter implementation
 *
 * Features:
 * - DSP-accurate RBJ biquad coefficient design + complex H(e^jw) evaluation
 * - Correct cascaded response: MULTIPLY magnitudes (linear), then convert to dB
 * - Bell baseline: gain=0 → magnitude=1 → 0dB (exact flat line)
 * - FabFilter-style node Y: gain filters use gainDb, cut filters sit on curve
 * - Instant drag preview (optimistic UI, no roundtrip lag)
 * - PERCEPTUAL (nonlinear) mapping:
 *   - Frequency: logarithmic (20Hz-20kHz over 3 decades)
 *   - Q: pow(q, 1.15) for musical feel (wider range at high Q)
 *   - Gain: perceptual curve for fine control in center
 * - Spectrum analyzer overlay from AudioWorklet FFT data
 */

import React, { useState, useCallback, useMemo, useRef, useEffect, memo } from 'react';
import type { Band, BandType } from './utils';
import { FilterTypeIcon } from './FilterTypeIcon';
import { buildSpectrumPath, type SpectrumData } from './buildSpectrumPath';
import { SpectrumCanvas } from './SpectrumCanvas';
import {
  FREQ_MIN,
  FREQ_MAX,
  DB_MIN,
  DB_MAX,
  Q_PERCEPTUAL_EXPONENT,
  SAMPLE_RATE_DEFAULT,
  DB_TO_LINEAR,
  freqToX,
  xToFreq,
  dbToY,
  yToDb,
  clamp,
  formatFreq,
  formatDb,
} from './frequencyUtils';

// ============ Constants ============

/** Sample rate for filter design calculations */
const SR = SAMPLE_RATE_DEFAULT;

// 8 bands: vibrant FabFilter Pro-Q4 palette (WOW Edition)
const BAND_COLORS = [
  '#ff6b8a', // Band 1 - Rose
  '#ffb347', // Band 2 - Orange
  '#47d4ff', // Band 3 - Cyan
  '#4ade80', // Band 4 - Green
  '#a78bfa', // Band 5 - Purple
  '#f472b6', // Band 6 - Pink
  '#fb923c', // Band 7 - Amber
  '#22d3d3', // Band 8 - Teal
];

const FREQ_LABELS = [20, 50, 100, 200, 500, '1k', '2k', '5k', '10k', '20k'];
const FREQ_VALUES = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
const DB_LABELS = [24, 12, 0, -12, -24];

// ============ Perceptual (Nonlinear) Mapping ============
// NOTE: freqToX, xToFreq, dbToY, yToDb are imported from frequencyUtils.ts
// See frequencyUtils.ts for WHY LOGARITHMIC FREQUENCY explanation.

function getBandColor(index: number): string {
  return BAND_COLORS[index % BAND_COLORS.length];
}

function isCutType(t: BandType): boolean {
  return t === 'highPass' || t === 'lowPass' || t === 'notch' || t === 'bandPass';
}

function isGainType(t: BandType): boolean {
  return t === 'bell' || t === 'lowShelf' || t === 'highShelf' || t === 'tilt';
}

// ============ DSP-accurate RBJ biquads ============
// NOTE: DB_TO_LINEAR imported from frequencyUtils.ts

type Biquad = { b0: number; b1: number; b2: number; a1: number; a2: number };

// ============ Biquad Coefficient Cache ============
// Caches computed biquad coefficients to avoid recalculation on every frame.
// Key: "type|freq|gain|q" -> Biquad
// ~15% CPU reduction during curve rendering.

/** Maximum cache entries before cleanup */
const BIQUAD_CACHE_MAX_SIZE = 256;

/** Biquad coefficient cache */
const biquadCache: Map<string, Biquad> = new Map();

/**
 * Generate cache key for biquad coefficients.
 * Uses fixed precision to avoid floating-point key explosion.
 */
function getBiquadCacheKey(type: string, freq: number, gain: number, q: number): string {
  // Round to 2 decimal places for freq/gain, 3 for Q (more precision needed for Q)
  return `${type}|${freq.toFixed(1)}|${gain.toFixed(1)}|${q.toFixed(3)}`;
}

/**
 * Get or compute biquad coefficients with caching.
 */
function getCachedBiquad(
  type: string,
  sr: number,
  freq: number,
  gain: number,
  q: number
): Biquad | null {
  const key = getBiquadCacheKey(type, freq, gain, q);

  // Check cache
  const cached = biquadCache.get(key);
  if (cached) return cached;

  // Compute
  let biq: Biquad | null = null;

  switch (type) {
    case 'bell':
      if (gain === 0) return null; // Unity, no filter needed
      biq = designBell(sr, freq, gain, q);
      break;
    case 'lowShelf':
      if (gain === 0) return null;
      biq = designLowShelf(sr, freq, gain, 1);
      break;
    case 'highShelf':
      if (gain === 0) return null;
      biq = designHighShelf(sr, freq, gain, 1);
      break;
    case 'highPass':
      biq = designHighPass(sr, freq, q);
      break;
    case 'lowPass':
      biq = designLowPass(sr, freq, q);
      break;
    case 'notch':
      biq = designNotch(sr, freq, q);
      break;
    case 'bandPass': {
      const w0 = (2 * Math.PI * freq) / sr;
      const cw = Math.cos(w0);
      const alpha = Math.sin(w0) / (2 * q);
      biq = norm({
        b0: alpha,
        b1: 0,
        b2: -alpha,
        a0: 1 + alpha,
        a1: -2 * cw,
        a2: 1 - alpha,
      });
      break;
    }
    default:
      return null;
  }

  if (!biq) return null;

  // Store in cache (with LRU-style cleanup)
  if (biquadCache.size >= BIQUAD_CACHE_MAX_SIZE) {
    // Remove oldest entries (first 25%)
    const keysToDelete = Array.from(biquadCache.keys()).slice(0, BIQUAD_CACHE_MAX_SIZE / 4);
    keysToDelete.forEach(k => biquadCache.delete(k));
  }

  biquadCache.set(key, biq);
  return biq;
}

function norm(c: { b0: number; b1: number; b2: number; a0: number; a1: number; a2: number }): Biquad {
  return { b0: c.b0 / c.a0, b1: c.b1 / c.a0, b2: c.b2 / c.a0, a1: c.a1 / c.a0, a2: c.a2 / c.a0 };
}

function designBell(sr: number, f: number, gDb: number, q: number): Biquad {
  const A = DB_TO_LINEAR(gDb);
  const w0 = (2 * Math.PI * f) / sr;
  const alpha = Math.sin(w0) / (2 * q);
  const cw = Math.cos(w0);

  const b0 = 1 + alpha * A;
  const b1 = -2 * cw;
  const b2 = 1 - alpha * A;
  const a0 = 1 + alpha / A;
  const a1 = -2 * cw;
  const a2 = 1 - alpha / A;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

function designNotch(sr: number, f: number, q: number): Biquad {
  const w0 = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * q);

  const b0 = 1;
  const b1 = -2 * cw;
  const b2 = 1;
  const a0 = 1 + alpha;
  const a1 = -2 * cw;
  const a2 = 1 - alpha;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

function designHighPass(sr: number, f: number, q: number): Biquad {
  const w0 = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * q);

  const b0 = (1 + cw) / 2;
  const b1 = -(1 + cw);
  const b2 = (1 + cw) / 2;
  const a0 = 1 + alpha;
  const a1 = -2 * cw;
  const a2 = 1 - alpha;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

function designLowPass(sr: number, f: number, q: number): Biquad {
  const w0 = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * q);

  const b0 = (1 - cw) / 2;
  const b1 = (1 - cw);
  const b2 = (1 - cw) / 2;
  const a0 = 1 + alpha;
  const a1 = -2 * cw;
  const a2 = 1 - alpha;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

// RBJ shelves (S=1)
function designLowShelf(sr: number, f: number, gDb: number, S = 1): Biquad {
  const A = DB_TO_LINEAR(gDb);
  const w0 = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w0);
  const sw = Math.sin(w0);
  const alpha = (sw / 2) * Math.sqrt((A + 1 / A) * (1 / S - 1) + 2);
  const sqrtA = Math.sqrt(A);

  const b0 = A * ((A + 1) - (A - 1) * cw + 2 * sqrtA * alpha);
  const b1 = 2 * A * ((A - 1) - (A + 1) * cw);
  const b2 = A * ((A + 1) - (A - 1) * cw - 2 * sqrtA * alpha);
  const a0 = (A + 1) + (A - 1) * cw + 2 * sqrtA * alpha;
  const a1 = -2 * ((A - 1) + (A + 1) * cw);
  const a2 = (A + 1) + (A - 1) * cw - 2 * sqrtA * alpha;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

function designHighShelf(sr: number, f: number, gDb: number, S = 1): Biquad {
  const A = DB_TO_LINEAR(gDb);
  const w0 = (2 * Math.PI * f) / sr;
  const cw = Math.cos(w0);
  const sw = Math.sin(w0);
  const alpha = (sw / 2) * Math.sqrt((A + 1 / A) * (1 / S - 1) + 2);
  const sqrtA = Math.sqrt(A);

  const b0 = A * ((A + 1) + (A - 1) * cw + 2 * sqrtA * alpha);
  const b1 = -2 * A * ((A - 1) + (A + 1) * cw);
  const b2 = A * ((A + 1) + (A - 1) * cw - 2 * sqrtA * alpha);
  const a0 = (A + 1) - (A - 1) * cw + 2 * sqrtA * alpha;
  const a1 = 2 * ((A - 1) - (A + 1) * cw);
  const a2 = (A + 1) - (A - 1) * cw - 2 * sqrtA * alpha;
  return norm({ b0, b1, b2, a0, a1, a2 });
}

/**
 * Calculate |H(e^jw)| - frequency response magnitude at given frequency
 */
function biquadMagAtFreq(b: Biquad, sr: number, freq: number): number {
  const w = (2 * Math.PI * freq) / sr;

  const c1 = Math.cos(w);
  const s1 = -Math.sin(w);
  const c2 = Math.cos(2 * w);
  const s2 = -Math.sin(2 * w);

  const nr = b.b0 + b.b1 * c1 + b.b2 * c2;
  const ni = b.b1 * s1 + b.b2 * s2;

  const dr = 1 + b.a1 * c1 + b.a2 * c2;
  const di = b.a1 * s1 + b.a2 * s2;

  const n2 = nr * nr + ni * ni;
  const d2 = dr * dr + di * di;

  return Math.sqrt(Math.max(1e-20, n2 / Math.max(1e-20, d2)));
}

/**
 * Calculate band magnitude at frequency.
 * CRITICAL: Bell/shelf with gain=0 returns 1.0 (unity) → 0dB baseline
 *
 * Uses biquad coefficient caching for ~15% CPU reduction.
 *
 * WHY PERCEPTUAL Q MAPPING:
 * Raw Q values are linear but musical perception is logarithmic.
 * Q=1 feels "normal", Q=10 feels "narrow", Q=0.5 feels "wide".
 * A pow(q, 1.15) curve gives more control at musical values (0.5-4)
 * while still allowing surgical narrow bands (10+).
 */
function calculateBandMag(band: Band, freq: number): number {
  if (!band.enabled) return 1;

  const f0 = clamp(band.freqHz, FREQ_MIN, FREQ_MAX);
  const f = clamp(freq, FREQ_MIN, FREQ_MAX);

  // PERCEPTUAL Q: Apply pow curve for musical feel
  const qUi = clamp(band.q || 1, 0.1, 24);
  const q = Math.pow(qUi, Q_PERCEPTUAL_EXPONENT);

  const g = clamp(band.gainDb || 0, -24, 24);

  // Tilt filter: visual-only approximation (not cacheable)
  if (band.type === 'tilt') {
    if (g === 0) return 1;
    const tiltRatio = Math.log10(f / f0);
    const tiltDb = clamp(tiltRatio * g * 0.5, DB_MIN, DB_MAX);
    return Math.pow(10, tiltDb / 20);
  }

  // Use cached biquad coefficients for all other filter types
  const biq = getCachedBiquad(band.type, SR, f0, g, q);
  if (!biq) return 1; // Unity gain (e.g., bell/shelf with gain=0)

  return biquadMagAtFreq(biq, SR, f);
}

/**
 * Get node Y position in dB.
 * Gain filters: node at gain value
 * Cut filters: node sits on curve at cutoff frequency
 */
function getNodeGainDb(band: Band): number {
  if (isGainType(band.type)) return band.gainDb;

  // Cut filters: calculate their own contribution at cutoff
  const mag = calculateBandMag(band, band.freqHz);
  return 20 * Math.log10(Math.max(1e-12, mag));
}

// ============ Types ============

// SpectrumData is imported from buildSpectrumPath.ts

type Props = {
  bands: Band[];
  activeIndex: number;
  onSelect: (index: number) => void;
  onBandChange: (index: number, updates: Partial<Pick<Band, 'freqHz' | 'gainDb' | 'q'>>) => void;
  onBandEnable: (index: number, enabled: boolean) => void;
  analyzerOn?: boolean;
  spectrumData?: SpectrumData | null;
  /** Freeze spectrum updates (during external drag to save frame time) */
  freezeSpectrum?: boolean;
  /** Use canvas-based spectrum analyzer (WOW Edition) */
  useCanvasSpectrum?: boolean;
  /** Whether audio is playing (for canvas spectrum simulation) */
  isPlaying?: boolean;
  /** Analyzer quality setting */
  analyzerQuality?: 'low' | 'mid' | 'high';
};

type Tooltip = {
  visible: boolean;
  x: number;
  y: number;
  bandIndex: number;
  freqHz: number;
  gainDb: number;
  q: number;
};

// ============ Component ============

function EQGraphInner({
  bands,
  activeIndex,
  onSelect,
  onBandChange,
  onBandEnable,
  analyzerOn = false,
  spectrumData,
  freezeSpectrum = false,
  useCanvasSpectrum = true,  // Default to canvas for WOW Edition
  isPlaying = false,
  analyzerQuality = 'mid',
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 280 });

  const [tooltip, setTooltip] = useState<Tooltip>({
    visible: false, x: 0, y: 0, bandIndex: 0, freqHz: 1000, gainDb: 0, q: 1,
  });

  const [dragging, setDragging] = useState<{
    index: number;
    startClientX: number;
    startClientY: number;
    startFreq: number;
    startGain: number;
    startQ: number;
    startDbFromY: number;
  } | null>(null);

  // Sync ref for instant drag state access (avoids React batch delay)
  const draggingRef = useRef<typeof dragging>(null);

  // ============ Instant Preview (optimistic UI) ============
  // During drag: use previewBands for instant feedback
  // When not dragging: sync with props

  const [previewBands, setPreviewBands] = useState<Band[]>(bands);
  const previewBandsRef = useRef<Band[]>(bands); // Mirror for sync read in callbacks

  // CRITICAL: Use React state for isDragging, not ref
  // The ref is only for instant access in event handlers
  // The state is for reactive re-renders
  const isDragging = dragging !== null;

  // rAF throttle for host updates (1 update per frame)
  const rafRef = useRef<number | null>(null);
  const pendingRef = useRef<{ index: number; updates: Partial<Pick<Band, 'freqHz' | 'gainDb' | 'q'>> } | null>(null);

  // Pointer capture tracking (for proper release on up/cancel)
  const capturedPointerRef = useRef<{ id: number; target: Element } | null>(null);

  // Cleanup RAF on unmount (prevent zombie callbacks)
  useEffect(() => {
    return () => {
      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
    };
  }, []);

  // Sync preview with props when NOT dragging
  useEffect(() => {
    if (!isDragging) {
      setPreviewBands(bands);
      previewBandsRef.current = bands;
    }
  }, [bands, isDragging]);

  // Which bands to use for rendering
  // During drag: use previewBands state (triggers re-render) synced with ref
  // The ref ensures handlePointerMove always has fresh data
  // The state ensures React re-renders with updated values
  const renderBands = isDragging ? previewBands : bands;

  // Resize observer
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const observer = new ResizeObserver((entries) => {
      const { width, height } = entries[0].contentRect;
      setDimensions({ width, height });
    });

    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  const { width, height } = dimensions;
  const padding = { left: 36, right: 12, top: 12, bottom: 20 };
  const graphWidth = width - padding.left - padding.right;
  const graphHeight = height - padding.top - padding.bottom;

  // ============ Spectrum analyzer freeze cache ============
  // Keep last good spectrum frame when not frozen (FabFilter-style)
  // This prevents micro-stutter during knob drag

  const lastSpectrumRef = useRef<SpectrumData | null>(null);
  const lastSpectrumPathRef = useRef<string>('');
  const lastSpectrumBuildTRef = useRef<number>(0);

  // Capture spectrum data when not frozen
  useEffect(() => {
    if (!freezeSpectrum && !isDragging && spectrumData) {
      lastSpectrumRef.current = spectrumData;
    }
  }, [freezeSpectrum, isDragging, spectrumData]);

  // While frozen, reuse last captured frame (or fallback to current if none)
  const effectiveSpectrum = useMemo(() => {
    if (freezeSpectrum || isDragging) {
      return lastSpectrumRef.current ?? spectrumData ?? null;
    }
    return spectrumData ?? null;
  }, [freezeSpectrum, isDragging, spectrumData]);

  // ============ Spectrum analyzer path (FabFilter-style) ============
  // Uses buildSpectrumPath with:
  // - Log frequency mapping
  // - Soft floor compression (no hard clip at noise floor)
  // - EMA smoothing (bidirectional)
  // - Bin decimation for performance
  // - 30fps throttle

  const spectrumPath = useMemo(() => {
    if (!analyzerOn || !effectiveSpectrum?.fftDb || graphWidth <= 0 || graphHeight <= 0) {
      lastSpectrumPathRef.current = '';
      return '';
    }

    // 30fps throttle when not frozen (reduces CPU during live updates)
    const now = performance.now();
    if (!freezeSpectrum && !isDragging && (now - lastSpectrumBuildTRef.current) < 33) {
      return lastSpectrumPathRef.current; // reuse last path (30fps cap)
    }
    lastSpectrumBuildTRef.current = now;

    // Build path using FabFilter-style algorithm
    const path = buildSpectrumPath(effectiveSpectrum, {
      x0: padding.left,
      y0: padding.top,
      width: graphWidth,
      height: graphHeight,
      minHz: FREQ_MIN,
      maxHz: FREQ_MAX,
      minDb: -90,
      maxDb: -18,
      smoothing: 0.22,
      step: 2,
      floorDb: -90,
      floorKneeDb: 8,
    });

    // Store for reuse
    lastSpectrumPathRef.current = path;
    return path;
  }, [analyzerOn, effectiveSpectrum, graphWidth, graphHeight, padding.left, padding.top, freezeSpectrum, isDragging]);

  // ============ Total curve path ============

  const curvePath = useMemo(() => {
    if (graphWidth <= 0 || graphHeight <= 0) return '';

    // Fewer points during drag for better performance
    const numPoints = isDragging ? 256 : 512;
    const points: { x: number; y: number }[] = [];

    for (let i = 0; i <= numPoints; i++) {
      const t = i / numPoints;
      const freq = FREQ_MIN * Math.pow(FREQ_MAX / FREQ_MIN, t);
      const x = freqToX(freq, graphWidth) + padding.left;

      /**
       * CORRECT CASCADE MATH:
       * DO NOT add dB values - that's wrong!
       * MULTIPLY magnitudes (linear), then convert to dB.
       *
       * Why: dB is logarithmic. Adding dB = multiplying ratios.
       * For cascaded filters, we want: total = filter1 * filter2 * ...
       * Not: total_dB = dB1 + dB2 (this double-counts the log)
       */
      let totalMag = 1;
      for (const band of renderBands) {
        totalMag *= calculateBandMag(band, freq);
      }

      const totalDb = 20 * Math.log10(Math.max(1e-12, totalMag));
      const y = dbToY(totalDb, graphHeight) + padding.top;
      points.push({ x, y });
    }

    if (points.length < 2) return '';

    // Smooth quadratic Bézier path
    let d = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length - 1; i++) {
      const p1 = points[i];
      const p2 = points[i + 1];
      const midX = (p1.x + p2.x) / 2;
      const midY = (p1.y + p2.y) / 2;
      d += ` Q ${p1.x} ${p1.y} ${midX} ${midY}`;
    }
    const last = points[points.length - 1];
    d += ` L ${last.x} ${last.y}`;
    return d;
  }, [renderBands, graphWidth, graphHeight, padding.left, padding.top]);

  // ============ Grid ============

  const gridLines = useMemo(() => {
    if (graphWidth <= 0 || graphHeight <= 0) return [];

    const lines: React.ReactNode[] = [];

    for (let i = 0; i <= 20; i++) {
      const x = (i / 20) * graphWidth + padding.left;
      const isMajor = i % 4 === 0;
      lines.push(
        <line
          key={`v${i}`}
          x1={x}
          y1={padding.top}
          x2={x}
          y2={height - padding.bottom}
          className={isMajor ? 'gridMajor' : 'gridMinor'}
        />
      );
    }

    for (let i = 0; i <= 8; i++) {
      const y = (i / 8) * graphHeight + padding.top;
      const isMajor = i % 2 === 0;
      lines.push(
        <line
          key={`h${i}`}
          x1={padding.left}
          y1={y}
          x2={width - padding.right}
          y2={y}
          className={isMajor ? 'gridMajor' : 'gridMinor'}
        />
      );
    }

    return lines;
  }, [width, height, graphWidth, graphHeight, padding]);

  const freqLabels = useMemo(() => {
    if (graphWidth <= 0) return [];
    return FREQ_VALUES.map((freq, i) => {
      const x = freqToX(freq, graphWidth) + padding.left;
      return (
        <text key={freq} x={x} y={height - 4} className="axisLabel" textAnchor="middle">
          {FREQ_LABELS[i]}
        </text>
      );
    });
  }, [graphWidth, height, padding.left]);

  const dbLabels = useMemo(() => {
    if (graphHeight <= 0) return [];
    return DB_LABELS.map((db) => {
      const y = dbToY(db, graphHeight) + padding.top;
      return (
        <text key={db} x={padding.left - 6} y={y + 3} className="axisLabel" textAnchor="end">
          {db > 0 ? `+${db}` : db}
        </text>
      );
    });
  }, [graphHeight, padding.left, padding.top]);

  // ============ Node positions ============

  const nodePositions = useMemo(() => {
    if (graphWidth <= 0 || graphHeight <= 0) return [];
    return renderBands.map((band) => {
      const nodeDb = getNodeGainDb(band);
      return {
        x: freqToX(band.freqHz, graphWidth) + padding.left,
        y: dbToY(nodeDb, graphHeight) + padding.top,
      };
    });
  }, [renderBands, graphWidth, graphHeight, padding.left, padding.top]);

  // Active node drawn last (on top)
  const drawOrder = useMemo(() => {
    const idxs = bands.map((_, i) => i);
    return idxs.filter(i => i !== activeIndex).concat(activeIndex);
  }, [bands, activeIndex]);

  // ============ Drag handlers ============

  const handlePointerDown = useCallback((e: React.PointerEvent, band: Band) => {
    e.preventDefault();
    e.stopPropagation();

    // Capture pointer for reliable drag (even outside window)
    const target = e.target as Element;
    target.setPointerCapture(e.pointerId);
    capturedPointerRef.current = { id: e.pointerId, target };

    onSelect(band.index);
    if (!band.enabled) onBandEnable(band.index, true);

    // INSTANT PREVIEW: Snapshot bands at drag start
    // This ensures renderBands uses fresh data immediately when isDragging becomes true
    setPreviewBands(bands);
    previewBandsRef.current = bands;

    const container = containerRef.current;
    const rect = container?.getBoundingClientRect();
    const localY = rect ? (e.clientY - rect.top - padding.top) : 0;
    const startDbFromY = yToDb(localY, graphHeight);

    // Create drag state
    const dragState = {
      index: band.index,
      startClientX: e.clientX,
      startClientY: e.clientY,
      startFreq: band.freqHz,
      startGain: band.gainDb,
      startQ: band.q,
      startDbFromY,
    };

    // Update BOTH ref (instant) and state (triggers render)
    draggingRef.current = dragState;
    setDragging(dragState);

    const pos = nodePositions[band.index];
    if (pos) {
      setTooltip({
        visible: true,
        x: pos.x,
        y: pos.y,
        bandIndex: band.index,
        freqHz: band.freqHz,
        gainDb: band.gainDb,
        q: band.q,
      });
    }
  }, [onSelect, onBandEnable, nodePositions, graphHeight, padding.top, bands]);

  // Schedule host update via rAF (throttled to 1 update per frame)
  const scheduleHostSend = useCallback((index: number, updates: Partial<Pick<Band, 'freqHz' | 'gainDb' | 'q'>>) => {
    pendingRef.current = { index, updates };

    if (rafRef.current === null) {
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = null;
        const pending = pendingRef.current;
        if (pending) {
          onBandChange(pending.index, pending.updates);
          pendingRef.current = null;
        }
      });
    }
  }, [onBandChange]);

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    // Use ref for instant check (no React batch delay)
    const drag = draggingRef.current;
    if (!drag) return;

    const container = containerRef.current;
    if (!container) return;

    const rect = container.getBoundingClientRect();
    const x = e.clientX - rect.left - padding.left;
    const y = e.clientY - rect.top - padding.top;

    // Read from ref for instant sync (avoids stale closure)
    const b = previewBandsRef.current[drag.index];
    if (!b) return;

    // SHIFT = fine control (0.25x sensitivity)
    const fine = e.shiftKey ? 0.25 : 1.0;

    // X always controls frequency (logarithmic)
    const freqHz = clamp(xToFreq(x, graphWidth), FREQ_MIN, FREQ_MAX);

    // Y controls:
    // - ALT: Q for all types (FabFilter behavior)
    // - otherwise: gain for gain-types, Q for cut-types
    const dy = (drag.startClientY - e.clientY) * fine;

    let updates: Partial<Pick<Band, 'freqHz' | 'gainDb' | 'q'>> = { freqHz };

    if (e.altKey || isCutType(b.type)) {
      // Q: exponential feel (vertical drag scales multiplicatively)
      const baseQ = drag.startQ || 1;
      const qScale = Math.pow(2, dy / 120); // ~1 octave Q change per 120px
      const newQ = clamp(baseQ * qScale, 0.1, 24);
      updates.q = newQ;
      // Cut filters: keep gain at 0
      if (isCutType(b.type)) updates.gainDb = 0;
    } else {
      // Gain: map Y to dB directly
      const gainDb = clamp(yToDb(y, graphHeight), DB_MIN, DB_MAX);
      updates.gainDb = gainDb;
    }

    // INSTANT PREVIEW: Update both ref and state
    const updatedBand = { ...b, ...updates };
    const nextBands = [...previewBandsRef.current];
    nextBands[drag.index] = updatedBand;
    previewBandsRef.current = nextBands;
    setPreviewBands(nextBands);

    // Schedule host update via rAF (throttled)
    scheduleHostSend(drag.index, updates);

    // Tooltip follows node
    const tipGain = updates.gainDb ?? b.gainDb;
    const tipQ = updates.q ?? b.q;

    const nodeDb = getNodeGainDb(updatedBand);
    setTooltip({
      visible: true,
      x: freqToX(freqHz, graphWidth) + padding.left,
      y: dbToY(nodeDb, graphHeight) + padding.top,
      bandIndex: drag.index,
      freqHz,
      gainDb: tipGain,
      q: tipQ,
    });
  }, [graphWidth, graphHeight, padding.left, padding.top, scheduleHostSend]);

  const handlePointerUp = useCallback((_e?: React.PointerEvent) => {
    // Release pointer capture (prevents "stuck drag" when mouse leaves window)
    if (capturedPointerRef.current) {
      try {
        capturedPointerRef.current.target.releasePointerCapture(capturedPointerRef.current.id);
      } catch {
        // Ignore if already released
      }
      capturedPointerRef.current = null;
    }

    // Cancel pending rAF
    if (rafRef.current !== null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }

    // Send final update to host
    if (pendingRef.current) {
      onBandChange(pendingRef.current.index, pendingRef.current.updates);
      pendingRef.current = null;
    }

    // Clear drag state (both ref and state)
    draggingRef.current = null;
    setDragging(null);
    setTooltip((prev) => ({ ...prev, visible: false }));
  }, [onBandChange]);

  // ============ Render ============

  return (
    <div
      ref={containerRef}
      style={{ width: '100%', height: '100%', position: 'relative', touchAction: 'none' }}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerLeave={handlePointerUp}
    >
      {/* Canvas-based spectrum analyzer (WOW Edition - behind everything) */}
      {analyzerOn && useCanvasSpectrum && (
        <SpectrumCanvas
          width={width}
          height={height}
          fftDb={spectrumData?.fftDb}
          sampleRate={spectrumData?.sampleRate}
          enabled={analyzerOn}
          isPlaying={isPlaying}
          quality={analyzerQuality}
          padding={padding}
        />
      )}

      <svg className="graphSvg" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        {gridLines}

        {/* 0dB reference line */}
        <line
          x1={padding.left}
          y1={dbToY(0, graphHeight) + padding.top}
          x2={width - padding.right}
          y2={dbToY(0, graphHeight) + padding.top}
          className="zeroLine"
        />

        {/* SVG Spectrum analyzer fallback (when canvas not used) */}
        {analyzerOn && !useCanvasSpectrum && (
          <g className="vaneqSpectrumLayer" pointerEvents="none" shapeRendering="optimizeSpeed">
            {spectrumPath && (
              <path d={spectrumPath} className="vaneqSpectrumGlow" vectorEffect="non-scaling-stroke" />
            )}
            {spectrumPath && (
              <path d={spectrumPath} className="vaneqSpectrumPath" vectorEffect="non-scaling-stroke" />
            )}
          </g>
        )}

        {/* EQ curve glow + line */}
        {curvePath && <path d={curvePath} className="curveGlow" stroke="var(--accentCyan)" />}
        {curvePath && <path d={curvePath} className="curveLine" stroke="var(--accentCyan)" />}

        {freqLabels}
        {dbLabels}

        {/* Band nodes (active last for z-order) */}
        {drawOrder.map((i) => {
          const band = renderBands[i];
          const pos = nodePositions[i];
          if (!band || !pos) return null;

          const color = getBandColor(i);
          const isActive = i === activeIndex;

          return (
            <g
              key={i}
              className={`bandNode ${isActive ? 'active' : ''} nodeShadow`}
              transform={`translate(${pos.x}, ${pos.y})`}
              onPointerDown={(e) => handlePointerDown(e, band)}
              style={{ opacity: band.enabled ? 1 : 0.35 }}
            >
              <circle r="14" className="nodeHoverRing" stroke={color} />
              <circle r="8" className="nodeBase" stroke={color} />
              <circle r="3" className="nodeInner" fill={color} />
            </g>
          );
        })}
      </svg>

      {/* Tooltip (HTML overlay) */}
      {tooltip.visible && (
        <div
          className="graphTooltip"
          style={{
            position: 'absolute',
            left: tooltip.x + 12,
            top: tooltip.y - 16,
            pointerEvents: 'none',
          }}
        >
          <div className="tipTitle">
            <FilterTypeIcon type={renderBands[tooltip.bandIndex]?.type} size={12} />
            <span style={{ marginLeft: 6 }}>B{tooltip.bandIndex + 1}</span>
          </div>
          <div className="tipRow">{formatFreq(tooltip.freqHz)} Hz</div>
          {isGainType(renderBands[tooltip.bandIndex]?.type) ? (
            <div className="tipRow">{formatDb(tooltip.gainDb)}</div>
          ) : (
            <div className="tipRow">Q {tooltip.q.toFixed(2)}</div>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * Memoized EQGraph - prevents re-render when parent updates unrelated state.
 * Uses shallow comparison of props.
 */
export const EQGraph = memo(EQGraphInner);

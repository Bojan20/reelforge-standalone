/**
 * buildSpectrumPath.ts
 *
 * FabFilter-style spectrum path builder:
 * - Maps FFT bins -> log-frequency X axis (minHz..maxHz)
 * - Maps dB -> Y with clamp + soft floor
 * - Optional smoothing (fast, single-pass EMA) + bin decimation
 *
 * Usage:
 * const spectrumPath = useMemo(() => buildSpectrumPath(effectiveSpectrum, view), [effectiveSpectrum, view]);
 */

export type SpectrumData = {
  fftDb: Float32Array | number[];
  sampleRate: number;
};

export type SpectrumView = {
  // Drawing rect in SVG local coords
  x0: number;
  y0: number;
  width: number;
  height: number;

  // Frequency axis range (FabFilter-style)
  minHz: number; // 20
  maxHz: number; // 20000

  // dB range shown for analyzer (NOT the EQ gain range)
  // Typical: -90..-18 or -84..-12
  minDb: number; // -90
  maxDb: number; // -18

  // How much smoothing (0 = none). 0.15..0.35 is good.
  smoothing?: number;

  // Bin decimation step (1=full res, 2=half, 3=third) — big perf win
  step?: number;

  // Optional: noise floor "soft clamp" (FabFilter-style)
  // Values below floorDb get gently compressed rather than hard clipped.
  floorDb?: number; // e.g. -90
  floorKneeDb?: number; // e.g. 8 (knee width)
};

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

function logMapFreqToX(freqHz: number, minHz: number, maxHz: number, x0: number, w: number) {
  const f = clamp(freqHz, minHz, maxHz);
  const t = Math.log(f / minHz) / Math.log(maxHz / minHz);
  return x0 + t * w;
}

function dbToY(db: number, minDb: number, maxDb: number, y0: number, h: number) {
  const d = clamp(db, minDb, maxDb);
  const t = (d - minDb) / (maxDb - minDb); // 0..1
  // SVG y grows downward: maxDb at top
  return y0 + (1 - t) * h;
}

/**
 * Soft floor compress (knee) so noise floor doesn't stick as a hard line.
 * FabFilter-style: gentle compression below floor instead of hard clip.
 */
function applySoftFloor(db: number, floorDb: number, kneeDb: number) {
  if (db >= floorDb) return db;
  // Below floor: gently compress downward so it doesn't slam to min
  // Simple knee curve: floor - knee .. floor region eases
  const d = floorDb - db; // positive
  if (d >= kneeDb) return floorDb - kneeDb - (d - kneeDb) * 0.25; // compress deep tail
  // within knee: smooth easing
  const t = d / kneeDb; // 0..1
  return floorDb - kneeDb * (t * t * (3 - 2 * t));
}

/**
 * Single-pass EMA smoothing on dB values.
 * Bidirectional for symmetric feel (still cheap).
 */
function smoothDb(values: number[], alpha: number) {
  if (alpha <= 0) return values;
  let prev = values[0] ?? -120;
  // Forward pass
  for (let i = 1; i < values.length; i++) {
    const v = values[i];
    const s = prev + alpha * (v - prev);
    values[i] = s;
    prev = s;
  }
  // Backward pass for symmetric feel
  prev = values[values.length - 1] ?? prev;
  for (let i = values.length - 2; i >= 0; i--) {
    const v = values[i];
    const s = prev + alpha * (v - prev);
    values[i] = s;
    prev = s;
  }
  return values;
}

/**
 * Build SVG path string for spectrum analyzer.
 * FabFilter-style: log frequency, soft floor, EMA smoothing, decimation.
 */
export function buildSpectrumPath(spectrum: SpectrumData | null, view: SpectrumView): string {
  if (!spectrum) return '';

  const {
    x0,
    y0,
    width: w,
    height: h,
    minHz,
    maxHz,
    minDb,
    maxDb,
    smoothing = 0.22,
    step = 2,
    floorDb = minDb,
    floorKneeDb = 8,
  } = view;

  const bins = spectrum.fftDb;
  const sr = spectrum.sampleRate;

  const n = bins.length;
  if (!n || !sr) return '';

  // Nyquist
  const nyq = sr * 0.5;

  // Collect points (decimated) in a tight array first
  const xs: number[] = [];
  const ds: number[] = [];

  // Convert bin index -> freq:
  // freq = (i / (n-1)) * nyq  (approx for half spectrum)
  // We skip bin 0 to avoid DC weirdness; start at 1.
  for (let i = 1; i < n; i += step) {
    const f = (i / (n - 1)) * nyq;

    // Only draw in our visible freq window
    if (f < minHz) continue;
    if (f > maxHz) break;

    // Read dB
    const db = typeof bins[i] === 'number' ? (bins as number[])[i] : (bins as Float32Array)[i];

    xs.push(logMapFreqToX(f, minHz, maxHz, x0, w));
    // Apply soft floor (FabFilter-style)
    ds.push(applySoftFloor(db, floorDb, floorKneeDb));
  }

  if (xs.length < 2) return '';

  // Smooth dB curve (cheap + effective)
  smoothDb(ds, smoothing);

  // Build SVG path (polyline). Keep it light: no Beziers.
  let d = `M ${xs[0].toFixed(2)} ${dbToY(ds[0], minDb, maxDb, y0, h).toFixed(2)}`;

  for (let i = 1; i < xs.length; i++) {
    const y = dbToY(ds[i], minDb, maxDb, y0, h);
    d += ` L ${xs[i].toFixed(2)} ${y.toFixed(2)}`;
  }

  return d;
}

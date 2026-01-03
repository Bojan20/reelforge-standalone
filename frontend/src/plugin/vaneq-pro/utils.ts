export type BandType =
  | 'bell'
  | 'lowShelf'
  | 'highShelf'
  | 'lowPass'
  | 'highPass'
  | 'notch'
  | 'bandPass'
  | 'tilt';

export type Band = {
  index: number;
  enabled: boolean;
  type: BandType;
  freqHz: number;
  gainDb: number;
  q: number;
};

export type GraphBounds = { left: number; top: number; width: number; height: number };

export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));

export function dbToY(db: number, bounds: GraphBounds, dbMin = -24, dbMax = 24) {
  const t = (db - dbMax) / (dbMin - dbMax);
  return bounds.top + t * bounds.height;
}

export function yToDb(y: number, bounds: GraphBounds, dbMin = -24, dbMax = 24) {
  const t = (y - bounds.top) / bounds.height;
  return dbMax + t * (dbMin - dbMax);
}

export function freqToX(freqHz: number, bounds: GraphBounds, fMin = 20, fMax = 20000) {
  const clamped = clamp(freqHz, fMin, fMax);
  const logMin = Math.log10(fMin);
  const logMax = Math.log10(fMax);
  const t = (Math.log10(clamped) - logMin) / (logMax - logMin);
  return bounds.left + t * bounds.width;
}

export function xToFreq(x: number, bounds: GraphBounds, fMin = 20, fMax = 20000) {
  const t = clamp((x - bounds.left) / bounds.width, 0, 1);
  const logMin = Math.log10(fMin);
  const logMax = Math.log10(fMax);
  const logF = logMin + t * (logMax - logMin);
  return Math.pow(10, logF);
}

export function formatFreq(freqHz: number) {
  if (freqHz >= 1000) return `${(freqHz / 1000).toFixed(2)}k`;
  return `${Math.round(freqHz)}`;
}

export function formatDb(db: number) {
  const s = db >= 0 ? '+' : '';
  return `${s}${db.toFixed(1)} dB`;
}

export function bandColor(index: number) {
  const colors = ['var(--ve-red)', 'var(--ve-orange)', 'var(--ve-yellow)', 'var(--ve-cyan)', 'var(--ve-blue)', 'var(--ve-purple)', 'var(--ve-green)', 'var(--ve-blue)'];
  return colors[index % colors.length];
}

const NUM_TO_BAND_TYPE: BandType[] = [
  'bell', 'lowShelf', 'highShelf', 'lowPass', 'highPass', 'notch', 'bandPass', 'tilt'
];

// VERSION: 2024-12-22-v2 - implicit enable fix applied
export function getBandFromParams(params: Record<string, any>, index: number): Band {
  const p = params || {};

  // Type can be stored as number (0-7) or string ('bell', etc.)
  const rawType = p[`band${index}_type`];
  let bandType: BandType = 'bell';
  if (typeof rawType === 'number') {
    bandType = NUM_TO_BAND_TYPE[rawType] ?? 'bell';
  } else if (typeof rawType === 'string' && NUM_TO_BAND_TYPE.includes(rawType as BandType)) {
    bandType = rawType as BandType;
  }

  const gainDb = Number(p[`band${index}_gainDb`] ?? 0);
  const rawEnabled = p[`band${index}_enabled`];
  const explicitEnabled = rawEnabled === 1 || rawEnabled === true;

  // IMPLICIT ENABLE logic:
  // 1. If explicitly enabled (enabled=1), the band is enabled
  // 2. If gain is non-zero, the band is implicitly enabled (for bell/shelf filters)
  // This matches the defensive fallback in vaneqTypes.ts unflattenVanEqParams
  // Ensures UI visualization matches DSP behavior
  const enabled = explicitEnabled || gainDb !== 0;

  // NOTE: Implicit enable - removed debug logging to prevent console spam
  // When gainDb !== 0 && !explicitEnabled, the band is implicitly enabled

  return {
    index,
    enabled,
    type: bandType,
    freqHz: Number(p[`band${index}_freqHz`] ?? 1000),
    gainDb,
    q: Number(p[`band${index}_q`] ?? 1),
  };
}

export function setBandToBatch(index: number, b: Partial<Band>) {
  const out: { paramId: string; value: any }[] = [];
  if (b.enabled !== undefined) out.push({ paramId: `band${index}_enabled`, value: b.enabled ? 1 : 0 });
  if (b.type !== undefined) out.push({ paramId: `band${index}_type`, value: b.type });
  if (b.freqHz !== undefined) out.push({ paramId: `band${index}_freqHz`, value: b.freqHz });
  if (b.gainDb !== undefined) out.push({ paramId: `band${index}_gainDb`, value: b.gainDb });
  if (b.q !== undefined) out.push({ paramId: `band${index}_q`, value: b.q });
  return out;
}

/** Map-based version for VanEQProEditor */
export function setBandToBatchRecord(index: number, b: Partial<Band>): Record<string, number> {
  const out: Record<string, number> = {};
  if (b.enabled !== undefined) out[`band${index}_enabled`] = b.enabled ? 1 : 0;
  if (b.type !== undefined) out[`band${index}_type`] = BAND_TYPE_TO_NUM[b.type] ?? 0;
  if (b.freqHz !== undefined) out[`band${index}_freqHz`] = b.freqHz;
  if (b.gainDb !== undefined) out[`band${index}_gainDb`] = b.gainDb;
  if (b.q !== undefined) out[`band${index}_q`] = b.q;
  return out;
}

const BAND_TYPE_TO_NUM: Record<BandType, number> = {
  bell: 0,
  lowShelf: 1,
  highShelf: 2,
  lowPass: 3,
  highPass: 4,
  notch: 5,
  bandPass: 6,
  tilt: 7,
};

export function buildGridPath(bounds: GraphBounds) {
  const lines: string[] = [];
  const xCount = 12;
  for (let i = 0; i <= xCount; i++) {
    const x = bounds.left + (i / xCount) * bounds.width;
    lines.push(`M ${x} ${bounds.top} L ${x} ${bounds.top + bounds.height}`);
  }
  const yCount = 8;
  for (let i = 0; i <= yCount; i++) {
    const y = bounds.top + (i / yCount) * bounds.height;
    lines.push(`M ${bounds.left} ${y} L ${bounds.left + bounds.width} ${y}`);
  }
  return lines.join(' ');
}

/**
 * Visual-only response curve. Not DSP.
 * Produces a pleasant bell-ish shape so UI always looks alive.
 * Actual DSP happens in worklet.
 */
export function buildResponseCurvePath(bounds: GraphBounds, bands: Band[]) {
  const pts: { x: number; y: number }[] = [];
  const n = 200;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const freq = 20 * Math.pow(20000 / 20, t);
    let db = 0;
    for (const b of bands) {
      if (!b.enabled) continue;
      const r = Math.log(freq / b.freqHz);
      const shape = Math.exp(-0.5 * (r * r) * (b.q * 0.9));
      const sign = b.type === 'notch' ? -1 : 1;
      const gain = b.type === 'lowPass' || b.type === 'highPass' ? (b.gainDb >= 0 ? 0 : b.gainDb) : b.gainDb;
      db += sign * gain * shape;
    }
    db = clamp(db, -24, 24);
    const x = freqToX(freq, bounds);
    const y = dbToY(db, bounds);
    pts.push({ x, y });
  }
  let d = '';
  for (let i = 0; i < pts.length; i++) {
    d += `${i === 0 ? 'M' : 'L'} ${pts[i].x} ${pts[i].y} `;
  }
  return d.trim();
}

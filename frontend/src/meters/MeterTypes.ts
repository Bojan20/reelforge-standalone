/**
 * ReelForge Meter Types
 *
 * Professional meter standards and configurations.
 *
 * @module meters/MeterTypes
 */

// ============ Meter Standards ============

export type MeterStandard =
  | 'peak'      // Digital peak meter
  | 'vu'        // VU meter (300ms integration)
  | 'ppm-ebu'   // PPM Type I (EBU)
  | 'ppm-din'   // PPM Type IIa (DIN)
  | 'ppm-bbc'   // PPM Type II (BBC)
  | 'ppm-nordic'// PPM Nordic
  | 'k-12'      // K-System K-12
  | 'k-14'      // K-System K-14
  | 'k-20'      // K-System K-20
  | 'lufs-m'    // LUFS Momentary
  | 'lufs-s'    // LUFS Short-term
  | 'lufs-i'    // LUFS Integrated
  | 'true-peak' // True Peak (ITU-R BS.1770-4)
;

// ============ Meter Configuration ============

export interface MeterConfig {
  /** Meter standard */
  standard: MeterStandard;
  /** Display name */
  name: string;
  /** Reference level (0dB point in dBFS) */
  refLevel: number;
  /** Scale minimum (dB) */
  scaleMin: number;
  /** Scale maximum (dB) */
  scaleMax: number;
  /** Tick marks */
  ticks: number[];
  /** Major tick marks */
  majorTicks: number[];
  /** Attack time (ms) */
  attackMs: number;
  /** Release time (ms) */
  releaseMs: number;
  /** Peak hold time (ms), 0 for no hold */
  peakHoldMs: number;
  /** Integration time (ms) for RMS meters */
  integrationMs: number;
  /** Color zones */
  zones: MeterZone[];
  /** Show peak indicator */
  showPeak: boolean;
  /** Show RMS/average */
  showRMS: boolean;
}

export interface MeterZone {
  /** Start level (dB) */
  start: number;
  /** End level (dB) */
  end: number;
  /** Color (hex) */
  color: number;
  /** Label (optional) */
  label?: string;
}

// ============ Preset Configurations ============

export const METER_PRESETS: Record<MeterStandard, MeterConfig> = {
  peak: {
    standard: 'peak',
    name: 'Peak',
    refLevel: 0,
    scaleMin: -60,
    scaleMax: 6,
    ticks: [-60, -48, -36, -24, -18, -12, -9, -6, -3, 0, 3, 6],
    majorTicks: [-48, -24, -12, -6, 0],
    attackMs: 0,
    releaseMs: 1500,
    peakHoldMs: 2000,
    integrationMs: 0,
    zones: [
      { start: -60, end: -18, color: 0x00ff00 },
      { start: -18, end: -6, color: 0xffff00 },
      { start: -6, end: 0, color: 0xff8800 },
      { start: 0, end: 6, color: 0xff0000 },
    ],
    showPeak: true,
    showRMS: false,
  },

  vu: {
    standard: 'vu',
    name: 'VU',
    refLevel: -18, // 0 VU = -18 dBFS (typical calibration)
    scaleMin: -40,
    scaleMax: 6,
    ticks: [-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3],
    majorTicks: [-20, -10, -7, -3, 0, 3],
    attackMs: 300,
    releaseMs: 300,
    peakHoldMs: 0,
    integrationMs: 300,
    zones: [
      { start: -40, end: -3, color: 0x00aa00, label: 'Normal' },
      { start: -3, end: 3, color: 0xffcc00, label: '+3 VU' },
      { start: 3, end: 6, color: 0xff3300, label: 'Over' },
    ],
    showPeak: false,
    showRMS: true,
  },

  'ppm-ebu': {
    standard: 'ppm-ebu',
    name: 'PPM (EBU)',
    refLevel: -18, // Test tone = -18 dBFS
    scaleMin: -42,
    scaleMax: 6,
    ticks: [-42, -36, -30, -24, -18, -12, -6, -4, -2, 0, 2, 4, 6],
    majorTicks: [-36, -24, -12, 0],
    attackMs: 10,
    releaseMs: 1500, // 24 dB/s fallback
    peakHoldMs: 0,
    integrationMs: 10,
    zones: [
      { start: -42, end: -12, color: 0x00cc00 },
      { start: -12, end: -6, color: 0xcccc00 },
      { start: -6, end: 0, color: 0xff8800 },
      { start: 0, end: 6, color: 0xff0000 },
    ],
    showPeak: true,
    showRMS: false,
  },

  'ppm-din': {
    standard: 'ppm-din',
    name: 'PPM (DIN)',
    refLevel: -9, // 0 dB = -9 dBFS
    scaleMin: -50,
    scaleMax: 5,
    ticks: [-50, -40, -30, -20, -10, -5, 0, 5],
    majorTicks: [-50, -30, -10, 0],
    attackMs: 10,
    releaseMs: 1500,
    peakHoldMs: 0,
    integrationMs: 10,
    zones: [
      { start: -50, end: -10, color: 0x00cc00 },
      { start: -10, end: -5, color: 0xcccc00 },
      { start: -5, end: 0, color: 0xff8800 },
      { start: 0, end: 5, color: 0xff0000 },
    ],
    showPeak: true,
    showRMS: false,
  },

  'ppm-bbc': {
    standard: 'ppm-bbc',
    name: 'PPM (BBC)',
    refLevel: -18, // PPM 4 = -18 dBFS
    scaleMin: -24,
    scaleMax: 12,
    ticks: [1, 2, 3, 4, 5, 6, 7], // BBC PPM scale 1-7
    majorTicks: [1, 4, 6],
    attackMs: 10,
    releaseMs: 2800, // 8.7 dB/s fallback (2.8s to drop 24dB)
    peakHoldMs: 0,
    integrationMs: 10,
    zones: [
      { start: -24, end: -6, color: 0x00cc00 },
      { start: -6, end: 0, color: 0xcccc00 },
      { start: 0, end: 6, color: 0xff8800 },
      { start: 6, end: 12, color: 0xff0000 },
    ],
    showPeak: true,
    showRMS: false,
  },

  'ppm-nordic': {
    standard: 'ppm-nordic',
    name: 'PPM (Nordic)',
    refLevel: -18,
    scaleMin: -42,
    scaleMax: 9,
    ticks: [-42, -36, -30, -24, -18, -12, -9, -6, -3, 0, 3, 6, 9],
    majorTicks: [-36, -18, -9, 0, 9],
    attackMs: 5,
    releaseMs: 1700, // 20 dB/s
    peakHoldMs: 0,
    integrationMs: 5,
    zones: [
      { start: -42, end: -9, color: 0x00cc00 },
      { start: -9, end: 0, color: 0xcccc00 },
      { start: 0, end: 6, color: 0xff8800 },
      { start: 6, end: 9, color: 0xff0000 },
    ],
    showPeak: true,
    showRMS: false,
  },

  'k-12': {
    standard: 'k-12',
    name: 'K-12',
    refLevel: -12, // 0 dB = -12 dBFS
    scaleMin: -36,
    scaleMax: 12,
    ticks: [-36, -30, -24, -18, -12, -9, -6, -3, 0, 3, 6, 9, 12],
    majorTicks: [-24, -12, 0, 12],
    attackMs: 0,
    releaseMs: 1500,
    peakHoldMs: 2000,
    integrationMs: 300,
    zones: [
      { start: -36, end: -4, color: 0x00cc00, label: 'Normal' },
      { start: -4, end: 0, color: 0xcccc00, label: 'Loud' },
      { start: 0, end: 12, color: 0xff3300, label: 'Over' },
    ],
    showPeak: true,
    showRMS: true,
  },

  'k-14': {
    standard: 'k-14',
    name: 'K-14',
    refLevel: -14, // 0 dB = -14 dBFS
    scaleMin: -40,
    scaleMax: 14,
    ticks: [-40, -30, -20, -14, -10, -6, -4, 0, 4, 8, 14],
    majorTicks: [-30, -14, 0, 14],
    attackMs: 0,
    releaseMs: 1500,
    peakHoldMs: 2000,
    integrationMs: 300,
    zones: [
      { start: -40, end: -4, color: 0x00cc00, label: 'Normal' },
      { start: -4, end: 0, color: 0xcccc00, label: 'Loud' },
      { start: 0, end: 14, color: 0xff3300, label: 'Over' },
    ],
    showPeak: true,
    showRMS: true,
  },

  'k-20': {
    standard: 'k-20',
    name: 'K-20',
    refLevel: -20, // 0 dB = -20 dBFS
    scaleMin: -48,
    scaleMax: 20,
    ticks: [-48, -36, -24, -20, -12, -6, 0, 4, 8, 12, 20],
    majorTicks: [-36, -20, 0, 20],
    attackMs: 0,
    releaseMs: 1500,
    peakHoldMs: 2000,
    integrationMs: 300,
    zones: [
      { start: -48, end: -4, color: 0x00cc00, label: 'Normal' },
      { start: -4, end: 0, color: 0xcccc00, label: 'Loud' },
      { start: 0, end: 20, color: 0xff3300, label: 'Over' },
    ],
    showPeak: true,
    showRMS: true,
  },

  'lufs-m': {
    standard: 'lufs-m',
    name: 'LUFS (M)',
    refLevel: -23, // EBU R128 target
    scaleMin: -60,
    scaleMax: 0,
    ticks: [-60, -50, -40, -30, -23, -18, -14, -9, -5, 0],
    majorTicks: [-40, -23, -14, 0],
    attackMs: 400, // 400ms momentary window
    releaseMs: 400,
    peakHoldMs: 0,
    integrationMs: 400,
    zones: [
      { start: -60, end: -25, color: 0x00aa00 },
      { start: -25, end: -21, color: 0x00cc00, label: 'Target' },
      { start: -21, end: -14, color: 0xcccc00 },
      { start: -14, end: 0, color: 0xff3300 },
    ],
    showPeak: false,
    showRMS: true,
  },

  'lufs-s': {
    standard: 'lufs-s',
    name: 'LUFS (S)',
    refLevel: -23,
    scaleMin: -60,
    scaleMax: 0,
    ticks: [-60, -50, -40, -30, -23, -18, -14, -9, -5, 0],
    majorTicks: [-40, -23, -14, 0],
    attackMs: 3000, // 3s short-term window
    releaseMs: 3000,
    peakHoldMs: 0,
    integrationMs: 3000,
    zones: [
      { start: -60, end: -25, color: 0x00aa00 },
      { start: -25, end: -21, color: 0x00cc00, label: 'Target' },
      { start: -21, end: -14, color: 0xcccc00 },
      { start: -14, end: 0, color: 0xff3300 },
    ],
    showPeak: false,
    showRMS: true,
  },

  'lufs-i': {
    standard: 'lufs-i',
    name: 'LUFS (I)',
    refLevel: -23,
    scaleMin: -60,
    scaleMax: 0,
    ticks: [-60, -50, -40, -30, -23, -18, -14, -9, -5, 0],
    majorTicks: [-40, -23, -14, 0],
    attackMs: 0,
    releaseMs: 0,
    peakHoldMs: 0,
    integrationMs: 0, // Full program integration
    zones: [
      { start: -60, end: -25, color: 0x00aa00 },
      { start: -25, end: -21, color: 0x00cc00, label: 'Target' },
      { start: -21, end: -14, color: 0xcccc00 },
      { start: -14, end: 0, color: 0xff3300 },
    ],
    showPeak: false,
    showRMS: true,
  },

  'true-peak': {
    standard: 'true-peak',
    name: 'True Peak',
    refLevel: -1, // -1 dBTP typical ceiling
    scaleMin: -60,
    scaleMax: 3,
    ticks: [-60, -48, -36, -24, -18, -12, -6, -3, -1, 0, 3],
    majorTicks: [-48, -24, -12, -1, 0],
    attackMs: 0, // 4x oversampled peak
    releaseMs: 1500,
    peakHoldMs: 2000,
    integrationMs: 0,
    zones: [
      { start: -60, end: -6, color: 0x00cc00 },
      { start: -6, end: -1, color: 0xcccc00 },
      { start: -1, end: 0, color: 0xff8800, label: 'Clip' },
      { start: 0, end: 3, color: 0xff0000, label: 'ISP' },
    ],
    showPeak: true,
    showRMS: false,
  },
};

// ============ Utility Functions ============

export function getMeterConfig(standard: MeterStandard): MeterConfig {
  return METER_PRESETS[standard];
}

export function dbToNormalized(db: number, config: MeterConfig): number {
  const range = config.scaleMax - config.scaleMin;
  return Math.max(0, Math.min(1, (db - config.scaleMin) / range));
}

export function normalizedToDb(normalized: number, config: MeterConfig): number {
  const range = config.scaleMax - config.scaleMin;
  return config.scaleMin + normalized * range;
}

export function getZoneColor(db: number, config: MeterConfig): number {
  for (const zone of config.zones) {
    if (db >= zone.start && db < zone.end) {
      return zone.color;
    }
  }
  return config.zones[config.zones.length - 1]?.color ?? 0xffffff;
}

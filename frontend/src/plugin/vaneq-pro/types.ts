/**
 * ReelForge VanEQ Pro Types
 *
 * Extended types for the Pro-Q style editor.
 *
 * @module plugin/vaneq-pro/types
 */

import type { VanEqBandType } from '../vaneqTypes';

/**
 * Band data for the EQ graph.
 */
export interface BandData {
  index: number;
  enabled: boolean;
  type: VanEqBandType;
  freqHz: number;
  gainDb: number;
  q: number;
}

/**
 * Point on the frequency response curve.
 */
export interface CurvePoint {
  freq: number;
  gain: number;
  x: number;
  y: number;
}

/**
 * A/B state snapshot for comparison.
 */
export interface ABSnapshot {
  params: Record<string, number>;
  label: 'A' | 'B';
}

/**
 * Undo/redo history entry.
 */
export interface HistoryEntry {
  params: Record<string, number>;
  timestamp: number;
  description?: string;
}

/**
 * Band type display info.
 */
export interface BandTypeInfo {
  type: VanEqBandType;
  label: string;
  shortLabel: string;
  icon: string;
  hasGain: boolean;
  hasQ: boolean;
}

/**
 * Band type configuration.
 * Icons will be replaced by SVG components in FilterTypeIcon.tsx
 */
export const BAND_TYPE_INFO: Record<VanEqBandType, BandTypeInfo> = {
  bell: {
    type: 'bell',
    label: 'Bell',
    shortLabel: 'Bell',
    icon: '∿',
    hasGain: true,
    hasQ: true,
  },
  lowShelf: {
    type: 'lowShelf',
    label: 'Low Shelf',
    shortLabel: 'LS',
    icon: '⌊',
    hasGain: true,
    hasQ: true,
  },
  highShelf: {
    type: 'highShelf',
    label: 'High Shelf',
    shortLabel: 'HS',
    icon: '⌉',
    hasGain: true,
    hasQ: true,
  },
  lowPass: {
    type: 'lowPass',
    label: 'Low Pass',
    shortLabel: 'LP',
    icon: '╲',
    hasGain: false,
    hasQ: true,
  },
  highPass: {
    type: 'highPass',
    label: 'High Pass',
    shortLabel: 'HP',
    icon: '╱',
    hasGain: false,
    hasQ: true,
  },
  notch: {
    type: 'notch',
    label: 'Notch',
    shortLabel: 'N',
    icon: '∨',
    hasGain: false,
    hasQ: true,
  },
  bandPass: {
    type: 'bandPass',
    label: 'Band Pass',
    shortLabel: 'BP',
    icon: '⋂',
    hasGain: false,
    hasQ: true,
  },
  tilt: {
    type: 'tilt',
    label: 'Tilt',
    shortLabel: 'Tilt',
    icon: '⟋',
    hasGain: true,
    hasQ: false,
  },
};

/**
 * Slope options for cut filters.
 */
export type FilterSlope = 6 | 12 | 18 | 24 | 36 | 48;

export const FILTER_SLOPES: FilterSlope[] = [6, 12, 18, 24, 36, 48];

/**
 * Graph constants.
 */
export const GRAPH_CONSTANTS = {
  // Frequency axis (Hz, logarithmic)
  FREQ_MIN: 20,
  FREQ_MAX: 20000,

  // Gain axis (dB, linear)
  GAIN_MIN: -24,
  GAIN_MAX: 24,

  // Q range
  Q_MIN: 0.1,
  Q_MAX: 24,

  // Grid frequencies (Hz)
  GRID_FREQS: [30, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000],

  // Grid gains (dB)
  GRID_GAINS: [-24, -18, -12, -6, 0, 6, 12, 18, 24],

  // Curve resolution (points)
  CURVE_POINTS: 256,
} as const;

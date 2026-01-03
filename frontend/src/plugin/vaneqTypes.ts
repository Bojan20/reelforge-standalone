/**
 * ReelForge M9.2 VanEQ Types
 *
 * Type definitions for the VanEQ Pro parametric equalizer.
 * 6-band EQ with professional filter types.
 *
 * @module plugin/vaneqTypes
 */

/**
 * VanEQ band filter types.
 *
 * Core types: bell, lowShelf, highShelf, lowPass, highPass, notch
 * Extended types: bandPass, tilt (optional)
 */
export type VanEqBandType =
  | 'bell'
  | 'lowShelf'
  | 'highShelf'
  | 'lowPass'
  | 'highPass'
  | 'notch'
  | 'bandPass'
  | 'tilt';

/**
 * Valid band types array for validation.
 * Order matters for numeric mapping to DSP.
 */
export const VALID_VANEQ_BAND_TYPES: VanEqBandType[] = [
  'bell',       // 0 - peaking
  'lowShelf',   // 1 - lowshelf
  'highShelf',  // 2 - highshelf
  'lowPass',    // 3 - lowpass
  'highPass',   // 4 - highpass
  'notch',      // 5 - notch
  'bandPass',   // 6 - bandpass
  'tilt',       // 7 - tilt shelf (custom)
];

/**
 * Map filter type to Web Audio BiquadFilterType.
 * 'tilt' requires special handling (not a standard biquad).
 */
export const BAND_TYPE_TO_BIQUAD: Record<VanEqBandType, BiquadFilterType | 'tilt'> = {
  bell: 'peaking',
  lowShelf: 'lowshelf',
  highShelf: 'highshelf',
  lowPass: 'lowpass',
  highPass: 'highpass',
  notch: 'notch',
  bandPass: 'bandpass',
  tilt: 'tilt', // Custom implementation needed
};

/**
 * VanEQ single band configuration.
 */
export interface VanEqBand {
  /** Whether this band is active */
  enabled: boolean;
  /** Filter type */
  type: VanEqBandType;
  /** Center/corner frequency in Hz */
  freqHz: number;
  /** Gain in dB (ignored for cut/notch types) */
  gainDb: number;
  /** Q factor (bandwidth) */
  q: number;
}

/**
 * VanEQ plugin parameters.
 */
export interface VanEqParams {
  /** Output gain in dB */
  outputGainDb: number;
  /** 8 EQ bands */
  bands: [VanEqBand, VanEqBand, VanEqBand, VanEqBand, VanEqBand, VanEqBand, VanEqBand, VanEqBand];
}

/**
 * VanEQ parameter constraints.
 */
export const VANEQ_CONSTRAINTS = {
  outputGainDb: { min: -24, max: 24 },
  freqHz: { min: 20, max: 20000 },
  gainDb: { min: -24, max: 24 },
  q: { min: 0.1, max: 24 },
  bandCount: 8,
} as const;

/**
 * Default band configuration for each band index.
 *
 * SILENCE GUARANTEE: All bands disabled by default = unity gain passthrough.
 * Users must explicitly enable bands to apply EQ.
 */
export const DEFAULT_VANEQ_BANDS: VanEqParams['bands'] = [
  { enabled: false, type: 'highPass', freqHz: 30, gainDb: 0, q: 0.707 },
  { enabled: false, type: 'lowShelf', freqHz: 120, gainDb: 0, q: 0.707 },
  { enabled: false, type: 'bell', freqHz: 400, gainDb: 0, q: 1 },
  { enabled: false, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
  { enabled: false, type: 'bell', freqHz: 2500, gainDb: 0, q: 1 },
  { enabled: false, type: 'bell', freqHz: 6000, gainDb: 0, q: 1 },
  { enabled: false, type: 'highShelf', freqHz: 12000, gainDb: 0, q: 0.707 },
  { enabled: false, type: 'lowPass', freqHz: 18000, gainDb: 0, q: 0.707 },
];

/**
 * Default VanEQ parameters.
 */
export const DEFAULT_VANEQ_PARAMS: VanEqParams = {
  outputGainDb: 0,
  bands: structuredClone(DEFAULT_VANEQ_BANDS),
};

/**
 * Flatten VanEQ params to a flat Record<string, number> for framework compatibility.
 */
export function flattenVanEqParams(params: VanEqParams): Record<string, number> {
  const flat: Record<string, number> = {
    outputGainDb: params.outputGainDb,
  };

  params.bands.forEach((band, i) => {
    flat[`band${i}_enabled`] = band.enabled ? 1 : 0;
    flat[`band${i}_type`] = VALID_VANEQ_BAND_TYPES.indexOf(band.type);
    flat[`band${i}_freqHz`] = band.freqHz;
    flat[`band${i}_gainDb`] = band.gainDb;
    flat[`band${i}_q`] = band.q;
  });

  return flat;
}

/**
 * Unflatten params from flat Record<string, number | string> back to VanEqParams.
 * Note: type can be either a number index or a string type name.
 */
export function unflattenVanEqParams(flat: Record<string, number | string>): VanEqParams {
  // Deep clone to avoid mutating DEFAULT_VANEQ_BANDS
  const bands = DEFAULT_VANEQ_BANDS.map(b => ({ ...b })) as VanEqParams['bands'];

  // NOTE: Debug logging removed to prevent console spam

  for (let i = 0; i < 8; i++) {
    const enabledKey = `band${i}_enabled`;
    const typeKey = `band${i}_type`;
    const freqKey = `band${i}_freqHz`;
    const gainKey = `band${i}_gainDb`;
    const qKey = `band${i}_q`;

    // Check if any band params exist for this index
    const hasAnyParam = enabledKey in flat || freqKey in flat || gainKey in flat || qKey in flat || typeKey in flat;

    if (hasAnyParam) {
      // Read the gain value (needed for defensive fallback)
      const gainDb = gainKey in flat ? Number(flat[gainKey]) : bands[i].gainDb;

      // If enabled is explicitly set, use it; otherwise default to false (disabled)
      // Handle both number (1/0) and string ('1'/'0')
      let enabled = bands[i].enabled;
      if (enabledKey in flat) {
        const rawEnabled = flat[enabledKey];
        enabled = rawEnabled === 1 || rawEnabled === '1';
      }

      // DEFENSIVE FALLBACK: If gainDb !== 0, implicitly enable the band
      // This is a safety net in case the UI's implicit enable fails to reach DSP
      if (!enabled && gainDb !== 0) {
        // NOTE: Debug logging removed - band auto-enabled silently
        enabled = true;
      }

      // Handle type: can be number index or string type name
      let bandType: VanEqBandType = bands[i].type;
      if (typeKey in flat) {
        const rawType = flat[typeKey];
        if (typeof rawType === 'number') {
          // Numeric index into VALID_VANEQ_BAND_TYPES
          bandType = VALID_VANEQ_BAND_TYPES[rawType] || 'bell';
        } else if (typeof rawType === 'string') {
          // String type name - validate it exists in the array
          bandType = VALID_VANEQ_BAND_TYPES.includes(rawType as VanEqBandType)
            ? (rawType as VanEqBandType)
            : 'bell';
        }
      }

      bands[i] = {
        enabled,
        type: bandType,
        freqHz: freqKey in flat ? Number(flat[freqKey]) : bands[i].freqHz,
        gainDb,
        q: qKey in flat ? Number(flat[qKey]) : bands[i].q,
      };
    }
  }

  return {
    outputGainDb: Number(flat.outputGainDb ?? 0),
    bands,
  };
}

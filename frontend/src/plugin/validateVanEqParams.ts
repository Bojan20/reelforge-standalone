/**
 * ReelForge M9.2 VanEQ Validation
 *
 * Strict validation for VanEQ parameters.
 * Hard-fail on invalid config (RF_ERR style).
 *
 * @module plugin/validateVanEqParams
 */

import {
  type VanEqParams,
  type VanEqBand,
  VANEQ_CONSTRAINTS,
  VALID_VANEQ_BAND_TYPES,
  DEFAULT_VANEQ_PARAMS,
} from './vaneqTypes';

export interface VanEqValidationError {
  type: 'error';
  message: string;
  field?: string;
}

export interface VanEqValidationResult {
  valid: boolean;
  errors: VanEqValidationError[];
}

/**
 * Validate VanEQ parameters.
 * Returns errors array - empty means valid.
 * Hard-fail on any invalid values (no silent clamping).
 */
export function validateVanEqParams(params: unknown): VanEqValidationResult {
  const errors: VanEqValidationError[] = [];

  if (!params || typeof params !== 'object') {
    errors.push({
      type: 'error',
      message: 'VanEQ params must be an object',
    });
    return { valid: false, errors };
  }

  const p = params as Record<string, unknown>;
  const c = VANEQ_CONSTRAINTS;

  // Validate outputGainDb
  if (typeof p.outputGainDb !== 'number') {
    errors.push({
      type: 'error',
      message: 'outputGainDb must be a number',
      field: 'outputGainDb',
    });
  } else if (Number.isNaN(p.outputGainDb) || !Number.isFinite(p.outputGainDb)) {
    errors.push({
      type: 'error',
      message: 'outputGainDb must be a finite number (no NaN/Infinity)',
      field: 'outputGainDb',
    });
  } else if (p.outputGainDb < c.outputGainDb.min || p.outputGainDb > c.outputGainDb.max) {
    errors.push({
      type: 'error',
      message: `outputGainDb must be ${c.outputGainDb.min} to ${c.outputGainDb.max}`,
      field: 'outputGainDb',
    });
  }

  // Validate bands array
  if (!Array.isArray(p.bands)) {
    errors.push({
      type: 'error',
      message: 'bands must be an array',
      field: 'bands',
    });
    return { valid: false, errors };
  }

  if (p.bands.length !== c.bandCount) {
    errors.push({
      type: 'error',
      message: `bands must have exactly ${c.bandCount} elements`,
      field: 'bands',
    });
    return { valid: false, errors };
  }

  // Validate each band
  p.bands.forEach((band, i) => {
    const bandErrors = validateBand(band, i);
    errors.push(...bandErrors);
  });

  return {
    valid: errors.length === 0,
    errors,
  };
}

function validateBand(band: unknown, index: number): VanEqValidationError[] {
  const errors: VanEqValidationError[] = [];
  const prefix = `bands[${index}]`;
  const c = VANEQ_CONSTRAINTS;

  if (!band || typeof band !== 'object') {
    errors.push({
      type: 'error',
      message: `${prefix} must be an object`,
      field: prefix,
    });
    return errors;
  }

  const b = band as Record<string, unknown>;

  // Validate enabled
  if (typeof b.enabled !== 'boolean') {
    errors.push({
      type: 'error',
      message: `${prefix}.enabled must be a boolean`,
      field: `${prefix}.enabled`,
    });
  }

  // Validate type
  if (!(VALID_VANEQ_BAND_TYPES as readonly string[]).includes(b.type as string)) {
    errors.push({
      type: 'error',
      message: `${prefix}.type must be one of: ${VALID_VANEQ_BAND_TYPES.join(', ')}`,
      field: `${prefix}.type`,
    });
  }

  // Validate freqHz
  if (typeof b.freqHz !== 'number') {
    errors.push({
      type: 'error',
      message: `${prefix}.freqHz must be a number`,
      field: `${prefix}.freqHz`,
    });
  } else if (Number.isNaN(b.freqHz) || !Number.isFinite(b.freqHz)) {
    errors.push({
      type: 'error',
      message: `${prefix}.freqHz must be a finite number`,
      field: `${prefix}.freqHz`,
    });
  } else if (b.freqHz < c.freqHz.min || b.freqHz > c.freqHz.max) {
    errors.push({
      type: 'error',
      message: `${prefix}.freqHz must be ${c.freqHz.min} to ${c.freqHz.max}`,
      field: `${prefix}.freqHz`,
    });
  }

  // Validate gainDb
  if (typeof b.gainDb !== 'number') {
    errors.push({
      type: 'error',
      message: `${prefix}.gainDb must be a number`,
      field: `${prefix}.gainDb`,
    });
  } else if (Number.isNaN(b.gainDb) || !Number.isFinite(b.gainDb)) {
    errors.push({
      type: 'error',
      message: `${prefix}.gainDb must be a finite number`,
      field: `${prefix}.gainDb`,
    });
  } else if (b.gainDb < c.gainDb.min || b.gainDb > c.gainDb.max) {
    errors.push({
      type: 'error',
      message: `${prefix}.gainDb must be ${c.gainDb.min} to ${c.gainDb.max}`,
      field: `${prefix}.gainDb`,
    });
  }

  // Validate q
  if (typeof b.q !== 'number') {
    errors.push({
      type: 'error',
      message: `${prefix}.q must be a number`,
      field: `${prefix}.q`,
    });
  } else if (Number.isNaN(b.q) || !Number.isFinite(b.q)) {
    errors.push({
      type: 'error',
      message: `${prefix}.q must be a finite number`,
      field: `${prefix}.q`,
    });
  } else if (b.q < c.q.min || b.q > c.q.max) {
    errors.push({
      type: 'error',
      message: `${prefix}.q must be ${c.q.min} to ${c.q.max}`,
      field: `${prefix}.q`,
    });
  }

  return errors;
}

/**
 * Clamp a VanEQ band's values to valid ranges.
 * Used during UI interaction, NOT during load.
 */
export function clampVanEqBand(band: VanEqBand): VanEqBand {
  const c = VANEQ_CONSTRAINTS;
  return {
    enabled: band.enabled,
    type: VALID_VANEQ_BAND_TYPES.includes(band.type) ? band.type : 'bell',
    freqHz: Math.max(c.freqHz.min, Math.min(c.freqHz.max, band.freqHz)),
    gainDb: Math.max(c.gainDb.min, Math.min(c.gainDb.max, band.gainDb)),
    q: Math.max(c.q.min, Math.min(c.q.max, band.q)),
  };
}

/**
 * Clamp VanEQ params to valid ranges.
 * Used during UI interaction, NOT during load.
 */
export function clampVanEqParams(params: VanEqParams): VanEqParams {
  const c = VANEQ_CONSTRAINTS;
  return {
    outputGainDb: Math.max(c.outputGainDb.min, Math.min(c.outputGainDb.max, params.outputGainDb)),
    bands: params.bands.map(clampVanEqBand) as VanEqParams['bands'],
  };
}

/**
 * Get default VanEQ params (deep clone).
 */
export function getDefaultVanEqParams(): VanEqParams {
  return structuredClone(DEFAULT_VANEQ_PARAMS);
}

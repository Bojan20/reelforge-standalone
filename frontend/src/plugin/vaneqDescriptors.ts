/**
 * ReelForge M9.2 VanEQ Parameter Descriptors
 *
 * ParamDescriptor definitions for the VanEQ 6-band parametric equalizer.
 * Used for auto-UI generation and parameter validation.
 *
 * @module plugin/vaneqDescriptors
 */

import type { ParamDescriptor } from './ParamDescriptor';
import { VANEQ_CONSTRAINTS, VALID_VANEQ_BAND_TYPES, DEFAULT_VANEQ_BANDS } from './vaneqTypes';

// ============ Shared Descriptors ============

/**
 * Band enabled state descriptor.
 * Stored as 0/1 for flat param compatibility.
 */
const bandEnabledDescriptor: ParamDescriptor = {
  id: 'enabled',
  name: 'Enabled',
  shortName: 'On',
  unit: '',
  min: 0,
  max: 1,
  default: 0,
  step: 1,
  fineStep: 1,
  scale: 'linear',
  description: 'Enable or disable this band',
};

/**
 * Band type descriptor.
 * Stored as index into VALID_VANEQ_BAND_TYPES array.
 */
const bandTypeDescriptor: ParamDescriptor = {
  id: 'type',
  name: 'Type',
  unit: '',
  min: 0,
  max: VALID_VANEQ_BAND_TYPES.length - 1,
  default: 0, // bell
  step: 1,
  fineStep: 1,
  scale: 'linear',
  description: 'Filter type (bell, lowShelf, highShelf, lowCut, highCut, notch)',
};

/**
 * Band frequency descriptor.
 */
const bandFreqDescriptor: ParamDescriptor = {
  id: 'freqHz',
  name: 'Frequency',
  shortName: 'Freq',
  unit: 'Hz',
  min: VANEQ_CONSTRAINTS.freqHz.min,
  max: VANEQ_CONSTRAINTS.freqHz.max,
  default: 1000,
  step: 1,
  fineStep: 1,
  scale: 'logarithmic',
  description: 'Center/corner frequency of the filter',
};

/**
 * Band gain descriptor.
 */
const bandGainDescriptor: ParamDescriptor = {
  id: 'gainDb',
  name: 'Gain',
  unit: 'dB',
  min: VANEQ_CONSTRAINTS.gainDb.min,
  max: VANEQ_CONSTRAINTS.gainDb.max,
  default: 0,
  step: 0.5,
  fineStep: 0.1,
  scale: 'linear',
  description: 'Boost or cut at this frequency',
};

/**
 * Band Q descriptor.
 */
const bandQDescriptor: ParamDescriptor = {
  id: 'q',
  name: 'Q Factor',
  shortName: 'Q',
  unit: 'Q',
  min: VANEQ_CONSTRAINTS.q.min,
  max: VANEQ_CONSTRAINTS.q.max,
  default: 1,
  step: 0.1,
  fineStep: 0.01,
  scale: 'linear',
  description: 'Width of the filter (higher = narrower)',
};

// ============ Output Gain Descriptor ============

/**
 * Output gain descriptor.
 */
const outputGainDescriptor: ParamDescriptor = {
  id: 'outputGainDb',
  name: 'Output',
  shortName: 'Out',
  unit: 'dB',
  min: VANEQ_CONSTRAINTS.outputGainDb.min,
  max: VANEQ_CONSTRAINTS.outputGainDb.max,
  default: 0,
  step: 0.5,
  fineStep: 0.1,
  scale: 'linear',
  description: 'Output gain compensation',
};

// ============ Band Labels ============

const BAND_LABELS = ['Band 1', 'Band 2', 'Band 3', 'Band 4', 'Band 5', 'Band 6', 'Band 7', 'Band 8'];

// ============ Complete VanEQ Descriptors ============

/**
 * Generate all parameter descriptors for VanEQ.
 * Includes 5 params per band (8 bands) + output gain = 41 params total.
 */
function generateVanEqDescriptors(): ParamDescriptor[] {
  const descriptors: ParamDescriptor[] = [outputGainDescriptor];

  for (let i = 0; i < VANEQ_CONSTRAINTS.bandCount; i++) {
    const bandDefaults = DEFAULT_VANEQ_BANDS[i];
    const group = BAND_LABELS[i];

    // Enabled
    descriptors.push({
      ...bandEnabledDescriptor,
      id: `band${i}_enabled`,
      group,
      default: bandDefaults.enabled ? 1 : 0,
    });

    // Type
    descriptors.push({
      ...bandTypeDescriptor,
      id: `band${i}_type`,
      group,
      default: VALID_VANEQ_BAND_TYPES.indexOf(bandDefaults.type),
    });

    // Frequency
    descriptors.push({
      ...bandFreqDescriptor,
      id: `band${i}_freqHz`,
      group,
      default: bandDefaults.freqHz,
    });

    // Gain
    descriptors.push({
      ...bandGainDescriptor,
      id: `band${i}_gainDb`,
      group,
      default: bandDefaults.gainDb,
    });

    // Q
    descriptors.push({
      ...bandQDescriptor,
      id: `band${i}_q`,
      group,
      default: bandDefaults.q,
    });
  }

  return descriptors;
}

/**
 * Complete VanEQ parameter descriptors.
 */
export const VANEQ_PARAM_DESCRIPTORS: ParamDescriptor[] = generateVanEqDescriptors();

/**
 * Get a VanEQ parameter descriptor by ID.
 *
 * @param paramId - The parameter ID
 * @returns The descriptor or undefined
 */
export function getVanEqParamDescriptor(paramId: string): ParamDescriptor | undefined {
  return VANEQ_PARAM_DESCRIPTORS.find((d) => d.id === paramId);
}

/**
 * Get default flat params for VanEQ.
 */
export function getVanEqDefaultParams(): Record<string, number> {
  const params: Record<string, number> = {};
  for (const desc of VANEQ_PARAM_DESCRIPTORS) {
    params[desc.id] = desc.default;
  }
  return params;
}

/**
 * Get the band type display name for a type index.
 */
export function getBandTypeDisplayName(typeIndex: number): string {
  const type = VALID_VANEQ_BAND_TYPES[typeIndex];
  switch (type) {
    case 'bell':
      return 'Bell';
    case 'lowShelf':
      return 'Low Shelf';
    case 'highShelf':
      return 'High Shelf';
    case 'lowPass':
      return 'Low Pass';
    case 'highPass':
      return 'High Pass';
    case 'notch':
      return 'Notch';
    case 'bandPass':
      return 'Band Pass';
    case 'tilt':
      return 'Tilt';
    default:
      return 'Bell';
  }
}

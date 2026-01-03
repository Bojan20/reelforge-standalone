/**
 * ReelForge VanComp Pro - Parameter Descriptors
 *
 * Defines all parameters for the VanComp Pro compressor plugin.
 *
 * @module plugin/vancomp-pro/vancompDescriptors
 */

import type { ParamDescriptor } from '../ParamDescriptor';

/**
 * VanComp Pro parameter descriptors.
 */
export const VANCOMP_PARAM_DESCRIPTORS: ParamDescriptor[] = [
  // Main compression params
  {
    id: 'threshold',
    name: 'Threshold',
    min: -60,
    max: 0,
    default: -20,
    step: 0.5,
    fineStep: 0.1,
    unit: 'dB',
    group: 'compression',
  },
  {
    id: 'ratio',
    name: 'Ratio',
    min: 1,
    max: 20,
    default: 4,
    step: 0.5,
    fineStep: 0.1,
    unit: ':1',
    group: 'compression',
  },
  {
    id: 'attack',
    name: 'Attack',
    min: 0.1,
    max: 100,
    default: 10,
    step: 1,
    fineStep: 0.1,
    unit: 'ms',
    group: 'timing',
  },
  {
    id: 'release',
    name: 'Release',
    min: 10,
    max: 1000,
    default: 100,
    step: 10,
    fineStep: 1,
    unit: 'ms',
    group: 'timing',
  },
  {
    id: 'knee',
    name: 'Knee',
    min: 0,
    max: 24,
    default: 6,
    step: 1,
    fineStep: 0.5,
    unit: 'dB',
    group: 'compression',
  },
  // Output section
  {
    id: 'makeup',
    name: 'Makeup',
    min: -12,
    max: 24,
    default: 0,
    step: 0.5,
    fineStep: 0.1,
    unit: 'dB',
    group: 'output',
  },
  {
    id: 'mix',
    name: 'Mix',
    min: 0,
    max: 100,
    default: 100,
    step: 5,
    fineStep: 1,
    unit: '%',
    group: 'output',
  },
  // Sidechain section
  {
    id: 'scHpf',
    name: 'SC HPF',
    min: 20,
    max: 500,
    default: 20,
    step: 10,
    fineStep: 1,
    unit: 'Hz',
    group: 'sidechain',
  },
  // Auto options
  {
    id: 'autoGain',
    name: 'Auto Gain',
    min: 0,
    max: 1,
    default: 0,
    step: 1,
    fineStep: 1,
    unit: '',
    group: 'options',
  },
  // Quality mode
  {
    id: 'quality',
    name: 'Quality',
    min: 0,
    max: 2,
    default: 1,
    step: 1,
    fineStep: 1,
    unit: '',
    group: 'options',
  },
];

/**
 * Get default params object from descriptors.
 */
export function getVanCompDefaultParams(): Record<string, number> {
  const params: Record<string, number> = {};
  for (const desc of VANCOMP_PARAM_DESCRIPTORS) {
    params[desc.id] = desc.default;
  }
  return params;
}

/**
 * Quality mode labels.
 */
export const VANCOMP_QUALITY_MODES = ['Eco', 'Normal', 'High'] as const;

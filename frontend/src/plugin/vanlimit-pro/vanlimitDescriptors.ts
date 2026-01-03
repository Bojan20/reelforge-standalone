/**
 * ReelForge VanLimit Pro - Parameter Descriptors
 *
 * Defines all parameters for the VanLimit Pro limiter plugin.
 *
 * @module plugin/vanlimit-pro/vanlimitDescriptors
 */

import type { ParamDescriptor } from '../ParamDescriptor';

/**
 * VanLimit Pro parameter descriptors.
 */
export const VANLIMIT_PARAM_DESCRIPTORS: ParamDescriptor[] = [
  // Main limiting params
  {
    id: 'ceiling',
    name: 'Ceiling',
    min: -12,
    max: 0,
    default: -0.3,
    step: 0.1,
    fineStep: 0.01,
    unit: 'dB',
    group: 'output',
  },
  {
    id: 'threshold',
    name: 'Threshold',
    min: -24,
    max: 0,
    default: -6,
    step: 0.5,
    fineStep: 0.1,
    unit: 'dB',
    group: 'limiting',
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
    id: 'lookahead',
    name: 'Lookahead',
    min: 0,
    max: 10,
    default: 3,
    step: 0.5,
    fineStep: 0.1,
    unit: 'ms',
    group: 'timing',
  },
  // Mode selection
  {
    id: 'mode',
    name: 'Mode',
    min: 0,
    max: 2,
    default: 1,
    step: 1,
    fineStep: 1,
    unit: '',
    group: 'options',
  },
  // Oversampling (studio mode)
  {
    id: 'oversampling',
    name: 'Oversampling',
    min: 0,
    max: 3,
    default: 1,
    step: 1,
    fineStep: 1,
    unit: '',
    group: 'options',
  },
  // Link stereo
  {
    id: 'stereoLink',
    name: 'Stereo Link',
    min: 0,
    max: 100,
    default: 100,
    step: 10,
    fineStep: 1,
    unit: '%',
    group: 'options',
  },
  // True peak mode
  {
    id: 'truePeak',
    name: 'True Peak',
    min: 0,
    max: 1,
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
export function getVanLimitDefaultParams(): Record<string, number> {
  const params: Record<string, number> = {};
  for (const desc of VANLIMIT_PARAM_DESCRIPTORS) {
    params[desc.id] = desc.default;
  }
  return params;
}

/**
 * Limiter mode labels.
 */
export const VANLIMIT_MODES = ['Clean', 'Punch', 'Loud'] as const;

/**
 * Oversampling options.
 */
export const VANLIMIT_OVERSAMPLING = ['Off', '2x', '4x', '8x'] as const;

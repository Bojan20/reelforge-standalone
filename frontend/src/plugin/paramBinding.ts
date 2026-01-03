/**
 * ReelForge M9.1 Parameter Binding Helpers
 *
 * Centralized utilities for reading/writing plugin parameters.
 * Provides consistent clamping, validation, and immutable updates.
 *
 * Key principles:
 * - UI may clamp values during interaction (normalizeForUI)
 * - Load validation is hard-fail (no silent clamping on load)
 * - All updates are immutable
 *
 * @module plugin/paramBinding
 */

import type { ParamDescriptor } from './ParamDescriptor';

/**
 * Normalize a value for UI display/interaction.
 * Clamps to valid range - safe for use during dragging.
 *
 * This is the ONLY place where clamping should happen during UI interaction.
 * Load validation must NOT use this - it must hard-fail on invalid data.
 *
 * @param descriptor - The parameter descriptor
 * @param value - The raw value
 * @returns Clamped value within [min, max]
 */
export function normalizeForUI(descriptor: ParamDescriptor, value: number): number {
  return Math.max(descriptor.min, Math.min(descriptor.max, value));
}

/**
 * Validate a value on load.
 * Returns validation result without modifying the value.
 *
 * IMPORTANT: This is for validation only. Invalid values should cause
 * hard-fail (RF_ERR) during project load, not silent clamping.
 *
 * @param descriptor - The parameter descriptor
 * @param value - The value to validate
 * @returns Validation result with error message if invalid
 */
export function validateOnLoad(
  descriptor: ParamDescriptor,
  value: number
): { valid: boolean; error?: string } {
  if (typeof value !== 'number' || Number.isNaN(value)) {
    return { valid: false, error: `${descriptor.id}: expected number, got ${typeof value}` };
  }

  if (value < descriptor.min) {
    return {
      valid: false,
      error: `${descriptor.id}: value ${value} below minimum ${descriptor.min}`,
    };
  }

  if (value > descriptor.max) {
    return {
      valid: false,
      error: `${descriptor.id}: value ${value} above maximum ${descriptor.max}`,
    };
  }

  return { valid: true };
}

/**
 * Validate all parameters for a plugin on load.
 *
 * @param descriptors - Array of parameter descriptors
 * @param params - The parameter values to validate
 * @returns Validation result with all errors
 */
export function validateParamsOnLoad(
  descriptors: ParamDescriptor[],
  params: Record<string, number>
): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  for (const desc of descriptors) {
    // Skip read-only params (they have fixed values)
    if (desc.readOnly) continue;

    const value = params[desc.id];

    // Check for missing params
    if (value === undefined) {
      // Missing is OK - will use default
      continue;
    }

    const result = validateOnLoad(desc, value);
    if (!result.valid && result.error) {
      errors.push(result.error);
    }
  }

  return { valid: errors.length === 0, errors };
}

/**
 * Apply a single parameter update immutably.
 * Clamps the value for UI safety.
 *
 * @param params - Current parameter values
 * @param paramId - The parameter ID to update
 * @param value - The new value
 * @param descriptor - The parameter descriptor (for clamping)
 * @returns New params object with the update applied
 */
export function applyPatch(
  params: Record<string, number>,
  paramId: string,
  value: number,
  descriptor: ParamDescriptor
): Record<string, number> {
  const clampedValue = normalizeForUI(descriptor, value);
  return { ...params, [paramId]: clampedValue };
}

/**
 * Apply multiple parameter updates immutably.
 *
 * @param params - Current parameter values
 * @param updates - Map of paramId to new value
 * @param descriptorMap - Map of paramId to descriptor
 * @returns New params object with all updates applied
 */
export function applyPatches(
  params: Record<string, number>,
  updates: Record<string, number>,
  descriptorMap: Map<string, ParamDescriptor>
): Record<string, number> {
  const result = { ...params };

  for (const [paramId, value] of Object.entries(updates)) {
    const descriptor = descriptorMap.get(paramId);
    if (descriptor) {
      result[paramId] = normalizeForUI(descriptor, value);
    } else {
      // Unknown param - pass through (may be a plugin-specific param)
      result[paramId] = value;
    }
  }

  return result;
}

/**
 * Reset a parameter to its default value.
 *
 * @param params - Current parameter values
 * @param paramId - The parameter ID to reset
 * @param descriptor - The parameter descriptor (for default)
 * @returns New params object with the reset applied
 */
export function resetParam(
  params: Record<string, number>,
  paramId: string,
  descriptor: ParamDescriptor
): Record<string, number> {
  return { ...params, [paramId]: descriptor.default };
}

/**
 * Get default parameter values from descriptors.
 *
 * @param descriptors - Array of parameter descriptors
 * @returns Object with default values for all params
 */
export function getDefaultParams(descriptors: ParamDescriptor[]): Record<string, number> {
  const params: Record<string, number> = {};
  for (const desc of descriptors) {
    params[desc.id] = desc.default;
  }
  return params;
}

/**
 * Create a descriptor map for efficient lookup.
 *
 * @param descriptors - Array of parameter descriptors
 * @returns Map of paramId to descriptor
 */
export function createDescriptorMap(
  descriptors: ParamDescriptor[]
): Map<string, ParamDescriptor> {
  return new Map(descriptors.map((d) => [d.id, d]));
}

/**
 * Check if two param objects are equal (shallow comparison of values).
 *
 * @param a - First param object
 * @param b - Second param object
 * @returns True if equal
 */
export function paramsEqual(
  a: Record<string, number>,
  b: Record<string, number>
): boolean {
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);

  if (keysA.length !== keysB.length) return false;

  for (const key of keysA) {
    if (a[key] !== b[key]) return false;
  }

  return true;
}

/**
 * Snap a value to the nearest step.
 *
 * @param value - The value to snap
 * @param descriptor - The parameter descriptor
 * @param fine - Whether to use fine step
 * @returns Snapped value
 */
export function snapToStep(
  value: number,
  descriptor: ParamDescriptor,
  fine: boolean = false
): number {
  const step = fine ? descriptor.fineStep : descriptor.step;
  if (step <= 0) return value;

  const snapped = Math.round(value / step) * step;
  return normalizeForUI(descriptor, snapped);
}

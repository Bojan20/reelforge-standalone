/**
 * ReelForge M9.0 Parameter Descriptor
 *
 * Centralized parameter metadata for plugins.
 * Enables future auto-UI generation and validation.
 *
 * @module plugin/ParamDescriptor
 */

/**
 * Unit types for parameter display.
 */
export type ParamUnit = 'Hz' | 'dB' | 'ms' | 's' | '%' | ':1' | 'Q' | '';

/**
 * Parameter display scale.
 * - 'linear': Linear mapping (default)
 * - 'logarithmic': Log scale (for frequency, etc.)
 */
export type ParamScale = 'linear' | 'logarithmic';

/**
 * Parameter descriptor for plugin parameters.
 * Provides all metadata needed for UI generation, validation, and serialization.
 */
export interface ParamDescriptor {
  /** Unique identifier within the plugin (e.g., 'threshold', 'frequency') */
  id: string;

  /** Human-readable name for display (e.g., 'Threshold', 'Frequency') */
  name: string;

  /** Short name for compact displays (e.g., 'Thresh', 'Freq') */
  shortName?: string;

  /** Unit for display (appended to value) */
  unit?: ParamUnit;

  /** Minimum allowed value */
  min: number;

  /** Maximum allowed value */
  max: number;

  /** Default value */
  default: number;

  /** Normal step increment (for sliders, mouse wheel) */
  step: number;

  /** Fine step increment (for shift+drag) */
  fineStep: number;

  /** Display scale (linear or logarithmic) */
  scale?: ParamScale;

  /** Optional display multiplier (e.g., 1000 to show seconds as ms) */
  displayMultiplier?: number;

  /** Optional description for tooltips */
  description?: string;

  /** Whether this parameter is read-only (display only) */
  readOnly?: boolean;

  /** Optional group for UI organization (e.g., 'Band 1', 'Envelope') */
  group?: string;
}

/**
 * Validate a value against a param descriptor.
 * Returns clamped value within valid range.
 *
 * @param value - The value to validate
 * @param desc - The parameter descriptor
 * @returns Clamped value
 */
export function clampParamValue(value: number, desc: ParamDescriptor): number {
  return Math.max(desc.min, Math.min(desc.max, value));
}

/**
 * Check if a value is within valid range.
 *
 * @param value - The value to check
 * @param desc - The parameter descriptor
 * @returns True if value is valid
 */
export function isParamValueValid(value: number, desc: ParamDescriptor): boolean {
  return value >= desc.min && value <= desc.max;
}

/**
 * Format a value for display.
 *
 * @param value - The raw value
 * @param desc - The parameter descriptor
 * @returns Formatted string for display
 */
export function formatParamValue(value: number, desc: ParamDescriptor): string {
  // Guard against NaN/Infinity values
  if (!Number.isFinite(value)) {
    console.error(`RF_ERR_INVALID_PARAM: formatParamValue received non-finite value: ${value}`);
    return '—';
  }

  const displayValue = desc.displayMultiplier
    ? value * desc.displayMultiplier
    : value;

  // Guard against NaN after multiplication
  if (!Number.isFinite(displayValue)) {
    console.error(`RF_ERR_INVALID_PARAM: displayValue became non-finite after multiplier: ${displayValue}`);
    return '—';
  }

  // Determine precision based on step
  const step = desc.step;
  let precision = 2; // Default precision

  if (step > 0 && step < 1) {
    // Calculate precision, clamped to valid toFixed range [0, 100]
    const rawPrecision = Math.ceil(-Math.log10(step));
    precision = Math.max(0, Math.min(100, rawPrecision));
  } else if (step >= 1) {
    precision = 0;
  }
  // step <= 0 uses default precision of 2

  const formatted = displayValue.toFixed(precision);
  return desc.unit ? `${formatted} ${desc.unit}` : formatted;
}

/**
 * Convert slider position to value (handles logarithmic scale).
 *
 * @param position - Slider position (0-1)
 * @param desc - The parameter descriptor
 * @returns The parameter value
 */
export function sliderToValue(position: number, desc: ParamDescriptor): number {
  const { min, max, scale } = desc;

  if (scale === 'logarithmic' && min > 0) {
    // Logarithmic mapping
    const logMin = Math.log10(min);
    const logMax = Math.log10(max);
    const logValue = logMin + position * (logMax - logMin);
    return Math.pow(10, logValue);
  }

  // Linear mapping
  return min + position * (max - min);
}

/**
 * Convert value to slider position (handles logarithmic scale).
 *
 * @param value - The parameter value
 * @param desc - The parameter descriptor
 * @returns Slider position (0-1)
 */
export function valueToSlider(value: number, desc: ParamDescriptor): number {
  const { min, max, scale } = desc;

  if (scale === 'logarithmic' && min > 0) {
    // Logarithmic mapping
    const logMin = Math.log10(min);
    const logMax = Math.log10(max);
    const logValue = Math.log10(Math.max(min, value));
    return (logValue - logMin) / (logMax - logMin);
  }

  // Linear mapping
  return (value - min) / (max - min);
}

/**
 * Get the step to use based on modifier keys.
 *
 * @param desc - The parameter descriptor
 * @param fine - Whether fine adjustment is active (e.g., shift held)
 * @returns Step value to use
 */
export function getEffectiveStep(desc: ParamDescriptor, fine: boolean): number {
  return fine ? desc.fineStep : desc.step;
}

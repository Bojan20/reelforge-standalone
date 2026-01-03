/**
 * ReelForge DSP Module
 *
 * Professional-grade digital signal processing for zero-artifact audio.
 *
 * Features:
 * - True Peak Limiter (EBU R128 / ITU-R BS.1770-4 compliant)
 * - LUFS Metering (K-weighted, gated loudness)
 * - TPDF Dithering (mastering-quality bit depth reduction)
 *
 * @module core/dsp
 */

// True Peak Limiter
export {
  TruePeakLimiter,
  createTruePeakLimiter,
  type LimiterConfig,
  type LimiterState,
} from './truePeakLimiter';

// LUFS Meter
export {
  LUFSMeter,
  createLUFSMeter,
  type LUFSMeterConfig,
  type LUFSReading,
} from './lufsMeter';

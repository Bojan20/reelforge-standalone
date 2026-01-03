/**
 * Audio Constants
 *
 * Centralized audio-related constants to replace magic numbers.
 * All timing values are in seconds unless otherwise noted.
 */

// ============ Timing Constants ============

/** Click-free parameter ramp time (10ms) */
export const PARAM_RAMP_SEC = 0.01;

/** Bypass crossfade time (10ms) */
export const BYPASS_RAMP_SEC = 0.01;

/** Default fade in/out time (50ms) */
export const DEFAULT_FADE_SEC = 0.05;

/** Short fade for quick transitions (5ms) */
export const SHORT_FADE_SEC = 0.005;

/** Long fade for smooth transitions (100ms) */
export const LONG_FADE_SEC = 0.1;

/** Crossfade overlap time (20ms) */
export const CROSSFADE_SEC = 0.02;

// ============ Delay Constants ============

/** Maximum PDC delay time (500ms) */
export const MAX_PDC_DELAY_SEC = 0.5;

/** Default delay buffer size (2 seconds) */
export const DEFAULT_DELAY_BUFFER_SEC = 2.0;

// ============ Dynamics Constants ============

/** Default compressor attack (10ms) */
export const DEFAULT_ATTACK_SEC = 0.01;

/** Default compressor release (100ms) */
export const DEFAULT_RELEASE_SEC = 0.1;

/** Default limiter ceiling (-0.3dB) */
export const DEFAULT_CEILING_DB = -0.3;

/** Default limiter release (50ms) */
export const LIMITER_RELEASE_SEC = 0.05;

// ============ Metering Constants ============

/** Peak meter decay rate (dB per second) */
export const METER_DECAY_RATE = 26.0;

/** Peak hold time (2 seconds) */
export const PEAK_HOLD_SEC = 2.0;

/** Metering update interval (samples) */
export const METER_UPDATE_SAMPLES = 2048;

/** RMS averaging window (300ms) */
export const RMS_WINDOW_SEC = 0.3;

// ============ Filter Constants ============

/** Minimum filter frequency (20Hz) */
export const MIN_FREQ_HZ = 20;

/** Maximum filter frequency (20kHz) */
export const MAX_FREQ_HZ = 20000;

/** Nyquist fraction for filter stability (0.49) */
export const NYQUIST_FRACTION = 0.49;

/** Default Q factor */
export const DEFAULT_Q = 0.707;

// ============ Level Constants ============

/** Unity gain (0dB) */
export const UNITY_GAIN = 1.0;

/** Silence threshold (linear) */
export const SILENCE_THRESHOLD = 0.0001;

/** Silence threshold (dB) */
export const SILENCE_THRESHOLD_DB = -80;

/** Default master volume (0.85) */
export const DEFAULT_MASTER_VOLUME = 0.85;

// ============ Buffer Constants ============

/** Default sample rate */
export const DEFAULT_SAMPLE_RATE = 48000;

/** Common buffer sizes */
export const BUFFER_SIZES = {
  TINY: 128,
  SMALL: 256,
  MEDIUM: 512,
  DEFAULT: 1024,
  LARGE: 2048,
  HUGE: 4096,
} as const;

/** Default audio buffer cache size */
export const DEFAULT_CACHE_SIZE = 100;

/** Default cache max age (30 minutes) */
export const DEFAULT_CACHE_MAX_AGE_MS = 30 * 60 * 1000;

// ============ Playback Constants ============

/** Default update interval for playback position (50ms) */
export const PLAYBACK_UPDATE_INTERVAL_MS = 50;

/** Seek look-ahead buffer (100ms) */
export const SEEK_LOOKAHEAD_SEC = 0.1;

// ============ Engine Constants ============

/** Master insert DSP fallback timeout (2 seconds) */
export const MASTER_INSERT_FALLBACK_MS = 2000;

/** Fade retry delay (100ms) */
export const FADE_RETRY_DELAY_MS = 100;

/** Default fade duration (300ms) */
export const DEFAULT_FADE_DURATION_MS = 300;

/** Voice stop delay (50ms) - allows fade out before stop */
export const VOICE_STOP_DELAY_MS = 50;

// ============ Utility Conversions ============

/** Convert dB to linear */
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

/** Convert linear to dB */
export function linearToDb(linear: number): number {
  if (linear <= 0) return SILENCE_THRESHOLD_DB;
  return 20 * Math.log10(linear);
}

/** Convert seconds to samples */
export function secToSamples(sec: number, sampleRate: number = DEFAULT_SAMPLE_RATE): number {
  return Math.round(sec * sampleRate);
}

/** Convert samples to seconds */
export function samplesToSec(samples: number, sampleRate: number = DEFAULT_SAMPLE_RATE): number {
  return samples / sampleRate;
}

/** Convert ms to seconds */
export function msToSec(ms: number): number {
  return ms / 1000;
}

/** Convert seconds to ms */
export function secToMs(sec: number): number {
  return sec * 1000;
}

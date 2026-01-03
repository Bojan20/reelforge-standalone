/**
 * ReelForge Spatial System - Math Utilities
 * Low-level math functions optimized for spatial calculations.
 *
 * @module reelforge/spatial/utils/math
 */

/**
 * Clamp value to 0..1 range.
 */
export function clamp01(v: number): number {
  return v < 0 ? 0 : v > 1 ? 1 : v;
}

/**
 * Clamp value to arbitrary range.
 */
export function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

/**
 * Linear interpolation.
 */
export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/**
 * Inverse lerp - find t given value between a and b.
 */
export function inverseLerp(a: number, b: number, value: number): number {
  if (Math.abs(b - a) < 1e-10) return 0;
  return (value - a) / (b - a);
}

/**
 * Remap value from one range to another.
 */
export function remap(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number
): number {
  const t = inverseLerp(inMin, inMax, value);
  return lerp(outMin, outMax, clamp01(t));
}

/**
 * Smooth step (Hermite interpolation).
 */
export function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = clamp01((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

/**
 * Smoother step (Ken Perlin's improved version).
 */
export function smootherstep(edge0: number, edge1: number, x: number): number {
  const t = clamp01((x - edge0) / (edge1 - edge0));
  return t * t * t * (t * (t * 6 - 15) + 10);
}

/**
 * Exponential decay for smoothing.
 * Returns blend factor for given dt and time constant.
 */
export function expDecay(dt: number, tau: number): number {
  if (tau <= 0) return 1;
  return 1 - Math.exp(-dt / tau);
}

/**
 * Distance between two 2D points.
 */
export function distance(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1;
  const dy = y2 - y1;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Squared distance (faster, no sqrt).
 */
export function distanceSq(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1;
  const dy = y2 - y1;
  return dx * dx + dy * dy;
}

/**
 * Normalize 2D vector.
 */
export function normalize2D(x: number, y: number): { x: number; y: number } {
  const len = Math.sqrt(x * x + y * y);
  if (len < 1e-10) return { x: 0, y: 0 };
  return { x: x / len, y: y / len };
}

/**
 * Apply deadzone to value.
 * Values within deadzone are snapped to 0.
 */
export function applyDeadzone(value: number, deadzone: number): number {
  if (Math.abs(value) < deadzone) return 0;
  // Rescale remaining range
  const sign = value < 0 ? -1 : 1;
  return sign * ((Math.abs(value) - deadzone) / (1 - deadzone));
}

/**
 * Equal-power panning gains.
 * Input: pan -1 (left) to +1 (right)
 * Output: gainL and gainR for constant power
 */
export function equalPowerGains(pan: number): { gainL: number; gainR: number } {
  // Map pan from -1..+1 to 0..PI/2
  const angle = (clamp(pan, -1, 1) + 1) * 0.25 * Math.PI;
  return {
    gainL: Math.cos(angle),
    gainR: Math.sin(angle),
  };
}

/**
 * Convert normalized X (0..1) to pan (-1..+1).
 */
export function xNormToPan(xNorm: number): number {
  return clamp01(xNorm) * 2 - 1;
}

/**
 * Convert pan (-1..+1) to normalized X (0..1).
 */
export function panToXNorm(pan: number): number {
  return (clamp(pan, -1, 1) + 1) * 0.5;
}

/**
 * Apply pan with deadzone and max limit.
 */
export function processPan(
  xNorm: number,
  deadzone: number,
  maxPan: number
): number {
  let pan = xNormToPan(xNorm);
  pan = applyDeadzone(pan, deadzone);
  return clamp(pan, -maxPan, maxPan);
}

/**
 * Weighted average of values with weights.
 */
export function weightedAverage(
  values: number[],
  weights: number[]
): number {
  if (values.length === 0) return 0;
  if (values.length !== weights.length) {
    throw new Error('Values and weights must have same length');
  }

  let sum = 0;
  let weightSum = 0;

  for (let i = 0; i < values.length; i++) {
    sum += values[i] * weights[i];
    weightSum += weights[i];
  }

  if (weightSum < 1e-10) return values[0] ?? 0;
  return sum / weightSum;
}

/**
 * Weighted average of 2D points.
 */
export function weightedAverage2D(
  points: Array<{ x: number; y: number }>,
  weights: number[]
): { x: number; y: number } {
  if (points.length === 0) return { x: 0.5, y: 0.5 };

  const xs = points.map(p => p.x);
  const ys = points.map(p => p.y);

  return {
    x: weightedAverage(xs, weights),
    y: weightedAverage(ys, weights),
  };
}

/**
 * Calculate velocity from position delta.
 */
export function calculateVelocity(
  currentPos: number,
  prevPos: number,
  dtSec: number
): number {
  if (dtSec <= 0) return 0;
  return (currentPos - prevPos) / dtSec;
}

/**
 * Exponential moving average update.
 */
export function ema(current: number, target: number, alpha: number): number {
  return current + alpha * (target - current);
}

/**
 * Check if point is within viewport bounds (with margin).
 */
export function isInViewport(
  xNorm: number,
  yNorm: number,
  margin: number = 0
): boolean {
  return (
    xNorm >= -margin &&
    xNorm <= 1 + margin &&
    yNorm >= -margin &&
    yNorm <= 1 + margin
  );
}

/**
 * Calculate confidence decay based on time since last update.
 */
export function confidenceDecay(
  baseConfidence: number,
  timeSinceUpdateMs: number,
  halfLifeMs: number = 500
): number {
  const decay = Math.pow(0.5, timeSinceUpdateMs / halfLifeMs);
  return baseConfidence * decay;
}

/**
 * Combine multiple confidence values (geometric mean-ish).
 */
export function combineConfidence(...confidences: number[]): number {
  if (confidences.length === 0) return 0;

  // Use product with root for diminishing returns
  let product = 1;
  for (const c of confidences) {
    product *= Math.max(0.01, c); // Avoid zero killing everything
  }

  return Math.pow(product, 1 / confidences.length);
}

/**
 * DB to linear gain conversion.
 */
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

/**
 * Linear gain to dB conversion.
 */
export function linearToDb(linear: number): number {
  if (linear <= 0) return -Infinity;
  return 20 * Math.log10(linear);
}

/**
 * Frequency to normalized 0..1 in log scale.
 * Useful for LPF visualization.
 */
export function freqToNorm(
  freq: number,
  minFreq: number = 20,
  maxFreq: number = 20000
): number {
  const logMin = Math.log10(minFreq);
  const logMax = Math.log10(maxFreq);
  const logFreq = Math.log10(clamp(freq, minFreq, maxFreq));
  return (logFreq - logMin) / (logMax - logMin);
}

/**
 * Normalized 0..1 to frequency in log scale.
 */
export function normToFreq(
  norm: number,
  minFreq: number = 20,
  maxFreq: number = 20000
): number {
  const logMin = Math.log10(minFreq);
  const logMax = Math.log10(maxFreq);
  const logFreq = lerp(logMin, logMax, clamp01(norm));
  return Math.pow(10, logFreq);
}

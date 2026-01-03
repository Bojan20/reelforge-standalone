/**
 * ReelForge Clip Gain & Envelope Editor
 *
 * Per-clip gain control with automation envelope support.
 * Supports breakpoint editing and smooth interpolation.
 *
 * @module audio-processing/ClipGain
 */

// ============ Types ============

export type InterpolationType = 'linear' | 'exponential' | 'logarithmic' | 's-curve' | 'hold';

export interface EnvelopePoint {
  time: number; // In seconds
  value: number; // 0-2 (0 = -inf dB, 1 = 0dB, 2 = +6dB)
  curve?: InterpolationType;
}

export interface ClipGainEnvelope {
  id: string;
  clipId: string;
  points: EnvelopePoint[];
  defaultValue: number;
  rangeMin: number;
  rangeMax: number;
}

export interface GainAutomation {
  enabled: boolean;
  envelope: ClipGainEnvelope;
  smoothingMs: number;
}

// ============ Interpolation Functions ============

function linearInterpolate(start: number, end: number, t: number): number {
  return start + (end - start) * t;
}

function exponentialInterpolate(start: number, end: number, t: number): number {
  if (start === 0) return end * t;
  return start * Math.pow(end / start, t);
}

function logarithmicInterpolate(start: number, end: number, t: number): number {
  // Logarithmic feels faster at start, slower at end
  const logT = 1 - Math.pow(1 - t, 2);
  return start + (end - start) * logT;
}

function sCurveInterpolate(start: number, end: number, t: number): number {
  // Smooth S-curve
  const smoothT = t * t * (3 - 2 * t);
  return start + (end - start) * smoothT;
}

function holdInterpolate(start: number, _end: number, _t: number): number {
  return start; // Stay at start value until next point
}

function interpolate(
  start: number,
  end: number,
  t: number,
  type: InterpolationType = 'linear'
): number {
  switch (type) {
    case 'linear':
      return linearInterpolate(start, end, t);
    case 'exponential':
      return exponentialInterpolate(start, end, t);
    case 'logarithmic':
      return logarithmicInterpolate(start, end, t);
    case 's-curve':
      return sCurveInterpolate(start, end, t);
    case 'hold':
      return holdInterpolate(start, end, t);
    default:
      return linearInterpolate(start, end, t);
  }
}

// ============ Clip Gain Engine ============

export class ClipGainEngine {
  private envelopes = new Map<string, ClipGainEnvelope>();

  /**
   * Create new gain envelope for clip.
   */
  createEnvelope(clipId: string): ClipGainEnvelope {
    const envelope: ClipGainEnvelope = {
      id: `envelope_${clipId}_${Date.now()}`,
      clipId,
      points: [],
      defaultValue: 1.0, // 0dB
      rangeMin: 0,
      rangeMax: 2, // +6dB
    };

    this.envelopes.set(envelope.id, envelope);
    return envelope;
  }

  /**
   * Get envelope by clip ID.
   */
  getEnvelopeForClip(clipId: string): ClipGainEnvelope | undefined {
    for (const envelope of this.envelopes.values()) {
      if (envelope.clipId === clipId) {
        return envelope;
      }
    }
    return undefined;
  }

  /**
   * Add point to envelope.
   */
  addPoint(
    envelopeId: string,
    time: number,
    value: number,
    curve: InterpolationType = 'linear'
  ): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope) return false;

    // Clamp value to range
    value = Math.max(envelope.rangeMin, Math.min(envelope.rangeMax, value));

    // Find insertion position (keep sorted by time)
    let insertIndex = envelope.points.length;
    for (let i = 0; i < envelope.points.length; i++) {
      if (envelope.points[i].time > time) {
        insertIndex = i;
        break;
      } else if (Math.abs(envelope.points[i].time - time) < 0.001) {
        // Update existing point
        envelope.points[i].value = value;
        envelope.points[i].curve = curve;
        return true;
      }
    }

    envelope.points.splice(insertIndex, 0, { time, value, curve });
    return true;
  }

  /**
   * Remove point from envelope.
   */
  removePoint(envelopeId: string, time: number): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope) return false;

    const index = envelope.points.findIndex(p => Math.abs(p.time - time) < 0.001);
    if (index !== -1) {
      envelope.points.splice(index, 1);
      return true;
    }
    return false;
  }

  /**
   * Move point to new position.
   */
  movePoint(
    envelopeId: string,
    oldTime: number,
    newTime: number,
    newValue?: number
  ): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope) return false;

    const point = envelope.points.find(p => Math.abs(p.time - oldTime) < 0.001);
    if (!point) return false;

    // Remove and re-add to maintain sort order
    this.removePoint(envelopeId, oldTime);
    this.addPoint(
      envelopeId,
      newTime,
      newValue ?? point.value,
      point.curve
    );

    return true;
  }

  /**
   * Get gain value at specific time.
   */
  getValueAtTime(envelopeId: string, time: number): number {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope || envelope.points.length === 0) {
      return envelope?.defaultValue ?? 1.0;
    }

    // Before first point
    if (time <= envelope.points[0].time) {
      return envelope.points[0].value;
    }

    // After last point
    if (time >= envelope.points[envelope.points.length - 1].time) {
      return envelope.points[envelope.points.length - 1].value;
    }

    // Find surrounding points
    for (let i = 0; i < envelope.points.length - 1; i++) {
      const p1 = envelope.points[i];
      const p2 = envelope.points[i + 1];

      if (time >= p1.time && time < p2.time) {
        const t = (time - p1.time) / (p2.time - p1.time);
        return interpolate(p1.value, p2.value, t, p1.curve);
      }
    }

    return envelope.defaultValue;
  }

  /**
   * Generate gain curve for entire clip.
   */
  generateGainCurve(
    envelopeId: string,
    duration: number,
    sampleRate: number
  ): Float32Array {
    const samples = Math.ceil(duration * sampleRate);
    const curve = new Float32Array(samples);
    const envelope = this.envelopes.get(envelopeId);

    if (!envelope) {
      curve.fill(1.0);
      return curve;
    }

    for (let i = 0; i < samples; i++) {
      const time = i / sampleRate;
      curve[i] = this.getValueAtTime(envelopeId, time);
    }

    return curve;
  }

  /**
   * Apply gain envelope to audio buffer.
   */
  applyEnvelope(
    buffer: AudioBuffer,
    envelopeId: string
  ): void {
    const gainCurve = this.generateGainCurve(
      envelopeId,
      buffer.duration,
      buffer.sampleRate
    );

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < data.length; i++) {
        data[i] *= gainCurve[i];
      }
    }
  }

  /**
   * Apply simple static gain to buffer.
   */
  applyGain(buffer: AudioBuffer, gainDb: number): void {
    const gain = Math.pow(10, gainDb / 20);

    for (let ch = 0; ch < buffer.numberOfChannels; ch++) {
      const data = buffer.getChannelData(ch);

      for (let i = 0; i < data.length; i++) {
        data[i] *= gain;
      }
    }
  }

  /**
   * Normalize envelope points.
   */
  normalizeEnvelope(envelopeId: string): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope || envelope.points.length === 0) return false;

    let maxValue = 0;
    for (const point of envelope.points) {
      if (point.value > maxValue) maxValue = point.value;
    }

    if (maxValue > 0 && maxValue !== 1) {
      const scale = 1 / maxValue;
      for (const point of envelope.points) {
        point.value *= scale;
      }
    }

    return true;
  }

  /**
   * Invert envelope.
   */
  invertEnvelope(envelopeId: string): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope || envelope.points.length === 0) return false;

    for (const point of envelope.points) {
      // Invert around center of range
      const center = (envelope.rangeMax + envelope.rangeMin) / 2;
      point.value = center + (center - point.value);
    }

    return true;
  }

  /**
   * Scale envelope by factor.
   */
  scaleEnvelope(envelopeId: string, factor: number): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope || envelope.points.length === 0) return false;

    for (const point of envelope.points) {
      point.value = Math.max(
        envelope.rangeMin,
        Math.min(envelope.rangeMax, point.value * factor)
      );
    }

    return true;
  }

  /**
   * Clear all points from envelope.
   */
  clearEnvelope(envelopeId: string): boolean {
    const envelope = this.envelopes.get(envelopeId);
    if (!envelope) return false;

    envelope.points = [];
    return true;
  }

  /**
   * Delete envelope.
   */
  deleteEnvelope(envelopeId: string): boolean {
    return this.envelopes.delete(envelopeId);
  }

  /**
   * Duplicate envelope.
   */
  duplicateEnvelope(envelopeId: string, newClipId: string): ClipGainEnvelope | undefined {
    const source = this.envelopes.get(envelopeId);
    if (!source) return undefined;

    const newEnvelope: ClipGainEnvelope = {
      id: `envelope_${newClipId}_${Date.now()}`,
      clipId: newClipId,
      points: source.points.map(p => ({ ...p })),
      defaultValue: source.defaultValue,
      rangeMin: source.rangeMin,
      rangeMax: source.rangeMax,
    };

    this.envelopes.set(newEnvelope.id, newEnvelope);
    return newEnvelope;
  }

  /**
   * Get envelope visualization data.
   */
  getVisualizationData(
    envelopeId: string,
    width: number,
    duration: number
  ): Array<{ x: number; y: number }> {
    const envelope = this.envelopes.get(envelopeId);
    const points: Array<{ x: number; y: number }> = [];

    if (!envelope) {
      points.push({ x: 0, y: 0.5 });
      points.push({ x: width, y: 0.5 });
      return points;
    }

    // Generate smooth curve
    const steps = Math.min(width, 200);
    for (let i = 0; i <= steps; i++) {
      const t = (i / steps) * duration;
      const value = this.getValueAtTime(envelopeId, t);
      const normalizedY = 1 - ((value - envelope.rangeMin) / (envelope.rangeMax - envelope.rangeMin));

      points.push({
        x: (i / steps) * width,
        y: normalizedY * 100, // 0-100 range
      });
    }

    return points;
  }
}

// ============ Singleton Instance ============

export const clipGainEngine = new ClipGainEngine();

// ============ Utility Functions ============

/**
 * Convert linear gain to dB.
 */
export function gainToDb(gain: number): number {
  return gain > 0 ? 20 * Math.log10(gain) : -Infinity;
}

/**
 * Convert dB to linear gain.
 */
export function dbToGain(db: number): number {
  return Math.pow(10, db / 20);
}

/**
 * Format gain for display.
 */
export function formatGain(gain: number): string {
  const db = gainToDb(gain);
  if (!isFinite(db)) return '-∞ dB';
  return `${db >= 0 ? '+' : ''}${db.toFixed(1)} dB`;
}

/**
 * Get interpolation type name.
 */
export function getInterpolationName(type: InterpolationType): string {
  const names: Record<InterpolationType, string> = {
    linear: 'Linear',
    exponential: 'Exponential',
    logarithmic: 'Logarithmic',
    's-curve': 'S-Curve',
    hold: 'Hold',
  };
  return names[type];
}

/**
 * Get all interpolation types.
 */
export function getInterpolationTypes(): InterpolationType[] {
  return ['linear', 'exponential', 'logarithmic', 's-curve', 'hold'];
}

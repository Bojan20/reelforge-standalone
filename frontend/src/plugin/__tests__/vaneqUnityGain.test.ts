/**
 * ReelForge M9.3 VanEQ Unity Gain Tests
 *
 * Verifies that VanEQ maintains unity gain (no volume change) when:
 * - All bands are disabled
 * - All bands have 0dB gain
 * - Plugin is ON but neutral
 *
 * Uses OfflineAudioContext for deterministic testing.
 */

import { describe, it, expect, beforeAll } from 'vitest';

// The worklet code as a string for inline loading
const VANEQ_WORKLET_CODE = `
// Simplified VanEQ processor for testing unity passthrough

class BiquadCoefficients {
  static calculate(type, freq, gain, q, sampleRate) {
    const omega = (2 * Math.PI * freq) / sampleRate;
    const sinOmega = Math.sin(omega);
    const cosOmega = Math.cos(omega);
    const alpha = sinOmega / (2 * q);
    const A = Math.pow(10, gain / 40);

    let b0, b1, b2, a0, a1, a2;

    switch (type) {
      case 0: // bell/peaking
        b0 = 1 + alpha * A;
        b1 = -2 * cosOmega;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cosOmega;
        a2 = 1 - alpha / A;
        break;
      default:
        return { b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 };
    }

    return {
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    };
  }
}

class BiquadFilter {
  constructor() {
    this.x1 = [0, 0];
    this.x2 = [0, 0];
    this.y1 = [0, 0];
    this.y2 = [0, 0];
    this.b0 = 1;
    this.b1 = 0;
    this.b2 = 0;
    this.a1 = 0;
    this.a2 = 0;
    this.targetB0 = 1;
    this.targetB1 = 0;
    this.targetB2 = 0;
    this.targetA1 = 0;
    this.targetA2 = 0;
    this.smoothingFactor = 0.02;
  }

  setCoefficients(coeffs) {
    this.targetB0 = coeffs.b0;
    this.targetB1 = coeffs.b1;
    this.targetB2 = coeffs.b2;
    this.targetA1 = coeffs.a1;
    this.targetA2 = coeffs.a2;
  }

  setBypass() {
    this.targetB0 = 1;
    this.targetB1 = 0;
    this.targetB2 = 0;
    this.targetA1 = 0;
    this.targetA2 = 0;
  }

  process(input, output, channel) {
    for (let i = 0; i < input.length; i++) {
      this.b0 += (this.targetB0 - this.b0) * this.smoothingFactor;
      this.b1 += (this.targetB1 - this.b1) * this.smoothingFactor;
      this.b2 += (this.targetB2 - this.b2) * this.smoothingFactor;
      this.a1 += (this.targetA1 - this.a1) * this.smoothingFactor;
      this.a2 += (this.targetA2 - this.a2) * this.smoothingFactor;

      const x = input[i];
      const y =
        this.b0 * x +
        this.b1 * this.x1[channel] +
        this.b2 * this.x2[channel] -
        this.a1 * this.y1[channel] -
        this.a2 * this.y2[channel];

      this.x2[channel] = this.x1[channel];
      this.x1[channel] = x;
      this.y2[channel] = this.y1[channel];
      this.y1[channel] = y;

      output[i] = y;
    }
  }
}

class VanEqProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.filters = [];
    for (let i = 0; i < 6; i++) {
      this.filters.push(new BiquadFilter());
    }
    this.bandEnabled = [false, false, false, false, false, false];
    this.outputGain = 1;
    this.targetOutputGain = 1;
    this.gainSmoothingFactor = 0.01;
    this._isUnityPassthrough = true;
    this.tempBuffer = null;

    this.port.onmessage = (event) => {
      this.handleMessage(event.data);
    };
  }

  handleMessage(data) {
    if (data.type === 'update') {
      const { bands, outputGain } = data;

      if (typeof outputGain === 'number') {
        this.targetOutputGain = Math.pow(10, outputGain / 20);
      }

      if (Array.isArray(bands)) {
        bands.forEach((band, i) => {
          if (i >= this.filters.length) return;
          this.bandEnabled[i] = band.enabled;

          if (band.enabled) {
            const coeffs = BiquadCoefficients.calculate(
              0, // bell type
              band.freqHz,
              band.gainDb,
              band.q,
              sampleRate
            );
            this.filters[i].setCoefficients(coeffs);
          } else {
            this.filters[i].setBypass();
          }
        });
      }

      const anyBandEnabled = this.bandEnabled.some(Boolean);
      const isUnityGain = Math.abs(this.targetOutputGain - 1.0) < 0.0001;
      this._isUnityPassthrough = !anyBandEnabled && isUnityGain;
    }
  }

  process(inputs, outputs) {
    const input = inputs[0];
    const output = outputs[0];

    if (!input || !input.length || !output || !output.length) {
      return true;
    }

    const numChannels = Math.min(input.length, output.length);
    const blockSize = input[0]?.length || 0;

    if (blockSize === 0) return true;

    // UNITY PASSTHROUGH: When all bands disabled and gain is 0dB
    if (this._isUnityPassthrough && Math.abs(this.outputGain - 1.0) < 0.0001) {
      for (let ch = 0; ch < numChannels; ch++) {
        if (input[ch] && output[ch]) {
          output[ch].set(input[ch]);
        }
      }
      return true;
    }

    if (!this.tempBuffer || this.tempBuffer.length !== blockSize) {
      this.tempBuffer = new Float32Array(blockSize);
    }

    for (let ch = 0; ch < numChannels; ch++) {
      const inputChannel = input[ch];
      const outputChannel = output[ch];
      if (!inputChannel || !outputChannel) continue;

      outputChannel.set(inputChannel);

      for (let f = 0; f < this.filters.length; f++) {
        this.filters[f].process(outputChannel, this.tempBuffer, ch);
        outputChannel.set(this.tempBuffer);
      }

      for (let i = 0; i < blockSize; i++) {
        this.outputGain += (this.targetOutputGain - this.outputGain) * this.gainSmoothingFactor;
        outputChannel[i] *= this.outputGain;
      }
    }

    return true;
  }
}

registerProcessor('vaneq-processor-test', VanEqProcessor);
`;

/**
 * Create a test tone buffer (1kHz sine wave)
 */
function createTestTone(
  sampleRate: number,
  durationSeconds: number,
  frequency: number = 1000,
  amplitude: number = 0.5
): Float32Array {
  const numSamples = Math.floor(sampleRate * durationSeconds);
  const buffer = new Float32Array(numSamples);
  for (let i = 0; i < numSamples; i++) {
    buffer[i] = amplitude * Math.sin((2 * Math.PI * frequency * i) / sampleRate);
  }
  return buffer;
}

/**
 * Calculate RMS of a buffer
 */
function calculateRMS(buffer: Float32Array): number {
  let sumSquares = 0;
  for (let i = 0; i < buffer.length; i++) {
    sumSquares += buffer[i] * buffer[i];
  }
  return Math.sqrt(sumSquares / buffer.length);
}

/**
 * Calculate max sample-by-sample difference between two buffers
 */
function maxDifference(a: Float32Array, b: Float32Array): number {
  const len = Math.min(a.length, b.length);
  let maxDiff = 0;
  for (let i = 0; i < len; i++) {
    const diff = Math.abs(a[i] - b[i]);
    if (diff > maxDiff) maxDiff = diff;
  }
  return maxDiff;
}

// Check if we're in a browser environment with AudioWorklet support
const hasAudioWorklet = typeof AudioWorkletNode !== 'undefined' && typeof OfflineAudioContext !== 'undefined';

describe.skipIf(!hasAudioWorklet)('VanEQ Unity Gain', () => {
  const SAMPLE_RATE = 48000;
  const DURATION = 0.5; // 500ms test duration
  let testTone: Float32Array;

  beforeAll(() => {
    testTone = createTestTone(SAMPLE_RATE, DURATION, 1000, 0.5);
  });

  it('should maintain exact unity gain when all bands disabled', async () => {
    const ctx = new OfflineAudioContext(1, testTone.length, SAMPLE_RATE);

    // Load worklet from blob
    const blob = new Blob([VANEQ_WORKLET_CODE], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    // Create nodes
    const source = ctx.createBufferSource();
    const inputBuffer = ctx.createBuffer(1, testTone.length, SAMPLE_RATE);
    inputBuffer.copyToChannel(testTone, 0);
    source.buffer = inputBuffer;

    const worklet = new AudioWorkletNode(ctx, 'vaneq-processor-test');

    // Send update with all bands disabled
    worklet.port.postMessage({
      type: 'update',
      bands: [
        { enabled: false, freqHz: 100, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 300, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 1000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 3000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 8000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 16000, gainDb: 0, q: 1 },
      ],
      outputGain: 0, // 0 dB
    });

    // Connect and render
    source.connect(worklet);
    worklet.connect(ctx.destination);
    source.start();

    const rendered = await ctx.startRendering();
    const output = rendered.getChannelData(0);

    // Skip first 128 samples to allow for smoothing settle
    const skipSamples = 128;
    const inputRMS = calculateRMS(testTone.slice(skipSamples));
    const outputRMS = calculateRMS(output.slice(skipSamples));

    // RMS should be identical (within floating point tolerance)
    const rmsDiffPercent = Math.abs(outputRMS - inputRMS) / inputRMS * 100;
    expect(rmsDiffPercent).toBeLessThan(0.1); // Less than 0.1% difference

    // Sample-by-sample difference should be near zero
    const maxDiff = maxDifference(testTone.slice(skipSamples), output.slice(skipSamples));
    expect(maxDiff).toBeLessThan(0.001); // Max 0.001 sample difference
  });

  it('should maintain unity gain with 0dB gain on enabled bands', async () => {
    const ctx = new OfflineAudioContext(1, testTone.length, SAMPLE_RATE);

    const blob = new Blob([VANEQ_WORKLET_CODE], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    const source = ctx.createBufferSource();
    const inputBuffer = ctx.createBuffer(1, testTone.length, SAMPLE_RATE);
    inputBuffer.copyToChannel(testTone, 0);
    source.buffer = inputBuffer;

    const worklet = new AudioWorkletNode(ctx, 'vaneq-processor-test');

    // Enable band with 0dB gain (should be acoustically transparent)
    worklet.port.postMessage({
      type: 'update',
      bands: [
        { enabled: true, freqHz: 1000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 300, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 1000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 3000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 8000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 16000, gainDb: 0, q: 1 },
      ],
      outputGain: 0,
    });

    source.connect(worklet);
    worklet.connect(ctx.destination);
    source.start();

    const rendered = await ctx.startRendering();
    const output = rendered.getChannelData(0);

    // Skip first 256 samples for filter settling
    const skipSamples = 256;
    const inputRMS = calculateRMS(testTone.slice(skipSamples));
    const outputRMS = calculateRMS(output.slice(skipSamples));

    // A bell filter at 0dB gain should be unity at all frequencies
    // Allow slightly more tolerance for filter processing
    const rmsDiffPercent = Math.abs(outputRMS - inputRMS) / inputRMS * 100;
    expect(rmsDiffPercent).toBeLessThan(1); // Less than 1% difference
  });

  it('should apply gain correctly when bands are active', async () => {
    const ctx = new OfflineAudioContext(1, testTone.length, SAMPLE_RATE);

    const blob = new Blob([VANEQ_WORKLET_CODE], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    const source = ctx.createBufferSource();
    const inputBuffer = ctx.createBuffer(1, testTone.length, SAMPLE_RATE);
    inputBuffer.copyToChannel(testTone, 0);
    source.buffer = inputBuffer;

    const worklet = new AudioWorkletNode(ctx, 'vaneq-processor-test');

    // Enable band with +6dB gain at test frequency
    worklet.port.postMessage({
      type: 'update',
      bands: [
        { enabled: true, freqHz: 1000, gainDb: 6, q: 1 },
        { enabled: false, freqHz: 300, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 1000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 3000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 8000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 16000, gainDb: 0, q: 1 },
      ],
      outputGain: 0,
    });

    source.connect(worklet);
    worklet.connect(ctx.destination);
    source.start();

    const rendered = await ctx.startRendering();
    const output = rendered.getChannelData(0);

    // Skip first 512 samples for filter settling
    const skipSamples = 512;
    const inputRMS = calculateRMS(testTone.slice(skipSamples));
    const outputRMS = calculateRMS(output.slice(skipSamples));

    // +6dB = 2x amplitude = 2x RMS (approximately)
    const expectedRatio = Math.pow(10, 6 / 20); // ~2.0
    const actualRatio = outputRMS / inputRMS;

    // Should be close to expected gain (within 20% tolerance for filter character)
    expect(actualRatio).toBeGreaterThan(expectedRatio * 0.8);
    expect(actualRatio).toBeLessThan(expectedRatio * 1.2);
  });

  it('output gain should apply correctly', async () => {
    const ctx = new OfflineAudioContext(1, testTone.length, SAMPLE_RATE);

    const blob = new Blob([VANEQ_WORKLET_CODE], { type: 'application/javascript' });
    const url = URL.createObjectURL(blob);
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);

    const source = ctx.createBufferSource();
    const inputBuffer = ctx.createBuffer(1, testTone.length, SAMPLE_RATE);
    inputBuffer.copyToChannel(testTone, 0);
    source.buffer = inputBuffer;

    const worklet = new AudioWorkletNode(ctx, 'vaneq-processor-test');

    // All bands disabled, but output gain +3dB
    worklet.port.postMessage({
      type: 'update',
      bands: [
        { enabled: false, freqHz: 100, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 300, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 1000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 3000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 8000, gainDb: 0, q: 1 },
        { enabled: false, freqHz: 16000, gainDb: 0, q: 1 },
      ],
      outputGain: 3, // +3 dB
    });

    source.connect(worklet);
    worklet.connect(ctx.destination);
    source.start();

    const rendered = await ctx.startRendering();
    const output = rendered.getChannelData(0);

    // Skip samples for gain smoothing to settle
    const skipSamples = 1024;
    const inputRMS = calculateRMS(testTone.slice(skipSamples));
    const outputRMS = calculateRMS(output.slice(skipSamples));

    // +3dB = ~1.41x amplitude
    const expectedRatio = Math.pow(10, 3 / 20);
    const actualRatio = outputRMS / inputRMS;

    // Should be close to +3dB (within 5% tolerance)
    expect(actualRatio).toBeGreaterThan(expectedRatio * 0.95);
    expect(actualRatio).toBeLessThan(expectedRatio * 1.05);
  });
});

// Pure unit tests that don't require AudioWorklet
describe('VanEQ Unity Gain - Unit Tests', () => {
  it('test tone generator produces correct amplitude', () => {
    const tone = createTestTone(48000, 0.1, 1000, 0.5);
    const rms = calculateRMS(tone);
    // RMS of sine wave = amplitude / sqrt(2)
    const expectedRMS = 0.5 / Math.sqrt(2);
    expect(Math.abs(rms - expectedRMS)).toBeLessThan(0.001);
  });

  it('maxDifference returns 0 for identical buffers', () => {
    const a = new Float32Array([0.1, 0.2, 0.3, 0.4]);
    const b = new Float32Array([0.1, 0.2, 0.3, 0.4]);
    expect(maxDifference(a, b)).toBe(0);
  });

  it('maxDifference detects differences', () => {
    const a = new Float32Array([0.1, 0.2, 0.3, 0.4]);
    const b = new Float32Array([0.1, 0.25, 0.3, 0.4]);
    expect(maxDifference(a, b)).toBeCloseTo(0.05, 5);
  });
});

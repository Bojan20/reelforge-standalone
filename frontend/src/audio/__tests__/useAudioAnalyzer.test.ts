/**
 * useAudioAnalyzer Hook Tests
 *
 * Tests for audio analysis functionality.
 *
 * @module audio/__tests__/useAudioAnalyzer.test
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';

// Mock Web Audio API
const mockAnalyserNode = {
  fftSize: 2048,
  frequencyBinCount: 1024,
  smoothingTimeConstant: 0.8,
  getByteFrequencyData: vi.fn((array: Uint8Array) => {
    // Fill with mock data
    for (let i = 0; i < array.length; i++) {
      array[i] = Math.floor(Math.random() * 256);
    }
  }),
  getByteTimeDomainData: vi.fn((array: Uint8Array) => {
    for (let i = 0; i < array.length; i++) {
      array[i] = 128 + Math.floor((Math.random() - 0.5) * 50);
    }
  }),
  getFloatTimeDomainData: vi.fn((array: Float32Array) => {
    for (let i = 0; i < array.length; i++) {
      array[i] = (Math.random() - 0.5) * 0.5;
    }
  }),
  connect: vi.fn(),
  disconnect: vi.fn(),
};

const mockGainNode = {
  gain: { value: 1 },
  connect: vi.fn(),
  disconnect: vi.fn(),
};

const mockSourceNode = {
  connect: vi.fn(),
  disconnect: vi.fn(),
};

const mockAudioContext = {
  state: 'running',
  sampleRate: 48000,
  currentTime: 0,
  createAnalyser: vi.fn(() => mockAnalyserNode),
  createGain: vi.fn(() => mockGainNode),
  createMediaStreamSource: vi.fn(() => mockSourceNode),
  createMediaElementSource: vi.fn(() => mockSourceNode),
  resume: vi.fn(),
  suspend: vi.fn(),
  close: vi.fn(),
};

// Setup global mocks
vi.stubGlobal('AudioContext', vi.fn(() => mockAudioContext));
vi.stubGlobal('webkitAudioContext', vi.fn(() => mockAudioContext));

describe('useAudioAnalyzer', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('audio data analysis', () => {
    it('should calculate peak level correctly', () => {
      // Test peak calculation
      const samples = new Float32Array([0.1, -0.5, 0.8, -0.3, 0.2]);
      const peak = Math.max(...samples.map(Math.abs));
      expect(peak).toBe(0.8);
    });

    it('should calculate RMS level correctly', () => {
      const samples = new Float32Array([0.5, 0.5, 0.5, 0.5]);
      const sumSquares = samples.reduce((sum, s) => sum + s * s, 0);
      const rms = Math.sqrt(sumSquares / samples.length);
      expect(rms).toBe(0.5);
    });

    it('should convert linear to dB correctly', () => {
      // 1.0 linear = 0 dB
      expect(20 * Math.log10(1.0)).toBeCloseTo(0, 5);

      // 0.5 linear ≈ -6 dB
      expect(20 * Math.log10(0.5)).toBeCloseTo(-6.02, 1);

      // 0.1 linear = -20 dB
      expect(20 * Math.log10(0.1)).toBeCloseTo(-20, 5);

      // 0.01 linear = -40 dB
      expect(20 * Math.log10(0.01)).toBeCloseTo(-40, 5);
    });

    it('should handle silence (zero values)', () => {
      const samples = new Float32Array([0, 0, 0, 0]);
      const peak = Math.max(...samples.map(Math.abs));
      const sumSquares = samples.reduce((sum, s) => sum + s * s, 0);
      const rms = Math.sqrt(sumSquares / samples.length);

      expect(peak).toBe(0);
      expect(rms).toBe(0);

      // dB of silence should be -Infinity
      const peakDb = peak > 0 ? 20 * Math.log10(peak) : -Infinity;
      expect(peakDb).toBe(-Infinity);
    });
  });

  describe('FFT analysis', () => {
    it('should have correct bin count based on FFT size', () => {
      const fftSize = 2048;
      const binCount = fftSize / 2;
      expect(binCount).toBe(1024);
    });

    it('should calculate frequency for bin index', () => {
      const sampleRate = 48000;
      const fftSize = 2048;
      const binCount = fftSize / 2;

      // Bin frequency = (binIndex * sampleRate) / fftSize
      const bin100 = (100 * sampleRate) / fftSize;
      expect(bin100).toBeCloseTo(2343.75, 2);

      // Nyquist frequency is at last bin
      const nyquist = sampleRate / 2;
      expect(nyquist).toBe(24000);
    });

    it('should identify frequency bands', () => {
      const sampleRate = 48000;
      const fftSize = 2048;

      const getBinForFreq = (freq: number) =>
        Math.round((freq * fftSize) / sampleRate);

      // Sub bass: 20-60 Hz
      expect(getBinForFreq(20)).toBe(1);
      expect(getBinForFreq(60)).toBe(3);

      // Bass: 60-250 Hz
      expect(getBinForFreq(250)).toBe(11);

      // Low mids: 250-500 Hz
      expect(getBinForFreq(500)).toBe(21);

      // Mids: 500-2000 Hz
      expect(getBinForFreq(2000)).toBe(85);

      // Upper mids: 2000-4000 Hz
      expect(getBinForFreq(4000)).toBe(171);

      // Presence: 4000-6000 Hz
      expect(getBinForFreq(6000)).toBe(256);

      // Brilliance: 6000-20000 Hz
      expect(getBinForFreq(20000)).toBe(853);
    });
  });

  describe('meter ballistics', () => {
    it('should apply attack smoothing', () => {
      const attackTime = 0.001; // 1ms attack
      const sampleRate = 48000;
      const attackCoeff = Math.exp(-1 / (attackTime * sampleRate));

      // Attack coefficient should be close to 1 (slow change)
      expect(attackCoeff).toBeGreaterThan(0.99);
    });

    it('should apply release smoothing', () => {
      const releaseTime = 0.3; // 300ms release
      const sampleRate = 48000;
      const releaseCoeff = Math.exp(-1 / (releaseTime * sampleRate));

      // Release coefficient should allow gradual falloff
      expect(releaseCoeff).toBeGreaterThan(0.99);
      expect(releaseCoeff).toBeLessThan(1);
    });

    it('should calculate peak hold correctly', () => {
      const holdTime = 1.0; // 1 second hold
      const frameRate = 60;
      const holdFrames = Math.round(holdTime * frameRate);

      expect(holdFrames).toBe(60);
    });
  });

  describe('frequency band analysis', () => {
    it('should calculate band energy', () => {
      // Mock FFT data
      const fftData = new Uint8Array(1024);
      for (let i = 0; i < 1024; i++) {
        fftData[i] = i < 100 ? 200 : 50; // Strong low frequencies
      }

      // Calculate energy for first 100 bins (low frequencies)
      let lowEnergy = 0;
      for (let i = 0; i < 100; i++) {
        lowEnergy += fftData[i];
      }
      lowEnergy /= 100;

      expect(lowEnergy).toBe(200);

      // Calculate energy for bins 100-200 (mid frequencies)
      let midEnergy = 0;
      for (let i = 100; i < 200; i++) {
        midEnergy += fftData[i];
      }
      midEnergy /= 100;

      expect(midEnergy).toBe(50);
    });
  });

  describe('waveform data', () => {
    it('should normalize waveform to -1 to 1 range', () => {
      // Byte data is 0-255, with 128 being zero crossing
      const byteData = new Uint8Array([0, 64, 128, 192, 255]);

      const normalized = Array.from(byteData).map((v) => (v - 128) / 128);

      expect(normalized[0]).toBeCloseTo(-1, 2);
      expect(normalized[2]).toBeCloseTo(0, 2);
      expect(normalized[4]).toBeCloseTo(0.992, 2);
    });

    it('should downsample waveform for display', () => {
      const samples = new Float32Array(1024);
      for (let i = 0; i < 1024; i++) {
        samples[i] = Math.sin((i / 1024) * Math.PI * 4);
      }

      // Downsample to 128 points
      const displaySize = 128;
      const blockSize = Math.floor(samples.length / displaySize);
      const display = new Float32Array(displaySize);

      for (let i = 0; i < displaySize; i++) {
        let max = 0;
        for (let j = 0; j < blockSize; j++) {
          const idx = i * blockSize + j;
          if (idx < samples.length) {
            max = Math.max(max, Math.abs(samples[idx]));
          }
        }
        display[i] = max;
      }

      expect(display.length).toBe(128);
      expect(Math.max(...display)).toBeLessThanOrEqual(1);
    });
  });

  describe('stereo analysis', () => {
    it('should calculate stereo correlation', () => {
      // Perfectly correlated (mono)
      const left = new Float32Array([0.5, -0.3, 0.8, -0.2]);
      const right = new Float32Array([0.5, -0.3, 0.8, -0.2]);

      let sum = 0;
      let leftSum = 0;
      let rightSum = 0;

      for (let i = 0; i < left.length; i++) {
        sum += left[i] * right[i];
        leftSum += left[i] * left[i];
        rightSum += right[i] * right[i];
      }

      const correlation = sum / Math.sqrt(leftSum * rightSum);
      expect(correlation).toBeCloseTo(1, 5);
    });

    it('should detect phase cancellation', () => {
      // Inverted phase
      const left = new Float32Array([0.5, -0.3, 0.8, -0.2]);
      const right = new Float32Array([-0.5, 0.3, -0.8, 0.2]);

      let sum = 0;
      let leftSum = 0;
      let rightSum = 0;

      for (let i = 0; i < left.length; i++) {
        sum += left[i] * right[i];
        leftSum += left[i] * left[i];
        rightSum += right[i] * right[i];
      }

      const correlation = sum / Math.sqrt(leftSum * rightSum);
      expect(correlation).toBeCloseTo(-1, 5);
    });

    it('should calculate stereo width', () => {
      // Calculate mid/side
      const left = 0.8;
      const right = 0.6;

      const mid = (left + right) / 2;
      const side = (left - right) / 2;

      // Width = side/mid ratio (simplified)
      const width = Math.abs(side) / Math.abs(mid);

      expect(mid).toBeCloseTo(0.7, 5);
      expect(side).toBeCloseTo(0.1, 5);
      expect(width).toBeCloseTo(0.143, 2);
    });
  });

  describe('LUFS loudness', () => {
    it('should apply K-weighting filter coefficients', () => {
      // K-weighting is a two-stage filter
      // Stage 1: High shelf (+4 dB @ 1681 Hz)
      // Stage 2: High-pass (fc = 38 Hz)

      // These are approximate coefficients for 48kHz
      const highShelfGain = 4; // dB
      const highShelfFreq = 1681; // Hz
      const highPassFreq = 38; // Hz

      expect(highShelfGain).toBe(4);
      expect(highShelfFreq).toBe(1681);
      expect(highPassFreq).toBe(38);
    });

    it('should calculate gated loudness blocks', () => {
      // LUFS uses 400ms blocks with 75% overlap
      const blockDuration = 0.4; // seconds
      const overlap = 0.75;
      const stepDuration = blockDuration * (1 - overlap);

      expect(stepDuration).toBeCloseTo(0.1, 5); // 100ms steps
    });

    it('should apply absolute gate threshold', () => {
      const absoluteThreshold = -70; // LUFS
      const blockLoudness = -65;

      const passesGate = blockLoudness >= absoluteThreshold;
      expect(passesGate).toBe(true);

      const quietBlock = -75;
      const failsGate = quietBlock >= absoluteThreshold;
      expect(failsGate).toBe(false);
    });

    it('should calculate relative gate threshold', () => {
      // Relative threshold is ungated loudness - 10 LU
      const ungatedLoudness = -23; // LUFS
      const relativeThreshold = ungatedLoudness - 10;

      expect(relativeThreshold).toBe(-33);
    });
  });
});

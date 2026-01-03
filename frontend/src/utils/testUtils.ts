/**
 * ReelForge Test Utilities
 *
 * Helpers for testing timeline, audio, and plugin components.
 *
 * @module utils/testUtils
 */

import type { Track, Clip, Marker, TimelineState, AudioClip } from '../timeline/types';

// ============ Mock Data Generators ============

let mockIdCounter = 0;

/**
 * Generate a unique mock ID.
 */
export function mockId(prefix = 'mock'): string {
  return `${prefix}_${++mockIdCounter}`;
}

/**
 * Reset mock ID counter.
 */
export function resetMockIds(): void {
  mockIdCounter = 0;
}

/**
 * Create a mock track.
 */
export function createMockTrack(overrides: Partial<Track> = {}): Track {
  return {
    id: mockId('track'),
    name: 'Test Track',
    type: 'audio',
    color: '#4a9eff',
    height: 80,
    muted: false,
    solo: false,
    armed: false,
    volume: 1,
    pan: 0,
    expanded: false,
    parentId: null,
    order: 0,
    clips: [],
    locked: false,
    visible: true,
    ...overrides,
  };
}

/**
 * Create a mock clip.
 */
export function createMockClip(overrides: Partial<Clip> = {}): Clip {
  return {
    id: mockId('clip'),
    type: 'audio',
    name: 'Test Clip',
    startTime: 0,
    duration: 5,
    sourceOffset: 0,
    color: null,
    gain: 1,
    muted: false,
    selected: false,
    locked: false,
    fadeIn: 0,
    fadeOut: 0,
    fadeInCurve: 'linear',
    fadeOutCurve: 'linear',
    ...overrides,
  };
}

/**
 * Create a mock audio clip with waveform.
 */
export function createMockAudioClip(overrides: Partial<AudioClip> = {}): AudioClip {
  return {
    ...createMockClip(),
    type: 'audio',
    audioSourceId: mockId('audio'),
    waveformData: generateMockWaveform(512),
    pitchShift: 0,
    timeStretch: 1,
    preservePitch: true,
    ...overrides,
  } as AudioClip;
}

/**
 * Create a mock marker.
 */
export function createMockMarker(overrides: Partial<Marker> = {}): Marker {
  return {
    id: mockId('marker'),
    type: 'marker',
    name: 'Test Marker',
    position: 0,
    color: '#ffaa00',
    ...overrides,
  };
}

/**
 * Create mock timeline state.
 */
export function createMockTimelineState(overrides: Partial<TimelineState> = {}): TimelineState {
  return {
    playheadPosition: 0,
    visibleStart: 0,
    visibleEnd: 30,
    pixelsPerSecond: 50,
    isPlaying: false,
    loopEnabled: false,
    loopStart: 0,
    loopEnd: 10,
    selection: null,
    snapEnabled: true,
    gridDivision: 0.25,
    sampleRate: 48000,
    bpm: 120,
    timeSignatureNum: 4,
    timeSignatureDen: 4,
    ...overrides,
  };
}

// ============ Mock Audio Data ============

/**
 * Generate mock waveform data.
 */
export function generateMockWaveform(length = 512): Float32Array {
  const data = new Float32Array(length);
  const now = Date.now() / 1000;

  for (let i = 0; i < length; i++) {
    const t = i / length;
    // Simple sine wave with harmonics
    data[i] =
      Math.sin(t * Math.PI * 4 + now) * 0.5 +
      Math.sin(t * Math.PI * 8 + now * 2) * 0.25 +
      Math.sin(t * Math.PI * 16 + now * 3) * 0.125 +
      (Math.random() - 0.5) * 0.1;
  }

  return data;
}

/**
 * Generate mock FFT data.
 */
export function generateMockFFT(binCount = 1024): Uint8Array {
  const data = new Uint8Array(binCount);
  const now = Date.now() / 1000;

  for (let i = 0; i < binCount; i++) {
    const freq = i / binCount;
    // Pink noise-ish falloff
    let value = 200 - freq * 150;
    value += Math.sin(freq * 20 + now * 3) * 20;
    value += Math.random() * 10;
    data[i] = Math.max(0, Math.min(255, value));
  }

  return data;
}

/**
 * Generate mock audio levels.
 */
export function generateMockLevels(): {
  peak: number;
  rms: number;
  peakDb: number;
  rmsDb: number;
  peakL: number;
  peakR: number;
} {
  const peak = 0.7 + Math.random() * 0.2;
  const rms = peak * 0.7;

  return {
    peak,
    rms,
    peakDb: 20 * Math.log10(peak),
    rmsDb: 20 * Math.log10(rms),
    peakL: peak * (0.9 + Math.random() * 0.2),
    peakR: peak * (0.9 + Math.random() * 0.2),
  };
}

// ============ Test Scenarios ============

/**
 * Create a test timeline with multiple tracks and clips.
 */
export function createTestTimeline(trackCount = 4, clipsPerTrack = 3): {
  tracks: Track[];
  markers: Marker[];
  state: TimelineState;
} {
  const tracks: Track[] = [];
  const colors = ['#4a9eff', '#ff6b6b', '#51cf66', '#ffd43b', '#be4bdb', '#20c997'];

  for (let t = 0; t < trackCount; t++) {
    const clips: Clip[] = [];

    for (let c = 0; c < clipsPerTrack; c++) {
      clips.push(
        createMockClip({
          name: `Clip ${t + 1}.${c + 1}`,
          startTime: c * 8 + Math.random() * 2,
          duration: 4 + Math.random() * 4,
        })
      );
    }

    tracks.push(
      createMockTrack({
        name: `Track ${t + 1}`,
        color: colors[t % colors.length],
        order: t,
        clips,
      })
    );
  }

  const markers: Marker[] = [
    createMockMarker({ name: 'Start', position: 0 }),
    createMockMarker({ name: 'Chorus', position: 16, color: '#ff6b6b' }),
    createMockMarker({ name: 'Bridge', position: 32, color: '#51cf66' }),
  ];

  return {
    tracks,
    markers,
    state: createMockTimelineState(),
  };
}

// ============ Assertion Helpers ============

/**
 * Assert two numbers are approximately equal.
 */
export function assertApproxEqual(
  actual: number,
  expected: number,
  tolerance = 0.001,
  message = ''
): void {
  const diff = Math.abs(actual - expected);
  if (diff > tolerance) {
    throw new Error(
      `${message ? message + ': ' : ''}Expected ${expected}, got ${actual} (diff: ${diff})`
    );
  }
}

/**
 * Assert a value is within range.
 */
export function assertInRange(
  value: number,
  min: number,
  max: number,
  message = ''
): void {
  if (value < min || value > max) {
    throw new Error(
      `${message ? message + ': ' : ''}Expected ${value} to be in range [${min}, ${max}]`
    );
  }
}

/**
 * Assert an array has expected length.
 */
export function assertLength<T>(
  arr: T[],
  expectedLength: number,
  message = ''
): void {
  if (arr.length !== expectedLength) {
    throw new Error(
      `${message ? message + ': ' : ''}Expected length ${expectedLength}, got ${arr.length}`
    );
  }
}

// ============ Timing Helpers ============

/**
 * Wait for a specified duration.
 */
export function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wait for next animation frame.
 */
export function waitFrame(): Promise<number> {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

/**
 * Wait for multiple animation frames.
 */
export async function waitFrames(count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await waitFrame();
  }
}

/**
 * Wait until condition is true.
 */
export async function waitUntil(
  condition: () => boolean,
  timeout = 5000,
  interval = 50
): Promise<void> {
  const start = Date.now();

  while (!condition()) {
    if (Date.now() - start > timeout) {
      throw new Error('waitUntil timeout');
    }
    await wait(interval);
  }
}

// ============ Mock Event Helpers ============

/**
 * Create a mock mouse event.
 */
export function createMockMouseEvent(
  type: string,
  options: Partial<MouseEvent> = {}
): MouseEvent {
  return new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: 0,
    clientY: 0,
    ...options,
  });
}

/**
 * Create a mock keyboard event.
 */
export function createMockKeyboardEvent(
  type: string,
  key: string,
  options: Partial<KeyboardEvent> = {}
): KeyboardEvent {
  return new KeyboardEvent(type, {
    bubbles: true,
    cancelable: true,
    key,
    ...options,
  });
}

/**
 * Create a mock wheel event.
 */
export function createMockWheelEvent(
  deltaX: number,
  deltaY: number,
  options: Partial<WheelEvent> = {}
): WheelEvent {
  return new WheelEvent('wheel', {
    bubbles: true,
    cancelable: true,
    deltaX,
    deltaY,
    ...options,
  });
}

// ============ Console Helpers ============

/**
 * Capture console output.
 */
export function captureConsole(): {
  logs: string[];
  warnings: string[];
  errors: string[];
  restore: () => void;
} {
  const logs: string[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];

  const originalLog = console.log;
  const originalWarn = console.warn;
  const originalError = console.error;

  console.log = (...args) => logs.push(args.join(' '));
  console.warn = (...args) => warnings.push(args.join(' '));
  console.error = (...args) => errors.push(args.join(' '));

  return {
    logs,
    warnings,
    errors,
    restore: () => {
      console.log = originalLog;
      console.warn = originalWarn;
      console.error = originalError;
    },
  };
}

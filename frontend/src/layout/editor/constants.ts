/**
 * Editor Constants
 *
 * Shared constants for the LayoutDemo editor.
 *
 * @module layout/editor/constants
 */

import type { BusState } from './types';

// ============ Demo Bus Configuration ============

export const DEMO_BUSES: BusState[] = [
  { id: 'sfx', name: 'SFX', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'music', name: 'Music', volume: 0.8, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'voice', name: 'Voice', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'ambient', name: 'Ambient', volume: 0.7, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'master', name: 'Master', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, isMaster: true, inserts: [] },
];

// ============ Track Colors ============

export const TRACK_COLORS = [
  '#e74c3c', '#9b59b6', '#3498db', '#2ecc71', '#f39c12',
  '#1abc9c', '#e67e22', '#c0392b', '#8e44ad', '#27ae60',
];

// ============ Session Storage Keys ============

export const STORAGE_KEYS = {
  SESSION: 'reelforge_session',
  AUDIO_META: 'reelforge_audio_meta',
} as const;

// ============ Default Values ============

export const DEFAULT_BPM = 120;
export const DEFAULT_SAMPLE_RATE = 48000;
export const DEFAULT_BUFFER_SIZE = 256;

// ============ Limits ============

export const MAX_TRACKS = 64;
export const MAX_INSERTS_PER_BUS = 8;
export const MAX_SENDS_PER_CHANNEL = 8;
export const MAX_VOICES = 256;
export const MAX_UNDO_HISTORY = 100;

// ============ Timing ============

export const METER_UPDATE_INTERVAL = 16; // ~60fps
export const AUTOSAVE_INTERVAL = 60000; // 1 minute
export const PEAK_HOLD_TIME = 2000; // 2 seconds
export const CLIP_INDICATOR_TIME = 3000; // 3 seconds

// ============ Audio Analysis ============

export const FFT_SIZE = 2048;
export const MIN_FREQUENCY = 20;
export const MAX_FREQUENCY = 20000;
export const WAVEFORM_SAMPLES = 200;

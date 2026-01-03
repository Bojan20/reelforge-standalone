/**
 * ReelForge Timeline Types
 *
 * Core type definitions for the timeline/sequencer system.
 *
 * @module timeline/types
 */

// ============ Time Units ============

/** Time in seconds */
export type Seconds = number;

/** Time in samples */
export type Samples = number;

/** Time in beats */
export type Beats = number;

/** Time in bars:beats:ticks format */
export interface BarsBeatsTicks {
  bars: number;
  beats: number;
  ticks: number;
}

// ============ Timeline State ============

export interface TimelineState {
  /** Current playhead position in seconds */
  playheadPosition: Seconds;
  /** Visible time range start */
  visibleStart: Seconds;
  /** Visible time range end */
  visibleEnd: Seconds;
  /** Pixels per second (zoom level) */
  pixelsPerSecond: number;
  /** Whether timeline is playing */
  isPlaying: boolean;
  /** Whether loop is enabled */
  loopEnabled: boolean;
  /** Loop start position */
  loopStart: Seconds;
  /** Loop end position */
  loopEnd: Seconds;
  /** Current selection range (if any) */
  selection: TimeRange | null;
  /** Snap to grid enabled */
  snapEnabled: boolean;
  /** Grid division (e.g., 1/4, 1/8, 1/16) */
  gridDivision: number;
  /** Sample rate for conversions */
  sampleRate: number;
  /** BPM for beat grid */
  bpm: number;
  /** Time signature numerator */
  timeSignatureNum: number;
  /** Time signature denominator */
  timeSignatureDen: number;
}

export interface TimeRange {
  start: Seconds;
  end: Seconds;
}

// ============ Tracks ============

export type TrackType = 'audio' | 'midi' | 'bus' | 'master' | 'folder';

export interface Track {
  /** Unique track ID */
  id: string;
  /** Track display name */
  name: string;
  /** Track type */
  type: TrackType;
  /** Track color (hex) */
  color: string;
  /** Track height in pixels */
  height: number;
  /** Whether track is muted */
  muted: boolean;
  /** Whether track is soloed */
  solo: boolean;
  /** Whether track is armed for recording */
  armed: boolean;
  /** Track volume (0-1, 1 = 0dB) */
  volume: number;
  /** Track pan (-1 to 1) */
  pan: number;
  /** Whether track is expanded (shows lanes) */
  expanded: boolean;
  /** Parent folder track ID (if nested) */
  parentId: string | null;
  /** Track order index */
  order: number;
  /** Clips/regions on this track */
  clips: Clip[];
  /** Track is locked (no editing) */
  locked: boolean;
  /** Track is visible */
  visible: boolean;
}

// ============ Clips/Regions ============

export type ClipType = 'audio' | 'midi' | 'automation';

export interface Clip {
  /** Unique clip ID */
  id: string;
  /** Clip type */
  type: ClipType;
  /** Clip display name */
  name: string;
  /** Start position on timeline (seconds) */
  startTime: Seconds;
  /** Duration (seconds) */
  duration: Seconds;
  /** Offset into source (for trimmed clips) */
  sourceOffset: Seconds;
  /** Clip color (hex, or null to use track color) */
  color: string | null;
  /** Clip gain/volume (multiplier) */
  gain: number;
  /** Whether clip is muted */
  muted: boolean;
  /** Whether clip is selected */
  selected: boolean;
  /** Whether clip is locked */
  locked: boolean;
  /** Fade in duration (seconds) */
  fadeIn: number;
  /** Fade out duration (seconds) */
  fadeOut: number;
  /** Fade in curve type */
  fadeInCurve: FadeCurve;
  /** Fade out curve type */
  fadeOutCurve: FadeCurve;
}

export type FadeCurve = 'linear' | 'exponential' | 'logarithmic' | 's-curve';

export interface AudioClip extends Clip {
  type: 'audio';
  /** Reference to audio file/buffer */
  audioSourceId: string;
  /** Waveform data for display (normalized peaks) */
  waveformData?: Float32Array;
  /** Pitch shift in semitones */
  pitchShift: number;
  /** Time stretch ratio (1 = normal) */
  timeStretch: number;
  /** Whether to preserve pitch when stretching */
  preservePitch: boolean;
}

export interface MidiClip extends Clip {
  type: 'midi';
  /** MIDI notes in this clip */
  notes: MidiNote[];
}

export interface MidiNote {
  /** Note number (0-127) */
  pitch: number;
  /** Velocity (0-127) */
  velocity: number;
  /** Start time relative to clip start */
  startTime: Seconds;
  /** Duration */
  duration: Seconds;
}

export interface AutomationClip extends Clip {
  type: 'automation';
  /** Parameter being automated */
  paramId: string;
  /** Automation points */
  points: AutomationPoint[];
}

export interface AutomationPoint {
  /** Time position */
  time: Seconds;
  /** Value (normalized 0-1) */
  value: number;
  /** Curve type to next point */
  curve: AutomationCurve;
}

export type AutomationCurve = 'linear' | 'exponential' | 'logarithmic' | 'step';

// ============ Markers ============

export type MarkerType = 'marker' | 'loop' | 'punch';

export interface Marker {
  /** Unique marker ID */
  id: string;
  /** Marker type */
  type: MarkerType;
  /** Marker name */
  name: string;
  /** Position in seconds */
  position: Seconds;
  /** Color (hex) */
  color: string;
  /** End position for range markers */
  endPosition?: Seconds;
}

// ============ Grid & Snap ============

export interface GridSettings {
  /** Grid division (1 = whole note, 0.25 = quarter, 0.125 = eighth, etc.) */
  division: number;
  /** Whether grid lines are visible */
  visible: boolean;
  /** Grid line color */
  color: string;
  /** Grid line opacity */
  opacity: number;
}

export interface SnapSettings {
  /** Snap enabled */
  enabled: boolean;
  /** Snap to grid */
  toGrid: boolean;
  /** Snap to clip edges */
  toClips: boolean;
  /** Snap to markers */
  toMarkers: boolean;
  /** Snap to playhead */
  toPlayhead: boolean;
  /** Snap strength (pixels) */
  strength: number;
}

// ============ Zoom Levels ============

export interface ZoomPreset {
  name: string;
  pixelsPerSecond: number;
}

export const ZOOM_PRESETS: ZoomPreset[] = [
  { name: 'Full', pixelsPerSecond: 10 },
  { name: 'Overview', pixelsPerSecond: 25 },
  { name: 'Normal', pixelsPerSecond: 50 },
  { name: 'Detail', pixelsPerSecond: 100 },
  { name: 'Fine', pixelsPerSecond: 200 },
  { name: 'Sample', pixelsPerSecond: 500 },
];

// ============ Transport ============

export interface TransportState {
  isPlaying: boolean;
  isRecording: boolean;
  isPaused: boolean;
  position: Seconds;
  tempo: number;
  timeSignature: [number, number];
}

// ============ Timeline Actions ============

export type TimelineAction =
  | { type: 'SET_PLAYHEAD'; position: Seconds }
  | { type: 'SET_ZOOM'; pixelsPerSecond: number }
  | { type: 'SET_VISIBLE_RANGE'; start: Seconds; end: Seconds }
  | { type: 'SET_SELECTION'; selection: TimeRange | null }
  | { type: 'SET_LOOP'; enabled: boolean; start?: Seconds; end?: Seconds }
  | { type: 'SET_SNAP'; enabled: boolean }
  | { type: 'SET_GRID'; division: number }
  | { type: 'ADD_TRACK'; track: Track }
  | { type: 'REMOVE_TRACK'; trackId: string }
  | { type: 'UPDATE_TRACK'; trackId: string; updates: Partial<Track> }
  | { type: 'REORDER_TRACKS'; trackIds: string[] }
  | { type: 'ADD_CLIP'; trackId: string; clip: Clip }
  | { type: 'REMOVE_CLIP'; trackId: string; clipId: string }
  | { type: 'UPDATE_CLIP'; trackId: string; clipId: string; updates: Partial<Clip> }
  | { type: 'MOVE_CLIP'; trackId: string; clipId: string; newStart: Seconds; newTrackId?: string }
  | { type: 'SPLIT_CLIP'; trackId: string; clipId: string; splitPoint: Seconds }
  | { type: 'ADD_MARKER'; marker: Marker }
  | { type: 'REMOVE_MARKER'; markerId: string }
  | { type: 'UPDATE_MARKER'; markerId: string; updates: Partial<Marker> };

// ============ Default Values ============

export const DEFAULT_TIMELINE_STATE: TimelineState = {
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
  gridDivision: 0.25, // Quarter notes
  sampleRate: 48000,
  bpm: 120,
  timeSignatureNum: 4,
  timeSignatureDen: 4,
};

export const DEFAULT_TRACK: Omit<Track, 'id' | 'name' | 'order'> = {
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
  clips: [],
  locked: false,
  visible: true,
};

// ============ Utility Functions ============

/**
 * Convert seconds to samples.
 */
export function secondsToSamples(seconds: Seconds, sampleRate: number): Samples {
  return Math.round(seconds * sampleRate);
}

/**
 * Convert samples to seconds.
 */
export function samplesToSeconds(samples: Samples, sampleRate: number): Seconds {
  return samples / sampleRate;
}

/**
 * Convert seconds to beats.
 */
export function secondsToBeats(seconds: Seconds, bpm: number): Beats {
  return (seconds * bpm) / 60;
}

/**
 * Convert beats to seconds.
 */
export function beatsToSeconds(beats: Beats, bpm: number): Seconds {
  return (beats * 60) / bpm;
}

/**
 * Convert seconds to bars:beats:ticks.
 */
export function secondsToBarsBeatsTicks(
  seconds: Seconds,
  bpm: number,
  timeSignatureNum: number,
  ticksPerBeat = 480
): BarsBeatsTicks {
  const totalBeats = secondsToBeats(seconds, bpm);
  const bars = Math.floor(totalBeats / timeSignatureNum);
  const beatsInBar = totalBeats - bars * timeSignatureNum;
  const beats = Math.floor(beatsInBar);
  const ticks = Math.round((beatsInBar - beats) * ticksPerBeat);

  return { bars: bars + 1, beats: beats + 1, ticks };
}

/**
 * Format time as MM:SS.ms
 */
export function formatTime(seconds: Seconds): string {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins}:${secs.toFixed(2).padStart(5, '0')}`;
}

/**
 * Format time as bars:beats:ticks
 */
export function formatBarsBeatsTicks(bbt: BarsBeatsTicks): string {
  return `${bbt.bars}:${bbt.beats}:${bbt.ticks.toString().padStart(3, '0')}`;
}

/**
 * Quantize time to grid.
 */
export function quantizeToGrid(
  time: Seconds,
  gridDivision: number,
  bpm: number
): Seconds {
  const beatDuration = 60 / bpm;
  const gridSize = beatDuration * gridDivision * 4; // gridDivision is fraction of whole note
  return Math.round(time / gridSize) * gridSize;
}

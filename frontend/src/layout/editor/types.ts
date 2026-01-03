/**
 * Editor Types
 *
 * Shared types for the LayoutDemo editor.
 *
 * @module layout/editor/types
 */

import type { TimelineTrack, TimelineClip, Crossfade } from '../Timeline';
import type { MusicLayer, BlendCurve, MusicState } from '../LayeredMusicEditor';
import type { EventRoute, RouteAction, RouteBus, RoutesConfig } from '../../core/routesTypes';
import type { PoolAsset } from '../../components/AudioPoolPanel';
import type { AudioFileInfo } from '../../components/AudioBrowser';

// ============ Bus Types ============

export interface BusInsertSlot {
  id: string;
  name: string;
  type: 'eq' | 'comp' | 'reverb' | 'delay' | 'filter' | 'fx' | 'utility' | 'custom';
  bypassed?: boolean;
}

export interface BusState {
  id: string;
  name: string;
  volume: number;
  pan: number;
  muted: boolean;
  soloed: boolean;
  meterLevel: number;
  inserts: BusInsertSlot[];
  isMaster?: boolean;
}

// ============ Session Types ============

export interface SessionState {
  selectedEventName: string | null;
  selectedActionIndex: number | null;
  activeLowerTab: string;
  routes: unknown | null;
  timestamp: number;
}

export interface AudioFileMeta {
  id: string;
  name: string;
  duration: number;
  waveform: number[];
}

// ============ Drag & Drop Types ============

export interface DragItem {
  id: string;
  name: string;
  duration: number;
  type?: 'audio' | 'clip' | 'asset';
  waveform?: number[];
  blobUrl?: string;
  originalFile?: File;
  buffer?: AudioBuffer;
}

// ============ Plugin Types ============

export interface PluginDefinition {
  id: string;
  name: string;
  category: 'eq' | 'dynamics' | 'reverb' | 'delay' | 'modulation' | 'utility' | 'custom';
  manufacturer?: string;
  version?: string;
}

export interface PluginPickerState {
  isOpen: boolean;
  busId: string | null;
  slotIndex: number;
  position: { x: number; y: number };
}

export interface ActivePluginEditor {
  busId: string;
  slotIndex: number;
  plugin: BusInsertSlot;
  position: { x: number; y: number };
}

// ============ Import Types ============

export interface ImportedFile {
  id: string;
  name: string;
  file: File;
  buffer: AudioBuffer;
  duration: number;
  waveform: number[];
  blobUrl: string;
}

export interface PendingImport {
  file: AudioFileInfo;
  options?: unknown;
}

// ============ Selection Types ============

export interface EditorSelection {
  eventName: string | null;
  actionIndex: number | null;
  actionIndices: number[];
  clipId: string | null;
  busId: string | null;
}

// ============ Playback Types ============

export interface PlaybackState {
  isPlaying: boolean;
  isRecording: boolean;
  currentTime: number;
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
}

// ============ Re-exports ============

export type {
  TimelineTrack,
  TimelineClip,
  Crossfade,
  MusicLayer,
  BlendCurve,
  MusicState,
  EventRoute,
  RouteAction,
  RouteBus,
  RoutesConfig,
  PoolAsset,
  AudioFileInfo,
};

/**
 * Global State Atoms
 *
 * Centralized Jotai atoms for application state.
 * Organized by domain for clear separation.
 *
 * @module state/atoms
 */

import { atom } from 'jotai';
import { atomWithStorage } from 'jotai/utils';

// ============ Editor State ============

export type EditorMode = 'welcome' | 'editor' | 'showcase' | 'legacy';

export const editorModeAtom = atomWithStorage<EditorMode>('rf_editor_mode', 'welcome');

export const isDarkModeAtom = atomWithStorage('rf_dark_mode', true);

// ============ Playback State ============

export interface PlaybackState {
  isPlaying: boolean;
  isRecording: boolean;
  currentTime: number;
  bpm: number;
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
  metronomeEnabled: boolean;
  snapEnabled: boolean;
}

export const playbackAtom = atom<PlaybackState>({
  isPlaying: false,
  isRecording: false,
  currentTime: 0,
  bpm: 120,
  loopEnabled: false,
  loopStart: 0,
  loopEnd: 10,
  metronomeEnabled: false,
  snapEnabled: true,
});

// Derived atoms for specific playback properties
export const isPlayingAtom = atom(
  (get) => get(playbackAtom).isPlaying,
  (get, set, isPlaying: boolean) => {
    set(playbackAtom, { ...get(playbackAtom), isPlaying });
  }
);

export const currentTimeAtom = atom(
  (get) => get(playbackAtom).currentTime,
  (get, set, currentTime: number) => {
    set(playbackAtom, { ...get(playbackAtom), currentTime });
  }
);

export const bpmAtom = atom(
  (get) => get(playbackAtom).bpm,
  (get, set, bpm: number) => {
    set(playbackAtom, { ...get(playbackAtom), bpm });
  }
);

// ============ Selection State ============

export interface SelectionState {
  selectedEventName: string | null;
  selectedActionIndex: number | null;
  selectedActionIndices: number[];
  selectedClipId: string | null;
  selectedTrackId: string | null;
  selectedBusId: string | null;
}

export const selectionAtom = atom<SelectionState>({
  selectedEventName: null,
  selectedActionIndex: null,
  selectedActionIndices: [],
  selectedClipId: null,
  selectedTrackId: null,
  selectedBusId: null,
});

// Derived atoms
export const selectedEventNameAtom = atom(
  (get) => get(selectionAtom).selectedEventName,
  (get, set, selectedEventName: string | null) => {
    set(selectionAtom, { ...get(selectionAtom), selectedEventName, selectedActionIndex: null });
  }
);

export const selectedClipIdAtom = atom(
  (get) => get(selectionAtom).selectedClipId,
  (get, set, selectedClipId: string | null) => {
    set(selectionAtom, { ...get(selectionAtom), selectedClipId });
  }
);

// ============ UI State ============

export interface UIState {
  leftZoneVisible: boolean;
  rightZoneVisible: boolean;
  lowerZoneVisible: boolean;
  lowerZoneHeight: number;
  activeLowerTab: string;
  inspectorWidth: number;
  browserWidth: number;
}

export const uiAtom = atomWithStorage<UIState>('rf_ui_state', {
  leftZoneVisible: true,
  rightZoneVisible: true,
  lowerZoneVisible: true,
  lowerZoneHeight: 300,
  activeLowerTab: 'mixer',
  inspectorWidth: 280,
  browserWidth: 250,
});

// Derived atoms for UI visibility
export const leftZoneVisibleAtom = atom(
  (get) => get(uiAtom).leftZoneVisible,
  (get, set, visible: boolean) => {
    set(uiAtom, { ...get(uiAtom), leftZoneVisible: visible });
  }
);

export const rightZoneVisibleAtom = atom(
  (get) => get(uiAtom).rightZoneVisible,
  (get, set, visible: boolean) => {
    set(uiAtom, { ...get(uiAtom), rightZoneVisible: visible });
  }
);

export const lowerZoneVisibleAtom = atom(
  (get) => get(uiAtom).lowerZoneVisible,
  (get, set, visible: boolean) => {
    set(uiAtom, { ...get(uiAtom), lowerZoneVisible: visible });
  }
);

export const activeLowerTabAtom = atom(
  (get) => get(uiAtom).activeLowerTab,
  (get, set, tab: string) => {
    set(uiAtom, { ...get(uiAtom), activeLowerTab: tab });
  }
);

// ============ Mixer State ============

export interface BusState {
  id: string;
  name: string;
  volume: number;
  pan: number;
  muted: boolean;
  soloed: boolean;
  isMaster?: boolean;
}

export const busesAtom = atom<BusState[]>([
  { id: 'sfx', name: 'SFX', volume: 1, pan: 0, muted: false, soloed: false },
  { id: 'music', name: 'Music', volume: 0.8, pan: 0, muted: false, soloed: false },
  { id: 'voice', name: 'Voice', volume: 1, pan: 0, muted: false, soloed: false },
  { id: 'ambient', name: 'Ambient', volume: 0.7, pan: 0, muted: false, soloed: false },
  { id: 'master', name: 'Master', volume: 1, pan: 0, muted: false, soloed: false, isMaster: true },
]);

// Helper to update a specific bus
export const updateBusAtom = atom(
  null,
  (get, set, { busId, updates }: { busId: string; updates: Partial<BusState> }) => {
    set(busesAtom, get(busesAtom).map(bus =>
      bus.id === busId ? { ...bus, ...updates } : bus
    ));
  }
);

// Check if any bus is soloed
export const hasAnySoloAtom = atom(
  (get) => get(busesAtom).some(bus => bus.soloed)
);

// ============ Timeline State ============

export interface TimelineViewState {
  zoom: number; // pixels per second
  scrollX: number;
  scrollY: number;
  gridVisible: boolean;
  waveformsVisible: boolean;
}

export const timelineViewAtom = atom<TimelineViewState>({
  zoom: 100,
  scrollX: 0,
  scrollY: 0,
  gridVisible: true,
  waveformsVisible: true,
});

export const timelineZoomAtom = atom(
  (get) => get(timelineViewAtom).zoom,
  (get, set, zoom: number) => {
    set(timelineViewAtom, {
      ...get(timelineViewAtom),
      zoom: Math.max(10, Math.min(500, zoom)),
    });
  }
);

// ============ Audio Import State ============

export interface ImportedFileState {
  id: string;
  name: string;
  duration: number;
  sampleRate: number;
  channels: number;
}

export const importedFilesAtom = atom<ImportedFileState[]>([]);

// ============ Preferences ============

export interface Preferences {
  audioBufferSize: 128 | 256 | 512 | 1024 | 2048;
  sampleRate: 44100 | 48000 | 96000;
  autoSaveEnabled: boolean;
  autoSaveIntervalMs: number;
  confirmOnDelete: boolean;
  scrollFollowsPlayhead: boolean;
  faderStyle: 'cubase' | 'protools' | 'logic' | 'ableton';
}

export const preferencesAtom = atomWithStorage<Preferences>('rf_preferences', {
  audioBufferSize: 256,
  sampleRate: 48000,
  autoSaveEnabled: true,
  autoSaveIntervalMs: 60000,
  confirmOnDelete: true,
  scrollFollowsPlayhead: true,
  faderStyle: 'cubase',
});

// ============ Plugin State ============

export interface ActivePlugin {
  busId: string;
  slotIndex: number;
  pluginId: string;
  pluginName: string;
  isOpen: boolean;
}

export const activePluginsAtom = atom<ActivePlugin[]>([]);

export const openPluginAtom = atom(
  null,
  (get, set, plugin: Omit<ActivePlugin, 'isOpen'>) => {
    const current = get(activePluginsAtom);
    const existing = current.find(
      p => p.busId === plugin.busId && p.slotIndex === plugin.slotIndex
    );

    if (existing) {
      // Toggle open state
      set(activePluginsAtom, current.map(p =>
        p === existing ? { ...p, isOpen: !p.isOpen } : p
      ));
    } else {
      // Add new plugin
      set(activePluginsAtom, [...current, { ...plugin, isOpen: true }]);
    }
  }
);

export const closePluginAtom = atom(
  null,
  (get, set, { busId, slotIndex }: { busId: string; slotIndex: number }) => {
    set(activePluginsAtom, get(activePluginsAtom).filter(
      p => !(p.busId === busId && p.slotIndex === slotIndex)
    ));
  }
);

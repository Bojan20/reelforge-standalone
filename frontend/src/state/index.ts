/**
 * State Module
 *
 * Centralized state management using Jotai.
 *
 * Usage:
 * ```tsx
 * import { useAtom } from 'jotai';
 * import { isPlayingAtom, selectedClipIdAtom } from '@/state';
 *
 * function Component() {
 *   const [isPlaying, setIsPlaying] = useAtom(isPlayingAtom);
 *   const [selectedClip] = useAtom(selectedClipIdAtom);
 *   // ...
 * }
 * ```
 *
 * @module state
 */

export {
  // Editor
  editorModeAtom,
  isDarkModeAtom,
  type EditorMode,

  // Playback
  playbackAtom,
  isPlayingAtom,
  currentTimeAtom,
  bpmAtom,
  type PlaybackState,

  // Selection
  selectionAtom,
  selectedEventNameAtom,
  selectedClipIdAtom,
  type SelectionState,

  // UI
  uiAtom,
  leftZoneVisibleAtom,
  rightZoneVisibleAtom,
  lowerZoneVisibleAtom,
  activeLowerTabAtom,
  type UIState,

  // Mixer
  busesAtom,
  updateBusAtom,
  hasAnySoloAtom,
  type BusState,

  // Timeline
  timelineViewAtom,
  timelineZoomAtom,
  type TimelineViewState,

  // Import
  importedFilesAtom,
  type ImportedFileState,

  // Preferences
  preferencesAtom,
  type Preferences,

  // Plugins
  activePluginsAtom,
  openPluginAtom,
  closePluginAtom,
  type ActivePlugin,
} from './atoms';

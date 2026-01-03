/**
 * ReelForge Store - Public API
 *
 * Export all store functionality from a single entry point.
 */

// Core store
export { useReelForgeStore } from './reelforgeStore';
export type { ReelForgeStore, BusPdcState } from './reelforgeStore';

// State selector hooks
export {
  useMixerState,
  useProjectState,
  useMasterInsertState,
  useBusInsertState,
} from './reelforgeStore';

// Action hooks
export {
  useMixerActions,
  useProjectActions,
  useMasterInsertActions,
  useBusInsertActions,
} from './reelforgeStore';

// Backwards-compatible hooks (drop-in replacements for old contexts)
export {
  useMixer,
  useProject,
  useProjectRoutes,
  useMasterInserts,
  useBusInserts,
  useMasterInsertChain,
  useMasterInsertLatency,
  usePdcState,
  useMasterInsertSampleRate,
  useBusInsertChain,
  useBusInsertLatency,
} from './hooks';

// New Project Store (timeline-focused)
export {
  getProjectStore,
  default as ProjectStore,
} from './projectStore';

export type {
  TrackState,
  ClipState,
  InsertState,
  SendState,
  MarkerState,
  TransportState,
  ProjectMetadata,
  ProjectState,
  HistoryEntry,
} from './projectStore';

export {
  useProjectStore,
  useProjectSelector,
  useTransport,
  useTracks,
  useTrack,
  useClips,
  useMarkers,
  useHistory,
  useView,
  useSelection,
} from './useProjectStore';

// Playback Store (separate Timeline vs Mixer playback)
export { getPlaybackStore, default as PlaybackStore } from './playbackStore';

export type {
  TimelinePlaybackState,
  MixerPlaybackState,
  PlaybackStoreState,
} from './playbackStore';

export {
  usePlaybackStore,
  useTimelinePlayback,
  useMixerPlayback,
  useIsAnythingPlaying,
  useStopAll,
} from './usePlaybackStore';

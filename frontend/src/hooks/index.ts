/**
 * ReelForge Hooks
 *
 * Custom React hooks for audio, project, and UI.
 *
 * @module hooks
 */

export { useAudioAnalyzer } from './useAudioAnalyzer';
export { useAudioEngine } from './useAudioEngine';
export { useAudioLoopAnalyzer } from './useAudioLoopAnalyzer';
export { useMasterABSnapshot } from './useMasterABSnapshot';
export { usePerformance } from './usePerformance';
export { usePreviewExecutor } from './usePreviewExecutor';
export { usePreviewMixSync } from './usePreviewMixSync';
export { useProjectHistory } from './useProjectHistory';

// Extracted hooks for EventsPage refactoring
export { useCommandActions } from './useCommandActions';
export { useDragDrop } from './useDragDrop';
export { useEventActions } from './useEventActions';
export { usePlaybackControls } from './usePlaybackControls';
export { useDetachablePanel } from './useDetachablePanel';
export { useRuntimeCore, LATENCY_UPDATE_INTERVAL_MS } from './useRuntimeCore';

// New hooks for editor integration
export { useMixerDSP, type MixerBus, type MixerInsert, type MixerDSPReturn } from './useMixerDSP';
export { useTimelinePlayback, type TimelineClipData, type TimelinePlaybackReturn } from './useTimelinePlayback';
export { useGlobalShortcuts, formatShortcut, SHORTCUTS, type ShortcutAction, type ShortcutName } from './useGlobalShortcuts';
export { useAudioExport, DEFAULT_EXPORT_SETTINGS, type ExportSettings, type ExportClip, type AudioExportReturn } from './useAudioExport';
export { useSessionPersistence, createSessionState, type SessionState, type SessionPersistenceReturn } from './useSessionPersistence';

// Metering hooks
export { useBusMeter, useSimulatedBusMeter, linearToDb, dbToLinear, getMeterColor, type BusMeterState, type BusMeterConfig } from './useBusMeter';
export { useLiveMeter, useMultipleMeters, useBusMeterSetup, dbToNormalized, normalizedToDb, type MeterState, type UseLiveMeterOptions, type MultipleMeterState } from './useLiveMeter';

// Auto-save hook
export { useAutoSave, formatAutoSaveTime, formatDataSize, type AutoSaveEntry, type AutoSaveConfig, type RecoveryInfo, type AutoSaveStatus, type UseAutoSaveOptions, type UseAutoSaveReturn } from './useAutoSave';

// Editor mode
export { useEditorMode, MODE_CONFIGS, type EditorMode, type EditorModeConfig, type UseEditorModeReturn } from './useEditorMode';

// Types
export type { UseCommandActionsOptions, UseCommandActionsReturn } from './useCommandActions';
export type { UseDragDropOptions, UseDragDropReturn } from './useDragDrop';
export type { UseEventActionsOptions, UseEventActionsReturn } from './useEventActions';
export type { UsePlaybackControlsOptions, UsePlaybackControlsReturn } from './usePlaybackControls';
export type { UseDetachablePanelOptions, UseDetachablePanelReturn } from './useDetachablePanel';
export type { UseRuntimeCoreOptions, UseRuntimeCoreReturn } from './useRuntimeCore';

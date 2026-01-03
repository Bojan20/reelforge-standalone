/**
 * ReelForge Core
 *
 * Core systems, contexts, DSP, and utilities.
 *
 * @module core
 */

// ============ Contexts ============
// AssetInsertContext
export {
  AssetInsertProvider,
  useAssetInserts,
  useAssetInsertChain,
  useAssetHasInserts,
} from './AssetInsertContext';

// BusInsertContext
export {
  BusInsertProvider,
  useBusInserts,
  useBusInsertChain,
  useBusInsertLatency,
  type BusPdcState,
} from './BusInsertContext';

// MasterInsertContext
export {
  MasterInsertProvider,
  useMasterInserts,
  useMasterInsertChain,
  useMasterInsertLatency,
  usePdcState,
  useMasterInsertSampleRate,
} from './MasterInsertContext';

// PreviewMixContext
export {
  PreviewMixProvider,
  usePreviewMix,
  usePreviewMixSnapshot,
} from './PreviewMixContext';

// ============ Audio Engine ============
export { AudioEngine, type AudioEngineState } from './audioEngine';
export { AudioContextManager, getSharedAudioContext, ensureAudioContextResumed } from './AudioContextManager';
export {
  PreviewEngine,
  usePreview,
  type PreviewState,
  type PreviewOptions,
  type PreviewEvent,
  type PreviewEventType,
} from './previewEngine';
export {
  UndoManager,
  useUndo,
  createPropertyCommand,
  createArrayPushCommand,
  createArrayRemoveCommand,
  createArrayMoveCommand,
  createMapSetCommand,
  createMapDeleteCommand,
  createCompositeCommand,
  setupUndoKeyboardShortcuts,
  type UndoableCommand,
  type Transaction,
  type HistoryState,
  type HistoryEvent,
} from './undoSystem';
export {
  DragDropManager,
  useDraggable,
  useDropTarget,
  useDragState,
  type DragItem,
  type DragItemType,
  type DropTarget,
  type DropResult,
  type DragState,
  type DragEvent,
} from './dragDropSystem';
export {
  AudioMeter,
  MeterManager,
  useMeter,
  getMeterColor,
  generateMeterSegments,
  formatDb,
  formatLufs,
  type MeterReading,
  type MeterConfig,
} from './audioMetering';
export {
  ProjectPersistence,
  useProject,
  type ProjectMetadata,
  type ProjectData,
  type RecentProject,
  type AutoSaveEntry,
} from './projectPersistence';
export {
  ThemeManager,
  useTheme,
  type ThemeMode,
  type ThemeColors,
  type ThemePreset,
  type ThemeState,
} from './themeSystem';
export { AudioBufferCache } from './audioBufferCache';
export {
  EngineClient,
  type EngineStatus,
  type EngineLogEntry,
  type OutgoingMessage,
  type IncomingMessage,
} from './engineClient';
export {
  NativeRuntimeCoreWrapper,
  isNativeRuntimeCoreAvailable,
  getNativeLoadError,
  createNativeRuntimeCore,
  type NativeGameEvent,
  type NativePlayCommand,
  type NativeStopCommand,
  type NativeStopAllCommand,
  type NativeSetBusGainCommand,
  type NativeAdapterCommand,
  type NativeRuntimeStats,
  type NativeRoutesInfo,
  type NativeRuntimeCoreOptions,
  type INativeRuntimeCore,
} from './nativeRuntimeCore';

// ============ DSP ============
// Use namespace for busInsertDSP (has DUCKING_CONFIG conflict)
export * as BusInsertDSP from './busInsertDSP';
export * from './masterInsertDSP';
export * from './voiceInsertDSP';
export * from './dspMetrics';

// ============ Pooling ============
export { voiceChainPool } from './VoiceChainPool';

// ============ Send/Return Buses ============
export {
  sendReturnBus,
  type SendBusId,
  type SendBusConfig,
  type SendConfig,
} from './SendReturnBus';

// ============ Custom Aux Buses ============
export {
  customAuxBus,
  type CustomAuxBusId,
  type CustomAuxBusConfig,
} from './CustomAuxBus';

// ============ Automation Lanes ============
export {
  AutomationLane,
  automationManager,
  type InterpolationMode,
  type RecordingMode,
  type AutomationPoint,
  type AutomationLaneConfig,
  type AutomationLaneState,
} from './AutomationLane';

// ============ Offline Rendering ============
export {
  offlineRenderer,
  downloadBlob,
  dbToGain,
  gainToDb,
  type ExportFormat,
  type DitherType,
  type RenderOptions,
  type RenderResult,
  type ExportResult,
  type AudioGraphSetup,
} from './OfflineRenderer';

// ============ Loop Analysis ============
// All have LoopAnalysisResult - use namespace for each
export * as LoopAnalyzer from './loopAnalyzer';
export * as LoopAnalyzerIntegration from './loopAnalyzerIntegration';
export * as LoopAnalyzerWithLibrary from './loopAnalyzerWithLibrary';
export * as AdvancedLoopAnalyzer from './advancedLoopAnalyzer';
export * as AudioLoopAnalysis from './audioLoopAnalysis';
export * from './bpmMetadata';

// ============ Music System ============
export * from './layeredMusicSystem';
export * from './advancedMusicCrossfade';
export * from './tempoMatchedCrossfade';

// ============ Mix Snapshots & Control Bus ============
export {
  SnapshotManager,
  DEFAULT_SNAPSHOTS,
  type SnapshotTransitionOptions,
} from './mixSnapshots';
export {
  ControlBusManager,
  DEFAULT_CONTROL_BUSES,
  parseControlPath,
} from './controlBus';

// ============ Intensity Layers & Ducking ============
export {
  IntensityLayerSystem,
  DEFAULT_LAYER_CONFIGS,
  type MusicLayer,
  type IntensityLayerConfig,
} from './intensityLayers';
export {
  DuckingManager,
  DEFAULT_DUCKING_RULES,
  type DuckingRule,
} from './duckingManager';

// ============ Sound Variations ============
export {
  SoundVariationManager,
  DEFAULT_VARIATION_CONTAINERS,
  type VariationMode,
  type SoundVariation,
  type VariationContainer,
  type VariationPlayResult,
} from './soundVariations';

// ============ Voice Concurrency ============
export {
  VoiceConcurrencyManager,
  DEFAULT_CONCURRENCY_RULES,
  type VoiceKillPolicy,
  type VoiceConcurrencyRule,
  type ActiveVoice,
} from './voiceConcurrency';

// ============ Sequence Containers ============
export {
  SequenceContainerManager,
  DEFAULT_SEQUENCE_CONTAINERS,
  type SequenceStepTiming,
  type SequenceStep,
  type SequenceContainer,
  type SequencePlaybackState,
  type SequencePlayOptions,
} from './sequenceContainer';

// ============ Stingers ============
export {
  StingerManager,
  DEFAULT_STINGERS,
  type StingerTriggerMode,
  type StingerTailMode,
  type Stinger,
  type StingerPlayOptions,
  type MusicBeatInfo,
  type StingerQueueItem,
} from './stingerManager';

// ============ Parameter Modifiers ============
export {
  ParameterModifierManager,
  LFO,
  Envelope,
  AutomationCurve,
  DEFAULT_LFO_CONFIGS,
  DEFAULT_ENVELOPE_CONFIGS,
  DEFAULT_CURVE_CONFIGS,
  type LFOWaveform,
  type LFOConfig,
  type EnvelopeState,
  type EnvelopeConfig,
  type CurveInterpolation,
  type CurveKeyframe,
  type CurveConfig,
  type ModifierTarget,
  type ActiveModifier,
} from './parameterModifiers';

// ============ Blend Containers ============
export {
  BlendContainerManager,
  DEFAULT_BLEND_CONTAINERS,
  type BlendCurveType,
  type BlendTrack,
  type BlendContainer,
  type BlendContainerState,
  type BlendPlayOptions,
} from './blendContainer';

// ============ Priority System ============
export {
  PriorityManager,
  DEFAULT_PRIORITY_CONFIGS,
  DEFAULT_BUS_LIMITS,
  PRIORITY_LEVELS,
  type PriorityLevel,
  type PriorityConfig,
  type PrioritizedSound,
  type BusPriorityLimit,
} from './prioritySystem';

// ============ Event Groups ============
export {
  EventGroupManager,
  DEFAULT_EVENT_GROUPS,
  type GroupBehavior,
  type EventGroupMember,
  type EventGroup,
  type ActiveGroupMember,
  type QueuedGroupMember,
} from './eventGroups';

// ============ RTPC (Real-Time Parameter Control) ============
export {
  RTPCManager,
  DEFAULT_RTPC_DEFINITIONS,
  type RTPCTarget,
  type RTPCCurveType,
  type RTPCCurvePoint,
  type RTPCBinding,
  type RTPCDefinition,
  type ActiveRTPC,
} from './rtpc';

// ============ Game Sync ============
export {
  GameSyncManager,
  DEFAULT_STATE_GROUPS,
  DEFAULT_SWITCH_GROUPS,
  DEFAULT_TRIGGERS,
  type GameSyncType,
  type StateAction,
  type StateDefinition,
  type StateGroup,
  type SwitchValue,
  type SwitchGroup,
  type TriggerAction,
  type Trigger,
  type ActiveState,
} from './gameSync';

// ============ Markers & Cue Points ============
export {
  MarkerManager,
  createLoopMarkers,
  createIntroLoopMarkers,
  createMusicSectionMarkers,
  type MarkerType,
  type MarkerAction,
  type Marker,
  type MarkerRegion,
  type AssetMarkers,
  type ActiveMarkerTracking,
} from './markers';

// ============ Playlist System ============
export {
  PlaylistManager,
  DEFAULT_PLAYLISTS,
  type PlaylistMode,
  type PlaylistLoopMode,
  type PlaylistTrack,
  type Playlist,
  type PlaylistState,
} from './playlist';

// ============ Music Transitions ============
export {
  MusicTransitionManager,
  DEFAULT_TRANSITION_RULES,
  type TransitionType,
  type TransitionSync,
  type TransitionRule,
  type MusicTrackInfo,
  type PendingTransition,
} from './musicTransition';

// ============ Interactive Music ============
export {
  InteractiveMusicController,
  DEFAULT_INTERACTIVE_MUSIC_CONFIGS,
  type MusicState,
  type MusicLayer as InteractiveMusicLayer,
  type MusicSegment,
  type InteractiveMusicConfig,
  type ActiveMusicState,
} from './interactiveMusic';

// ============ Insert Chain ============
export * from './insertChainClipboard';
export * from './insertChainPresets';

// ============ Routes ============
export * from './routesStorage';
export * from './routesTypes';

// ============ Validation ============
export * from './validateMasterInserts';
export * from './validateProject';
export * from './validateRoutes';

// ============ Persistence ============
export * from './persistence';
export * from './assetIndex';

// ============ Preview ============
// Use namespace for previewMixState (has DUCKING_CONFIG conflict)
export * as PreviewMixState from './previewMixState';
export * from './masterABSnapshot';

// ============ Diagnostics ============
export * from './diagnosticsExport';
export { useDiagnosticsSnapshot } from './useDiagnosticsSnapshot';
export * as CorePerformanceMonitor from './performanceMonitor';

// ============ Audio Diagnostics & Profiler ============
export {
  AudioDiagnosticsManager,
  AudioConsoleLogger,
  audioLogger,
  type DiagnosticEventType,
  type DiagnosticEvent,
  type VoiceStats,
  type MemoryStats,
  type BusLevelReading,
  type PerformanceMetrics,
  type DiagnosticsSnapshot,
} from './audioDiagnostics';
export {
  AudioProfiler,
  FrameTimeMonitor,
  audioProfiler,
  frameMonitor,
  type ProfileCategory,
  type ProfileSample,
  type CategoryStats,
  type ProfileReport,
  type ActiveProfile,
} from './audioProfiler';

// ============ DSP Plugins ============
export {
  ReverbPlugin,
  DelayPlugin,
  ChorusPlugin,
  PhaserPlugin,
  FlangerPlugin,
  TremoloPlugin,
  DistortionPlugin,
  FilterPlugin,
  PluginChain,
  createPlugin,
  DEFAULT_REVERB_CONFIG,
  DEFAULT_DELAY_CONFIG,
  DEFAULT_CHORUS_CONFIG,
  DEFAULT_PHASER_CONFIG,
  DEFAULT_FLANGER_CONFIG,
  DEFAULT_TREMOLO_CONFIG,
  DEFAULT_DISTORTION_CONFIG,
  DEFAULT_FILTER_CONFIG,
  type PluginType,
  type PluginParameter,
  type DSPPlugin,
  type ReverbConfig,
  type DelayConfig,
  type DelayMode,
  type ChorusConfig,
  type PhaserConfig,
  type FlangerConfig,
  type TremoloConfig,
  type DistortionConfig,
  type DistortionType,
  type FilterConfig,
  type FilterType,
  type PluginConfig,
} from './dspPlugins';

// ============ Spatial Audio ============
export {
  SpatialAudioManager,
  SpatialVoiceManager,
  SPATIAL_PRESETS,
  createCircularSources,
  createGridSources,
  lerpPosition,
  createPathPoints,
  DEFAULT_SPATIAL_SOURCE_CONFIG,
  DEFAULT_LISTENER_CONFIG,
  type DistanceModel,
  type PanningModel,
  type Vector3,
  type Orientation3D,
  type SpatialSourceConfig,
  type ListenerConfig,
  type AudioZone,
  type ActiveSpatialSource,
  type SpatialVoice,
} from './spatialAudio';

// Perceptual Spatial Audio Integration
export {
  SpatialAudioManager as PerceptualSpatialAudioManager,
  useSpatialAudio,
  useSpatialAnchor,
  type SpatialAudioManagerConfig,
  type SpatialVoice as PerceptualSpatialVoice,
} from './SpatialAudioManager';

// ============ Animation ============
export * from './animation';

// ============ Utilities ============
export * from './focusManagement';
export * from './keyboardShortcuts';
export * from './featureFlags';
export * from './rfErrors';
export * from './templateAdapter';

// ============ Types ============
export * from './types';
export * from './masterInsertTypes';
export * from './BaseGameLayers';

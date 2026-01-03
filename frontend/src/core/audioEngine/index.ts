/**
 * AudioEngine Module System
 *
 * This module provides a clean import interface for the AudioEngine system.
 * The actual implementation remains in audioEngine.ts.
 *
 * ## Architecture Overview
 *
 * The AudioEngine handles 22 distinct feature areas:
 *
 * ### Core Audio
 * - Bus routing and volume control
 * - Voice management and playback
 * - Buffer caching
 *
 * ### Game Integration
 * - **GameSync** - States, switches, triggers
 * - **RTPC** - Real-time parameter control
 * - **Events** - Event groups and bindings
 *
 * ### Music System
 * - **Interactive Music** - State-based music
 * - **Transitions** - Beat-synced transitions
 * - **Playlists** - Sequential/random playback
 * - **Stingers** - One-shot music hits
 *
 * ### Voice Management
 * - **Concurrency** - Voice limits per event
 * - **Priority** - Voice stealing policies
 * - **Variations** - Random/sequential selection
 * - **Sequences** - Multi-step containers
 *
 * ### Effects & Processing
 * - **Ducking** - Volume automation
 * - **Blends** - Crossfade containers
 * - **Modifiers** - LFO, envelope, curves
 * - **DSP Plugins** - Insert/send effects
 * - **Spatial** - 3D positioning
 *
 * ### Utility
 * - **Snapshots** - Save/restore mix states
 * - **Markers** - Cue points and regions
 * - **Diagnostics** - Logging and profiling
 *
 * ## Usage
 *
 * ```typescript
 * // Main AudioEngine class
 * import { AudioEngine } from '@/core/audioEngine';
 *
 * // Specific managers
 * import { SnapshotManager, SpatialAudioManager } from '@/core/audioEngine';
 *
 * // Types
 * import type { AudioEngineState, BusId } from '@/core/audioEngine';
 * ```
 *
 * @module core/audioEngine
 */

// ============ Main AudioEngine ============
export { AudioEngine, type AudioEngineState } from '../audioEngine';

// ============ Shared Types ============
export type { VoiceInstance } from './types';
export type { BusId, MixSnapshot, ControlBus } from '../types';

// ============ Mix Snapshots ============
export { SnapshotManager, type SnapshotTransitionOptions } from '../mixSnapshots';

// ============ Control Bus ============
export { ControlBusManager, parseControlPath } from '../controlBus';

// ============ Intensity Layers ============
export { IntensityLayerSystem, type IntensityLayerConfig } from '../intensityLayers';

// ============ Ducking ============
export { DuckingManager, type DuckingRule } from '../duckingManager';

// ============ Sound Variations ============
export { SoundVariationManager, type VariationContainer, type VariationPlayResult } from '../soundVariations';

// ============ Voice Concurrency ============
export { VoiceConcurrencyManager, type VoiceConcurrencyRule, type ActiveVoice } from '../voiceConcurrency';

// ============ Sequence Containers ============
export { SequenceContainerManager, type SequenceContainer, type SequencePlayOptions } from '../sequenceContainer';

// ============ Stingers ============
export { StingerManager, type Stinger, type StingerPlayOptions, type MusicBeatInfo } from '../stingerManager';

// ============ Parameter Modifiers ============
export { ParameterModifierManager, type LFOConfig, type EnvelopeConfig, type CurveConfig, type ModifierTarget } from '../parameterModifiers';

// ============ Blend Containers ============
export { BlendContainerManager, type BlendContainer, type BlendPlayOptions } from '../blendContainer';

// ============ Priority System ============
export { PriorityManager, type PriorityConfig, type BusPriorityLimit } from '../prioritySystem';

// ============ Event Groups ============
export { EventGroupManager, type EventGroup, type EventGroupMember } from '../eventGroups';

// ============ RTPC ============
export { RTPCManager, type RTPCDefinition, type RTPCBinding } from '../rtpc';

// ============ Game Sync ============
export { GameSyncManager, type StateGroup, type SwitchGroup, type Trigger } from '../gameSync';

// ============ Markers ============
export { MarkerManager, type AssetMarkers, type Marker, type MarkerRegion } from '../markers';

// ============ Playlist ============
export { PlaylistManager, type Playlist, type PlaylistTrack, type PlaylistMode, type PlaylistLoopMode } from '../playlist';

// ============ Music Transitions ============
export { MusicTransitionManager, type TransitionRule, type MusicTrackInfo } from '../musicTransition';

// ============ Interactive Music ============
export { InteractiveMusicController, type InteractiveMusicConfig, type MusicState } from '../interactiveMusic';

// ============ Diagnostics ============
export { AudioDiagnosticsManager, audioLogger, type DiagnosticsSnapshot, type DiagnosticEvent, type DiagnosticEventType } from '../audioDiagnostics';

// ============ Profiler ============
export { AudioProfiler, FrameTimeMonitor, audioProfiler, frameMonitor, type ProfileReport, type ProfileSample, type ProfileCategory } from '../audioProfiler';

// ============ DSP Plugins ============
export { PluginChain, createPlugin, type DSPPlugin, type PluginConfig } from '../dspPlugins';

// ============ Spatial Audio ============
export {
  SpatialAudioManager,
  SpatialVoiceManager,
  type SpatialSourceConfig,
  type Vector3,
  type Orientation3D,
  type AudioZone,
  type ActiveSpatialSource,
  SPATIAL_PRESETS
} from '../spatialAudio';

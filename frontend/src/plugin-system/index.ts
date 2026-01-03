/**
 * ReelForge Plugin System
 *
 * Complete plugin infrastructure for DAW:
 * - Plugin registry and discovery
 * - Plugin wrappers (Web Audio, AudioWorklet)
 * - Preset management
 * - Parameter automation
 * - Window management
 * - Plugin chains
 *
 * @module plugin-system
 */

// Plugin Registry
export {
  PluginRegistry,
  getCategoryDisplayName,
  getAllCategories,
  validateDescriptor,
  type PluginCategory,
  type PluginFormat,
  type PluginParameter,
  type PluginDescriptor,
  type PluginInstance,
  type PluginState,
  type PluginScanResult,
  type PluginRegistryEvent,
} from './PluginRegistry';

// Plugin Wrappers
export {
  BasePlugin,
  WebAudioPlugin,
  AudioWorkletPlugin,
  ScriptProcessorPlugin,
  OfflinePlugin,
  createParameter,
  floatParam,
  dbParam,
  freqParam,
  choiceParam,
  boolParam,
} from './PluginWrapper';

// Preset Manager
export {
  PresetManager,
  type PluginPreset,
  type PresetBank,
  type PresetImportResult,
  type PresetExportOptions,
  type PresetEvent,
} from './PresetManager';

// Parameter Automation
export {
  AutomationEngine,
  getModeName,
  getCurveName,
  type AutomationMode,
  type AutomationCurve,
  type AutomationPoint,
  type AutomationLane,
  type AutomationSnapshot,
  type RecordingSession,
  type AutomationEvent,
} from './ParameterAutomation';

// Window Manager
export {
  PluginWindowManager,
  type WindowMode,
  type DockPosition,
  type WindowBounds,
  type PluginWindow,
  type WindowLayoutPreset,
  type WindowEvent,
} from './PluginWindowManager';

// Plugin Chain
export {
  PluginChain,
  PluginChainManager,
  type PluginSlot,
  type PluginChainConfig,
  type ChainProcessingResult,
  type ChainEvent,
} from './PluginChain';

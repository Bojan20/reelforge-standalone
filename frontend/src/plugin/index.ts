/**
 * ReelForge M9.1 Plugin Module
 *
 * Central exports for the plugin system.
 * This is the public API for plugin definitions, registration,
 * DSP factories, editors, and parameter binding.
 *
 * @module plugin
 */

// Parameter Descriptor types and utilities
export type { ParamDescriptor, ParamUnit, ParamScale } from './ParamDescriptor';

export {
  clampParamValue,
  isParamValueValid,
  formatParamValue,
  sliderToValue,
  valueToSlider,
  getEffectiveStep,
} from './ParamDescriptor';

// Plugin Definition types
export type {
  PluginDefinition,
  PluginCategory,
  PluginDSPInstance,
  PluginEditorProps,
} from './PluginDefinition';

// Van* Plugin descriptors
export { VANEQ_PARAM_DESCRIPTORS } from './vaneqDescriptors';
export { VANCOMP_PARAM_DESCRIPTORS } from './vancomp-pro/vancompDescriptors';
export { VANLIMIT_PARAM_DESCRIPTORS } from './vanlimit-pro/vanlimitDescriptors';

// Plugin Registry
export {
  registerPlugin,
  getPluginDefinition,
  getAllPluginDefinitions,
  getRegisteredPluginIds,
  isPluginRegistered,
  getPluginParamDescriptors,
  getPluginLatency,
  getPluginsByCategory,
  onPluginRegistryChange,
} from './pluginRegistry';

export type { PluginRegistryListener } from './pluginRegistry';

// Plugin Instance Pool
export { pluginPool } from './PluginInstancePool';

// Parameter Binding Helpers
export {
  normalizeForUI,
  validateOnLoad,
  validateParamsOnLoad,
  applyPatch,
  applyPatches,
  resetParam,
  getDefaultParams,
  createDescriptorMap,
  paramsEqual,
  snapToStep,
} from './paramBinding';

// Van* DSP Factories
export { createVanEqDSP } from './vaneqDSP';
export { createVanCompDSP } from './vancomp-pro/vancompDSP';
export { createVanLimitDSP } from './vanlimit-pro/vanlimitDSP';

// Van* Editors
export { default as VanEQProEditor } from './vaneq-pro/VanEQProEditor';
export { VanCompProEditor } from './vancomp-pro/VanCompProEditor';
export { VanLimitProEditor } from './vanlimit-pro/VanLimitProEditor';

// Insert Selection Context
export {
  InsertSelectionProvider,
  useInsertSelection,
  useIsInsertSelected,
} from './InsertSelectionContext';

export type {
  InsertScope,
  InsertSelection,
  OnParamChange,
  OnParamReset,
  OnBypassChange,
} from './InsertSelectionContext';

// Plugin Editor Drawer
export { PluginEditorDrawer } from './PluginEditorDrawer';

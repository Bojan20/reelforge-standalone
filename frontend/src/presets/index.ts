/**
 * ReelForge Presets Module
 *
 * Plugin preset management:
 * - Save/load presets
 * - Categories
 * - Import/export
 *
 * @module presets
 */

export { PresetManager } from './PresetManager';
export type {
  PresetManagerProps,
  Preset,
  PresetCategory,
  PresetParameter,
} from './PresetManager';

export { usePresets } from './usePresets';
export type { UsePresetsOptions, UsePresetsReturn, PresetDiff } from './usePresets';

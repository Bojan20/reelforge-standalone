/**
 * ReelForge Plugin Host
 *
 * Plugin hosting and UI components:
 * - Plugin windows
 * - Parameter controls
 * - Plugin browser
 *
 * @module plugin-host
 */

export { PluginWindow } from './PluginWindow';
export type { PluginWindowProps } from './PluginWindow';

export { PluginParameter } from './PluginParameter';
export type {
  PluginParameterProps,
  ParameterType,
  ParameterOption,
} from './PluginParameter';

export { PluginBrowser } from './PluginBrowser';
export type {
  PluginBrowserProps,
  PluginInfo,
  PluginCategory,
} from './PluginBrowser';

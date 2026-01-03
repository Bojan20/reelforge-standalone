/**
 * ReelForge M9.3 Plugin Window Bridge Hook
 *
 * React hook for IPC communication between plugin windows
 * and the main process.
 *
 * @module plugin-window/usePluginWindowBridge
 */

import { useMemo } from 'react';

/**
 * Plugin window state from main process.
 */
export interface PluginWindowState {
  insertId: string;
  pluginId: string;
  pluginName: string;
  params: Record<string, number>;
  bypassed: boolean;
}

/**
 * Plugin window API exposed by preload script.
 */
interface PluginWindowAPI {
  getInitialState: () => Promise<PluginWindowState | null>;
  sendParamChange: (insertId: string, paramId: string, value: number) => void;
  sendBypassChange: (insertId: string, bypassed: boolean) => void;
  requestClose: (insertId: string) => void;
  onParamsUpdate: (callback: (data: { params: Record<string, number> }) => void) => () => void;
  onBypassUpdate: (callback: (data: { bypassed: boolean }) => void) => () => void;
}

// Declare global window type extension
declare global {
  interface Window {
    pluginWindowAPI?: PluginWindowAPI;
    isElectron?: boolean;
  }
}

/**
 * Mock API for web (non-Electron) context.
 * Provides stub implementations that don't do anything.
 */
const mockAPI: PluginWindowAPI = {
  getInitialState: async () => null,
  sendParamChange: () => {},
  sendBypassChange: () => {},
  requestClose: () => {},
  onParamsUpdate: () => () => {},
  onBypassUpdate: () => () => {},
};

/**
 * Hook to access the plugin window IPC bridge.
 *
 * In Electron, uses the exposed pluginWindowAPI.
 * In web browser, returns a mock that does nothing.
 */
export function usePluginWindowBridge(): PluginWindowAPI {
  return useMemo(() => {
    // Check if running in Electron with the API available
    if (typeof window !== 'undefined' && window.pluginWindowAPI) {
      return window.pluginWindowAPI;
    }

    // Return mock for web context
    return mockAPI;
  }, []);
}

/**
 * Check if running in Electron.
 */
export function isElectron(): boolean {
  return typeof window !== 'undefined' && window.isElectron === true;
}

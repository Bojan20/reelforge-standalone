/**
 * ReelForge M9.3 Electron Type Declarations
 *
 * Type declarations for Electron APIs exposed via preload script.
 *
 * @module types/electron
 */

/**
 * API exposed to main window for managing plugin windows.
 */
export interface ElectronAPI {
  /**
   * Open a plugin window.
   */
  openPluginWindow: (data: {
    insertId: string;
    pluginId: string;
    pluginName: string;
    params: Record<string, number>;
    bypassed: boolean;
  }) => Promise<{ success: boolean; error?: string }>;

  /**
   * Close a plugin window.
   */
  closePluginWindow: (insertId: string) => Promise<{ success: boolean }>;

  /**
   * Update plugin params in a window.
   */
  updatePluginParams: (data: {
    insertId: string;
    params: Record<string, number>;
  }) => Promise<{ success: boolean }>;

  /**
   * Update bypass state in a window.
   */
  updatePluginBypass: (data: {
    insertId: string;
    bypassed: boolean;
  }) => Promise<{ success: boolean }>;

  /**
   * Listen for param changes from plugin windows.
   */
  onPluginParamChange: (callback: (data: {
    insertId: string;
    paramId: string;
    value: number;
  }) => void) => () => void;

  /**
   * Listen for bypass changes from plugin windows.
   */
  onPluginBypassChange: (callback: (data: {
    insertId: string;
    bypassed: boolean;
  }) => void) => () => void;
}

/**
 * API exposed to plugin windows for IPC communication.
 */
export interface PluginWindowAPI {
  /**
   * Get initial state for this plugin window.
   */
  getInitialState: () => Promise<{
    insertId: string;
    pluginId: string;
    pluginName: string;
    params: Record<string, number>;
    bypassed: boolean;
  } | null>;

  /**
   * Send a param change to the main window.
   */
  sendParamChange: (insertId: string, paramId: string, value: number) => void;

  /**
   * Send a bypass change to the main window.
   */
  sendBypassChange: (insertId: string, bypassed: boolean) => void;

  /**
   * Request to close this window.
   */
  requestClose: (insertId: string) => void;

  /**
   * Listen for params updates from the main window.
   */
  onParamsUpdate: (callback: (data: { params: Record<string, number> }) => void) => () => void;

  /**
   * Listen for bypass updates from the main window.
   */
  onBypassUpdate: (callback: (data: { bypassed: boolean }) => void) => () => void;
}

/**
 * Extend Window interface with Electron APIs.
 */
declare global {
  interface Window {
    /**
     * Main window API for managing plugin windows.
     * Only available in Electron environment.
     */
    electronAPI?: ElectronAPI;

    /**
     * Plugin window API for IPC communication.
     * Only available in plugin window context.
     */
    pluginWindowAPI?: PluginWindowAPI;

    /**
     * Flag indicating we're running in Electron.
     */
    isElectron?: boolean;
  }
}

export {};

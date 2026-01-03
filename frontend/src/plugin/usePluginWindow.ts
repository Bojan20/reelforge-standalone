/**
 * ReelForge Plugin Window Hook
 *
 * Hook for opening plugin windows from the main renderer.
 * Uses BroadcastChannel for browser window communication.
 *
 * @module plugin/usePluginWindow
 */

import { useCallback, useEffect, useRef } from 'react';
import { getPluginDefinition } from './pluginRegistry';
import { usePluginWindowHost } from '../plugin-window/usePluginWindowSync';
import { masterInsertDSP } from '../core/masterInsertDSP';
import { useReelForgeStore } from '../store/reelforgeStore';
import type { VanEqDSP, VanEqMeterData } from './vaneqDSP';

/**
 * Check if a plugin should open in a standalone window.
 */
export function shouldOpenInWindow(pluginId: string): boolean {
  const def = getPluginDefinition(pluginId);
  return def?.opensInWindow === true;
}

/**
 * Hook for managing plugin windows.
 *
 * Uses BroadcastChannel for synchronization between main app and plugin windows.
 *
 * @param onParamChange - Callback when plugin window changes a param
 * @param onBypassChange - Callback when plugin window changes bypass
 * @param onParamBatch - Callback when plugin window changes multiple params atomically
 */
export function usePluginWindow(
  onParamChange?: (insertId: string, paramId: string, value: number) => void,
  onBypassChange?: (insertId: string, bypassed: boolean) => void,
  onParamBatch?: (insertId: string, changes: Record<string, number>) => void
) {
  // State provider ref to avoid stale closures
  const stateProviderRef = useRef<Map<string, { params: Record<string, number>; bypassed: boolean }>>(
    new Map()
  );

  // Track active metering for each insertId
  const meteringRef = useRef<Map<string, { pluginId: string; stopMetering: () => void }>>(
    new Map()
  );

  // Set up plugin window host with BroadcastChannel
  const host = usePluginWindowHost(
    // Handle param changes from plugin windows
    (insertId, paramId, value) => {
      onParamChange?.(insertId, paramId, value);
      // Also update local cache
      const state = stateProviderRef.current.get(insertId);
      if (state) {
        state.params[paramId] = value;
      }
    },
    // Handle bypass changes from plugin windows
    (insertId, bypassed) => {
      onBypassChange?.(insertId, bypassed);
      // Also update local cache
      const state = stateProviderRef.current.get(insertId);
      if (state) {
        state.bypassed = bypassed;
      }
    },
    // Handle batch param changes from plugin windows (atomic update)
    (insertId, changes) => {
      // Update local cache atomically
      const state = stateProviderRef.current.get(insertId);
      if (state) {
        Object.assign(state.params, changes);
      }
      // Invoke batch callback if provided
      onParamBatch?.(insertId, changes);
    }
  );

  // Set up state provider for the host
  // CRITICAL: Always pull state from zustand store (single source of truth)
  // The local cache is ONLY used for real-time updates during active window session
  useEffect(() => {
    host.setStateProvider((insertId) => {
      // ALWAYS pull from zustand store - it's the single source of truth
      // This ensures reopened windows get the CURRENT state with all changes
      const masterChain = useReelForgeStore.getState().masterChain;
      const insert = masterChain.inserts.find(ins => ins.id === insertId);

      console.debug('[usePluginWindow] stateProvider called for:', insertId, {
        foundInStore: !!insert,
        insertCount: masterChain.inserts.length,
        insertIds: masterChain.inserts.map(i => i.id),
      });

      if (insert) {
        // Flatten params if needed (VanEQ params are already flat)
        const params = insert.params as unknown as Record<string, number>;
        console.debug('[usePluginWindow] Returning state from zustand:', {
          insertId,
          paramCount: Object.keys(params).length,
          bypassed: !insert.enabled,
          sampleParams: Object.entries(params).slice(0, 3),
        });
        return { params, bypassed: !insert.enabled };
      }

      // Not found in master chain - could be a bus insert, return null
      console.warn('[usePluginWindow] Insert not found in masterChain:', insertId);
      return null;
    });
  }, [host]);

  /**
   * Start metering for a VanEQ insert.
   * Gets the VanEqDSP instance from masterInsertDSP and starts its metering.
   * Retries up to 20 times with 250ms delay (~5s total) if DSP not ready yet.
   */
  const startMeteringForInsert = useCallback((insertId: string, pluginId: string, retryCount = 0) => {
    // Only start metering for vaneq plugins
    if (pluginId !== 'vaneq') {
      return;
    }

    // Stop existing metering first (prevents duplicate metering callbacks)
    const existing = meteringRef.current.get(insertId);
    if (existing) {
      existing.stopMetering();
      meteringRef.current.delete(insertId);
    }

    const MAX_RETRIES = 20;
    const RETRY_DELAY_MS = 250;

    // Check if DSP is initialized
    if (!masterInsertDSP.isInitialized()) {
      if (retryCount < MAX_RETRIES) {
        // Log less frequently to reduce noise
        if (retryCount === 0 || retryCount % 5 === 0) {
          console.debug(`[usePluginWindow] masterInsertDSP not initialized, retry ${retryCount + 1}/${MAX_RETRIES}`);
        }
        setTimeout(() => startMeteringForInsert(insertId, pluginId, retryCount + 1), RETRY_DELAY_MS);
      } else {
        console.warn('[usePluginWindow] masterInsertDSP not initialized after max retries, metering unavailable');
      }
      return;
    }

    // Get the plugin DSP instance
    const pluginDSP = masterInsertDSP.getPluginDSP(insertId);
    if (!pluginDSP) {
      if (retryCount < MAX_RETRIES) {
        // Log less frequently to reduce noise
        if (retryCount === 0 || retryCount % 5 === 0) {
          console.debug(`[usePluginWindow] No plugin DSP for ${insertId}, retry ${retryCount + 1}/${MAX_RETRIES}`);
        }
        setTimeout(() => startMeteringForInsert(insertId, pluginId, retryCount + 1), RETRY_DELAY_MS);
      } else {
        console.warn('[usePluginWindow] No plugin DSP found for insert after max retries:', insertId);
      }
      return;
    }

    // Cast to VanEqDSP and start metering
    const vaneqDSP = pluginDSP as unknown as VanEqDSP;
    if (typeof vaneqDSP.startMetering !== 'function') {
      console.warn('[usePluginWindow] Plugin DSP does not support metering:', insertId);
      return;
    }

    // Set the insert ID for meter data identification
    if (typeof vaneqDSP.setInsertId === 'function') {
      vaneqDSP.setInsertId(insertId);
    }

    console.debug(`[usePluginWindow] Starting metering for ${insertId}`);

    // Start metering with callback to send to plugin window
    vaneqDSP.startMetering((meterData: VanEqMeterData) => {
      // Encode FFT bins as base64 for efficient transfer
      const fftBytes = new Uint8Array(meterData.fftBins.buffer);
      let binary = '';
      for (let i = 0; i < fftBytes.length; i++) {
        binary += String.fromCharCode(fftBytes[i]);
      }
      const fftBinsB64 = btoa(binary);

      // Send meter update via host
      host.sendMeterUpdate(insertId, {
        rmsL: meterData.rmsL,
        rmsR: meterData.rmsR,
        peakL: meterData.peakL,
        peakR: meterData.peakR,
        fftBinsB64,
        sampleRate: meterData.sampleRate,
      });
    });

    // Track the metering stop function
    meteringRef.current.set(insertId, {
      pluginId,
      stopMetering: () => {
        if (typeof vaneqDSP.stopMetering === 'function') {
          vaneqDSP.stopMetering();
        }
      },
    });
  }, [host]);

  /**
   * Stop metering for an insert.
   */
  const stopMeteringForInsert = useCallback((insertId: string) => {
    const existing = meteringRef.current.get(insertId);
    if (existing) {
      existing.stopMetering();
      meteringRef.current.delete(insertId);
    }
  }, []);

  /**
   * Open a plugin window.
   */
  const openPluginWindow = useCallback(async (
    insertId: string,
    pluginId: string,
    params: Record<string, number>,
    bypassed: boolean
  ): Promise<boolean> => {
    // Check if this plugin supports standalone windows
    if (!shouldOpenInWindow(pluginId)) {
      return false;
    }

    // Store state for sync
    stateProviderRef.current.set(insertId, { params: { ...params }, bypassed });

    // Open window via host
    const success = host.openPluginWindow(insertId, pluginId);

    // Start metering if window opened successfully
    if (success) {
      startMeteringForInsert(insertId, pluginId);
    }

    return success;
  }, [host, startMeteringForInsert]);

  /**
   * Close a plugin window.
   */
  const closePluginWindow = useCallback(async (insertId: string): Promise<void> => {
    // Stop metering first
    stopMeteringForInsert(insertId);
    host.closePluginWindow(insertId);
    // NOTE: Don't delete state from cache - we want to preserve it for next open
    // The state gets updated by param/bypass callbacks while window is open,
    // so closing and reopening should restore the last known state.
  }, [host, stopMeteringForInsert]);

  /**
   * Update plugin params in a window.
   */
  const updatePluginParams = useCallback(async (
    insertId: string,
    params: Record<string, number>
  ): Promise<void> => {
    // Update local cache
    const state = stateProviderRef.current.get(insertId);
    if (state) {
      state.params = { ...params };
    }

    // Send update to window
    const bypassState = state?.bypassed ?? false;
    host.sendStateUpdate(insertId, params, bypassState);
  }, [host]);

  /**
   * Update bypass state in a window.
   */
  const updatePluginBypass = useCallback(async (
    insertId: string,
    bypassed: boolean
  ): Promise<void> => {
    // Update local cache
    const state = stateProviderRef.current.get(insertId);
    if (state) {
      state.bypassed = bypassed;
    }

    // Send update to window
    const paramsState = state?.params ?? {};
    host.sendStateUpdate(insertId, paramsState, bypassed);
  }, [host]);

  return {
    openPluginWindow,
    closePluginWindow,
    closeAllPluginWindows: host.closeAllPluginWindows,
    updatePluginParams,
    updatePluginBypass,
    isWindowOpen: host.isWindowOpen,
    shouldOpenInWindow,
    popupBlocked: host.popupBlocked,
    clearPopupBlocked: host.clearPopupBlocked,
  };
}

/**
 * ReelForge Plugin Window Sync Hook
 *
 * BroadcastChannel-based synchronization between plugin windows
 * and the main ReelForge app. Works in browser context.
 *
 * CTO Requirements Implemented:
 * - Revision counter for snapshot versioning (ignores stale updates)
 * - Handshake gate before allowing param changes
 * - Project close signal for cleanup
 * - One window per insertId (focus existing)
 *
 * @module plugin-window/usePluginWindowSync
 */

import { useEffect, useCallback, useRef, useState } from 'react';

// Channel name for plugin window communication
const CHANNEL_NAME = 'reelforge-plugin-sync';

/**
 * Message types for plugin window sync.
 */
export type PluginSyncMessageType =
  | 'REQUEST_INITIAL_STATE'
  | 'INITIAL_STATE'
  | 'PARAM_CHANGE'
  | 'PARAM_BATCH'
  | 'BYPASS_CHANGE'
  | 'STATE_UPDATE'
  | 'WINDOW_CLOSED'
  | 'WINDOW_REGISTERED'
  | 'PROJECT_CLOSED'
  | 'HOST_READY'
  | 'PING'
  | 'PONG'
  | 'METER_UPDATE';

/**
 * Meter data for remote analyzer display.
 */
export interface MeterData {
  rmsL: number;
  rmsR: number;
  peakL: number;
  peakR: number;
  /** FFT bins as base64 encoded Float32Array */
  fftBinsB64?: string;
  /** Sample rate for FFT frequency mapping (defaults to 48000) */
  sampleRate?: number;
}

/**
 * Plugin sync message structure with revision for ordering.
 */
export interface PluginSyncMessage {
  type: PluginSyncMessageType;
  insertId: string;
  pluginId?: string;
  params?: Record<string, number>;
  bypassed?: boolean;
  paramId?: string;
  value?: number;
  /** Batch of param changes for PARAM_BATCH messages (atomic update) */
  changes?: Record<string, number>;
  timestamp?: number;
  /** Monotonic revision counter for ordering */
  revision?: number;
  /** Meter data for METER_UPDATE messages */
  meter?: MeterData;
}

/**
 * Connection state for plugin window.
 */
export type PluginWindowConnectionState =
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'project_closed';

/**
 * Hook for plugin window to sync with main app.
 *
 * Used by plugin windows to receive state updates and send param changes.
 * Implements handshake gate - param changes are queued until connected.
 */
export function usePluginWindowSync(
  insertId: string,
  pluginId: string,
  onStateUpdate: (params: Record<string, number>, bypassed: boolean) => void,
  onConnectionChange: (state: PluginWindowConnectionState) => void,
  onMeterUpdate?: (meter: MeterData) => void
) {
  const channelRef = useRef<BroadcastChannel | null>(null);
  const pingIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastPongRef = useRef<number>(0);
  const lastRevisionRef = useRef<number>(-1);
  const isConnectedRef = useRef<boolean>(false);
  const pendingChangesRef = useRef<Array<{ paramId: string; value: number } | { bypassed: boolean }>>([]);

  // Store callbacks in refs to avoid infinite loops from dependency changes
  const onStateUpdateRef = useRef(onStateUpdate);
  const onConnectionChangeRef = useRef(onConnectionChange);
  const onMeterUpdateRef = useRef(onMeterUpdate);

  // Keep refs updated with latest callbacks
  onStateUpdateRef.current = onStateUpdate;
  onConnectionChangeRef.current = onConnectionChange;
  onMeterUpdateRef.current = onMeterUpdate;

  // Initialize channel
  useEffect(() => {
    const channel = new BroadcastChannel(CHANNEL_NAME);
    channelRef.current = channel;
    onConnectionChangeRef.current('connecting');

    // Handle messages from main app
    const handleMessage = (event: MessageEvent<PluginSyncMessage>) => {
      const msg = event.data;

      // Allow broadcast messages (insertId='*') for HOST_READY and PROJECT_CLOSED
      const isBroadcast = msg.insertId === '*';
      const isForThisInsert = msg.insertId === insertId;

      // Only process messages for this insert or broadcasts
      if (!isForThisInsert && !isBroadcast) return;

      switch (msg.type) {
        case 'INITIAL_STATE':
          if (msg.params !== undefined && msg.bypassed !== undefined) {
            // Accept initial state and set revision baseline
            lastRevisionRef.current = msg.revision ?? 0;
            onStateUpdateRef.current(msg.params, msg.bypassed);
            isConnectedRef.current = true;
            onConnectionChangeRef.current('connected');

            // Flush any pending changes
            flushPendingChanges();
          }
          break;

        case 'STATE_UPDATE':
          // Only accept if revision is newer
          if (msg.revision !== undefined && msg.revision <= lastRevisionRef.current) {
            // Stale update, ignore
            return;
          }
          if (msg.params !== undefined && msg.bypassed !== undefined) {
            lastRevisionRef.current = msg.revision ?? lastRevisionRef.current;
            onStateUpdateRef.current(msg.params, msg.bypassed);
          }
          break;

        case 'PROJECT_CLOSED':
          // Project was closed/switched - disable editing
          isConnectedRef.current = false;
          onConnectionChangeRef.current('project_closed');
          break;

        case 'PONG':
          lastPongRef.current = Date.now();
          if (!isConnectedRef.current) {
            // Reconnected after disconnect
            isConnectedRef.current = true;
            onConnectionChangeRef.current('connected');
          }
          break;

        case 'HOST_READY':
          // Host (main app) just started/restarted
          // Request initial state to reconnect
          channel.postMessage({
            type: 'REQUEST_INITIAL_STATE',
            insertId,
            pluginId,
            timestamp: Date.now(),
          } satisfies PluginSyncMessage);
          break;

        case 'METER_UPDATE':
          // Receive meter data from main app for analyzer display
          if (msg.meter && onMeterUpdateRef.current) {
            onMeterUpdateRef.current(msg.meter);
          }
          break;
      }
    };

    channel.addEventListener('message', handleMessage);

    // Ping interval to check connection
    pingIntervalRef.current = setInterval(() => {
      const elapsed = Date.now() - lastPongRef.current;
      if (elapsed > 5000 && isConnectedRef.current) {
        isConnectedRef.current = false;
        onConnectionChangeRef.current('disconnected');
      }
      channel.postMessage({
        type: 'PING',
        insertId,
        pluginId,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    }, 2000);

    // Request initial state
    channel.postMessage({
      type: 'REQUEST_INITIAL_STATE',
      insertId,
      pluginId,
      timestamp: Date.now(),
    } satisfies PluginSyncMessage);

    return () => {
      // Notify window closing
      channel.postMessage({
        type: 'WINDOW_CLOSED',
        insertId,
        pluginId,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);

      if (pingIntervalRef.current) {
        clearInterval(pingIntervalRef.current);
      }
      channel.removeEventListener('message', handleMessage);
      channel.close();
      channelRef.current = null;
    };
    // Note: callbacks are accessed via refs, so they don't need to be in dependencies
  }, [insertId, pluginId]);

  // Flush pending changes after connection
  const flushPendingChanges = useCallback(() => {
    const channel = channelRef.current;
    if (!channel) return;

    for (const change of pendingChangesRef.current) {
      if ('paramId' in change) {
        channel.postMessage({
          type: 'PARAM_CHANGE',
          insertId,
          pluginId,
          paramId: change.paramId,
          value: change.value,
          timestamp: Date.now(),
        } satisfies PluginSyncMessage);
      } else {
        channel.postMessage({
          type: 'BYPASS_CHANGE',
          insertId,
          pluginId,
          bypassed: change.bypassed,
          timestamp: Date.now(),
        } satisfies PluginSyncMessage);
      }
    }
    pendingChangesRef.current = [];
  }, [insertId, pluginId]);

  // Send param change to main app (queued if not connected)
  const sendParamChange = useCallback(
    (paramId: string, value: number) => {
      if (!isConnectedRef.current) {
        // Queue the change
        pendingChangesRef.current.push({ paramId, value });
        return;
      }
      channelRef.current?.postMessage({
        type: 'PARAM_CHANGE',
        insertId,
        pluginId,
        paramId,
        value,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    },
    [insertId, pluginId]
  );

  // Send batch param changes to main app (atomic update - prevents race conditions)
  const sendParamBatch = useCallback(
    (changes: Record<string, number>) => {
      if (!isConnectedRef.current) {
        // Queue individual changes (batch not supported in queue)
        for (const [paramId, value] of Object.entries(changes)) {
          pendingChangesRef.current.push({ paramId, value });
        }
        return;
      }
      channelRef.current?.postMessage({
        type: 'PARAM_BATCH',
        insertId,
        pluginId,
        changes,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    },
    [insertId, pluginId]
  );

  // Send bypass change to main app (queued if not connected)
  const sendBypassChange = useCallback(
    (bypassed: boolean) => {
      if (!isConnectedRef.current) {
        // Queue the change
        pendingChangesRef.current.push({ bypassed });
        return;
      }
      channelRef.current?.postMessage({
        type: 'BYPASS_CHANGE',
        insertId,
        pluginId,
        bypassed,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    },
    [insertId, pluginId]
  );

  // Request initial state
  const requestInitialState = useCallback(() => {
    channelRef.current?.postMessage({
      type: 'REQUEST_INITIAL_STATE',
      insertId,
      pluginId,
      timestamp: Date.now(),
    } satisfies PluginSyncMessage);
  }, [insertId, pluginId]);

  return {
    sendParamChange,
    sendParamBatch,
    sendBypassChange,
    requestInitialState,
    isConnected: isConnectedRef.current,
  };
}

/**
 * Window tracking info for the host.
 */
interface TrackedWindow {
  pluginId: string;
  windowRef: Window | null;
  revision: number;
}

/**
 * Module-level singleton for window tracking.
 * CRITICAL: This MUST be at module level to persist across React re-renders.
 * React hooks create new refs on each render, which breaks metering callbacks
 * that capture the old ref. By using module-level state, we ensure all hook
 * instances share the same window tracking Map.
 */
const moduleOpenWindows = new Map<string, TrackedWindow>();
const moduleRevision = { current: 0 };
let moduleChannel: BroadcastChannel | null = null;
let moduleStateProvider: ((insertId: string) => { params: Record<string, number>; bypassed: boolean } | null) | null = null;

// Module-level callback refs for handling messages (updated on each hook render)
const moduleCallbacks = {
  onParamChange: null as ((insertId: string, paramId: string, value: number) => void) | null,
  onBypassChange: null as ((insertId: string, bypassed: boolean) => void) | null,
  onParamBatch: null as ((insertId: string, changes: Record<string, number>) => void) | null,
};

/**
 * Hook for main app to manage plugin window sync.
 *
 * Used by the main app to track open windows and sync state.
 * Implements revision counter for proper ordering.
 */
export function usePluginWindowHost(
  onParamChange: (insertId: string, paramId: string, value: number) => void,
  onBypassChange: (insertId: string, bypassed: boolean) => void,
  onParamBatch?: (insertId: string, changes: Record<string, number>) => void
) {
  const [popupBlocked, setPopupBlocked] = useState<string | null>(null);

  // Update module-level callbacks on each render
  // This ensures the message handler always uses the latest callbacks
  moduleCallbacks.onParamChange = onParamChange;
  moduleCallbacks.onBypassChange = onBypassChange;
  moduleCallbacks.onParamBatch = onParamBatch ?? null;

  // Initialize channel (only once at module level)
  useEffect(() => {
    // If channel already exists at module level, just return
    if (moduleChannel) {
      return;
    }

    const channel = new BroadcastChannel(CHANNEL_NAME);
    moduleChannel = channel;

    // Broadcast HOST_READY to any orphaned plugin windows
    // This allows them to reconnect after main app refresh
    channel.postMessage({
      type: 'HOST_READY',
      insertId: '*',
      timestamp: Date.now(),
    } satisfies PluginSyncMessage);

    // Handle messages from plugin windows
    // Uses module-level callbacks which are updated on each hook render
    const handleMessage = (event: MessageEvent<PluginSyncMessage>) => {
      const msg = event.data;

      switch (msg.type) {
        case 'REQUEST_INITIAL_STATE':
          console.debug('[PluginWindowHost] REQUEST_INITIAL_STATE received:', msg.insertId);
          // Send current state to the requesting window
          if (moduleStateProvider && msg.insertId) {
            const state = moduleStateProvider(msg.insertId);
            console.debug('[PluginWindowHost] stateProvider returned:', state ? {
              paramCount: Object.keys(state.params).length,
              bypassed: state.bypassed,
              sampleParams: Object.entries(state.params).slice(0, 3),
            } : null);
            if (state) {
              moduleRevision.current += 1;
              const revision = moduleRevision.current;
              // Update tracked window revision
              const tracked = moduleOpenWindows.get(msg.insertId);
              if (tracked) {
                tracked.revision = revision;
              }
              console.debug('[PluginWindowHost] Sending INITIAL_STATE:', { insertId: msg.insertId, revision });
              channel.postMessage({
                type: 'INITIAL_STATE',
                insertId: msg.insertId,
                pluginId: msg.pluginId,
                params: state.params,
                bypassed: state.bypassed,
                revision,
                timestamp: Date.now(),
              } satisfies PluginSyncMessage);
            } else {
              // No state available for this insert (orphaned window after refresh)
              // Tell the window to close
              console.warn('[PluginWindowHost] No state available, sending PROJECT_CLOSED');
              channel.postMessage({
                type: 'PROJECT_CLOSED',
                insertId: msg.insertId,
                timestamp: Date.now(),
              } satisfies PluginSyncMessage);
            }
          } else {
            console.warn('[PluginWindowHost] No stateProvider or insertId:', { hasProvider: !!moduleStateProvider, insertId: msg.insertId });
          }
          break;

        case 'PARAM_CHANGE':
          if (msg.insertId && msg.paramId !== undefined && msg.value !== undefined) {
            moduleCallbacks.onParamChange?.(msg.insertId, msg.paramId, msg.value);
          }
          break;

        case 'PARAM_BATCH':
          // Atomic batch update - all params applied at once
          if (msg.insertId && msg.changes) {
            if (moduleCallbacks.onParamBatch) {
              moduleCallbacks.onParamBatch(msg.insertId, msg.changes);
            } else if (moduleCallbacks.onParamChange) {
              // Fallback: apply individually (less ideal but works)
              for (const [paramId, value] of Object.entries(msg.changes)) {
                moduleCallbacks.onParamChange(msg.insertId, paramId, value);
              }
            }
          }
          break;

        case 'BYPASS_CHANGE':
          if (msg.insertId && msg.bypassed !== undefined) {
            moduleCallbacks.onBypassChange?.(msg.insertId, msg.bypassed);
          }
          break;

        case 'PING':
          // Respond with pong
          channel.postMessage({
            type: 'PONG',
            insertId: msg.insertId,
            timestamp: Date.now(),
          } satisfies PluginSyncMessage);
          break;

        case 'WINDOW_CLOSED':
          moduleOpenWindows.delete(msg.insertId);
          break;
      }
    };

    channel.addEventListener('message', handleMessage);

    // Note: We intentionally do NOT clean up the channel on unmount
    // because module-level state should persist across React re-renders
    return () => {
      // Only cleanup if component is truly being destroyed (page unload)
      // For now, keep the channel alive to support React StrictMode double-mount
    };
  }, []);

  // Set state provider callback (uses module-level state)
  const setStateProvider = useCallback(
    (provider: (insertId: string) => { params: Record<string, number>; bypassed: boolean } | null) => {
      moduleStateProvider = provider;
    },
    []
  );

  // Open a plugin window (uses module-level window tracking)
  const openPluginWindow = useCallback(
    (insertId: string, pluginId: string): boolean => {
      // Check if window already open
      const existing = moduleOpenWindows.get(insertId);
      if (existing?.windowRef && !existing.windowRef.closed) {
        // Focus existing window
        existing.windowRef.focus();
        return true;
      }

      // Determine window size based on plugin
      let width = 800;
      let height = 500;
      switch (pluginId) {
        case 'vaneq': {
          // FabFilter-style fixed window presets (S/M/L) - must match VanEQProEditor.tsx
          const VANEQ_SIZES: Record<string, { w: number; h: number }> = {
            S: { w: 1000, h: 620 },
            M: { w: 1250, h: 760 },
            L: { w: 1550, h: 950 },
          };
          let storedSize = 'M';
          try {
            const stored = localStorage.getItem('vaneq_size');
            if (stored === 'S' || stored === 'M' || stored === 'L') {
              storedSize = stored;
            }
          } catch { /* ignore */ }
          const size = VANEQ_SIZES[storedSize];
          width = size.w;
          height = size.h;
          break;
        }
        case 'vancomp':
          width = 850;
          height = 480;
          break;
        case 'vanlimit':
          width = 850;
          height = 450;
          break;
      }

      // Calculate centered position
      const left = Math.round((window.screen.width - width) / 2);
      const top = Math.round((window.screen.height - height) / 2);

      // Open new window
      // Note: alwaysOnTop is not a standard browser feature, but Electron can use it
      const features = `width=${width},height=${height},left=${left},top=${top},resizable=no,scrollbars=no,alwaysOnTop=yes`;
      const url = `/plugin.html?insertId=${encodeURIComponent(insertId)}&pluginId=${encodeURIComponent(pluginId)}`;

      console.debug('[PluginWindowHost] Opening window:', { url, features, insertId, pluginId });

      const windowRef = window.open(url, `plugin-${insertId}`, features);

      if (windowRef) {
        console.debug('[PluginWindowHost] Window opened successfully, tracking at module level');
        moduleOpenWindows.set(insertId, {
          pluginId,
          windowRef,
          revision: moduleRevision.current
        });

        // Try to keep window on top by refocusing when main window gets focus
        // This is a workaround for browsers that don't support alwaysOnTop
        const keepOnTop = () => {
          if (windowRef && !windowRef.closed) {
            windowRef.focus();
          } else {
            window.removeEventListener('focus', keepOnTop);
          }
        };
        // Focus plugin window when main app window gains focus
        window.addEventListener('focus', keepOnTop);

        setPopupBlocked(null);
        return true;
      } else {
        // Popup was blocked
        console.warn('[PluginWindowHost] Popup BLOCKED by browser');
        setPopupBlocked(insertId);
        return false;
      }
    },
    []
  );

  // Close a plugin window (uses module-level window tracking)
  const closePluginWindow = useCallback((insertId: string) => {
    const existing = moduleOpenWindows.get(insertId);
    if (existing?.windowRef && !existing.windowRef.closed) {
      existing.windowRef.close();
    }
    moduleOpenWindows.delete(insertId);
  }, []);

  // Close all plugin windows (for project switch, uses module-level state)
  const closeAllPluginWindows = useCallback(() => {
    // Send project closed signal to all windows
    moduleChannel?.postMessage({
      type: 'PROJECT_CLOSED',
      insertId: '*', // Broadcast to all
      timestamp: Date.now(),
    } satisfies PluginSyncMessage);

    // Close all tracked windows
    for (const [, tracked] of moduleOpenWindows) {
      if (tracked.windowRef && !tracked.windowRef.closed) {
        tracked.windowRef.close();
      }
    }
    moduleOpenWindows.clear();
  }, []);

  // Check if window is open for an insert (uses module-level state)
  const isWindowOpen = useCallback((insertId: string): boolean => {
    const existing = moduleOpenWindows.get(insertId);
    return existing?.windowRef != null && !existing.windowRef.closed;
  }, []);

  // Send state update to a specific window with revision (uses module-level state)
  const sendStateUpdate = useCallback(
    (insertId: string, params: Record<string, number>, bypassed: boolean) => {
      moduleRevision.current += 1;
      const revision = moduleRevision.current;
      // Update tracked window revision
      const tracked = moduleOpenWindows.get(insertId);
      if (tracked) {
        tracked.revision = revision;
      }
      moduleChannel?.postMessage({
        type: 'STATE_UPDATE',
        insertId,
        params,
        bypassed,
        revision,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    },
    []
  );

  // Clear popup blocked state
  const clearPopupBlocked = useCallback(() => {
    setPopupBlocked(null);
  }, []);

  // Send meter update to a specific window (uses module-level state)
  // Fire-and-forget, no revision needed
  const sendMeterUpdate = useCallback(
    (insertId: string, meter: MeterData) => {
      // Only send if window is open (uses module-level tracking)
      const tracked = moduleOpenWindows.get(insertId);
      if (!tracked?.windowRef || tracked.windowRef.closed) {
        return;
      }

      moduleChannel?.postMessage({
        type: 'METER_UPDATE',
        insertId,
        meter,
        timestamp: Date.now(),
      } satisfies PluginSyncMessage);
    },
    []
  );

  return {
    openPluginWindow,
    closePluginWindow,
    closeAllPluginWindows,
    isWindowOpen,
    sendStateUpdate,
    sendMeterUpdate,
    setStateProvider,
    popupBlocked,
    clearPopupBlocked,
  };
}

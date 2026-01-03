/**
 * ReelForge Plugin Editor Drawer
 *
 * Global editor container that displays the selected insert's editor.
 * Split into Shell + Content to ensure stable hook order.
 *
 * Shell: Always mounted, stable hooks, decides whether to render content
 * Content: Only mounted when selection exists, can have any hooks
 *
 * For plugins with opensInWindow=true (like VanEQ), opens a standalone browser
 * window instead of the drawer. Uses BroadcastChannel for param sync.
 *
 * CTO Requirements:
 * - Popup blocked detection with fallback banner
 * - Project switch closes all plugin windows
 * - One window per insertId (focus existing)
 *
 * @module plugin/PluginEditorDrawer
 */

import { useCallback, useEffect, useMemo, useRef } from 'react';
import { useInsertSelection, type InsertSelection } from './InsertSelectionContext';
import { getPluginDefinition } from './pluginRegistry';
import { useMixer, useMasterInsertSampleRate } from '../store';
import { usePluginWindow, shouldOpenInWindow } from './usePluginWindow';
import type { ParamDescriptor } from './ParamDescriptor';
import type { OnParamChange, OnParamReset, OnBypassChange } from './InsertSelectionContext';
import './PluginEditorDrawer.css';

// ============================================================================
// CONTENT COMPONENT (mounted only when selection exists)
// ============================================================================

interface DrawerContentProps {
  selection: InsertSelection;
  onClose: () => void;
  onParamChange: OnParamChange | null;
  onParamReset: OnParamReset | null;
  onBypassChange: OnBypassChange | null;
  /** AudioContext sample rate for accurate frequency calculations */
  sampleRate: number;
}

/**
 * Inner content component - only mounted when there's a valid selection.
 * Can safely use any hooks since it mounts/unmounts cleanly.
 */
function PluginEditorDrawerContent({
  selection,
  onClose,
  onParamChange,
  onParamReset,
  onBypassChange,
  sampleRate,
}: DrawerContentProps) {
  // Get plugin definition
  const pluginDef = useMemo(() => {
    return getPluginDefinition(selection.pluginId);
  }, [selection.pluginId]);

  // Get param descriptors from plugin definition
  const descriptors = useMemo((): ParamDescriptor[] => {
    // Van* plugins have descriptors in their plugin definition
    return pluginDef?.params ?? [];
  }, [pluginDef]);

  // Get scope label
  const scopeLabel = useMemo(() => {
    switch (selection.scope) {
      case 'master':
        return 'Master';
      case 'bus':
        return selection.busId ? `Bus: ${selection.busId}` : 'Bus';
      case 'asset':
        return selection.assetId ? `Asset: ${selection.assetId}` : 'Asset';
      default:
        return '';
    }
  }, [selection.scope, selection.busId, selection.assetId]);

  // Handle param change
  const handleParamChange = useCallback(
    (paramId: string, value: number) => {
      if (onParamChange) {
        onParamChange(paramId, value);
      }
    },
    [onParamChange]
  );

  // Handle param reset
  const handleParamReset = useCallback(
    (paramId: string) => {
      if (onParamReset) {
        onParamReset(paramId);
      }
    },
    [onParamReset]
  );

  // Handle bypass change
  const handleBypassChange = useCallback(
    (bypassed: boolean) => {
      if (onBypassChange) {
        onBypassChange(bypassed);
      }
    },
    [onBypassChange]
  );

  // Get plugin info
  const pluginIcon = pluginDef?.icon ?? '🔌';
  const pluginName = pluginDef?.displayName ?? selection.pluginId;

  // Get Editor component
  const Editor = pluginDef?.Editor;

  return (
    <div className="rf-plugin-drawer">
      <div className="rf-plugin-drawer-overlay" onClick={onClose} />
      <div className="rf-plugin-drawer-panel">
        <div className="rf-plugin-drawer-header">
          <div className="rf-plugin-drawer-title">
            <span className="rf-plugin-drawer-icon">{pluginIcon}</span>
            <span className="rf-plugin-drawer-name">{pluginName}</span>
            <span className="rf-plugin-drawer-scope">{scopeLabel}</span>
          </div>
          <div className="rf-plugin-drawer-actions">
            <button
              className={`rf-plugin-drawer-bypass ${selection.bypassed ? 'bypassed' : ''}`}
              onClick={() => handleBypassChange(!selection.bypassed)}
              title={selection.bypassed ? 'Enable' : 'Bypass'}
            >
              {selection.bypassed ? 'OFF' : 'ON'}
            </button>
            <button
              className="rf-plugin-drawer-close"
              onClick={onClose}
              title="Close (Esc)"
            >
              ×
            </button>
          </div>
        </div>

        <div className="rf-plugin-drawer-content">
          {Editor ? (
            <Editor
              params={selection.params}
              descriptors={descriptors}
              onChange={handleParamChange}
              onReset={handleParamReset}
              onBypassChange={handleBypassChange}
              bypassed={selection.bypassed}
              sampleRate={sampleRate}
            />
          ) : (
            <div className="rf-plugin-drawer-no-editor">
              No editor available for {pluginName}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// ============================================================================
// SHELL COMPONENT (always mounted, stable hook order)
// ============================================================================

/**
 * Plugin Editor Drawer Shell.
 *
 * Always mounted at App level with stable hook order.
 * Renders content only when selection exists and plugin doesn't open in window.
 *
 * For plugins with opensInWindow=true, opens a standalone browser window instead.
 */
export function PluginEditorDrawer() {
  // ---- HOOKS (always called in same order) ----
  const {
    selection,
    clearSelection,
    onParamChange,
    onParamReset,
    onBypassChange,
    onParamBatch,
  } = useInsertSelection();

  const { state: mixerState } = useMixer();

  // Get sampleRate for accurate frequency calculations in EQ plugins
  // Uses safe hook with fallback (48000) when outside MasterInsertProvider
  const sampleRate = useMasterInsertSampleRate();

  // Track if we opened a window (to avoid re-opening)
  const windowOpenedRef = useRef<string | null>(null);

  // Store callbacks for open windows (persists after clearSelection clears the context callbacks)
  // Key: insertId, Value: { onParamChange, onParamBatch, onBypassChange }
  const windowCallbacksRef = useRef<Map<string, {
    onParamChange: (paramId: string, value: number) => void;
    onParamBatch: (changes: Record<string, number>) => void;
    onBypassChange: (bypassed: boolean) => void;
  }>>(new Map());

  // Plugin window hook for standalone windows
  const {
    openPluginWindow,
    closeAllPluginWindows,
    updatePluginParams,
    updatePluginBypass,
    popupBlocked,
    clearPopupBlocked,
  } = usePluginWindow(
    // Handle param changes from plugin window
    (insertId, paramId, value) => {
      // First check stored callbacks (for windows that are open after selection was cleared)
      const storedCallbacks = windowCallbacksRef.current.get(insertId);
      if (storedCallbacks) {
        storedCallbacks.onParamChange(paramId, value);
        return;
      }
      // Fallback to current selection callbacks (shouldn't normally happen for windows)
      if (onParamChange && selection?.insertId === insertId) {
        onParamChange(paramId, value);
      }
    },
    // Handle bypass changes from plugin window
    (insertId, bypassed) => {
      // First check stored callbacks (for windows that are open after selection was cleared)
      const storedCallbacks = windowCallbacksRef.current.get(insertId);
      if (storedCallbacks) {
        storedCallbacks.onBypassChange(bypassed);
        return;
      }
      // Fallback to current selection callbacks (shouldn't normally happen for windows)
      if (onBypassChange && selection?.insertId === insertId) {
        onBypassChange(bypassed);
      }
    },
    // Handle batch param changes from plugin window (ATOMIC update - prevents race conditions)
    (insertId, changes) => {
      console.debug('[PluginEditorDrawer] onParamBatch received:', {
        insertId,
        changeCount: Object.keys(changes).length,
        hasStoredCallbacks: windowCallbacksRef.current.has(insertId),
      });
      const storedCallbacks = windowCallbacksRef.current.get(insertId);
      if (storedCallbacks) {
        storedCallbacks.onParamBatch(changes);
      } else {
        console.warn('[PluginEditorDrawer] No stored callbacks for insertId:', insertId);
      }
    }
  );

  // Track last project ID to detect project switch
  const lastProjectIdRef = useRef<string | null>(null);

  // Handle close - stable callback
  const handleClose = useCallback(() => {
    clearSelection();
  }, [clearSelection]);

  // Check if current selection should open in window
  const usesWindow = selection ? shouldOpenInWindow(selection.pluginId) : false;

  // DEBUG: Log selection changes
  useEffect(() => {
    if (selection) {
      console.debug('[PluginEditorDrawer] Selection changed:', {
        pluginId: selection.pluginId,
        insertId: selection.insertId,
        usesWindow,
        hasParamChange: !!onParamChange,
        hasBypassChange: !!onBypassChange,
      });
    }
  }, [selection, usesWindow, onParamChange, onBypassChange]);

  // Open plugin window when selection changes (for window-based plugins)
  useEffect(() => {
    if (!selection || !usesWindow) {
      windowOpenedRef.current = null;
      return;
    }

    // Avoid re-opening the same window
    if (windowOpenedRef.current === selection.insertId) {
      return;
    }

    // Wait for callbacks to be set (they're set in a separate state update)
    // This fixes race condition where selection is set but callbacks aren't ready yet
    if (!onParamChange || !onBypassChange) {
      console.debug('[PluginEditorDrawer] Waiting for callbacks...', { selection: selection.insertId });
      return;
    }

    console.debug('[PluginEditorDrawer] Opening plugin window:', {
      insertId: selection.insertId,
      pluginId: selection.pluginId,
    });

    // Store callbacks BEFORE clearing selection (they come from context and will be cleared)
    windowCallbacksRef.current.set(selection.insertId, {
      onParamChange,
      onParamBatch: onParamBatch ?? ((changes) => {
        // Fallback: apply changes sequentially if no batch handler
        for (const [paramId, value] of Object.entries(changes)) {
          onParamChange(paramId, value);
        }
      }),
      onBypassChange,
    });

    // Open the window
    openPluginWindow(
      selection.insertId,
      selection.pluginId,
      selection.params,
      selection.bypassed
    ).then((success) => {
      if (success) {
        console.debug('[PluginEditorDrawer] Plugin window opened successfully');
        windowOpenedRef.current = selection.insertId;
        // Clear selection since window is now open
        // Note: callbacks are preserved in windowCallbacksRef
        clearSelection();
      } else {
        console.warn('[PluginEditorDrawer] Plugin window open FAILED (popup blocked?)');
        // Window open failed, remove stored callbacks
        windowCallbacksRef.current.delete(selection.insertId);
      }
    });
  }, [selection, usesWindow, openPluginWindow, clearSelection, onParamChange, onParamBatch, onBypassChange]);

  // Sync params to plugin window when they change
  useEffect(() => {
    if (!selection || !usesWindow) return;
    if (windowOpenedRef.current !== selection.insertId) return;

    updatePluginParams(selection.insertId, selection.params);
  }, [selection, usesWindow, updatePluginParams]);

  // Sync bypass to plugin window when it changes
  useEffect(() => {
    if (!selection || !usesWindow) return;
    if (windowOpenedRef.current !== selection.insertId) return;

    updatePluginBypass(selection.insertId, selection.bypassed);
  }, [selection, usesWindow, updatePluginBypass]);

  // Auto-close drawer when mixer closes
  // This prevents "blank screen" when mixer X is clicked while drawer is open
  useEffect(() => {
    if (!mixerState.isVisible && selection) {
      clearSelection();
    }
  }, [mixerState.isVisible, selection, clearSelection]);

  // Handle escape key to close (only when drawer is open)
  useEffect(() => {
    if (!selection || usesWindow) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        clearSelection();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [selection, usesWindow, clearSelection]);

  // Detect project switch and close all plugin windows
  useEffect(() => {
    const currentProjectId = mixerState.project?.id ?? null;

    // On first mount, just store the project ID
    if (lastProjectIdRef.current === null) {
      lastProjectIdRef.current = currentProjectId;
      return;
    }

    // If project changed, close all plugin windows
    if (currentProjectId !== lastProjectIdRef.current) {
      closeAllPluginWindows();
      windowOpenedRef.current = null;
      // Clear all stored callbacks since windows are closed
      windowCallbacksRef.current.clear();
      lastProjectIdRef.current = currentProjectId;
    }
  }, [mixerState.project?.id, closeAllPluginWindows]);

  // Close all plugin windows when app reloads or closes
  useEffect(() => {
    const handleBeforeUnload = () => {
      closeAllPluginWindows();
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload);
      // Also close windows on component unmount
      closeAllPluginWindows();
    };
  }, [closeAllPluginWindows]);

  // Retry opening window after popup was blocked
  const handleRetryOpenWindow = useCallback(() => {
    if (!popupBlocked || !selection) return;

    clearPopupBlocked();

    // Store callbacks before opening
    if (onParamChange && onBypassChange) {
      windowCallbacksRef.current.set(selection.insertId, {
        onParamChange,
        onParamBatch: onParamBatch ?? ((changes) => {
          for (const [paramId, value] of Object.entries(changes)) {
            onParamChange(paramId, value);
          }
        }),
        onBypassChange,
      });
    }

    openPluginWindow(
      selection.insertId,
      selection.pluginId,
      selection.params,
      selection.bypassed
    ).then((success) => {
      if (success) {
        windowOpenedRef.current = selection.insertId;
        clearSelection();
      } else {
        windowCallbacksRef.current.delete(selection.insertId);
      }
    });
  }, [popupBlocked, selection, clearPopupBlocked, openPluginWindow, clearSelection, onParamChange, onParamBatch, onBypassChange]);

  // ---- RENDER (after all hooks) ----

  // Popup blocked banner
  if (popupBlocked) {
    return (
      <div className="rf-plugin-popup-blocked">
        <div className="rf-plugin-popup-blocked-content">
          <span className="rf-plugin-popup-blocked-icon">🚫</span>
          <div className="rf-plugin-popup-blocked-text">
            <strong>Popup Blocked</strong>
            <p>Your browser blocked the plugin window. Please allow popups for this site.</p>
          </div>
          <div className="rf-plugin-popup-blocked-actions">
            <button onClick={handleRetryOpenWindow}>Try Again</button>
            <button onClick={clearPopupBlocked}>Dismiss</button>
          </div>
        </div>
      </div>
    );
  }

  // Don't render content if no selection or using window
  if (!selection || usesWindow) {
    return null;
  }

  // Render content component (safe to mount/unmount)
  return (
    <PluginEditorDrawerContent
      selection={selection}
      onClose={handleClose}
      onParamChange={onParamChange}
      onParamReset={onParamReset}
      onBypassChange={onBypassChange}
      sampleRate={sampleRate}
    />
  );
}

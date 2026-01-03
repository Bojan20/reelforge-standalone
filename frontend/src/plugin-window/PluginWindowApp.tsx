/**
 * ReelForge Plugin Window App
 *
 * Main component for plugin editor windows.
 * Manages state synchronization with the main window via BroadcastChannel.
 *
 * CTO Requirements:
 * - Hard-fail UI for unknown pluginId (RF_ERR, not crash)
 * - Proper connection state handling (connecting, connected, disconnected, project_closed)
 * - Read-only mode when disconnected or project closed
 *
 * @module plugin-window/PluginWindowApp
 */

import { useState, useCallback, useMemo, useEffect, useRef, Component, type ReactNode, type ErrorInfo } from 'react';
import { usePluginWindowSync, type PluginWindowConnectionState, type MeterData } from './usePluginWindowSync';
import VanEQProEditor from '../plugin/vaneq-pro/VanEQProEditor';
import { VanCompProEditor } from '../plugin/vancomp-pro/VanCompProEditor';
import { VanLimitProEditor } from '../plugin/vanlimit-pro/VanLimitProEditor';
import { VANEQ_PARAM_DESCRIPTORS } from '../plugin/vaneqDescriptors';
import { VANCOMP_PARAM_DESCRIPTORS } from '../plugin/vancomp-pro/vancompDescriptors';
import { VANLIMIT_PARAM_DESCRIPTORS } from '../plugin/vanlimit-pro/vanlimitDescriptors';
import { isPluginRegistered, getPluginDefinition, getPluginParamDescriptors } from '../plugin/pluginRegistry';
import './PluginWindowApp.css';

/**
 * Error Boundary for plugin editors
 * Prevents plugin render errors from crashing the entire window
 */
interface PluginErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class PluginErrorBoundary extends Component<{ children: ReactNode; pluginId: string }, PluginErrorBoundaryState> {
  constructor(props: { children: ReactNode; pluginId: string }) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): PluginErrorBoundaryState {
    return { hasError: true, error };
  }

  override componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('[PluginErrorBoundary] Plugin render error:', error, errorInfo);
  }

  override render() {
    if (this.state.hasError) {
      return (
        <div className="rf-plugin-window-error-state">
          <div className="rf-plugin-window-hard-fail">
            <span className="rf-plugin-window-error-icon">💥</span>
            <h2>Plugin Render Error</h2>
            <p>The {this.props.pluginId} plugin encountered an error while rendering.</p>
            <div className="rf-plugin-window-error-details">
              <code>{this.state.error?.message || 'Unknown error'}</code>
            </div>
            <button onClick={() => this.setState({ hasError: false, error: null })}>
              Try Again
            </button>
            <button onClick={() => window.close()} style={{ marginLeft: 8 }}>
              Close Window
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

interface PluginWindowAppProps {
  insertId: string;
  pluginId: string;
}

/**
 * Get default params for a plugin.
 */
function getDefaultParams(pluginId: string): Record<string, number> {
  const params: Record<string, number> = {};

  let descriptors;
  switch (pluginId) {
    case 'vaneq':
      descriptors = VANEQ_PARAM_DESCRIPTORS;
      break;
    case 'vancomp':
      descriptors = VANCOMP_PARAM_DESCRIPTORS;
      break;
    case 'vanlimit':
      descriptors = VANLIMIT_PARAM_DESCRIPTORS;
      break;
    default:
      descriptors = getPluginParamDescriptors(pluginId);
  }

  for (const desc of descriptors) {
    params[desc.id] = desc.default;
  }

  return params;
}

/**
 * Check if a pluginId is valid for standalone windows.
 */
function isValidWindowPlugin(pluginId: string): boolean {
  if (!isPluginRegistered(pluginId)) return false;
  const def = getPluginDefinition(pluginId);
  return def?.opensInWindow === true;
}

/**
 * Plugin Window App Component
 */
export function PluginWindowApp({ insertId, pluginId }: PluginWindowAppProps) {
  // Validate pluginId first - this is the hard-fail check
  const isValidPlugin = useMemo(() => isValidWindowPlugin(pluginId), [pluginId]);

  // Initialize with default params, will be updated via sync
  const [params, setParams] = useState<Record<string, number>>(() =>
    getDefaultParams(pluginId)
  );
  const [bypassed, setBypassed] = useState(false);
  const [connectionState, setConnectionState] = useState<PluginWindowConnectionState>('connecting');
  const [meterData, setMeterData] = useState<MeterData | null>(null);

  // Track when a knob drag is in progress - ignore host param echo during drag
  // This prevents jitter when the host sends back stale values mid-drag
  const isDraggingRef = useRef(false);

  // Prevent manual window resize by restoring size on resize event
  // Note: resizeTo() requires same-origin windows (popup from main app)
  const initialSizeRef = useRef<{ width: number; height: number } | null>(null);
  const resizeRafRef = useRef<number>(0);

  useEffect(() => {
    // Read target size from localStorage for vaneq plugin
    // and explicitly resize window after a short delay to ensure it applies
    const applyInitialSize = () => {
      if (pluginId === 'vaneq') {
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
        // Force apply size after window is ready
        try {
          window.resizeTo(size.w, size.h);
        } catch { /* ignore */ }
        initialSizeRef.current = { width: size.w, height: size.h };
      } else {
        initialSizeRef.current = {
          width: window.outerWidth,
          height: window.outerHeight,
        };
      }
    };

    // Wait for window to be ready, then apply size
    // Using multiple frames to ensure browser has finished initial layout
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        applyInitialSize();
      });
    });

    // Listen for programmatic resize from VanEQProEditor S/M/L buttons
    // This updates our stored size so we don't fight against it
    const handleProgrammaticResize = (e: Event) => {
      const { width, height } = (e as CustomEvent<{ width: number; height: number }>).detail;
      initialSizeRef.current = { width, height };
    };

    const handleResize = () => {
      // Cancel any pending resize restore
      if (resizeRafRef.current) {
        cancelAnimationFrame(resizeRafRef.current);
      }

      // Use RAF to batch resize corrections and avoid fighting with the browser
      resizeRafRef.current = requestAnimationFrame(() => {
        if (initialSizeRef.current) {
          const { width, height } = initialSizeRef.current;
          // Only restore if size actually changed (not just position)
          if (window.outerWidth !== width || window.outerHeight !== height) {
            try {
              window.resizeTo(width, height);
            } catch {
              // resizeTo may fail in some browser contexts, ignore
            }
          }
        }
      });
    };

    window.addEventListener('vaneq-programmatic-resize', handleProgrammaticResize);
    window.addEventListener('resize', handleResize);
    return () => {
      window.removeEventListener('vaneq-programmatic-resize', handleProgrammaticResize);
      window.removeEventListener('resize', handleResize);
      if (resizeRafRef.current) {
        cancelAnimationFrame(resizeRafRef.current);
      }
    };
  }, []);

  // Decode FFT bins from base64 to Float32Array for spectrum analyzer
  const spectrumData = useMemo(() => {
    if (!meterData?.fftBinsB64) return null;
    try {
      const binary = atob(meterData.fftBinsB64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      const fftDb = new Float32Array(bytes.buffer);
      // Use actual sample rate from audio context (fallback to 48kHz for compatibility)
      return { fftDb, sampleRate: meterData.sampleRate ?? 48000 };
    } catch {
      return null;
    }
  }, [meterData]);

  // Handle state updates from main app
  // IMPORTANT: Skip param updates during drag to prevent jitter from host echo
  const handleStateUpdate = useCallback(
    (newParams: Record<string, number>, newBypassed: boolean) => {
      console.debug('[PluginWindowApp] handleStateUpdate received:', {
        paramCount: Object.keys(newParams).length,
        bypassed: newBypassed,
        sampleParams: Object.entries(newParams).slice(0, 3),
        isDragging: isDraggingRef.current,
      });

      // Always update bypass (not affected by knob drag)
      setBypassed(newBypassed);

      // Skip param updates during drag - local preview takes precedence
      if (isDraggingRef.current) {
        console.debug('[PluginWindowApp] Skipping param update during drag');
        return;
      }

      setParams(newParams);
    },
    []
  );

  // Handle connection status changes
  const handleConnectionChange = useCallback((state: PluginWindowConnectionState) => {
    setConnectionState(state);
  }, []);

  // Handle meter updates from main app (for analyzer display)
  const handleMeterUpdate = useCallback((meter: MeterData) => {
    setMeterData(meter);
  }, []);

  // Set up sync with main app (only if valid plugin)
  const { sendParamChange, sendParamBatch, sendBypassChange } = usePluginWindowSync(
    insertId,
    pluginId,
    handleStateUpdate,
    handleConnectionChange,
    handleMeterUpdate
  );

  // Handle param change from editor
  const handleParamChange = useCallback(
    (paramId: string, value: any) => {
      setParams((prev) => ({ ...prev, [paramId]: value }));
      sendParamChange(paramId, value);
    },
    [sendParamChange]
  );

  // Handle batch param changes (atomic update - prevents race conditions)
  // Note: VanEQProEditor uses array format [{paramId, value}], we convert to Record for sync
  // IMPORTANT: Use Record<string, any> to preserve booleans/enums (not just numbers)
  const handleParamBatch = useCallback(
    (changes: Record<string, any>) => {
      setParams((prev) => ({ ...prev, ...changes }));
      sendParamBatch(changes);
    },
    [sendParamBatch]
  );

  // Handler for VanEQProEditor's Record-based onChangeBatch
  // Also intercepts special markers: __bypass__, __solo__
  const handleVanEQBatch = useCallback(
    (changes: Record<string, number>) => {
      // Extract special markers
      const { __bypass__, __solo__, ...rest } = changes;

      // Handle bypass marker (used by power button)
      if (typeof __bypass__ === 'number') {
        const newBypassed = __bypass__ === 1;
        setBypassed(newBypassed);
        sendBypassChange(newBypassed);
      }

      // Handle solo marker - send as a special param
      // Solo is sent to DSP as 'soloedBand' param (-1 = none, 0-7 = band index)
      if (typeof __solo__ === 'number') {
        // Add soloedBand to the batch as a regular param
        // This will be picked up by VanEqDSP.applyParams
        rest['soloedBand'] = __solo__;
      }

      // Send remaining params if any
      if (Object.keys(rest).length > 0) {
        handleParamBatch(rest);
      }
    },
    [handleParamBatch, sendBypassChange]
  );

  // Handle param reset
  const handleParamReset = useCallback(
    (paramId: string) => {
      const allDescriptors = [
        ...VANEQ_PARAM_DESCRIPTORS,
        ...VANCOMP_PARAM_DESCRIPTORS,
        ...VANLIMIT_PARAM_DESCRIPTORS,
      ];
      const descriptor = allDescriptors.find((d) => d.id === paramId);
      if (descriptor) {
        const defaultVal = descriptor.default;
        setParams((prev) => ({ ...prev, [paramId]: defaultVal }));
        sendParamChange(paramId, defaultVal);
      }
    },
    [sendParamChange]
  );

  // Handle bypass change
  const handleBypassChange = useCallback(
    (newBypassed: boolean) => {
      setBypassed(newBypassed);
      sendBypassChange(newBypassed);
    },
    [sendBypassChange]
  );

  // Handle drag lifecycle from VanEQProEditor
  // When dragging, ignore host param echo to prevent jitter
  const handleDragStart = useCallback(() => {
    isDraggingRef.current = true;
  }, []);

  const handleDragEnd = useCallback(() => {
    isDraggingRef.current = false;
  }, []);


  // Auto-close window when project is closed (orphaned window after refresh)
  useEffect(() => {
    if (connectionState === 'project_closed') {
      const timer = setTimeout(() => {
        window.close();
      }, 2000);
      return () => clearTimeout(timer);
    }
  }, [connectionState]);

  // Determine if editor should be read-only
  const isReadOnly = connectionState !== 'connected';

  // Get status message for overlay
  const getStatusOverlay = () => {
    switch (connectionState) {
      case 'connecting':
        return (
          <div className="rf-plugin-window-connecting">
            <div className="rf-plugin-window-spinner" />
            <span>Connecting to ReelForge...</span>
          </div>
        );
      case 'disconnected':
        return (
          <div className="rf-plugin-window-disconnected">
            <span className="rf-plugin-window-status-icon">⚠️</span>
            <span>Connection lost. Reconnecting...</span>
          </div>
        );
      case 'project_closed':
        return (
          <div className="rf-plugin-window-project-closed">
            <span className="rf-plugin-window-status-icon">📁</span>
            <span>Connection Lost</span>
            <p>The main app was reloaded or the project was closed.</p>
            <p style={{ fontSize: '12px', opacity: 0.7 }}>This window will close automatically...</p>
            <button onClick={() => window.close()}>Close Now</button>
          </div>
        );
      default:
        return null;
    }
  };

  // HARD-FAIL: Unknown or invalid pluginId
  if (!isValidPlugin) {
    return (
      <div className="rf-plugin-window rf-plugin-window-error-state">
        <div className="rf-plugin-window-hard-fail">
          <span className="rf-plugin-window-error-icon">🚫</span>
          <h2>RF_ERR: Unknown Plugin</h2>
          <p>Plugin ID "{pluginId}" is not registered or does not support standalone windows.</p>
          <div className="rf-plugin-window-error-details">
            <code>insertId: {insertId}</code>
            <code>pluginId: {pluginId}</code>
          </div>
          <button onClick={() => window.close()}>Close Window</button>
        </div>
      </div>
    );
  }

  // Render the appropriate editor
  const renderEditor = () => {
    switch (pluginId) {
      case 'vaneq':
        return (
          <VanEQProEditor
            params={params}
            bypassed={bypassed}
            onChange={handleParamChange}
            onChangeBatch={handleVanEQBatch}
            spectrumData={spectrumData}
            onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
          />
        );
      case 'vancomp':
        return (
          <VanCompProEditor
            params={params}
            onChange={handleParamChange}
            onReset={handleParamReset}
            onBypassChange={handleBypassChange}
            bypassed={bypassed}
            readOnly={isReadOnly}
          />
        );
      case 'vanlimit':
        return (
          <VanLimitProEditor
            params={params}
            onChange={handleParamChange}
            onReset={handleParamReset}
            onBypassChange={handleBypassChange}
            bypassed={bypassed}
            readOnly={isReadOnly}
          />
        );
      default:
        // This shouldn't happen due to isValidPlugin check, but just in case
        return (
          <div className="rf-plugin-window-no-editor">
            <h2>Unsupported Plugin</h2>
            <p>Plugin "{pluginId}" does not have a standalone editor.</p>
          </div>
        );
    }
  };

  return (
    <div className="rf-plugin-window">
      {getStatusOverlay()}
      <div className={`rf-plugin-window-content ${connectionState}`}>
        <PluginErrorBoundary pluginId={pluginId}>
          {renderEditor()}
        </PluginErrorBoundary>
      </div>
    </div>
  );
}

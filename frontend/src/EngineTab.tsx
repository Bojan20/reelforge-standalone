import { useState, useRef, useEffect, useCallback } from 'react';
import { EngineClient, type EngineStatus, type EngineLogEntry, type EngineLogRaw } from './core/engineClient';
import type { LatencyStats, RuntimeStub } from './runtimeStub';
import type { NativeRuntimeStats } from './core/nativeRuntimeCore';
import RoutesEditor from './components/RoutesEditor';
import ProjectRoutesEditor from './components/ProjectRoutesEditor';
import BusInspector from './components/BusInspector';
import type { RoutesConfig } from './core/routesTypes';
import type { NativeRuntimeCoreWrapper } from './core/nativeRuntimeCore';

/** Type guard for GameEventFired message in log entry raw data */
function isGameEventFired(raw: EngineLogRaw | undefined): raw is { type: 'GameEventFired'; eventName: string; seq?: number; engineTimeMs?: number } {
  return !!raw && 'type' in raw && raw.type === 'GameEventFired';
}

/** Safely get seq from raw log data */
function getSeqFromRaw(raw: EngineLogRaw | undefined): number | null {
  if (raw && 'seq' in raw && typeof raw.seq === 'number') {
    return raw.seq;
  }
  return null;
}

interface StressStats {
  sentEvents: number;
  ignoredDuplicates: number;
  lastSnapshotTime: number | null;
  isRunning: boolean;
}

interface SnapshotEntry {
  timestamp: string;
  latency: {
    count: number;
    avgMs: string;
    minMs: string;
    maxMs: string;
    lastMs: string;
  } | null;
  backend: {
    activeVoices: number;
    pendingTimers: number;
  } | string;
  // M6.5: Core stats from native RuntimeCore
  coreStats?: NativeRuntimeStats | null;
}

// Duration presets in minutes
const DURATION_PRESETS = [1, 5, 15, 30, 60];

interface NativeLatencySplit {
  coreMs: number;
  execMs: number;
  totalMs: number;
  count: number;
}

interface EngineTabProps {
  engineClient: EngineClient | null;
  engineStatus: EngineStatus;
  engineLogs: EngineLogEntry[];
  engineUrl: string;
  onUrlChange: (url: string) => void;
  latencyStats?: LatencyStats | null;
  perEventStats?: Record<string, LatencyStats>;
  onClearStats?: () => void;
  runtimeStub?: RuntimeStub | null;
  // Native RuntimeCore toggle
  useNativeCore?: boolean;
  onToggleNativeCore?: (enabled: boolean) => void;
  nativeCoreAvailable?: boolean;
  nativeCoreError?: string | null;
  nativeLatencySplit?: NativeLatencySplit | null;
  onRunDeterminismCheck?: () => Promise<{ passed: boolean; details: string }>;
  // M6.5: Get core stats for snapshot export
  getCoreStats?: () => NativeRuntimeStats | null;
  // M6.7: Routes Editor
  routesPath?: string;
  assetIds?: Set<string>;
  onReloadCore?: (config: RoutesConfig) => Promise<boolean>;
  // M7.0: Use project context for routes (if true, ignores routesPath/assetIds)
  useProjectRoutes?: boolean;
  // M7.0: Native core instance for project routes editor
  nativeCore?: NativeRuntimeCoreWrapper | null;
  // M7.1: Local flood callback (uses preview executor)
  onLocalFlood?: (count: number, eventName: string) => void;
  // M7.1: Last command info for Bus Inspector debug
  lastCommand?: { type: string; bus?: string; timestamp: number } | null;
}

type EngineSubTab = 'monitor' | 'routes';

export default function EngineTab({
  engineClient,
  engineStatus,
  engineLogs,
  engineUrl,
  onUrlChange,
  latencyStats,
  perEventStats,
  onClearStats,
  runtimeStub,
  useNativeCore = false,
  onToggleNativeCore,
  nativeCoreAvailable = false,
  nativeCoreError = null,
  nativeLatencySplit = null,
  onRunDeterminismCheck,
  getCoreStats,
  routesPath,
  assetIds,
  onReloadCore,
  useProjectRoutes = false,
  nativeCore,
  onLocalFlood,
  lastCommand,
}: EngineTabProps) {
  // Sub-tab state (M6.7)
  const [activeSubTab, setActiveSubTab] = useState<EngineSubTab>('monitor');

  // M7.1: Bus Inspector state
  const [busInspectorCollapsed, setBusInspectorCollapsed] = useState(false);

  // Stress test state
  const [stressPanelOpen, setStressPanelOpen] = useState(false);
  const [floodCount, setFloodCount] = useState(500);
  const [floodRate, setFloodRate] = useState(100);
  const [stressDuration, setStressDuration] = useState(5);
  const [randomStopAll, setRandomStopAll] = useState(false);
  const [stressStats, setStressStats] = useState<StressStats>({
    sentEvents: 0,
    ignoredDuplicates: 0,
    lastSnapshotTime: null,
    isRunning: false
  });

  // Determinism check state
  const [determinismResult, setDeterminismResult] = useState<{ passed: boolean; details: string } | null>(null);
  const [determinismChecking, setDeterminismChecking] = useState(false);

  // Snapshot log storage for export
  const snapshotLogRef = useRef<SnapshotEntry[]>([]);

  // Track last received event for local injection
  const [lastEventInfo, setLastEventInfo] = useState<{ eventName: string; seq?: number } | null>(null);

  // Stress mode timers
  const stressTimersRef = useRef<{
    floodInterval: ReturnType<typeof setInterval> | null;
    snapshotInterval: ReturnType<typeof setInterval> | null;
    stopAllInterval: ReturnType<typeof setInterval> | null;
    endTimeout: ReturnType<typeof setTimeout> | null;
  }>({
    floodInterval: null,
    snapshotInterval: null,
    stopAllInterval: null,
    endTimeout: null
  });

  // Track last event from logs
  useEffect(() => {
    const lastIncoming = engineLogs
      .filter(e => e.direction === 'in' && isGameEventFired(e.raw))
      .at(-1);
    if (lastIncoming && isGameEventFired(lastIncoming.raw)) {
      setLastEventInfo({
        eventName: lastIncoming.raw.eventName,
        seq: lastIncoming.raw.seq
      });
    }
  }, [engineLogs]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      const timers = stressTimersRef.current;
      if (timers.floodInterval) clearInterval(timers.floodInterval);
      if (timers.snapshotInterval) clearInterval(timers.snapshotInterval);
      if (timers.stopAllInterval) clearInterval(timers.stopAllInterval);
      if (timers.endTimeout) clearTimeout(timers.endTimeout);
    };
  }, []);

  const handleConnectClick = () => {
    if (!engineClient) return;
    if (engineStatus === 'connected' || engineStatus === 'connecting') {
      engineClient.disconnect();
    } else {
      engineClient.connect(engineUrl);
    }
  };

  const handleTriggerTestEvent = () => {
    engineClient?.triggerEvent('onBaseGameSpin');
  };

  const getStatusIcon = () => {
    switch (engineStatus) {
      case 'connected': return '●';
      case 'connecting': return '◐';
      case 'error': return '✕';
      default: return '○';
    }
  };

  const getConnectButtonText = () => {
    if (engineStatus === 'connected') return 'Disconnect';
    if (engineStatus === 'connecting') return 'Connecting...';
    return 'Connect';
  };

  const getConnectButtonIcon = () => {
    return engineStatus === 'connected' ? '⏹' : '▶';
  };

  const isConnecting = engineStatus === 'connected' || engineStatus === 'connecting';

  const formatMs = (ms: number) => {
    if (ms < 0.01) return '<0.01';
    return ms.toFixed(2);
  };

  // === LOCAL FAULT INJECTION (no WS roundtrip) ===

  const handleLocalDuplicate = useCallback(() => {
    if (!runtimeStub || !lastEventInfo) {
      console.warn('[StressTest] No stub or last event info');
      return;
    }

    const { eventName, seq } = lastEventInfo;
    console.log(`[StressTest] Injecting duplicate seq=${seq}`);

    // First call - should succeed
    const result1 = runtimeStub.triggerEventByName(eventName, performance.now(), seq);
    // Second call with same seq - should be deduped
    const result2 = runtimeStub.triggerEventByName(eventName, performance.now(), seq);

    if (result1 !== null && result2 === null) {
      console.log(`[StressTest] ✅ Duplicate correctly ignored`);
      setStressStats(prev => ({ ...prev, ignoredDuplicates: prev.ignoredDuplicates + 1 }));
    } else {
      console.warn(`[StressTest] ⚠️ Unexpected results: result1=${result1 !== null}, result2=${result2 !== null}`);
    }
  }, [runtimeStub, lastEventInfo]);

  const handleLocalOutOfOrder = useCallback(() => {
    if (!runtimeStub || !lastEventInfo) {
      console.warn('[StressTest] No stub or last event info');
      return;
    }

    const { eventName, seq = 0 } = lastEventInfo;
    const higherSeq = seq + 100;
    const lowerSeq = seq + 99;

    console.log(`[StressTest] Injecting out-of-order: seq=${higherSeq} then seq=${lowerSeq}`);

    // Higher seq first
    runtimeStub.triggerEventByName(eventName, performance.now(), higherSeq);
    // Then lower seq (should still work, just out of order)
    runtimeStub.triggerEventByName(eventName, performance.now(), lowerSeq);

    console.log(`[StressTest] ⚠️ OUT_OF_ORDER seq - both processed (no dedupe for different seqs)`);
  }, [runtimeStub, lastEventInfo]);

  // === WS-BASED STRESS TESTS ===

  const handleWsDuplicate = () => {
    engineClient?.stressTest('duplicate', 1, 'onReelStop');
  };

  const handleWsOutOfOrder = () => {
    engineClient?.stressTest('outOfOrder', 1, 'onReelStop');
  };

  const handleFlood = useCallback(() => {
    // Use WS if connected, otherwise use local flood
    if (engineStatus === 'connected' && engineClient) {
      engineClient.stressTest('flood', floodCount, 'onReelStop');
    } else if (onLocalFlood) {
      onLocalFlood(floodCount, 'onReelStop');
    } else if (runtimeStub) {
      // Fallback: direct stub injection
      for (let i = 0; i < floodCount; i++) {
        runtimeStub.triggerEventByName('onReelStop', performance.now());
      }
    }
    setStressStats(prev => ({ ...prev, sentEvents: prev.sentEvents + floodCount }));
  }, [engineStatus, engineClient, floodCount, onLocalFlood, runtimeStub]);

  const handleWsRapidFire = () => {
    engineClient?.stressTest('rapidFire', Math.min(floodCount, 100), 'onReelStop');
    setStressStats(prev => ({ ...prev, sentEvents: prev.sentEvents + Math.min(floodCount, 100) }));
  };

  // === STRESS MODE (soak-lite) ===

  const takeSnapshot = useCallback(() => {
    const stats = runtimeStub?.getOverallStats();
    const backendStats = (runtimeStub as any)?.backend?.getStats?.();
    const coreStats = getCoreStats?.() ?? null;

    const snapshot: SnapshotEntry = {
      timestamp: new Date().toISOString(),
      latency: stats ? {
        count: stats.count,
        avgMs: stats.avgMs.toFixed(2),
        minMs: stats.minMs.toFixed(2),
        maxMs: stats.maxMs.toFixed(2),
        lastMs: stats.lastMs.toFixed(2)
      } : null,
      backend: backendStats ? {
        activeVoices: backendStats.activeVoices,
        pendingTimers: backendStats.pendingTimers
      } : 'n/a',
      coreStats: coreStats
    };

    // Store in log (ring buffer, max 1000 entries for long soak tests)
    snapshotLogRef.current = [...snapshotLogRef.current.slice(-999), snapshot];

    console.log('[StressTest] SNAPSHOT:', JSON.stringify(snapshot));
    setStressStats(prev => ({ ...prev, lastSnapshotTime: Date.now() }));
  }, [runtimeStub, getCoreStats]);

  // Export snapshot logs as JSON file
  const exportSnapshotLogs = useCallback(() => {
    const logs = snapshotLogRef.current;
    if (logs.length === 0) {
      console.warn('[StressTest] No snapshots to export');
      return;
    }

    const exportData = {
      exportedAt: new Date().toISOString(),
      snapshotCount: logs.length,
      snapshots: logs
    };

    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = `reelforge-stress-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    console.log(`[StressTest] Exported ${logs.length} snapshots`);
  }, []);

  // Clear snapshot logs
  const clearSnapshotLogs = useCallback(() => {
    snapshotLogRef.current = [];
    console.log('[StressTest] Snapshot logs cleared');
  }, []);

  const startStressMode = useCallback(() => {
    if (stressStats.isRunning) return;

    console.log(`[StressTest] Starting stress mode: duration=${stressDuration}min, rate=${floodRate}/sec, randomStopAll=${randomStopAll}`);

    setStressStats(prev => ({ ...prev, isRunning: true, sentEvents: 0, ignoredDuplicates: 0 }));

    const timers = stressTimersRef.current;

    // Flood interval
    const intervalMs = 1000 / floodRate;
    let eventsSent = 0;
    timers.floodInterval = setInterval(() => {
      engineClient?.triggerEvent('onReelStop');
      eventsSent++;
      if (eventsSent % 100 === 0) {
        setStressStats(prev => ({ ...prev, sentEvents: eventsSent }));
      }
    }, intervalMs);

    // Snapshot interval (every 3 seconds)
    timers.snapshotInterval = setInterval(() => {
      takeSnapshot();
    }, 3000);

    // Random StopAll interval (every 5-15 seconds)
    if (randomStopAll) {
      const scheduleRandomStopAll = () => {
        const delay = 5000 + Math.random() * 10000; // 5-15 seconds
        timers.stopAllInterval = setTimeout(() => {
          console.log('[StressTest] Injecting random StopAll');
          runtimeStub?.triggerEventByName('onStopAll', performance.now());
          scheduleRandomStopAll();
        }, delay) as unknown as ReturnType<typeof setInterval>;
      };
      scheduleRandomStopAll();
    }

    // End timeout
    timers.endTimeout = setTimeout(() => {
      stopStressMode();
      console.log(`[StressTest] Stress mode completed after ${stressDuration} minutes`);
    }, stressDuration * 60 * 1000);

    // Initial snapshot
    takeSnapshot();
  }, [engineClient, runtimeStub, floodRate, stressDuration, randomStopAll, stressStats.isRunning, takeSnapshot]);

  const stopStressMode = useCallback(() => {
    console.log('[StressTest] Stopping stress mode');

    const timers = stressTimersRef.current;
    if (timers.floodInterval) {
      clearInterval(timers.floodInterval);
      timers.floodInterval = null;
    }
    if (timers.snapshotInterval) {
      clearInterval(timers.snapshotInterval);
      timers.snapshotInterval = null;
    }
    if (timers.stopAllInterval) {
      clearTimeout(timers.stopAllInterval as unknown as ReturnType<typeof setTimeout>);
      timers.stopAllInterval = null;
    }
    if (timers.endTimeout) {
      clearTimeout(timers.endTimeout);
      timers.endTimeout = null;
    }

    setStressStats(prev => ({ ...prev, isRunning: false }));

    // Final snapshot
    takeSnapshot();
  }, [takeSnapshot]);

  // Run determinism check
  const handleDeterminismCheck = useCallback(async () => {
    if (!onRunDeterminismCheck || determinismChecking) return;

    setDeterminismChecking(true);
    setDeterminismResult(null);

    try {
      const result = await onRunDeterminismCheck();
      setDeterminismResult(result);
      console.log(`[DeterminismCheck] ${result.passed ? 'PASS' : 'FAIL'}: ${result.details}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setDeterminismResult({ passed: false, details: `Error: ${msg}` });
    } finally {
      setDeterminismChecking(false);
    }
  }, [onRunDeterminismCheck, determinismChecking]);

  return (
    <div className="rf-engine-tab">
      {/* Sub-tab Navigation (M6.7) */}
      <div className="rf-engine-subtabs">
        <button
          className={`rf-engine-subtab ${activeSubTab === 'monitor' ? 'active' : ''}`}
          onClick={() => setActiveSubTab('monitor')}
        >
          Monitor
        </button>
        {(routesPath || useProjectRoutes) && (
          <button
            className={`rf-engine-subtab ${activeSubTab === 'routes' ? 'active' : ''}`}
            onClick={() => setActiveSubTab('routes')}
          >
            Routes
          </button>
        )}
      </div>

      {/* Routes Editor (M6.7 / M7.0) */}
      {activeSubTab === 'routes' && (useProjectRoutes || routesPath) && (
        <div className="rf-engine-routes-container">
          {useProjectRoutes ? (
            <ProjectRoutesEditor
              nativeCore={nativeCore}
              showSimulation={false}
            />
          ) : routesPath ? (
            <RoutesEditor
              routesPath={routesPath}
              assetIds={assetIds}
              onReloadCore={onReloadCore}
            />
          ) : null}
        </div>
      )}

      {/* Monitor Tab Content */}
      {activeSubTab === 'monitor' && (
        <>
      <div className="rf-engine-header">
        <div className="rf-engine-connection-group">
          <div className="rf-engine-url-wrapper">
            <label className="rf-engine-label">ENGINE URL</label>
            <div className="rf-engine-input-group">
              <span className="rf-engine-input-icon">🔌</span>
              <input
                type="text"
                value={engineUrl}
                onChange={(e) => onUrlChange(e.target.value)}
                className="rf-engine-url-input"
                placeholder="ws://localhost:7777"
                disabled={isConnecting}
              />
            </div>
          </div>

          <div className="rf-engine-controls">
            <button
              className={`rf-engine-btn rf-engine-btn-${engineStatus === 'connected' ? 'disconnect' : 'connect'}`}
              onClick={handleConnectClick}
              disabled={engineStatus === 'connecting'}
            >
              <span className="rf-engine-btn-icon">{getConnectButtonIcon()}</span>
              <span className="rf-engine-btn-text">{getConnectButtonText()}</span>
            </button>

            <button
              className="rf-engine-action-btn"
              onClick={handleTriggerTestEvent}
              disabled={engineStatus !== 'connected'}
            >
              <span className="rf-engine-action-icon">⚡</span>
              <span>Test Event</span>
            </button>
          </div>
        </div>

        <div className={`rf-engine-status rf-engine-status-${engineStatus}`}>
          <span className="rf-engine-status-icon">{getStatusIcon()}</span>
          <span className="rf-engine-status-text">{engineStatus.toUpperCase()}</span>
        </div>
      </div>

      {/* Latency Stats Panel */}
      {latencyStats && latencyStats.count > 0 && (
        <div className="rf-engine-latency">
          <div className="rf-engine-latency-header">
            <span className="rf-engine-latency-title">Latency Stats</span>
            <button
              className="rf-engine-latency-clear"
              onClick={onClearStats}
              title="Clear stats"
            >
              Clear
            </button>
          </div>

          {/* Overall Stats */}
          <div className="rf-engine-latency-overall">
            <div className="rf-engine-latency-row">
              <span className="rf-engine-latency-label">Overall</span>
              <span className="rf-engine-latency-value rf-engine-latency-count">
                n={latencyStats.count}
              </span>
            </div>
            <div className="rf-engine-latency-metrics">
              <div className="rf-engine-latency-metric">
                <span className="rf-engine-latency-metric-label">Last</span>
                <span className="rf-engine-latency-metric-value">{formatMs(latencyStats.lastMs)}ms</span>
              </div>
              <div className="rf-engine-latency-metric">
                <span className="rf-engine-latency-metric-label">Min</span>
                <span className="rf-engine-latency-metric-value">{formatMs(latencyStats.minMs)}ms</span>
              </div>
              <div className="rf-engine-latency-metric">
                <span className="rf-engine-latency-metric-label">Max</span>
                <span className="rf-engine-latency-metric-value">{formatMs(latencyStats.maxMs)}ms</span>
              </div>
              <div className="rf-engine-latency-metric">
                <span className="rf-engine-latency-metric-label">Avg</span>
                <span className="rf-engine-latency-metric-value">{formatMs(latencyStats.avgMs)}ms</span>
              </div>
            </div>
          </div>

          {/* Per-Event Stats */}
          {perEventStats && Object.keys(perEventStats).length > 0 && (
            <div className="rf-engine-latency-events">
              <div className="rf-engine-latency-events-header">Per Event</div>
              {Object.entries(perEventStats).map(([eventName, stats]) => (
                <div key={eventName} className="rf-engine-latency-event">
                  <div className="rf-engine-latency-row">
                    <span className="rf-engine-latency-event-name">{eventName}</span>
                    <span className="rf-engine-latency-value rf-engine-latency-count">
                      n={stats.count}
                    </span>
                  </div>
                  <div className="rf-engine-latency-metrics rf-engine-latency-metrics-small">
                    <span className="rf-engine-latency-metric-inline">
                      {formatMs(stats.lastMs)} / {formatMs(stats.minMs)} / {formatMs(stats.maxMs)} / {formatMs(stats.avgMs)}ms
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* M7.1: Bus Inspector Panel */}
      <div className="rf-engine-bus-inspector">
        <BusInspector
          collapsed={busInspectorCollapsed}
          onToggleCollapsed={() => setBusInspectorCollapsed(!busInspectorCollapsed)}
          lastCommand={lastCommand}
        />
      </div>

      {/* Stress Test Panel (dev-only) */}
      <div className="rf-engine-stress">
        <div
          className="rf-engine-stress-header"
          onClick={() => setStressPanelOpen(!stressPanelOpen)}
        >
          <span className="rf-engine-stress-toggle">{stressPanelOpen ? '▼' : '▶'}</span>
          <span className="rf-engine-stress-title">Stress / Fault Injection</span>
          {stressStats.isRunning && (
            <span className="rf-engine-stress-running">● RUNNING</span>
          )}
        </div>

        {stressPanelOpen && (
          <div className="rf-engine-stress-content">
            {/* Native RuntimeCore Toggle */}
            <div className="rf-engine-stress-section">
              <div className="rf-engine-stress-section-title">RuntimeCore Mode</div>
              <div className="rf-engine-stress-controls">
                <label className="rf-engine-stress-checkbox">
                  <input
                    type="checkbox"
                    checked={useNativeCore}
                    onChange={(e) => onToggleNativeCore?.(e.target.checked)}
                    disabled={!nativeCoreAvailable}
                  />
                  <span>Use Native RuntimeCore (C++)</span>
                </label>
              </div>
              {nativeCoreAvailable ? (
                <div className="rf-engine-stress-info" style={{ color: useNativeCore ? '#22c55e' : '#888' }}>
                  {useNativeCore ? '● Native core active' : '○ Using JS RuntimeStub'}
                </div>
              ) : (
                <div className="rf-engine-stress-info" style={{ color: '#ef4444' }}>
                  ✕ Native addon not available{nativeCoreError ? `: ${nativeCoreError}` : ''}
                </div>
              )}

              {/* Split Latency Metrics (native mode only) */}
              {useNativeCore && nativeLatencySplit && (
                <div className="rf-engine-stress-stats" style={{ marginTop: '8px' }}>
                  <div className="rf-engine-stress-stat">
                    <span>recv→core:</span>
                    <span>{nativeLatencySplit.coreMs.toFixed(2)}ms</span>
                  </div>
                  <div className="rf-engine-stress-stat">
                    <span>core→exec:</span>
                    <span>{nativeLatencySplit.execMs.toFixed(2)}ms</span>
                  </div>
                  <div className="rf-engine-stress-stat">
                    <span>recv→exec:</span>
                    <span>{nativeLatencySplit.totalMs.toFixed(2)}ms</span>
                  </div>
                  <div className="rf-engine-stress-stat">
                    <span>n=</span>
                    <span>{nativeLatencySplit.count}</span>
                  </div>
                </div>
              )}

              {/* Determinism Check Button */}
              {nativeCoreAvailable && (
                <div className="rf-engine-stress-buttons" style={{ marginTop: '8px' }}>
                  <button
                    className="rf-engine-stress-btn"
                    onClick={handleDeterminismCheck}
                    disabled={determinismChecking}
                    title="Run 50 events twice and compare command arrays"
                  >
                    {determinismChecking ? '⏳ Checking...' : '🔬 Run Determinism Check'}
                  </button>
                </div>
              )}
              {determinismResult && (
                <div
                  className="rf-engine-stress-info"
                  style={{ color: determinismResult.passed ? '#22c55e' : '#ef4444', marginTop: '4px' }}
                >
                  {determinismResult.passed ? '✓ PASS' : '✕ FAIL'}: {determinismResult.details}
                </div>
              )}
            </div>

            {/* Local Fault Injection */}
            <div className="rf-engine-stress-section">
              <div className="rf-engine-stress-section-title">Local Injection (no WS)</div>
              <div className="rf-engine-stress-buttons">
                <button
                  className="rf-engine-stress-btn rf-engine-stress-btn-warn"
                  onClick={handleLocalDuplicate}
                  disabled={!runtimeStub || !lastEventInfo}
                  title="Inject duplicate seq locally"
                >
                  Duplicate Seq
                </button>
                <button
                  className="rf-engine-stress-btn rf-engine-stress-btn-warn"
                  onClick={handleLocalOutOfOrder}
                  disabled={!runtimeStub || !lastEventInfo}
                  title="Inject out-of-order seq locally"
                >
                  Out-of-Order
                </button>
              </div>
              {lastEventInfo && (
                <div className="rf-engine-stress-info">
                  Last: {lastEventInfo.eventName} (seq={lastEventInfo.seq})
                </div>
              )}
            </div>

            {/* WS Fault Injection */}
            <div className="rf-engine-stress-section">
              <div className="rf-engine-stress-section-title">WS Injection</div>
              <div className="rf-engine-stress-buttons">
                <button
                  className="rf-engine-stress-btn"
                  onClick={handleWsDuplicate}
                  disabled={engineStatus !== 'connected'}
                >
                  WS Duplicate
                </button>
                <button
                  className="rf-engine-stress-btn"
                  onClick={handleWsOutOfOrder}
                  disabled={engineStatus !== 'connected'}
                >
                  WS Out-of-Order
                </button>
                <button
                  className="rf-engine-stress-btn rf-engine-stress-btn-danger"
                  onClick={handleFlood}
                  disabled={!onLocalFlood && !runtimeStub && engineStatus !== 'connected'}
                  title={engineStatus === 'connected' ? 'WS Flood' : 'Local Flood'}
                >
                  Flood ({floodCount})
                  {engineStatus !== 'connected' && (onLocalFlood || runtimeStub) && (
                    <span style={{ marginLeft: 4, fontSize: 9, opacity: 0.7 }}>LOCAL</span>
                  )}
                </button>
                <button
                  className="rf-engine-stress-btn rf-engine-stress-btn-danger"
                  onClick={handleWsRapidFire}
                  disabled={engineStatus !== 'connected'}
                >
                  Rapid Fire
                </button>
              </div>
            </div>

            {/* Stress Mode Controls */}
            <div className="rf-engine-stress-section">
              <div className="rf-engine-stress-section-title">Stress Mode (Soak)</div>
              <div className="rf-engine-stress-controls">
                <label className="rf-engine-stress-control">
                  <span>Flood count:</span>
                  <input
                    type="number"
                    value={floodCount}
                    onChange={(e) => setFloodCount(parseInt(e.target.value) || 100)}
                    min={10}
                    max={10000}
                  />
                </label>
                <label className="rf-engine-stress-control">
                  <span>Rate (ev/sec):</span>
                  <input
                    type="number"
                    value={floodRate}
                    onChange={(e) => setFloodRate(parseInt(e.target.value) || 10)}
                    min={1}
                    max={1000}
                  />
                </label>
                <div className="rf-engine-stress-control rf-engine-stress-duration">
                  <span>Duration:</span>
                  <div className="rf-engine-stress-presets">
                    {DURATION_PRESETS.map(mins => (
                      <button
                        key={mins}
                        className={`rf-engine-stress-preset ${stressDuration === mins ? 'active' : ''}`}
                        onClick={() => setStressDuration(mins)}
                        disabled={stressStats.isRunning}
                      >
                        {mins}m
                      </button>
                    ))}
                  </div>
                </div>
                <label className="rf-engine-stress-checkbox">
                  <input
                    type="checkbox"
                    checked={randomStopAll}
                    onChange={(e) => setRandomStopAll(e.target.checked)}
                  />
                  <span>Random StopAll</span>
                </label>
              </div>
              <div className="rf-engine-stress-buttons">
                {!stressStats.isRunning ? (
                  <button
                    className="rf-engine-stress-btn rf-engine-stress-btn-start"
                    onClick={startStressMode}
                    disabled={engineStatus !== 'connected'}
                  >
                    ▶ Start Stress
                  </button>
                ) : (
                  <button
                    className="rf-engine-stress-btn rf-engine-stress-btn-stop"
                    onClick={stopStressMode}
                  >
                    ⏹ Stop Stress
                  </button>
                )}
                <button
                  className="rf-engine-stress-btn"
                  onClick={takeSnapshot}
                  disabled={!runtimeStub}
                >
                  📸 Snapshot
                </button>
              </div>
            </div>

            {/* Stats Display */}
            <div className="rf-engine-stress-stats">
              <div className="rf-engine-stress-stat">
                <span>Sent:</span>
                <span>{stressStats.sentEvents}</span>
              </div>
              <div className="rf-engine-stress-stat">
                <span>Ignored:</span>
                <span>{stressStats.ignoredDuplicates}</span>
              </div>
              <div className="rf-engine-stress-stat">
                <span>Snapshots:</span>
                <span>{snapshotLogRef.current.length}</span>
              </div>
              <div className="rf-engine-stress-stat">
                <span>Last:</span>
                <span>
                  {stressStats.lastSnapshotTime
                    ? new Date(stressStats.lastSnapshotTime).toLocaleTimeString()
                    : 'n/a'}
                </span>
              </div>
            </div>

            {/* Export Controls */}
            <div className="rf-engine-stress-export">
              <button
                className="rf-engine-stress-btn rf-engine-stress-btn-export"
                onClick={exportSnapshotLogs}
                disabled={snapshotLogRef.current.length === 0}
                title="Download snapshot logs as JSON"
              >
                ⬇ Export Logs
              </button>
              <button
                className="rf-engine-stress-btn rf-engine-stress-btn-clear"
                onClick={clearSnapshotLogs}
                disabled={snapshotLogRef.current.length === 0}
                title="Clear snapshot logs"
              >
                🗑 Clear
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="rf-engine-log">
        {engineLogs.length === 0 ? (
          <div className="rf-engine-log-empty">
            <div className="rf-engine-log-empty-icon">📡</div>
            <div className="rf-engine-log-empty-text">No messages yet</div>
            <div className="rf-engine-log-empty-hint">Connect to the engine to start monitoring</div>
          </div>
        ) : (
          engineLogs
            .slice()
            .reverse()
            .map((entry) => (
              <div
                key={entry.id}
                className={`rf-engine-log-row rf-engine-log-${entry.direction}`}
              >
                <span className="rf-engine-log-time">
                  {new Date(entry.timestamp).toLocaleTimeString()}
                </span>
                <span className="rf-engine-log-dir">
                  {entry.direction === 'in' ? '←' : entry.direction === 'out' ? '→' : '●'}
                </span>
                <span className="rf-engine-log-msg">{entry.message}</span>
                {getSeqFromRaw(entry.raw) !== null && (
                  <span className="rf-engine-log-seq">#{getSeqFromRaw(entry.raw)}</span>
                )}
              </div>
            ))
        )}
      </div>
        </>
      )}
    </div>
  );
}

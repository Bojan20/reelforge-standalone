/**
 * Sidechain Router Panel
 *
 * Visual UI for sidechain routing configuration:
 * - Route creation and management
 * - Source/target selection
 * - Envelope settings (attack/release/hold)
 * - Ducking curve visualization
 * - Real-time GR metering
 */

import React, { useState, memo, useCallback, useEffect, useRef } from 'react';
import type { BusId } from '../core/types';
import {
  SidechainRouter,
  type SidechainRoute,
  type SidechainMeter,
  type DuckingCurve,
  type SidechainMode,
  type FilterType,
  SLOT_SIDECHAIN_PRESETS,
} from '../core/sidechainRouter';
import './SidechainRouterPanel.css';

// ============ TYPES ============

interface SidechainRouterPanelProps {
  buses: Array<{ id: BusId; name: string }>;
  onRouteChange?: (routeId: string, route: SidechainRoute) => void;
}

// ============ CONSTANTS ============

const DUCKING_CURVES: { value: DuckingCurve; label: string }[] = [
  { value: 'linear', label: 'Linear' },
  { value: 'exponential', label: 'Exponential' },
  { value: 'logarithmic', label: 'Logarithmic' },
  { value: 'scurve', label: 'S-Curve' },
];

const DETECTION_MODES: { value: SidechainMode; label: string }[] = [
  { value: 'peak', label: 'Peak' },
  { value: 'rms', label: 'RMS' },
  { value: 'envelope', label: 'Envelope' },
];

const FILTER_TYPES: { value: FilterType; label: string }[] = [
  { value: 'none', label: 'Off' },
  { value: 'lowpass', label: 'Low Pass' },
  { value: 'highpass', label: 'High Pass' },
  { value: 'bandpass', label: 'Band Pass' },
];

// ============ MAIN COMPONENT ============

const SidechainRouterPanel: React.FC<SidechainRouterPanelProps> = memo(({
  buses,
  onRouteChange,
}) => {
  const [router] = useState(() => new SidechainRouter());
  const [routes, setRoutes] = useState<SidechainRoute[]>([]);
  const [meters, setMeters] = useState<Map<string, SidechainMeter>>(new Map());
  const [selectedRouteId, setSelectedRouteId] = useState<string | null>(null);
  const [showNewRouteModal, setShowNewRouteModal] = useState(false);

  // Subscribe to meter updates
  useEffect(() => {
    const unsubscribe = router.onMeterUpdate((newMeters) => {
      const meterMap = new Map(newMeters.map(m => [m.routeId, m]));
      setMeters(meterMap);
    });

    return () => {
      unsubscribe();
      router.dispose();
    };
  }, [router]);

  // Refresh routes
  const refreshRoutes = useCallback(() => {
    setRoutes(router.getAllRoutes());
  }, [router]);

  // Create route from preset
  const createFromPreset = useCallback((
    presetName: keyof typeof SLOT_SIDECHAIN_PRESETS,
    sourceId: string,
    sourceName: string,
    targetId: string,
    targetName: string
  ) => {
    const preset = SLOT_SIDECHAIN_PRESETS[presetName];
    const filterConfig = preset.filter as { type: FilterType; frequency?: number; q?: number; enabled: boolean };
    router.createRoute(targetId, targetName, [{ id: sourceId, name: sourceName }], {
      name: preset.name,
      envelope: preset.envelope,
      ducking: preset.ducking,
      filter: {
        type: filterConfig.type,
        frequency: filterConfig.frequency ?? 1000,
        q: filterConfig.q ?? 0.707,
        enabled: filterConfig.enabled,
      },
    });
    refreshRoutes();
    setShowNewRouteModal(false);
  }, [router, refreshRoutes]);

  // Delete route
  const deleteRoute = useCallback((id: string) => {
    router.deleteRoute(id);
    refreshRoutes();
    if (selectedRouteId === id) {
      setSelectedRouteId(null);
    }
  }, [router, refreshRoutes, selectedRouteId]);

  // Toggle route
  const toggleRoute = useCallback((id: string) => {
    const route = router.getRoute(id);
    if (route) {
      router.setRouteEnabled(id, !route.enabled);
      refreshRoutes();
    }
  }, [router, refreshRoutes]);

  // Update route settings
  const updateEnvelope = useCallback((id: string, key: string, value: number) => {
    router.setEnvelope(id, { [key]: value });
    refreshRoutes();
    const route = router.getRoute(id);
    if (route) onRouteChange?.(id, route);
  }, [router, refreshRoutes, onRouteChange]);

  const updateDucking = useCallback((id: string, key: string, value: number | string) => {
    router.setDucking(id, { [key]: value });
    refreshRoutes();
    const route = router.getRoute(id);
    if (route) onRouteChange?.(id, route);
  }, [router, refreshRoutes, onRouteChange]);

  const updateFilter = useCallback((id: string, key: string, value: string | number | boolean) => {
    router.setFilter(id, { [key]: value });
    refreshRoutes();
  }, [router, refreshRoutes]);

  const selectedRoute = selectedRouteId ? router.getRoute(selectedRouteId) : null;

  return (
    <div className="sidechain-router-panel">
      {/* Header */}
      <div className="sidechain-header">
        <div className="sidechain-title">
          <span className="sidechain-icon">⛓️</span>
          <h3>Sidechain Router</h3>
          <span className="route-count">{routes.length} routes</span>
        </div>
        <button
          className="add-route-btn"
          onClick={() => setShowNewRouteModal(true)}
        >
          + New Route
        </button>
      </div>

      {/* Routes List */}
      <div className="routes-list">
        {routes.length === 0 ? (
          <div className="empty-state">
            <span className="empty-icon">🔗</span>
            <p>No sidechain routes configured</p>
            <button onClick={() => setShowNewRouteModal(true)}>
              Create First Route
            </button>
          </div>
        ) : (
          routes.map(route => (
            <RouteCard
              key={route.id}
              route={route}
              meter={meters.get(route.id)}
              isSelected={selectedRouteId === route.id}
              onSelect={() => setSelectedRouteId(route.id)}
              onToggle={() => toggleRoute(route.id)}
              onDelete={() => deleteRoute(route.id)}
            />
          ))
        )}
      </div>

      {/* Route Details */}
      {selectedRoute && (
        <RouteDetails
          route={selectedRoute}
          meter={meters.get(selectedRoute.id)}
          onEnvelopeChange={(key, value) => updateEnvelope(selectedRoute.id, key, value)}
          onDuckingChange={(key, value) => updateDucking(selectedRoute.id, key, value)}
          onFilterChange={(key, value) => updateFilter(selectedRoute.id, key, value)}
          onMixChange={(mix) => {
            router.setMix(selectedRoute.id, mix);
            refreshRoutes();
          }}
        />
      )}

      {/* New Route Modal */}
      {showNewRouteModal && (
        <NewRouteModal
          buses={buses}
          presets={Object.keys(SLOT_SIDECHAIN_PRESETS) as (keyof typeof SLOT_SIDECHAIN_PRESETS)[]}
          onClose={() => setShowNewRouteModal(false)}
          onCreate={createFromPreset}
        />
      )}
    </div>
  );
});

SidechainRouterPanel.displayName = 'SidechainRouterPanel';
export default SidechainRouterPanel;

// ============ ROUTE CARD ============

interface RouteCardProps {
  route: SidechainRoute;
  meter?: SidechainMeter;
  isSelected: boolean;
  onSelect: () => void;
  onToggle: () => void;
  onDelete: () => void;
}

const RouteCard = memo<RouteCardProps>(({
  route,
  meter,
  isSelected,
  onSelect,
  onToggle,
  onDelete,
}) => {
  const grDb = meter?.gainReduction ?? 0;
  const grPercent = Math.min(100, Math.abs(grDb) / 24 * 100);

  return (
    <div
      className={`route-card ${isSelected ? 'selected' : ''} ${route.enabled ? '' : 'disabled'}`}
      onClick={onSelect}
    >
      <div className="route-main">
        <button
          className="route-toggle"
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          style={{ borderColor: route.enabled ? '#22c55e' : '#666' }}
        >
          {route.enabled ? '✓' : ''}
        </button>

        <div className="route-flow">
          <span className="route-source">{route.sources[0]?.sourceName || 'Source'}</span>
          <span className="route-arrow">→</span>
          <span className="route-target">{route.targetBusName}</span>
        </div>

        <div className="route-name">{route.name}</div>

        {/* GR Meter */}
        <div className="route-gr-meter">
          <div className="gr-bar" style={{ width: `${grPercent}%` }} />
          <span className="gr-value">{grDb.toFixed(1)} dB</span>
        </div>

        <button
          className="route-delete"
          onClick={(e) => { e.stopPropagation(); onDelete(); }}
        >
          ×
        </button>
      </div>

      {/* Quick params */}
      <div className="route-params">
        <span>Attack: {route.envelope.attackMs}ms</span>
        <span>Release: {route.envelope.releaseMs}ms</span>
        <span>Range: {route.ducking.range}dB</span>
        <span>Curve: {route.ducking.curve}</span>
      </div>
    </div>
  );
});

RouteCard.displayName = 'RouteCard';

// ============ ROUTE DETAILS ============

interface RouteDetailsProps {
  route: SidechainRoute;
  meter?: SidechainMeter;
  onEnvelopeChange: (key: string, value: number) => void;
  onDuckingChange: (key: string, value: number | string) => void;
  onFilterChange: (key: string, value: string | number | boolean) => void;
  onMixChange: (mix: number) => void;
}

const RouteDetails = memo<RouteDetailsProps>(({
  route,
  meter,
  onEnvelopeChange,
  onDuckingChange,
  onFilterChange,
  onMixChange,
}) => {
  return (
    <div className="route-details">
      <h4>Route Settings: {route.name}</h4>

      {/* Envelope Section */}
      <div className="detail-section">
        <div className="section-header">
          <span className="section-icon">📈</span>
          <span>Envelope Follower</span>
        </div>

        <div className="param-row">
          <label>Mode</label>
          <select
            value={route.envelope.mode}
            onChange={(e) => onEnvelopeChange('mode', e.target.value as unknown as number)}
          >
            {DETECTION_MODES.map(m => (
              <option key={m.value} value={m.value}>{m.label}</option>
            ))}
          </select>
        </div>

        <div className="param-row">
          <label>Attack</label>
          <input
            type="range"
            min="0.1"
            max="100"
            step="0.1"
            value={route.envelope.attackMs}
            onChange={(e) => onEnvelopeChange('attackMs', parseFloat(e.target.value))}
          />
          <span className="param-value">{route.envelope.attackMs.toFixed(1)} ms</span>
        </div>

        <div className="param-row">
          <label>Release</label>
          <input
            type="range"
            min="10"
            max="1000"
            step="1"
            value={route.envelope.releaseMs}
            onChange={(e) => onEnvelopeChange('releaseMs', parseFloat(e.target.value))}
          />
          <span className="param-value">{route.envelope.releaseMs} ms</span>
        </div>

        <div className="param-row">
          <label>Hold</label>
          <input
            type="range"
            min="0"
            max="500"
            step="1"
            value={route.envelope.holdMs}
            onChange={(e) => onEnvelopeChange('holdMs', parseFloat(e.target.value))}
          />
          <span className="param-value">{route.envelope.holdMs} ms</span>
        </div>
      </div>

      {/* Ducking Section */}
      <div className="detail-section">
        <div className="section-header">
          <span className="section-icon">📉</span>
          <span>Ducking</span>
        </div>

        <DuckingCurveVisualizer
          threshold={route.ducking.threshold}
          range={route.ducking.range}
          curve={route.ducking.curve}
          ratio={route.ducking.ratio}
          currentGR={meter?.gainReduction ?? 0}
        />

        <div className="param-row">
          <label>Threshold</label>
          <input
            type="range"
            min="-60"
            max="0"
            step="0.5"
            value={route.ducking.threshold}
            onChange={(e) => onDuckingChange('threshold', parseFloat(e.target.value))}
          />
          <span className="param-value">{route.ducking.threshold} dB</span>
        </div>

        <div className="param-row">
          <label>Range</label>
          <input
            type="range"
            min="-48"
            max="0"
            step="0.5"
            value={route.ducking.range}
            onChange={(e) => onDuckingChange('range', parseFloat(e.target.value))}
          />
          <span className="param-value">{route.ducking.range} dB</span>
        </div>

        <div className="param-row">
          <label>Curve</label>
          <select
            value={route.ducking.curve}
            onChange={(e) => onDuckingChange('curve', e.target.value)}
          >
            {DUCKING_CURVES.map(c => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
        </div>

        <div className="param-row">
          <label>Depth</label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={route.ducking.depth}
            onChange={(e) => onDuckingChange('depth', parseFloat(e.target.value))}
          />
          <span className="param-value">{(route.ducking.depth * 100).toFixed(0)}%</span>
        </div>
      </div>

      {/* Key Filter Section */}
      <div className="detail-section">
        <div className="section-header">
          <span className="section-icon">🎚️</span>
          <span>Key Filter</span>
          <label className="toggle-label">
            <input
              type="checkbox"
              checked={route.filter.enabled}
              onChange={(e) => onFilterChange('enabled', e.target.checked)}
            />
            Enable
          </label>
        </div>

        {route.filter.enabled && (
          <>
            <div className="param-row">
              <label>Type</label>
              <select
                value={route.filter.type}
                onChange={(e) => onFilterChange('type', e.target.value)}
              >
                {FILTER_TYPES.map(f => (
                  <option key={f.value} value={f.value}>{f.label}</option>
                ))}
              </select>
            </div>

            <div className="param-row">
              <label>Frequency</label>
              <input
                type="range"
                min="20"
                max="20000"
                step="1"
                value={route.filter.frequency}
                onChange={(e) => onFilterChange('frequency', parseFloat(e.target.value))}
              />
              <span className="param-value">{route.filter.frequency} Hz</span>
            </div>

            <div className="param-row">
              <label>Q</label>
              <input
                type="range"
                min="0.1"
                max="10"
                step="0.1"
                value={route.filter.q}
                onChange={(e) => onFilterChange('q', parseFloat(e.target.value))}
              />
              <span className="param-value">{route.filter.q.toFixed(1)}</span>
            </div>
          </>
        )}
      </div>

      {/* Mix */}
      <div className="detail-section">
        <div className="section-header">
          <span className="section-icon">🎛️</span>
          <span>Mix</span>
        </div>

        <div className="param-row">
          <label>Dry/Wet</label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={route.mix}
            onChange={(e) => onMixChange(parseFloat(e.target.value))}
          />
          <span className="param-value">{(route.mix * 100).toFixed(0)}%</span>
        </div>
      </div>
    </div>
  );
});

RouteDetails.displayName = 'RouteDetails';

// ============ DUCKING CURVE VISUALIZER ============

interface DuckingCurveVisualizerProps {
  threshold: number;
  range: number;
  curve: DuckingCurve;
  ratio: number;
  currentGR: number;
}

const DuckingCurveVisualizer = memo<DuckingCurveVisualizerProps>(({
  threshold,
  range,
  curve,
  currentGR,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.width;
    const height = canvas.height;

    // Clear
    ctx.fillStyle = '#151515';
    ctx.fillRect(0, 0, width, height);

    // Grid
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const x = (i / 4) * width;
      const y = (i / 4) * height;
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }

    // Draw curve
    ctx.strokeStyle = '#6366f1';
    ctx.lineWidth = 2;
    ctx.beginPath();

    const thresholdNorm = (threshold + 60) / 60; // -60 to 0 -> 0 to 1
    const maxReduction = Math.abs(range);

    for (let i = 0; i <= width; i++) {
      const inputDb = (i / width) * 60 - 60; // -60 to 0
      let outputDb = inputDb;

      if (inputDb > threshold) {
        const overThreshold = inputDb - threshold;
        let reduction = 0;

        switch (curve) {
          case 'linear':
            reduction = Math.min(overThreshold * 0.5, maxReduction);
            break;
          case 'exponential':
            reduction = maxReduction * (1 - Math.exp(-overThreshold / 10));
            break;
          case 'logarithmic':
            reduction = maxReduction * Math.log10(1 + overThreshold) / Math.log10(11);
            break;
          case 'scurve':
            reduction = maxReduction * Math.tanh(overThreshold / 10);
            break;
        }

        outputDb = inputDb - reduction;
      }

      const x = i;
      const y = height - ((outputDb + 60) / 60) * height;

      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    // Threshold line
    ctx.strokeStyle = '#ef4444';
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    const threshX = thresholdNorm * width;
    ctx.moveTo(threshX, 0);
    ctx.lineTo(threshX, height);
    ctx.stroke();
    ctx.setLineDash([]);

    // Current GR indicator
    if (currentGR < 0) {
      const grY = height - ((currentGR + 60) / 60) * height;
      ctx.fillStyle = '#22c55e';
      ctx.beginPath();
      ctx.arc(width - 10, grY, 4, 0, Math.PI * 2);
      ctx.fill();
    }

  }, [threshold, range, curve, currentGR]);

  return (
    <div className="ducking-visualizer">
      <canvas ref={canvasRef} width={200} height={100} />
      <div className="visualizer-labels">
        <span>-60dB</span>
        <span>Input Level</span>
        <span>0dB</span>
      </div>
    </div>
  );
});

DuckingCurveVisualizer.displayName = 'DuckingCurveVisualizer';

// ============ NEW ROUTE MODAL ============

interface NewRouteModalProps {
  buses: Array<{ id: BusId; name: string }>;
  presets: (keyof typeof SLOT_SIDECHAIN_PRESETS)[];
  onClose: () => void;
  onCreate: (
    preset: keyof typeof SLOT_SIDECHAIN_PRESETS,
    sourceId: string,
    sourceName: string,
    targetId: string,
    targetName: string
  ) => void;
}

const NewRouteModal = memo<NewRouteModalProps>(({
  buses,
  presets,
  onClose,
  onCreate,
}) => {
  const [selectedPreset, setSelectedPreset] = useState<keyof typeof SLOT_SIDECHAIN_PRESETS>(presets[0]);
  const [sourceId, setSourceId] = useState<string>(buses[0]?.id || '');
  const [targetId, setTargetId] = useState<string>(buses[1]?.id || buses[0]?.id || '');

  const handleCreate = () => {
    const sourceBus = buses.find(b => b.id === sourceId);
    const targetBus = buses.find(b => b.id === targetId);
    if (sourceBus && targetBus) {
      onCreate(selectedPreset, sourceId, sourceBus.name, targetId, targetBus.name);
    }
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={e => e.stopPropagation()}>
        <h3>New Sidechain Route</h3>

        <div className="modal-field">
          <label>Preset</label>
          <select
            value={selectedPreset}
            onChange={(e) => setSelectedPreset(e.target.value as keyof typeof SLOT_SIDECHAIN_PRESETS)}
          >
            {presets.map(p => (
              <option key={p} value={p}>
                {SLOT_SIDECHAIN_PRESETS[p].name}
              </option>
            ))}
          </select>
        </div>

        <div className="modal-field">
          <label>Source (Trigger)</label>
          <select value={sourceId} onChange={(e) => setSourceId(e.target.value)}>
            {buses.map(b => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
        </div>

        <div className="modal-field">
          <label>Target (Duck)</label>
          <select value={targetId} onChange={(e) => setTargetId(e.target.value)}>
            {buses.map(b => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
        </div>

        <div className="modal-preview">
          <span className="preview-source">{buses.find(b => b.id === sourceId)?.name}</span>
          <span className="preview-arrow">→ ducks →</span>
          <span className="preview-target">{buses.find(b => b.id === targetId)?.name}</span>
        </div>

        <div className="modal-actions">
          <button className="btn-cancel" onClick={onClose}>Cancel</button>
          <button className="btn-create" onClick={handleCreate}>Create Route</button>
        </div>
      </div>
    </div>
  );
});

NewRouteModal.displayName = 'NewRouteModal';

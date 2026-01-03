/**
 * ReelForge M7.1 Bus Inspector
 *
 * Real-time visualization of preview mix state.
 * Shows per-bus gain, active voices, master gain, and ducking state.
 * Uses real WebAudio duck gains from busInsertDSP.
 */

import { useEffect, useState, useRef } from 'react';
import { usePreviewMixSnapshot } from '../core/PreviewMixContext';
import type { BusId } from '../core/types';
import type { InsertableBusId } from '../project/projectTypes';
import { busInsertDSP, DUCKING_CONFIG } from '../core/busInsertDSP';
import BusInsertPanel from './BusInsertPanel';
import './BusInspector.css';

/** Throttle interval for UI updates (15Hz as per spec) */
const UPDATE_THROTTLE_MS = 67; // ~15Hz

/** Bus display configuration */
const BUS_DISPLAY_CONFIG: { id: BusId; label: string; color: string }[] = [
  { id: 'master', label: 'Master', color: '#f59e0b' },
  { id: 'music', label: 'Music', color: '#3b82f6' },
  { id: 'sfx', label: 'SFX', color: '#10b981' },
  { id: 'ambience', label: 'Ambience', color: '#8b5cf6' },
  { id: 'voice', label: 'VO', color: '#ef4444' },
];

/** Last command info for debug display */
interface LastCommandInfo {
  type: string;
  bus?: string;
  timestamp: number;
}

interface BusInspectorProps {
  /** Optional: external voice counts from AudioEngine */
  externalVoiceCounts?: Record<BusId, number>;
  /** Whether panel is collapsed */
  collapsed?: boolean;
  /** Toggle collapsed state */
  onToggleCollapsed?: () => void;
  /** Last command info for debug overlay */
  lastCommand?: LastCommandInfo | null;
}

export default function BusInspector({
  externalVoiceCounts,
  collapsed = false,
  onToggleCollapsed,
  lastCommand,
}: BusInspectorProps) {
  const snapshot = usePreviewMixSnapshot();
  const [throttledSnapshot, setThrottledSnapshot] = useState(snapshot);
  const [duckingState, setDuckingState] = useState({ isDucking: false, duckerVoiceCount: 0 });
  const [duckGainValues, setDuckGainValues] = useState<Record<InsertableBusId, number>>({
    music: 1,
    sfx: 1,
    ambience: 1,
    voice: 1,
  });
  const lastUpdateRef = useRef(0);

  // Throttle updates to 15Hz
  useEffect(() => {
    const now = Date.now();
    if (now - lastUpdateRef.current >= UPDATE_THROTTLE_MS) {
      setThrottledSnapshot(snapshot);
      // Also update ducking state from busInsertDSP
      setDuckingState(busInsertDSP.getDuckingState());
      setDuckGainValues({
        music: busInsertDSP.getDuckGainValue('music'),
        sfx: busInsertDSP.getDuckGainValue('sfx'),
        ambience: busInsertDSP.getDuckGainValue('ambience'),
        voice: busInsertDSP.getDuckGainValue('voice'),
      });
      lastUpdateRef.current = now;
    } else {
      const timeout = setTimeout(() => {
        setThrottledSnapshot(snapshot);
        setDuckingState(busInsertDSP.getDuckingState());
        setDuckGainValues({
          music: busInsertDSP.getDuckGainValue('music'),
          sfx: busInsertDSP.getDuckGainValue('sfx'),
          ambience: busInsertDSP.getDuckGainValue('ambience'),
          voice: busInsertDSP.getDuckGainValue('voice'),
        });
        lastUpdateRef.current = Date.now();
      }, UPDATE_THROTTLE_MS - (now - lastUpdateRef.current));
      return () => clearTimeout(timeout);
    }
  }, [snapshot]);

  // Use external voice counts if provided, otherwise use snapshot
  const getVoiceCount = (busId: BusId): number => {
    if (externalVoiceCounts && busId in externalVoiceCounts) {
      return externalVoiceCounts[busId];
    }
    return throttledSnapshot.buses[busId]?.activeVoices ?? 0;
  };

  // Get real duck gain value for a bus
  const getDuckGain = (busId: BusId): number => {
    if (busId === 'master') return 1;
    return duckGainValues[busId as InsertableBusId] ?? 1;
  };

  if (collapsed) {
    return (
      <div className="rf-bus-inspector rf-bus-inspector-collapsed" onClick={onToggleCollapsed}>
        <div className="rf-bus-inspector-collapsed-label">
          <span className="rf-bus-inspector-icon">🎛️</span>
          <span>Bus Inspector</span>
          {duckingState.isDucking && (
            <span className="rf-bus-inspector-duck-badge">DUCK</span>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="rf-bus-inspector">
      <div className="rf-bus-inspector-header" onClick={onToggleCollapsed}>
        <span className="rf-bus-inspector-icon">🎛️</span>
        <span className="rf-bus-inspector-title">Bus Inspector</span>
        <span className="rf-bus-inspector-subtitle">Preview Mix State</span>
        {onToggleCollapsed && (
          <button className="rf-bus-inspector-collapse-btn" title="Collapse">
            ▼
          </button>
        )}
      </div>

      <div className="rf-bus-inspector-content">
        {/* Master Gain */}
        <div className="rf-bus-inspector-master">
          <div className="rf-bus-inspector-master-label">Master</div>
          <div className="rf-bus-inspector-master-value">
            <div className="rf-bus-inspector-gain-track">
              <div
                className="rf-bus-inspector-gain-bar rf-bus-inspector-gain-effective"
                style={{
                  width: `${throttledSnapshot.masterGain * 100}%`,
                  backgroundColor: BUS_DISPLAY_CONFIG[0].color,
                }}
              />
            </div>
            <span className="rf-bus-inspector-gain-text">
              {(throttledSnapshot.masterGain * 100).toFixed(0)}%
            </span>
          </div>
        </div>

        {/* Ducking Status - uses real WebAudio ducking state */}
        <div className={`rf-bus-inspector-ducking ${duckingState.isDucking ? 'active' : ''}`}>
          <span className="rf-bus-inspector-ducking-label">Ducking</span>
          <span className={`rf-bus-inspector-ducking-status ${duckingState.isDucking ? 'on' : 'off'}`}>
            {duckingState.isDucking ? 'ON' : 'OFF'}
          </span>
          {duckingState.isDucking && (
            <span className="rf-bus-inspector-ducking-info">
              {DUCKING_CONFIG.DUCKER_BUS.toUpperCase()} → {DUCKING_CONFIG.DUCKED_BUS} ×{DUCKING_CONFIG.DUCK_RATIO}
            </span>
          )}
        </div>

        {/* Per-Bus State */}
        <div className="rf-bus-inspector-buses">
          {BUS_DISPLAY_CONFIG.filter(b => b.id !== 'master').map(bus => {
            const busState = throttledSnapshot.buses[bus.id];
            if (!busState) return null;

            // Use real duck gain from WebAudio DSP
            const duckGain = getDuckGain(bus.id);
            const isDucked = duckGain < 1;
            const effectiveGain = busState.baseGain * duckGain;
            const voiceCount = getVoiceCount(bus.id);

            return (
              <div
                key={bus.id}
                className={`rf-bus-inspector-bus ${isDucked ? 'ducked' : ''} ${voiceCount > 0 ? 'active' : ''}`}
              >
                <div className="rf-bus-inspector-bus-header">
                  <span
                    className="rf-bus-inspector-bus-indicator"
                    style={{ backgroundColor: bus.color }}
                  />
                  <span className="rf-bus-inspector-bus-name">{bus.label}</span>
                  <span className="rf-bus-inspector-bus-voices">
                    {voiceCount > 0 ? `${voiceCount} voice${voiceCount > 1 ? 's' : ''}` : '—'}
                  </span>
                </div>
                <div className="rf-bus-inspector-bus-gain">
                  <div className="rf-bus-inspector-gain-track">
                    {/* Base gain bar */}
                    <div
                      className="rf-bus-inspector-gain-bar rf-bus-inspector-gain-base"
                      style={{
                        width: `${busState.baseGain * 100}%`,
                        backgroundColor: `${bus.color}40`,
                      }}
                    />
                    {/* Effective gain bar (includes duck) */}
                    <div
                      className="rf-bus-inspector-gain-bar rf-bus-inspector-gain-effective"
                      style={{
                        width: `${effectiveGain * 100}%`,
                        backgroundColor: bus.color,
                      }}
                    />
                  </div>
                  <span className="rf-bus-inspector-gain-value">
                    {(effectiveGain * 100).toFixed(0)}%
                    {isDucked && (
                      <span className="rf-bus-inspector-duck-indicator">🔇</span>
                    )}
                  </span>
                </div>
                {/* Bus Insert Panel */}
                <BusInsertPanel
                  busId={bus.id as InsertableBusId}
                  busLabel={bus.label}
                  busColor={bus.color}
                />
              </div>
            );
          })}
        </div>

        {/* Signal Chain Diagram */}
        <div className="rf-bus-inspector-chain">
          <span className="rf-bus-inspector-chain-label">Signal Chain:</span>
          <span className="rf-bus-inspector-chain-flow">
            Asset → Gain → Bus → [INS] → Duck → Master → [INS] → Out
          </span>
        </div>

        {/* Debug: Last Command */}
        {lastCommand && (
          <div className="rf-bus-inspector-debug">
            <span className="rf-bus-inspector-debug-label">Last:</span>
            <span className={`rf-bus-inspector-debug-cmd rf-bus-inspector-debug-${lastCommand.type.toLowerCase()}`}>
              {lastCommand.type}
            </span>
            {lastCommand.bus && (
              <span className="rf-bus-inspector-debug-bus">
                {lastCommand.bus}
              </span>
            )}
            <span className="rf-bus-inspector-debug-time">
              {new Date(lastCommand.timestamp).toLocaleTimeString('en-US', { hour12: false })}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

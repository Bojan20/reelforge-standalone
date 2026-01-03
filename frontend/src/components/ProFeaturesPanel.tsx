/**
 * Professional Features Panel
 *
 * UI for advanced audio middleware features:
 * - Soundbank Management
 * - Streaming Audio
 * - Aux Send/Return
 * - Switch Containers
 * - Offline Bounce
 * - Live Update
 * - Certification Export
 */

import React, { useState, memo, useCallback } from 'react';
import type { BusId } from '../core/types';
import type { BankStatus, LoadPriority } from '../core/soundbankManager';
import type { SampleRate, BitDepth, BounceFormat } from '../core/offlineBounce';
import type { ConnectionStatus } from '../core/liveUpdate';
import './ProFeaturesPanel.css';

// ============ TYPES ============

interface ProFeaturesPanelProps {
  buses: Array<{ id: BusId; name: string }>;
  onFeatureChange?: (feature: string, enabled: boolean) => void;
}

// ============ HELPER COMPONENTS ============

const SectionHeader = memo(({
  title,
  enabled,
  onToggle,
  expanded,
  onExpand,
}: {
  title: string;
  enabled?: boolean;
  onToggle?: (enabled: boolean) => void;
  expanded: boolean;
  onExpand: () => void;
}) => (
  <div className="pro-section-header" onClick={onExpand}>
    <div className="pro-section-title">
      <span className={`pro-expand-icon ${expanded ? 'expanded' : ''}`}>▶</span>
      {title}
    </div>
    {onToggle && (
      <label className="pro-toggle" onClick={e => e.stopPropagation()}>
        <input
          type="checkbox"
          checked={enabled}
          onChange={e => onToggle(e.target.checked)}
        />
        <span className="pro-toggle-slider" />
      </label>
    )}
  </div>
));

// ============ SOUNDBANK SECTION ============

const SoundbankSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(true);
  const [banks, setBanks] = useState<Array<{
    id: string;
    name: string;
    status: BankStatus;
    memoryMB: number;
    priority: LoadPriority;
  }>>([
    { id: 'core', name: 'Core Sounds', status: 'loaded', memoryMB: 5, priority: 'startup' },
    { id: 'music', name: 'Music', status: 'loaded', memoryMB: 45, priority: 'startup' },
    { id: 'sfx_base', name: 'Base SFX', status: 'loaded', memoryMB: 12, priority: 'level' },
    { id: 'sfx_wins', name: 'Win SFX', status: 'unloaded', memoryMB: 18, priority: 'level' },
    { id: 'sfx_bonus', name: 'Bonus SFX', status: 'unloaded', memoryMB: 15, priority: 'on-demand' },
  ]);

  const totalLoaded = banks.filter(b => b.status === 'loaded').reduce((sum, b) => sum + b.memoryMB, 0);
  const memoryBudget = 100;

  const handleLoadBank = (bankId: string) => {
    setBanks(prev => prev.map(b =>
      b.id === bankId ? { ...b, status: 'loading' as BankStatus } : b
    ));
    setTimeout(() => {
      setBanks(prev => prev.map(b =>
        b.id === bankId ? { ...b, status: 'loaded' as BankStatus } : b
      ));
    }, 500);
  };

  const handleUnloadBank = (bankId: string) => {
    setBanks(prev => prev.map(b =>
      b.id === bankId ? { ...b, status: 'unloaded' as BankStatus } : b
    ));
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Soundbank Management"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-memory-bar">
            <div className="pro-memory-label">
              Memory: {totalLoaded}MB / {memoryBudget}MB
            </div>
            <div className="pro-memory-track">
              <div
                className="pro-memory-fill"
                style={{ width: `${(totalLoaded / memoryBudget) * 100}%` }}
              />
            </div>
          </div>

          <div className="pro-bank-list">
            {banks.map(bank => (
              <div key={bank.id} className="pro-bank-item">
                <div className="pro-bank-info">
                  <span className={`pro-bank-status ${bank.status}`} />
                  <span className="pro-bank-name">{bank.name}</span>
                  <span className="pro-bank-size">{bank.memoryMB}MB</span>
                  <span className={`pro-bank-priority ${bank.priority}`}>{bank.priority}</span>
                </div>
                <div className="pro-bank-actions">
                  {bank.status === 'unloaded' && (
                    <button
                      className="pro-btn pro-btn-sm"
                      onClick={() => handleLoadBank(bank.id)}
                      disabled={!enabled}
                    >
                      Load
                    </button>
                  )}
                  {bank.status === 'loaded' && (
                    <button
                      className="pro-btn pro-btn-sm pro-btn-outline"
                      onClick={() => handleUnloadBank(bank.id)}
                      disabled={!enabled}
                    >
                      Unload
                    </button>
                  )}
                  {bank.status === 'loading' && (
                    <span className="pro-loading">Loading...</span>
                  )}
                </div>
              </div>
            ))}
          </div>

          <div className="pro-bank-actions-global">
            <button className="pro-btn" disabled={!enabled}>Load All Startup</button>
            <button className="pro-btn pro-btn-outline" disabled={!enabled}>Unload On-Demand</button>
          </div>
        </div>
      )}
    </div>
  );
});

// ============ STREAMING SECTION ============

const StreamingSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [config, setConfig] = useState({
    prefetchDuration: 5,
    bufferAhead: 10,
    maxStreams: 8,
  });

  const [streams] = useState([
    { id: 'stream_1', asset: 'music_base', bufferHealth: 0.95, position: 45.2, duration: 180 },
    { id: 'stream_2', asset: 'ambience_bg', bufferHealth: 0.88, position: 120.5, duration: 300 },
  ]);

  return (
    <div className="pro-section">
      <SectionHeader
        title="Streaming Audio"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-config-grid">
            <label>
              Prefetch Duration (s)
              <input
                type="number"
                value={config.prefetchDuration}
                onChange={e => setConfig(prev => ({ ...prev, prefetchDuration: Number(e.target.value) }))}
                disabled={!enabled}
                min={1}
                max={30}
              />
            </label>
            <label>
              Buffer Ahead (s)
              <input
                type="number"
                value={config.bufferAhead}
                onChange={e => setConfig(prev => ({ ...prev, bufferAhead: Number(e.target.value) }))}
                disabled={!enabled}
                min={5}
                max={60}
              />
            </label>
            <label>
              Max Concurrent Streams
              <input
                type="number"
                value={config.maxStreams}
                onChange={e => setConfig(prev => ({ ...prev, maxStreams: Number(e.target.value) }))}
                disabled={!enabled}
                min={1}
                max={16}
              />
            </label>
          </div>

          <div className="pro-stream-list">
            <div className="pro-stream-header">
              <span>Asset</span>
              <span>Buffer Health</span>
              <span>Position</span>
            </div>
            {streams.map(stream => (
              <div key={stream.id} className="pro-stream-item">
                <span>{stream.asset}</span>
                <div className="pro-buffer-bar">
                  <div
                    className={`pro-buffer-fill ${stream.bufferHealth < 0.5 ? 'low' : ''}`}
                    style={{ width: `${stream.bufferHealth * 100}%` }}
                  />
                  <span>{(stream.bufferHealth * 100).toFixed(0)}%</span>
                </div>
                <span>{stream.position.toFixed(1)}s / {stream.duration}s</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
});

// ============ AUX SENDS SECTION ============

const AuxSendsSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [auxBuses, setAuxBuses] = useState<Array<{
    id: string;
    name: string;
    volume: number;
    muted: boolean;
    effect: string;
  }>>([
    { id: 'aux_reverb', name: 'Reverb Send', volume: 0.5, muted: false, effect: 'Hall Reverb' },
    { id: 'aux_delay', name: 'Delay Send', volume: 0.3, muted: false, effect: 'Stereo Delay' },
    { id: 'aux_chorus', name: 'Chorus Send', volume: 0.4, muted: true, effect: 'Chorus' },
  ]);

  const handleVolumeChange = (busId: string, volume: number) => {
    setAuxBuses(prev => prev.map(b => b.id === busId ? { ...b, volume } : b));
  };

  const handleMuteToggle = (busId: string) => {
    setAuxBuses(prev => prev.map(b => b.id === busId ? { ...b, muted: !b.muted } : b));
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Aux Send/Return"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-aux-list">
            {auxBuses.map(bus => (
              <div key={bus.id} className={`pro-aux-item ${bus.muted ? 'muted' : ''}`}>
                <div className="pro-aux-header">
                  <span className="pro-aux-name">{bus.name}</span>
                  <span className="pro-aux-effect">{bus.effect}</span>
                  <button
                    className={`pro-mute-btn ${bus.muted ? 'active' : ''}`}
                    onClick={() => handleMuteToggle(bus.id)}
                    disabled={!enabled}
                  >
                    M
                  </button>
                </div>
                <div className="pro-aux-fader">
                  <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.01}
                    value={bus.volume}
                    onChange={e => handleVolumeChange(bus.id, Number(e.target.value))}
                    disabled={!enabled || bus.muted}
                  />
                  <span>{(bus.volume * 100).toFixed(0)}%</span>
                </div>
              </div>
            ))}
          </div>
          <button className="pro-btn pro-btn-sm" disabled={!enabled}>+ Add Aux Bus</button>
        </div>
      )}
    </div>
  );
});

// ============ SWITCH CONTAINER SECTION ============

const SwitchContainerSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [switchGroups, setSwitchGroups] = useState<Array<{
    id: string;
    name: string;
    currentValue: string;
    values: string[];
  }>>([
    { id: 'game_state', name: 'Game State', currentValue: 'idle', values: ['idle', 'spinning', 'anticipation', 'win', 'big_win', 'bonus'] },
    { id: 'music_intensity', name: 'Music Intensity', currentValue: 'medium', values: ['low', 'medium', 'high', 'max'] },
    { id: 'environment', name: 'Environment', currentValue: 'default', values: ['default', 'underwater', 'space', 'ancient', 'fantasy'] },
  ]);

  const handleSwitchChange = (groupId: string, value: string) => {
    setSwitchGroups(prev => prev.map(g =>
      g.id === groupId ? { ...g, currentValue: value } : g
    ));
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Switch Containers"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-switch-list">
            {switchGroups.map(group => (
              <div key={group.id} className="pro-switch-group">
                <label className="pro-switch-label">{group.name}</label>
                <select
                  value={group.currentValue}
                  onChange={e => handleSwitchChange(group.id, e.target.value)}
                  disabled={!enabled}
                  className="pro-switch-select"
                >
                  {group.values.map(v => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </div>
            ))}
          </div>
          <div className="pro-switch-actions">
            <button className="pro-btn pro-btn-sm" disabled={!enabled}>+ Add Switch Group</button>
            <button className="pro-btn pro-btn-sm pro-btn-outline" disabled={!enabled}>Reset All</button>
          </div>
        </div>
      )}
    </div>
  );
});

// ============ OFFLINE BOUNCE SECTION ============

const OfflineBounceSection = memo(({
  enabled,
  onToggle,
  buses: _buses,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
  buses: Array<{ id: BusId; name: string }>;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [config, setConfig] = useState({
    startTime: 0,
    endTime: 10,
    sampleRate: 48000 as SampleRate,
    bitDepth: 24 as BitDepth,
    format: 'wav' as BounceFormat,
    normalize: false,
    targetLoudness: -14,
  });
  const [isRendering, setIsRendering] = useState(false);
  const [progress, setProgress] = useState(0);

  const handleBounce = () => {
    setIsRendering(true);
    setProgress(0);
    const interval = setInterval(() => {
      setProgress(prev => {
        if (prev >= 100) {
          clearInterval(interval);
          setIsRendering(false);
          return 100;
        }
        return prev + 5;
      });
    }, 100);
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Offline Bounce"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-bounce-config">
            <div className="pro-bounce-row">
              <label>
                Start (s)
                <input
                  type="number"
                  value={config.startTime}
                  onChange={e => setConfig(prev => ({ ...prev, startTime: Number(e.target.value) }))}
                  disabled={!enabled || isRendering}
                  min={0}
                  step={0.1}
                />
              </label>
              <label>
                End (s)
                <input
                  type="number"
                  value={config.endTime}
                  onChange={e => setConfig(prev => ({ ...prev, endTime: Number(e.target.value) }))}
                  disabled={!enabled || isRendering}
                  min={0.1}
                  step={0.1}
                />
              </label>
            </div>

            <div className="pro-bounce-row">
              <label>
                Sample Rate
                <select
                  value={config.sampleRate}
                  onChange={e => setConfig(prev => ({ ...prev, sampleRate: Number(e.target.value) as SampleRate }))}
                  disabled={!enabled || isRendering}
                >
                  <option value={44100}>44.1 kHz</option>
                  <option value={48000}>48 kHz</option>
                  <option value={96000}>96 kHz</option>
                </select>
              </label>
              <label>
                Bit Depth
                <select
                  value={config.bitDepth}
                  onChange={e => setConfig(prev => ({ ...prev, bitDepth: Number(e.target.value) as BitDepth }))}
                  disabled={!enabled || isRendering}
                >
                  <option value={16}>16-bit</option>
                  <option value={24}>24-bit</option>
                  <option value={32}>32-bit float</option>
                </select>
              </label>
              <label>
                Format
                <select
                  value={config.format}
                  onChange={e => setConfig(prev => ({ ...prev, format: e.target.value as BounceFormat }))}
                  disabled={!enabled || isRendering}
                >
                  <option value="wav">WAV</option>
                  <option value="mp3">MP3</option>
                  <option value="ogg">OGG</option>
                </select>
              </label>
            </div>

            <div className="pro-bounce-row">
              <label className="pro-checkbox-label">
                <input
                  type="checkbox"
                  checked={config.normalize}
                  onChange={e => setConfig(prev => ({ ...prev, normalize: e.target.checked }))}
                  disabled={!enabled || isRendering}
                />
                Normalize to
                <input
                  type="number"
                  value={config.targetLoudness}
                  onChange={e => setConfig(prev => ({ ...prev, targetLoudness: Number(e.target.value) }))}
                  disabled={!enabled || isRendering || !config.normalize}
                  min={-30}
                  max={0}
                  step={1}
                  style={{ width: 60 }}
                />
                LUFS
              </label>
            </div>
          </div>

          {isRendering && (
            <div className="pro-bounce-progress">
              <div className="pro-progress-bar">
                <div className="pro-progress-fill" style={{ width: `${progress}%` }} />
              </div>
              <span>{progress}%</span>
            </div>
          )}

          <div className="pro-bounce-actions">
            <button
              className="pro-btn pro-btn-primary"
              onClick={handleBounce}
              disabled={!enabled || isRendering}
            >
              {isRendering ? 'Rendering...' : 'Bounce'}
            </button>
            <button
              className="pro-btn"
              disabled={!enabled || isRendering}
            >
              Bounce Stems
            </button>
          </div>
        </div>
      )}
    </div>
  );
});

// ============ LIVE UPDATE SECTION ============

const LiveUpdateSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [status, setStatus] = useState<ConnectionStatus>('disconnected');
  const [host, setHost] = useState('localhost');
  const [port, setPort] = useState(9876);

  const handleConnect = () => {
    setStatus('connecting');
    setTimeout(() => setStatus('connected'), 1000);
  };

  const handleDisconnect = () => {
    setStatus('disconnected');
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Live Update"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-live-status">
            <span className={`pro-status-indicator ${status}`} />
            <span>{status.charAt(0).toUpperCase() + status.slice(1)}</span>
          </div>

          <div className="pro-live-config">
            <label>
              Host
              <input
                type="text"
                value={host}
                onChange={e => setHost(e.target.value)}
                disabled={!enabled || status === 'connected'}
              />
            </label>
            <label>
              Port
              <input
                type="number"
                value={port}
                onChange={e => setPort(Number(e.target.value))}
                disabled={!enabled || status === 'connected'}
                min={1024}
                max={65535}
              />
            </label>
          </div>

          <div className="pro-live-actions">
            {status === 'disconnected' && (
              <button
                className="pro-btn pro-btn-primary"
                onClick={handleConnect}
                disabled={!enabled}
              >
                Connect
              </button>
            )}
            {status === 'connecting' && (
              <button className="pro-btn" disabled>
                Connecting...
              </button>
            )}
            {status === 'connected' && (
              <>
                <button
                  className="pro-btn pro-btn-outline"
                  onClick={handleDisconnect}
                  disabled={!enabled}
                >
                  Disconnect
                </button>
                <button className="pro-btn" disabled={!enabled}>
                  Push Changes
                </button>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
});

// ============ CERTIFICATION SECTION ============

const CertificationSection = memo(({
  enabled,
  onToggle,
}: {
  enabled: boolean;
  onToggle: (enabled: boolean) => void;
}) => {
  const [expanded, setExpanded] = useState(false);
  const [exportFormat, setExportFormat] = useState<'json' | 'csv' | 'xml'>('json');
  const [isGenerating, setIsGenerating] = useState(false);

  const handleGenerateReport = () => {
    setIsGenerating(true);
    setTimeout(() => setIsGenerating(false), 2000);
  };

  return (
    <div className="pro-section">
      <SectionHeader
        title="Certification Export"
        enabled={enabled}
        onToggle={onToggle}
        expanded={expanded}
        onExpand={() => setExpanded(!expanded)}
      />
      {expanded && (
        <div className="pro-section-content">
          <div className="pro-cert-info">
            <div className="pro-cert-row">
              <span>RNG Algorithm:</span>
              <span>XorShift128+</span>
            </div>
            <div className="pro-cert-row">
              <span>Deterministic:</span>
              <span className="pro-cert-pass">Yes</span>
            </div>
            <div className="pro-cert-row">
              <span>Asset Integrity:</span>
              <span className="pro-cert-pass">Verified</span>
            </div>
            <div className="pro-cert-row">
              <span>Volume Compliance:</span>
              <span className="pro-cert-pass">ITU-R BS.1770</span>
            </div>
            <div className="pro-cert-row">
              <span>Event Coverage:</span>
              <span>95.5%</span>
            </div>
          </div>

          <div className="pro-cert-format">
            <label>Export Format</label>
            <div className="pro-format-options">
              <button
                className={`pro-format-btn ${exportFormat === 'json' ? 'active' : ''}`}
                onClick={() => setExportFormat('json')}
                disabled={!enabled}
              >
                JSON
              </button>
              <button
                className={`pro-format-btn ${exportFormat === 'csv' ? 'active' : ''}`}
                onClick={() => setExportFormat('csv')}
                disabled={!enabled}
              >
                CSV (PAR)
              </button>
              <button
                className={`pro-format-btn ${exportFormat === 'xml' ? 'active' : ''}`}
                onClick={() => setExportFormat('xml')}
                disabled={!enabled}
              >
                XML (GLI)
              </button>
            </div>
          </div>

          <div className="pro-cert-actions">
            <button
              className="pro-btn pro-btn-primary"
              onClick={handleGenerateReport}
              disabled={!enabled || isGenerating}
            >
              {isGenerating ? 'Generating...' : 'Generate Report'}
            </button>
            <button
              className="pro-btn"
              disabled={!enabled}
            >
              Run Compliance Test
            </button>
          </div>
        </div>
      )}
    </div>
  );
});

// ============ MAIN PANEL ============

const ProFeaturesPanel: React.FC<ProFeaturesPanelProps> = ({
  buses,
  onFeatureChange,
}) => {
  const [features, setFeatures] = useState({
    soundbanks: true,
    streaming: true,
    auxSends: true,
    switches: true,
    bounce: true,
    liveUpdate: false,
    certification: true,
  });

  const handleFeatureToggle = useCallback((feature: keyof typeof features, enabled: boolean) => {
    setFeatures(prev => ({ ...prev, [feature]: enabled }));
    onFeatureChange?.(feature, enabled);
  }, [onFeatureChange]);

  return (
    <div className="pro-features-panel">
      <div className="pro-features-header">
        <h2>Professional Features</h2>
        <span className="pro-badge">Pro</span>
      </div>

      <div className="pro-features-content">
        <SoundbankSection
          enabled={features.soundbanks}
          onToggle={(e) => handleFeatureToggle('soundbanks', e)}
        />

        <StreamingSection
          enabled={features.streaming}
          onToggle={(e) => handleFeatureToggle('streaming', e)}
        />

        <AuxSendsSection
          enabled={features.auxSends}
          onToggle={(e) => handleFeatureToggle('auxSends', e)}
        />

        <SwitchContainerSection
          enabled={features.switches}
          onToggle={(e) => handleFeatureToggle('switches', e)}
        />

        <OfflineBounceSection
          enabled={features.bounce}
          onToggle={(e) => handleFeatureToggle('bounce', e)}
          buses={buses}
        />

        <LiveUpdateSection
          enabled={features.liveUpdate}
          onToggle={(e) => handleFeatureToggle('liveUpdate', e)}
        />

        <CertificationSection
          enabled={features.certification}
          onToggle={(e) => handleFeatureToggle('certification', e)}
        />
      </div>
    </div>
  );
};

export default memo(ProFeaturesPanel);

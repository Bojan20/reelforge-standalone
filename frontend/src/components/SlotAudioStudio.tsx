/**
 * Slot Audio Studio
 *
 * Revolutionary slot-game-focused audio editor:
 * - Game State Tabs (Base Game, Free Spins, Bonus, Jackpot)
 * - Visual Timeline per state
 * - Inline Editing (hover to reveal controls)
 * - Mini Visualizers (ducking curves, EQ response)
 * - One-click Preview
 * - Slot-specific terminology
 */

import React, { useState, memo, useCallback, useRef, useEffect } from 'react';
import type { BusId } from '../core/types';
import './SlotAudioStudio.css';

// ============ TYPES ============

type GameState = 'base' | 'freespins' | 'bonus' | 'jackpot' | 'settings';

interface SlotEvent {
  id: string;
  name: string;
  category: 'reel' | 'win' | 'feature' | 'ui' | 'music' | 'ambience';
  duration: number;
  volume: number;
  bus: BusId;
  enabled: boolean;
  hasVariations: boolean;
  variationCount?: number;
}

interface MusicLayer {
  id: string;
  name: string;
  state: 'idle' | 'spin' | 'win' | 'feature';
  volume: number;
  crossfadeMs: number;
}

interface DuckingRule {
  id: string;
  source: string;
  target: string;
  amount: number;
  attackMs: number;
  releaseMs: number;
}

interface SlotAudioStudioProps {
  onEventTrigger?: (eventId: string) => void;
  onEventSelect?: (eventId: string) => void;
  onPlayPreview?: (eventId: string) => void;
  onStateChange?: (state: GameState) => void;
}

// ============ GAME STATE CONFIG ============

const GAME_STATE_CONFIG: Record<GameState, { label: string; icon: string; color: string }> = {
  base: { label: 'Base Game', icon: '🎰', color: '#3b82f6' },
  freespins: { label: 'Free Spins', icon: '🎁', color: '#8b5cf6' },
  bonus: { label: 'Bonus', icon: '⭐', color: '#f59e0b' },
  jackpot: { label: 'Jackpot', icon: '💎', color: '#ef4444' },
  settings: { label: 'Settings', icon: '⚙️', color: '#6b7280' },
};

// ============ CATEGORY CONFIG ============

const CATEGORY_CONFIG: Record<string, { label: string; color: string; bgColor: string }> = {
  reel: { label: 'Reel', color: '#22c55e', bgColor: '#22c55e20' },
  win: { label: 'Win', color: '#eab308', bgColor: '#eab30820' },
  feature: { label: 'Feature', color: '#8b5cf6', bgColor: '#8b5cf620' },
  ui: { label: 'UI', color: '#6b7280', bgColor: '#6b728020' },
  music: { label: 'Music', color: '#3b82f6', bgColor: '#3b82f620' },
  ambience: { label: 'Ambience', color: '#06b6d4', bgColor: '#06b6d420' },
};

// ============ DEMO DATA ============

const DEMO_EVENTS: Record<GameState, SlotEvent[]> = {
  base: [
    { id: 'reel_spin', name: 'Reel Spin', category: 'reel', duration: 0.8, volume: 1, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 5 },
    { id: 'reel_stop', name: 'Reel Stop', category: 'reel', duration: 0.3, volume: 0.9, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 5 },
    { id: 'reel_anticipation', name: 'Anticipation', category: 'reel', duration: 1.5, volume: 0.85, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'win_small', name: 'Small Win', category: 'win', duration: 0.5, volume: 0.8, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 3 },
    { id: 'win_medium', name: 'Medium Win', category: 'win', duration: 1.2, volume: 0.9, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 3 },
    { id: 'win_big', name: 'Big Win', category: 'win', duration: 2.5, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'coin_drop', name: 'Coin Drop', category: 'win', duration: 0.2, volume: 0.7, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 8 },
    { id: 'btn_spin', name: 'Spin Button', category: 'ui', duration: 0.1, volume: 0.6, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'btn_bet', name: 'Bet Change', category: 'ui', duration: 0.08, volume: 0.5, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'music_base', name: 'Base Music', category: 'music', duration: 120, volume: 0.7, bus: 'music', enabled: true, hasVariations: false },
    { id: 'amb_casino', name: 'Casino Ambience', category: 'ambience', duration: 60, volume: 0.3, bus: 'ambience', enabled: true, hasVariations: false },
  ],
  freespins: [
    { id: 'fs_trigger', name: 'FS Trigger', category: 'feature', duration: 2.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'fs_spin', name: 'FS Reel Spin', category: 'reel', duration: 0.6, volume: 0.9, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 3 },
    { id: 'fs_stop', name: 'FS Reel Stop', category: 'reel', duration: 0.25, volume: 0.85, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 3 },
    { id: 'fs_win', name: 'FS Win', category: 'win', duration: 1.5, volume: 1, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 4 },
    { id: 'fs_retrigger', name: 'FS Retrigger', category: 'feature', duration: 2.5, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'fs_complete', name: 'FS Complete', category: 'feature', duration: 3.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'music_fs', name: 'Free Spins Music', category: 'music', duration: 90, volume: 0.8, bus: 'music', enabled: true, hasVariations: false },
  ],
  bonus: [
    { id: 'bonus_trigger', name: 'Bonus Trigger', category: 'feature', duration: 3.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'bonus_pick', name: 'Pick Item', category: 'feature', duration: 0.3, volume: 0.9, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 6 },
    { id: 'bonus_reveal', name: 'Reveal Prize', category: 'win', duration: 1.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: true, variationCount: 4 },
    { id: 'bonus_multiplier', name: 'Multiplier Hit', category: 'win', duration: 1.5, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'bonus_complete', name: 'Bonus Complete', category: 'feature', duration: 4.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'music_bonus', name: 'Bonus Music', category: 'music', duration: 60, volume: 0.85, bus: 'music', enabled: true, hasVariations: false },
  ],
  jackpot: [
    { id: 'jp_trigger', name: 'Jackpot Trigger', category: 'feature', duration: 5.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'jp_buildup', name: 'Jackpot Buildup', category: 'feature', duration: 8.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'jp_hit', name: 'Jackpot Hit', category: 'win', duration: 10.0, volume: 1, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'jp_coins', name: 'Coin Shower', category: 'win', duration: 15.0, volume: 0.9, bus: 'sfx', enabled: true, hasVariations: false },
    { id: 'music_jackpot', name: 'Jackpot Music', category: 'music', duration: 30, volume: 1, bus: 'music', enabled: true, hasVariations: false },
  ],
  settings: [],
};

const DEMO_MUSIC_LAYERS: MusicLayer[] = [
  { id: 'layer_idle', name: 'Idle', state: 'idle', volume: 0.6, crossfadeMs: 1000 },
  { id: 'layer_spin', name: 'Spin', state: 'spin', volume: 0.8, crossfadeMs: 500 },
  { id: 'layer_win', name: 'Win', state: 'win', volume: 1.0, crossfadeMs: 300 },
  { id: 'layer_feature', name: 'Feature', state: 'feature', volume: 1.0, crossfadeMs: 800 },
];

const DEMO_DUCKING_RULES: DuckingRule[] = [
  { id: 'duck_1', source: 'Win SFX', target: 'Music', amount: -12, attackMs: 50, releaseMs: 500 },
  { id: 'duck_2', source: 'Voice', target: 'All', amount: -18, attackMs: 20, releaseMs: 300 },
  { id: 'duck_3', source: 'Feature', target: 'Ambience', amount: -24, attackMs: 100, releaseMs: 1000 },
];

// ============ MINI VISUALIZER COMPONENTS ============

const DuckingCurve = memo(({ attackMs, releaseMs, amount }: { attackMs: number; releaseMs: number; amount: number }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const w = canvas.width;
    const h = canvas.height;

    ctx.clearRect(0, 0, w, h);

    // Background grid
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 4; i++) {
      const y = (h / 4) * i;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }

    // Ducking curve
    const attackX = (attackMs / (attackMs + releaseMs + 100)) * w * 0.4;
    const holdX = attackX + w * 0.2;
    const releaseX = holdX + (releaseMs / (attackMs + releaseMs + 100)) * w * 0.4;
    const duckY = h - (Math.abs(amount) / 24) * h * 0.8;

    ctx.beginPath();
    ctx.strokeStyle = '#ef4444';
    ctx.lineWidth = 2;
    ctx.moveTo(0, h * 0.1);
    ctx.lineTo(attackX, duckY);
    ctx.lineTo(holdX, duckY);
    ctx.lineTo(releaseX, h * 0.1);
    ctx.lineTo(w, h * 0.1);
    ctx.stroke();

    // Fill
    ctx.fillStyle = '#ef444420';
    ctx.beginPath();
    ctx.moveTo(0, h * 0.1);
    ctx.lineTo(attackX, duckY);
    ctx.lineTo(holdX, duckY);
    ctx.lineTo(releaseX, h * 0.1);
    ctx.lineTo(w, h * 0.1);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();

  }, [attackMs, releaseMs, amount]);

  return <canvas ref={canvasRef} width={120} height={40} className="ducking-curve-canvas" />;
});

const WaveformBar = memo(({ duration, isPlaying }: { duration: number; isPlaying?: boolean }) => {
  const bars = Math.min(20, Math.max(5, Math.floor(duration * 10)));
  return (
    <div className={`waveform-bar ${isPlaying ? 'playing' : ''}`}>
      {Array.from({ length: bars }).map((_, i) => (
        <div
          key={i}
          className="waveform-segment"
          style={{
            height: `${30 + Math.random() * 70}%`,
            animationDelay: `${i * 50}ms`,
          }}
        />
      ))}
    </div>
  );
});

const MusicLayerTimeline = memo(({ layers }: { layers: MusicLayer[] }) => {
  return (
    <div className="music-timeline">
      {layers.map((layer, i) => (
        <div key={layer.id} className="music-timeline-layer">
          <div
            className="music-timeline-block"
            style={{
              left: `${i * 25}%`,
              width: '30%',
              backgroundColor: `hsl(${220 + i * 30}, 70%, 50%)`,
            }}
          >
            <span>{layer.name}</span>
          </div>
          {i < layers.length - 1 && (
            <div
              className="music-timeline-crossfade"
              style={{ left: `${(i + 1) * 25 - 5}%` }}
            >
              ╳ {layer.crossfadeMs}ms
            </div>
          )}
        </div>
      ))}
    </div>
  );
});

// ============ EVENT ROW COMPONENT ============

const EventRow = memo(({
  event,
  onPreview,
  onEdit,
  onToggle,
  onVolumeChange,
}: {
  event: SlotEvent;
  onPreview: () => void;
  onEdit: () => void;
  onToggle: () => void;
  onVolumeChange: (volume: number) => void;
}) => {
  const [isHovered, setIsHovered] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const categoryConfig = CATEGORY_CONFIG[event.category];

  return (
    <div
      className={`event-row ${!event.enabled ? 'disabled' : ''} ${isHovered ? 'hovered' : ''}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <div className="event-row-main">
        <button
          className="event-toggle"
          onClick={onToggle}
          style={{ borderColor: event.enabled ? categoryConfig.color : '#666' }}
        >
          {event.enabled ? '●' : '○'}
        </button>

        <div
          className="event-category-badge"
          style={{ backgroundColor: categoryConfig.bgColor, color: categoryConfig.color }}
        >
          {categoryConfig.label}
        </div>

        <span className="event-name">{event.name}</span>

        {event.hasVariations && (
          <span className="event-variations">×{event.variationCount}</span>
        )}

        <WaveformBar duration={event.duration} />

        <span className="event-duration">{event.duration.toFixed(2)}s</span>

        <div className={`event-actions ${isHovered ? 'visible' : ''}`}>
          <button className="event-btn preview" onClick={onPreview} title="Preview">
            ▶
          </button>
          <button className="event-btn edit" onClick={() => setIsEditing(!isEditing)} title="Edit">
            ✎
          </button>
        </div>
      </div>

      {/* Inline Edit Panel */}
      {isEditing && (
        <div className="event-inline-edit">
          <label>
            Volume
            <input
              type="range"
              min={0}
              max={1}
              step={0.01}
              value={event.volume}
              onChange={(e) => onVolumeChange(Number(e.target.value))}
            />
            <span>{Math.round(event.volume * 100)}%</span>
          </label>
          <label>
            Bus
            <select defaultValue={event.bus}>
              <option value="sfx">SFX</option>
              <option value="music">Music</option>
              <option value="voice">Voice</option>
              <option value="ambience">Ambience</option>
            </select>
          </label>
          <button className="event-btn" onClick={onEdit}>
            Open Editor →
          </button>
        </div>
      )}
    </div>
  );
});

// ============ DUCKING RULE ROW ============

const DuckingRuleRow = memo(({ rule }: { rule: DuckingRule }) => {
  const [isHovered, setIsHovered] = useState(false);

  return (
    <div
      className={`ducking-row ${isHovered ? 'hovered' : ''}`}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <div className="ducking-route">
        <span className="ducking-source">{rule.source}</span>
        <span className="ducking-arrow">→</span>
        <span className="ducking-target">{rule.target}</span>
      </div>

      <DuckingCurve attackMs={rule.attackMs} releaseMs={rule.releaseMs} amount={rule.amount} />

      <div className={`ducking-params ${isHovered ? 'visible' : ''}`}>
        <span>{rule.amount}dB</span>
        <span>A: {rule.attackMs}ms</span>
        <span>R: {rule.releaseMs}ms</span>
      </div>
    </div>
  );
});

// ============ SETTINGS PANEL ============

const SettingsPanel = memo(() => {
  return (
    <div className="settings-panel">
      <h3>Global Settings</h3>

      <div className="settings-section">
        <h4>Memory Management</h4>
        <div className="settings-row">
          <label>Memory Budget</label>
          <input type="number" defaultValue={100} /> MB
        </div>
        <div className="settings-row">
          <label>Auto-unload on budget</label>
          <input type="checkbox" defaultChecked />
        </div>
      </div>

      <div className="settings-section">
        <h4>Streaming</h4>
        <div className="settings-row">
          <label>Prefetch Duration</label>
          <input type="number" defaultValue={5} /> s
        </div>
        <div className="settings-row">
          <label>Buffer Ahead</label>
          <input type="number" defaultValue={10} /> s
        </div>
      </div>

      <div className="settings-section">
        <h4>Live Update</h4>
        <div className="settings-row">
          <label>Enable Live Update</label>
          <input type="checkbox" />
        </div>
        <div className="settings-row">
          <label>Port</label>
          <input type="number" defaultValue={9876} />
        </div>
      </div>

      <div className="settings-section">
        <h4>Certification</h4>
        <button className="settings-btn">Generate Report</button>
        <button className="settings-btn">Run Compliance Test</button>
      </div>
    </div>
  );
});

// ============ MAIN COMPONENT ============

const SlotAudioStudio: React.FC<SlotAudioStudioProps> = ({
  onEventTrigger,
  onStateChange,
}) => {
  const [activeState, setActiveState] = useState<GameState>('base');
  const [events, setEvents] = useState(DEMO_EVENTS);
  const [musicLayers] = useState(DEMO_MUSIC_LAYERS);
  const [duckingRules] = useState(DEMO_DUCKING_RULES);
  const [searchQuery, setSearchQuery] = useState('');
  const [showCommandPalette, setShowCommandPalette] = useState(false);

  // Keyboard shortcut for command palette
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setShowCommandPalette(prev => !prev);
      }
      if (e.key === 'Escape') {
        setShowCommandPalette(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const handleStateChange = useCallback((state: GameState) => {
    setActiveState(state);
    onStateChange?.(state);
  }, [onStateChange]);

  const handleEventPreview = useCallback((eventId: string) => {
    onEventTrigger?.(eventId);
  }, [onEventTrigger]);

  const handleEventToggle = useCallback((eventId: string) => {
    setEvents(prev => ({
      ...prev,
      [activeState]: prev[activeState].map(e =>
        e.id === eventId ? { ...e, enabled: !e.enabled } : e
      ),
    }));
  }, [activeState]);

  const handleEventVolumeChange = useCallback((eventId: string, volume: number) => {
    setEvents(prev => ({
      ...prev,
      [activeState]: prev[activeState].map(e =>
        e.id === eventId ? { ...e, volume } : e
      ),
    }));
  }, [activeState]);

  const currentEvents = events[activeState] ?? [];
  const filteredEvents = searchQuery
    ? currentEvents.filter(e => e.name.toLowerCase().includes(searchQuery.toLowerCase()))
    : currentEvents;

  // Group events by category
  const groupedEvents = filteredEvents.reduce((acc, event) => {
    if (!acc[event.category]) acc[event.category] = [];
    acc[event.category].push(event);
    return acc;
  }, {} as Record<string, SlotEvent[]>);

  const stateConfig = GAME_STATE_CONFIG[activeState];

  return (
    <div className="slot-audio-studio">
      {/* Command Palette */}
      {showCommandPalette && (
        <div className="command-palette-overlay" onClick={() => setShowCommandPalette(false)}>
          <div className="command-palette" onClick={e => e.stopPropagation()}>
            <input
              type="text"
              placeholder="Type a command... (Esc to close)"
              autoFocus
              className="command-input"
            />
            <div className="command-list">
              <div className="command-item">Preview All Events</div>
              <div className="command-item">Stop All Sounds</div>
              <div className="command-item">Add Ducking Rule</div>
              <div className="command-item">Export Project</div>
              <div className="command-item">Generate Certification Report</div>
              <div className="command-item">Reset to Defaults</div>
            </div>
          </div>
        </div>
      )}

      {/* Header */}
      <div className="studio-header">
        <h2>Slot Audio Studio</h2>
        <div className="header-actions">
          <input
            type="text"
            placeholder="Search events... (⌘K for commands)"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="search-input"
          />
          <button className="header-btn" onClick={() => setShowCommandPalette(true)}>
            ⌘K
          </button>
        </div>
      </div>

      {/* Game State Tabs */}
      <div className="state-tabs">
        {(Object.entries(GAME_STATE_CONFIG) as [GameState, typeof stateConfig][]).map(([state, config]) => (
          <button
            key={state}
            className={`state-tab ${activeState === state ? 'active' : ''}`}
            onClick={() => handleStateChange(state)}
            style={{
              borderBottomColor: activeState === state ? config.color : 'transparent',
            }}
          >
            <span className="state-icon">{config.icon}</span>
            <span className="state-label">{config.label}</span>
          </button>
        ))}
      </div>

      {/* Main Content */}
      <div className="studio-content">
        {activeState === 'settings' ? (
          <SettingsPanel />
        ) : (
          <>
            {/* Events Section */}
            <div className="section events-section">
              <div className="section-header" style={{ borderLeftColor: stateConfig.color }}>
                <span className="section-icon">🎰</span>
                <span className="section-title">{stateConfig.label} Audio Events</span>
                <span className="section-count">{filteredEvents.length} events</span>
              </div>

              <div className="events-list">
                {Object.entries(groupedEvents).map(([category, categoryEvents]) => (
                  <div key={category} className="event-category-group">
                    <div
                      className="category-header"
                      style={{ color: CATEGORY_CONFIG[category]?.color }}
                    >
                      {CATEGORY_CONFIG[category]?.label} ({categoryEvents.length})
                    </div>
                    {categoryEvents.map(event => (
                      <EventRow
                        key={event.id}
                        event={event}
                        onPreview={() => handleEventPreview(event.id)}
                        onEdit={() => {}}
                        onToggle={() => handleEventToggle(event.id)}
                        onVolumeChange={(v) => handleEventVolumeChange(event.id, v)}
                      />
                    ))}
                  </div>
                ))}
              </div>
            </div>

            {/* Music Layers Section */}
            {activeState === 'base' && (
              <div className="section music-section">
                <div className="section-header" style={{ borderLeftColor: '#3b82f6' }}>
                  <span className="section-icon">🎵</span>
                  <span className="section-title">Music Layers</span>
                </div>
                <MusicLayerTimeline layers={musicLayers} />
                <div className="music-layers-list">
                  {musicLayers.map(layer => (
                    <div key={layer.id} className="music-layer-row">
                      <span className="layer-name">{layer.name}</span>
                      <input
                        type="range"
                        min={0}
                        max={1}
                        step={0.01}
                        defaultValue={layer.volume}
                      />
                      <span className="layer-volume">{Math.round(layer.volume * 100)}%</span>
                      <span className="layer-crossfade">↔ {layer.crossfadeMs}ms</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Ducking Rules Section */}
            <div className="section ducking-section">
              <div className="section-header" style={{ borderLeftColor: '#ef4444' }}>
                <span className="section-icon">🔊</span>
                <span className="section-title">Ducking Rules</span>
                <button className="add-btn">+ Add Rule</button>
              </div>
              <div className="ducking-list">
                {duckingRules.map(rule => (
                  <DuckingRuleRow key={rule.id} rule={rule} />
                ))}
              </div>
            </div>
          </>
        )}
      </div>

      {/* Footer Status */}
      <div className="studio-footer">
        <span className="status-item">
          <span className="status-dot active" />
          Audio Engine: Active
        </span>
        <span className="status-item">
          Memory: 45MB / 100MB
        </span>
        <span className="status-item">
          Voices: 8 / 32
        </span>
        <span className="status-item">
          CPU: 12%
        </span>
      </div>
    </div>
  );
};

export default memo(SlotAudioStudio);

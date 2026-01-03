/**
 * ReelForge Channel Strip
 *
 * Cubase-style channel strip for the right zone in DAW mode.
 * Shows selected track/bus parameters:
 * - ProFader with GPU-accelerated metering
 * - Pan control
 * - Inserts (8 slots)
 * - Sends (8 slots)
 * - EQ curve preview
 * - Output routing
 *
 * @module layout/ChannelStrip
 */

import { memo, useCallback } from 'react';
import { ProFader } from '../components/ProFader';
import './ChannelStrip.css';

// ============ Types ============

export interface InsertSlot {
  id: string;
  pluginName: string | null;
  bypassed: boolean;
}

export interface SendSlot {
  id: string;
  destination: string | null;
  level: number; // -inf to +6 dB
  preFader: boolean;
  bypassed: boolean;
}

export interface EQBand {
  frequency: number;
  gain: number;
  q: number;
  type: 'lowshelf' | 'highshelf' | 'peak' | 'lowpass' | 'highpass';
  enabled: boolean;
}

export interface ChannelStripData {
  id: string;
  name: string;
  type: 'audio' | 'instrument' | 'bus' | 'fx' | 'master';
  color?: string;
  // Fader/Pan
  volume: number; // -inf to +12 dB
  pan: number; // -100 to +100
  mute: boolean;
  solo: boolean;
  // Meter levels (0-1 normalized)
  meterL: number;
  meterR: number;
  peakL: number;
  peakR: number;
  // Inserts & Sends
  inserts: InsertSlot[];
  sends: SendSlot[];
  // EQ
  eqEnabled: boolean;
  eqBands: EQBand[];
  // Routing
  input: string;
  output: string;
  // LUFS metering (master channel only)
  lufs?: {
    momentary: number;  // LUFS momentary (400ms)
    shortTerm: number;  // LUFS short-term (3s)
    integrated: number; // LUFS integrated (program)
    truePeak: number;   // True peak dBTP
    range?: number;     // Loudness range LU
  };
}

export interface ChannelStripProps {
  /** Selected channel data */
  channel: ChannelStripData | null;
  /** Collapsed state */
  collapsed?: boolean;
  /** Toggle collapse */
  onToggleCollapse?: () => void;
  /** Volume change */
  onVolumeChange?: (channelId: string, volume: number) => void;
  /** Pan change */
  onPanChange?: (channelId: string, pan: number) => void;
  /** Mute toggle */
  onMuteToggle?: (channelId: string) => void;
  /** Solo toggle */
  onSoloToggle?: (channelId: string) => void;
  /** Insert click (open plugin browser) */
  onInsertClick?: (channelId: string, slotIndex: number) => void;
  /** Insert remove (remove plugin from slot) */
  onInsertRemove?: (channelId: string, slotIndex: number) => void;
  /** Insert bypass toggle */
  onInsertBypassToggle?: (channelId: string, slotIndex: number) => void;
  /** Send level change */
  onSendLevelChange?: (channelId: string, sendIndex: number, level: number) => void;
  /** EQ toggle */
  onEQToggle?: (channelId: string) => void;
  /** Output routing click */
  onOutputClick?: (channelId: string) => void;
}

// ============ Helper Components ============

interface VerticalFaderProps {
  value: number;
  min: number;
  max: number;
  meterL: number;
  meterR: number;
  peakL: number;
  peakR: number;
  gainReduction?: number;
  onChange?: (value: number) => void;
  disabled?: boolean;
  /** Use ProFader (Canvas-based, professional) */
  useProFader?: boolean;
  /** Fader style for ProFader */
  faderStyle?: 'cubase' | 'protools' | 'logic' | 'ableton';
  /** Channel label */
  label?: string;
}

const VerticalFader = memo(function VerticalFader({
  value,
  min,
  max,
  meterL,
  meterR,
  peakL,
  peakR,
  gainReduction = 0,
  onChange,
  disabled,
  useProFader = true,
  faderStyle = 'cubase',
  label,
}: VerticalFaderProps) {
  // ProFader - GPU-accelerated professional fader
  if (useProFader) {
    return (
      <div className="rf-channel-fader rf-channel-fader--pro">
        <ProFader
          value={value}
          min={min}
          max={max}
          meterL={meterL}
          meterR={meterR}
          peakL={peakL}
          peakR={peakR}
          gainReduction={gainReduction}
          width={60}
          height={200}
          onChange={onChange}
          disabled={disabled}
          showScale={true}
          style={faderStyle}
          label={label}
          stereo={true}
        />
      </div>
    );
  }

  // Legacy fallback - HTML/CSS fader
  const percentage = ((value - min) / (max - min)) * 100;
  const faderPos = 100 - percentage;

  const formatDb = (db: number) => {
    if (db <= -60) return '-∞';
    return db >= 0 ? `+${db.toFixed(1)}` : db.toFixed(1);
  };

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      if (onChange && !disabled) {
        onChange(parseFloat(e.target.value));
      }
    },
    [onChange, disabled]
  );

  const handleDoubleClick = useCallback(() => {
    if (onChange && !disabled) {
      onChange(0);
    }
  }, [onChange, disabled]);

  const isClippingL = peakL >= 1.0;
  const isClippingR = peakR >= 1.0;

  return (
    <div className="rf-channel-fader">
      <div className="rf-channel-meter">
        <div className="rf-channel-meter__track">
          <div className={`rf-channel-meter__clip ${isClippingL ? 'active' : ''}`} />
          <div
            className="rf-channel-meter__fill rf-channel-meter__fill--left"
            style={{
              transform: `scaleY(${meterL})`,
              height: '100%'
            }}
          />
          <div
            className="rf-channel-meter__peak rf-channel-meter__peak--left"
            style={{ bottom: `${peakL * 100}%` }}
          />
        </div>
        <div className="rf-channel-meter__track">
          <div className={`rf-channel-meter__clip ${isClippingR ? 'active' : ''}`} />
          <div
            className="rf-channel-meter__fill rf-channel-meter__fill--right"
            style={{
              transform: `scaleY(${meterR})`,
              height: '100%'
            }}
          />
          <div
            className="rf-channel-meter__peak rf-channel-meter__peak--right"
            style={{ bottom: `${peakR * 100}%` }}
          />
        </div>
      </div>

      <div className="rf-channel-fader__track" onDoubleClick={handleDoubleClick}>
        <div
          className="rf-channel-fader__thumb"
          style={{ top: `${faderPos}%` }}
        />
        <input
          type="range"
          min={min}
          max={max}
          step={0.1}
          value={value}
          onChange={handleChange}
          disabled={disabled}
          className="rf-channel-fader__input"
          style={{
            writingMode: 'vertical-lr',
            direction: 'rtl',
          }}
        />
        <div className="rf-channel-fader__scale">
          <span data-db="+12">+12</span>
          <span data-db="+6">+6</span>
          <span data-db="0">0</span>
          <span data-db="-6">-6</span>
          <span data-db="-12">-12</span>
          <span data-db="-24">-24</span>
          <span data-db="-inf">-∞</span>
        </div>
      </div>

      <div className="rf-channel-fader__value">{formatDb(value)} dB</div>
    </div>
  );
});

interface PanKnobProps {
  value: number; // -100 to +100
  onChange?: (value: number) => void;
  disabled?: boolean;
}

const PanKnob = memo(function PanKnob({ value, onChange, disabled }: PanKnobProps) {
  // Map -100..+100 to rotation -135..+135 degrees
  const rotation = (value / 100) * 135;

  const formatPan = (v: number) => {
    if (v === 0) return 'C';
    return v < 0 ? `L${Math.abs(v)}` : `R${v}`;
  };

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      if (onChange && !disabled) {
        onChange(parseInt(e.target.value, 10));
      }
    },
    [onChange, disabled]
  );

  const handleDoubleClick = useCallback(() => {
    if (onChange && !disabled) {
      onChange(0); // Reset to center
    }
  }, [onChange, disabled]);

  return (
    <div className="rf-channel-pan">
      <div
        className="rf-channel-pan__knob"
        onDoubleClick={handleDoubleClick}
        title="Double-click to center"
      >
        <div
          className="rf-channel-pan__indicator"
          style={{ transform: `rotate(${rotation}deg)` }}
        />
        <input
          type="range"
          min={-100}
          max={100}
          step={1}
          value={value}
          onChange={handleChange}
          disabled={disabled}
          className="rf-channel-pan__input"
        />
      </div>
      <span className="rf-channel-pan__value">{formatPan(value)}</span>
    </div>
  );
});

interface InsertRackProps {
  inserts: InsertSlot[];
  onInsertClick?: (index: number) => void;
  onInsertRemove?: (index: number) => void;
  onInsertBypassToggle?: (index: number) => void;
}

const InsertRack = memo(function InsertRack({
  inserts,
  onInsertClick,
  onInsertRemove,
  onInsertBypassToggle,
}: InsertRackProps) {
  const handleContextMenu = useCallback((e: React.MouseEvent, index: number, hasPlugin: boolean) => {
    e.preventDefault();
    if (!hasPlugin) return;

    // Create context menu
    const menu = document.createElement('div');
    menu.className = 'rf-context-menu';
    menu.style.cssText = `
      position: fixed;
      left: ${e.clientX}px;
      top: ${e.clientY}px;
      z-index: 9999;
      background: var(--rf-bg-2, #1e1e26);
      border: 1px solid var(--rf-border, #333);
      border-radius: 6px;
      padding: 4px 0;
      min-width: 140px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.4);
    `;

    const createItem = (label: string, onClick: () => void, danger = false) => {
      const item = document.createElement('button');
      item.className = 'rf-context-menu__item';
      item.textContent = label;
      item.style.cssText = `
        display: block;
        width: 100%;
        padding: 8px 16px;
        text-align: left;
        background: transparent;
        border: none;
        color: ${danger ? '#ff6b6b' : 'var(--rf-text-primary, #e8e8f0)'};
        font-size: 12px;
        cursor: pointer;
      `;
      item.onmouseenter = () => item.style.background = 'var(--rf-bg-3, #2a2a38)';
      item.onmouseleave = () => item.style.background = 'transparent';
      item.onclick = () => {
        onClick();
        menu.remove();
      };
      return item;
    };

    // Bypass toggle
    const insert = inserts[index];
    menu.appendChild(createItem(
      insert.bypassed ? 'Enable' : 'Bypass',
      () => onInsertBypassToggle?.(index)
    ));

    // Separator
    const sep = document.createElement('div');
    sep.style.cssText = 'height: 1px; background: var(--rf-border, #333); margin: 4px 8px;';
    menu.appendChild(sep);

    // Remove
    menu.appendChild(createItem('Remove', () => onInsertRemove?.(index), true));

    document.body.appendChild(menu);

    // Close on click outside
    const closeMenu = (ev: MouseEvent) => {
      if (!menu.contains(ev.target as Node)) {
        menu.remove();
        document.removeEventListener('click', closeMenu);
      }
    };
    setTimeout(() => document.addEventListener('click', closeMenu), 0);
  }, [inserts, onInsertRemove, onInsertBypassToggle]);

  return (
    <div className="rf-channel-section">
      <div className="rf-channel-section__header">Inserts</div>
      <div className="rf-channel-inserts">
        {inserts.map((insert, i) => (
          <button
            key={insert.id}
            className={`rf-channel-insert ${insert.pluginName ? 'rf-channel-insert--active' : ''} ${insert.bypassed ? 'rf-channel-insert--bypassed' : ''}`}
            onClick={() => onInsertClick?.(i)}
            onContextMenu={(e) => handleContextMenu(e, i, !!insert.pluginName)}
            title={insert.pluginName ? `${insert.pluginName} (right-click for options)` : `Insert ${i + 1} (empty)`}
          >
            <span className="rf-channel-insert__num">{i + 1}</span>
            <span className="rf-channel-insert__name">
              {insert.pluginName || '—'}
            </span>
            {insert.bypassed && insert.pluginName && (
              <span className="rf-channel-insert__bypass-badge">OFF</span>
            )}
          </button>
        ))}
      </div>
    </div>
  );
});

interface SendRackProps {
  sends: SendSlot[];
  onSendLevelChange?: (index: number, level: number) => void;
}

const SendRack = memo(function SendRack({ sends, onSendLevelChange }: SendRackProps) {
  return (
    <div className="rf-channel-section">
      <div className="rf-channel-section__header">Sends</div>
      <div className="rf-channel-sends">
        {sends.slice(0, 8).map((send, i) => (
          <div
            key={send.id}
            className={`rf-channel-send ${send.destination ? 'rf-channel-send--active' : ''} ${send.bypassed ? 'rf-channel-send--bypassed' : ''}`}
          >
            <span className="rf-channel-send__num">{i + 1}</span>
            <span className="rf-channel-send__dest">
              {send.destination || '—'}
            </span>
            {send.destination && (
              <input
                type="range"
                min={-60}
                max={6}
                step={0.5}
                value={send.level}
                onChange={(e) => onSendLevelChange?.(i, parseFloat(e.target.value))}
                className="rf-channel-send__level"
                title={`${send.level.toFixed(1)} dB`}
              />
            )}
            {send.preFader && <span className="rf-channel-send__pre">PRE</span>}
          </div>
        ))}
      </div>
    </div>
  );
});

interface EQPreviewProps {
  bands: EQBand[];
  enabled: boolean;
  onToggle?: () => void;
}

// ============ LUFS Meter Component (Master only) ============

interface LUFSMeterDisplayProps {
  momentary: number;  // Current LUFS
  shortTerm: number;  // Short-term LUFS
  integrated: number; // Integrated LUFS
  truePeak: number;   // True peak dBTP
  target?: number;    // Target LUFS (default: -14)
}

const LUFSMeterDisplay = memo(function LUFSMeterDisplay({
  momentary,
  shortTerm,
  integrated,
  truePeak,
  target = -14,
}: LUFSMeterDisplayProps) {
  // Map LUFS to meter position (-40 to 0 range)
  const lufsToPercent = (lufs: number) => {
    const clamped = Math.max(-40, Math.min(0, lufs));
    return ((clamped + 40) / 40) * 100;
  };

  // Format LUFS value
  const formatLufs = (lufs: number) => {
    if (lufs <= -40) return '-∞';
    return lufs.toFixed(1);
  };

  // Warning states
  const isTooLoud = integrated > target + 1;
  const isTooQuiet = integrated < target - 3;
  const isClipping = truePeak > -0.3;

  return (
    <div className="rf-lufs-meter">
      <div className="rf-lufs-meter__header">
        <span>Loudness</span>
        <span className="rf-lufs-meter__target" title="EBU R128 Target">
          {target} LUFS
        </span>
      </div>

      {/* Visual meter */}
      <div className="rf-lufs-meter__bar">
        {/* Target zone */}
        <div
          className="rf-lufs-meter__zone"
          style={{
            left: `${lufsToPercent(target - 1)}%`,
            width: `${(2 / 40) * 100}%`,
          }}
        />
        {/* Momentary indicator */}
        <div
          className="rf-lufs-meter__indicator rf-lufs-meter__indicator--momentary"
          style={{ left: `${lufsToPercent(momentary)}%` }}
        />
        {/* Short-term indicator */}
        <div
          className="rf-lufs-meter__indicator rf-lufs-meter__indicator--short"
          style={{ left: `${lufsToPercent(shortTerm)}%` }}
        />
        {/* Integrated (main) */}
        <div
          className={`rf-lufs-meter__indicator rf-lufs-meter__indicator--integrated ${
            isTooLoud ? 'warning-loud' : isTooQuiet ? 'warning-quiet' : ''
          }`}
          style={{ left: `${lufsToPercent(integrated)}%` }}
        />
      </div>

      {/* Numeric display */}
      <div className="rf-lufs-meter__values">
        <div className="rf-lufs-meter__value">
          <span className="rf-lufs-meter__label">M</span>
          <span>{formatLufs(momentary)}</span>
        </div>
        <div className="rf-lufs-meter__value">
          <span className="rf-lufs-meter__label">S</span>
          <span>{formatLufs(shortTerm)}</span>
        </div>
        <div className={`rf-lufs-meter__value rf-lufs-meter__value--main ${
          isTooLoud ? 'warning-loud' : isTooQuiet ? 'warning-quiet' : ''
        }`}>
          <span className="rf-lufs-meter__label">I</span>
          <span>{formatLufs(integrated)}</span>
        </div>
        <div className={`rf-lufs-meter__value ${isClipping ? 'warning-clip' : ''}`}>
          <span className="rf-lufs-meter__label">TP</span>
          <span>{truePeak > -40 ? truePeak.toFixed(1) : '-∞'}</span>
        </div>
      </div>
    </div>
  );
});

const EQPreview = memo(function EQPreview({ bands, enabled, onToggle }: EQPreviewProps) {
  // Generate SVG path for EQ curve (simplified)
  const generatePath = () => {
    if (!enabled || bands.length === 0) return 'M 0 50 L 200 50';

    // Very simplified EQ curve
    let path = 'M 0 50';
    const width = 200;
    const height = 100;
    const midY = height / 2;

    for (let x = 0; x <= width; x += 4) {
      const freq = 20 * Math.pow(1000, x / width); // 20Hz to 20kHz log scale
      let y = midY;

      for (const band of bands) {
        if (!band.enabled) continue;
        // Simplified gain contribution
        const dist = Math.abs(Math.log10(freq) - Math.log10(band.frequency));
        const influence = Math.exp(-dist * band.q * 0.5);
        y -= band.gain * influence * 2;
      }

      path += ` L ${x} ${Math.max(5, Math.min(95, y))}`;
    }

    return path;
  };

  return (
    <div className="rf-channel-section">
      <div className="rf-channel-section__header">
        <span>EQ</span>
        <button
          className={`rf-channel-eq-toggle ${enabled ? 'rf-channel-eq-toggle--active' : ''}`}
          onClick={onToggle}
          title={enabled ? 'Bypass EQ' : 'Enable EQ'}
        >
          {enabled ? 'ON' : 'OFF'}
        </button>
      </div>
      <div className="rf-channel-eq">
        <svg viewBox="0 0 200 100" className="rf-channel-eq__curve">
          {/* Grid */}
          <line x1="0" y1="50" x2="200" y2="50" stroke="var(--rf-border)" strokeWidth="1" />
          <line x1="50" y1="0" x2="50" y2="100" stroke="var(--rf-border)" strokeWidth="0.5" strokeDasharray="2,2" />
          <line x1="100" y1="0" x2="100" y2="100" stroke="var(--rf-border)" strokeWidth="0.5" strokeDasharray="2,2" />
          <line x1="150" y1="0" x2="150" y2="100" stroke="var(--rf-border)" strokeWidth="0.5" strokeDasharray="2,2" />
          {/* Curve */}
          <path
            d={generatePath()}
            fill="none"
            stroke={enabled ? 'var(--rf-accent)' : 'var(--rf-text-muted)'}
            strokeWidth="2"
          />
        </svg>
      </div>
    </div>
  );
});

// ============ Channel Strip Component ============

export const ChannelStrip = memo(function ChannelStrip({
  channel,
  collapsed = false,
  onToggleCollapse,
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onInsertClick,
  onInsertRemove,
  onInsertBypassToggle,
  onSendLevelChange,
  onEQToggle,
  onOutputClick,
}: ChannelStripProps) {
  if (collapsed) {
    return null;
  }

  const TYPE_ICONS: Record<ChannelStripData['type'], string> = {
    audio: '🎵',
    instrument: '🎹',
    bus: '🔈',
    fx: '🎛️',
    master: '🔊',
  };

  return (
    <div className="rf-right-zone rf-channel-strip rf-scrollbar">
      {/* Header */}
      <div className="rf-zone-header">
        <span className="rf-zone-header__title">Channel</span>
        <div className="rf-zone-header__actions">
          {onToggleCollapse && (
            <button
              className="rf-zone-header__btn"
              onClick={onToggleCollapse}
              title="Collapse Zone"
            >
              ▶
            </button>
          )}
        </div>
      </div>

      {/* Channel Content */}
      <div className="rf-channel-content rf-scrollbar">
        {!channel ? (
          <div className="rf-inspector__empty">
            <span className="rf-inspector__empty-icon">🎚️</span>
            <span>Select a track to view channel strip</span>
          </div>
        ) : (
          <>
            {/* Channel Name */}
            <div
              className="rf-channel-header"
              style={{
                borderLeftColor: channel.color || 'var(--rf-accent)',
              }}
            >
              <span className="rf-channel-header__icon">{TYPE_ICONS[channel.type]}</span>
              <span className="rf-channel-header__name">{channel.name}</span>
            </div>

            {/* Mute/Solo */}
            <div className="rf-channel-controls">
              <button
                className={`rf-channel-btn rf-channel-btn--mute ${channel.mute ? 'active' : ''}`}
                onClick={() => onMuteToggle?.(channel.id)}
                title="Mute (M)"
              >
                M
              </button>
              <button
                className={`rf-channel-btn rf-channel-btn--solo ${channel.solo ? 'active' : ''}`}
                onClick={() => onSoloToggle?.(channel.id)}
                title="Solo (S)"
              >
                S
              </button>
            </div>

            {/* Pan */}
            <div className="rf-channel-section rf-channel-section--pan">
              <div className="rf-channel-section__header">Pan</div>
              <PanKnob
                value={channel.pan}
                onChange={(v) => onPanChange?.(channel.id, v)}
              />
            </div>

            {/* Fader */}
            <VerticalFader
              value={channel.volume}
              min={-60}
              max={12}
              meterL={channel.meterL}
              meterR={channel.meterR}
              peakL={channel.peakL}
              peakR={channel.peakR}
              onChange={(v) => onVolumeChange?.(channel.id, v)}
            />

            {/* LUFS Meter - Master channel only */}
            {channel.type === 'master' && channel.lufs && (
              <LUFSMeterDisplay
                momentary={channel.lufs.momentary}
                shortTerm={channel.lufs.shortTerm}
                integrated={channel.lufs.integrated}
                truePeak={channel.lufs.truePeak}
                target={-14}
              />
            )}

            {/* Inserts */}
            <InsertRack
              inserts={channel.inserts}
              onInsertClick={(i) => onInsertClick?.(channel.id, i)}
              onInsertRemove={(i) => onInsertRemove?.(channel.id, i)}
              onInsertBypassToggle={(i) => onInsertBypassToggle?.(channel.id, i)}
            />

            {/* Sends */}
            <SendRack
              sends={channel.sends}
              onSendLevelChange={(i, level) => onSendLevelChange?.(channel.id, i, level)}
            />

            {/* EQ Preview */}
            <EQPreview
              bands={channel.eqBands}
              enabled={channel.eqEnabled}
              onToggle={() => onEQToggle?.(channel.id)}
            />

            {/* Output Routing */}
            <div className="rf-channel-section">
              <div className="rf-channel-section__header">Output</div>
              <button
                className="rf-channel-output"
                onClick={() => onOutputClick?.(channel.id)}
              >
                <span className="rf-channel-output__icon">🔈</span>
                <span className="rf-channel-output__name">{channel.output}</span>
                <span className="rf-channel-output__arrow">▼</span>
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
});

// ============ Default empty channel data ============

export function createEmptyInserts(count: number = 8): InsertSlot[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `insert-${i}`,
    pluginName: null,
    bypassed: false,
  }));
}

export function createEmptySends(count: number = 8): SendSlot[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `send-${i}`,
    destination: null,
    level: -Infinity,
    preFader: false,
    bypassed: false,
  }));
}

export function createDefaultChannelStrip(
  id: string,
  name: string,
  type: ChannelStripData['type'] = 'audio'
): ChannelStripData {
  return {
    id,
    name,
    type,
    volume: 0,
    pan: 0,
    mute: false,
    solo: false,
    meterL: 0,
    meterR: 0,
    peakL: 0,
    peakR: 0,
    inserts: createEmptyInserts(),
    sends: createEmptySends(),
    eqEnabled: false,
    eqBands: [],
    input: 'No Input',
    output: 'Stereo Out',
  };
}

export default ChannelStrip;

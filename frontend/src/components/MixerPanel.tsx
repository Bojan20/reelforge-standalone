/**
 * Mixer Panel
 *
 * Professional mixing console with:
 * - Bus channel strips
 * - Faders with dB scale
 * - Peak/RMS meters
 * - Mute/Solo/Arm
 * - Pan control
 * - Send levels
 *
 * @module components/MixerPanel
 */

import { memo, useState, useCallback, useRef } from 'react';
import { useMeter, formatDb, type MeterReading } from '../core/audioMetering';
import './MixerPanel.css';

// ============ TYPES ============

export interface BusChannel {
  id: string;
  name: string;
  color?: string;
  volume: number;       // 0-1 linear
  pan: number;          // -1 to 1
  muted: boolean;
  solo: boolean;
  armed?: boolean;
  sends?: Array<{
    busId: string;
    level: number;
  }>;
}

export interface MixerPanelProps {
  buses: BusChannel[];
  masterBus?: BusChannel;
  onVolumeChange?: (busId: string, volume: number) => void;
  onPanChange?: (busId: string, pan: number) => void;
  onMuteToggle?: (busId: string) => void;
  onSoloToggle?: (busId: string) => void;
  onArmToggle?: (busId: string) => void;
  onSendChange?: (busId: string, sendBusId: string, level: number) => void;
  orientation?: 'horizontal' | 'vertical';
  compact?: boolean;
}

// ============ CHANNEL STRIP ============

interface ChannelStripProps {
  channel: BusChannel;
  isMaster?: boolean;
  onVolumeChange?: (volume: number) => void;
  onPanChange?: (pan: number) => void;
  onMuteToggle?: () => void;
  onSoloToggle?: () => void;
  onArmToggle?: () => void;
  compact?: boolean;
}

const ChannelStrip = memo(function ChannelStrip({
  channel,
  isMaster = false,
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onArmToggle,
  compact = false,
}: ChannelStripProps) {
  const { reading } = useMeter(channel.id);
  const faderRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);

  // Convert linear to dB for display
  const volumeDb = channel.volume > 0 ? 20 * Math.log10(channel.volume) : -Infinity;
  const volumeDbStr = formatDb(volumeDb);

  // Fader drag handler
  const handleFaderDrag = useCallback((e: MouseEvent | React.MouseEvent) => {
    if (!faderRef.current || !onVolumeChange) return;

    const rect = faderRef.current.getBoundingClientRect();
    const y = Math.max(0, Math.min(1, 1 - (e.clientY - rect.top) / rect.height));

    // Convert to curved response (more resolution near 0dB)
    const volume = Math.pow(y, 2);
    onVolumeChange(volume);
  }, [onVolumeChange]);

  // Mouse handlers
  const handleMouseDown = (e: React.MouseEvent) => {
    e.preventDefault();
    setIsDragging(true);
    handleFaderDrag(e);

    const handleMouseMove = (e: MouseEvent) => handleFaderDrag(e);
    const handleMouseUp = () => {
      setIsDragging(false);
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  };

  // Double click to reset
  const handleDoubleClick = () => {
    onVolumeChange?.(1); // 0dB
  };

  // Pan knob
  const handlePanChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    onPanChange?.(parseFloat(e.target.value));
  };

  return (
    <div
      className={`channel-strip ${isMaster ? 'channel-strip--master' : ''} ${compact ? 'channel-strip--compact' : ''}`}
      style={{ '--channel-color': channel.color || '#6366f1' } as React.CSSProperties}
    >
      {/* Channel Name */}
      <div className="channel-strip__header">
        <span className="channel-strip__name">{channel.name}</span>
        {channel.color && (
          <div
            className="channel-strip__color"
            style={{ background: channel.color }}
          />
        )}
      </div>

      {/* Meter + Fader */}
      <div className="channel-strip__fader-section">
        {/* Meter */}
        <div className="channel-strip__meter">
          <ChannelMeter reading={reading} />
        </div>

        {/* Fader Track */}
        <div
          className={`channel-strip__fader ${isDragging ? 'dragging' : ''}`}
          ref={faderRef}
          onMouseDown={handleMouseDown}
          onDoubleClick={handleDoubleClick}
        >
          {/* dB Scale */}
          <div className="fader-scale">
            {[6, 0, -6, -12, -24, -48].map((db) => (
              <div
                key={db}
                className="fader-scale__mark"
                style={{ bottom: `${dbToPercent(db)}%` }}
              >
                <span>{db > 0 ? `+${db}` : db}</span>
              </div>
            ))}
          </div>

          {/* Fader Track Fill */}
          <div
            className="fader-track__fill"
            style={{ height: `${Math.sqrt(channel.volume) * 100}%` }}
          />

          {/* Fader Knob */}
          <div
            className="fader-knob"
            style={{ bottom: `${Math.sqrt(channel.volume) * 100}%` }}
          >
            <div className="fader-knob__grip" />
          </div>
        </div>
      </div>

      {/* Volume Display */}
      <div className="channel-strip__volume-display">
        {volumeDbStr} dB
      </div>

      {/* Pan Knob */}
      {!isMaster && (
        <div className="channel-strip__pan">
          <input
            type="range"
            min="-1"
            max="1"
            step="0.01"
            value={channel.pan}
            onChange={handlePanChange}
            className="pan-knob"
            title={`Pan: ${channel.pan > 0 ? `R${Math.round(channel.pan * 100)}` : channel.pan < 0 ? `L${Math.round(-channel.pan * 100)}` : 'C'}`}
          />
          <span className="pan-label">
            {channel.pan > 0.05 ? `R${Math.round(channel.pan * 100)}` :
             channel.pan < -0.05 ? `L${Math.round(-channel.pan * 100)}` : 'C'}
          </span>
        </div>
      )}

      {/* Control Buttons */}
      <div className="channel-strip__controls">
        <button
          className={`channel-btn channel-btn--mute ${channel.muted ? 'active' : ''}`}
          onClick={onMuteToggle}
          title="Mute"
        >
          M
        </button>
        <button
          className={`channel-btn channel-btn--solo ${channel.solo ? 'active' : ''}`}
          onClick={onSoloToggle}
          title="Solo"
        >
          S
        </button>
        {!isMaster && onArmToggle && (
          <button
            className={`channel-btn channel-btn--arm ${channel.armed ? 'active' : ''}`}
            onClick={onArmToggle}
            title="Arm for Recording"
          >
            R
          </button>
        )}
      </div>
    </div>
  );
});

// ============ CHANNEL METER ============

interface ChannelMeterProps {
  reading: MeterReading | null;
}

const ChannelMeter = memo(function ChannelMeter({ reading }: ChannelMeterProps) {
  if (!reading) {
    return (
      <div className="channel-meter channel-meter--empty">
        <div className="channel-meter__bar" />
        <div className="channel-meter__bar" />
      </div>
    );
  }

  const leftPct = dbToPercent(reading.left.peak);
  const rightPct = dbToPercent(reading.right.peak);

  return (
    <div className={`channel-meter ${reading.isClipping ? 'channel-meter--clipping' : ''}`}>
      {/* Left */}
      <div className="channel-meter__bar">
        <div
          className="channel-meter__fill"
          style={{
            height: `${leftPct}%`,
            background: getMeterGradientVertical(reading.left.peak),
          }}
        />
        {reading.isClipping && <div className="channel-meter__clip" />}
      </div>

      {/* Right */}
      <div className="channel-meter__bar">
        <div
          className="channel-meter__fill"
          style={{
            height: `${rightPct}%`,
            background: getMeterGradientVertical(reading.right.peak),
          }}
        />
        {reading.isClipping && <div className="channel-meter__clip" />}
      </div>
    </div>
  );
});

// ============ MIXER PANEL ============

export const MixerPanel = memo(function MixerPanel({
  buses,
  masterBus,
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onArmToggle,
  orientation = 'horizontal',
  compact = false,
}: MixerPanelProps) {
  return (
    <div className={`mixer-panel mixer-panel--${orientation} ${compact ? 'mixer-panel--compact' : ''}`}>
      {/* Bus Channels */}
      <div className="mixer-panel__channels">
        {buses.map((bus) => (
          <ChannelStrip
            key={bus.id}
            channel={bus}
            onVolumeChange={onVolumeChange ? (v) => onVolumeChange(bus.id, v) : undefined}
            onPanChange={onPanChange ? (p) => onPanChange(bus.id, p) : undefined}
            onMuteToggle={onMuteToggle ? () => onMuteToggle(bus.id) : undefined}
            onSoloToggle={onSoloToggle ? () => onSoloToggle(bus.id) : undefined}
            onArmToggle={onArmToggle ? () => onArmToggle(bus.id) : undefined}
            compact={compact}
          />
        ))}
      </div>

      {/* Master Bus */}
      {masterBus && (
        <>
          <div className="mixer-panel__divider" />
          <ChannelStrip
            channel={masterBus}
            isMaster
            onVolumeChange={onVolumeChange ? (v) => onVolumeChange(masterBus.id, v) : undefined}
            onMuteToggle={onMuteToggle ? () => onMuteToggle(masterBus.id) : undefined}
            onSoloToggle={onSoloToggle ? () => onSoloToggle(masterBus.id) : undefined}
            compact={compact}
          />
        </>
      )}
    </div>
  );
});

// ============ HELPERS ============

function dbToPercent(db: number, minDb = -60, maxDb = 6): number {
  if (db <= minDb) return 0;
  if (db >= maxDb) return 100;
  return ((db - minDb) / (maxDb - minDb)) * 100;
}

function getMeterGradientVertical(db: number): string {
  if (db >= 0) {
    return 'linear-gradient(0deg, #22c55e 0%, #eab308 70%, #ef4444 95%)';
  }
  if (db >= -6) {
    return 'linear-gradient(0deg, #22c55e 0%, #22c55e 60%, #eab308 100%)';
  }
  return '#22c55e';
}

export default MixerPanel;

/**
 * ReelForge Mixer Channel
 *
 * Individual channel strip for the mixer with:
 * - Fader (volume)
 * - Pan knob
 * - Level meter
 * - Mute/Solo/Arm buttons
 * - Insert slots
 * - Send controls
 *
 * @module mixer/MixerChannel
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './MixerChannel.css';

// ============ Types ============

export interface Send {
  /** Target bus ID */
  targetId: string;
  /** Target bus name (for display) */
  targetName: string;
  /** Send level (0-1) */
  level: number;
  /** Pre/Post fader */
  preFader: boolean;
  /** Is enabled */
  enabled: boolean;
}

export interface MixerChannelProps {
  /** Channel ID */
  id: string;
  /** Channel name */
  name: string;
  /** Channel color */
  color?: string;
  /** Volume in dB (-inf to +12) */
  volume: number;
  /** Pan (-1 to 1) */
  pan: number;
  /** Is muted */
  muted: boolean;
  /** Is soloed */
  solo: boolean;
  /** Is armed for recording */
  armed: boolean;
  /** Current peak level L (0-1) */
  peakL?: number;
  /** Current peak level R (0-1) */
  peakR?: number;
  /** Number of insert slots */
  insertCount?: number;
  /** Send assignments */
  sends?: Send[];
  /** Available send targets (bus names) */
  sendTargets?: { id: string; name: string }[];
  /** On volume change */
  onVolumeChange: (volume: number) => void;
  /** On pan change */
  onPanChange: (pan: number) => void;
  /** On mute toggle */
  onMuteToggle: () => void;
  /** On solo toggle */
  onSoloToggle: () => void;
  /** On arm toggle */
  onArmToggle: () => void;
  /** On name change */
  onNameChange?: (name: string) => void;
  /** On insert click */
  onInsertClick?: (slot: number) => void;
  /** On send level change */
  onSendLevelChange?: (sendIndex: number, level: number) => void;
  /** On send toggle (enable/disable) */
  onSendToggle?: (sendIndex: number) => void;
  /** On send add */
  onSendAdd?: (targetId: string) => void;
  /** On send remove */
  onSendRemove?: (sendIndex: number) => void;
  /** On send pre/post toggle */
  onSendPrePostToggle?: (sendIndex: number) => void;
  /** Compact mode */
  compact?: boolean;
}

// ============ Constants ============

const FADER_MIN_DB = -60;
const FADER_MAX_DB = 12;
const FADER_UNITY_DB = 0;

// ============ Component ============

export function MixerChannel({
  id: _id,
  name,
  color = '#4a9eff',
  volume,
  pan,
  muted,
  solo,
  armed,
  peakL = 0,
  peakR = 0,
  insertCount = 4,
  sends = [],
  sendTargets = [],
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onArmToggle,
  onNameChange,
  onInsertClick,
  onSendLevelChange,
  onSendToggle,
  onSendAdd,
  onSendRemove,
  onSendPrePostToggle,
  compact = false,
}: MixerChannelProps) {
  const [isEditingName, setIsEditingName] = useState(false);
  const [editedName, setEditedName] = useState(name);
  const [, setIsDraggingFader] = useState(false);
  const [, setIsDraggingPan] = useState(false);
  const faderRef = useRef<HTMLDivElement>(null);
  const panRef = useRef<HTMLDivElement>(null);

  // ============ Volume/Fader ============

  const dbToPercent = (db: number): number => {
    if (db <= FADER_MIN_DB) return 0;
    if (db >= FADER_MAX_DB) return 100;
    return ((db - FADER_MIN_DB) / (FADER_MAX_DB - FADER_MIN_DB)) * 100;
  };

  const percentToDb = (percent: number): number => {
    if (percent <= 0) return -Infinity;
    if (percent >= 100) return FADER_MAX_DB;
    return FADER_MIN_DB + (percent / 100) * (FADER_MAX_DB - FADER_MIN_DB);
  };

  const handleFaderMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsDraggingFader(true);

      const updateFader = (clientY: number) => {
        if (!faderRef.current) return;
        const rect = faderRef.current.getBoundingClientRect();
        const percent = 100 - ((clientY - rect.top) / rect.height) * 100;
        const db = percentToDb(Math.max(0, Math.min(100, percent)));
        onVolumeChange(db);
      };

      updateFader(e.clientY);

      const handleMouseMove = (e: MouseEvent) => updateFader(e.clientY);
      const handleMouseUp = () => {
        setIsDraggingFader(false);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [onVolumeChange]
  );

  const handleFaderDoubleClick = useCallback(() => {
    onVolumeChange(FADER_UNITY_DB);
  }, [onVolumeChange]);

  // ============ Pan ============

  const handlePanMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsDraggingPan(true);

      const updatePan = (clientX: number) => {
        if (!panRef.current) return;
        const rect = panRef.current.getBoundingClientRect();
        const percent = ((clientX - rect.left) / rect.width) * 2 - 1;
        onPanChange(Math.max(-1, Math.min(1, percent)));
      };

      updatePan(e.clientX);

      const handleMouseMove = (e: MouseEvent) => updatePan(e.clientX);
      const handleMouseUp = () => {
        setIsDraggingPan(false);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [onPanChange]
  );

  const handlePanDoubleClick = useCallback(() => {
    onPanChange(0);
  }, [onPanChange]);

  // ============ Name Editing ============

  const handleNameDoubleClick = useCallback(() => {
    if (onNameChange) {
      setIsEditingName(true);
      setEditedName(name);
    }
  }, [name, onNameChange]);

  const handleNameSubmit = useCallback(() => {
    if (editedName.trim() && onNameChange) {
      onNameChange(editedName.trim());
    }
    setIsEditingName(false);
  }, [editedName, onNameChange]);

  const handleNameKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter') {
        handleNameSubmit();
      } else if (e.key === 'Escape') {
        setIsEditingName(false);
        setEditedName(name);
      }
    },
    [handleNameSubmit, name]
  );

  // ============ Render ============

  const faderPercent = dbToPercent(volume);
  const panPercent = ((pan + 1) / 2) * 100;
  const panLabel = pan === 0 ? 'C' : pan < 0 ? `L${Math.abs(Math.round(pan * 100))}` : `R${Math.round(pan * 100)}`;

  return (
    <div
      className={`mixer-channel ${compact ? 'mixer-channel--compact' : ''} ${muted ? 'mixer-channel--muted' : ''} ${solo ? 'mixer-channel--solo' : ''}`}
      style={{ '--channel-color': color } as React.CSSProperties}
    >
      {/* Insert Slots */}
      {!compact && (
        <div className="mixer-channel__inserts">
          {Array.from({ length: insertCount }).map((_, i) => (
            <button
              key={i}
              className="mixer-channel__insert-slot"
              onClick={() => onInsertClick?.(i)}
              title={`Insert ${i + 1}`}
            >
              {i + 1}
            </button>
          ))}
        </div>
      )}

      {/* Sends Section */}
      {!compact && (
        <div className="mixer-channel__sends">
          <div className="mixer-channel__sends-header">
            <span>Sends</span>
            {sendTargets.length > 0 && onSendAdd && (
              <select
                className="mixer-channel__send-add"
                value=""
                onChange={(e) => {
                  if (e.target.value) {
                    onSendAdd(e.target.value);
                  }
                }}
                title="Add send"
              >
                <option value="">+</option>
                {sendTargets
                  .filter(t => !sends.some(s => s.targetId === t.id))
                  .map(t => (
                    <option key={t.id} value={t.id}>{t.name}</option>
                  ))
                }
              </select>
            )}
          </div>
          {sends.map((send, i) => (
            <div
              key={send.targetId}
              className={`mixer-channel__send ${send.enabled ? '' : 'mixer-channel__send--disabled'}`}
            >
              <button
                className="mixer-channel__send-name"
                onClick={() => onSendToggle?.(i)}
                title={send.enabled ? 'Disable send' : 'Enable send'}
              >
                {send.targetName}
              </button>
              <input
                type="range"
                className="mixer-channel__send-level"
                min="0"
                max="100"
                value={send.level * 100}
                onChange={(e) => onSendLevelChange?.(i, parseInt(e.target.value) / 100)}
                title={`Send level: ${Math.round(send.level * 100)}%`}
              />
              <button
                className={`mixer-channel__send-prefader ${send.preFader ? 'active' : ''}`}
                onClick={() => onSendPrePostToggle?.(i)}
                title={send.preFader ? 'Pre-fader' : 'Post-fader'}
              >
                {send.preFader ? 'PRE' : 'POST'}
              </button>
              {onSendRemove && (
                <button
                  className="mixer-channel__send-remove"
                  onClick={() => onSendRemove(i)}
                  title="Remove send"
                >
                  ×
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Pan */}
      <div className="mixer-channel__pan-section">
        <div
          ref={panRef}
          className="mixer-channel__pan"
          onMouseDown={handlePanMouseDown}
          onDoubleClick={handlePanDoubleClick}
          title={`Pan: ${panLabel}`}
        >
          <div className="mixer-channel__pan-track">
            <div
              className="mixer-channel__pan-indicator"
              style={{ left: `${panPercent}%` }}
            />
            <div className="mixer-channel__pan-center" />
          </div>
        </div>
        <span className="mixer-channel__pan-label">{panLabel}</span>
      </div>

      {/* Fader Section */}
      <div className="mixer-channel__fader-section">
        {/* Level Meters */}
        <div className="mixer-channel__meters">
          <LevelMeter level={peakL} />
          <LevelMeter level={peakR} />
        </div>

        {/* Fader */}
        <div
          ref={faderRef}
          className="mixer-channel__fader"
          onMouseDown={handleFaderMouseDown}
          onDoubleClick={handleFaderDoubleClick}
        >
          <div className="mixer-channel__fader-track">
            <div
              className="mixer-channel__fader-fill"
              style={{ height: `${faderPercent}%` }}
            />
            <div
              className="mixer-channel__fader-thumb"
              style={{ bottom: `${faderPercent}%` }}
            />
            {/* Unity marker */}
            <div
              className="mixer-channel__fader-unity"
              style={{ bottom: `${dbToPercent(0)}%` }}
            />
          </div>
        </div>

        {/* dB Display */}
        <div className="mixer-channel__db">
          {volume <= FADER_MIN_DB ? '-∞' : volume.toFixed(1)}
          <span className="mixer-channel__db-unit">dB</span>
        </div>
      </div>

      {/* Buttons */}
      <div className="mixer-channel__buttons">
        <button
          className={`mixer-channel__btn mixer-channel__btn--mute ${muted ? 'active' : ''}`}
          onClick={onMuteToggle}
          title="Mute"
        >
          M
        </button>
        <button
          className={`mixer-channel__btn mixer-channel__btn--solo ${solo ? 'active' : ''}`}
          onClick={onSoloToggle}
          title="Solo"
        >
          S
        </button>
        <button
          className={`mixer-channel__btn mixer-channel__btn--arm ${armed ? 'active' : ''}`}
          onClick={onArmToggle}
          title="Arm for Recording"
        >
          R
        </button>
      </div>

      {/* Name */}
      <div
        className="mixer-channel__name"
        style={{ borderColor: color }}
        onDoubleClick={handleNameDoubleClick}
      >
        {isEditingName ? (
          <input
            type="text"
            value={editedName}
            onChange={(e) => setEditedName(e.target.value)}
            onBlur={handleNameSubmit}
            onKeyDown={handleNameKeyDown}
            autoFocus
          />
        ) : (
          <span title={name}>{name}</span>
        )}
      </div>
    </div>
  );
}

// ============ Level Meter Sub-component ============

interface LevelMeterProps {
  level: number;
  peakHold?: boolean;
}

function LevelMeter({ level, peakHold = true }: LevelMeterProps) {
  const [peak, setPeak] = useState(0);
  const peakTimer = useRef<number | undefined>(undefined);

  useEffect(() => {
    if (level > peak) {
      setPeak(level);
      if (peakTimer.current) {
        clearTimeout(peakTimer.current);
      }
      peakTimer.current = window.setTimeout(() => {
        setPeak(0);
      }, 1500);
    }

    return () => {
      if (peakTimer.current) {
        clearTimeout(peakTimer.current);
      }
    };
  }, [level, peak]);

  const levelPercent = Math.min(100, level * 100);
  const peakPercent = Math.min(100, peak * 100);

  // Color based on level
  const getColor = (percent: number): string => {
    if (percent > 95) return '#ff3333';
    if (percent > 80) return '#ffaa00';
    return '#00ff88';
  };

  return (
    <div className="mixer-channel__meter">
      <div
        className="mixer-channel__meter-fill"
        style={{
          height: `${levelPercent}%`,
          background: `linear-gradient(to top, #00ff88 0%, #00ff88 80%, #ffaa00 90%, #ff3333 100%)`,
        }}
      />
      {peakHold && peak > 0 && (
        <div
          className="mixer-channel__meter-peak"
          style={{
            bottom: `${peakPercent}%`,
            backgroundColor: getColor(peakPercent),
          }}
        />
      )}
    </div>
  );
}

export default MixerChannel;

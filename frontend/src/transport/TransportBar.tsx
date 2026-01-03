/**
 * ReelForge Transport Bar
 *
 * Global transport controls with:
 * - Play/Stop/Record buttons
 * - Time display (bars:beats or timecode)
 * - Tempo/BPM control
 * - Time signature
 * - Loop toggle
 * - Metronome toggle
 *
 * @module transport/TransportBar
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './TransportBar.css';

// ============ Types ============

export type TimeDisplayMode = 'bars' | 'timecode' | 'samples';

export interface TransportBarProps {
  /** Is playing */
  isPlaying: boolean;
  /** Is recording */
  isRecording: boolean;
  /** Current time in seconds */
  currentTime: number;
  /** Total duration in seconds */
  duration?: number;
  /** Tempo in BPM */
  tempo: number;
  /** Time signature [numerator, denominator] */
  timeSignature: [number, number];
  /** Loop enabled */
  loopEnabled: boolean;
  /** Loop start time */
  loopStart: number;
  /** Loop end time */
  loopEnd: number;
  /** Metronome enabled */
  metronomeEnabled: boolean;
  /** Sample rate */
  sampleRate?: number;
  /** On play click */
  onPlay: () => void;
  /** On pause click */
  onPause: () => void;
  /** On stop click */
  onStop: () => void;
  /** On record click */
  onRecord: () => void;
  /** On rewind click */
  onRewind?: () => void;
  /** On forward click */
  onForward?: () => void;
  /** On tempo change */
  onTempoChange: (tempo: number) => void;
  /** On time signature change */
  onTimeSignatureChange?: (signature: [number, number]) => void;
  /** On loop toggle */
  onLoopToggle: () => void;
  /** On metronome toggle */
  onMetronomeToggle: () => void;
  /** On time click (for seeking) */
  onTimeClick?: (time: number) => void;
}

// ============ Time Formatting ============

export function formatTimecode(seconds: number): string {
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  const frames = Math.floor((seconds % 1) * 30); // 30fps

  return `${hrs.toString().padStart(2, '0')}:${mins
    .toString()
    .padStart(2, '0')}:${secs.toString().padStart(2, '0')}:${frames
    .toString()
    .padStart(2, '0')}`;
}

export function formatBarsBeats(
  seconds: number,
  tempo: number,
  timeSignature: [number, number]
): string {
  const beatsPerSecond = tempo / 60;
  const totalBeats = seconds * beatsPerSecond;
  const beatsPerBar = timeSignature[0];

  const bars = Math.floor(totalBeats / beatsPerBar) + 1;
  const beats = Math.floor(totalBeats % beatsPerBar) + 1;
  const ticks = Math.floor((totalBeats % 1) * 960); // 960 PPQN

  return `${bars.toString().padStart(3, '0')}.${beats}.${ticks
    .toString()
    .padStart(3, '0')}`;
}

export function formatSamples(seconds: number, sampleRate: number): string {
  const samples = Math.floor(seconds * sampleRate);
  return samples.toLocaleString();
}

// ============ Component ============

export function TransportBar({
  isPlaying,
  isRecording,
  currentTime,
  duration = 0,
  tempo,
  timeSignature,
  loopEnabled,
  loopStart,
  loopEnd,
  metronomeEnabled,
  sampleRate = 48000,
  onPlay,
  onPause,
  onStop,
  onRecord,
  onRewind,
  onForward,
  onTempoChange,
  onTimeSignatureChange: _onTimeSignatureChange,
  onLoopToggle,
  onMetronomeToggle,
  onTimeClick: _onTimeClick,
}: TransportBarProps) {
  const [timeMode, setTimeMode] = useState<TimeDisplayMode>('bars');
  const [isEditingTempo, setIsEditingTempo] = useState(false);
  const [editedTempo, setEditedTempo] = useState(tempo.toString());
  const tempoInputRef = useRef<HTMLInputElement>(null);

  // Format time based on mode
  const formattedTime =
    timeMode === 'bars'
      ? formatBarsBeats(currentTime, tempo, timeSignature)
      : timeMode === 'timecode'
      ? formatTimecode(currentTime)
      : formatSamples(currentTime, sampleRate);

  // Cycle time display mode
  const cycleTimeMode = useCallback(() => {
    setTimeMode((prev) =>
      prev === 'bars' ? 'timecode' : prev === 'timecode' ? 'samples' : 'bars'
    );
  }, []);

  // Tempo editing
  const handleTempoDoubleClick = useCallback(() => {
    setIsEditingTempo(true);
    setEditedTempo(tempo.toString());
  }, [tempo]);

  const handleTempoSubmit = useCallback(() => {
    const newTempo = parseFloat(editedTempo);
    if (!isNaN(newTempo) && newTempo >= 20 && newTempo <= 999) {
      onTempoChange(newTempo);
    }
    setIsEditingTempo(false);
  }, [editedTempo, onTempoChange]);

  const handleTempoKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter') {
        handleTempoSubmit();
      } else if (e.key === 'Escape') {
        setIsEditingTempo(false);
        setEditedTempo(tempo.toString());
      }
    },
    [handleTempoSubmit, tempo]
  );

  // Tempo scroll
  const handleTempoWheel = useCallback(
    (e: React.WheelEvent) => {
      e.preventDefault();
      const delta = e.deltaY > 0 ? -1 : 1;
      const newTempo = Math.max(20, Math.min(999, tempo + delta));
      onTempoChange(newTempo);
    },
    [tempo, onTempoChange]
  );

  // Focus tempo input when editing
  useEffect(() => {
    if (isEditingTempo && tempoInputRef.current) {
      tempoInputRef.current.focus();
      tempoInputRef.current.select();
    }
  }, [isEditingTempo]);

  // Progress percentage
  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  return (
    <div className="transport-bar">
      {/* Transport Controls */}
      <div className="transport-bar__controls">
        <button
          className="transport-bar__btn transport-bar__btn--rewind"
          onClick={onRewind}
          title="Rewind (,)"
        >
          <span className="transport-bar__icon">⏮</span>
        </button>

        <button
          className={`transport-bar__btn transport-bar__btn--stop ${
            !isPlaying && currentTime === 0 ? 'active' : ''
          }`}
          onClick={onStop}
          title="Stop (.)"
        >
          <span className="transport-bar__icon">⏹</span>
        </button>

        <button
          className={`transport-bar__btn transport-bar__btn--play ${
            isPlaying ? 'active' : ''
          }`}
          onClick={isPlaying ? onPause : onPlay}
          title="Play/Pause (Space)"
        >
          <span className="transport-bar__icon">
            {isPlaying ? '⏸' : '▶'}
          </span>
        </button>

        <button
          className={`transport-bar__btn transport-bar__btn--record ${
            isRecording ? 'active' : ''
          }`}
          onClick={onRecord}
          title="Record (Ctrl+R)"
        >
          <span className="transport-bar__icon">⏺</span>
        </button>

        <button
          className="transport-bar__btn transport-bar__btn--forward"
          onClick={onForward}
          title="Forward (/)"
        >
          <span className="transport-bar__icon">⏭</span>
        </button>
      </div>

      {/* Time Display */}
      <div
        className="transport-bar__time"
        onClick={cycleTimeMode}
        title={`Click to cycle: ${timeMode}`}
      >
        <span className="transport-bar__time-value">{formattedTime}</span>
        <span className="transport-bar__time-mode">
          {timeMode === 'bars' ? 'BAR' : timeMode === 'timecode' ? 'TC' : 'SMP'}
        </span>
      </div>

      {/* Progress Bar */}
      {duration > 0 && (
        <div className="transport-bar__progress">
          <div
            className="transport-bar__progress-fill"
            style={{ width: `${progress}%` }}
          />
          {loopEnabled && (
            <div
              className="transport-bar__loop-region"
              style={{
                left: `${(loopStart / duration) * 100}%`,
                width: `${((loopEnd - loopStart) / duration) * 100}%`,
              }}
            />
          )}
        </div>
      )}

      {/* Tempo */}
      <div
        className="transport-bar__tempo"
        onDoubleClick={handleTempoDoubleClick}
        onWheel={handleTempoWheel}
        title="Double-click to edit, scroll to adjust"
      >
        {isEditingTempo ? (
          <input
            ref={tempoInputRef}
            type="text"
            className="transport-bar__tempo-input"
            value={editedTempo}
            onChange={(e) => setEditedTempo(e.target.value)}
            onBlur={handleTempoSubmit}
            onKeyDown={handleTempoKeyDown}
          />
        ) : (
          <span className="transport-bar__tempo-value">
            {tempo.toFixed(1)}
          </span>
        )}
        <span className="transport-bar__tempo-unit">BPM</span>
      </div>

      {/* Time Signature */}
      <div
        className="transport-bar__signature"
        title="Time Signature"
      >
        <span className="transport-bar__signature-value">
          {timeSignature[0]}/{timeSignature[1]}
        </span>
      </div>

      {/* Toggle Buttons */}
      <div className="transport-bar__toggles">
        <button
          className={`transport-bar__toggle ${loopEnabled ? 'active' : ''}`}
          onClick={onLoopToggle}
          title="Loop (L)"
        >
          <span className="transport-bar__toggle-icon">🔁</span>
          <span className="transport-bar__toggle-label">LOOP</span>
        </button>

        <button
          className={`transport-bar__toggle ${metronomeEnabled ? 'active' : ''}`}
          onClick={onMetronomeToggle}
          title="Metronome"
        >
          <span className="transport-bar__toggle-icon">🎵</span>
          <span className="transport-bar__toggle-label">CLICK</span>
        </button>
      </div>
    </div>
  );
}

export default TransportBar;

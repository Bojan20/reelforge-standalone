/**
 * ReelForge Transport Controls
 *
 * Playback transport controls with:
 * - Play/Pause/Stop
 * - Record
 * - Loop toggle
 * - Time display
 * - Tempo/BPM
 *
 * @module timeline/TransportControls
 */

import { useCallback, useState, useEffect, useRef } from 'react';
import type { UseTimelineReturn } from './useTimeline';
import { formatTime, secondsToBarsBeatsTicks, formatBarsBeatsTicks } from './types';
import './TransportControls.css';

// ============ Types ============

export interface TransportControlsProps {
  /** Timeline hook return value */
  timeline: UseTimelineReturn;
  /** Is playing */
  isPlaying: boolean;
  /** Is recording */
  isRecording?: boolean;
  /** On play/pause toggle */
  onPlayPause: () => void;
  /** On stop */
  onStop: () => void;
  /** On record toggle */
  onRecord?: () => void;
  /** On tempo change */
  onTempoChange?: (bpm: number) => void;
  /** Show record button */
  showRecord?: boolean;
  /** Show tempo controls */
  showTempo?: boolean;
  /** Compact mode */
  compact?: boolean;
}

// ============ Icons ============

const PlayIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <path d="M4 2.5v11l9-5.5z" />
  </svg>
);

const PauseIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <rect x="3" y="2" width="4" height="12" />
    <rect x="9" y="2" width="4" height="12" />
  </svg>
);

const StopIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <rect x="3" y="3" width="10" height="10" />
  </svg>
);

const RecordIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <circle cx="8" cy="8" r="5" />
  </svg>
);

const LoopIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <path d="M12 4H4v2H2V3a1 1 0 011-1h9V0l3 2.5-3 2.5V4z" />
    <path d="M4 12h8v-2h2v3a1 1 0 01-1 1H4v2l-3-2.5 3-2.5v1z" />
  </svg>
);

const SkipBackIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <rect x="2" y="3" width="2" height="10" />
    <path d="M14 3v10L6 8z" />
  </svg>
);

const SkipForwardIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
    <rect x="12" y="3" width="2" height="10" />
    <path d="M2 3v10l8-5z" />
  </svg>
);

// ============ Component ============

export function TransportControls({
  timeline,
  isPlaying,
  isRecording = false,
  onPlayPause,
  onStop,
  onRecord,
  onTempoChange,
  showRecord = true,
  showTempo = true,
  compact = false,
}: TransportControlsProps) {
  const { state, setPlayhead, setLoop } = timeline;
  const [timeMode, setTimeMode] = useState<'time' | 'bbt'>('time');
  const [isEditingTempo, setIsEditingTempo] = useState(false);
  const [tempoInput, setTempoInput] = useState(state.bpm.toString());
  const tempoInputRef = useRef<HTMLInputElement>(null);

  // Format current position
  const formattedTime =
    timeMode === 'time'
      ? formatTime(state.playheadPosition)
      : formatBarsBeatsTicks(
          secondsToBarsBeatsTicks(state.playheadPosition, state.bpm, state.timeSignatureNum)
        );

  // Skip to start
  const handleSkipBack = useCallback(() => {
    setPlayhead(0);
  }, [setPlayhead]);

  // Skip forward (to end of content or +10s)
  const handleSkipForward = useCallback(() => {
    // For now, skip to loop end if loop enabled, otherwise +10s
    if (state.loopEnabled) {
      setPlayhead(state.loopEnd);
    } else {
      setPlayhead(state.playheadPosition + 10);
    }
  }, [state.loopEnabled, state.loopEnd, state.playheadPosition, setPlayhead]);

  // Toggle loop
  const handleLoopToggle = useCallback(() => {
    setLoop(!state.loopEnabled);
  }, [state.loopEnabled, setLoop]);

  // Handle tempo submit
  const handleTempoSubmit = useCallback(() => {
    const newBpm = parseFloat(tempoInput);
    if (!isNaN(newBpm) && newBpm >= 20 && newBpm <= 400) {
      onTempoChange?.(newBpm);
    } else {
      setTempoInput(state.bpm.toString());
    }
    setIsEditingTempo(false);
  }, [tempoInput, state.bpm, onTempoChange]);

  // Focus tempo input when editing
  useEffect(() => {
    if (isEditingTempo && tempoInputRef.current) {
      tempoInputRef.current.focus();
      tempoInputRef.current.select();
    }
  }, [isEditingTempo]);

  // Update tempo input when bpm changes externally
  useEffect(() => {
    if (!isEditingTempo) {
      setTempoInput(state.bpm.toString());
    }
  }, [state.bpm, isEditingTempo]);

  return (
    <div className={`transport ${compact ? 'transport--compact' : ''}`}>
      {/* Time Display */}
      <div
        className="transport__time"
        onClick={() => setTimeMode(timeMode === 'time' ? 'bbt' : 'time')}
        title="Click to toggle time format"
      >
        <span className="transport__time-value">{formattedTime}</span>
        <span className="transport__time-mode">{timeMode === 'time' ? 'TIME' : 'BAR'}</span>
      </div>

      {/* Main Controls */}
      <div className="transport__controls">
        <button
          className="transport__btn"
          onClick={handleSkipBack}
          title="Skip to start"
        >
          <SkipBackIcon />
        </button>

        <button
          className={`transport__btn transport__btn--play ${isPlaying ? 'playing' : ''}`}
          onClick={onPlayPause}
          title={isPlaying ? 'Pause' : 'Play'}
        >
          {isPlaying ? <PauseIcon /> : <PlayIcon />}
        </button>

        <button
          className="transport__btn"
          onClick={onStop}
          title="Stop"
        >
          <StopIcon />
        </button>

        {showRecord && (
          <button
            className={`transport__btn transport__btn--record ${isRecording ? 'recording' : ''}`}
            onClick={onRecord}
            title={isRecording ? 'Stop recording' : 'Record'}
          >
            <RecordIcon />
          </button>
        )}

        <button
          className="transport__btn"
          onClick={handleSkipForward}
          title="Skip forward"
        >
          <SkipForwardIcon />
        </button>

        <div className="transport__divider" />

        <button
          className={`transport__btn ${state.loopEnabled ? 'active' : ''}`}
          onClick={handleLoopToggle}
          title="Toggle loop"
        >
          <LoopIcon />
        </button>
      </div>

      {/* Tempo */}
      {showTempo && (
        <div className="transport__tempo">
          {isEditingTempo ? (
            <input
              ref={tempoInputRef}
              type="number"
              className="transport__tempo-input"
              value={tempoInput}
              onChange={(e) => setTempoInput(e.target.value)}
              onBlur={handleTempoSubmit}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleTempoSubmit();
                if (e.key === 'Escape') {
                  setTempoInput(state.bpm.toString());
                  setIsEditingTempo(false);
                }
              }}
              min="20"
              max="400"
              step="0.1"
            />
          ) : (
            <span
              className="transport__tempo-value"
              onClick={() => setIsEditingTempo(true)}
              title="Click to edit tempo"
            >
              {state.bpm.toFixed(1)}
            </span>
          )}
          <span className="transport__tempo-label">BPM</span>
        </div>
      )}

      {/* Time Signature */}
      {showTempo && (
        <div className="transport__signature">
          <span className="transport__signature-value">
            {state.timeSignatureNum}/{state.timeSignatureDen}
          </span>
        </div>
      )}
    </div>
  );
}

export default TransportControls;

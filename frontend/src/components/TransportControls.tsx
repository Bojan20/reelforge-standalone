/**
 * Transport Controls Component
 *
 * DAW-style transport bar with:
 * - Play/Pause/Stop
 * - Time display
 * - Loop toggle
 * - Volume control
 * - Playhead position slider
 *
 * @module components/TransportControls
 */

import React, { memo, useCallback, useState, useEffect } from 'react';
import type { PreviewState } from '../core/previewEngine';
import './TransportControls.css';

// ============ TYPES ============

export interface TransportControlsProps {
  state: PreviewState;
  onPlay: () => void;
  onPause: () => void;
  onStop: () => void;
  onSeek: (time: number) => void;
  onVolumeChange: (volume: number) => void;
  onLoopToggle: () => void;
  disabled?: boolean;
  compact?: boolean;
}

// ============ HELPERS ============

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(2, '0')}`;
}

// ============ COMPONENT ============

const TransportControls: React.FC<TransportControlsProps> = memo(({
  state,
  onPlay,
  onPause,
  onStop,
  onSeek,
  onVolumeChange,
  onLoopToggle,
  disabled = false,
  compact = false,
}) => {
  const [isDragging, setIsDragging] = useState(false);
  const [dragTime, setDragTime] = useState(0);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't trigger if typing in input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      switch (e.code) {
        case 'Space':
          e.preventDefault();
          if (state.isPlaying && !state.isPaused) {
            onPause();
          } else {
            onPlay();
          }
          break;
        case 'Escape':
          onStop();
          break;
        case 'KeyL':
          if (!e.metaKey && !e.ctrlKey) {
            onLoopToggle();
          }
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [state.isPlaying, state.isPaused, onPlay, onPause, onStop, onLoopToggle]);

  // Handle seek bar drag
  const handleSeekStart = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (state.duration === 0) return;

    setIsDragging(true);
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const percent = Math.max(0, Math.min(1, x / rect.width));
    const time = percent * state.duration;
    setDragTime(time);
  }, [state.duration]);

  const handleSeekMove = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!isDragging) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const percent = Math.max(0, Math.min(1, x / rect.width));
    const time = percent * state.duration;
    setDragTime(time);
  }, [isDragging, state.duration]);

  const handleSeekEnd = useCallback(() => {
    if (isDragging) {
      onSeek(dragTime);
      setIsDragging(false);
    }
  }, [isDragging, dragTime, onSeek]);

  // Calculate progress
  const displayTime = isDragging ? dragTime : state.currentTime;
  const progress = state.duration > 0 ? (displayTime / state.duration) * 100 : 0;

  return (
    <div className={`transport-controls ${compact ? 'compact' : ''} ${disabled ? 'disabled' : ''}`}>
      {/* Transport Buttons */}
      <div className="transport-buttons">
        {/* Stop */}
        <button
          className="transport-btn transport-btn--stop"
          onClick={onStop}
          disabled={disabled}
          title="Stop (Esc)"
        >
          <svg viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="6" width="12" height="12" rx="1" />
          </svg>
        </button>

        {/* Play/Pause */}
        <button
          className={`transport-btn transport-btn--play ${state.isPlaying && !state.isPaused ? 'active' : ''}`}
          onClick={state.isPlaying && !state.isPaused ? onPause : onPlay}
          disabled={disabled}
          title={state.isPlaying && !state.isPaused ? 'Pause (Space)' : 'Play (Space)'}
        >
          {state.isPlaying && !state.isPaused ? (
            <svg viewBox="0 0 24 24" fill="currentColor">
              <rect x="6" y="5" width="4" height="14" rx="1" />
              <rect x="14" y="5" width="4" height="14" rx="1" />
            </svg>
          ) : (
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M8 5.14v13.72a1 1 0 001.5.86l11-6.86a1 1 0 000-1.72l-11-6.86A1 1 0 008 5.14z" />
            </svg>
          )}
        </button>

        {/* Loop */}
        <button
          className={`transport-btn transport-btn--loop ${state.looping ? 'active' : ''}`}
          onClick={onLoopToggle}
          disabled={disabled}
          title="Loop (L)"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M17 2l4 4-4 4" />
            <path d="M3 11V9a4 4 0 014-4h14" />
            <path d="M7 22l-4-4 4-4" />
            <path d="M21 13v2a4 4 0 01-4 4H3" />
          </svg>
        </button>
      </div>

      {/* Time Display */}
      <div className="transport-time">
        <span className="transport-time__current">{formatTime(displayTime)}</span>
        <span className="transport-time__separator">/</span>
        <span className="transport-time__duration">{formatTime(state.duration)}</span>
      </div>

      {/* Seek Bar */}
      <div
        className="transport-seek"
        onMouseDown={handleSeekStart}
        onMouseMove={handleSeekMove}
        onMouseUp={handleSeekEnd}
        onMouseLeave={handleSeekEnd}
      >
        <div className="transport-seek__track">
          <div
            className="transport-seek__fill"
            style={{ width: `${progress}%` }}
          />
          <div
            className="transport-seek__thumb"
            style={{ left: `${progress}%` }}
          />
        </div>
      </div>

      {/* Volume Control */}
      <div className="transport-volume">
        <button
          className="transport-btn transport-btn--volume"
          onClick={() => onVolumeChange(state.volume > 0 ? 0 : 1)}
          title={state.volume > 0 ? 'Mute' : 'Unmute'}
        >
          <svg viewBox="0 0 24 24" fill="currentColor">
            {state.volume === 0 ? (
              <path d="M11 5L6 9H2v6h4l5 4V5zM23 9l-6 6M17 9l6 6" />
            ) : state.volume < 0.5 ? (
              <path d="M11 5L6 9H2v6h4l5 4V5zM15.54 8.46a5 5 0 010 7.07" />
            ) : (
              <path d="M11 5L6 9H2v6h4l5 4V5zM15.54 8.46a5 5 0 010 7.07M19.07 4.93a10 10 0 010 14.14" />
            )}
          </svg>
        </button>
        <input
          type="range"
          className="transport-volume__slider"
          min={0}
          max={1}
          step={0.01}
          value={state.volume}
          onChange={(e) => onVolumeChange(parseFloat(e.target.value))}
          disabled={disabled}
        />
      </div>

      {/* Now Playing Indicator */}
      {state.currentAssetId && (
        <div className="transport-now-playing">
          <span className="transport-now-playing__icon">
            {state.isPlaying && !state.isPaused ? '🔊' : '⏸️'}
          </span>
          <span className="transport-now-playing__name">
            {state.currentAssetId}
          </span>
        </div>
      )}
    </div>
  );
});

TransportControls.displayName = 'TransportControls';
export default TransportControls;

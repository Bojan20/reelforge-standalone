/**
 * SoundListItem - Optimized sound row component with React.memo
 */

import { memo } from 'react';
import type { AudioFileObject } from '../core/types';

interface SoundListItemProps {
  sound: AudioFileObject;
  isSelected: boolean;
  isPlaying: boolean;
  onSelect: (soundId: string) => void;
  onPlay: (sound: AudioFileObject) => void;
  onStop: () => void;
  onDelete: (soundId: string) => void;
}

function SoundListItemComponent({
  sound,
  isSelected,
  isPlaying,
  onSelect,
  onPlay,
  onStop,
  onDelete,
}: SoundListItemProps) {
  const formatFileSize = (size: string | undefined): string => {
    if (!size) return '—';
    // Size is already formatted as string
    return size;
  };

  const formatDuration = (seconds: number | undefined): string => {
    if (!seconds) return '—';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  return (
    <div
      className={`sound-item ${isSelected ? 'selected' : ''}`}
      onClick={() => onSelect(sound.name)}
    >
      <div className="sound-header">
        <span className="sound-name" title={sound.name}>
          {sound.name}
        </span>
        <div className="sound-actions">
          <button
            className="play-btn-small"
            onClick={(e) => {
              e.stopPropagation();
              if (isPlaying) {
                onStop();
              } else {
                onPlay(sound);
              }
            }}
            title={isPlaying ? 'Stop' : 'Play'}
          >
            {isPlaying ? '⏹' : '▶'}
          </button>
          <button
            className="delete-btn-small"
            onClick={(e) => {
              e.stopPropagation();
              if (confirm(`Delete sound "${sound.name}"?`)) {
                onDelete(sound.name);
              }
            }}
            title="Delete"
          >
            🗑️
          </button>
        </div>
      </div>
      <div className="sound-meta">
        <span className="sound-duration">{formatDuration(sound.duration)}</span>
        <span className="sound-size">{formatFileSize(sound.size)}</span>
      </div>
    </div>
  );
}

// Memoize to prevent re-renders
export const SoundListItem = memo(
  SoundListItemComponent,
  (prevProps, nextProps) => {
    return (
      prevProps.sound.name === nextProps.sound.name &&
      prevProps.isSelected === nextProps.isSelected &&
      prevProps.isPlaying === nextProps.isPlaying &&
      prevProps.sound.duration === nextProps.sound.duration &&
      prevProps.sound.size === nextProps.sound.size
    );
  }
);

SoundListItem.displayName = 'SoundListItem';

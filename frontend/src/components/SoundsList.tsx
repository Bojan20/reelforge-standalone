/**
 * SoundsList - Optimized sounds list with memoization
 */

import { memo, useMemo } from 'react';
import type { AudioFileObject } from '../core/types';
import { SoundListItem } from './SoundListItem';

interface SoundsListProps {
  sounds: AudioFileObject[];
  selectedSoundId: string | null;
  currentPlayingSound: string;
  searchQuery: string;
  onSelectSound: (soundId: string) => void;
  onPlaySound: (sound: AudioFileObject) => void;
  onStopSound: () => void;
  onDeleteSound: (soundId: string) => void;
}

function SoundsListComponent({
  sounds,
  selectedSoundId,
  currentPlayingSound,
  searchQuery,
  onSelectSound,
  onPlaySound,
  onStopSound,
  onDeleteSound,
}: SoundsListProps) {
  // Memoize filtered sounds
  const filteredSounds = useMemo(() => {
    if (!searchQuery) return sounds;

    const query = searchQuery.toLowerCase();
    return sounds.filter((sound) => sound.name.toLowerCase().includes(query));
  }, [sounds, searchQuery]);

  // Memoize sound items
  const soundItems = useMemo(
    () =>
      filteredSounds.map((sound) => (
        <SoundListItem
          key={sound.name}
          sound={sound}
          isSelected={selectedSoundId === sound.name}
          isPlaying={currentPlayingSound === sound.name}
          onSelect={onSelectSound}
          onPlay={onPlaySound}
          onStop={onStopSound}
          onDelete={onDeleteSound}
        />
      )),
    [filteredSounds, selectedSoundId, currentPlayingSound, onSelectSound, onPlaySound, onStopSound, onDeleteSound]
  );

  if (filteredSounds.length === 0) {
    return (
      <div className="empty-state">
        {searchQuery ? `No sounds found for "${searchQuery}"` : 'No sounds uploaded yet'}
      </div>
    );
  }

  return <div className="sounds-list">{soundItems}</div>;
}

// Memoize component
export const SoundsList = memo(SoundsListComponent);

SoundsList.displayName = 'SoundsList';

/**
 * Reel Stop Sequencer
 *
 * Visual timeline for per-reel stop audio timing.
 * Shows each reel's stop timing and associated sounds.
 *
 * Features:
 * - Timeline visualization
 * - Per-reel sound assignment
 * - Timing adjustment (drag handles)
 * - Anticipation triggers
 * - Preview playback
 *
 * @module layout/slot/ReelStopSequencer
 */

import { memo, useState, useCallback, useRef, useEffect } from 'react';

// ============ Types ============

export interface ReelStopSound {
  id: string;
  name: string;
  type: 'stop' | 'thud' | 'symbol' | 'anticipation';
  delay: number; // ms after reel stop
  duration: number; // visual duration in timeline
}

export interface ReelConfig {
  reelIndex: number;
  stopTime: number; // ms from spin start
  sounds: ReelStopSound[];
  hasAnticipation: boolean;
  anticipationStartTime?: number;
}

export interface ReelStopSequencerProps {
  reels: ReelConfig[];
  totalDuration: number; // ms
  currentTime?: number;
  isPlaying?: boolean;
  onReelChange?: (reels: ReelConfig[]) => void;
  onPlay?: () => void;
  onStop?: () => void;
  onSeek?: (time: number) => void;
}

// ============ Constants ============

const REEL_COLORS = ['#ef4444', '#f59e0b', '#22c55e', '#3b82f6', '#8b5cf6'];

// ============ Timeline Track ============

interface TimelineTrackProps {
  reel: ReelConfig;
  totalDuration: number;
  currentTime: number;
  isSelected: boolean;
  onSelect: () => void;
  onStopTimeChange: (time: number) => void;
  onSoundClick: (soundId: string) => void;
}

const TimelineTrack = memo(function TimelineTrack({
  reel,
  totalDuration,
  currentTime,
  isSelected,
  onSelect,
  onStopTimeChange,
  onSoundClick,
}: TimelineTrackProps) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);

  const color = REEL_COLORS[reel.reelIndex % REEL_COLORS.length];
  const stopPosition = (reel.stopTime / totalDuration) * 100;

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  useEffect(() => {
    if (!isDragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (!trackRef.current) return;
      const rect = trackRef.current.getBoundingClientRect();
      const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
      const newTime = (x / rect.width) * totalDuration;
      onStopTimeChange(Math.round(newTime));
    };

    const handleMouseUp = () => {
      setIsDragging(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, totalDuration, onStopTimeChange]);

  const isReelStopped = currentTime >= reel.stopTime;

  return (
    <div
      ref={trackRef}
      className={`rf-reel-track ${isSelected ? 'rf-reel-track--selected' : ''}`}
      onClick={onSelect}
    >
      {/* Track label */}
      <div className="rf-reel-track__label">
        <span className="rf-reel-track__index" style={{ backgroundColor: color }}>
          R{reel.reelIndex + 1}
        </span>
        <span className="rf-reel-track__time">{reel.stopTime}ms</span>
      </div>

      {/* Timeline area */}
      <div className="rf-reel-track__timeline">
        {/* Anticipation region */}
        {reel.hasAnticipation && reel.anticipationStartTime !== undefined && (
          <div
            className="rf-reel-track__anticipation"
            style={{
              left: `${(reel.anticipationStartTime / totalDuration) * 100}%`,
              width: `${((reel.stopTime - reel.anticipationStartTime) / totalDuration) * 100}%`,
            }}
          >
            <span>⚡ ANTIC</span>
          </div>
        )}

        {/* Stop marker */}
        <div
          className={`rf-reel-track__stop ${isDragging ? 'dragging' : ''} ${isReelStopped ? 'stopped' : ''}`}
          style={{ left: `${stopPosition}%`, borderColor: color }}
          onMouseDown={handleMouseDown}
        >
          <div className="rf-reel-track__stop-line" style={{ backgroundColor: color }} />
          <div className="rf-reel-track__stop-label">STOP</div>
        </div>

        {/* Sound blocks */}
        {reel.sounds.map((sound) => {
          const soundStart = reel.stopTime + sound.delay;
          const soundPosition = (soundStart / totalDuration) * 100;
          const soundWidth = (sound.duration / totalDuration) * 100;

          return (
            <div
              key={sound.id}
              className={`rf-reel-track__sound rf-reel-track__sound--${sound.type}`}
              style={{
                left: `${soundPosition}%`,
                width: `${Math.max(soundWidth, 2)}%`,
              }}
              onClick={(e) => {
                e.stopPropagation();
                onSoundClick(sound.id);
              }}
              title={`${sound.name} (+${sound.delay}ms)`}
            >
              <span>{sound.type === 'anticipation' ? '⚡' : '🔊'}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
});

// ============ Sound Editor Panel ============

interface SoundEditorProps {
  reel: ReelConfig | null;
  selectedSound: ReelStopSound | null;
  onSoundChange: (sound: ReelStopSound) => void;
  onSoundAdd: () => void;
  onSoundRemove: (soundId: string) => void;
  onAnticipationChange: (enabled: boolean) => void;
}

const SoundEditor = memo(function SoundEditor({
  reel,
  selectedSound,
  onSoundChange,
  onSoundAdd,
  onSoundRemove,
  onAnticipationChange,
}: SoundEditorProps) {
  if (!reel) {
    return (
      <div className="rf-reel-sound-editor rf-reel-sound-editor--empty">
        <p>Select a reel to edit sounds</p>
      </div>
    );
  }

  return (
    <div className="rf-reel-sound-editor">
      <div className="rf-reel-sound-editor__header">
        <span>Reel {reel.reelIndex + 1} Sounds</span>
        <button onClick={onSoundAdd}>+ Add Sound</button>
      </div>

      <div className="rf-reel-sound-editor__list">
        {reel.sounds.map((sound) => (
          <div
            key={sound.id}
            className={`rf-reel-sound-editor__item ${selectedSound?.id === sound.id ? 'selected' : ''}`}
          >
            <div className="rf-reel-sound-editor__item-header">
              <span className={`rf-reel-sound-editor__type rf-reel-sound-editor__type--${sound.type}`}>
                {sound.type}
              </span>
              <span className="rf-reel-sound-editor__name">{sound.name}</span>
              <button
                className="rf-reel-sound-editor__remove"
                onClick={() => onSoundRemove(sound.id)}
              >
                ×
              </button>
            </div>
            <div className="rf-reel-sound-editor__item-controls">
              <label>
                Delay:
                <input
                  type="number"
                  value={sound.delay}
                  min={0}
                  step={10}
                  onChange={(e) =>
                    onSoundChange({ ...sound, delay: parseInt(e.target.value) || 0 })
                  }
                />
                ms
              </label>
            </div>
          </div>
        ))}
        {reel.sounds.length === 0 && (
          <div className="rf-reel-sound-editor__empty">No sounds assigned</div>
        )}
      </div>

      {/* Anticipation toggle */}
      <div className="rf-reel-sound-editor__anticipation">
        <label>
          <input
            type="checkbox"
            checked={reel.hasAnticipation}
            onChange={(e) => onAnticipationChange(e.target.checked)}
          />
          Enable Anticipation
        </label>
      </div>
    </div>
  );
});

// ============ Main Component ============

export const ReelStopSequencer = memo(function ReelStopSequencer({
  reels,
  totalDuration,
  currentTime = 0,
  isPlaying = false,
  onReelChange,
  onPlay,
  onStop,
  onSeek,
}: ReelStopSequencerProps) {
  const [selectedReel, setSelectedReel] = useState<number | null>(null);
  const [selectedSound, setSelectedSound] = useState<string | null>(null);
  const timelineRef = useRef<HTMLDivElement>(null);

  // Handle reel stop time change
  const handleStopTimeChange = useCallback(
    (reelIndex: number, newTime: number) => {
      const newReels = reels.map((r) =>
        r.reelIndex === reelIndex ? { ...r, stopTime: newTime } : r
      );
      onReelChange?.(newReels);
    },
    [reels, onReelChange]
  );

  // Handle sound change
  const handleSoundChange = useCallback(
    (updatedSound: ReelStopSound) => {
      if (selectedReel === null) return;
      const newReels = reels.map((r) =>
        r.reelIndex === selectedReel
          ? {
              ...r,
              sounds: r.sounds.map((s) =>
                s.id === updatedSound.id ? updatedSound : s
              ),
            }
          : r
      );
      onReelChange?.(newReels);
    },
    [reels, selectedReel, onReelChange]
  );

  // Add sound to selected reel
  const handleSoundAdd = useCallback(() => {
    if (selectedReel === null) return;
    const newSound: ReelStopSound = {
      id: `sound-${Date.now()}`,
      name: 'new_sound',
      type: 'stop',
      delay: 0,
      duration: 100,
    };
    const newReels = reels.map((r) =>
      r.reelIndex === selectedReel
        ? { ...r, sounds: [...r.sounds, newSound] }
        : r
    );
    onReelChange?.(newReels);
  }, [reels, selectedReel, onReelChange]);

  // Remove sound
  const handleSoundRemove = useCallback(
    (soundId: string) => {
      if (selectedReel === null) return;
      const newReels = reels.map((r) =>
        r.reelIndex === selectedReel
          ? { ...r, sounds: r.sounds.filter((s) => s.id !== soundId) }
          : r
      );
      onReelChange?.(newReels);
    },
    [reels, selectedReel, onReelChange]
  );

  // Toggle anticipation for selected reel
  const handleAnticipationChange = useCallback(
    (enabled: boolean) => {
      if (selectedReel === null) return;
      const reel = reels.find((r) => r.reelIndex === selectedReel);
      if (!reel) return;

      const newReels = reels.map((r) =>
        r.reelIndex === selectedReel
          ? {
              ...r,
              hasAnticipation: enabled,
              // Calculate anticipation start time: 300ms before previous reel stops
              anticipationStartTime: enabled
                ? Math.max(0, r.stopTime - 300)
                : undefined,
            }
          : r
      );
      onReelChange?.(newReels);
    },
    [reels, selectedReel, onReelChange]
  );

  // Timeline click for seeking
  const handleTimelineClick = useCallback(
    (e: React.MouseEvent) => {
      if (!timelineRef.current) return;
      const rect = timelineRef.current.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const time = (x / rect.width) * totalDuration;
      onSeek?.(Math.round(time));
    },
    [totalDuration, onSeek]
  );

  // Format time display
  const formatTime = (ms: number) => {
    const sec = Math.floor(ms / 1000);
    const msRemainder = ms % 1000;
    return `${sec}.${msRemainder.toString().padStart(3, '0')}`;
  };

  // Get selected reel config
  const selectedReelConfig = selectedReel !== null
    ? reels.find((r) => r.reelIndex === selectedReel) ?? null
    : null;

  // Get selected sound config
  const selectedSoundConfig = selectedReelConfig && selectedSound
    ? selectedReelConfig.sounds.find((s) => s.id === selectedSound) ?? null
    : null;

  return (
    <div className="rf-reel-stop-sequencer">
      {/* Header */}
      <div className="rf-reel-stop-sequencer__header">
        <span className="rf-reel-stop-sequencer__title">Reel Stop Sequencer</span>
        <div className="rf-reel-stop-sequencer__transport">
          <button
            className="rf-reel-stop-sequencer__btn"
            onClick={() => onSeek?.(0)}
          >
            ⏮
          </button>
          <button
            className={`rf-reel-stop-sequencer__btn ${isPlaying ? 'active' : ''}`}
            onClick={isPlaying ? onStop : onPlay}
          >
            {isPlaying ? '⏸' : '▶'}
          </button>
          <span className="rf-reel-stop-sequencer__time">
            {formatTime(currentTime)} / {formatTime(totalDuration)}
          </span>
        </div>
      </div>

      {/* Timeline ruler */}
      <div className="rf-reel-stop-sequencer__ruler">
        {Array.from({ length: Math.ceil(totalDuration / 500) + 1 }).map((_, i) => {
          const time = i * 500;
          return (
            <div
              key={i}
              className="rf-reel-stop-sequencer__ruler-mark"
              style={{ left: `${(time / totalDuration) * 100}%` }}
            >
              <span>{time}ms</span>
            </div>
          );
        })}
      </div>

      {/* Tracks container */}
      <div
        ref={timelineRef}
        className="rf-reel-stop-sequencer__tracks"
        onClick={handleTimelineClick}
      >
        {/* Playhead */}
        <div
          className="rf-reel-stop-sequencer__playhead"
          style={{ left: `${(currentTime / totalDuration) * 100}%` }}
        />

        {/* Reel tracks */}
        {reels.map((reel) => (
          <TimelineTrack
            key={reel.reelIndex}
            reel={reel}
            totalDuration={totalDuration}
            currentTime={currentTime}
            isSelected={selectedReel === reel.reelIndex}
            onSelect={() => setSelectedReel(reel.reelIndex)}
            onStopTimeChange={(time) => handleStopTimeChange(reel.reelIndex, time)}
            onSoundClick={(soundId) => setSelectedSound(soundId)}
          />
        ))}
      </div>

      {/* Sound editor panel */}
      <SoundEditor
        reel={selectedReelConfig}
        selectedSound={selectedSoundConfig}
        onSoundChange={handleSoundChange}
        onSoundAdd={handleSoundAdd}
        onSoundRemove={handleSoundRemove}
        onAnticipationChange={handleAnticipationChange}
      />
    </div>
  );
});

// ============ Demo Data ============

export function generateDemoReelConfig(): ReelConfig[] {
  return [
    {
      reelIndex: 0,
      stopTime: 800,
      sounds: [
        { id: 'r1-stop', name: 'reel_stop_01', type: 'stop', delay: 0, duration: 100 },
        { id: 'r1-thud', name: 'reel_thud_01', type: 'thud', delay: 30, duration: 80 },
      ],
      hasAnticipation: false,
    },
    {
      reelIndex: 1,
      stopTime: 1100,
      sounds: [
        { id: 'r2-stop', name: 'reel_stop_02', type: 'stop', delay: 0, duration: 100 },
        { id: 'r2-thud', name: 'reel_thud_02', type: 'thud', delay: 30, duration: 80 },
      ],
      hasAnticipation: false,
    },
    {
      reelIndex: 2,
      stopTime: 1400,
      sounds: [
        { id: 'r3-stop', name: 'reel_stop_03', type: 'stop', delay: 0, duration: 100 },
        { id: 'r3-thud', name: 'reel_thud_03', type: 'thud', delay: 30, duration: 80 },
      ],
      hasAnticipation: true,
      anticipationStartTime: 1100,
    },
    {
      reelIndex: 3,
      stopTime: 1700,
      sounds: [
        { id: 'r4-stop', name: 'reel_stop_04', type: 'stop', delay: 0, duration: 100 },
      ],
      hasAnticipation: false,
    },
    {
      reelIndex: 4,
      stopTime: 2000,
      sounds: [
        { id: 'r5-stop', name: 'reel_stop_05', type: 'stop', delay: 0, duration: 100 },
        { id: 'r5-final', name: 'reel_stop_final', type: 'stop', delay: 50, duration: 150 },
      ],
      hasAnticipation: false,
    },
  ];
}

export default ReelStopSequencer;

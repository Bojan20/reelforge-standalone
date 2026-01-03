/**
 * ReelForge Mixer
 *
 * Main mixer component with multiple channels, master bus,
 * and global controls.
 *
 * @module mixer/Mixer
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { MixerChannel } from './MixerChannel';
import './Mixer.css';

// ============ Types ============

export interface ChannelState {
  id: string;
  name: string;
  color: string;
  volume: number;
  pan: number;
  muted: boolean;
  solo: boolean;
  armed: boolean;
  peakL: number;
  peakR: number;
}

export interface MixerProps {
  /** Initial channels */
  channels?: ChannelState[];
  /** On channel change */
  onChannelChange?: (channel: ChannelState) => void;
  /** On master volume change */
  onMasterVolumeChange?: (volume: number) => void;
  /** Compact mode */
  compact?: boolean;
}

// ============ Default Colors ============

const CHANNEL_COLORS = [
  '#4a9eff', // Blue
  '#ff6b6b', // Red
  '#51cf66', // Green
  '#ffd43b', // Yellow
  '#cc5de8', // Purple
  '#ff922b', // Orange
  '#20c997', // Teal
  '#f06595', // Pink
];

// ============ Component ============

export function Mixer({
  channels: initialChannels,
  onChannelChange,
  onMasterVolumeChange,
  compact = false,
}: MixerProps) {
  const [channels, setChannels] = useState<ChannelState[]>(
    initialChannels || createDefaultChannels()
  );
  const [masterVolume, setMasterVolume] = useState(0);
  const [masterPeakL, setMasterPeakL] = useState(0);
  const [masterPeakR, setMasterPeakR] = useState(0);
  const [scrollPosition, setScrollPosition] = useState(0);
  const scrollRef = useRef<HTMLDivElement>(null);
  const meterAnimationRef = useRef<number>(0);

  // Simulate meter activity
  useEffect(() => {
    const updateMeters = () => {
      setChannels((prev) =>
        prev.map((ch) => ({
          ...ch,
          peakL: ch.muted ? 0 : Math.random() * 0.7 + 0.1,
          peakR: ch.muted ? 0 : Math.random() * 0.7 + 0.1,
        }))
      );

      // Master meters
      const activeSolo = channels.some((ch) => ch.solo);
      const activeChannels = channels.filter(
        (ch) => !ch.muted && (!activeSolo || ch.solo)
      );
      if (activeChannels.length > 0) {
        setMasterPeakL(Math.random() * 0.8 + 0.1);
        setMasterPeakR(Math.random() * 0.8 + 0.1);
      } else {
        setMasterPeakL(0);
        setMasterPeakR(0);
      }

      meterAnimationRef.current = requestAnimationFrame(updateMeters);
    };

    // Start simulation - in real app, this would come from audio engine
    // updateMeters();

    return () => {
      if (meterAnimationRef.current) {
        cancelAnimationFrame(meterAnimationRef.current);
      }
    };
  }, [channels]);

  // Channel handlers
  const handleVolumeChange = useCallback(
    (id: string, volume: number) => {
      setChannels((prev) =>
        prev.map((ch) => (ch.id === id ? { ...ch, volume } : ch))
      );
      const channel = channels.find((ch) => ch.id === id);
      if (channel && onChannelChange) {
        onChannelChange({ ...channel, volume });
      }
    },
    [channels, onChannelChange]
  );

  const handlePanChange = useCallback(
    (id: string, pan: number) => {
      setChannels((prev) =>
        prev.map((ch) => (ch.id === id ? { ...ch, pan } : ch))
      );
      const channel = channels.find((ch) => ch.id === id);
      if (channel && onChannelChange) {
        onChannelChange({ ...channel, pan });
      }
    },
    [channels, onChannelChange]
  );

  const handleMuteToggle = useCallback(
    (id: string) => {
      setChannels((prev) =>
        prev.map((ch) => (ch.id === id ? { ...ch, muted: !ch.muted } : ch))
      );
    },
    []
  );

  const handleSoloToggle = useCallback(
    (id: string) => {
      setChannels((prev) =>
        prev.map((ch) => (ch.id === id ? { ...ch, solo: !ch.solo } : ch))
      );
    },
    []
  );

  const handleArmToggle = useCallback(
    (id: string) => {
      setChannels((prev) =>
        prev.map((ch) => (ch.id === id ? { ...ch, armed: !ch.armed } : ch))
      );
    },
    []
  );

  const handleNameChange = useCallback((id: string, name: string) => {
    setChannels((prev) =>
      prev.map((ch) => (ch.id === id ? { ...ch, name } : ch))
    );
  }, []);

  const handleMasterVolumeChange = useCallback(
    (volume: number) => {
      setMasterVolume(volume);
      onMasterVolumeChange?.(volume);
    },
    [onMasterVolumeChange]
  );

  // Scroll handling
  const handleScroll = useCallback(() => {
    if (scrollRef.current) {
      setScrollPosition(scrollRef.current.scrollLeft);
    }
  }, []);

  const scrollLeft = useCallback(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollBy({ left: -200, behavior: 'smooth' });
    }
  }, []);

  const scrollRight = useCallback(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollBy({ left: 200, behavior: 'smooth' });
    }
  }, []);

  // Channel management
  const addChannel = useCallback(() => {
    const newChannel: ChannelState = {
      id: `ch_${Date.now()}`,
      name: `Track ${channels.length + 1}`,
      color: CHANNEL_COLORS[channels.length % CHANNEL_COLORS.length],
      volume: 0,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    };
    setChannels((prev) => [...prev, newChannel]);
  }, [channels.length]);

  const canScrollLeft = scrollPosition > 0;
  const canScrollRight =
    scrollRef.current &&
    scrollPosition <
      scrollRef.current.scrollWidth - scrollRef.current.clientWidth;

  return (
    <div className={`mixer ${compact ? 'mixer--compact' : ''}`}>
      {/* Toolbar */}
      <div className="mixer__toolbar">
        <button className="mixer__btn" onClick={addChannel} title="Add Channel">
          +
        </button>
        <div className="mixer__toolbar-spacer" />
        <button
          className="mixer__scroll-btn"
          onClick={scrollLeft}
          disabled={!canScrollLeft}
          title="Scroll Left"
        >
          ‹
        </button>
        <button
          className="mixer__scroll-btn"
          onClick={scrollRight}
          disabled={!canScrollRight}
          title="Scroll Right"
        >
          ›
        </button>
      </div>

      {/* Channel Strip Container */}
      <div className="mixer__content">
        {/* Scrollable Channels */}
        <div
          ref={scrollRef}
          className="mixer__channels"
          onScroll={handleScroll}
        >
          {channels.map((channel) => (
            <MixerChannel
              key={channel.id}
              id={channel.id}
              name={channel.name}
              color={channel.color}
              volume={channel.volume}
              pan={channel.pan}
              muted={channel.muted}
              solo={channel.solo}
              armed={channel.armed}
              peakL={channel.peakL}
              peakR={channel.peakR}
              compact={compact}
              onVolumeChange={(vol) => handleVolumeChange(channel.id, vol)}
              onPanChange={(pan) => handlePanChange(channel.id, pan)}
              onMuteToggle={() => handleMuteToggle(channel.id)}
              onSoloToggle={() => handleSoloToggle(channel.id)}
              onArmToggle={() => handleArmToggle(channel.id)}
              onNameChange={(name) => handleNameChange(channel.id, name)}
            />
          ))}
        </div>

        {/* Master Channel */}
        <div className="mixer__master-section">
          <div className="mixer__master-label">MASTER</div>
          <MixerChannel
            id="master"
            name="Master"
            color="#ffd43b"
            volume={masterVolume}
            pan={0}
            muted={false}
            solo={false}
            armed={false}
            peakL={masterPeakL}
            peakR={masterPeakR}
            compact={compact}
            onVolumeChange={handleMasterVolumeChange}
            onPanChange={() => {}}
            onMuteToggle={() => {}}
            onSoloToggle={() => {}}
            onArmToggle={() => {}}
            insertCount={0}
          />
        </div>
      </div>
    </div>
  );
}

// ============ Helper Functions ============

function createDefaultChannels(): ChannelState[] {
  return [
    {
      id: 'ch_1',
      name: 'Drums',
      color: CHANNEL_COLORS[0],
      volume: -6,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
    {
      id: 'ch_2',
      name: 'Bass',
      color: CHANNEL_COLORS[1],
      volume: -8,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
    {
      id: 'ch_3',
      name: 'Keys',
      color: CHANNEL_COLORS[2],
      volume: -10,
      pan: -0.3,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
    {
      id: 'ch_4',
      name: 'Guitar',
      color: CHANNEL_COLORS[3],
      volume: -12,
      pan: 0.4,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
    {
      id: 'ch_5',
      name: 'Vocals',
      color: CHANNEL_COLORS[4],
      volume: -4,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
    {
      id: 'ch_6',
      name: 'FX',
      color: CHANNEL_COLORS[5],
      volume: -18,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
      peakL: 0,
      peakR: 0,
    },
  ];
}

export default Mixer;

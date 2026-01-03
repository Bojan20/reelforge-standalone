/**
 * ReelForge Mixer with Audio Engine
 *
 * Connected mixer component that uses the real AudioEngine
 * for audio processing and metering.
 *
 * @module mixer/MixerWithEngine
 */

import { useEffect, useCallback, useState } from 'react';
import { Mixer, type ChannelState } from './Mixer';
import { useAudioEngine } from '../engine/useAudioEngine';

// ============ Types ============

export interface MixerWithEngineProps {
  /** Initial channel configurations */
  initialChannels?: Array<{
    id: string;
    name: string;
    color: string;
    volume?: number;
    pan?: number;
  }>;
  /** Compact mode */
  compact?: boolean;
  /** On channel change callback */
  onChannelChange?: (channel: ChannelState) => void;
}

// ============ Default Channels ============

const DEFAULT_CHANNELS = [
  { id: 'ch_drums', name: 'Drums', color: '#4a9eff', volume: -6, pan: 0 },
  { id: 'ch_bass', name: 'Bass', color: '#ff6b6b', volume: -8, pan: 0 },
  { id: 'ch_keys', name: 'Keys', color: '#51cf66', volume: -10, pan: -0.3 },
  { id: 'ch_guitar', name: 'Guitar', color: '#ffd43b', volume: -12, pan: 0.4 },
  { id: 'ch_vocals', name: 'Vocals', color: '#cc5de8', volume: -4, pan: 0 },
  { id: 'ch_fx', name: 'FX', color: '#ff922b', volume: -18, pan: 0 },
];

// ============ Component ============

export function MixerWithEngine({
  initialChannels = DEFAULT_CHANNELS,
  compact = false,
  onChannelChange,
}: MixerWithEngineProps) {
  const engine = useAudioEngine();
  const [channels, setChannels] = useState<ChannelState[]>([]);
  const [, setMasterVolume] = useState(0);

  // Initialize engine and channels
  useEffect(() => {
    const init = async () => {
      await engine.initialize();

      // Create channels in engine
      for (const ch of initialChannels) {
        engine.createChannel({
          id: ch.id,
          name: ch.name,
          volume: ch.volume ?? 0,
          pan: ch.pan ?? 0,
          muted: false,
          solo: false,
        });
      }
    };

    init();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Sync channel states with engine
  useEffect(() => {
    const engineChannels = Array.from(engine.channels.values());

    const mapped: ChannelState[] = engineChannels.map((ch) => ({
      id: ch.id,
      name: ch.name,
      color:
        initialChannels.find((ic) => ic.id === ch.id)?.color || '#4a9eff',
      volume: ch.volume,
      pan: ch.pan,
      muted: ch.muted,
      solo: ch.solo,
      armed: false,
      peakL: ch.peakL,
      peakR: ch.peakR,
    }));

    setChannels(mapped);
  }, [engine.channels, initialChannels]);

  // Handlers
  const handleChannelChange = useCallback(
    (channel: ChannelState) => {
      const existing = engine.channels.get(channel.id);
      if (!existing) return;

      // Detect what changed
      if (existing.volume !== channel.volume) {
        engine.setVolume(channel.id, channel.volume);
      }
      if (existing.pan !== channel.pan) {
        engine.setPan(channel.id, channel.pan);
      }
      if (existing.muted !== channel.muted) {
        engine.setMute(channel.id, channel.muted);
      }
      if (existing.solo !== channel.solo) {
        engine.setSolo(channel.id, channel.solo);
      }

      onChannelChange?.(channel);
    },
    [engine, onChannelChange]
  );

  const handleMasterVolumeChange = useCallback(
    (volume: number) => {
      setMasterVolume(volume);
      engine.setMasterVolume(volume);
    },
    [engine]
  );

  // Add master meter to channel list
  const masterMeter = engine.masterMeter;
  const masterPeakL = masterMeter?.peakL ?? 0;
  const masterPeakR = masterMeter?.peakR ?? 0;

  return (
    <div className="mixer-with-engine">
      <Mixer
        channels={channels.map((ch) => ({
          ...ch,
          // Use real meter data from engine
          peakL: engine.channels.get(ch.id)?.peakL ?? 0,
          peakR: engine.channels.get(ch.id)?.peakR ?? 0,
        }))}
        onChannelChange={handleChannelChange}
        onMasterVolumeChange={handleMasterVolumeChange}
        compact={compact}
      />

      {/* Status Bar */}
      {engine.isInitialized && (
        <div className="mixer-with-engine__status">
          <span className="mixer-with-engine__status-item">
            {engine.state.sampleRate / 1000}kHz
          </span>
          <span className="mixer-with-engine__status-item">
            Latency: {(engine.state.latency * 1000).toFixed(1)}ms
          </span>
          <span className="mixer-with-engine__status-item">
            Master: L {(masterPeakL * 100).toFixed(0)}% R{' '}
            {(masterPeakR * 100).toFixed(0)}%
          </span>
        </div>
      )}
    </div>
  );
}

export default MixerWithEngine;

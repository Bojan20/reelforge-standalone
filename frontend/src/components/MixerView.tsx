import { memo, useCallback, useState, useEffect, useRef } from 'react';
import type { BusId } from '../core/types';
import type { InsertableBusId } from '../project/projectTypes';
import { useMixer } from '../store';
import { StripInsertRack } from './StripInsertRack';
import { LevelMeter } from '../meters/LevelMeter';

interface MixerViewProps {
  onBusChange: (busId: BusId, volume: number, muted?: boolean) => void;
  selectedBus: BusId | null;
  onSelectBus: (busId: BusId | null) => void;
}

// Convert linear volume (0.0 - 1.0) to decibels
function volumeToDb(volume: number): string {
  if (volume <= 0) return '-∞';
  const db = 20 * Math.log10(volume);
  return db.toFixed(1);
}

// ============ Memoized Strip Component ============

interface MixerStripProps {
  busId: BusId;
  busName: string;
  volume: number;
  muted: boolean;
  isSelected: boolean;
  onBusChange: (busId: BusId, volume: number, muted?: boolean) => void;
  onSelectBus: (busId: BusId | null) => void;
}

const MixerStrip = memo(function MixerStrip({
  busId,
  busName,
  volume,
  muted,
  isSelected,
  onBusChange,
  onSelectBus,
}: MixerStripProps) {
  const isMaster = busId === 'master';

  const handleSelect = useCallback(() => {
    onSelectBus(isSelected ? null : busId);
  }, [busId, isSelected, onSelectBus]);

  const handleMuteToggle = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    onBusChange(busId, volume, !muted);
  }, [busId, volume, muted, onBusChange]);

  const handleVolumeChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    onBusChange(busId, parseFloat(e.target.value));
  }, [busId, onBusChange]);

  return (
    <div
      className={`rf-mixer-strip ${isMaster ? 'rf-mixer-strip-master' : ''} ${isSelected ? 'rf-mixer-strip-selected' : ''}`}
    >
      <div
        className="rf-mixer-name"
        onClick={handleSelect}
        style={{ cursor: 'pointer' }}
      >
        {busName}
      </div>
      <button
        className={`rf-mixer-mute ${muted ? 'rf-mixer-mute-active' : ''}`}
        onClick={handleMuteToggle}
      >
        M
      </button>
      <StripInsertRack
        scope={isMaster ? 'master' : 'bus'}
        scopeId={isMaster ? undefined : (busId as InsertableBusId)}
      />
      <div className="rf-mixer-fader-container">
        <div className="rf-mixer-fader-bg"></div>
        <input
          type="range"
          className="rf-mixer-fader"
          min="0"
          max="1"
          step="0.01"
          value={volume}
          onInput={handleVolumeChange}
          onChange={handleVolumeChange}
        />
      </div>
      <div className="rf-mixer-value">
        <div>{volumeToDb(volume)}</div>
        <div style={{ fontSize: '9px', color: '#888' }}>dB ({(volume * 100).toFixed(0)}%)</div>
      </div>
    </div>
  );
});

// ============ Bus Config ============

const BUSES = [
  { id: 'music' as BusId, name: 'Music' },
  { id: 'sfx' as BusId, name: 'SFX' },
  { id: 'voice' as BusId, name: 'Voice' },
  { id: 'ambience' as BusId, name: 'Ambience' },
  { id: 'master' as BusId, name: 'Master' }
] as const;

// ============ Main Component ============

export default function MixerView({ onBusChange, selectedBus, onSelectBus }: MixerViewProps) {
  const { state, getBusState } = useMixer();
  const { project } = state;
  const containerRef = useRef<HTMLDivElement>(null);

  // Simulated master level (would connect to real analyzer in production)
  const [masterLevel, setMasterLevel] = useState({ L: 0, R: 0 });
  const animRef = useRef<number>(0);

  useEffect(() => {
    const animate = () => {
      const masterState = getBusState('master');
      const vol = masterState.muted ? 0 : masterState.volume;
      // Simulate realistic level movement
      setMasterLevel({
        L: vol * (0.3 + Math.random() * 0.5),
        R: vol * (0.3 + Math.random() * 0.5),
      });
      animRef.current = requestAnimationFrame(animate);
    };
    animRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animRef.current);
  }, [getBusState]);

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Only handle when mixer is focused or has selected bus
      if (!containerRef.current?.contains(document.activeElement) && !selectedBus) return;

      const busIds = BUSES.map(b => b.id);
      const currentIndex = selectedBus ? busIds.indexOf(selectedBus) : -1;

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          if (currentIndex > 0) {
            onSelectBus(busIds[currentIndex - 1]);
          } else if (currentIndex === -1) {
            onSelectBus(busIds[0]);
          }
          break;

        case 'ArrowRight':
          e.preventDefault();
          if (currentIndex < busIds.length - 1) {
            onSelectBus(busIds[currentIndex + 1]);
          } else if (currentIndex === -1) {
            onSelectBus(busIds[0]);
          }
          break;

        case 'ArrowUp':
          if (selectedBus) {
            e.preventDefault();
            const busState = getBusState(selectedBus);
            const step = e.shiftKey ? 0.1 : 0.02;
            onBusChange(selectedBus, Math.min(1, busState.volume + step));
          }
          break;

        case 'ArrowDown':
          if (selectedBus) {
            e.preventDefault();
            const busState = getBusState(selectedBus);
            const step = e.shiftKey ? 0.1 : 0.02;
            onBusChange(selectedBus, Math.max(0, busState.volume - step));
          }
          break;

        case 'm':
        case 'M':
          if (selectedBus) {
            e.preventDefault();
            const busState = getBusState(selectedBus);
            onBusChange(selectedBus, busState.volume, !busState.muted);
          }
          break;

        case 'Escape':
          onSelectBus(null);
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [selectedBus, onSelectBus, onBusChange, getBusState]);

  if (!project) return null;

  return (
    <div ref={containerRef} className="rf-mixer-strips" tabIndex={0}>
      {BUSES.map(bus => {
        const busState = getBusState(bus.id);
        return (
          <MixerStrip
            key={bus.id}
            busId={bus.id}
            busName={bus.name}
            volume={busState.volume}
            muted={busState.muted}
            isSelected={selectedBus === bus.id}
            onBusChange={onBusChange}
            onSelectBus={onSelectBus}
          />
        );
      })}
      {/* Master Level Meter */}
      <div style={{ marginLeft: '8px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <span style={{ fontSize: '9px', color: '#888', marginBottom: '4px' }}>OUT</span>
        <LevelMeter
          levelL={masterLevel.L}
          levelR={masterLevel.R}
          orientation="vertical"
          width={24}
          height={180}
          showScale={false}
          showLabels={true}
        />
      </div>
    </div>
  );
}

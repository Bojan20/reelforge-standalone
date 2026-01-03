import { useState, useEffect } from 'react';
import type { ReelForgeProject, BusId } from './core/types';

interface MixerPanelProps {
  project: ReelForgeProject | null;
  onBusChange: (busId: BusId, volume: number, muted?: boolean) => void;
  visible: boolean;
  onToggle: () => void;
}

export default function MixerPanel({ project, onBusChange, visible, onToggle }: MixerPanelProps) {
  const [isClosing, setIsClosing] = useState(false);
  const [shouldRender, setShouldRender] = useState(visible);
  const [selectedBus, setSelectedBus] = useState<BusId | null>(null);

  useEffect(() => {
    if (visible) {
      setShouldRender(true);
      setIsClosing(false);
    } else if (shouldRender) {
      setIsClosing(true);
      const timer = setTimeout(() => {
        setShouldRender(false);
        setIsClosing(false);
      }, 400);
      return () => clearTimeout(timer);
    }
  }, [visible, shouldRender]);

  if (!project || !project.buses || project.buses.length === 0) return null;

  return (
    <>
      <button 
        className="rf-mixer-toggle"
        onClick={onToggle}
        title={visible ? 'Hide Mixer' : 'Show Mixer'}
      >
        {visible ? '▼' : '▲'} MIXER
      </button>
      
      {shouldRender && (
        <div className={`rf-mixer-panel ${isClosing ? 'closing' : ''}`}>
          <div className="rf-mixer-strips">
            {project.buses.map(bus => {
              const isMaster = bus.id === 'master';
              const isSelected = selectedBus === bus.id;
              const volumeDb = bus.volume === 0 ? -Infinity : Math.round(20 * Math.log10(bus.volume ?? 1));
              const volumePercent = Math.round((bus.volume ?? 1) * 100);

              return (
                <div
                  key={bus.id}
                  className={`rf-mixer-strip ${isMaster ? 'rf-mixer-strip-master' : ''} ${isSelected && !isMaster ? 'rf-mixer-strip-selected' : ''}`}
                  onClick={() => setSelectedBus(bus.id)}
                >
                  <div className="rf-mixer-name">{bus.name}</div>

                  <button
                    className={bus.muted ? 'rf-mixer-mute rf-mixer-mute-active' : 'rf-mixer-mute'}
                    onClick={(e) => {
                      e.stopPropagation();
                      onBusChange(bus.id, bus.volume ?? 1, !bus.muted);
                    }}
                    title={bus.muted ? 'Unmute' : 'Mute'}
                  >
                    M
                  </button>

                  <div className="rf-mixer-fader-container">
                    <div className="rf-mixer-fader-bg"></div>
                    <input
                      type="range"
                      min={0}
                      max={100}
                      value={volumePercent}
                      onChange={(e) =>
                        onBusChange(bus.id, Number(e.target.value) / 100, bus.muted)
                      }
                      onFocus={() => setSelectedBus(bus.id)}
                      className="rf-mixer-fader"
                    />
                  </div>

                  <div className="rf-mixer-value">
                    <div>{volumeDb === -Infinity ? '-∞' : volumeDb > 0 ? `+${volumeDb}` : volumeDb}</div>
                    <div style={{ fontSize: '9px', color: '#888' }}>dB ({volumePercent}%)</div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </>
  );
}

/**
 * VanEQ Pro - Mid Strip Component
 * Add button, band chips, and mini controls
 */

import type { Band } from './utils';

const BAND_COLORS = ['#58d6ff', '#ffd36a', '#ffb24a', '#c48bff', '#50e3c2', '#ff6b8a', '#8b9fff', '#7cd992'];

type Props = {
  bands: Band[];
  activeIndex: number;
  onSelect: (index: number) => void;
};

export function BandStrip({
  bands,
  activeIndex,
  onSelect,
}: Props) {
  // Mini meter segments (simulated)
  const meterSegs = Array.from({ length: 12 }, (_, i) => i < 6);

  return (
    <div className="midStrip">
      {/* Left: Add button */}
      <div className="midLeft">
        <button className="addBtn">
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.8">
            <path d="M6 2v8M2 6h8" />
          </svg>
          <span>Add</span>
        </button>
      </div>

      {/* Center: Band chips */}
      <div className="midCenter">
        {bands.map((band, i) => (
          <button
            key={i}
            className={`chip ${activeIndex === i ? 'active' : ''}`}
            onClick={() => onSelect(i)}
          >
            <span
              className="chipDot"
              style={{ background: band.enabled ? BAND_COLORS[i] : 'var(--muted)' }}
            />
            <span>{i + 1}</span>
          </button>
        ))}
      </div>

      {/* Right: Icon + mini meter + control */}
      <div className="midRight">
        <button className="iconBtn">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.4">
            <path d="M7 1v12M3 5l4-4 4 4M3 9l4 4 4-4" />
          </svg>
        </button>

        <div className="miniMeter">
          {meterSegs.map((on, i) => (
            <div
              key={i}
              className="meterSeg"
              style={{ background: on ? 'var(--ok)' : 'rgba(255,255,255,.08)' }}
            />
          ))}
        </div>

        <button className="iconBtn">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.4">
            <circle cx="7" cy="7" r="5" />
            <path d="M7 4v3l2 2" />
          </svg>
        </button>
      </div>
    </div>
  );
}

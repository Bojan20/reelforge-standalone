/**
 * ReelForge Marker Manager
 *
 * Timeline marker and region management:
 * - Markers (points)
 * - Regions (ranges)
 * - Loop regions
 * - Punch in/out
 * - Navigation
 *
 * @module markers/MarkerManager
 */

import { useState, useCallback, useMemo } from 'react';
import './MarkerManager.css';

// ============ Types ============

export type MarkerType = 'marker' | 'region' | 'loop' | 'punch';

export interface Marker {
  id: string;
  type: MarkerType;
  name: string;
  color: string;
  position: number; // seconds
  endPosition?: number; // for regions
  locked: boolean;
  comment?: string;
}

export interface MarkerManagerProps {
  /** All markers */
  markers: Marker[];
  /** Current playhead position */
  playheadPosition: number;
  /** Tempo BPM */
  tempo: number;
  /** Time signature */
  timeSignature: [number, number];
  /** On marker add */
  onMarkerAdd?: (marker: Omit<Marker, 'id'>) => void;
  /** On marker update */
  onMarkerUpdate?: (markerId: string, updates: Partial<Marker>) => void;
  /** On marker delete */
  onMarkerDelete?: (markerId: string) => void;
  /** On navigate to marker */
  onNavigate?: (position: number) => void;
  /** On set loop region */
  onSetLoop?: (start: number, end: number) => void;
  /** On close */
  onClose?: () => void;
}

// ============ Constants ============

const MARKER_COLORS = [
  '#ff6b6b',
  '#ffd43b',
  '#51cf66',
  '#4a9eff',
  '#be4bdb',
  '#20c997',
  '#ff922b',
  '#74c0fc',
];

const MARKER_TYPE_LABELS: Record<MarkerType, string> = {
  marker: 'Marker',
  region: 'Region',
  loop: 'Loop',
  punch: 'Punch',
};

// ============ Helpers ============

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 1000);
  return `${mins}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(3, '0')}`;
}

function formatBarsBeats(seconds: number, tempo: number, timeSignature: [number, number]): string {
  const beatsPerSecond = tempo / 60;
  const totalBeats = seconds * beatsPerSecond;
  const beatsPerBar = timeSignature[0];
  const bars = Math.floor(totalBeats / beatsPerBar) + 1;
  const beats = Math.floor(totalBeats % beatsPerBar) + 1;
  return `${bars}:${beats}`;
}

// ============ Component ============

export function MarkerManager({
  markers,
  playheadPosition,
  tempo,
  timeSignature,
  onMarkerAdd,
  onMarkerUpdate,
  onMarkerDelete,
  onNavigate,
  onSetLoop,
  onClose,
}: MarkerManagerProps) {
  const [filter, setFilter] = useState<MarkerType | 'all'>('all');
  const [search, setSearch] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [isAdding, setIsAdding] = useState(false);
  const [newMarker, setNewMarker] = useState<Partial<Marker>>({
    type: 'marker',
    name: '',
    color: MARKER_COLORS[0],
  });

  // Filter and sort markers
  const filteredMarkers = useMemo(() => {
    let result = markers;

    if (filter !== 'all') {
      result = result.filter((m) => m.type === filter);
    }

    if (search) {
      const lowerSearch = search.toLowerCase();
      result = result.filter(
        (m) =>
          m.name.toLowerCase().includes(lowerSearch) ||
          m.comment?.toLowerCase().includes(lowerSearch)
      );
    }

    return result.sort((a, b) => a.position - b.position);
  }, [markers, filter, search]);

  // Count by type
  const typeCounts = useMemo(() => {
    const counts: Record<string, number> = { all: markers.length };
    for (const marker of markers) {
      counts[marker.type] = (counts[marker.type] || 0) + 1;
    }
    return counts;
  }, [markers]);

  // Handle add marker
  const handleAdd = useCallback(() => {
    if (newMarker.name?.trim()) {
      onMarkerAdd?.({
        type: newMarker.type || 'marker',
        name: newMarker.name.trim(),
        color: newMarker.color || MARKER_COLORS[0],
        position: playheadPosition,
        endPosition: newMarker.type === 'region' ? playheadPosition + 10 : undefined,
        locked: false,
      });
      setIsAdding(false);
      setNewMarker({ type: 'marker', name: '', color: MARKER_COLORS[0] });
    }
  }, [newMarker, playheadPosition, onMarkerAdd]);

  // Handle rename
  const handleRename = useCallback(
    (markerId: string) => {
      if (editName.trim()) {
        onMarkerUpdate?.(markerId, { name: editName.trim() });
      }
      setEditingId(null);
      setEditName('');
    },
    [editName, onMarkerUpdate]
  );

  // Handle delete
  const handleDelete = useCallback(
    (marker: Marker) => {
      if (marker.locked) return;
      if (confirm(`Delete "${marker.name}"?`)) {
        onMarkerDelete?.(marker.id);
      }
    },
    [onMarkerDelete]
  );

  // Handle set as loop
  const handleSetLoop = useCallback(
    (marker: Marker) => {
      if (marker.type === 'region' && marker.endPosition) {
        onSetLoop?.(marker.position, marker.endPosition);
      }
    },
    [onSetLoop]
  );

  // Navigate to next/previous marker
  const navigateNext = useCallback(() => {
    const next = filteredMarkers.find((m) => m.position > playheadPosition);
    if (next) onNavigate?.(next.position);
  }, [filteredMarkers, playheadPosition, onNavigate]);

  const navigatePrevious = useCallback(() => {
    const prev = [...filteredMarkers]
      .reverse()
      .find((m) => m.position < playheadPosition - 0.1);
    if (prev) onNavigate?.(prev.position);
  }, [filteredMarkers, playheadPosition, onNavigate]);

  return (
    <div className="marker-manager">
      {/* Header */}
      <div className="marker-manager__header">
        <h2>Markers & Regions</h2>
        <div className="marker-manager__nav">
          <button
            className="marker-manager__nav-btn"
            onClick={navigatePrevious}
            title="Previous marker"
          >
            ◀
          </button>
          <button
            className="marker-manager__nav-btn"
            onClick={navigateNext}
            title="Next marker"
          >
            ▶
          </button>
        </div>
        {onClose && (
          <button className="marker-manager__close" onClick={onClose}>
            ×
          </button>
        )}
      </div>

      {/* Toolbar */}
      <div className="marker-manager__toolbar">
        <input
          type="text"
          className="marker-manager__search"
          placeholder="Search..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button
          className="marker-manager__btn primary"
          onClick={() => setIsAdding(true)}
        >
          + Add
        </button>
      </div>

      {/* Filters */}
      <div className="marker-manager__filters">
        {(['all', 'marker', 'region', 'loop', 'punch'] as const).map((type) => (
          <button
            key={type}
            className={`marker-manager__filter ${filter === type ? 'active' : ''}`}
            onClick={() => setFilter(type)}
          >
            {type === 'all' ? 'All' : MARKER_TYPE_LABELS[type]}
            <span className="marker-manager__filter-count">
              {typeCounts[type] || 0}
            </span>
          </button>
        ))}
      </div>

      {/* Add Form */}
      {isAdding && (
        <div className="marker-manager__add-form">
          <input
            type="text"
            placeholder="Marker name"
            value={newMarker.name || ''}
            onChange={(e) => setNewMarker({ ...newMarker, name: e.target.value })}
            autoFocus
          />
          <select
            value={newMarker.type}
            onChange={(e) =>
              setNewMarker({ ...newMarker, type: e.target.value as MarkerType })
            }
          >
            <option value="marker">Marker</option>
            <option value="region">Region</option>
            <option value="loop">Loop</option>
            <option value="punch">Punch</option>
          </select>
          <div className="marker-manager__color-picker">
            {MARKER_COLORS.map((color) => (
              <button
                key={color}
                className={`marker-manager__color ${
                  newMarker.color === color ? 'active' : ''
                }`}
                style={{ backgroundColor: color }}
                onClick={() => setNewMarker({ ...newMarker, color })}
              />
            ))}
          </div>
          <div className="marker-manager__add-actions">
            <button className="marker-manager__btn primary" onClick={handleAdd}>
              Add
            </button>
            <button
              className="marker-manager__btn"
              onClick={() => setIsAdding(false)}
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Marker List */}
      <div className="marker-manager__list">
        {filteredMarkers.length === 0 ? (
          <div className="marker-manager__empty">No markers found</div>
        ) : (
          filteredMarkers.map((marker) => (
            <div
              key={marker.id}
              className={`marker-manager__item ${marker.locked ? 'locked' : ''}`}
              onClick={() => onNavigate?.(marker.position)}
            >
              <span
                className="marker-manager__item-color"
                style={{ backgroundColor: marker.color }}
              />
              <span className="marker-manager__item-type">
                {MARKER_TYPE_LABELS[marker.type]}
              </span>

              {editingId === marker.id ? (
                <input
                  type="text"
                  className="marker-manager__edit-input"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onBlur={() => handleRename(marker.id)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleRename(marker.id);
                    if (e.key === 'Escape') setEditingId(null);
                  }}
                  autoFocus
                  onClick={(e) => e.stopPropagation()}
                />
              ) : (
                <span
                  className="marker-manager__item-name"
                  onDoubleClick={(e) => {
                    e.stopPropagation();
                    if (!marker.locked) {
                      setEditingId(marker.id);
                      setEditName(marker.name);
                    }
                  }}
                >
                  {marker.name}
                </span>
              )}

              <span className="marker-manager__item-time">
                {formatTime(marker.position)}
              </span>
              <span className="marker-manager__item-bars">
                {formatBarsBeats(marker.position, tempo, timeSignature)}
              </span>

              {marker.endPosition && (
                <span className="marker-manager__item-duration">
                  → {formatTime(marker.endPosition)}
                </span>
              )}

              <div className="marker-manager__item-actions">
                {marker.type === 'region' && marker.endPosition && (
                  <button
                    className="marker-manager__item-btn"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleSetLoop(marker);
                    }}
                    title="Set as loop region"
                  >
                    🔁
                  </button>
                )}
                <button
                  className={`marker-manager__item-btn ${marker.locked ? 'active' : ''}`}
                  onClick={(e) => {
                    e.stopPropagation();
                    onMarkerUpdate?.(marker.id, { locked: !marker.locked });
                  }}
                  title={marker.locked ? 'Unlock' : 'Lock'}
                >
                  {marker.locked ? '🔒' : '🔓'}
                </button>
                {!marker.locked && (
                  <button
                    className="marker-manager__item-btn delete"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDelete(marker);
                    }}
                    title="Delete"
                  >
                    ×
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Footer */}
      <div className="marker-manager__footer">
        <span>{filteredMarkers.length} items</span>
        <span className="marker-manager__playhead">
          Playhead: {formatTime(playheadPosition)}
        </span>
      </div>
    </div>
  );
}

export default MarkerManager;

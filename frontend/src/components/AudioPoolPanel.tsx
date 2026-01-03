/**
 * AudioPoolPanel Component
 *
 * Cubase Pool-inspired audio asset management panel:
 * - View all imported audio files
 * - Used/Unused status tracking
 * - Local vs External (referenced) indication
 * - Replace file functionality
 * - Consolidate (copy all external to project)
 * - Remove unused files
 *
 * @module components/AudioPoolPanel
 */

import { useState, useCallback, useMemo, useEffect, memo } from 'react';
import './AudioPoolPanel.css';
import { useDraggable, type DragItem } from '../core/dragDropSystem';

// ============ Types ============

export type AssetStatus = 'used' | 'unused' | 'missing';
export type AssetLocation = 'local' | 'external';

export interface PoolAsset {
  /** Unique ID */
  id: string;
  /** File name */
  name: string;
  /** Full path (for external files) */
  path?: string;
  /** Duration in seconds */
  duration: number;
  /** Sample rate */
  sampleRate: number;
  /** Number of channels */
  channels: number;
  /** File format */
  format: string;
  /** File size in bytes */
  size: number;
  /** Waveform data */
  waveform?: number[];
  /** Usage status */
  status: AssetStatus;
  /** Location (local in project or external reference) */
  location: AssetLocation;
  /** Number of times used in project */
  usageCount: number;
  /** Where it's used (event names) */
  usedIn?: string[];
  /** Date added */
  dateAdded: Date;
  /** Detected BPM (tempo) */
  bpm?: number;
  /** BPM detection confidence (0-1) */
  bpmConfidence?: number;
  /** Musical key (e.g., "Am", "C") */
  key?: string;
  /** Number of bars in loop */
  loopBars?: number;
}

export interface AudioPoolPanelProps {
  /** Assets in the pool */
  assets: PoolAsset[];
  /** Called when user wants to replace a file */
  onReplace?: (assetId: string) => void;
  /** Called when user removes assets */
  onRemove?: (assetIds: string[]) => void;
  /** Called to consolidate external files */
  onConsolidate?: () => void;
  /** Called to remove unused files */
  onRemoveUnused?: () => void;
  /** Called when asset is selected */
  onSelect?: (asset: PoolAsset) => void;
  /** Called when asset is double-clicked (preview) */
  onPreview?: (asset: PoolAsset) => void;
  /** Custom class */
  className?: string;
}

// ============ Utilities ============

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 100);
  return `${mins}:${secs.toString().padStart(2, '0')}.${ms.toString().padStart(2, '0')}`;
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatSampleRate(sr: number): string {
  return `${(sr / 1000).toFixed(1)}k`;
}

// ============ Draggable Row Component ============

interface DraggablePoolRowProps {
  asset: PoolAsset;
  isSelected: boolean;
  onSelect: (id: string, e: React.MouseEvent) => void;
  onDoubleClick: (asset: PoolAsset) => void;
  onContextMenu: (e: React.MouseEvent, id: string) => void;
  getStatusIcon: (status: AssetStatus) => string;
}

const DraggablePoolRow = memo(function DraggablePoolRow({
  asset,
  isSelected,
  onSelect,
  onDoubleClick,
  onContextMenu,
  getStatusIcon,
}: DraggablePoolRowProps) {
  // Create drag item for timeline drop
  const dragItem: DragItem = {
    type: 'audio-asset',
    id: `audio-${asset.id}`,
    label: asset.name,
    data: {
      duration: asset.duration,
      waveform: asset.waveform,
      sampleRate: asset.sampleRate,
      channels: asset.channels,
    },
  };

  const { isDragging, dragHandlers } = useDraggable(dragItem);

  return (
    <div
      {...dragHandlers}
      className={`rf-audio-pool__row ${isSelected ? 'selected' : ''} ${
        asset.status === 'unused' ? 'unused' : ''
      } ${asset.location === 'external' ? 'external' : ''} ${
        isDragging ? 'dragging' : ''
      }`}
      onClick={(e) => onSelect(asset.id, e)}
      onDoubleClick={() => onDoubleClick(asset)}
      onContextMenu={(e) => onContextMenu(e, asset.id)}
    >
      <div className={`rf-audio-pool__status rf-audio-pool__status--${asset.status}`}>
        {getStatusIcon(asset.status)}
      </div>
      <div className="rf-audio-pool__name">
        <span className={`rf-audio-pool__name-icon ${asset.location === 'external' ? 'external' : ''}`}>
          {asset.location === 'external' ? '🔗' : '📄'}
        </span>
        <span className="rf-audio-pool__name-text" title={asset.path || asset.name}>
          {asset.name}
        </span>
      </div>
      <span className="rf-audio-pool__meta rf-audio-pool__meta--duration">
        {formatDuration(asset.duration)}
      </span>
      <span className="rf-audio-pool__meta">
        {formatSampleRate(asset.sampleRate)}
      </span>
      <span className="rf-audio-pool__meta">
        {formatFileSize(asset.size)}
      </span>
      <span className="rf-audio-pool__meta">
        {asset.channels === 1 ? 'M' : 'S'}
      </span>
      <span className={`rf-audio-pool__meta rf-audio-pool__meta--bpm ${asset.bpm ? '' : 'no-bpm'}`}>
        {asset.bpm ? (
          <span title={`${asset.bpm} BPM (${Math.round((asset.bpmConfidence ?? 0) * 100)}% confidence)${asset.loopBars ? `, ${asset.loopBars} bars` : ''}`}>
            {asset.bpm}
          </span>
        ) : (
          <span title="No BPM detected">—</span>
        )}
      </span>
      <div className="rf-audio-pool__usage">
        <span className={`rf-audio-pool__usage-count ${asset.usageCount === 0 ? 'zero' : ''}`}>
          {asset.usageCount}×
        </span>
      </div>
    </div>
  );
});

// ============ Main Component ============

type SortField = 'name' | 'duration' | 'size' | 'sampleRate' | 'status' | 'usage' | 'bpm';
type SortDirection = 'asc' | 'desc';

export function AudioPoolPanel({
  assets,
  onReplace,
  onRemove,
  onConsolidate,
  onRemoveUnused,
  onSelect,
  onPreview,
  className = '',
}: AudioPoolPanelProps) {
  // State
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    assetId: string;
  } | null>(null);

  // Close context menu on click outside
  useEffect(() => {
    const handleClick = () => setContextMenu(null);
    document.addEventListener('click', handleClick);
    return () => document.removeEventListener('click', handleClick);
  }, []);

  // Stats
  const stats = useMemo(() => {
    const used = assets.filter(a => a.status === 'used').length;
    const unused = assets.filter(a => a.status === 'unused').length;
    const external = assets.filter(a => a.location === 'external').length;
    const totalSize = assets.reduce((sum, a) => sum + a.size, 0);

    return { total: assets.length, used, unused, external, totalSize };
  }, [assets]);

  // Filter and sort assets
  const filteredAssets = useMemo(() => {
    let result = assets;

    // Search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      result = result.filter(a => a.name.toLowerCase().includes(query));
    }

    // Sort
    result = [...result].sort((a, b) => {
      let comparison = 0;

      switch (sortField) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'duration':
          comparison = a.duration - b.duration;
          break;
        case 'size':
          comparison = a.size - b.size;
          break;
        case 'sampleRate':
          comparison = a.sampleRate - b.sampleRate;
          break;
        case 'status':
          comparison = a.status.localeCompare(b.status);
          break;
        case 'usage':
          comparison = a.usageCount - b.usageCount;
          break;
        case 'bpm':
          // Sort by BPM, files without BPM go to the end
          const aBpm = a.bpm ?? (sortDirection === 'asc' ? Infinity : -Infinity);
          const bBpm = b.bpm ?? (sortDirection === 'asc' ? Infinity : -Infinity);
          comparison = aBpm - bBpm;
          break;
      }

      return sortDirection === 'asc' ? comparison : -comparison;
    });

    return result;
  }, [assets, searchQuery, sortField, sortDirection]);

  // Handle sort
  const handleSort = useCallback((field: SortField) => {
    if (sortField === field) {
      setSortDirection(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  }, [sortField]);

  // Handle selection
  const handleSelect = useCallback((id: string, event: React.MouseEvent) => {
    const asset = assets.find(a => a.id === id);

    setSelectedIds(prev => {
      const next = new Set(prev);

      if (event.ctrlKey || event.metaKey) {
        if (next.has(id)) {
          next.delete(id);
        } else {
          next.add(id);
        }
      } else if (event.shiftKey && prev.size > 0) {
        const assetIds = filteredAssets.map(a => a.id);
        const lastSelected = Array.from(prev).pop()!;
        const lastIdx = assetIds.indexOf(lastSelected);
        const currentIdx = assetIds.indexOf(id);
        const start = Math.min(lastIdx, currentIdx);
        const end = Math.max(lastIdx, currentIdx);

        for (let i = start; i <= end; i++) {
          next.add(assetIds[i]);
        }
      } else {
        next.clear();
        next.add(id);
      }

      return next;
    });

    if (asset) {
      onSelect?.(asset);
    }
  }, [assets, filteredAssets, onSelect]);

  // Handle double click
  const handleDoubleClick = useCallback((asset: PoolAsset) => {
    onPreview?.(asset);
  }, [onPreview]);

  // Handle context menu
  const handleContextMenu = useCallback((e: React.MouseEvent, assetId: string) => {
    e.preventDefault();
    setContextMenu({ x: e.clientX, y: e.clientY, assetId });

    // Also select the item
    if (!selectedIds.has(assetId)) {
      setSelectedIds(new Set([assetId]));
    }
  }, [selectedIds]);

  // Handle remove
  const handleRemove = useCallback(() => {
    const ids = Array.from(selectedIds);
    if (ids.length > 0) {
      onRemove?.(ids);
      setSelectedIds(new Set());
    }
    setContextMenu(null);
  }, [selectedIds, onRemove]);

  // Handle replace
  const handleReplace = useCallback(() => {
    if (contextMenu) {
      onReplace?.(contextMenu.assetId);
    }
    setContextMenu(null);
  }, [contextMenu, onReplace]);

  // Status icon
  const getStatusIcon = (status: AssetStatus) => {
    switch (status) {
      case 'used': return '✓';
      case 'unused': return '○';
      case 'missing': return '⚠';
    }
  };

  return (
    <div className={`rf-audio-pool ${className}`}>
      {/* Header */}
      <div className="rf-audio-pool__header">
        <div className="rf-audio-pool__title">Audio Pool</div>
        <div className="rf-audio-pool__actions">
          {stats.external > 0 && (
            <button
              className="rf-audio-pool__action-btn"
              onClick={onConsolidate}
              title="Copy all external files to project"
            >
              Consolidate
            </button>
          )}
          {stats.unused > 0 && (
            <button
              className="rf-audio-pool__action-btn rf-audio-pool__action-btn--danger"
              onClick={onRemoveUnused}
              title="Remove files not used in project"
            >
              Remove Unused
            </button>
          )}
        </div>
      </div>

      {/* Toolbar */}
      <div className="rf-audio-pool__toolbar">
        <div className="rf-audio-pool__search">
          <input
            type="text"
            className="rf-audio-pool__search-input"
            placeholder="Search files..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
      </div>

      {/* Stats */}
      <div className="rf-audio-pool__stats">
        <div className="rf-audio-pool__stat">
          <span>Total:</span>
          <span className="rf-audio-pool__stat-value">{stats.total} files</span>
        </div>
        <div className="rf-audio-pool__stat rf-audio-pool__stat--used">
          <span>Used:</span>
          <span className="rf-audio-pool__stat-value">{stats.used}</span>
        </div>
        <div className="rf-audio-pool__stat rf-audio-pool__stat--unused">
          <span>Unused:</span>
          <span className="rf-audio-pool__stat-value">{stats.unused}</span>
        </div>
        {stats.external > 0 && (
          <div className="rf-audio-pool__stat rf-audio-pool__stat--external">
            <span>External:</span>
            <span className="rf-audio-pool__stat-value">{stats.external}</span>
          </div>
        )}
        <div className="rf-audio-pool__stat">
          <span>Size:</span>
          <span className="rf-audio-pool__stat-value">{formatFileSize(stats.totalSize)}</span>
        </div>
      </div>

      {/* Table */}
      <div className="rf-audio-pool__table">
        <div className="rf-audio-pool__table-header">
          <span></span>
          <span
            className={sortField === 'name' ? 'sorted' : ''}
            onClick={() => handleSort('name')}
          >
            Name {sortField === 'name' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
          <span
            className={sortField === 'duration' ? 'sorted' : ''}
            onClick={() => handleSort('duration')}
          >
            Duration {sortField === 'duration' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
          <span
            className={sortField === 'sampleRate' ? 'sorted' : ''}
            onClick={() => handleSort('sampleRate')}
          >
            Rate {sortField === 'sampleRate' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
          <span
            className={sortField === 'size' ? 'sorted' : ''}
            onClick={() => handleSort('size')}
          >
            Size {sortField === 'size' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
          <span>Ch</span>
          <span
            className={sortField === 'bpm' ? 'sorted' : ''}
            onClick={() => handleSort('bpm')}
          >
            BPM {sortField === 'bpm' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
          <span
            className={sortField === 'usage' ? 'sorted' : ''}
            onClick={() => handleSort('usage')}
          >
            Used {sortField === 'usage' && (sortDirection === 'asc' ? '↑' : '↓')}
          </span>
        </div>

        <div className="rf-audio-pool__table-body">
          {filteredAssets.length === 0 ? (
            <div className="rf-audio-pool__empty">
              <div className="rf-audio-pool__empty-icon">📁</div>
              <div className="rf-audio-pool__empty-text">
                {searchQuery ? 'No matching files' : 'No audio files in pool'}
              </div>
            </div>
          ) : (
            filteredAssets.map(asset => (
              <DraggablePoolRow
                key={asset.id}
                asset={asset}
                isSelected={selectedIds.has(asset.id)}
                onSelect={handleSelect}
                onDoubleClick={handleDoubleClick}
                onContextMenu={handleContextMenu}
                getStatusIcon={getStatusIcon}
              />
            ))
          )}
        </div>
      </div>

      {/* Context Menu */}
      {contextMenu && (
        <div
          className="rf-audio-pool__context-menu"
          style={{ left: contextMenu.x, top: contextMenu.y }}
          onClick={e => e.stopPropagation()}
        >
          <div className="rf-audio-pool__context-item" onClick={() => {
            const asset = assets.find(a => a.id === contextMenu.assetId);
            if (asset) handleDoubleClick(asset);
            setContextMenu(null);
          }}>
            ▶ Preview
          </div>
          <div className="rf-audio-pool__context-item" onClick={handleReplace}>
            🔄 Replace...
          </div>
          <div className="rf-audio-pool__context-separator" />
          <div className="rf-audio-pool__context-item" onClick={() => {
            const asset = assets.find(a => a.id === contextMenu.assetId);
            if (asset?.usedIn && asset.usedIn.length > 0) {
              console.log('Used in:', asset.usedIn);
            }
            setContextMenu(null);
          }}>
            📍 Show Usage
          </div>
          {assets.find(a => a.id === contextMenu.assetId)?.location === 'external' && (
            <div className="rf-audio-pool__context-item" onClick={() => {
              // Copy to project
              setContextMenu(null);
            }}>
              📦 Copy to Project
            </div>
          )}
          <div className="rf-audio-pool__context-separator" />
          <div
            className="rf-audio-pool__context-item rf-audio-pool__context-item--danger"
            onClick={handleRemove}
          >
            🗑️ Remove from Pool
          </div>
        </div>
      )}
    </div>
  );
}

export default AudioPoolPanel;

/**
 * ReelForge Left Zone (Project Explorer + Channel)
 *
 * Two-tab layout:
 * - Project Explorer: Wwise-style project hierarchy browser
 * - Channel: Cubase-style channel strip for selected track
 *
 * @module layout/LeftZone
 */

import { memo, useState, useCallback, useMemo } from 'react';
import { useDraggable, useDropTarget, type DragItem, type DropTarget } from '../core/dragDropSystem';
import type { ChannelStripData, InsertSlot, EQBand } from './ChannelStrip';

// ============ Types ============

export type TreeItemType = 'folder' | 'event' | 'sound' | 'bus' | 'state' | 'switch' | 'rtpc' | 'music';

export interface TreeNode {
  id: string;
  type: TreeItemType;
  label: string;
  children?: TreeNode[];
  count?: number;
  data?: unknown;
}

export type LeftZoneTab = 'project' | 'channel';

export interface LeftZoneProps {
  /** Whether zone is collapsed */
  collapsed?: boolean;
  /** Tree data */
  tree: TreeNode[];
  /** Selected item ID */
  selectedId?: string | null;
  /** On item select */
  onSelect?: (id: string, type: TreeItemType, data?: unknown) => void;
  /** On item double-click */
  onDoubleClick?: (id: string, type: TreeItemType, data?: unknown) => void;
  /** Search query */
  searchQuery?: string;
  /** On search change */
  onSearchChange?: (query: string) => void;
  /** On add click */
  onAdd?: (type: TreeItemType) => void;
  /** On collapse toggle */
  onToggleCollapse?: () => void;
  /** On event reorder (drag & drop) */
  onEventReorder?: (draggedId: string, targetId: string, position: 'before' | 'after') => void;

  // Channel Strip props (for Channel tab)
  /** Active tab */
  activeTab?: LeftZoneTab;
  /** On tab change */
  onTabChange?: (tab: LeftZoneTab) => void;
  /** Selected channel data */
  channelData?: ChannelStripData | null;
  /** Volume change */
  onChannelVolumeChange?: (channelId: string, volume: number) => void;
  /** Pan change */
  onChannelPanChange?: (channelId: string, pan: number) => void;
  /** Mute toggle */
  onChannelMuteToggle?: (channelId: string) => void;
  /** Solo toggle */
  onChannelSoloToggle?: (channelId: string) => void;
  /** Insert click (open plugin browser) */
  onChannelInsertClick?: (channelId: string, slotIndex: number) => void;
  /** Send level change */
  onChannelSendLevelChange?: (channelId: string, sendIndex: number, level: number) => void;
  /** EQ toggle */
  onChannelEQToggle?: (channelId: string) => void;
  /** Output routing click */
  onChannelOutputClick?: (channelId: string) => void;
}

// ============ Icon Map ============

const ICONS: Record<TreeItemType, string> = {
  folder: '📁',
  event: '🎯',
  sound: '🔊',
  bus: '🔈',
  state: '🏷️',
  switch: '🔀',
  rtpc: '📊',
  music: '🎵',
};

// ============ Tree Item ============

interface TreeItemProps {
  node: TreeNode;
  level: number;
  selectedId?: string | null;
  expandedIds: Set<string>;
  onToggle: (id: string) => void;
  onSelect: (id: string, type: TreeItemType, data?: unknown) => void;
  onDoubleClick?: (id: string, type: TreeItemType, data?: unknown) => void;
  searchQuery?: string;
  onEventReorder?: (draggedId: string, targetId: string, position: 'before' | 'after') => void;
}

const TreeItem = memo(function TreeItem({
  node,
  level,
  selectedId,
  expandedIds,
  onToggle,
  onSelect,
  onDoubleClick,
  searchQuery,
  onEventReorder,
}: TreeItemProps) {
  const [dropPosition, setDropPosition] = useState<'before' | 'after' | null>(null);
  const hasChildren = node.children && node.children.length > 0;
  const isExpanded = expandedIds.has(node.id);
  const isSelected = selectedId === node.id;

  // Draggable for sound/music/event items
  const isDraggableType = node.type === 'sound' || node.type === 'music' || node.type === 'event';
  const dragItem: DragItem = {
    type: node.type === 'event' ? 'event' : 'audio-asset',
    id: node.id,
    label: node.label,
    data: { nodeType: node.type, ...((node.data as object) || {}) },
  };
  const { isDragging, dragHandlers } = useDraggable(dragItem);

  // Drop target for event reordering
  const isDroppable = node.type === 'event' && onEventReorder;
  const dropTarget: DropTarget = {
    id: `event-drop-${node.id}`,
    type: 'event-reorder',
    accepts: ['event'],
  };

  const handleEventDrop = useCallback((item: DragItem, _target: DropTarget) => {
    if (item.id !== node.id && dropPosition && onEventReorder) {
      onEventReorder(item.id, node.id, dropPosition);
    }
    setDropPosition(null);
  }, [node.id, dropPosition, onEventReorder]);

  const { ref: dropRef, isOver } = useDropTarget(dropTarget, handleEventDrop);

  // Filter children if searching
  const visibleChildren = useMemo(() => {
    if (!node.children) return [];
    if (!searchQuery) return node.children;

    const query = searchQuery.toLowerCase();
    return node.children.filter(
      (child) =>
        child.label.toLowerCase().includes(query) ||
        (child.children && child.children.some((c) => c.label.toLowerCase().includes(query)))
    );
  }, [node.children, searchQuery]);

  // Match highlight
  const matchesSearch = searchQuery && node.label.toLowerCase().includes(searchQuery.toLowerCase());

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (hasChildren) {
        onToggle(node.id);
      }
      onSelect(node.id, node.type, node.data);
    },
    [node, hasChildren, onToggle, onSelect]
  );

  const handleDoubleClick = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onDoubleClick?.(node.id, node.type, node.data);
    },
    [node, onDoubleClick]
  );

  // Determine drop position based on mouse Y within element
  const handleDragOver = useCallback((e: React.DragEvent) => {
    if (!isDroppable || !isOver) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const y = e.clientY - rect.top;
    const midpoint = rect.height / 2;
    setDropPosition(y < midpoint ? 'before' : 'after');
  }, [isDroppable, isOver]);

  const handleDragLeave = useCallback(() => {
    setDropPosition(null);
  }, []);

  // Get the actual ref for the element
  const elementRef = isDroppable ? dropRef : undefined;

  return (
    <>
      <div
        ref={elementRef as React.Ref<HTMLDivElement>}
        className={`rf-tree-item ${isSelected ? 'selected' : ''} ${isDragging ? 'dragging' : ''} ${isDraggableType ? 'draggable' : ''} ${isOver && isDroppable ? 'drop-target' : ''} ${dropPosition ? `drop-${dropPosition}` : ''}`}
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        style={{ paddingLeft: 12 + level * 16, opacity: isDragging ? 0.5 : 1 }}
        {...(isDraggableType ? dragHandlers : {})}
      >
        {/* Expand Arrow */}
        {hasChildren ? (
          <span className={`rf-tree-item__expand ${isExpanded ? 'expanded' : ''}`}>
            ▶
          </span>
        ) : (
          <span className="rf-tree-item__indent" />
        )}

        {/* Icon */}
        <span className={`rf-tree-item__icon rf-tree-item__icon--${node.type}`}>
          {ICONS[node.type]}
        </span>

        {/* Label */}
        <span
          className="rf-tree-item__label"
          style={matchesSearch ? { color: 'var(--rf-accent-primary)' } : undefined}
        >
          {node.label}
        </span>

        {/* Count Badge */}
        {node.count !== undefined && node.count > 0 && (
          <span className="rf-tree-item__count">{node.count}</span>
        )}
      </div>

      {/* Children */}
      {hasChildren && isExpanded && (
        <>
          {visibleChildren.map((child) => (
            <TreeItem
              key={child.id}
              node={child}
              level={level + 1}
              selectedId={selectedId}
              expandedIds={expandedIds}
              onToggle={onToggle}
              onSelect={onSelect}
              onDoubleClick={onDoubleClick}
              searchQuery={searchQuery}
              onEventReorder={onEventReorder}
            />
          ))}
        </>
      )}
    </>
  );
});

// ============ Channel Strip Panel (Cubase/Pro Tools style) ============

interface ChannelPanelProps {
  channel: ChannelStripData | null;
  onVolumeChange?: (channelId: string, volume: number) => void;
  onPanChange?: (channelId: string, pan: number) => void;
  onMuteToggle?: (channelId: string) => void;
  onSoloToggle?: (channelId: string) => void;
  onInsertClick?: (channelId: string, slotIndex: number) => void;
  onSendLevelChange?: (channelId: string, sendIndex: number, level: number) => void;
  onEQToggle?: (channelId: string) => void;
  onOutputClick?: (channelId: string) => void;
}

const ChannelPanel = memo(function ChannelPanel({
  channel,
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onInsertClick,
  onSendLevelChange,
  onEQToggle,
  onOutputClick,
}: ChannelPanelProps) {
  // Format dB value
  const formatDb = (db: number) => {
    if (db <= -60) return '-∞';
    return db >= 0 ? `+${db.toFixed(1)}` : db.toFixed(1);
  };

  // Format pan
  const formatPan = (v: number) => {
    if (v === 0) return 'C';
    return v < 0 ? `L${Math.abs(v)}` : `R${v}`;
  };

  const TYPE_ICONS: Record<string, string> = {
    audio: '🎵',
    instrument: '🎹',
    bus: '🔈',
    fx: '🎛️',
    master: '🔊',
  };

  if (!channel) {
    return (
      <div className="rf-channel-panel rf-scrollbar">
        <div className="rf-channel-panel__empty">
          <span className="rf-channel-panel__empty-icon">🎚️</span>
          <span>Select a track to view channel</span>
        </div>
      </div>
    );
  }

  // Calculate fader position (inverted for visual)
  const faderPercentage = ((channel.volume - (-60)) / (12 - (-60))) * 100;
  const meterL = channel.meterL * 100;
  const meterR = channel.meterR * 100;

  return (
    <div className="rf-channel-panel rf-scrollbar">
      {/* Channel Header */}
      <div
        className="rf-channel-panel__header"
        style={{ borderLeftColor: channel.color || 'var(--rf-accent-primary)' }}
      >
        <span className="rf-channel-panel__icon">{TYPE_ICONS[channel.type] || '🎵'}</span>
        <span className="rf-channel-panel__name">{channel.name}</span>
        <span className="rf-channel-panel__type">{channel.type.toUpperCase()}</span>
      </div>

      {/* I/O Section */}
      <div className="rf-channel-panel__section">
        <div className="rf-channel-panel__section-header">I/O</div>
        <div className="rf-channel-panel__io">
          <div className="rf-channel-panel__io-row">
            <span className="rf-channel-panel__io-label">In</span>
            <button className="rf-channel-panel__io-btn">{channel.input}</button>
          </div>
          <div className="rf-channel-panel__io-row">
            <span className="rf-channel-panel__io-label">Out</span>
            <button
              className="rf-channel-panel__io-btn"
              onClick={() => onOutputClick?.(channel.id)}
            >
              {channel.output}
              <span className="rf-channel-panel__io-arrow">▼</span>
            </button>
          </div>
        </div>
      </div>

      {/* Inserts Section */}
      <div className="rf-channel-panel__section">
        <div className="rf-channel-panel__section-header">
          Inserts
          <span className="rf-channel-panel__section-count">
            {channel.inserts.filter((i: InsertSlot) => i.pluginName).length}/8
          </span>
        </div>
        <div className="rf-channel-panel__inserts">
          {channel.inserts.slice(0, 8).map((insert: InsertSlot, i: number) => (
            <div
              key={insert.id}
              className={`rf-channel-panel__insert ${insert.pluginName ? 'rf-channel-panel__insert--active' : ''} ${insert.bypassed ? 'rf-channel-panel__insert--bypassed' : ''}`}
              onClick={() => onInsertClick?.(channel.id, i)}
            >
              <button
                className={`rf-channel-panel__insert-power ${insert.pluginName && !insert.bypassed ? 'active' : ''}`}
                onClick={(e) => {
                  e.stopPropagation();
                  // Toggle bypass would go here
                }}
              >
                <span className="rf-channel-panel__insert-power-dot" />
              </button>
              <span className="rf-channel-panel__insert-name">
                {insert.pluginName || `Insert ${i + 1}`}
              </span>
              <span className="rf-channel-panel__insert-arrow">▼</span>
            </div>
          ))}
        </div>
      </div>

      {/* EQ Section */}
      <div className="rf-channel-panel__section">
        <div className="rf-channel-panel__section-header">
          Equalizer
          <button
            className={`rf-channel-panel__section-toggle ${channel.eqEnabled ? 'active' : ''}`}
            onClick={() => onEQToggle?.(channel.id)}
          >
            {channel.eqEnabled ? 'ON' : 'OFF'}
          </button>
        </div>
        <div className="rf-channel-panel__eq">
          <svg viewBox="0 0 200 60" className="rf-channel-panel__eq-curve">
            {/* Grid */}
            <line x1="0" y1="30" x2="200" y2="30" stroke="var(--rf-border)" strokeWidth="1" />
            {[25, 50, 75, 100, 125, 150, 175].map(x => (
              <line key={x} x1={x} y1="0" x2={x} y2="60" stroke="var(--rf-border)" strokeWidth="0.5" opacity="0.3" />
            ))}
            {/* Curve - simplified */}
            <path
              d={generateEQPath(channel.eqBands, channel.eqEnabled)}
              fill="none"
              stroke={channel.eqEnabled ? 'var(--rf-accent-primary)' : 'var(--rf-text-tertiary)'}
              strokeWidth="2"
            />
            {/* Band dots */}
            {channel.eqEnabled && channel.eqBands.filter((b: EQBand) => b.enabled).map((band: EQBand, i: number) => {
              const x = freqToX(band.frequency, 200);
              const y = 30 - (band.gain * 1.5);
              return (
                <circle
                  key={i}
                  cx={x}
                  cy={Math.max(5, Math.min(55, y))}
                  r="4"
                  fill="var(--rf-accent-primary)"
                />
              );
            })}
          </svg>
        </div>
      </div>

      {/* Sends Section */}
      <div className="rf-channel-panel__section">
        <div className="rf-channel-panel__section-header">
          Sends
          <span className="rf-channel-panel__section-count">
            {channel.sends.filter(s => s.destination).length}/8
          </span>
        </div>
        <div className="rf-channel-panel__sends">
          {channel.sends.slice(0, 8).map((send, i) => (
            <div
              key={send.id}
              className={`rf-channel-panel__send ${send.destination ? 'rf-channel-panel__send--active' : ''} ${send.bypassed ? 'rf-channel-panel__send--bypassed' : ''}`}
            >
              <button
                className={`rf-channel-panel__send-power ${send.destination && !send.bypassed ? 'active' : ''}`}
              >
                <span className="rf-channel-panel__send-power-dot" />
              </button>
              <span className="rf-channel-panel__send-dest">
                {send.destination || `Send ${i + 1}`}
              </span>
              {send.destination && (
                <>
                  <input
                    type="range"
                    min={-60}
                    max={6}
                    step={0.5}
                    value={send.level}
                    onChange={(e) => onSendLevelChange?.(channel.id, i, parseFloat(e.target.value))}
                    className="rf-channel-panel__send-fader"
                  />
                  <span className="rf-channel-panel__send-db">{formatDb(send.level)}</span>
                  {send.preFader && <span className="rf-channel-panel__send-pre">PRE</span>}
                </>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Fader Section - Main */}
      <div className="rf-channel-panel__section rf-channel-panel__section--fader">
        <div className="rf-channel-panel__section-header">Fader</div>

        {/* Mute/Solo */}
        <div className="rf-channel-panel__controls">
          <button
            className={`rf-channel-panel__btn rf-channel-panel__btn--mute ${channel.mute ? 'active' : ''}`}
            onClick={() => onMuteToggle?.(channel.id)}
          >
            M
          </button>
          <button
            className={`rf-channel-panel__btn rf-channel-panel__btn--solo ${channel.solo ? 'active' : ''}`}
            onClick={() => onSoloToggle?.(channel.id)}
          >
            S
          </button>
        </div>

        {/* Pan */}
        <div className="rf-channel-panel__pan">
          <span className="rf-channel-panel__pan-label">Pan</span>
          <input
            type="range"
            min={-100}
            max={100}
            step={1}
            value={channel.pan}
            onChange={(e) => onPanChange?.(channel.id, parseInt(e.target.value))}
            onDoubleClick={() => onPanChange?.(channel.id, 0)}
            className="rf-channel-panel__pan-slider"
          />
          <span className="rf-channel-panel__pan-value">{formatPan(channel.pan)}</span>
        </div>

        {/* Fader + Meters */}
        <div className="rf-channel-panel__fader-area">
          {/* Meters */}
          <div className="rf-channel-panel__meters">
            <div className="rf-channel-panel__meter">
              <div className="rf-channel-panel__meter-fill" style={{ height: `${meterL}%` }} />
              <div className="rf-channel-panel__meter-peak" style={{ bottom: `${channel.peakL * 100}%` }} />
            </div>
            <div className="rf-channel-panel__meter">
              <div className="rf-channel-panel__meter-fill" style={{ height: `${meterR}%` }} />
              <div className="rf-channel-panel__meter-peak" style={{ bottom: `${channel.peakR * 100}%` }} />
            </div>
          </div>

          {/* Fader Track */}
          <div className="rf-channel-panel__fader">
            <div className="rf-channel-panel__fader-scale">
              <span>+12</span>
              <span>+6</span>
              <span>0</span>
              <span>-6</span>
              <span>-12</span>
              <span>-24</span>
              <span>-∞</span>
            </div>
            <div className="rf-channel-panel__fader-track">
              <div
                className="rf-channel-panel__fader-thumb"
                style={{ bottom: `${faderPercentage}%` }}
              />
              <div className="rf-channel-panel__fader-unity" />
              <input
                type="range"
                min={-60}
                max={12}
                step={0.1}
                value={channel.volume}
                onChange={(e) => onVolumeChange?.(channel.id, parseFloat(e.target.value))}
                onDoubleClick={() => onVolumeChange?.(channel.id, 0)}
                className="rf-channel-panel__fader-input"
              />
            </div>
          </div>

          {/* dB Readout */}
          <div className="rf-channel-panel__db-readout">
            {formatDb(channel.volume)} dB
          </div>
        </div>
      </div>
    </div>
  );
});

// Helper: Generate EQ curve path
function generateEQPath(bands: EQBand[], enabled: boolean): string {
  if (!enabled || bands.length === 0) return 'M 0 30 L 200 30';

  let path = 'M 0 30';
  const width = 200;
  const midY = 30;

  for (let x = 0; x <= width; x += 2) {
    const freq = 20 * Math.pow(1000, x / width);
    let y = midY;

    for (const band of bands) {
      if (!band.enabled) continue;
      const dist = Math.abs(Math.log10(freq) - Math.log10(band.frequency));
      const influence = Math.exp(-dist * band.q * 0.5);
      y -= band.gain * influence * 1.5;
    }

    path += ` L ${x} ${Math.max(5, Math.min(55, y))}`;
  }

  return path;
}

// Helper: Frequency to X position
function freqToX(freq: number, width: number): number {
  return (Math.log10(freq / 20) / Math.log10(1000)) * width;
}

// ============ Left Zone Component ============

export const LeftZone = memo(function LeftZone({
  collapsed = false,
  tree,
  selectedId,
  onSelect,
  onDoubleClick,
  searchQuery = '',
  onSearchChange,
  onAdd,
  onToggleCollapse,
  onEventReorder,
  // Tab props
  activeTab = 'project',
  onTabChange,
  // Channel props
  channelData,
  onChannelVolumeChange,
  onChannelPanChange,
  onChannelMuteToggle,
  onChannelSoloToggle,
  onChannelInsertClick,
  onChannelSendLevelChange,
  onChannelEQToggle,
  onChannelOutputClick,
}: LeftZoneProps) {
  const [internalActiveTab, setInternalActiveTab] = useState<LeftZoneTab>('project');
  const [expandedIds, setExpandedIds] = useState<Set<string>>(
    () => new Set(tree.map((node) => node.id)) // Expand root by default
  );

  // Use external or internal tab state
  const currentTab = onTabChange ? activeTab : internalActiveTab;
  const handleTabChange = useCallback((tab: LeftZoneTab) => {
    if (onTabChange) {
      onTabChange(tab);
    } else {
      setInternalActiveTab(tab);
    }
  }, [onTabChange]);

  const handleToggle = useCallback((id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleSelect = useCallback(
    (id: string, type: TreeItemType, data?: unknown) => {
      onSelect?.(id, type, data);
    },
    [onSelect]
  );

  // Filter tree for search
  const filteredTree = useMemo(() => {
    if (!searchQuery) return tree;

    const query = searchQuery.toLowerCase();
    const filterNode = (node: TreeNode): TreeNode | null => {
      const matches = node.label.toLowerCase().includes(query);
      const filteredChildren = node.children
        ?.map(filterNode)
        .filter((n): n is TreeNode => n !== null);

      if (matches || (filteredChildren && filteredChildren.length > 0)) {
        return {
          ...node,
          children: filteredChildren,
        };
      }
      return null;
    };

    return tree.map(filterNode).filter((n): n is TreeNode => n !== null);
  }, [tree, searchQuery]);

  if (collapsed) {
    return null;
  }

  return (
    <div className="rf-left-zone rf-scrollbar">
      {/* Header with Tabs */}
      <div className="rf-zone-header rf-zone-header--tabs">
        <div className="rf-zone-tabs">
          <button
            className={`rf-zone-tab ${currentTab === 'project' ? 'rf-zone-tab--active' : ''}`}
            onClick={() => handleTabChange('project')}
          >
            Project
          </button>
          <button
            className={`rf-zone-tab ${currentTab === 'channel' ? 'rf-zone-tab--active' : ''}`}
            onClick={() => handleTabChange('channel')}
          >
            Channel
          </button>
        </div>
        <div className="rf-zone-header__actions">
          {currentTab === 'project' && onAdd && (
            <button
              className="rf-zone-header__btn"
              onClick={() => onAdd('event')}
              title="Add Event"
            >
              +
            </button>
          )}
          {onToggleCollapse && (
            <button
              className="rf-zone-header__btn"
              onClick={onToggleCollapse}
              title="Collapse Zone"
            >
              ◀
            </button>
          )}
        </div>
      </div>

      {/* Project Explorer Tab */}
      {currentTab === 'project' && (
        <>
          {/* Search */}
          <div className="rf-search-bar">
            <input
              type="text"
              className="rf-search-bar__input"
              placeholder="Search..."
              value={searchQuery}
              onChange={(e) => onSearchChange?.(e.target.value)}
            />
          </div>

          {/* Tree */}
          <div className="rf-tree rf-scrollbar">
            {filteredTree.map((node) => (
              <TreeItem
                key={node.id}
                node={node}
                level={0}
                selectedId={selectedId}
                expandedIds={expandedIds}
                onToggle={handleToggle}
                onSelect={handleSelect}
                onDoubleClick={onDoubleClick}
                searchQuery={searchQuery}
                onEventReorder={onEventReorder}
              />
            ))}

            {filteredTree.length === 0 && searchQuery && (
              <div
                style={{
                  padding: '24px 16px',
                  textAlign: 'center',
                  color: 'var(--rf-text-tertiary)',
                  fontSize: 12,
                }}
              >
                No results for "{searchQuery}"
              </div>
            )}
          </div>
        </>
      )}

      {/* Channel Tab */}
      {currentTab === 'channel' && (
        <ChannelPanel
          channel={channelData ?? null}
          onVolumeChange={onChannelVolumeChange}
          onPanChange={onChannelPanChange}
          onMuteToggle={onChannelMuteToggle}
          onSoloToggle={onChannelSoloToggle}
          onInsertClick={onChannelInsertClick}
          onSendLevelChange={onChannelSendLevelChange}
          onEQToggle={onChannelEQToggle}
          onOutputClick={onChannelOutputClick}
        />
      )}
    </div>
  );
});

export default LeftZone;

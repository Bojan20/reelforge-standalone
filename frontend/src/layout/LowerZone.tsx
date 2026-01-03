/**
 * ReelForge Lower Zone
 *
 * Dockable panel area with tabs:
 * - Mixer
 * - Editor
 * - Browser
 * - Profiler
 * - Console
 *
 * @module layout/LowerZone
 */

import { memo, useState, useCallback, useRef, useEffect, type ReactNode } from 'react';
import { useDropTarget, type DropTarget, type DragItem } from '../core/dragDropSystem';

// ============ Canvas Meter Component ============
// GPU-accelerated meter rendering without React re-renders

interface CanvasMeterProps {
  /** Left channel level (0-1) */
  levelL: number;
  /** Right channel level (0-1) */
  levelR: number;
  /** Left peak hold (0-1) */
  peakL?: number;
  /** Right peak hold (0-1) */
  peakR?: number;
  /** Height of the meter in pixels */
  height: number;
}

// Memoized to prevent unnecessary re-mounts, but meter updates bypass React
const CanvasMeter = memo(function CanvasMeter({ levelL, levelR, peakL, peakR, height }: CanvasMeterProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationFrameRef = useRef<number>(0);
  const valuesRef = useRef({ levelL: 0, levelR: 0, peakL: 0, peakR: 0 });

  // Update values ref without triggering re-render
  valuesRef.current = { levelL, levelR, peakL: peakL ?? levelL, peakR: peakR ?? levelR };

  // Draw function - runs on every animation frame
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const width = canvas.width / dpr;
    const h = canvas.height / dpr;

    const { levelL: lL, levelR: lR, peakL: pL, peakR: pR } = valuesRef.current;

    // Noise gate
    const NOISE_FLOOR = 0.00003;
    const gL = lL < NOISE_FLOOR ? 0 : lL;
    const gR = lR < NOISE_FLOOR ? 0 : lR;
    const gPL = pL < NOISE_FLOOR ? 0 : pL;
    const gPR = pR < NOISE_FLOOR ? 0 : pR;

    // Convert to dB and percentage
    const dbL = gL <= 0 ? -60 : 20 * Math.log10(gL);
    const dbR = gR <= 0 ? -60 : 20 * Math.log10(gR);
    const dbPL = gPL <= 0 ? -60 : 20 * Math.log10(gPL);
    const dbPR = gPR <= 0 ? -60 : 20 * Math.log10(gPR);

    const pctL = Math.max(0, Math.min(100, ((dbL + 60) / 66) * 100));
    const pctR = Math.max(0, Math.min(100, ((dbR + 60) / 66) * 100));
    const pctPL = Math.max(0, Math.min(100, ((dbPL + 60) / 66) * 100));
    const pctPR = Math.max(0, Math.min(100, ((dbPR + 60) / 66) * 100));

    // Clear
    ctx.fillStyle = '#0a0a0b';
    ctx.fillRect(0, 0, width, h);

    // Meter widths
    const meterWidth = 5;
    const gap = 1;
    const leftX = 0;
    const rightX = meterWidth + gap;

    // Get color based on dB
    const getColor = (db: number) => {
      if (db >= 0) return '#ef4444'; // Red - clipping
      if (db >= -6) return '#f59e0b'; // Yellow - warning
      return '#22c55e'; // Green - normal
    };

    // Draw meter fills (from bottom up)
    const fillHeight = (h * pctL) / 100;
    ctx.fillStyle = getColor(dbL);
    ctx.fillRect(leftX, h - fillHeight, meterWidth, fillHeight);

    const fillHeightR = (h * pctR) / 100;
    ctx.fillStyle = getColor(dbR);
    ctx.fillRect(rightX, h - fillHeightR, meterWidth, fillHeightR);

    // Draw peak holds
    if (pctPL > 0) {
      const peakY = h - (h * pctPL) / 100;
      ctx.fillStyle = dbPL >= 0 ? '#ef4444' : '#f0f0f2';
      ctx.fillRect(leftX, peakY - 1, meterWidth, 2);
    }

    if (pctPR > 0) {
      const peakY = h - (h * pctPR) / 100;
      ctx.fillStyle = dbPR >= 0 ? '#ef4444' : '#f0f0f2';
      ctx.fillRect(rightX, peakY - 1, meterWidth, 2);
    }

    // Continue animation loop
    animationFrameRef.current = requestAnimationFrame(draw);
  }, []);

  // Setup canvas and start animation loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = 12 * dpr; // 5 + 1 + 5 + 1 padding
    canvas.height = height * dpr;

    const ctx = canvas.getContext('2d', { alpha: false });
    if (ctx) {
      ctx.scale(dpr, dpr);
    }

    // Start animation loop
    animationFrameRef.current = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(animationFrameRef.current);
    };
  }, [height, draw]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width: 12, height, display: 'block' }}
      className="rf-mixer-strip-pro__canvas-meter"
    />
  );
});

// ============ Types ============

export interface LowerZoneTab {
  id: string;
  label: string;
  icon?: string;
  content: ReactNode;
  /** Group ID for hierarchical tabs */
  group?: string;
}

export interface TabGroup {
  id: string;
  label: string;
  icon?: string;
  /** Tabs in this group */
  tabs: string[];
}

export interface LowerZoneProps {
  /** Whether zone is collapsed */
  collapsed?: boolean;
  /** Available tabs */
  tabs: LowerZoneTab[];
  /** Tab groups for hierarchical organization */
  tabGroups?: TabGroup[];
  /** Active tab ID */
  activeTabId?: string;
  /** On tab change */
  onTabChange?: (tabId: string) => void;
  /** On collapse toggle */
  onToggleCollapse?: () => void;
  /** Initial height */
  height?: number;
  /** On height change */
  onHeightChange?: (height: number) => void;
  /** Min height */
  minHeight?: number;
  /** Max height */
  maxHeight?: number;
}

// ============ Mixer Strip Component ============

export interface InsertSlot {
  id: string;
  name: string;
  type?: 'eq' | 'comp' | 'reverb' | 'delay' | 'filter' | 'fx' | 'utility' | 'custom';
  bypassed?: boolean;
}

export interface MixerStripProps {
  id: string;
  name: string;
  isMaster?: boolean;
  volume: number;
  pan?: number;
  muted: boolean;
  soloed: boolean;
  meterLevel?: number;
  meterLevelR?: number;
  peakHold?: number;
  peakHoldR?: number;
  inserts?: InsertSlot[];
  onVolumeChange?: (volume: number) => void;
  onPanChange?: (pan: number) => void;
  onMuteToggle?: () => void;
  onSoloToggle?: () => void;
  onInsertClick?: (slotIndex: number, insert: InsertSlot | null, event?: React.MouseEvent) => void;
  onInsertBypass?: (slotIndex: number, insert: InsertSlot) => void;
  onSelect?: () => void;
  selected?: boolean;
  /** On audio asset drop */
  onAudioDrop?: (audioItem: DragItem) => void;
}

// DB scale markers
const DB_MARKS = [6, 0, -6, -12, -24, -48];

// Convert dB to percentage height (0-100) - used for dB scale marks
function dbToPercent(db: number): number {
  if (db <= -60) return 0;
  if (db >= 6) return 100;
  return ((db + 60) / 66) * 100;
}

// Custom comparator for MixerStrip - optimized for 60fps meter animation
// CRITICAL: Callbacks are EXCLUDED from comparison because they're recreated
// on every parent render but don't actually change behavior
function mixerStripPropsAreEqual(prev: MixerStripProps, next: MixerStripProps): boolean {
  // Quick bail for meter level changes (most frequent update path)
  // These updates MUST be fast for smooth 60fps animation
  if (prev.meterLevel !== next.meterLevel || prev.meterLevelR !== next.meterLevelR) {
    return false;
  }
  if (prev.peakHold !== next.peakHold || prev.peakHoldR !== next.peakHoldR) {
    return false;
  }

  // Static props that rarely change - compare these
  // NOTE: Callbacks are intentionally EXCLUDED - they're stable by ref in parent useCallback
  return (
    prev.id === next.id &&
    prev.name === next.name &&
    prev.isMaster === next.isMaster &&
    prev.volume === next.volume &&
    prev.pan === next.pan &&
    prev.muted === next.muted &&
    prev.soloed === next.soloed &&
    prev.selected === next.selected &&
    prev.inserts === next.inserts
    // Callbacks excluded: onVolumeChange, onPanChange, onMuteToggle, onSoloToggle,
    // onInsertClick, onInsertBypass, onSelect, onAudioDrop
    // They change reference but not behavior, so comparing them causes unnecessary re-renders
  );
}

export const MixerStrip = memo(function MixerStrip({
  id,
  name,
  isMaster = false,
  volume,
  pan = 0,
  muted,
  soloed,
  meterLevel = 0,
  meterLevelR,
  peakHold,
  peakHoldR,
  inserts = [],
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onInsertClick,
  onInsertBypass,
  onSelect,
  selected,
  onAudioDrop,
}: MixerStripProps) {
  // Drop target for audio assets
  const dropTarget: DropTarget = {
    id: `mixer-${id}`,
    type: 'mixer-bus',
    accepts: ['audio-asset'],
  };

  const handleDrop = useCallback((item: DragItem, _target: DropTarget) => {
    onAudioDrop?.(item);
  }, [onAudioDrop]);

  const { ref: dropRef, isOver } = useDropTarget(dropTarget, handleDrop);

  // Convert volume (0-1.5) to dB display
  const volumeDb = volume <= 0 ? -Infinity : 20 * Math.log10(volume);
  const volumeDbStr = volumeDb <= -60 ? '-∞' : volumeDb.toFixed(1);

  // Is clipping? (meter level >= 1.0 means 0dB or above)
  const isClipping = meterLevel >= 1.0 || (meterLevelR ?? meterLevel) >= 1.0;

  // Insert slots (always show 4)
  const insertSlots = Array.from({ length: 4 }, (_, i) => inserts[i] || null);

  // Pan display
  const panDisplay = pan === 0 ? 'C' : pan < 0 ? `L${Math.abs(Math.round(pan * 100))}` : `R${Math.round(pan * 100)}`;

  return (
    <div
      ref={dropRef as React.Ref<HTMLDivElement>}
      className={`rf-mixer-strip-pro ${isMaster ? 'rf-mixer-strip-pro--master' : ''} ${selected ? 'rf-mixer-strip-pro--selected' : ''} ${muted ? 'rf-mixer-strip-pro--muted' : ''} ${isOver ? 'rf-mixer-strip-pro--drop-active' : ''}`}
      onClick={onSelect}
    >
      {/* Channel Name */}
      <div className="rf-mixer-strip-pro__name">
        <span className="rf-mixer-strip-pro__name-text">{name}</span>
        {isMaster && <span className="rf-mixer-strip-pro__master-badge">M</span>}
      </div>

      {/* Insert Rack */}
      <div className="rf-mixer-strip-pro__inserts">
        {insertSlots.map((insert, idx) => (
          <div
            key={idx}
            className={`rf-mixer-strip-pro__insert ${insert ? 'rf-mixer-strip-pro__insert--filled' : ''} ${insert?.bypassed ? 'rf-mixer-strip-pro__insert--bypassed' : ''}`}
            title={insert ? `${insert.name} (click to edit)` : 'Click to add insert'}
          >
            {insert ? (
              <>
                <button
                  className={`rf-mixer-strip-pro__insert-power ${insert.bypassed ? 'rf-mixer-strip-pro__insert-power--off' : ''}`}
                  onClick={(e) => {
                    e.stopPropagation();
                    onInsertBypass?.(idx, insert);
                  }}
                  title={insert.bypassed ? 'Enable plugin' : 'Bypass plugin'}
                >
                  <span className="rf-mixer-strip-pro__insert-power-icon" />
                </button>
                <span
                  className="rf-mixer-strip-pro__insert-name"
                  onClick={(e) => {
                    e.stopPropagation();
                    onInsertClick?.(idx, insert, e);
                  }}
                >
                  {insert.name}
                </span>
                <button
                  className="rf-mixer-strip-pro__insert-dropdown"
                  onClick={(e) => {
                    e.stopPropagation();
                    // Open plugin picker for this slot (pass null to indicate "replace mode")
                    onInsertClick?.(idx, null, e);
                  }}
                  title="Change plugin"
                >
                  <span className="rf-mixer-strip-pro__insert-dropdown-arrow">&#9662;</span>
                </button>
              </>
            ) : (
              <span
                className="rf-mixer-strip-pro__insert-empty"
                onClick={(e) => {
                  e.stopPropagation();
                  onInsertClick?.(idx, insert, e);
                }}
              >
                +
              </span>
            )}
          </div>
        ))}
      </div>

      {/* Pan Knob */}
      {!isMaster && onPanChange && (
        <div className="rf-mixer-strip-pro__pan">
          <input
            type="range"
            min={-1}
            max={1}
            step={0.01}
            value={pan}
            onChange={(e) => onPanChange(parseFloat(e.target.value))}
            onDoubleClick={() => onPanChange(0)} // Reset to center
            className="rf-mixer-strip-pro__pan-slider"
            title={`Pan: ${panDisplay} (double-click to center)`}
          />
          <span className="rf-mixer-strip-pro__pan-value">{panDisplay}</span>
        </div>
      )}

      {/* Main Fader Section */}
      <div className="rf-mixer-strip-pro__fader-section">
        {/* dB Scale */}
        <div className="rf-mixer-strip-pro__db-scale">
          {DB_MARKS.map((db) => (
            <div key={db} className="rf-mixer-strip-pro__db-mark" style={{ bottom: `${dbToPercent(db)}%` }}>
              <span>{db > 0 ? `+${db}` : db}</span>
            </div>
          ))}
        </div>

        {/* Stereo Meter - Canvas-based for besprekoran 60fps */}
        <div className="rf-mixer-strip-pro__meters">
          <CanvasMeter
            levelL={meterLevel}
            levelR={meterLevelR ?? meterLevel}
            peakL={peakHold}
            peakR={peakHoldR}
            height={280}
          />
        </div>

        {/* Fader */}
        <div className="rf-mixer-strip-pro__fader">
          <div className="rf-mixer-strip-pro__fader-track">
            <input
              type="range"
              min={0}
              max={1.5}
              step={0.001}
              value={volume}
              onChange={(e) => onVolumeChange?.(parseFloat(e.target.value))}
              onDoubleClick={() => onVolumeChange?.(1.0)} // Reset to unity (0dB)
              className="rf-mixer-strip-pro__fader-input"
              title={`Volume: ${volumeDbStr} dB (double-click to reset)`}
            />
            {/* Unity (0dB) mark */}
            <div className="rf-mixer-strip-pro__unity-mark" />
          </div>
        </div>
      </div>

      {/* dB Readout */}
      <div className={`rf-mixer-strip-pro__db-readout ${isClipping ? 'rf-mixer-strip-pro__db-readout--clip' : ''}`}>
        {volumeDbStr}
        <span className="rf-mixer-strip-pro__db-unit">dB</span>
      </div>

      {/* Solo / Mute */}
      <div className="rf-mixer-strip-pro__buttons">
        <button
          className={`rf-mixer-strip-pro__btn rf-mixer-strip-pro__btn--solo ${soloed ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onSoloToggle?.();
          }}
          title="Solo (S)"
        >
          S
        </button>
        <button
          className={`rf-mixer-strip-pro__btn rf-mixer-strip-pro__btn--mute ${muted ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onMuteToggle?.();
          }}
          title="Mute (M)"
        >
          M
        </button>
      </div>

      {/* Clip Indicator */}
      {isClipping && (
        <div className="rf-mixer-strip-pro__clip-indicator">CLIP</div>
      )}
    </div>
  );
}, mixerStripPropsAreEqual);

// ============ Lower Zone Component ============

export const LowerZone = memo(function LowerZone({
  collapsed = false,
  tabs,
  tabGroups,
  activeTabId,
  onTabChange,
  onToggleCollapse,
  height = 280,
  onHeightChange,
  minHeight = 100,
  maxHeight = 500,
}: LowerZoneProps) {
  const [isResizing, setIsResizing] = useState(false);
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);
  const startYRef = useRef(0);
  const startHeightRef = useRef(height);

  // Find which group the active tab belongs to
  const activeGroup = tabGroups?.find(g => g.tabs.includes(activeTabId || ''));

  // Handle resize drag
  const handleResizeStart = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsResizing(true);
      startYRef.current = e.clientY;
      startHeightRef.current = height;

      const handleMouseMove = (e: MouseEvent) => {
        const deltaY = startYRef.current - e.clientY;
        const newHeight = Math.max(minHeight, Math.min(maxHeight, startHeightRef.current + deltaY));
        onHeightChange?.(newHeight);
      };

      const handleMouseUp = () => {
        setIsResizing(false);
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };

      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    },
    [height, minHeight, maxHeight, onHeightChange]
  );

  // Get active tab content
  const activeTab = tabs.find((t) => t.id === activeTabId) || tabs[0];

  return (
    <div
      className={`rf-lower-zone ${collapsed ? 'collapsed' : ''}`}
      style={{ height: collapsed ? 36 : height }}
    >
      {/* Resize Handle */}
      <div
        className="rf-lower-zone__resize"
        onMouseDown={handleResizeStart}
        style={isResizing ? { background: 'var(--rf-accent-primary)' } : undefined}
      />

      {/* Tab Bar */}
      <div className="rf-tab-bar">
        {tabGroups ? (
          // Grouped tabs with subtabs
          <>
            {tabGroups.map((group, groupIndex) => {
              const groupTabs = tabs.filter(t => group.tabs.includes(t.id));
              const isActiveGroup = activeGroup?.id === group.id;
              const isExpanded = expandedGroup === group.id;
              const hasMultipleTabs = groupTabs.length > 1;

              return (
                <div key={group.id} className="rf-tab-group" style={{ display: 'flex', alignItems: 'center' }}>
                  {/* Separator between groups */}
                  {groupIndex > 0 && (
                    <div className="rf-tab-separator" style={{
                      width: 1,
                      height: 20,
                      background: 'var(--rf-border)',
                      margin: '0 4px',
                    }} />
                  )}

                  {hasMultipleTabs ? (
                    // Group with dropdown
                    <div
                      className={`rf-tab rf-tab--group ${isActiveGroup ? 'active' : ''}`}
                      onClick={() => setExpandedGroup(isExpanded ? null : group.id)}
                      style={{ position: 'relative' }}
                    >
                      {group.icon && <span className="rf-tab__icon">{group.icon}</span>}
                      <span>{group.label}</span>
                      <span style={{ marginLeft: 4, fontSize: 8 }}>{isExpanded ? '▲' : '▼'}</span>

                      {/* Dropdown */}
                      {isExpanded && (
                        <div
                          className="rf-tab-dropdown"
                          style={{
                            position: 'absolute',
                            top: '100%',
                            left: 0,
                            background: 'var(--rf-bg-2)',
                            border: '1px solid var(--rf-border)',
                            borderRadius: 4,
                            padding: 4,
                            zIndex: 100,
                            minWidth: 120,
                            boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
                          }}
                          onClick={(e) => e.stopPropagation()}
                        >
                          {groupTabs.map((tab) => (
                            <div
                              key={tab.id}
                              className={`rf-tab-dropdown-item ${activeTabId === tab.id ? 'active' : ''}`}
                              onClick={() => {
                                onTabChange?.(tab.id);
                                setExpandedGroup(null);
                              }}
                              style={{
                                padding: '6px 10px',
                                cursor: 'pointer',
                                borderRadius: 3,
                                fontSize: 11,
                                display: 'flex',
                                alignItems: 'center',
                                gap: 6,
                                background: activeTabId === tab.id ? 'var(--rf-accent-primary)' : 'transparent',
                                color: activeTabId === tab.id ? '#fff' : 'var(--rf-text-secondary)',
                              }}
                            >
                              {tab.icon && <span>{tab.icon}</span>}
                              <span>{tab.label}</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  ) : (
                    // Single tab in group
                    groupTabs.map((tab) => (
                      <div
                        key={tab.id}
                        className={`rf-tab ${activeTabId === tab.id ? 'active' : ''}`}
                        onClick={() => onTabChange?.(tab.id)}
                      >
                        {tab.icon && <span className="rf-tab__icon">{tab.icon}</span>}
                        <span>{tab.label}</span>
                      </div>
                    ))
                  )}
                </div>
              );
            })}
          </>
        ) : (
          // Flat tabs (backwards compatible)
          tabs.map((tab) => (
            <div
              key={tab.id}
              className={`rf-tab ${activeTabId === tab.id ? 'active' : ''}`}
              onClick={() => onTabChange?.(tab.id)}
            >
              {tab.icon && <span className="rf-tab__icon">{tab.icon}</span>}
              <span>{tab.label}</span>
            </div>
          ))
        )}

        <div style={{ flex: 1 }} />

        {/* Collapse Button */}
        {onToggleCollapse && (
          <button
            className="rf-zone-header__btn"
            onClick={onToggleCollapse}
            title={collapsed ? 'Expand Zone' : 'Collapse Zone'}
            style={{ marginRight: 8 }}
          >
            {collapsed ? '▲' : '▼'}
          </button>
        )}
      </div>

      {/* Content */}
      <div className="rf-lower-zone__content rf-scrollbar">
        {activeTab?.content}
      </div>
    </div>
  );
});

// ============ Console Panel ============

export interface ConsoleMessage {
  id: string;
  level: 'info' | 'warn' | 'error';
  message: string;
  timestamp: Date;
}

export interface ConsolePanelProps {
  messages: ConsoleMessage[];
  onClear?: () => void;
}

export const ConsolePanel = memo(function ConsolePanel({
  messages,
  onClear,
}: ConsolePanelProps) {
  const getLevelColor = (level: ConsoleMessage['level']) => {
    switch (level) {
      case 'error': return 'var(--rf-accent-error)';
      case 'warn': return 'var(--rf-accent-warning)';
      default: return 'var(--rf-text-secondary)';
    }
  };

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '8px 12px', borderBottom: '1px solid var(--rf-border)', display: 'flex', alignItems: 'center' }}>
        <span style={{ fontSize: 11, color: 'var(--rf-text-tertiary)' }}>
          {messages.length} messages
        </span>
        {onClear && (
          <button
            onClick={onClear}
            style={{
              marginLeft: 'auto',
              padding: '4px 8px',
              background: 'var(--rf-bg-3)',
              border: 'none',
              borderRadius: 4,
              color: 'var(--rf-text-secondary)',
              fontSize: 11,
              cursor: 'pointer',
            }}
          >
            Clear
          </button>
        )}
      </div>
      <div style={{ flex: 1, overflow: 'auto', fontFamily: 'monospace', fontSize: 11 }}>
        {messages.map((msg) => (
          <div
            key={msg.id}
            style={{
              padding: '4px 12px',
              borderBottom: '1px solid var(--rf-border)',
              color: getLevelColor(msg.level),
            }}
          >
            <span style={{ color: 'var(--rf-text-tertiary)', marginRight: 8 }}>
              {msg.timestamp.toLocaleTimeString()}
            </span>
            {msg.message}
          </div>
        ))}
      </div>
    </div>
  );
});

export default LowerZone;

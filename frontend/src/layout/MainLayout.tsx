/**
 * ReelForge Main Layout
 *
 * Master layout wrapper combining:
 * - ControlBar (top)
 * - LeftZone (project explorer)
 * - CenterZone (main editor)
 * - RightZone (inspector)
 * - LowerZone (mixer/editor/browser)
 *
 * @module layout/MainLayout
 */

import { memo, useState, useCallback, useEffect, type ReactNode } from 'react';
import { ControlBar, type ControlBarProps } from './ControlBar';
import { LeftZone, type LeftZoneProps, type TreeNode } from './LeftZone';
import { RightZone, type RightZoneProps, type InspectorSection } from './RightZone';
// ChannelStrip types used for props, component reserved for DAW mode
import type { ChannelStripProps, ChannelStripData } from './ChannelStrip';
import { LowerZone, type LowerZoneTab, type TabGroup } from './LowerZone';
import type { EditorMode } from '../hooks/useEditorMode';
import './layout.css';

// ============ Types ============

export interface MainLayoutProps {
  // Control bar
  controlBar: Omit<ControlBarProps, 'onToggleLeftZone' | 'onToggleRightZone' | 'onToggleLowerZone'>;

  // Left zone (Project Explorer)
  projectTree: TreeNode[];
  selectedProjectId?: string | null;
  onProjectSelect?: LeftZoneProps['onSelect'];
  onProjectDoubleClick?: LeftZoneProps['onDoubleClick'];
  projectSearchQuery?: string;
  onProjectSearchChange?: LeftZoneProps['onSearchChange'];
  onProjectAdd?: LeftZoneProps['onAdd'];

  // Center zone (Editor)
  children: ReactNode;

  // Right zone (Inspector) - used in Middleware mode
  inspectorType: RightZoneProps['objectType'];
  inspectorName?: string;
  inspectorSections: InspectorSection[];

  // Right zone (Channel Strip) - used in DAW mode
  editorMode?: EditorMode;
  channelStripData?: ChannelStripData | null;
  onChannelVolumeChange?: ChannelStripProps['onVolumeChange'];
  onChannelPanChange?: ChannelStripProps['onPanChange'];
  onChannelMuteToggle?: ChannelStripProps['onMuteToggle'];
  onChannelSoloToggle?: ChannelStripProps['onSoloToggle'];
  onChannelInsertClick?: ChannelStripProps['onInsertClick'];
  onChannelSendLevelChange?: ChannelStripProps['onSendLevelChange'];
  onChannelEQToggle?: ChannelStripProps['onEQToggle'];
  onChannelOutputClick?: ChannelStripProps['onOutputClick'];

  // Lower zone (Mixer/Tabs)
  lowerTabs: LowerZoneTab[];
  lowerTabGroups?: TabGroup[];
  activeLowerTabId?: string;
  onLowerTabChange?: (tabId: string) => void;

  // Zone visibility state (optional - will use internal state if not provided)
  leftZoneVisible?: boolean;
  rightZoneVisible?: boolean;
  lowerZoneVisible?: boolean;
  onLeftZoneToggle?: () => void;
  onRightZoneToggle?: () => void;
  onLowerZoneToggle?: () => void;
}

// ============ Main Layout Component ============

export const MainLayout = memo(function MainLayout({
  controlBar,
  projectTree,
  selectedProjectId,
  onProjectSelect,
  onProjectDoubleClick,
  projectSearchQuery = '',
  onProjectSearchChange,
  onProjectAdd,
  children,
  inspectorType,
  inspectorName,
  inspectorSections,
  editorMode = 'middleware',
  channelStripData: _channelStripData,
  onChannelVolumeChange: _onChannelVolumeChange,
  onChannelPanChange: _onChannelPanChange,
  onChannelMuteToggle: _onChannelMuteToggle,
  onChannelSoloToggle: _onChannelSoloToggle,
  onChannelInsertClick: _onChannelInsertClick,
  onChannelSendLevelChange: _onChannelSendLevelChange,
  onChannelEQToggle: _onChannelEQToggle,
  onChannelOutputClick: _onChannelOutputClick,
  lowerTabs,
  lowerTabGroups,
  activeLowerTabId,
  onLowerTabChange,
  leftZoneVisible: externalLeftVisible,
  rightZoneVisible: externalRightVisible,
  lowerZoneVisible: externalLowerVisible,
  onLeftZoneToggle: externalLeftToggle,
  onRightZoneToggle: externalRightToggle,
  onLowerZoneToggle: externalLowerToggle,
}: MainLayoutProps) {
  // Internal zone visibility state (used if external state not provided)
  const [internalLeftVisible, setInternalLeftVisible] = useState(true);
  const [internalRightVisible, setInternalRightVisible] = useState(true);
  const [internalLowerVisible, setInternalLowerVisible] = useState(false); // Collapsed by default
  const [lowerZoneHeight, setLowerZoneHeight] = useState(450);

  // Use external or internal state
  const leftVisible = externalLeftVisible ?? internalLeftVisible;
  const rightVisible = externalRightVisible ?? internalRightVisible;
  const lowerVisible = externalLowerVisible ?? internalLowerVisible;

  // Toggle handlers
  const toggleLeft = useCallback(() => {
    if (externalLeftToggle) {
      externalLeftToggle();
    } else {
      setInternalLeftVisible((v) => !v);
    }
  }, [externalLeftToggle]);

  const toggleRight = useCallback(() => {
    if (externalRightToggle) {
      externalRightToggle();
    } else {
      setInternalRightVisible((v) => !v);
    }
  }, [externalRightToggle]);

  const toggleLower = useCallback(() => {
    if (externalLowerToggle) {
      externalLowerToggle();
    } else {
      setInternalLowerVisible((v) => !v);
    }
  }, [externalLowerToggle]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore if typing in input
      if (
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLTextAreaElement ||
        e.target instanceof HTMLSelectElement
      ) {
        return;
      }

      const key = e.key.toLowerCase();
      const ctrl = e.ctrlKey || e.metaKey;

      // Zone toggles
      if (ctrl && key === 'l') {
        e.preventDefault();
        toggleLeft();
      } else if (ctrl && key === 'r') {
        e.preventDefault();
        toggleRight();
      } else if (ctrl && key === 'b') {
        e.preventDefault();
        toggleLower();
      }

      // Transport shortcuts (only in DAW mode - Middleware mode uses Space for event preview)
      if (key === ' ' && editorMode === 'daw') {
        e.preventDefault();
        if (controlBar.isPlaying) {
          controlBar.onStop?.();
        } else {
          controlBar.onPlay?.();
        }
      } else if (key === '.' && !ctrl && editorMode === 'daw') {
        controlBar.onStop?.();
      } else if (key === 'r' && !ctrl) {
        controlBar.onRecord?.();
      // L shortcut is handled by useGlobalShortcuts (expand loop to content)
      } else if (key === 'k') {
        controlBar.onMetronomeToggle?.();
      } else if (key === ',') {
        controlBar.onRewind?.();
      } else if (key === '/') {
        controlBar.onForward?.();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [controlBar, editorMode, toggleLeft, toggleRight, toggleLower]);

  return (
    <div className="rf-app">
      {/* Control Bar */}
      <ControlBar
        {...controlBar}
        onToggleLeftZone={toggleLeft}
        onToggleRightZone={toggleRight}
        onToggleLowerZone={toggleLower}
        menuCallbacks={{
          ...controlBar.menuCallbacks,
          onToggleLeftPanel: toggleLeft,
          onToggleRightPanel: toggleRight,
          onToggleLowerPanel: toggleLower,
        }}
      />

      {/* Main Content Area */}
      <div className="rf-main">
        {/* Left Zone */}
        <LeftZone
          collapsed={!leftVisible}
          tree={projectTree}
          selectedId={selectedProjectId}
          onSelect={onProjectSelect}
          onDoubleClick={onProjectDoubleClick}
          searchQuery={projectSearchQuery}
          onSearchChange={onProjectSearchChange}
          onAdd={onProjectAdd}
          onToggleCollapse={toggleLeft}
        />

        {/* Center Zone + Lower Zone Container */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          {/* Center Zone */}
          <div className="rf-center-zone">{children}</div>

          {/* Lower Zone */}
          <LowerZone
            collapsed={!lowerVisible}
            tabs={lowerTabs}
            tabGroups={lowerTabGroups}
            activeTabId={activeLowerTabId}
            onTabChange={onLowerTabChange}
            onToggleCollapse={toggleLower}
            height={lowerZoneHeight}
            onHeightChange={setLowerZoneHeight}
            minHeight={100}
            maxHeight={500}
          />
        </div>

        {/* Right Zone - Only show Inspector in Middleware mode, hidden in DAW mode */}
        {editorMode === 'middleware' && (
          <RightZone
            collapsed={!rightVisible}
            objectType={inspectorType}
            objectName={inspectorName}
            sections={inspectorSections}
            onToggleCollapse={toggleRight}
          />
        )}
      </div>
    </div>
  );
});

export default MainLayout;

/**
 * ReelForge Layout System
 *
 * Professional DAW/Wwise hybrid layout components.
 *
 * @module layout
 */

// Main Layout
export { MainLayout } from './MainLayout';
export type { MainLayoutProps } from './MainLayout';

// Control Bar
export { ControlBar } from './ControlBar';
export type { ControlBarProps } from './ControlBar';

// Left Zone (Project Explorer)
export { LeftZone } from './LeftZone';
export type { LeftZoneProps, TreeNode, TreeItemType } from './LeftZone';

// Right Zone (Inspector)
export { RightZone, TextField, SelectField, SliderField, CheckboxField } from './RightZone';
export type {
  RightZoneProps,
  InspectorSection,
  InspectedObjectType,
  TextFieldProps,
  SelectFieldProps,
  SliderFieldProps,
  CheckboxFieldProps,
} from './RightZone';

// Channel Strip (DAW Mode Right Zone)
export {
  ChannelStrip,
  createEmptyInserts,
  createEmptySends,
  createDefaultChannelStrip,
} from './ChannelStrip';
export type {
  ChannelStripProps,
  ChannelStripData,
  InsertSlot as ChannelInsertSlot,
  SendSlot,
  EQBand,
} from './ChannelStrip';

// Lower Zone (Mixer/Tabs)
export { LowerZone, MixerStrip, ConsolePanel } from './LowerZone';
export type {
  LowerZoneProps,
  LowerZoneTab,
  TabGroup,
  MixerStripProps,
  InsertSlot,
  ConsolePanelProps,
  ConsoleMessage,
} from './LowerZone';

// Clip Editor (Lower Zone - DAW)
export { ClipEditor } from './ClipEditor';
export type {
  ClipEditorProps,
  ClipEditorClip,
  ClipEditorSelection,
} from './ClipEditor';

// Dockable Panel System
export { DockablePanel, usePanelManager } from './DockablePanel';
export type { DockablePanelProps, PanelManagerState } from './DockablePanel';

// Timeline
export { Timeline, generateDemoWaveform } from './Timeline';
export type {
  TimelineProps,
  TimelineTrack,
  TimelineClip,
  TimelineMarker,
  TimelineRegion,
  Crossfade,
} from './Timeline';

// Layered Music Editor
export {
  LayeredMusicEditor,
  generateDemoLayers,
  generateDemoBlendCurves,
  generateDemoStates,
} from './LayeredMusicEditor';
export type {
  LayeredMusicEditorProps,
  MusicLayer,
  BlendPoint,
  BlendCurve,
  MusicState,
} from './LayeredMusicEditor';

// Editor Mode Layout Configuration
export {
  DAW_MODE_CONFIG,
  MIDDLEWARE_MODE_CONFIG,
  MODE_LAYOUT_CONFIGS,
  getModeLayoutConfig,
  isTabVisibleInMode,
  isTabGroupVisibleInMode,
  getOrderedTabGroups,
  getDefaultTabForMode,
  filterTabGroupsForMode,
  filterTabsForMode,
} from './editorModeConfig';
export type {
  LowerZoneConfig,
  LeftZoneConfig,
  RightZoneConfig,
  EditorModeLayoutConfig,
} from './editorModeConfig';

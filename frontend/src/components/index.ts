/**
 * ReelForge Components
 *
 * Shared UI components for the editor.
 *
 * @module components
 */

// ============ Default Exports (re-export as named) ============
export { default as ActionTemplates } from './ActionTemplates';
export { default as AssetInsertPanel } from './AssetInsertPanel';
export { default as AssetPicker } from './AssetPicker';
export { default as AudioMeter } from './AudioMeter';
export { default as BusInsertPanel } from './BusInsertPanel';
export { default as BusInspector } from './BusInspector';
export { default as DiagnosticsHUD } from './DiagnosticsHUD';
export { default as ErrorBoundary } from './ErrorBoundary';
export { default as MasterInsertPanel } from './MasterInsertPanel';
export { default as MixerView } from './MixerView';
export { default as PixiSpectrum } from './PixiSpectrum';
export { default as PixiWaveform } from './PixiWaveform';
export { default as PresetBrowser } from './PresetBrowser';
export { default as ProjectHeader } from './ProjectHeader';
export { default as ProjectRoutesEditor } from './ProjectRoutesEditor';
export { default as RouteSimulationPanel } from './RouteSimulationPanel';
export { default as RoutesEditor } from './RoutesEditor';
export { default as StripInsertRack } from './StripInsertRack';

// ============ Named Exports ============
export * from './AudioLoopUploader';
export * from './EventList';
export * from './EventListItem';
export * from './LoopAnalysisUI';
export * from './ReelForgeLoopManager';
export * from './RFErrorBanner';
export * from './SoundListItem';
export * from './SoundsList';

// ============ New UI Integration Components ============
export * from './ToolbarIntegrations';
export * from './MixerPanel';
export * from './SettingsPanel';
export * from './RecentProjectsPanel';
export * from './TransportControls';
export * from './AssetPreviewButton';

// ============ Polish & UX Components ============
export * from './LoadingStates';
export * from './Tooltip';

// ============ Cubase-style Audio Import Components ============
export { default as AudioBrowser } from './AudioBrowser';
export type { AudioFileInfo, AudioBrowserProps } from './AudioBrowser';
export { default as ImportOptionsDialog } from './ImportOptionsDialog';
export type { ImportOptions, ImportMode, FileToImport, ImportOptionsDialogProps } from './ImportOptionsDialog';
export { default as AudioPoolPanel } from './AudioPoolPanel';
export type { PoolAsset, AssetStatus, AssetLocation, AudioPoolPanelProps } from './AudioPoolPanel';

// ============ Types Re-exports ============
export type { ErrorCode, ReelForgeError } from './ErrorBoundary';

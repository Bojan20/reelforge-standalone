/**
 * ReelForge Editor
 *
 * Professional DAW UI Component Library
 *
 * Re-exports are organized by module to avoid naming conflicts.
 * Import directly from submodules for specific components.
 *
 * @example
 * // Import specific components
 * import { Arrangement } from 'reelforge-editor/arrangement';
 * import { PianoRoll } from 'reelforge-editor/piano-roll';
 *
 * Similar Modules Guide:
 * - input-number (InputNumber) - Full-featured numeric input with controls
 * - number-input (NumberInput) - Simpler version with drag-to-adjust
 * - piano-roll - Standalone PianoRoll component
 * - midi-editor - PianoRoll + useMidiEditor hook
 * - stat (Stat) - Simple statistic display
 * - statistic (Statistic) - Advanced with countdown, loading
 * - notification - Single notification component
 * - notifications - Toast system with container and hook
 *
 * @module reelforge-editor
 */

// ============ DAW Components ============
// Use namespace exports to avoid conflicts
export * as Arrangement from './arrangement';
export * as Automation from './automation';
export * as Browser from './browser';
export * as ClipEditor from './clip-editor';
export * as Engine from './engine';
export * as Fader from './fader';
export * as History from './history';
export * as Knob from './knob';
export * as Markers from './markers';
export * as Meters from './meters';
export * as MidiEditor from './midi-editor';
export * as Mixer from './mixer';
export * as PeakMeter from './peak-meter';
export * as PianoRollModule from './piano-roll';
export * as Presets from './presets';
export * as Spectrogram from './spectrogram';
export * as Timeline from './timeline';
export * as Transport from './transport';
export * as Waveform from './waveform';

// ============ UI Components ============
export * from './accordion';
export * from './affix';
export * from './alert';
export * from './anchor';
export * from './aspect-ratio';
export * from './auto-complete';
export * from './avatar';
export * from './back-top';
export * from './badge';
export * from './breadcrumbs';
export * from './card';
export * from './carousel';
export * from './cascader';
export * from './checkbox';
export * from './click-outside';
export * from './code';
export * from './collapse';
export * from './color-picker';
export * from './color-swatch';
export * from './comment';
export * from './config-provider';
export * from './context-menu';
export * from './copy';
export * from './cropper';
export * from './data-table';
export * from './date-picker';
export * from './descriptions';
export * from './dialogs';
export * from './divider';
export * from './drawer';
export * from './dropdown';
export * from './empty';
export * from './file-upload';
export * from './highlight';
export * from './image';
export * from './infinite-scroll';
export * from './input-number';
export * from './kbd';
export * from './list';
export * from './masonry';
export * from './mentions';
export * from './overlay';
export * from './pagination';
export * from './popover';
export * from './portal';
export * from './progress';
export * from './qr-code';
export * from './radio';
export * from './rating';
export * from './resizable';
export * from './result';
export * from './scrollbar';
export * from './segmented';
export * from './select';
export * from './signature';
export * from './skeleton';
export * from './slider';
export * from './spin';
export * from './splitter';
export * from './stat';
export * from './statistic';
export * from './steps';
export * from './switch';
export * from './tabs';
export * from './tag';
export * from './textarea';
export * from './time-picker';
export * from './toggle';
export * from './tour';
export * from './transfer';
export * from './tree';
export * from './tree-select';
export * from './virtual-list';
export * from './watermark';

// ============ Alternative/Extended Modules ============
// Calendar (namespace to avoid date-picker conflict)
export * as CalendarModule from './calendar';

// Notifications - different systems
export * as Notification from './notification';
export * as Notifications from './notifications';

// NumberInput - alternative with drag support
export * as NumberInput from './number-input';

// Focus trap (namespace to avoid hook conflict)
export * as FocusTrap from './focus-trap';

// ============ Core Systems ============
export * as Core from './core';
export * as Components from './components';
export * as Contexts from './contexts';
export * as Hooks from './hooks';
export * as Utils from './utils';
export * as Project from './project';
export * as Types from './types';

// ============ Store ============
export * as Store from './store';

// ============ Shortcuts ============
export * as Shortcuts from './shortcuts';

// ============ Plugin System ============
export * as Plugin from './plugin';
export * as PluginHost from './plugin-host';
export * as PluginWindow from './plugin-window';

// ============ Audio ============
export * as Audio from './audio';

// ============ ReelForge Library ============
export * as ReelForge from './reelforge';

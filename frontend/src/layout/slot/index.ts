/**
 * ReelForge Slot Components
 *
 * Specialized UI components for slot game audio design.
 *
 * @module layout/slot
 */

// Spin Cycle Editor - State machine for spin audio
export { SpinCycleEditor, generateDemoSpinCycleConfig } from './SpinCycleEditor';
export type {
  SpinCycleEditorProps,
  SpinCycleConfig,
  SpinState,
  SpinStateAudio,
} from './SpinCycleEditor';

// Win Tier Editor - Tiered win celebration audio
export { WinTierEditor, generateDemoWinTiers } from './WinTierEditor';
export type {
  WinTierEditorProps,
  WinTier,
  WinTierConfig,
  WinTierSound,
} from './WinTierEditor';

// Reel Stop Sequencer - Per-reel timing and audio
export { ReelStopSequencer, generateDemoReelConfig } from './ReelStopSequencer';
export type {
  ReelStopSequencerProps,
  ReelConfig,
  ReelStopSound,
} from './ReelStopSequencer';

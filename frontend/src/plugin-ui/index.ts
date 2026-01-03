/**
 * ReelForge Plugin UI Framework
 *
 * Common components for building plugin UIs:
 * - Knob, Fader, Button, Toggle
 * - Meter, Waveform displays
 * - Preset management
 * - A/B comparison
 * - Theming integration
 *
 * @module plugin-ui
 */

// Controls
export { PluginKnob, type PluginKnobProps } from './controls/PluginKnob';
export { PluginFader, type PluginFaderProps } from './controls/PluginFader';
export { PluginButton, type PluginButtonProps } from './controls/PluginButton';
export { PluginToggle, type PluginToggleProps } from './controls/PluginToggle';
export { PluginSelect, type PluginSelectProps, type SelectOption } from './controls/PluginSelect';

// Displays
export { PluginMeter, type PluginMeterProps } from './displays/PluginMeter';
export { PluginGraph, type PluginGraphProps } from './displays/PluginGraph';

// Layout
export { PluginPanel, type PluginPanelProps } from './layout/PluginPanel';
export { PluginSection, type PluginSectionProps } from './layout/PluginSection';
export { PluginRow, type PluginRowProps } from './layout/PluginRow';

// Preset
export { PresetBar, type PresetBarProps } from './preset/PresetBar';

// Container
export { PluginContainer, type PluginContainerProps } from './PluginContainer';

// Theme
export { usePluginTheme, type PluginTheme } from './usePluginTheme';

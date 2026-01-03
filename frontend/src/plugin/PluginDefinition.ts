/**
 * ReelForge M9.1 Plugin Definition
 *
 * Defines the interface for audio processing plugins.
 * This module provides the core contracts for the Plugin Framework.
 *
 * @module plugin/PluginDefinition
 */

import type { ComponentType } from 'react';
import type { ParamDescriptor } from './ParamDescriptor';

/**
 * Plugin category for organization.
 */
export type PluginCategory = 'eq' | 'dynamics' | 'filter' | 'modulation' | 'utility';

/**
 * DSP instance interface for plugin processing nodes.
 *
 * Each insert creates one of these to handle the actual audio processing.
 * Implementations can use native Web Audio nodes or AudioWorklet nodes.
 *
 * Signal flow:
 * [Previous Node] → getInputNode() → [Processing] → getOutputNode() → [Next Node]
 */
export interface PluginDSPInstance {
  /**
   * Connect the plugin output to a destination node.
   * Called by the host when wiring up the chain.
   */
  connect(destination: AudioNode): void;

  /**
   * Disconnect all outputs.
   * Called by the host when rewiring or disposing.
   */
  disconnect(): void;

  /**
   * Dispose of all audio nodes and release resources.
   * Called when the insert is removed from the chain.
   */
  dispose(): void;

  /**
   * Set bypass state (optional).
   * If implemented, the plugin handles its own bypass crossfade.
   * If not implemented, the host will handle bypass routing.
   */
  setBypass?(bypassed: boolean): void;

  /**
   * Apply parameter values to the DSP nodes.
   * Called on initial creation and whenever params change.
   *
   * @param params - Flat key-value map of parameter values
   */
  applyParams(params: Record<string, number>): void;

  /**
   * Get the latency introduced by this plugin instance in samples.
   * Should match the static latencySamples in PluginDefinition.
   */
  getLatencySamples(): number;

  /**
   * Get the input node for connecting from the previous stage.
   * For simple plugins, this may be the same as getOutputNode().
   */
  getInputNode(): AudioNode;

  /**
   * Get the output node for connecting to the next stage.
   */
  getOutputNode(): AudioNode;
}

/**
 * Props passed to plugin editor components.
 */
export interface PluginEditorProps {
  /** Current parameter values as a flat key-value map */
  params: Record<string, number>;

  /** Parameter descriptors for UI generation */
  descriptors: ParamDescriptor[];

  /**
   * Callback when a single parameter changes.
   * Called during user interaction (dragging, typing).
   *
   * @param paramId - The parameter ID to update
   * @param value - The new value
   */
  onChange: (paramId: string, value: number) => void;

  /**
   * Callback for batch parameter changes (atomic update).
   * Use this when multiple params change together to avoid race conditions.
   *
   * @param changes - Map of paramId -> value for all changes
   */
  onChangeBatch?: (changes: Record<string, number>) => void;

  /**
   * Reset a parameter to its default value.
   *
   * @param paramId - The parameter ID to reset
   */
  onReset: (paramId: string) => void;

  /**
   * Optional: Callback for bypass state changes.
   * Only provided if the insert supports bypass.
   */
  onBypassChange?: (bypassed: boolean) => void;

  /** Whether the insert is currently bypassed */
  bypassed?: boolean;

  /** Whether the editor is in a read-only mode */
  readOnly?: boolean;

  /**
   * AudioContext sample rate for accurate frequency calculations.
   * Used by EQ plugins to ensure UI curve matches DSP processing.
   * Defaults to 48000 if not provided.
   */
  sampleRate?: number;

  /**
   * Real-time meter data from host-side analyzer.
   * Used by EQ/analyzer plugins to display actual audio levels.
   * Optional - if not provided, demo/simulated data may be used.
   */
  meterData?: {
    rmsL: number;
    rmsR: number;
    peakL: number;
    peakR: number;
    /** FFT bins as base64 encoded Float32Array */
    fftBinsB64?: string;
  };
}

/**
 * Plugin definition interface.
 *
 * This is the contract that all plugins must implement.
 * Built-in plugins (EQ, Compressor, Limiter) are registered with this interface.
 *
 * @example
 * ```typescript
 * const myPlugin: PluginDefinition = {
 *   id: 'my-plugin',
 *   displayName: 'My Plugin',
 *   version: '1.0.0',
 *   category: 'utility',
 *   params: MY_PARAM_DESCRIPTORS,
 *   latencySamples: 0,
 *   createDSP: (ctx) => new MyPluginDSP(ctx),
 *   Editor: MyPluginEditor,
 * };
 * ```
 */
export interface PluginDefinition {
  /** Unique identifier (must match PluginId for built-ins) */
  id: string;

  /** Human-readable name for display */
  displayName: string;

  /** Short name for compact displays */
  shortName?: string;

  /** Plugin version (semver) */
  version: string;

  /** Plugin category for organization */
  category: PluginCategory;

  /** Plugin description */
  description?: string;

  /** Icon for UI (emoji or icon identifier) */
  icon?: string;

  /** Parameter descriptors for auto-UI and validation */
  params: ParamDescriptor[];

  /** Latency introduced by this plugin in samples (at 48kHz reference) */
  latencySamples: number;

  /**
   * Factory function to create a DSP instance.
   *
   * @param ctx - The AudioContext to use for creating nodes
   * @returns A new PluginDSPInstance
   */
  createDSP: (ctx: AudioContext) => PluginDSPInstance;

  /**
   * React component for the plugin editor.
   * Receives PluginEditorProps for parameter binding.
   */
  Editor: ComponentType<PluginEditorProps>;

  /**
   * Whether this plugin supports bypass (default: true).
   * If false, the bypass button will not be shown.
   */
  supportsBypass?: boolean;

  /**
   * Whether this plugin opens in a separate Electron window (default: false).
   * If true, clicking the insert opens a standalone window instead of the drawer.
   * Only applies when running in Electron; in web browser, drawer is always used.
   */
  opensInWindow?: boolean;
}

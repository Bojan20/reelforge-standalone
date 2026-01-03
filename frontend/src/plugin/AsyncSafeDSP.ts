/**
 * ReelForge Async-Safe DSP Base
 *
 * Abstract base class for AudioWorklet-based plugins with async-safe routing.
 * Guarantees signal passes through during worklet initialization.
 *
 * Signal flow (when worklet ready, not bypassed):
 *   inputGain → workletNode → wetGain → outputGain
 *                                ↑
 *   inputGain → bypassGain ──────┘ (mixed, but bypassGain = 0)
 *
 * Signal flow (when bypassed OR worklet not ready):
 *   inputGain → bypassGain → outputGain (bypass path active)
 *
 * Key guarantees:
 * 1. Signal ALWAYS passes through (bypassGain=1 until worklet ready)
 * 2. Click-free crossfade when worklet becomes ready
 * 3. Click-free bypass toggling via gain ramps
 * 4. Proper disposal of all nodes
 *
 * @module plugin/AsyncSafeDSP
 */

import type { PluginDSPInstance } from './PluginDefinition';
import { ensureModuleLoaded } from './workletHost';

/** Bypass ramp time in seconds */
const BYPASS_RAMP_TIME = 0.01; // 10ms

/**
 * Configuration for async-safe DSP instance.
 */
export interface AsyncSafeDSPConfig {
  /** Worklet processor name (registered via registerProcessor) */
  processorName: string;
  /** Path to worklet module relative to this file */
  workletPath: string;
  /** Number of output channels (default: 2) */
  outputChannels?: number;
  /** Latency in samples (default: 0) */
  latencySamples?: number;
}

/**
 * Idle state listener callback type.
 */
export type IdleStateListener = (isIdle: boolean) => void;

/**
 * Abstract base class for async-safe DSP plugins.
 *
 * Subclasses should:
 * 1. Call super() with AudioContext
 * 2. Override getConfig() to provide worklet configuration
 * 3. Override transformParams() to convert flat params to worklet message format
 * 4. Call initWorklet() in their factory method
 */
export abstract class AsyncSafeDSP implements PluginDSPInstance {
  protected readonly ctx: AudioContext;
  protected readonly inputGain: GainNode;
  protected readonly outputGain: GainNode;
  protected readonly bypassGain: GainNode;
  protected readonly wetGain: GainNode;
  protected workletNode: AudioWorkletNode | null = null;
  protected bypassed = false;
  protected disposed = false;

  /** Pending params to apply once worklet is ready */
  protected pendingParams: Record<string, number> | null = null;

  /** Idle state from worklet (no signal detected) */
  protected _isIdle = true;
  protected idleListeners: Set<IdleStateListener> = new Set();

  /**
   * Create an async-safe DSP instance.
   * Signal flows through bypass path immediately (unity gain).
   */
  constructor(ctx: AudioContext) {
    this.ctx = ctx;

    // Create gain nodes for routing
    this.inputGain = ctx.createGain();
    this.outputGain = ctx.createGain();
    this.bypassGain = ctx.createGain();
    this.wetGain = ctx.createGain();

    // CRITICAL: Start with bypass path ACTIVE (gain = 1) so signal passes through
    // immediately before worklet is ready. Once worklet is ready, we crossfade.
    this.bypassGain.gain.value = 1;
    this.wetGain.gain.value = 0; // Wet path silent until worklet ready

    // Connect bypass path (always connected, gain controls mixing)
    this.inputGain.connect(this.bypassGain);
    this.bypassGain.connect(this.outputGain);

    // Wet path output (worklet will be connected later)
    this.wetGain.connect(this.outputGain);
  }

  /**
   * Get worklet configuration. Must be implemented by subclass.
   */
  protected abstract getConfig(): AsyncSafeDSPConfig;

  /**
   * Transform flat params to worklet message format.
   * Override in subclass to customize param handling.
   */
  protected abstract transformParams(params: Record<string, number>): unknown;

  /**
   * Handle messages from worklet (override for custom handling).
   * Default implementation handles 'idle' messages.
   */
  protected handleWorkletMessage(data: { type: string; [key: string]: unknown }): void {
    if (data.type === 'idle' && typeof data.isIdle === 'boolean') {
      this._isIdle = data.isIdle;
      this.idleListeners.forEach((listener) => listener(this._isIdle));
    }
  }

  /**
   * Initialize the AudioWorklet node.
   * Call this from the factory method after construction.
   */
  protected async initWorklet(): Promise<void> {
    if (this.disposed) return;

    const config = this.getConfig();

    try {
      // Get the worklet module URL
      const moduleUrl = new URL(config.workletPath, import.meta.url).href;

      // Ensure module is loaded (cached per context)
      await ensureModuleLoaded(this.ctx, moduleUrl);

      if (this.disposed) return;

      // Create the worklet node
      this.workletNode = new AudioWorkletNode(this.ctx, config.processorName, {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [config.outputChannels ?? 2],
      });

      // Listen for messages from worklet
      this.workletNode.port.onmessage = (event) => {
        this.handleWorkletMessage(event.data);
      };

      // Connect worklet to wet gain (inputGain → worklet → wetGain → outputGain)
      this.inputGain.connect(this.workletNode);
      this.workletNode.connect(this.wetGain);

      // Apply any pending params that arrived before worklet was ready
      if (this.pendingParams) {
        this.applyParams(this.pendingParams);
        this.pendingParams = null;
      }

      // Crossfade from bypass to wet path (unless already bypassed)
      if (!this.bypassed) {
        const now = this.ctx.currentTime;
        this.bypassGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
        this.wetGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
      }
    } catch (err) {
      console.error(`[${config.processorName}] Worklet initialization failed:`, err);
      // Fallback: bypass path is already active, just log the error
      // Signal continues to flow through bypassGain → outputGain
    }
  }

  /**
   * Connect the plugin output to a destination node.
   */
  connect(destination: AudioNode): void {
    this.outputGain.connect(destination);
  }

  /**
   * Disconnect all outputs.
   */
  disconnect(): void {
    this.outputGain.disconnect();
  }

  /**
   * Dispose of all audio nodes and release resources.
   */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;

    try {
      this.inputGain.disconnect();
      this.bypassGain.disconnect();
      this.wetGain.disconnect();
      this.outputGain.disconnect();
      if (this.workletNode) {
        this.workletNode.disconnect();
        this.workletNode = null;
      }
    } catch {
      // Ignore disconnection errors during disposal
    }

    this.idleListeners.clear();
  }

  /**
   * Set bypass state with click-free ramping.
   */
  setBypass(bypassed: boolean): void {
    if (this.bypassed === bypassed) return;
    this.bypassed = bypassed;

    const now = this.ctx.currentTime;

    if (bypassed) {
      // Fade in bypass path, fade out wet path
      this.bypassGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
      this.wetGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
    } else {
      // Fade out bypass path, fade in wet path (only if worklet is ready)
      if (this.workletNode) {
        this.bypassGain.gain.linearRampToValueAtTime(0, now + BYPASS_RAMP_TIME);
        this.wetGain.gain.linearRampToValueAtTime(1, now + BYPASS_RAMP_TIME);
      }
      // If worklet not ready, stay on bypass path (bypass gains stay as-is)
    }
  }

  /**
   * Apply parameter values to the DSP nodes.
   */
  applyParams(params: Record<string, number>): void {
    if (!this.workletNode) {
      // Worklet not ready yet - queue latest params for later
      this.pendingParams = params;
      return;
    }

    // Transform and send to worklet
    const message = this.transformParams(params);
    this.workletNode.port.postMessage(message);
  }

  /**
   * Get the latency introduced by this plugin in samples.
   */
  getLatencySamples(): number {
    return this.getConfig().latencySamples ?? 0;
  }

  /**
   * Get the input node for connecting from the previous stage.
   */
  getInputNode(): AudioNode {
    return this.inputGain;
  }

  /**
   * Get the output node for connecting to the next stage.
   */
  getOutputNode(): AudioNode {
    return this.outputGain;
  }

  /**
   * Check if the worklet is ready.
   */
  isReady(): boolean {
    return this.workletNode !== null;
  }

  /**
   * Reset processor state (sends reset message to worklet).
   */
  reset(): void {
    if (this.workletNode) {
      this.workletNode.port.postMessage({ type: 'reset' });
    }
  }

  /**
   * Get current idle state.
   */
  get isIdle(): boolean {
    return this._isIdle;
  }

  /**
   * Subscribe to idle state changes.
   */
  onIdleChange(listener: IdleStateListener): () => void {
    this.idleListeners.add(listener);
    return () => {
      this.idleListeners.delete(listener);
    };
  }
}

/**
 * Create a simple passthrough DSP instance for stub plugins.
 * Uses the async-safe pattern even though it's synchronous,
 * ensuring consistent behavior across all plugins.
 */
export function createPassthroughDSP(ctx: AudioContext): PluginDSPInstance {
  const inputGain = ctx.createGain();
  const outputGain = ctx.createGain();
  const bypassGain = ctx.createGain();

  // Unity gain passthrough
  inputGain.gain.value = 1;
  outputGain.gain.value = 1;
  bypassGain.gain.value = 1;

  // Direct connection (no processing)
  inputGain.connect(bypassGain);
  bypassGain.connect(outputGain);

  let bypassed = false;
  let disposed = false;

  return {
    connect(destination: AudioNode): void {
      if (!disposed) outputGain.connect(destination);
    },

    disconnect(): void {
      if (!disposed) {
        try {
          outputGain.disconnect();
        } catch {
          // Ignore
        }
      }
    },

    dispose(): void {
      if (disposed) return;
      disposed = true;
      try {
        inputGain.disconnect();
        bypassGain.disconnect();
        outputGain.disconnect();
      } catch {
        // Ignore
      }
    },

    setBypass(bypass: boolean): void {
      if (bypassed === bypass) return;
      bypassed = bypass;
      // For passthrough, bypass does nothing (already unity gain)
    },

    applyParams(_params: Record<string, number>): void {
      // No-op for passthrough
    },

    getLatencySamples(): number {
      return 0;
    },

    getInputNode(): AudioNode {
      return inputGain;
    },

    getOutputNode(): AudioNode {
      return outputGain;
    },
  };
}

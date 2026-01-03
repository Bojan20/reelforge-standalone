/**
 * AudioNodeFactory
 *
 * Centralized factory for creating and managing Web Audio nodes.
 * Reduces code duplication and provides consistent error handling.
 *
 * Benefits:
 * - Consistent node creation patterns
 * - Automatic parameter ramping for click-free updates
 * - Lifecycle tracking for debugging
 * - Future: Node pooling for voice reuse
 */

import { rfDebug } from './dspMetrics';
import {
  PARAM_RAMP_SEC,
  UNITY_GAIN,
  DEFAULT_Q,
  DEFAULT_SAMPLE_RATE,
} from './audioConstants';

// ============ Types ============

export interface GainNodeOptions {
  gain?: number;
  destination?: AudioNode;
}

export interface BiquadOptions {
  type?: BiquadFilterType;
  frequency?: number;
  Q?: number;
  gain?: number;
  destination?: AudioNode;
}

export interface CompressorOptions {
  threshold?: number;
  knee?: number;
  ratio?: number;
  attack?: number;
  release?: number;
  destination?: AudioNode;
}

export interface DelayOptions {
  maxDelayTime?: number;
  delayTime?: number;
  destination?: AudioNode;
}

// ============ Factory Class ============

export class AudioNodeFactory {
  private ctx: AudioContext;
  private createdNodes: Set<AudioNode> = new Set();

  constructor(ctx: AudioContext) {
    this.ctx = ctx;
  }

  /**
   * Create a gain node with optional initial gain and connection.
   */
  createGain(options: GainNodeOptions = {}): GainNode {
    const { gain = UNITY_GAIN, destination } = options;

    const node = this.ctx.createGain();
    node.gain.value = gain;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    rfDebug('AudioNodeFactory', `Created GainNode (gain=${gain})`);

    return node;
  }

  /**
   * Create a biquad filter with options.
   */
  createBiquad(options: BiquadOptions = {}): BiquadFilterNode {
    const {
      type = 'peaking',
      frequency = 1000,
      Q = DEFAULT_Q,
      gain = 0,
      destination,
    } = options;

    const node = this.ctx.createBiquadFilter();
    node.type = type;
    node.frequency.value = frequency;
    node.Q.value = Q;
    node.gain.value = gain;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    rfDebug('AudioNodeFactory', `Created BiquadFilter (${type} @ ${frequency}Hz)`);

    return node;
  }

  /**
   * Create a dynamics compressor with options.
   */
  createCompressor(options: CompressorOptions = {}): DynamicsCompressorNode {
    const {
      threshold = -24,
      knee = 6,
      ratio = 4,
      attack = 0.01,
      release = 0.1,
      destination,
    } = options;

    const node = this.ctx.createDynamicsCompressor();
    node.threshold.value = threshold;
    node.knee.value = knee;
    node.ratio.value = ratio;
    node.attack.value = attack;
    node.release.value = release;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    rfDebug('AudioNodeFactory', `Created DynamicsCompressor (threshold=${threshold}dB)`);

    return node;
  }

  /**
   * Create a delay node with options.
   */
  createDelay(options: DelayOptions = {}): DelayNode {
    const {
      maxDelayTime = 1.0,
      delayTime = 0,
      destination,
    } = options;

    const node = this.ctx.createDelay(maxDelayTime);
    node.delayTime.value = delayTime;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    rfDebug('AudioNodeFactory', `Created DelayNode (max=${maxDelayTime}s)`);

    return node;
  }

  /**
   * Create a stereo panner.
   */
  createPanner(pan: number = 0, destination?: AudioNode): StereoPannerNode {
    const node = this.ctx.createStereoPanner();
    node.pan.value = Math.max(-1, Math.min(1, pan));

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    return node;
  }

  /**
   * Create an analyser node for metering.
   */
  createAnalyser(fftSize: number = 2048, destination?: AudioNode): AnalyserNode {
    const node = this.ctx.createAnalyser();
    node.fftSize = fftSize;
    node.smoothingTimeConstant = 0.8;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    return node;
  }

  /**
   * Create a buffer source for one-shot playback.
   */
  createBufferSource(
    buffer: AudioBuffer,
    destination?: AudioNode
  ): AudioBufferSourceNode {
    const node = this.ctx.createBufferSource();
    node.buffer = buffer;

    if (destination) {
      node.connect(destination);
    }

    this.createdNodes.add(node);
    return node;
  }

  // ============ Click-Free Parameter Updates ============

  /**
   * Set gain with click-free ramping.
   */
  setGainSmooth(gainNode: GainNode, value: number, rampTime: number = PARAM_RAMP_SEC): void {
    const now = this.ctx.currentTime;
    gainNode.gain.cancelScheduledValues(now);
    gainNode.gain.setValueAtTime(gainNode.gain.value, now);
    gainNode.gain.linearRampToValueAtTime(value, now + rampTime);
  }

  /**
   * Set frequency with click-free ramping.
   */
  setFrequencySmooth(
    node: BiquadFilterNode | OscillatorNode,
    value: number,
    rampTime: number = PARAM_RAMP_SEC
  ): void {
    const now = this.ctx.currentTime;
    node.frequency.cancelScheduledValues(now);
    node.frequency.setValueAtTime(node.frequency.value, now);
    node.frequency.exponentialRampToValueAtTime(Math.max(1, value), now + rampTime);
  }

  /**
   * Set delay time with click-free ramping.
   */
  setDelaySmooth(delayNode: DelayNode, value: number, rampTime: number = PARAM_RAMP_SEC): void {
    const now = this.ctx.currentTime;
    delayNode.delayTime.cancelScheduledValues(now);
    delayNode.delayTime.setValueAtTime(delayNode.delayTime.value, now);
    delayNode.delayTime.linearRampToValueAtTime(value, now + rampTime);
  }

  // ============ Utility Methods ============

  /**
   * Connect multiple nodes in series.
   */
  chain(...nodes: AudioNode[]): void {
    for (let i = 0; i < nodes.length - 1; i++) {
      nodes[i].connect(nodes[i + 1]);
    }
  }

  /**
   * Disconnect and cleanup a node.
   */
  dispose(node: AudioNode): void {
    try {
      node.disconnect();
      this.createdNodes.delete(node);
    } catch {
      // Already disconnected
    }
  }

  /**
   * Dispose all created nodes.
   */
  disposeAll(): void {
    for (const node of this.createdNodes) {
      try {
        node.disconnect();
      } catch {
        // Ignore
      }
    }
    this.createdNodes.clear();
    rfDebug('AudioNodeFactory', 'Disposed all nodes');
  }

  /**
   * Get count of active nodes (for debugging).
   */
  getActiveNodeCount(): number {
    return this.createdNodes.size;
  }

  /**
   * Get the AudioContext.
   */
  getContext(): AudioContext {
    return this.ctx;
  }

  /**
   * Get current sample rate.
   */
  getSampleRate(): number {
    return this.ctx.sampleRate ?? DEFAULT_SAMPLE_RATE;
  }
}

// ============ Singleton Factory ============

let defaultFactory: AudioNodeFactory | null = null;

/**
 * Get or create the default factory for the shared AudioContext.
 */
export function getDefaultAudioNodeFactory(ctx: AudioContext): AudioNodeFactory {
  if (!defaultFactory || defaultFactory.getContext() !== ctx) {
    defaultFactory = new AudioNodeFactory(ctx);
  }
  return defaultFactory;
}

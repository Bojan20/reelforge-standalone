/**
 * ReelForge Plugin Wrapper
 *
 * Base classes for wrapping different plugin formats.
 * Provides uniform interface for all plugin types.
 *
 * @module plugin-system/PluginWrapper
 */

import type {
  PluginInstance,
  PluginParameter,
  PluginState,
  PluginDescriptor,
} from './PluginRegistry';

// ============ Base Plugin Class ============

export abstract class BasePlugin implements PluginInstance {
  id: string = '';
  descriptorId: string = '';

  protected sampleRate: number = 44100;
  protected blockSize: number = 512;
  protected parameters = new Map<string, PluginParameterValue>();
  protected isInitialized: boolean = false;

  protected descriptor: PluginDescriptor;

  constructor(descriptor: PluginDescriptor) {
    this.descriptor = descriptor;
    // Initialize parameters with defaults
    for (const param of descriptor.parameters) {
      this.parameters.set(param.id, {
        definition: param,
        value: param.defaultValue,
      });
    }
  }

  // ============ Lifecycle ============

  async initialize(sampleRate: number, blockSize: number): Promise<void> {
    this.sampleRate = sampleRate;
    this.blockSize = blockSize;
    this.isInitialized = true;
    await this.onInitialize();
  }

  dispose(): void {
    this.onDispose();
    this.isInitialized = false;
  }

  reset(): void {
    // Reset parameters to defaults
    for (const [, param] of this.parameters) {
      param.value = param.definition.defaultValue;
    }
    this.onReset();
  }

  // ============ Processing ============

  abstract process(inputs: Float32Array[][], outputs: Float32Array[][]): void;

  // ============ Parameters ============

  getParameter(id: string): number {
    return this.parameters.get(id)?.value ?? 0;
  }

  setParameter(id: string, value: number): void {
    const param = this.parameters.get(id);
    if (!param) return;

    // Clamp to range
    if (param.definition.minValue !== undefined) {
      value = Math.max(param.definition.minValue, value);
    }
    if (param.definition.maxValue !== undefined) {
      value = Math.min(param.definition.maxValue, value);
    }

    param.value = value;
    this.onParameterChange(id, value);
  }

  getParameterNormalized(id: string): number {
    const param = this.parameters.get(id);
    if (!param) return 0;

    const { minValue = 0, maxValue = 1 } = param.definition;
    return (param.value - minValue) / (maxValue - minValue);
  }

  setParameterNormalized(id: string, value: number): void {
    const param = this.parameters.get(id);
    if (!param) return;

    const { minValue = 0, maxValue = 1 } = param.definition;
    const denormalized = minValue + value * (maxValue - minValue);
    this.setParameter(id, denormalized);
  }

  getParameterInfo(id: string): PluginParameter | undefined {
    return this.parameters.get(id)?.definition;
  }

  getAllParameters(): Map<string, PluginParameterValue> {
    return new Map(this.parameters);
  }

  // ============ State ============

  getState(): PluginState {
    const parameters: Record<string, number> = {};
    for (const [id, param] of this.parameters) {
      parameters[id] = param.value;
    }

    return {
      descriptorId: this.descriptorId,
      version: this.descriptor.version,
      parameters,
      customData: this.getCustomState(),
    };
  }

  setState(state: PluginState): void {
    // Restore parameters
    for (const [id, value] of Object.entries(state.parameters)) {
      this.setParameter(id, value);
    }

    // Restore custom state
    if (state.customData) {
      this.setCustomState(state.customData);
    }
  }

  // ============ Protected Methods (Override in subclasses) ============

  protected async onInitialize(): Promise<void> {}
  protected onDispose(): void {}
  protected onReset(): void {}
  protected onParameterChange(_id: string, _value: number): void {}
  protected getCustomState(): unknown { return undefined; }
  protected setCustomState(_data: unknown): void {}
}

interface PluginParameterValue {
  definition: PluginParameter;
  value: number;
}

// ============ Web Audio Plugin ============

export abstract class WebAudioPlugin extends BasePlugin {
  protected context: AudioContext | null = null;
  protected inputNode: GainNode | null = null;
  protected outputNode: GainNode | null = null;

  /**
   * Connect to Web Audio API.
   */
  connectToContext(context: AudioContext): void {
    this.context = context;
    this.inputNode = context.createGain();
    this.outputNode = context.createGain();
    this.buildAudioGraph();
  }

  /**
   * Get input node for connection.
   */
  getInputNode(): AudioNode | null {
    return this.inputNode;
  }

  /**
   * Get output node for connection.
   */
  getOutputNode(): AudioNode | null {
    return this.outputNode;
  }

  /**
   * Build internal audio graph.
   * Override in subclasses.
   */
  protected abstract buildAudioGraph(): void;

  override process(_inputs: Float32Array[][], _outputs: Float32Array[][]): void {
    // Web Audio plugins don't use manual processing
    // Audio flows through the graph automatically
  }

  protected override onDispose(): void {
    this.inputNode?.disconnect();
    this.outputNode?.disconnect();
    this.inputNode = null;
    this.outputNode = null;
    this.context = null;
  }
}

// ============ AudioWorklet Plugin ============

export abstract class AudioWorkletPlugin extends BasePlugin {
  protected workletNode: AudioWorkletNode | null = null;
  protected context: AudioContext | null = null;

  /**
   * Get worklet processor name.
   */
  abstract getProcessorName(): string;

  /**
   * Get worklet module URL.
   */
  abstract getProcessorUrl(): string;

  /**
   * Connect to Web Audio API with AudioWorklet.
   */
  async connectToContext(context: AudioContext): Promise<void> {
    this.context = context;

    // Load worklet module
    await context.audioWorklet.addModule(this.getProcessorUrl());

    // Create worklet node
    this.workletNode = new AudioWorkletNode(context, this.getProcessorName(), {
      numberOfInputs: this.descriptor.numInputs,
      numberOfOutputs: this.descriptor.numOutputs,
      parameterData: this.getInitialParameterData(),
    });

    // Sync parameters
    this.syncParametersToWorklet();
  }

  /**
   * Get worklet node for connection.
   */
  getWorkletNode(): AudioWorkletNode | null {
    return this.workletNode;
  }

  protected getInitialParameterData(): Record<string, number> {
    const data: Record<string, number> = {};
    for (const [id, param] of this.parameters) {
      data[id] = param.value;
    }
    return data;
  }

  protected syncParametersToWorklet(): void {
    if (!this.workletNode) return;

    for (const [id, param] of this.parameters) {
      const audioParam = this.workletNode.parameters.get(id);
      if (audioParam) {
        audioParam.value = param.value;
      }
    }
  }

  protected override onParameterChange(id: string, value: number): void {
    if (!this.workletNode) return;

    const audioParam = this.workletNode.parameters.get(id);
    if (audioParam) {
      audioParam.value = value;
    }
  }

  override process(_inputs: Float32Array[][], _outputs: Float32Array[][]): void {
    // AudioWorklet plugins process in the worklet thread
  }

  protected override onDispose(): void {
    this.workletNode?.disconnect();
    this.workletNode = null;
    this.context = null;
  }
}

// ============ Script Processor Plugin (Legacy) ============

export abstract class ScriptProcessorPlugin extends BasePlugin {
  protected scriptNode: ScriptProcessorNode | null = null;
  protected context: AudioContext | null = null;

  /**
   * Connect to Web Audio API with ScriptProcessor.
   * @deprecated Use AudioWorkletPlugin instead
   */
  connectToContext(context: AudioContext, bufferSize: number = 1024): void {
    this.context = context;

    this.scriptNode = context.createScriptProcessor(
      bufferSize,
      this.descriptor.numInputs,
      this.descriptor.numOutputs
    );

    this.scriptNode.onaudioprocess = (event) => {
      const inputs: Float32Array[][] = [];
      const outputs: Float32Array[][] = [];

      // Collect inputs
      for (let ch = 0; ch < event.inputBuffer.numberOfChannels; ch++) {
        inputs.push([event.inputBuffer.getChannelData(ch)]);
      }

      // Collect outputs
      for (let ch = 0; ch < event.outputBuffer.numberOfChannels; ch++) {
        outputs.push([event.outputBuffer.getChannelData(ch)]);
      }

      this.process(inputs, outputs);
    };
  }

  /**
   * Get script node for connection.
   */
  getScriptNode(): ScriptProcessorNode | null {
    return this.scriptNode;
  }

  protected override onDispose(): void {
    if (this.scriptNode) {
      this.scriptNode.onaudioprocess = null;
      this.scriptNode.disconnect();
      this.scriptNode = null;
    }
    this.context = null;
  }
}

// ============ Offline Processor Plugin ============

export abstract class OfflinePlugin extends BasePlugin {
  /**
   * Process entire buffer offline.
   */
  abstract processBuffer(input: AudioBuffer): Promise<AudioBuffer>;

  override process(_inputs: Float32Array[][], _outputs: Float32Array[][]): void {
    // Offline plugins don't support real-time processing
    throw new Error('Offline plugins do not support real-time processing');
  }
}

// ============ Helper Functions ============

/**
 * Create parameter definition.
 */
export function createParameter(
  id: string,
  name: string,
  options: Partial<PluginParameter> = {}
): PluginParameter {
  return {
    id,
    name,
    type: options.type ?? 'float',
    defaultValue: options.defaultValue ?? 0,
    minValue: options.minValue ?? 0,
    maxValue: options.maxValue ?? 1,
    step: options.step,
    choices: options.choices,
    unit: options.unit,
    automatable: options.automatable ?? true,
  };
}

/**
 * Create float parameter.
 */
export function floatParam(
  id: string,
  name: string,
  defaultValue: number,
  min: number,
  max: number,
  unit?: string
): PluginParameter {
  return createParameter(id, name, {
    type: 'float',
    defaultValue,
    minValue: min,
    maxValue: max,
    unit,
  });
}

/**
 * Create dB parameter.
 */
export function dbParam(
  id: string,
  name: string,
  defaultValue: number,
  min: number = -60,
  max: number = 12
): PluginParameter {
  return createParameter(id, name, {
    type: 'float',
    defaultValue,
    minValue: min,
    maxValue: max,
    unit: 'dB',
  });
}

/**
 * Create frequency parameter.
 */
export function freqParam(
  id: string,
  name: string,
  defaultValue: number,
  min: number = 20,
  max: number = 20000
): PluginParameter {
  return createParameter(id, name, {
    type: 'float',
    defaultValue,
    minValue: min,
    maxValue: max,
    unit: 'Hz',
  });
}

/**
 * Create choice parameter.
 */
export function choiceParam(
  id: string,
  name: string,
  choices: string[],
  defaultIndex: number = 0
): PluginParameter {
  return createParameter(id, name, {
    type: 'choice',
    defaultValue: defaultIndex,
    minValue: 0,
    maxValue: choices.length - 1,
    choices,
  });
}

/**
 * Create boolean parameter.
 */
export function boolParam(
  id: string,
  name: string,
  defaultValue: boolean = false
): PluginParameter {
  return createParameter(id, name, {
    type: 'bool',
    defaultValue: defaultValue ? 1 : 0,
    minValue: 0,
    maxValue: 1,
  });
}

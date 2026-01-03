/**
 * DSP Plugin Adapters
 *
 * Adapts DSPPlugin classes from dspPlugins.ts to PluginDefinition interface
 * for registration in the plugin registry.
 *
 * @module plugin/dspPluginAdapters
 */

import type { PluginDefinition, PluginDSPInstance, PluginEditorProps, PluginCategory } from './PluginDefinition';
import type { ParamDescriptor, ParamUnit } from './ParamDescriptor';
import {
  ReverbPlugin,
  DelayPlugin,
  ChorusPlugin,
  PhaserPlugin,
  FlangerPlugin,
  TremoloPlugin,
  DistortionPlugin,
  FilterPlugin,
  type DSPPlugin,
} from '../core/dspPlugins';

// ============ Generic DSP Wrapper ============

/**
 * Wraps a DSPPlugin instance to conform to PluginDSPInstance interface.
 */
class DSPPluginWrapper implements PluginDSPInstance {
  private plugin: DSPPlugin;

  constructor(plugin: DSPPlugin) {
    this.plugin = plugin;
  }

  connect(destination: AudioNode): void {
    this.plugin.connect(destination);
  }

  disconnect(): void {
    this.plugin.disconnect();
  }

  dispose(): void {
    this.plugin.dispose();
  }

  setBypass(bypassed: boolean): void {
    this.plugin.setEnabled(!bypassed);
  }

  applyParams(params: Record<string, number>): void {
    for (const [key, value] of Object.entries(params)) {
      if (key === 'wetdry') {
        this.plugin.setWetDry(value);
      } else {
        this.plugin.setParameter(key, value);
      }
    }
  }

  getLatencySamples(): number {
    return 0; // DSP plugins have no lookahead latency
  }

  getInputNode(): AudioNode {
    return this.plugin.inputNode;
  }

  getOutputNode(): AudioNode {
    return this.plugin.outputNode;
  }
}

// ============ Helper to create ParamDescriptor ============

function param(
  id: string,
  name: string,
  min: number,
  max: number,
  defaultVal: number,
  step: number,
  unit?: ParamUnit
): ParamDescriptor {
  return {
    id,
    name,
    min,
    max,
    default: defaultVal,
    step,
    fineStep: step / 10,
    unit,
  };
}

// ============ Generic Plugin Editor ============

/**
 * Generic editor component for DSP plugins.
 * Renders sliders for all parameters.
 */
function GenericPluginEditor({ params, descriptors, onChange, onReset }: PluginEditorProps) {
  return (
    <div className="rf-generic-plugin-editor">
      <div className="rf-plugin-params">
        {descriptors.map((desc) => (
          <div key={desc.id} className="rf-plugin-param">
            <div className="rf-plugin-param__header">
              <label className="rf-plugin-param__label">{desc.name}</label>
              <button
                className="rf-plugin-param__reset"
                onClick={() => onReset(desc.id)}
                title="Reset to default"
              >
                ↺
              </button>
            </div>
            <div className="rf-plugin-param__control">
              <input
                type="range"
                min={desc.min}
                max={desc.max}
                step={desc.step ?? (desc.max - desc.min) / 100}
                value={params[desc.id] ?? desc.default}
                onChange={(e) => onChange(desc.id, parseFloat(e.target.value))}
                className="rf-plugin-param__slider"
              />
              <span className="rf-plugin-param__value">
                {(params[desc.id] ?? desc.default).toFixed(desc.unit === 'Hz' ? 0 : 2)}
                {desc.unit ? ` ${desc.unit}` : ''}
              </span>
            </div>
          </div>
        ))}
      </div>
      <style>{`
        .rf-generic-plugin-editor {
          padding: 16px;
          background: var(--rf-bg-1, #121214);
        }
        .rf-plugin-params {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        .rf-plugin-param {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .rf-plugin-param__header {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }
        .rf-plugin-param__label {
          font-size: 11px;
          font-weight: 500;
          color: var(--rf-text-secondary, #888892);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .rf-plugin-param__reset {
          padding: 2px 6px;
          background: transparent;
          border: none;
          color: var(--rf-text-secondary, #888892);
          cursor: pointer;
          font-size: 12px;
          opacity: 0.6;
          transition: opacity 0.15s;
        }
        .rf-plugin-param__reset:hover {
          opacity: 1;
          color: var(--rf-accent-primary, #0ea5e9);
        }
        .rf-plugin-param__control {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .rf-plugin-param__slider {
          flex: 1;
          height: 4px;
          -webkit-appearance: none;
          background: var(--rf-bg-3, #252528);
          border-radius: 2px;
          outline: none;
        }
        .rf-plugin-param__slider::-webkit-slider-thumb {
          -webkit-appearance: none;
          width: 14px;
          height: 14px;
          background: var(--rf-accent-primary, #0ea5e9);
          border-radius: 50%;
          cursor: pointer;
        }
        .rf-plugin-param__value {
          min-width: 60px;
          font-size: 11px;
          font-family: 'SF Mono', monospace;
          color: var(--rf-text-primary, #f0f0f2);
          text-align: right;
        }
      `}</style>
    </div>
  );
}

// ============ Plugin Definitions ============

/**
 * Reverb plugin definition.
 */
export const REVERB_PLUGIN: PluginDefinition = {
  id: 'reverb',
  displayName: 'Reverb',
  shortName: 'Rev',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'Convolution-based reverb with decay control',
  icon: '🌊',
  params: [
    param('decay', 'Decay', 0.1, 10, 2.0, 0.1, 's'),
    param('predelay', 'Pre-Delay', 0, 100, 10, 1, 'ms'),
    param('highcut', 'High Cut', 1000, 20000, 8000, 100, 'Hz'),
    param('lowcut', 'Low Cut', 20, 1000, 200, 10, 'Hz'),
    param('wetdry', 'Wet/Dry', 0, 1, 0.3, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new ReverbPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Delay plugin definition.
 */
export const DELAY_PLUGIN: PluginDefinition = {
  id: 'delay',
  displayName: 'Delay',
  shortName: 'Dly',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'Stereo delay with feedback and filtering',
  icon: '📢',
  params: [
    param('time', 'Time', 1, 2000, 375, 1, 'ms'),
    param('feedback', 'Feedback', 0, 0.95, 0.4, 0.01),
    param('highcut', 'High Cut', 500, 20000, 6000, 100, 'Hz'),
    param('wetdry', 'Wet/Dry', 0, 1, 0.3, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new DelayPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Chorus plugin definition.
 */
export const CHORUS_PLUGIN: PluginDefinition = {
  id: 'chorus',
  displayName: 'Chorus',
  shortName: 'Chr',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'Multi-voice chorus for thickening',
  icon: '🎭',
  params: [
    param('rate', 'Rate', 0.1, 10, 1.5, 0.1, 'Hz'),
    param('depth', 'Depth', 0, 30, 10, 0.5, 'ms'),
    param('voices', 'Voices', 1, 4, 2, 1),
    param('spread', 'Spread', 0, 1, 0.8, 0.01),
    param('wetdry', 'Wet/Dry', 0, 1, 0.5, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new ChorusPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Phaser plugin definition.
 */
export const PHASER_PLUGIN: PluginDefinition = {
  id: 'phaser',
  displayName: 'Phaser',
  shortName: 'Phs',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'All-pass filter phaser effect',
  icon: '🌀',
  params: [
    param('rate', 'Rate', 0.1, 10, 0.5, 0.1, 'Hz'),
    param('depth', 'Depth', 0, 1, 0.7, 0.01),
    param('feedback', 'Feedback', 0, 0.95, 0.5, 0.01),
    param('stages', 'Stages', 2, 12, 4, 2),
    param('basefreq', 'Base Freq', 100, 5000, 1000, 50, 'Hz'),
    param('wetdry', 'Wet/Dry', 0, 1, 0.5, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new PhaserPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Flanger plugin definition.
 */
export const FLANGER_PLUGIN: PluginDefinition = {
  id: 'flanger',
  displayName: 'Flanger',
  shortName: 'Flg',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'Short modulated delay flanger',
  icon: '✨',
  params: [
    param('rate', 'Rate', 0.1, 5, 0.3, 0.1, 'Hz'),
    param('depth', 'Depth', 0, 10, 2, 0.1, 'ms'),
    param('feedback', 'Feedback', -0.95, 0.95, 0.5, 0.01),
    param('wetdry', 'Wet/Dry', 0, 1, 0.5, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new FlangerPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Tremolo plugin definition.
 */
export const TREMOLO_PLUGIN: PluginDefinition = {
  id: 'tremolo',
  displayName: 'Tremolo',
  shortName: 'Trm',
  version: '1.0.0',
  category: 'modulation' as PluginCategory,
  description: 'Amplitude modulation tremolo',
  icon: '〰️',
  params: [
    param('rate', 'Rate', 0.1, 20, 5, 0.1, 'Hz'),
    param('depth', 'Depth', 0, 1, 0.5, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new TremoloPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Distortion plugin definition.
 */
export const DISTORTION_PLUGIN: PluginDefinition = {
  id: 'distortion',
  displayName: 'Distortion',
  shortName: 'Dist',
  version: '1.0.0',
  category: 'dynamics' as PluginCategory,
  description: 'Waveshaper-based distortion',
  icon: '🔥',
  params: [
    param('drive', 'Drive', 0, 100, 50, 1, '%'),
    param('tone', 'Tone', 500, 20000, 4000, 100, 'Hz'),
    param('outputgain', 'Output', -24, 12, 0, 0.5, 'dB'),
    param('wetdry', 'Wet/Dry', 0, 1, 1, 0.01),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new DistortionPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

/**
 * Filter plugin definition.
 */
export const FILTER_PLUGIN: PluginDefinition = {
  id: 'filter',
  displayName: 'Filter',
  shortName: 'Flt',
  version: '1.0.0',
  category: 'filter' as PluginCategory,
  description: 'Multi-mode biquad filter',
  icon: '🎚️',
  params: [
    param('frequency', 'Frequency', 20, 20000, 1000, 10, 'Hz'),
    param('q', 'Q', 0.1, 30, 1, 0.1),
    param('gain', 'Gain', -24, 24, 0, 0.5, 'dB'),
  ],
  latencySamples: 0,
  createDSP: (ctx: AudioContext) => new DSPPluginWrapper(new FilterPlugin(ctx)),
  Editor: GenericPluginEditor,
  supportsBypass: true,
};

// ============ Export All Plugins ============

export const DSP_PLUGINS: PluginDefinition[] = [
  REVERB_PLUGIN,
  DELAY_PLUGIN,
  CHORUS_PLUGIN,
  PHASER_PLUGIN,
  FLANGER_PLUGIN,
  TREMOLO_PLUGIN,
  DISTORTION_PLUGIN,
  FILTER_PLUGIN,
];

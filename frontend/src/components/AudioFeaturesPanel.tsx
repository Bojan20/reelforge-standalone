/**
 * ReelForge Audio Features Panel
 *
 * Comprehensive panel for all professional audio systems:
 * - Intensity Layers
 * - Ducking Manager
 * - Sound Variations
 * - Voice Concurrency
 * - Sequence Containers
 * - Stingers
 * - Parameter Modifiers (LFO, Envelope, Automation)
 * - Blend Containers
 * - Priority System
 * - Audio Diagnostics & Profiler
 * - DSP Plugins
 * - Spatial Audio
 *
 * @module components/AudioFeaturesPanel
 */

import { memo, useState, useCallback } from 'react';
import type { BusId } from '../core/types';
import {
  // Intensity Layers
  DEFAULT_LAYER_CONFIGS,
  type IntensityLayerConfig,
  // Ducking
  DEFAULT_DUCKING_RULES,
  type DuckingRule,
  // Sound Variations
  DEFAULT_VARIATION_CONTAINERS,
  type VariationContainer,
  type VariationMode,
  // Voice Concurrency
  DEFAULT_CONCURRENCY_RULES,
  type VoiceConcurrencyRule,
  // Sequence Containers
  DEFAULT_SEQUENCE_CONTAINERS,
  type SequenceContainer,
  // Stingers
  DEFAULT_STINGERS,
  type Stinger,
  // Parameter Modifiers
  DEFAULT_LFO_CONFIGS,
  DEFAULT_ENVELOPE_CONFIGS,
  type LFOConfig,
  type EnvelopeConfig,
  // Blend Containers
  DEFAULT_BLEND_CONTAINERS,
  type BlendContainer,
  // Priority System
  DEFAULT_PRIORITY_CONFIGS,
  PRIORITY_LEVELS,
  type PriorityConfig,
  // Diagnostics
  type DiagnosticsSnapshot,
  // Profiler
  type ProfileReport,
  // DSP Plugins
  type PluginType,
  // Spatial Audio
  SPATIAL_PRESETS,
  type Vector3,
  type AudioZone,
} from '../core';
import './AudioFeaturesPanel.css';

// ============ Types ============

export interface AudioFeaturesPanelProps {
  /** Current buses in the mixer */
  buses?: Array<{ id: BusId; name: string }>;
  /** Callback when feature state changes */
  onFeatureChange?: (feature: string, enabled: boolean, config?: unknown) => void;
  /** External diagnostics data */
  diagnosticsData?: DiagnosticsSnapshot | null;
  /** External profiler data */
  profilerData?: ProfileReport | null;
  /** Optional className */
  className?: string;
}

type FeatureSection =
  | 'intensity'
  | 'ducking'
  | 'variations'
  | 'concurrency'
  | 'sequences'
  | 'stingers'
  | 'modifiers'
  | 'blend'
  | 'priority'
  | 'diagnostics'
  | 'dsp'
  | 'spatial';

interface FeatureState {
  enabled: boolean;
  expanded: boolean;
}

// ============ Section Header Component ============

interface SectionHeaderProps {
  title: string;
  icon: string;
  enabled: boolean;
  expanded: boolean;
  onToggleEnabled: () => void;
  onToggleExpanded: () => void;
  badge?: string | number;
}

const SectionHeader = memo(function SectionHeader({
  title,
  icon,
  enabled,
  expanded,
  onToggleEnabled,
  onToggleExpanded,
  badge,
}: SectionHeaderProps) {
  return (
    <div className={`rf-feature-header ${enabled ? 'enabled' : 'disabled'}`}>
      <button className="rf-feature-expand" onClick={onToggleExpanded}>
        {expanded ? '▼' : '▶'}
      </button>
      <span className="rf-feature-icon">{icon}</span>
      <span className="rf-feature-title">{title}</span>
      {badge !== undefined && <span className="rf-feature-badge">{badge}</span>}
      <label className="rf-feature-toggle">
        <input
          type="checkbox"
          checked={enabled}
          onChange={onToggleEnabled}
        />
        <span className="rf-toggle-slider" />
      </label>
    </div>
  );
});

// ============ Slider Field Component ============

interface SliderFieldProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  unit?: string;
  onChange: (value: number) => void;
  disabled?: boolean;
}

const SliderField = memo(function SliderField({
  label,
  value,
  min,
  max,
  step = 1,
  unit = '',
  onChange,
  disabled = false,
}: SliderFieldProps) {
  return (
    <div className={`rf-slider-field ${disabled ? 'disabled' : ''}`}>
      <label>{label}</label>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        disabled={disabled}
      />
      <span className="rf-slider-value">
        {value.toFixed(step < 1 ? 2 : 0)}{unit}
      </span>
    </div>
  );
});

// ============ Select Field Component ============

interface SelectFieldProps<T extends string> {
  label: string;
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  disabled?: boolean;
}

function SelectFieldComponent<T extends string>({
  label,
  value,
  options,
  onChange,
  disabled = false,
}: SelectFieldProps<T>) {
  return (
    <div className={`rf-select-field ${disabled ? 'disabled' : ''}`}>
      <label>{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as T)}
        disabled={disabled}
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

const SelectField = memo(SelectFieldComponent) as typeof SelectFieldComponent;

// ============ Intensity Layers Section ============

interface IntensityLayersSectionProps {
  enabled: boolean;
  expanded: boolean;
  configs: IntensityLayerConfig[];
  currentIntensity: number;
  onIntensityChange: (value: number) => void;
}

const IntensityLayersSection = memo(function IntensityLayersSection({
  enabled,
  expanded,
  configs,
  currentIntensity,
  onIntensityChange,
}: IntensityLayersSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <SliderField
        label="Intensity"
        value={currentIntensity}
        min={0}
        max={1}
        step={0.01}
        onChange={onIntensityChange}
        disabled={!enabled}
      />
      <div className="rf-intensity-layers">
        {configs.map((config) => (
          <div key={config.id} className="rf-intensity-layer">
            <span className="rf-layer-name">{config.name}</span>
            <div className="rf-layer-info">
              <span>{config.layers.length} layers</span>
              <span>Bus: {config.bus}</span>
              <span>Crossfade: {config.crossfadeCurve}</span>
            </div>
            <div className="rf-layer-tracks">
              {config.layers.map((layer) => (
                <div key={layer.id} className="rf-layer-track">
                  <span className="rf-track-id">{layer.id}</span>
                  <span className="rf-track-range">
                    [{layer.intensityRange[0].toFixed(1)} - {layer.intensityRange[1].toFixed(1)}]
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Ducking Section ============

interface DuckingSectionProps {
  enabled: boolean;
  expanded: boolean;
  rules: DuckingRule[];
  onRuleChange: (index: number, changes: Partial<DuckingRule>) => void;
  onAddRule: () => void;
}

const DuckingSection = memo(function DuckingSection({
  enabled,
  expanded,
  rules,
  onRuleChange,
  onAddRule,
}: DuckingSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-ducking-rules">
        {rules.map((rule, index) => (
          <div key={rule.id} className="rf-ducking-rule">
            <div className="rf-rule-header">
              <span className="rf-rule-name">{rule.sourceBus} → {rule.targetBuses.join(', ')}</span>
              <label className="rf-mini-toggle">
                <input
                  type="checkbox"
                  checked={rule.enabled}
                  onChange={(e) => onRuleChange(index, { enabled: e.target.checked })}
                  disabled={!enabled}
                />
              </label>
            </div>
            <SliderField
              label="Amount"
              value={rule.duckAmount}
              min={0}
              max={1}
              step={0.01}
              onChange={(v) => onRuleChange(index, { duckAmount: v })}
              disabled={!enabled}
            />
            <div className="rf-rule-timing">
              <SliderField
                label="Attack"
                value={rule.attackMs}
                min={1}
                max={500}
                step={1}
                unit="ms"
                onChange={(v) => onRuleChange(index, { attackMs: v })}
                disabled={!enabled}
              />
              <SliderField
                label="Release"
                value={rule.releaseMs}
                min={10}
                max={2000}
                step={10}
                unit="ms"
                onChange={(v) => onRuleChange(index, { releaseMs: v })}
                disabled={!enabled}
              />
            </div>
          </div>
        ))}
      </div>
      <button
        className="rf-add-button"
        onClick={onAddRule}
        disabled={!enabled}
      >
        + Add Ducking Rule
      </button>
    </div>
  );
});

// ============ Sound Variations Section ============

interface VariationsSectionProps {
  enabled: boolean;
  expanded: boolean;
  containers: VariationContainer[];
  onContainerChange: (index: number, changes: Partial<VariationContainer>) => void;
}

const VariationsSection = memo(function VariationsSection({
  enabled,
  expanded,
  containers,
  onContainerChange,
}: VariationsSectionProps) {
  if (!expanded) return null;

  const modeOptions: Array<{ value: VariationMode; label: string }> = [
    { value: 'random', label: 'Random' },
    { value: 'sequence', label: 'Sequential' },
    { value: 'shuffle', label: 'Shuffle' },
  ];

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-variation-containers">
        {containers.map((container, index) => (
          <div key={container.id} className="rf-variation-container">
            <div className="rf-container-header">
              <span className="rf-container-name">{container.name}</span>
              <span className="rf-container-count">
                {container.variations.length} variations
              </span>
            </div>
            <SelectField
              label="Mode"
              value={container.mode}
              options={modeOptions}
              onChange={(v) => onContainerChange(index, { mode: v })}
              disabled={!enabled}
            />
            <div className="rf-variations-list">
              {container.variations.slice(0, 5).map((v, i) => (
                <div key={i} className="rf-variation-item">
                  <span className="rf-var-name">{v.assetId}</span>
                  <span className="rf-var-weight">{((v.weight ?? 1) * 100).toFixed(0)}%</span>
                </div>
              ))}
              {container.variations.length > 5 && (
                <div className="rf-variation-more">
                  +{container.variations.length - 5} more
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Voice Concurrency Section ============

interface ConcurrencySectionProps {
  enabled: boolean;
  expanded: boolean;
  rules: VoiceConcurrencyRule[];
  activeVoices: number;
  onRuleChange: (index: number, changes: Partial<VoiceConcurrencyRule>) => void;
}

const ConcurrencySection = memo(function ConcurrencySection({
  enabled,
  expanded,
  rules,
  activeVoices,
  onRuleChange,
}: ConcurrencySectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-voice-stats">
        <span className="rf-stat-label">Active Voices:</span>
        <span className="rf-stat-value">{activeVoices}</span>
      </div>
      <div className="rf-concurrency-rules">
        {rules.map((rule, index) => (
          <div key={rule.soundPattern} className="rf-concurrency-rule">
            <div className="rf-rule-header">
              <span className="rf-rule-name">{rule.soundPattern}</span>
              <span className="rf-rule-limit">max {rule.maxInstances}</span>
            </div>
            <SliderField
              label="Max Instances"
              value={rule.maxInstances}
              min={1}
              max={32}
              step={1}
              onChange={(v) => onRuleChange(index, { maxInstances: v })}
              disabled={!enabled}
            />
            <SelectField
              label="Kill Policy"
              value={rule.killPolicy}
              options={[
                { value: 'kill-oldest', label: 'Kill Oldest' },
                { value: 'kill-newest', label: 'Kill Newest' },
                { value: 'kill-quietest', label: 'Kill Quietest' },
                { value: 'kill-lowest-priority', label: 'Kill Lowest Priority' },
                { value: 'allow-all', label: 'Allow All' },
              ]}
              onChange={(v) => onRuleChange(index, { killPolicy: v })}
              disabled={!enabled}
            />
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Sequence Containers Section ============

interface SequencesSectionProps {
  enabled: boolean;
  expanded: boolean;
  containers: SequenceContainer[];
  onContainerChange: (index: number, changes: Partial<SequenceContainer>) => void;
}

const SequencesSection = memo(function SequencesSection({
  enabled,
  expanded,
  containers,
  onContainerChange,
}: SequencesSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-sequence-containers">
        {containers.map((container, index) => (
          <div key={container.id} className="rf-sequence-container">
            <div className="rf-container-header">
              <span className="rf-container-name">{container.name}</span>
              <label className="rf-mini-toggle">
                <input
                  type="checkbox"
                  checked={container.loop}
                  onChange={(e) => onContainerChange(index, { loop: e.target.checked })}
                  disabled={!enabled}
                />
                <span className="rf-toggle-label">Loop</span>
              </label>
            </div>
            <div className="rf-sequence-steps">
              {container.steps.map((step, stepIndex) => (
                <div key={stepIndex} className="rf-sequence-step">
                  <span className="rf-step-number">{stepIndex + 1}</span>
                  <span className="rf-step-asset">{step.assetId}</span>
                  <span className="rf-step-timing">{step.timing}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Stingers Section ============

interface StingersSectionProps {
  enabled: boolean;
  expanded: boolean;
  stingers: Stinger[];
  onStingerChange: (index: number, changes: Partial<Stinger>) => void;
  onTrigger: (stingerId: string) => void;
}

const StingersSection = memo(function StingersSection({
  enabled,
  expanded,
  stingers,
  onStingerChange,
  onTrigger,
}: StingersSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-stingers-list">
        {stingers.map((stinger, index) => (
          <div key={stinger.id} className="rf-stinger-item">
            <div className="rf-stinger-header">
              <span className="rf-stinger-name">{stinger.name}</span>
              <button
                className="rf-stinger-trigger"
                onClick={() => onTrigger(stinger.id)}
                disabled={!enabled}
              >
                ▶ Trigger
              </button>
            </div>
            <SelectField
              label="Trigger Mode"
              value={stinger.triggerMode ?? 'immediate'}
              options={[
                { value: 'immediate', label: 'Immediate' },
                { value: 'next-beat', label: 'Next Beat' },
                { value: 'next-bar', label: 'Next Bar' },
                { value: 'next-phrase', label: 'Next Phrase' },
              ]}
              onChange={(v) => onStingerChange(index, { triggerMode: v as Stinger['triggerMode'] })}
              disabled={!enabled}
            />
            <SelectField
              label="Tail Mode"
              value={stinger.tailMode ?? 'cut'}
              options={[
                { value: 'cut', label: 'Cut' },
                { value: 'fade', label: 'Fade' },
                { value: 'ring-out', label: 'Ring Out' },
              ]}
              onChange={(v) => onStingerChange(index, { tailMode: v as Stinger['tailMode'] })}
              disabled={!enabled}
            />
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Parameter Modifiers Section ============

interface ModifiersSectionProps {
  enabled: boolean;
  expanded: boolean;
  lfoConfigs: LFOConfig[];
  envelopeConfigs: EnvelopeConfig[];
  onLfoChange: (index: number, changes: Partial<LFOConfig>) => void;
  onEnvelopeChange: (index: number, changes: Partial<EnvelopeConfig>) => void;
}

const ModifiersSection = memo(function ModifiersSection({
  enabled,
  expanded,
  lfoConfigs,
  envelopeConfigs,
  onLfoChange,
  onEnvelopeChange,
}: ModifiersSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-modifiers-group">
        <h4>LFO Modifiers</h4>
        {lfoConfigs.map((lfo, index) => (
          <div key={lfo.id} className="rf-lfo-item">
            <span className="rf-lfo-name">{lfo.id}</span>
            <SelectField
              label="Waveform"
              value={lfo.waveform}
              options={[
                { value: 'sine', label: 'Sine' },
                { value: 'triangle', label: 'Triangle' },
                { value: 'square', label: 'Square' },
                { value: 'saw', label: 'Sawtooth' },
                { value: 'random', label: 'Random' },
              ]}
              onChange={(v) => onLfoChange(index, { waveform: v })}
              disabled={!enabled}
            />
            <SliderField
              label="Rate"
              value={lfo.frequency}
              min={0.01}
              max={20}
              step={0.01}
              unit="Hz"
              onChange={(v) => onLfoChange(index, { frequency: v })}
              disabled={!enabled}
            />
            <SliderField
              label="Amplitude"
              value={lfo.amplitude}
              min={0}
              max={1}
              step={0.01}
              onChange={(v) => onLfoChange(index, { amplitude: v })}
              disabled={!enabled}
            />
          </div>
        ))}
      </div>
      <div className="rf-modifiers-group">
        <h4>Envelope Modifiers</h4>
        {envelopeConfigs.map((env, index) => (
          <div key={env.id} className="rf-envelope-item">
            <span className="rf-env-name">{env.id}</span>
            <div className="rf-adsr-controls">
              <SliderField
                label="A"
                value={env.attackMs}
                min={0}
                max={2000}
                step={1}
                unit="ms"
                onChange={(v) => onEnvelopeChange(index, { attackMs: v })}
                disabled={!enabled}
              />
              <SliderField
                label="D"
                value={env.decayMs}
                min={0}
                max={2000}
                step={1}
                unit="ms"
                onChange={(v) => onEnvelopeChange(index, { decayMs: v })}
                disabled={!enabled}
              />
              <SliderField
                label="S"
                value={env.sustainLevel}
                min={0}
                max={1}
                step={0.01}
                onChange={(v) => onEnvelopeChange(index, { sustainLevel: v })}
                disabled={!enabled}
              />
              <SliderField
                label="R"
                value={env.releaseMs}
                min={0}
                max={5000}
                step={1}
                unit="ms"
                onChange={(v) => onEnvelopeChange(index, { releaseMs: v })}
                disabled={!enabled}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Blend Containers Section ============

interface BlendSectionProps {
  enabled: boolean;
  expanded: boolean;
  containers: BlendContainer[];
  onContainerChange: (index: number, changes: Partial<BlendContainer>) => void;
  onBlendValueChange: (containerId: string, value: number) => void;
}

const BlendSection = memo(function BlendSection({
  enabled,
  expanded,
  containers,
  onContainerChange,
  onBlendValueChange,
}: BlendSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-blend-containers">
        {containers.map((container, index) => (
          <div key={container.id} className="rf-blend-container">
            <div className="rf-container-header">
              <span className="rf-container-name">{container.name}</span>
            </div>
            <SliderField
              label="Blend Value"
              value={container.currentValue ?? 0.5}
              min={0}
              max={1}
              step={0.01}
              onChange={(v) => onBlendValueChange(container.id, v)}
              disabled={!enabled}
            />
            <SelectField
              label="Curve Type"
              value={container.curveType ?? 'linear'}
              options={[
                { value: 'linear', label: 'Linear' },
                { value: 'equal-power', label: 'Equal Power' },
                { value: 'logarithmic', label: 'Logarithmic' },
                { value: 'exponential', label: 'Exponential' },
              ]}
              onChange={(v) => onContainerChange(index, { curveType: v })}
              disabled={!enabled}
            />
            <div className="rf-blend-tracks">
              {container.tracks.map((track) => (
                <div key={track.id} className="rf-blend-track">
                  <span className="rf-track-name">{track.assetId}</span>
                  <span className="rf-track-range">
                    {track.blendStart.toFixed(2)} - {track.blendEnd.toFixed(2)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Priority System Section ============

interface PrioritySectionProps {
  enabled: boolean;
  expanded: boolean;
  configs: Array<{ id: string; config: PriorityConfig }>;
  onConfigChange: (index: number, changes: Partial<PriorityConfig>) => void;
}

const PrioritySection = memo(function PrioritySection({
  enabled,
  expanded,
  configs,
  onConfigChange,
}: PrioritySectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-priority-configs">
        {configs.map(({ id, config }, index) => (
          <div key={id} className="rf-priority-config">
            <div className="rf-config-header">
              <span className="rf-config-name">{id}</span>
              <span className={`rf-priority-level rf-priority-${config.level}`}>
                {config.level.toUpperCase()}
              </span>
            </div>
            <SelectField
              label="Priority Level"
              value={config.level}
              options={Object.keys(PRIORITY_LEVELS).map((level) => ({
                value: level as PriorityConfig['level'],
                label: level.charAt(0).toUpperCase() + level.slice(1),
              }))}
              onChange={(v) => onConfigChange(index, { level: v })}
              disabled={!enabled}
            />
            <SliderField
              label="Priority Value"
              value={config.value}
              min={0}
              max={100}
              step={1}
              onChange={(v) => onConfigChange(index, { value: v })}
              disabled={!enabled}
            />
          </div>
        ))}
      </div>
    </div>
  );
});

// ============ Diagnostics Section ============

interface DiagnosticsSectionProps {
  enabled: boolean;
  expanded: boolean;
  snapshot: DiagnosticsSnapshot | null;
  profilerReport: ProfileReport | null;
  onClearLogs: () => void;
  onExport: () => void;
}

const DiagnosticsSection = memo(function DiagnosticsSection({
  enabled,
  expanded,
  snapshot,
  profilerReport,
  onClearLogs,
  onExport,
}: DiagnosticsSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-diagnostics-grid">
        {/* Voice Stats */}
        <div className="rf-diag-card">
          <h4>Voices</h4>
          {snapshot ? (
            <>
              <div className="rf-stat-row">
                <span>Active:</span>
                <span className="rf-stat-value">{snapshot.voices.total}</span>
              </div>
              <div className="rf-stat-row">
                <span>Peak:</span>
                <span className="rf-stat-value">{snapshot.voices.peak}</span>
              </div>
              <div className="rf-stat-row">
                <span>Stolen:</span>
                <span className="rf-stat-value">{snapshot.voices.stolenCount}</span>
              </div>
            </>
          ) : (
            <div className="rf-no-data">No data</div>
          )}
        </div>

        {/* Memory Stats */}
        <div className="rf-diag-card">
          <h4>Memory</h4>
          {snapshot ? (
            <>
              <div className="rf-stat-row">
                <span>Buffers:</span>
                <span className="rf-stat-value">{snapshot.memory.cachedBuffers}</span>
              </div>
              <div className="rf-stat-row">
                <span>Used:</span>
                <span className="rf-stat-value">
                  {(snapshot.memory.bufferMemory / 1024 / 1024).toFixed(1)} MB
                </span>
              </div>
              <div className="rf-stat-row">
                <span>State:</span>
                <span className="rf-stat-value">{snapshot.memory.contextState}</span>
              </div>
            </>
          ) : (
            <div className="rf-no-data">No data</div>
          )}
        </div>

        {/* Performance */}
        <div className="rf-diag-card">
          <h4>Performance</h4>
          {snapshot ? (
            <>
              <div className="rf-stat-row">
                <span>Avg Update:</span>
                <span className="rf-stat-value">
                  {snapshot.performance.avgUpdateTime.toFixed(2)}ms
                </span>
              </div>
              <div className="rf-stat-row">
                <span>Updates/sec:</span>
                <span className="rf-stat-value">
                  {snapshot.performance.updatesPerSecond.toFixed(0)}
                </span>
              </div>
              <div className="rf-stat-row">
                <span>Drops:</span>
                <span className="rf-stat-value">{snapshot.performance.droppedFrames}</span>
              </div>
            </>
          ) : (
            <div className="rf-no-data">No data</div>
          )}
        </div>

        {/* Profiler */}
        <div className="rf-diag-card rf-diag-card-wide">
          <h4>Profiler</h4>
          {profilerReport ? (
            <>
              <div className="rf-stat-row">
                <span>Total Samples:</span>
                <span className="rf-stat-value">{profilerReport.totalSamples}</span>
              </div>
              <div className="rf-stat-row">
                <span>Ops/sec:</span>
                <span className="rf-stat-value">
                  {profilerReport.operationsPerSecond.toFixed(1)}
                </span>
              </div>
              <div className="rf-hotspots">
                <h5>Hotspots:</h5>
                {profilerReport.hotspots.slice(0, 3).map((h, i) => (
                  <div key={i} className="rf-hotspot">
                    {h.operation}: {h.avgTime.toFixed(2)}ms ({h.count}x)
                  </div>
                ))}
              </div>
            </>
          ) : (
            <div className="rf-no-data">Profiler disabled</div>
          )}
        </div>
      </div>
      <div className="rf-diag-actions">
        <button className="rf-action-button" onClick={onClearLogs} disabled={!enabled}>
          Clear Logs
        </button>
        <button className="rf-action-button" onClick={onExport} disabled={!enabled}>
          Export Diagnostics
        </button>
      </div>
    </div>
  );
});

// ============ DSP Plugins Section ============

interface DSPSectionProps {
  enabled: boolean;
  expanded: boolean;
  activePlugins: Array<{ type: PluginType; id: string; enabled: boolean }>;
  onAddPlugin: (type: PluginType) => void;
  onRemovePlugin: (id: string) => void;
  onTogglePlugin: (id: string, enabled: boolean) => void;
}

const DSPSection = memo(function DSPSection({
  enabled,
  expanded,
  activePlugins,
  onAddPlugin,
  onRemovePlugin,
  onTogglePlugin,
}: DSPSectionProps) {
  if (!expanded) return null;

  const pluginTypes: Array<{ type: PluginType; label: string; icon: string }> = [
    { type: 'reverb', label: 'Reverb', icon: '🌊' },
    { type: 'delay', label: 'Delay', icon: '🔁' },
    { type: 'chorus', label: 'Chorus', icon: '🎭' },
    { type: 'phaser', label: 'Phaser', icon: '🌀' },
    { type: 'flanger', label: 'Flanger', icon: '✈️' },
    { type: 'tremolo', label: 'Tremolo', icon: '〰️' },
    { type: 'distortion', label: 'Distortion', icon: '⚡' },
    { type: 'filter', label: 'Filter', icon: '📊' },
  ];

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      <div className="rf-plugin-palette">
        {pluginTypes.map((pt) => (
          <button
            key={pt.type}
            className="rf-plugin-add-button"
            onClick={() => onAddPlugin(pt.type)}
            disabled={!enabled}
            title={`Add ${pt.label}`}
          >
            <span className="rf-plugin-icon">{pt.icon}</span>
            <span className="rf-plugin-name">{pt.label}</span>
          </button>
        ))}
      </div>
      <div className="rf-active-plugins">
        {activePlugins.length === 0 ? (
          <div className="rf-no-plugins">No plugins active</div>
        ) : (
          activePlugins.map((plugin) => (
            <div key={plugin.id} className={`rf-plugin-item ${plugin.enabled ? '' : 'bypassed'}`}>
              <span className="rf-plugin-type">{plugin.type}</span>
              <span className="rf-plugin-id">{plugin.id}</span>
              <label className="rf-mini-toggle">
                <input
                  type="checkbox"
                  checked={plugin.enabled}
                  onChange={(e) => onTogglePlugin(plugin.id, e.target.checked)}
                  disabled={!enabled}
                />
              </label>
              <button
                className="rf-plugin-remove"
                onClick={() => onRemovePlugin(plugin.id)}
                disabled={!enabled}
              >
                ×
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
});

// ============ Spatial Audio Section ============

interface SpatialSectionProps {
  enabled: boolean;
  expanded: boolean;
  listenerPosition: Vector3;
  sources: Array<{ id: string; position: Vector3; label: string }>;
  zones: AudioZone[];
  onListenerChange: (position: Vector3) => void;
}

const SpatialSection = memo(function SpatialSection({
  enabled,
  expanded,
  listenerPosition,
  sources,
  zones,
  onListenerChange,
}: SpatialSectionProps) {
  if (!expanded) return null;

  return (
    <div className={`rf-feature-content ${enabled ? '' : 'disabled'}`}>
      {/* 3D Visualizer would go here - simplified for now */}
      <div className="rf-spatial-visualizer">
        <div className="rf-spatial-grid">
          {/* Listener */}
          <div
            className="rf-spatial-listener"
            style={{
              left: `${50 + listenerPosition.x * 10}%`,
              top: `${50 - listenerPosition.z * 10}%`,
            }}
            title="Listener"
          >
            👂
          </div>
          {/* Sources */}
          {sources.map((source) => (
            <div
              key={source.id}
              className="rf-spatial-source"
              style={{
                left: `${50 + source.position.x * 10}%`,
                top: `${50 - source.position.z * 10}%`,
              }}
              title={source.label}
            >
              🔊
            </div>
          ))}
        </div>
      </div>
      <div className="rf-spatial-controls">
        <h4>Listener Position</h4>
        <div className="rf-xyz-controls">
          <SliderField
            label="X"
            value={listenerPosition.x}
            min={-10}
            max={10}
            step={0.1}
            onChange={(v) => onListenerChange({ ...listenerPosition, x: v })}
            disabled={!enabled}
          />
          <SliderField
            label="Y"
            value={listenerPosition.y}
            min={-10}
            max={10}
            step={0.1}
            onChange={(v) => onListenerChange({ ...listenerPosition, y: v })}
            disabled={!enabled}
          />
          <SliderField
            label="Z"
            value={listenerPosition.z}
            min={-10}
            max={10}
            step={0.1}
            onChange={(v) => onListenerChange({ ...listenerPosition, z: v })}
            disabled={!enabled}
          />
        </div>
      </div>
      <div className="rf-spatial-zones">
        <h4>Audio Zones ({zones.length})</h4>
        {zones.map((zone) => (
          <div key={zone.id} className="rf-zone-item">
            <span className="rf-zone-name">{zone.name}</span>
            <span className="rf-zone-type">{zone.type}</span>
          </div>
        ))}
      </div>
      <div className="rf-spatial-presets">
        <h4>Presets</h4>
        <div className="rf-preset-buttons">
          {Object.keys(SPATIAL_PRESETS).map((preset) => (
            <button key={preset} className="rf-preset-button" disabled={!enabled}>
              {preset}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
});

// ============ Main Component ============

export default function AudioFeaturesPanel({
  onFeatureChange,
  diagnosticsData = null,
  profilerData = null,
  className = '',
}: AudioFeaturesPanelProps) {
  // Feature states
  const [featureStates, setFeatureStates] = useState<Record<FeatureSection, FeatureState>>({
    intensity: { enabled: true, expanded: false },
    ducking: { enabled: true, expanded: false },
    variations: { enabled: true, expanded: false },
    concurrency: { enabled: true, expanded: false },
    sequences: { enabled: true, expanded: false },
    stingers: { enabled: true, expanded: false },
    modifiers: { enabled: true, expanded: false },
    blend: { enabled: true, expanded: false },
    priority: { enabled: true, expanded: false },
    diagnostics: { enabled: true, expanded: true },
    dsp: { enabled: true, expanded: false },
    spatial: { enabled: true, expanded: false },
  });

  // Feature data
  const [intensityConfigs] = useState<IntensityLayerConfig[]>([...DEFAULT_LAYER_CONFIGS]);
  const [currentIntensity, setCurrentIntensity] = useState(0.5);
  const [duckingRules, setDuckingRules] = useState<DuckingRule[]>([...DEFAULT_DUCKING_RULES]);
  const [variationContainers] = useState<VariationContainer[]>([...DEFAULT_VARIATION_CONTAINERS]);
  const [concurrencyRules, setConcurrencyRules] = useState<VoiceConcurrencyRule[]>([...DEFAULT_CONCURRENCY_RULES]);
  const [sequenceContainers] = useState<SequenceContainer[]>([...DEFAULT_SEQUENCE_CONTAINERS]);
  const [stingers, setStingers] = useState<Stinger[]>([...DEFAULT_STINGERS]);
  const [lfoConfigs, setLfoConfigs] = useState<LFOConfig[]>([...DEFAULT_LFO_CONFIGS]);
  const [envelopeConfigs, setEnvelopeConfigs] = useState<EnvelopeConfig[]>([...DEFAULT_ENVELOPE_CONFIGS]);
  const [blendContainers, setBlendContainers] = useState<BlendContainer[]>([...DEFAULT_BLEND_CONTAINERS]);

  // Convert Record to array for priority configs
  const [priorityConfigs, setPriorityConfigs] = useState<Array<{ id: string; config: PriorityConfig }>>(() =>
    Object.entries(DEFAULT_PRIORITY_CONFIGS).map(([id, config]) => ({ id, config }))
  );

  const [activePlugins, setActivePlugins] = useState<Array<{ type: PluginType; id: string; enabled: boolean }>>([]);
  const [listenerPosition, setListenerPosition] = useState<Vector3>({ x: 0, y: 0, z: 0 });
  const [spatialSources] = useState<Array<{ id: string; position: Vector3; label: string }>>([]);
  const [audioZones] = useState<AudioZone[]>([]);
  const [activeVoices] = useState(0);

  // Toggle handlers
  const toggleEnabled = useCallback((section: FeatureSection) => {
    setFeatureStates((prev) => ({
      ...prev,
      [section]: { ...prev[section], enabled: !prev[section].enabled },
    }));
    onFeatureChange?.(section, !featureStates[section].enabled);
  }, [featureStates, onFeatureChange]);

  const toggleExpanded = useCallback((section: FeatureSection) => {
    setFeatureStates((prev) => ({
      ...prev,
      [section]: { ...prev[section], expanded: !prev[section].expanded },
    }));
  }, []);

  // Feature update handlers
  const handleIntensityChange = useCallback((value: number) => {
    setCurrentIntensity(value);
  }, []);

  const handleDuckingRuleChange = useCallback((index: number, changes: Partial<DuckingRule>) => {
    setDuckingRules((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleAddDuckingRule = useCallback(() => {
    const newRule: DuckingRule = {
      id: `duck_${Date.now()}`,
      sourceBus: 'sfx',
      targetBuses: ['music'],
      duckAmount: 0.5,
      attackMs: 50,
      releaseMs: 300,
      holdMs: 0,
      priority: 1,
      enabled: true,
    };
    setDuckingRules((prev) => [...prev, newRule]);
  }, []);

  const handleVariationContainerChange = useCallback((_index: number, _changes: Partial<VariationContainer>) => {
    // Update variation container
  }, []);

  const handleConcurrencyRuleChange = useCallback((index: number, changes: Partial<VoiceConcurrencyRule>) => {
    setConcurrencyRules((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleSequenceContainerChange = useCallback((_index: number, _changes: Partial<SequenceContainer>) => {
    // Update sequence container
  }, []);

  const handleStingerChange = useCallback((index: number, changes: Partial<Stinger>) => {
    setStingers((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleStingerTrigger = useCallback((stingerId: string) => {
    console.log('Trigger stinger:', stingerId);
  }, []);

  const handleLfoChange = useCallback((index: number, changes: Partial<LFOConfig>) => {
    setLfoConfigs((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleEnvelopeChange = useCallback((index: number, changes: Partial<EnvelopeConfig>) => {
    setEnvelopeConfigs((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleBlendContainerChange = useCallback((index: number, changes: Partial<BlendContainer>) => {
    setBlendContainers((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], ...changes };
      return updated;
    });
  }, []);

  const handleBlendValueChange = useCallback((containerId: string, value: number) => {
    setBlendContainers((prev) =>
      prev.map((c) => (c.id === containerId ? { ...c, currentValue: value } : c))
    );
  }, []);

  const handlePriorityConfigChange = useCallback((index: number, changes: Partial<PriorityConfig>) => {
    setPriorityConfigs((prev) => {
      const updated = [...prev];
      updated[index] = { ...updated[index], config: { ...updated[index].config, ...changes } };
      return updated;
    });
  }, []);

  const handleClearLogs = useCallback(() => {
    console.log('Clear diagnostics logs');
  }, []);

  const handleExportDiagnostics = useCallback(() => {
    console.log('Export diagnostics');
  }, []);

  const handleAddPlugin = useCallback((type: PluginType) => {
    const newPlugin = {
      type,
      id: `${type}_${Date.now()}`,
      enabled: true,
    };
    setActivePlugins((prev) => [...prev, newPlugin]);
  }, []);

  const handleRemovePlugin = useCallback((id: string) => {
    setActivePlugins((prev) => prev.filter((p) => p.id !== id));
  }, []);

  const handleTogglePlugin = useCallback((id: string, enabled: boolean) => {
    setActivePlugins((prev) =>
      prev.map((p) => (p.id === id ? { ...p, enabled } : p))
    );
  }, []);

  const handleListenerChange = useCallback((position: Vector3) => {
    setListenerPosition(position);
  }, []);

  // Feature definitions for rendering
  const features: Array<{
    id: FeatureSection;
    title: string;
    icon: string;
    badge?: string | number;
    content: React.ReactNode;
  }> = [
    {
      id: 'intensity',
      title: 'Intensity Layers',
      icon: '📊',
      badge: intensityConfigs.length,
      content: (
        <IntensityLayersSection
          enabled={featureStates.intensity.enabled}
          expanded={featureStates.intensity.expanded}
          configs={intensityConfigs}
          currentIntensity={currentIntensity}
          onIntensityChange={handleIntensityChange}
        />
      ),
    },
    {
      id: 'ducking',
      title: 'Ducking',
      icon: '🔉',
      badge: duckingRules.length,
      content: (
        <DuckingSection
          enabled={featureStates.ducking.enabled}
          expanded={featureStates.ducking.expanded}
          rules={duckingRules}
          onRuleChange={handleDuckingRuleChange}
          onAddRule={handleAddDuckingRule}
        />
      ),
    },
    {
      id: 'variations',
      title: 'Sound Variations',
      icon: '🎲',
      badge: variationContainers.length,
      content: (
        <VariationsSection
          enabled={featureStates.variations.enabled}
          expanded={featureStates.variations.expanded}
          containers={variationContainers}
          onContainerChange={handleVariationContainerChange}
        />
      ),
    },
    {
      id: 'concurrency',
      title: 'Voice Concurrency',
      icon: '🔊',
      badge: activeVoices,
      content: (
        <ConcurrencySection
          enabled={featureStates.concurrency.enabled}
          expanded={featureStates.concurrency.expanded}
          rules={concurrencyRules}
          activeVoices={activeVoices}
          onRuleChange={handleConcurrencyRuleChange}
        />
      ),
    },
    {
      id: 'sequences',
      title: 'Sequence Containers',
      icon: '📋',
      badge: sequenceContainers.length,
      content: (
        <SequencesSection
          enabled={featureStates.sequences.enabled}
          expanded={featureStates.sequences.expanded}
          containers={sequenceContainers}
          onContainerChange={handleSequenceContainerChange}
        />
      ),
    },
    {
      id: 'stingers',
      title: 'Stingers',
      icon: '🎺',
      badge: stingers.length,
      content: (
        <StingersSection
          enabled={featureStates.stingers.enabled}
          expanded={featureStates.stingers.expanded}
          stingers={stingers}
          onStingerChange={handleStingerChange}
          onTrigger={handleStingerTrigger}
        />
      ),
    },
    {
      id: 'modifiers',
      title: 'Parameter Modifiers',
      icon: '〰️',
      badge: lfoConfigs.length + envelopeConfigs.length,
      content: (
        <ModifiersSection
          enabled={featureStates.modifiers.enabled}
          expanded={featureStates.modifiers.expanded}
          lfoConfigs={lfoConfigs}
          envelopeConfigs={envelopeConfigs}
          onLfoChange={handleLfoChange}
          onEnvelopeChange={handleEnvelopeChange}
        />
      ),
    },
    {
      id: 'blend',
      title: 'Blend Containers',
      icon: '🎚️',
      badge: blendContainers.length,
      content: (
        <BlendSection
          enabled={featureStates.blend.enabled}
          expanded={featureStates.blend.expanded}
          containers={blendContainers}
          onContainerChange={handleBlendContainerChange}
          onBlendValueChange={handleBlendValueChange}
        />
      ),
    },
    {
      id: 'priority',
      title: 'Priority System',
      icon: '⚡',
      badge: priorityConfigs.length,
      content: (
        <PrioritySection
          enabled={featureStates.priority.enabled}
          expanded={featureStates.priority.expanded}
          configs={priorityConfigs}
          onConfigChange={handlePriorityConfigChange}
        />
      ),
    },
    {
      id: 'diagnostics',
      title: 'Diagnostics & Profiler',
      icon: '📈',
      content: (
        <DiagnosticsSection
          enabled={featureStates.diagnostics.enabled}
          expanded={featureStates.diagnostics.expanded}
          snapshot={diagnosticsData}
          profilerReport={profilerData}
          onClearLogs={handleClearLogs}
          onExport={handleExportDiagnostics}
        />
      ),
    },
    {
      id: 'dsp',
      title: 'DSP Plugins',
      icon: '🎛️',
      badge: activePlugins.length,
      content: (
        <DSPSection
          enabled={featureStates.dsp.enabled}
          expanded={featureStates.dsp.expanded}
          activePlugins={activePlugins}
          onAddPlugin={handleAddPlugin}
          onRemovePlugin={handleRemovePlugin}
          onTogglePlugin={handleTogglePlugin}
        />
      ),
    },
    {
      id: 'spatial',
      title: 'Spatial Audio',
      icon: '🌐',
      badge: spatialSources.length,
      content: (
        <SpatialSection
          enabled={featureStates.spatial.enabled}
          expanded={featureStates.spatial.expanded}
          listenerPosition={listenerPosition}
          sources={spatialSources}
          zones={audioZones}
          onListenerChange={handleListenerChange}
        />
      ),
    },
  ];

  return (
    <div className={`rf-audio-features-panel ${className}`}>
      <div className="rf-features-header">
        <h2>Audio Features</h2>
        <span className="rf-features-count">
          {Object.values(featureStates).filter((f) => f.enabled).length}/12 active
        </span>
      </div>
      <div className="rf-features-list">
        {features.map((feature) => (
          <div
            key={feature.id}
            className={`rf-feature-section ${featureStates[feature.id].expanded ? 'expanded' : ''}`}
          >
            <SectionHeader
              title={feature.title}
              icon={feature.icon}
              enabled={featureStates[feature.id].enabled}
              expanded={featureStates[feature.id].expanded}
              onToggleEnabled={() => toggleEnabled(feature.id)}
              onToggleExpanded={() => toggleExpanded(feature.id)}
              badge={feature.badge}
            />
            {feature.content}
          </div>
        ))}
      </div>
    </div>
  );
}

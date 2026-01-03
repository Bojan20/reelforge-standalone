/**
 * ReelForge M9.2 VanEQ Editor
 *
 * Professional parametric EQ editor with frequency response graph.
 * Features draggable band handles and type selection.
 *
 * @module plugin/vaneqEditor
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import type { PluginEditorProps } from './PluginDefinition';
import type { ParamDescriptor } from './ParamDescriptor';
import { formatParamValue, valueToSlider, sliderToValue, clampParamValue } from './ParamDescriptor';
import {
  VANEQ_CONSTRAINTS,
  VALID_VANEQ_BAND_TYPES,
  type VanEqBandType,
} from './vaneqTypes';
import { getBandTypeDisplayName } from './vaneqDescriptors';
import './vaneqEditor.css';

// ============ Throttle Utility ============

/** Throttle interval for drag updates (ms) - ~30 Hz */
const DRAG_THROTTLE_MS = 33;

/**
 * Create a throttled function that only executes at most once per interval.
 * Uses trailing edge - always fires the last call.
 */
function createThrottle<Args extends unknown[]>(
  fn: (...args: Args) => void,
  intervalMs: number
): ((...args: Args) => void) & { cancel: () => void } {
  let lastCall = 0;
  let pendingArgs: Args | null = null;
  let timeoutId: ReturnType<typeof setTimeout> | null = null;

  const throttled = ((...args: Args) => {
    const now = Date.now();
    const elapsed = now - lastCall;

    if (elapsed >= intervalMs) {
      // Enough time passed, execute immediately
      lastCall = now;
      fn(...args);
    } else {
      // Queue latest args for trailing edge
      pendingArgs = args;
      if (!timeoutId) {
        timeoutId = setTimeout(() => {
          if (pendingArgs) {
            lastCall = Date.now();
            fn(...pendingArgs);
            pendingArgs = null;
          }
          timeoutId = null;
        }, intervalMs - elapsed);
      }
    }
  }) as ((...args: Args) => void) & { cancel: () => void };

  throttled.cancel = () => {
    if (timeoutId) {
      clearTimeout(timeoutId);
      timeoutId = null;
    }
    pendingArgs = null;
  };

  return throttled;
}

// ============ Graph Constants ============

const GRAPH_WIDTH = 400;
const GRAPH_HEIGHT = 180;
const GRAPH_PADDING_X = 30;
const GRAPH_PADDING_Y = 20;
const GRAPH_INNER_WIDTH = GRAPH_WIDTH - GRAPH_PADDING_X * 2;
const GRAPH_INNER_HEIGHT = GRAPH_HEIGHT - GRAPH_PADDING_Y * 2;

// Frequency axis: 20Hz to 20kHz (logarithmic)
const FREQ_MIN = VANEQ_CONSTRAINTS.freqHz.min;
const FREQ_MAX = VANEQ_CONSTRAINTS.freqHz.max;
const LOG_FREQ_MIN = Math.log10(FREQ_MIN);
const LOG_FREQ_MAX = Math.log10(FREQ_MAX);

// Gain axis: -24dB to +24dB (linear)
const GAIN_MIN = VANEQ_CONSTRAINTS.gainDb.min;
const GAIN_MAX = VANEQ_CONSTRAINTS.gainDb.max;

// ============ Utility Functions ============

function freqToX(freq: number): number {
  const logFreq = Math.log10(Math.max(FREQ_MIN, Math.min(FREQ_MAX, freq)));
  const normalized = (logFreq - LOG_FREQ_MIN) / (LOG_FREQ_MAX - LOG_FREQ_MIN);
  return GRAPH_PADDING_X + normalized * GRAPH_INNER_WIDTH;
}

function xToFreq(x: number): number {
  const normalized = (x - GRAPH_PADDING_X) / GRAPH_INNER_WIDTH;
  const logFreq = LOG_FREQ_MIN + normalized * (LOG_FREQ_MAX - LOG_FREQ_MIN);
  return Math.pow(10, logFreq);
}

function gainToY(gain: number): number {
  const normalized = (gain - GAIN_MIN) / (GAIN_MAX - GAIN_MIN);
  return GRAPH_PADDING_Y + (1 - normalized) * GRAPH_INNER_HEIGHT;
}

function yToGain(y: number): number {
  const normalized = 1 - (y - GRAPH_PADDING_Y) / GRAPH_INNER_HEIGHT;
  return GAIN_MIN + normalized * (GAIN_MAX - GAIN_MIN);
}

function formatFreq(freq: number): string {
  if (freq >= 1000) {
    return `${(freq / 1000).toFixed(freq >= 10000 ? 0 : 1)}k`;
  }
  return freq.toFixed(0);
}

// ============ Band Colors ============

const BAND_COLORS = [
  '#e74c3c', // Red
  '#e67e22', // Orange
  '#f1c40f', // Yellow
  '#2ecc71', // Green
  '#3498db', // Blue
  '#9b59b6', // Purple
];

// ============ Frequency Response Graph ============

interface FreqGraphProps {
  params: Record<string, number>;
  activeBand: number;
  onBandClick: (band: number) => void;
  onBandDrag: (band: number, freq: number, gain: number) => void;
  readOnly: boolean;
}

function FreqGraph({
  params,
  activeBand,
  onBandClick,
  onBandDrag,
  readOnly,
}: FreqGraphProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const draggingRef = useRef<number | null>(null);

  // Extract band data
  const bands = useMemo(() => {
    const result: Array<{
      enabled: boolean;
      type: VanEqBandType;
      freq: number;
      gain: number;
      q: number;
    }> = [];

    for (let i = 0; i < 6; i++) {
      result.push({
        enabled: params[`band${i}_enabled`] === 1,
        type: VALID_VANEQ_BAND_TYPES[params[`band${i}_type`] ?? 0],
        freq: params[`band${i}_freqHz`] ?? 1000,
        gain: params[`band${i}_gainDb`] ?? 0,
        q: params[`band${i}_q`] ?? 1,
      });
    }

    return result;
  }, [params]);

  // Generate frequency axis labels
  const freqLabels = useMemo(() => {
    const freqs = [30, 100, 300, 1000, 3000, 10000];
    return freqs.map((f) => ({
      freq: f,
      x: freqToX(f),
      label: formatFreq(f),
    }));
  }, []);

  // Generate gain axis labels
  const gainLabels = useMemo(() => {
    const gains = [24, 12, 0, -12, -24];
    return gains.map((g) => ({
      gain: g,
      y: gainToY(g),
      label: g === 0 ? '0dB' : `${g > 0 ? '+' : ''}${g}`,
    }));
  }, []);

  // Handle mouse events for dragging with throttling
  const handleMouseDown = useCallback(
    (e: React.MouseEvent, bandIndex: number) => {
      if (readOnly) return;
      e.preventDefault();
      e.stopPropagation();

      draggingRef.current = bandIndex;
      onBandClick(bandIndex);

      // Create throttled drag handler for this drag session
      const throttledDrag = createThrottle(
        (band: number, freq: number, gain: number) => {
          onBandDrag(band, freq, gain);
        },
        DRAG_THROTTLE_MS
      );

      const handleMouseMove = (moveEvent: MouseEvent) => {
        if (draggingRef.current === null || !svgRef.current) return;

        const rect = svgRef.current.getBoundingClientRect();
        const x = moveEvent.clientX - rect.left;
        const y = moveEvent.clientY - rect.top;

        const freq = Math.max(FREQ_MIN, Math.min(FREQ_MAX, xToFreq(x)));
        const gain = Math.max(GAIN_MIN, Math.min(GAIN_MAX, yToGain(y)));

        throttledDrag(draggingRef.current, freq, gain);
      };

      const handleMouseUp = () => {
        // Cancel any pending throttled call and clean up
        throttledDrag.cancel();
        draggingRef.current = null;
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [readOnly, onBandClick, onBandDrag]
  );

  // Generate grid lines
  const gridPath = useMemo(() => {
    let path = '';

    // Vertical lines (frequencies)
    const freqs = [50, 100, 200, 500, 1000, 2000, 5000, 10000];
    for (const f of freqs) {
      const x = freqToX(f);
      path += `M${x},${GRAPH_PADDING_Y} L${x},${GRAPH_HEIGHT - GRAPH_PADDING_Y} `;
    }

    // Horizontal lines (gains)
    const gains = [-18, -12, -6, 0, 6, 12, 18];
    for (const g of gains) {
      const y = gainToY(g);
      path += `M${GRAPH_PADDING_X},${y} L${GRAPH_WIDTH - GRAPH_PADDING_X},${y} `;
    }

    return path;
  }, []);

  // Zero line
  const zeroY = gainToY(0);

  return (
    <svg
      ref={svgRef}
      className="rf-vaneq-graph"
      viewBox={`0 0 ${GRAPH_WIDTH} ${GRAPH_HEIGHT}`}
      preserveAspectRatio="xMidYMid meet"
    >
      {/* Background */}
      <rect
        x={GRAPH_PADDING_X}
        y={GRAPH_PADDING_Y}
        width={GRAPH_INNER_WIDTH}
        height={GRAPH_INNER_HEIGHT}
        className="rf-vaneq-graph-bg"
      />

      {/* Grid */}
      <path d={gridPath} className="rf-vaneq-graph-grid" />

      {/* Zero line (highlighted) */}
      <line
        x1={GRAPH_PADDING_X}
        y1={zeroY}
        x2={GRAPH_WIDTH - GRAPH_PADDING_X}
        y2={zeroY}
        className="rf-vaneq-graph-zero"
      />

      {/* Frequency labels */}
      {freqLabels.map(({ freq, x, label }) => (
        <text key={freq} x={x} y={GRAPH_HEIGHT - 4} className="rf-vaneq-axis-label">
          {label}
        </text>
      ))}

      {/* Gain labels */}
      {gainLabels.map(({ gain, y, label }) => (
        <text key={gain} x={4} y={y + 3} className="rf-vaneq-axis-label">
          {label}
        </text>
      ))}

      {/* Band handles */}
      {bands.map((band, i) => {
        const x = freqToX(band.freq);
        // For cut/notch/bandpass types, show handle at 0dB since gain doesn't apply
        const effectiveGain =
          band.type === 'lowPass' || band.type === 'highPass' || band.type === 'notch' || band.type === 'bandPass'
            ? 0
            : band.gain;
        const y = gainToY(effectiveGain);
        const isActive = i === activeBand;
        const color = BAND_COLORS[i];

        return (
          <g key={i} className={`rf-vaneq-band ${band.enabled ? 'enabled' : 'disabled'}`}>
            {/* Connection line from center */}
            <line
              x1={x}
              y1={zeroY}
              x2={x}
              y2={y}
              stroke={color}
              strokeWidth={1}
              strokeOpacity={band.enabled ? 0.5 : 0.2}
            />

            {/* Band handle */}
            <circle
              cx={x}
              cy={y}
              r={isActive ? 10 : 8}
              fill={color}
              fillOpacity={band.enabled ? 1 : 0.3}
              stroke={isActive ? '#fff' : 'none'}
              strokeWidth={2}
              className="rf-vaneq-band-handle"
              onMouseDown={(e) => handleMouseDown(e, i)}
              onClick={() => onBandClick(i)}
              style={{ cursor: readOnly ? 'default' : 'grab' }}
            />

            {/* Band number */}
            <text
              x={x}
              y={y + 4}
              className="rf-vaneq-band-number"
              style={{ pointerEvents: 'none' }}
            >
              {i + 1}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

// ============ Band Type Selector ============

interface BandTypeSelectorProps {
  value: number;
  onChange: (typeIndex: number) => void;
  disabled: boolean;
}

function BandTypeSelector({ value, onChange, disabled }: BandTypeSelectorProps) {
  return (
    <div className="rf-vaneq-type-selector">
      {VALID_VANEQ_BAND_TYPES.map((type, i) => (
        <button
          key={type}
          className={`rf-vaneq-type-btn ${value === i ? 'active' : ''}`}
          onClick={() => onChange(i)}
          disabled={disabled}
          title={getBandTypeDisplayName(i)}
        >
          {type === 'bell' && '~'}
          {type === 'lowShelf' && '⌊'}
          {type === 'highShelf' && '⌉'}
          {type === 'lowPass' && '/'}
          {type === 'highPass' && '\\'}
          {type === 'notch' && 'V'}
          {type === 'bandPass' && '∧'}
          {type === 'tilt' && '⟋'}
        </button>
      ))}
    </div>
  );
}

// ============ Parameter Slider ============

interface ParamSliderProps {
  descriptor: ParamDescriptor;
  value: number;
  onChange: (value: number) => void;
  onReset: () => void;
  disabled?: boolean;
  color?: string;
}

function ParamSlider({
  descriptor,
  value,
  onChange,
  onReset,
  disabled = false,
  color,
}: ParamSliderProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  // Editing state for numeric input
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState('');

  const sliderPosition = useMemo(
    () => valueToSlider(value, descriptor),
    [value, descriptor]
  );

  const displayValue = useMemo(
    () => formatParamValue(value, descriptor),
    [value, descriptor]
  );

  // Get raw numeric value for editing (with display multiplier applied)
  const rawDisplayValue = useMemo(() => {
    const displayVal = descriptor.displayMultiplier
      ? value * descriptor.displayMultiplier
      : value;
    return Number(displayVal.toPrecision(6));
  }, [value, descriptor]);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const position = Number(e.target.value);
      const newValue = sliderToValue(position, descriptor);
      onChange(newValue);
    },
    [onChange, descriptor]
  );

  // Start editing when clicking on value display
  const handleValueClick = useCallback(() => {
    if (disabled) return;
    setEditValue(String(rawDisplayValue));
    setIsEditing(true);
  }, [disabled, rawDisplayValue]);

  // Focus input when editing starts
  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  // Commit the edited value
  const commitEdit = useCallback(() => {
    const parsed = parseFloat(editValue);
    if (!Number.isNaN(parsed)) {
      const rawValue = descriptor.displayMultiplier
        ? parsed / descriptor.displayMultiplier
        : parsed;
      const clamped = clampParamValue(rawValue, descriptor);
      onChange(clamped);
    }
    setIsEditing(false);
  }, [editValue, descriptor, onChange]);

  // Cancel editing
  const cancelEdit = useCallback(() => {
    setIsEditing(false);
  }, []);

  // Handle keyboard events in the input
  const handleInputKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        commitEdit();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        cancelEdit();
      }
    },
    [commitEdit, cancelEdit]
  );

  return (
    <div className="rf-vaneq-param-row">
      <span className="rf-vaneq-param-label">
        {descriptor.shortName || descriptor.name}
      </span>
      <input
        type="range"
        className="rf-vaneq-param-slider"
        min={0}
        max={1}
        step={0.001}
        value={sliderPosition}
        onChange={handleChange}
        onDoubleClick={onReset}
        disabled={disabled}
        style={color ? { '--slider-color': color } as React.CSSProperties : undefined}
      />
      {isEditing ? (
        <input
          ref={inputRef}
          type="text"
          className="rf-vaneq-param-input"
          value={editValue}
          onChange={(e) => setEditValue(e.target.value)}
          onKeyDown={handleInputKeyDown}
          onBlur={commitEdit}
        />
      ) : (
        <span
          className="rf-vaneq-param-display"
          onClick={handleValueClick}
          title={disabled ? undefined : 'Click to type value'}
          style={{ cursor: disabled ? 'default' : 'text' }}
        >
          {displayValue}
        </span>
      )}
    </div>
  );
}

// ============ VanEQ Editor ============

export function VanEqEditor({
  params,
  descriptors,
  onChange,
  onReset,
  readOnly = false,
}: PluginEditorProps) {
  const [activeBand, setActiveBand] = useState(0);

  // Get descriptors for the current band
  const bandDescriptors = useMemo(() => {
    const prefix = `band${activeBand}_`;
    return descriptors.filter((d) => d.id.startsWith(prefix));
  }, [descriptors, activeBand]);

  // Get output gain descriptor
  const outputGainDescriptor = useMemo(() => {
    return descriptors.find((d) => d.id === 'outputGainDb');
  }, [descriptors]);

  // Get current band values
  const currentBand = useMemo(() => {
    return {
      enabled: params[`band${activeBand}_enabled`] === 1,
      type: params[`band${activeBand}_type`] ?? 0,
      freq: params[`band${activeBand}_freqHz`] ?? 1000,
      gain: params[`band${activeBand}_gainDb`] ?? 0,
      q: params[`band${activeBand}_q`] ?? 1,
    };
  }, [params, activeBand]);

  const handleBandClick = useCallback((band: number) => {
    setActiveBand(band);
  }, []);

  const handleBandDrag = useCallback(
    (band: number, freq: number, gain: number) => {
      onChange(`band${band}_freqHz`, Math.round(freq));

      // Only update gain for types that use it
      const bandType = params[`band${band}_type`] ?? 0;
      const typeStr = VALID_VANEQ_BAND_TYPES[bandType];
      if (typeStr !== 'lowPass' && typeStr !== 'highPass' && typeStr !== 'notch' && typeStr !== 'bandPass') {
        onChange(`band${band}_gainDb`, Math.round(gain * 10) / 10);
      }
    },
    [onChange, params]
  );

  const handleToggleEnabled = useCallback(() => {
    onChange(`band${activeBand}_enabled`, currentBand.enabled ? 0 : 1);
  }, [onChange, activeBand, currentBand.enabled]);

  const handleTypeChange = useCallback(
    (typeIndex: number) => {
      onChange(`band${activeBand}_type`, typeIndex);
    },
    [onChange, activeBand]
  );

  const handleParamChange = useCallback(
    (paramId: string, value: number) => {
      onChange(paramId, value);
    },
    [onChange]
  );

  const handleParamReset = useCallback(
    (paramId: string) => {
      onReset(paramId);
    },
    [onReset]
  );

  // Get descriptor by suffix
  const getDescriptor = useCallback(
    (suffix: string) => {
      return bandDescriptors.find((d) => d.id.endsWith(suffix));
    },
    [bandDescriptors]
  );

  const freqDescriptor = getDescriptor('_freqHz');
  const gainDescriptor = getDescriptor('_gainDb');
  const qDescriptor = getDescriptor('_q');

  // Check if current type uses gain
  const typeUsesGain = useMemo(() => {
    const typeStr = VALID_VANEQ_BAND_TYPES[currentBand.type];
    return typeStr !== 'lowPass' && typeStr !== 'highPass' && typeStr !== 'notch' && typeStr !== 'bandPass';
  }, [currentBand.type]);

  return (
    <div className="rf-vaneq-editor">
      {/* Frequency Response Graph */}
      <FreqGraph
        params={params}
        activeBand={activeBand}
        onBandClick={handleBandClick}
        onBandDrag={handleBandDrag}
        readOnly={readOnly}
      />

      {/* Band selector tabs */}
      <div className="rf-vaneq-band-tabs">
        {Array.from({ length: 6 }, (_, i) => {
          const enabled = params[`band${i}_enabled`] === 1;
          return (
            <button
              key={i}
              className={`rf-vaneq-band-tab ${activeBand === i ? 'active' : ''} ${enabled ? 'enabled' : ''}`}
              onClick={() => setActiveBand(i)}
              style={{ borderColor: BAND_COLORS[i] }}
            >
              {i + 1}
            </button>
          );
        })}
      </div>

      {/* Active band controls */}
      <div className="rf-vaneq-band-controls">
        <div className="rf-vaneq-band-header">
          <button
            className={`rf-vaneq-enable-btn ${currentBand.enabled ? 'enabled' : ''}`}
            onClick={handleToggleEnabled}
            disabled={readOnly}
            style={{ backgroundColor: currentBand.enabled ? BAND_COLORS[activeBand] : undefined }}
          >
            {currentBand.enabled ? 'ON' : 'OFF'}
          </button>
          <span className="rf-vaneq-band-title">Band {activeBand + 1}</span>
          <BandTypeSelector
            value={currentBand.type}
            onChange={handleTypeChange}
            disabled={readOnly}
          />
        </div>

        <div className="rf-vaneq-band-params">
          {/* Frequency */}
          {freqDescriptor && (
            <ParamSlider
              descriptor={freqDescriptor}
              value={currentBand.freq}
              onChange={(v) => handleParamChange(`band${activeBand}_freqHz`, v)}
              onReset={() => handleParamReset(`band${activeBand}_freqHz`)}
              disabled={readOnly}
              color={BAND_COLORS[activeBand]}
            />
          )}

          {/* Gain (only for types that use it) */}
          {gainDescriptor && typeUsesGain && (
            <ParamSlider
              descriptor={gainDescriptor}
              value={currentBand.gain}
              onChange={(v) => handleParamChange(`band${activeBand}_gainDb`, v)}
              onReset={() => handleParamReset(`band${activeBand}_gainDb`)}
              disabled={readOnly}
              color={BAND_COLORS[activeBand]}
            />
          )}

          {/* Q */}
          {qDescriptor && (
            <ParamSlider
              descriptor={qDescriptor}
              value={currentBand.q}
              onChange={(v) => handleParamChange(`band${activeBand}_q`, v)}
              onReset={() => handleParamReset(`band${activeBand}_q`)}
              disabled={readOnly}
              color={BAND_COLORS[activeBand]}
            />
          )}
        </div>
      </div>

      {/* Output gain */}
      {outputGainDescriptor && (
        <div className="rf-vaneq-output">
          <ParamSlider
            descriptor={outputGainDescriptor}
            value={params.outputGainDb ?? 0}
            onChange={(v) => handleParamChange('outputGainDb', v)}
            onReset={() => handleParamReset('outputGainDb')}
            disabled={readOnly}
          />
        </div>
      )}
    </div>
  );
}

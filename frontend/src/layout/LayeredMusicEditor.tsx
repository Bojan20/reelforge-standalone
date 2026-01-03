/**
 * ReelForge Layered Music Editor
 *
 * Wwise-style music layering system with:
 * - Multiple simultaneous layers
 * - Blend curves between states
 * - Parameter-driven mixing
 * - Visual blend editor
 * - RTPC connections
 *
 * @module layout/LayeredMusicEditor
 */

import { memo, useState, useCallback, useRef, useEffect, useMemo } from 'react';

// ============ Types ============

export interface MusicLayer {
  id: string;
  name: string;
  color: string;
  /** Volume (0-1) */
  volume: number;
  /** Pan (-1 to 1) */
  pan: number;
  /** Is layer active */
  active: boolean;
  /** Is layer muted */
  muted: boolean;
  /** Is layer soloed */
  soloed: boolean;
  /** Blend weight (0-1) for crossfades */
  blendWeight: number;
  /** Audio file/source */
  source?: string;
  /** Waveform data */
  waveform?: Float32Array | number[];
}

export interface BlendPoint {
  /** X position (parameter value 0-1) */
  x: number;
  /** Y position (blend value 0-1) */
  y: number;
}

export interface BlendCurve {
  layerId: string;
  points: BlendPoint[];
  /** Curve type */
  type: 'linear' | 'scurve' | 'log' | 'exp';
}

export interface MusicState {
  id: string;
  name: string;
  /** Layer volumes in this state */
  layerVolumes: Record<string, number>;
  /** Transition time to this state */
  transitionTime: number;
  /** Transition curve */
  transitionCurve: 'linear' | 'scurve' | 'exp';
}

export interface LayeredMusicEditorProps {
  /** Music layers */
  layers: MusicLayer[];
  /** Blend curves for parameter-driven blending */
  blendCurves?: BlendCurve[];
  /** Music states */
  states?: MusicState[];
  /** Current state ID */
  currentStateId?: string;
  /** RTPC parameter value (0-1) */
  rtpcValue?: number;
  /** RTPC parameter name */
  rtpcName?: string;
  /** On layer change */
  onLayerChange?: (layerId: string, changes: Partial<MusicLayer>) => void;
  /** On layer add */
  onLayerAdd?: () => void;
  /** On layer remove */
  onLayerRemove?: (layerId: string) => void;
  /** On blend curve change */
  onBlendCurveChange?: (layerId: string, points: BlendPoint[]) => void;
  /** On state change */
  onStateChange?: (stateId: string) => void;
  /** On RTPC value change */
  onRtpcChange?: (value: number) => void;
}

// ============ Layer Strip Component ============

interface LayerStripProps {
  layer: MusicLayer;
  isPlaying?: boolean;
  onChange?: (changes: Partial<MusicLayer>) => void;
  onRemove?: () => void;
}

const LayerStrip = memo(function LayerStrip({
  layer,
  onChange,
  onRemove,
}: LayerStripProps) {
  const volumeDb = layer.volume <= 0 ? '-∞' : (20 * Math.log10(layer.volume)).toFixed(1);

  return (
    <div
      className={`rf-layer-strip ${layer.muted ? 'muted' : ''} ${layer.soloed ? 'soloed' : ''}`}
      style={{ borderLeftColor: layer.color }}
    >
      {/* Header */}
      <div className="rf-layer-strip__header">
        <div
          className="rf-layer-strip__color"
          style={{ background: layer.color }}
        />
        <input
          type="text"
          className="rf-layer-strip__name"
          value={layer.name}
          onChange={(e) => onChange?.({ name: e.target.value })}
        />
        <button
          className="rf-layer-strip__remove"
          onClick={onRemove}
          title="Remove layer"
        >
          ×
        </button>
      </div>

      {/* Waveform preview */}
      <div className="rf-layer-strip__waveform">
        {layer.waveform ? (
          <MiniWaveform data={layer.waveform} color={layer.color} />
        ) : (
          <div className="rf-layer-strip__no-audio">No audio</div>
        )}
      </div>

      {/* Controls */}
      <div className="rf-layer-strip__controls">
        {/* Volume */}
        <div className="rf-layer-strip__fader">
          <label>Vol</label>
          <input
            type="range"
            min={0}
            max={1}
            step={0.01}
            value={layer.volume}
            onChange={(e) => onChange?.({ volume: parseFloat(e.target.value) })}
          />
          <span className="rf-layer-strip__value">{volumeDb}dB</span>
        </div>

        {/* Pan */}
        <div className="rf-layer-strip__fader">
          <label>Pan</label>
          <input
            type="range"
            min={-1}
            max={1}
            step={0.01}
            value={layer.pan}
            onChange={(e) => onChange?.({ pan: parseFloat(e.target.value) })}
          />
          <span className="rf-layer-strip__value">
            {layer.pan === 0 ? 'C' : layer.pan < 0 ? `L${Math.abs(layer.pan * 100).toFixed(0)}` : `R${(layer.pan * 100).toFixed(0)}`}
          </span>
        </div>

        {/* Blend weight */}
        <div className="rf-layer-strip__fader">
          <label>Blend</label>
          <input
            type="range"
            min={0}
            max={1}
            step={0.01}
            value={layer.blendWeight}
            onChange={(e) => onChange?.({ blendWeight: parseFloat(e.target.value) })}
          />
          <span className="rf-layer-strip__value">{(layer.blendWeight * 100).toFixed(0)}%</span>
        </div>
      </div>

      {/* Mute/Solo/Active */}
      <div className="rf-layer-strip__buttons">
        <button
          className={`rf-layer-strip__btn ${layer.active ? 'active' : ''}`}
          onClick={() => onChange?.({ active: !layer.active })}
          title="Active"
        >
          A
        </button>
        <button
          className={`rf-layer-strip__btn rf-layer-strip__btn--mute ${layer.muted ? 'active' : ''}`}
          onClick={() => onChange?.({ muted: !layer.muted })}
          title="Mute"
        >
          M
        </button>
        <button
          className={`rf-layer-strip__btn rf-layer-strip__btn--solo ${layer.soloed ? 'active' : ''}`}
          onClick={() => onChange?.({ soloed: !layer.soloed })}
          title="Solo"
        >
          S
        </button>
      </div>
    </div>
  );
});

// ============ Mini Waveform ============

interface MiniWaveformProps {
  data: Float32Array | number[];
  color: string;
}

const MiniWaveform = memo(function MiniWaveform({ data, color }: MiniWaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !data.length) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.offsetWidth;
    const height = canvas.offsetHeight;
    const dpr = window.devicePixelRatio;

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, width, height);

    const samplesPerPixel = Math.ceil(data.length / width);
    const centerY = height / 2;

    ctx.fillStyle = color;
    ctx.globalAlpha = 0.6;

    for (let x = 0; x < width; x++) {
      const startSample = Math.floor(x * samplesPerPixel);
      const endSample = Math.min(startSample + samplesPerPixel, data.length);

      let min = 0, max = 0;
      for (let i = startSample; i < endSample; i++) {
        const val = data[i];
        if (val < min) min = val;
        if (val > max) max = val;
      }

      const top = centerY - max * centerY;
      const barHeight = Math.max(1, (max - min) * centerY);
      ctx.fillRect(x, top, 1, barHeight);
    }
  }, [data, color]);

  return <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />;
});

// ============ Blend Curve Editor ============

interface BlendCurveEditorProps {
  curves: BlendCurve[];
  layers: MusicLayer[];
  rtpcValue: number;
  rtpcName: string;
  onCurveChange?: (layerId: string, points: BlendPoint[]) => void;
  onRtpcChange?: (value: number) => void;
}

const BlendCurveEditor = memo(function BlendCurveEditor({
  curves,
  layers,
  rtpcValue,
  rtpcName,
  onCurveChange,
  onRtpcChange,
}: BlendCurveEditorProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [selectedPoint, setSelectedPoint] = useState<{ layerId: string; pointIndex: number } | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const width = 400;
  const height = 200;
  const padding = 20;

  // Draw curves
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Background
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, width, height);

    // Grid
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 10; i++) {
      const x = padding + (i / 10) * (width - 2 * padding);
      const y = padding + (i / 10) * (height - 2 * padding);
      ctx.beginPath();
      ctx.moveTo(x, padding);
      ctx.lineTo(x, height - padding);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(padding, y);
      ctx.lineTo(width - padding, y);
      ctx.stroke();
    }

    // Draw each curve
    curves.forEach((curve) => {
      const layer = layers.find((l) => l.id === curve.layerId);
      if (!layer || curve.points.length < 2) return;

      ctx.strokeStyle = layer.color;
      ctx.lineWidth = 2;
      ctx.beginPath();

      curve.points.forEach((point, i) => {
        const x = padding + point.x * (width - 2 * padding);
        const y = height - padding - point.y * (height - 2 * padding);
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      });
      ctx.stroke();

      // Draw points
      curve.points.forEach((point, i) => {
        const x = padding + point.x * (width - 2 * padding);
        const y = height - padding - point.y * (height - 2 * padding);

        ctx.beginPath();
        ctx.arc(x, y, 5, 0, Math.PI * 2);
        ctx.fillStyle = selectedPoint?.layerId === curve.layerId && selectedPoint?.pointIndex === i
          ? '#fff'
          : layer.color;
        ctx.fill();
      });
    });

    // RTPC indicator
    const rtpcX = padding + rtpcValue * (width - 2 * padding);
    ctx.strokeStyle = '#4a9eff';
    ctx.lineWidth = 2;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(rtpcX, padding);
    ctx.lineTo(rtpcX, height - padding);
    ctx.stroke();
    ctx.setLineDash([]);

    // Labels
    ctx.fillStyle = '#888';
    ctx.font = '10px system-ui';
    ctx.textAlign = 'center';
    ctx.fillText('0', padding, height - 5);
    ctx.fillText('1', width - padding, height - 5);
    ctx.fillText(rtpcName, width / 2, height - 5);

    ctx.textAlign = 'right';
    ctx.fillText('0%', padding - 5, height - padding);
    ctx.fillText('100%', padding - 5, padding + 4);
  }, [curves, layers, rtpcValue, rtpcName, selectedPoint, width, height, padding]);

  // Handle mouse events
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left - padding) / (width - 2 * padding);
    const y = 1 - (e.clientY - rect.top - padding) / (height - 2 * padding);

    // Check if clicking on a point
    for (const curve of curves) {
      for (let i = 0; i < curve.points.length; i++) {
        const point = curve.points[i];
        const dist = Math.sqrt((point.x - x) ** 2 + (point.y - y) ** 2);
        if (dist < 0.05) {
          setSelectedPoint({ layerId: curve.layerId, pointIndex: i });
          setIsDragging(true);
          return;
        }
      }
    }

    // Otherwise, move RTPC
    if (x >= 0 && x <= 1) {
      onRtpcChange?.(Math.max(0, Math.min(1, x)));
    }
  }, [curves, width, height, padding, onRtpcChange]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!isDragging || !selectedPoint) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = Math.max(0, Math.min(1, (e.clientX - rect.left - padding) / (width - 2 * padding)));
    const y = Math.max(0, Math.min(1, 1 - (e.clientY - rect.top - padding) / (height - 2 * padding)));

    const curve = curves.find((c) => c.layerId === selectedPoint.layerId);
    if (!curve) return;

    const newPoints = [...curve.points];
    newPoints[selectedPoint.pointIndex] = { x, y };
    onCurveChange?.(selectedPoint.layerId, newPoints);
  }, [isDragging, selectedPoint, curves, width, height, padding, onCurveChange]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
  }, []);

  return (
    <div className="rf-blend-editor">
      <div className="rf-blend-editor__header">
        <span>Blend Curves</span>
        <span className="rf-blend-editor__rtpc">{rtpcName}: {(rtpcValue * 100).toFixed(0)}%</span>
      </div>
      <canvas
        ref={canvasRef}
        style={{ width, height, cursor: isDragging ? 'grabbing' : 'crosshair' }}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
      />
      {/* RTPC Slider */}
      <div className="rf-blend-editor__slider">
        <input
          type="range"
          min={0}
          max={1}
          step={0.01}
          value={rtpcValue}
          onChange={(e) => onRtpcChange?.(parseFloat(e.target.value))}
          style={{ width: width - 2 * padding }}
        />
      </div>
    </div>
  );
});

// ============ State Selector ============

interface StateSelectorProps {
  states: MusicState[];
  currentStateId?: string;
  onStateChange?: (stateId: string) => void;
}

const StateSelector = memo(function StateSelector({
  states,
  currentStateId,
  onStateChange,
}: StateSelectorProps) {
  return (
    <div className="rf-state-selector">
      <span className="rf-state-selector__label">State:</span>
      <div className="rf-state-selector__buttons">
        {states.map((state) => (
          <button
            key={state.id}
            className={`rf-state-selector__btn ${currentStateId === state.id ? 'active' : ''}`}
            onClick={() => onStateChange?.(state.id)}
          >
            {state.name}
            <span className="rf-state-selector__time">{state.transitionTime}s</span>
          </button>
        ))}
      </div>
    </div>
  );
});

// ============ Layered Music Editor Component ============

export const LayeredMusicEditor = memo(function LayeredMusicEditor({
  layers,
  blendCurves = [],
  states = [],
  currentStateId,
  rtpcValue = 0.5,
  rtpcName = 'Intensity',
  onLayerChange,
  onLayerAdd,
  onLayerRemove,
  onBlendCurveChange,
  onStateChange,
  onRtpcChange,
}: LayeredMusicEditorProps) {
  const [viewMode, setViewMode] = useState<'strips' | 'blend'>('strips');

  // Calculate effective volumes based on RTPC
  const effectiveVolumes = useMemo(() => {
    const volumes: Record<string, number> = {};
    layers.forEach((layer) => {
      const curve = blendCurves.find((c) => c.layerId === layer.id);
      if (curve && curve.points.length >= 2) {
        // Interpolate curve at rtpcValue
        let blendValue = 0;
        for (let i = 0; i < curve.points.length - 1; i++) {
          const p1 = curve.points[i];
          const p2 = curve.points[i + 1];
          if (rtpcValue >= p1.x && rtpcValue <= p2.x) {
            const t = (rtpcValue - p1.x) / (p2.x - p1.x);
            blendValue = p1.y + t * (p2.y - p1.y);
            break;
          }
        }
        volumes[layer.id] = layer.volume * blendValue;
      } else {
        volumes[layer.id] = layer.volume * layer.blendWeight;
      }
    });
    return volumes;
  }, [layers, blendCurves, rtpcValue]);

  return (
    <div className="rf-layered-music-editor">
      {/* Header */}
      <div className="rf-layered-music-editor__header">
        <span className="rf-layered-music-editor__title">Layered Music</span>
        <div className="rf-layered-music-editor__tabs">
          <button
            className={viewMode === 'strips' ? 'active' : ''}
            onClick={() => setViewMode('strips')}
          >
            Layers
          </button>
          <button
            className={viewMode === 'blend' ? 'active' : ''}
            onClick={() => setViewMode('blend')}
          >
            Blend
          </button>
        </div>
        {onLayerAdd && (
          <button className="rf-layered-music-editor__add" onClick={onLayerAdd}>
            + Add Layer
          </button>
        )}
      </div>

      {/* States */}
      {states.length > 0 && (
        <StateSelector
          states={states}
          currentStateId={currentStateId}
          onStateChange={onStateChange}
        />
      )}

      {/* Content */}
      <div className="rf-layered-music-editor__content">
        {viewMode === 'strips' ? (
          <div className="rf-layered-music-editor__strips">
            {layers.map((layer) => (
              <LayerStrip
                key={layer.id}
                layer={layer}
                onChange={(changes) => onLayerChange?.(layer.id, changes)}
                onRemove={() => onLayerRemove?.(layer.id)}
              />
            ))}
            {layers.length === 0 && (
              <div className="rf-layered-music-editor__empty">
                No layers. Click "+ Add Layer" to create one.
              </div>
            )}
          </div>
        ) : (
          <BlendCurveEditor
            curves={blendCurves}
            layers={layers}
            rtpcValue={rtpcValue}
            rtpcName={rtpcName}
            onCurveChange={onBlendCurveChange}
            onRtpcChange={onRtpcChange}
          />
        )}
      </div>

      {/* Mix Preview */}
      <div className="rf-layered-music-editor__mix">
        <span>Mix Preview:</span>
        <div className="rf-layered-music-editor__mix-bars">
          {layers.map((layer) => {
            const vol = effectiveVolumes[layer.id] || 0;
            return (
              <div
                key={layer.id}
                className="rf-layered-music-editor__mix-bar"
                style={{ background: layer.color, opacity: layer.muted ? 0.2 : 1 }}
              >
                <div
                  className="rf-layered-music-editor__mix-fill"
                  style={{ width: `${vol * 100}%` }}
                />
                <span>{layer.name}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
});

// ============ Generate Demo Layers ============

export function generateDemoLayers(): MusicLayer[] {
  const generateWaveform = (pattern: 'drums' | 'bass' | 'melody' | 'ambient') => {
    const samples = 500;
    const waveform = new Float32Array(samples);
    for (let i = 0; i < samples; i++) {
      const t = i / samples;
      switch (pattern) {
        case 'drums':
          // Transient-heavy
          waveform[i] = Math.sin(i * 0.5) * (1 - (i % 50) / 50) * 0.8;
          break;
        case 'bass':
          // Low frequency
          waveform[i] = Math.sin(t * Math.PI * 4) * 0.7 + (Math.random() - 0.5) * 0.1;
          break;
        case 'melody':
          // Higher frequency with variation
          waveform[i] = Math.sin(t * Math.PI * 20 + Math.sin(t * 3) * 2) * 0.5;
          break;
        case 'ambient':
          // Noise-like
          waveform[i] = (Math.random() - 0.5) * 0.3 * Math.sin(t * Math.PI);
          break;
      }
    }
    return waveform;
  };

  return [
    {
      id: 'drums',
      name: 'Drums',
      color: '#e74c3c',
      volume: 0.8,
      pan: 0,
      active: true,
      muted: false,
      soloed: false,
      blendWeight: 1,
      waveform: generateWaveform('drums'),
    },
    {
      id: 'bass',
      name: 'Bass',
      color: '#9b59b6',
      volume: 0.7,
      pan: 0,
      active: true,
      muted: false,
      soloed: false,
      blendWeight: 1,
      waveform: generateWaveform('bass'),
    },
    {
      id: 'melody',
      name: 'Melody',
      color: '#3498db',
      volume: 0.6,
      pan: 0.2,
      active: true,
      muted: false,
      soloed: false,
      blendWeight: 0.8,
      waveform: generateWaveform('melody'),
    },
    {
      id: 'ambient',
      name: 'Ambient',
      color: '#2ecc71',
      volume: 0.4,
      pan: -0.3,
      active: true,
      muted: false,
      soloed: false,
      blendWeight: 0.5,
      waveform: generateWaveform('ambient'),
    },
  ];
}

export function generateDemoBlendCurves(): BlendCurve[] {
  return [
    {
      layerId: 'drums',
      type: 'linear',
      points: [
        { x: 0, y: 0.3 },
        { x: 0.5, y: 1 },
        { x: 1, y: 1 },
      ],
    },
    {
      layerId: 'bass',
      type: 'linear',
      points: [
        { x: 0, y: 0.5 },
        { x: 0.3, y: 1 },
        { x: 1, y: 1 },
      ],
    },
    {
      layerId: 'melody',
      type: 'scurve',
      points: [
        { x: 0, y: 0 },
        { x: 0.4, y: 0.2 },
        { x: 0.7, y: 0.8 },
        { x: 1, y: 1 },
      ],
    },
    {
      layerId: 'ambient',
      type: 'exp',
      points: [
        { x: 0, y: 1 },
        { x: 0.5, y: 0.5 },
        { x: 1, y: 0.1 },
      ],
    },
  ];
}

export function generateDemoStates(): MusicState[] {
  return [
    {
      id: 'calm',
      name: 'Calm',
      layerVolumes: { drums: 0.2, bass: 0.5, melody: 0.3, ambient: 1 },
      transitionTime: 2,
      transitionCurve: 'scurve',
    },
    {
      id: 'explore',
      name: 'Explore',
      layerVolumes: { drums: 0.5, bass: 0.7, melody: 0.6, ambient: 0.6 },
      transitionTime: 1.5,
      transitionCurve: 'linear',
    },
    {
      id: 'action',
      name: 'Action',
      layerVolumes: { drums: 1, bass: 1, melody: 0.8, ambient: 0.2 },
      transitionTime: 0.5,
      transitionCurve: 'exp',
    },
    {
      id: 'victory',
      name: 'Victory',
      layerVolumes: { drums: 0.8, bass: 0.6, melody: 1, ambient: 0.4 },
      transitionTime: 1,
      transitionCurve: 'scurve',
    },
  ];
}

export default LayeredMusicEditor;

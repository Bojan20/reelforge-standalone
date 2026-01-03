/**
 * Multiband Compressor Panel
 *
 * Professional multiband dynamics processor UI:
 * - Band frequency visualization
 * - Per-band threshold/ratio/attack/release
 * - GR meters per band
 * - Preset selection
 * - Master output controls
 */

import React, { useState, memo, useCallback, useEffect, useRef } from 'react';
import type {
  MultibandCompressorConfig,
  BandConfig,
  DetectionMode,
  KneeType,
} from '../core/multibandCompressor';
import { MULTIBAND_PRESETS } from '../core/multibandCompressor';
import './MultibandCompressorPanel.css';

// ============ TYPES ============

interface MultibandCompressorPanelProps {
  onConfigChange?: (config: MultibandCompressorConfig) => void;
}

// ============ CONSTANTS ============

const BAND_COLORS = ['#22c55e', '#3b82f6', '#8b5cf6', '#f59e0b', '#ef4444'];

const DETECTION_MODES: { value: DetectionMode; label: string }[] = [
  { value: 'peak', label: 'Peak' },
  { value: 'rms', label: 'RMS' },
];

const KNEE_TYPES: { value: KneeType; label: string }[] = [
  { value: 'hard', label: 'Hard' },
  { value: 'soft', label: 'Soft' },
];

// Default configuration (no AudioContext needed for UI-only)
const DEFAULT_CONFIG: MultibandCompressorConfig = {
  bandCount: 3,
  bands: [
    { id: 'low', lowFreq: 20, highFreq: 250, threshold: -24, ratio: 4, attackMs: 10, releaseMs: 100, makeupGain: 0, bypass: false, solo: false, mute: false },
    { id: 'mid', lowFreq: 250, highFreq: 4000, threshold: -20, ratio: 3, attackMs: 8, releaseMs: 80, makeupGain: 0, bypass: false, solo: false, mute: false },
    { id: 'high', lowFreq: 4000, highFreq: 20000, threshold: -18, ratio: 2.5, attackMs: 5, releaseMs: 60, makeupGain: 0, bypass: false, solo: false, mute: false },
  ],
  globalThreshold: 0,
  globalRatio: 1,
  detectionMode: 'rms',
  kneeType: 'soft',
  kneeWidth: 6,
  lookaheadMs: 5,
  outputGain: 0,
  mix: 1,
  bypass: false,
};

// ============ MAIN COMPONENT ============

const MultibandCompressorPanel: React.FC<MultibandCompressorPanelProps> = memo(({
  onConfigChange,
}) => {
  const [config, setConfig] = useState<MultibandCompressorConfig>({ ...DEFAULT_CONFIG });
  const [selectedBand, setSelectedBand] = useState<number>(0);
  // Simulated meters for UI demo
  const [meters, setMeters] = useState<{ input: number; output: number; gr: number }[]>([
    { input: -18, output: -20, gr: -2 },
    { input: -15, output: -17, gr: -2 },
    { input: -12, output: -14, gr: -2 },
  ]);

  // Simulate meter animation
  useEffect(() => {
    const interval = setInterval(() => {
      setMeters(config.bands.map(() => ({
        input: -30 + Math.random() * 20,
        output: -32 + Math.random() * 20,
        gr: -(Math.random() * 8),
      })));
    }, 100);
    return () => clearInterval(interval);
  }, [config.bands]);

  // Apply preset
  const applyPreset = useCallback((presetName: keyof typeof MULTIBAND_PRESETS) => {
    const preset = MULTIBAND_PRESETS[presetName];
    const newConfig = { ...config, ...preset };
    setConfig(newConfig);
    onConfigChange?.(newConfig);
  }, [config, onConfigChange]);

  // Update band
  const updateBand = useCallback((bandIndex: number, key: keyof BandConfig, value: number | boolean) => {
    const newBands = [...config.bands];
    newBands[bandIndex] = { ...newBands[bandIndex], [key]: value };
    const newConfig = { ...config, bands: newBands };
    setConfig(newConfig);
    onConfigChange?.(newConfig);
  }, [config, onConfigChange]);

  // Update global
  const updateGlobal = useCallback((key: string, value: number | boolean | string) => {
    const newConfig = { ...config, [key]: value };
    setConfig(newConfig);
    onConfigChange?.(newConfig);
  }, [config, onConfigChange]);

  // Toggle bypass
  const toggleBypass = useCallback(() => {
    const newConfig = { ...config, bypass: !config.bypass };
    setConfig(newConfig);
    onConfigChange?.(newConfig);
  }, [config, onConfigChange]);

  const selectedBandConfig = config.bands[selectedBand];

  return (
    <div className="multiband-panel">
      {/* Header */}
      <div className="multiband-header">
        <div className="multiband-title">
          <span className="multiband-icon">📊</span>
          <h3>Multiband Compressor</h3>
        </div>

        <div className="header-controls">
          <select
            className="preset-select"
            value=""
            onChange={(e) => {
              if (e.target.value) {
                applyPreset(e.target.value as keyof typeof MULTIBAND_PRESETS);
              }
            }}
          >
            <option value="">Load Preset...</option>
            {Object.keys(MULTIBAND_PRESETS).map(p => (
              <option key={p} value={p}>
                {p.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}
              </option>
            ))}
          </select>

          <button
            className={`bypass-btn ${config.bypass ? 'active' : ''}`}
            onClick={toggleBypass}
          >
            {config.bypass ? '🔇 Bypassed' : '🔊 Active'}
          </button>
        </div>
      </div>

      {/* Frequency Spectrum */}
      <FrequencySpectrum
        bands={config.bands}
        selectedBand={selectedBand}
        onBandSelect={setSelectedBand}
        meters={meters}
      />

      {/* Band Tabs */}
      <div className="band-tabs">
        {config.bands.map((band, index) => (
          <button
            key={index}
            className={`band-tab ${selectedBand === index ? 'active' : ''} ${band.solo ? 'solo' : ''} ${band.mute ? 'mute' : ''}`}
            style={{ borderColor: BAND_COLORS[index] }}
            onClick={() => setSelectedBand(index)}
          >
            <span className="band-label">Band {index + 1}</span>
            <span className="band-range">
              {band.lowFreq} - {band.highFreq} Hz
            </span>
          </button>
        ))}
      </div>

      {/* Selected Band Controls */}
      {selectedBandConfig && (
        <div className="band-controls">
          <div className="band-header" style={{ borderColor: BAND_COLORS[selectedBand] }}>
            <span>Band {selectedBand + 1} Settings</span>
            <div className="band-toggles">
              <button
                className={`toggle-btn ${selectedBandConfig.solo ? 'active' : ''}`}
                onClick={() => updateBand(selectedBand, 'solo', !selectedBandConfig.solo)}
              >
                S
              </button>
              <button
                className={`toggle-btn mute ${selectedBandConfig.mute ? 'active' : ''}`}
                onClick={() => updateBand(selectedBand, 'mute', !selectedBandConfig.mute)}
              >
                M
              </button>
            </div>
          </div>

          {/* Crossover */}
          {selectedBand < config.bands.length - 1 && (
            <div className="control-row">
              <label>High Freq</label>
              <input
                type="range"
                min="20"
                max="20000"
                step="1"
                value={selectedBandConfig.highFreq}
                onChange={(e) => updateBand(selectedBand, 'highFreq', parseFloat(e.target.value))}
              />
              <span className="control-value">{selectedBandConfig.highFreq} Hz</span>
            </div>
          )}

          {/* Threshold */}
          <div className="control-row">
            <label>Threshold</label>
            <input
              type="range"
              min="-60"
              max="0"
              step="0.5"
              value={selectedBandConfig.threshold}
              onChange={(e) => updateBand(selectedBand, 'threshold', parseFloat(e.target.value))}
            />
            <span className="control-value">{selectedBandConfig.threshold} dB</span>
          </div>

          {/* Ratio */}
          <div className="control-row">
            <label>Ratio</label>
            <input
              type="range"
              min="1"
              max="20"
              step="0.1"
              value={selectedBandConfig.ratio}
              onChange={(e) => updateBand(selectedBand, 'ratio', parseFloat(e.target.value))}
            />
            <span className="control-value">{selectedBandConfig.ratio}:1</span>
          </div>

          {/* Attack */}
          <div className="control-row">
            <label>Attack</label>
            <input
              type="range"
              min="0.1"
              max="100"
              step="0.1"
              value={selectedBandConfig.attackMs}
              onChange={(e) => updateBand(selectedBand, 'attackMs', parseFloat(e.target.value))}
            />
            <span className="control-value">{selectedBandConfig.attackMs.toFixed(1)} ms</span>
          </div>

          {/* Release */}
          <div className="control-row">
            <label>Release</label>
            <input
              type="range"
              min="10"
              max="1000"
              step="1"
              value={selectedBandConfig.releaseMs}
              onChange={(e) => updateBand(selectedBand, 'releaseMs', parseFloat(e.target.value))}
            />
            <span className="control-value">{selectedBandConfig.releaseMs} ms</span>
          </div>

          {/* Makeup Gain */}
          <div className="control-row">
            <label>Makeup</label>
            <input
              type="range"
              min="-12"
              max="24"
              step="0.5"
              value={selectedBandConfig.makeupGain}
              onChange={(e) => updateBand(selectedBand, 'makeupGain', parseFloat(e.target.value))}
            />
            <span className="control-value">{selectedBandConfig.makeupGain > 0 ? '+' : ''}{selectedBandConfig.makeupGain} dB</span>
          </div>

          {/* GR Meter */}
          <div className="band-meter">
            <label>Gain Reduction</label>
            <div className="gr-meter-bar">
              <div
                className="gr-meter-fill"
                style={{
                  width: `${Math.min(100, Math.abs(meters[selectedBand]?.gr ?? 0) / 24 * 100)}%`,
                  backgroundColor: BAND_COLORS[selectedBand],
                }}
              />
            </div>
            <span className="gr-value">{(meters[selectedBand]?.gr ?? 0).toFixed(1)} dB</span>
          </div>
        </div>
      )}

      {/* Global Controls */}
      <div className="global-controls">
        <div className="global-header">
          <span className="global-icon">🎛️</span>
          <span>Global Settings</span>
        </div>

        <div className="global-grid">
          <div className="control-row">
            <label>Detection</label>
            <select
              value={config.detectionMode}
              onChange={(e) => updateGlobal('detectionMode', e.target.value)}
            >
              {DETECTION_MODES.map(m => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </div>

          <div className="control-row">
            <label>Knee</label>
            <select
              value={config.kneeType}
              onChange={(e) => updateGlobal('kneeType', e.target.value)}
            >
              {KNEE_TYPES.map(k => (
                <option key={k.value} value={k.value}>{k.label}</option>
              ))}
            </select>
          </div>

          <div className="control-row">
            <label>Knee Width</label>
            <input
              type="range"
              min="0"
              max="24"
              step="0.5"
              value={config.kneeWidth}
              onChange={(e) => updateGlobal('kneeWidth', parseFloat(e.target.value))}
            />
            <span className="control-value">{config.kneeWidth} dB</span>
          </div>

          <div className="control-row">
            <label>Lookahead</label>
            <input
              type="range"
              min="0"
              max="20"
              step="0.5"
              value={config.lookaheadMs}
              onChange={(e) => updateGlobal('lookaheadMs', parseFloat(e.target.value))}
            />
            <span className="control-value">{config.lookaheadMs} ms</span>
          </div>

          <div className="control-row">
            <label>Output</label>
            <input
              type="range"
              min="-12"
              max="12"
              step="0.5"
              value={config.outputGain}
              onChange={(e) => updateGlobal('outputGain', parseFloat(e.target.value))}
            />
            <span className="control-value">{config.outputGain > 0 ? '+' : ''}{config.outputGain} dB</span>
          </div>

          <div className="control-row">
            <label>Mix</label>
            <input
              type="range"
              min="0"
              max="1"
              step="0.01"
              value={config.mix}
              onChange={(e) => updateGlobal('mix', parseFloat(e.target.value))}
            />
            <span className="control-value">{(config.mix * 100).toFixed(0)}%</span>
          </div>
        </div>
      </div>
    </div>
  );
});

MultibandCompressorPanel.displayName = 'MultibandCompressorPanel';
export default MultibandCompressorPanel;

// ============ FREQUENCY SPECTRUM ============

interface FrequencySpectrumProps {
  bands: BandConfig[];
  selectedBand: number;
  onBandSelect: (index: number) => void;
  meters: { input: number; output: number; gr: number }[];
}

const FrequencySpectrum = memo<FrequencySpectrumProps>(({
  bands,
  selectedBand,
  onBandSelect,
  meters,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const width = canvas.width;
    const height = canvas.height;

    // Clear
    ctx.fillStyle = '#0f0f0f';
    ctx.fillRect(0, 0, width, height);

    // Frequency scale (logarithmic)
    const freqToX = (freq: number) => {
      const minLog = Math.log10(20);
      const maxLog = Math.log10(20000);
      return ((Math.log10(freq) - minLog) / (maxLog - minLog)) * width;
    };

    // Draw frequency grid
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 1;
    [100, 1000, 10000].forEach(freq => {
      const x = freqToX(freq);
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();

      ctx.fillStyle = '#666';
      ctx.font = '10px sans-serif';
      ctx.fillText(freq >= 1000 ? `${freq / 1000}k` : `${freq}`, x + 2, height - 4);
    });

    // Draw bands
    bands.forEach((band, index) => {
      const startX = freqToX(band.lowFreq);
      const endX = freqToX(band.highFreq);

      // Band background
      ctx.fillStyle = index === selectedBand
        ? `${BAND_COLORS[index]}40`
        : `${BAND_COLORS[index]}20`;
      ctx.fillRect(startX, 0, endX - startX, height);

      // Band border
      ctx.strokeStyle = BAND_COLORS[index];
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(endX, 0);
      ctx.lineTo(endX, height);
      ctx.stroke();

      // GR visualization
      const gr = meters[index]?.gr ?? 0;
      const grHeight = Math.abs(gr) / 24 * height * 0.8;
      ctx.fillStyle = `${BAND_COLORS[index]}80`;
      ctx.fillRect(startX, height - grHeight, endX - startX, grHeight);

      // Band label
      const centerX = (startX + endX) / 2;
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 11px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(`B${index + 1}`, centerX, 16);

      // Show GR value
      if (gr < 0) {
        ctx.fillStyle = BAND_COLORS[index];
        ctx.font = '10px monospace';
        ctx.fillText(`${gr.toFixed(1)}dB`, centerX, 30);
      }
    });

  }, [bands, selectedBand, meters]);

  const handleClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * (canvas.width / rect.width);

    // Find which band was clicked
    const freqToX = (freq: number) => {
      const minLog = Math.log10(20);
      const maxLog = Math.log10(20000);
      return ((Math.log10(freq) - minLog) / (maxLog - minLog)) * canvas.width;
    };

    for (let i = 0; i < bands.length; i++) {
      const startX = freqToX(bands[i].lowFreq);
      const endX = freqToX(bands[i].highFreq);
      if (x >= startX && x < endX) {
        onBandSelect(i);
        break;
      }
    }
  };

  return (
    <div className="frequency-spectrum">
      <canvas
        ref={canvasRef}
        width={600}
        height={80}
        onClick={handleClick}
      />
    </div>
  );
});

FrequencySpectrum.displayName = 'FrequencySpectrum';

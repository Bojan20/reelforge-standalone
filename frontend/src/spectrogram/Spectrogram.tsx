/**
 * ReelForge Spectrogram
 *
 * Audio frequency visualization:
 * - FFT-based analysis
 * - Multiple color schemes
 * - Linear/logarithmic scale
 * - Real-time display
 *
 * @module spectrogram/Spectrogram
 */

import { useRef, useEffect, useCallback, useState } from 'react';
import './Spectrogram.css';

// ============ Types ============

export type ColorScheme = 'heat' | 'grayscale' | 'rainbow' | 'plasma' | 'viridis';
export type FrequencyScale = 'linear' | 'logarithmic' | 'mel';

export interface SpectrogramProps {
  /** Audio buffer */
  audioBuffer?: AudioBuffer | null;
  /** Live analyser node */
  analyserNode?: AnalyserNode | null;
  /** FFT size */
  fftSize?: number;
  /** Min frequency (Hz) */
  minFrequency?: number;
  /** Max frequency (Hz) */
  maxFrequency?: number;
  /** Frequency scale */
  frequencyScale?: FrequencyScale;
  /** Color scheme */
  colorScheme?: ColorScheme;
  /** Min decibels */
  minDecibels?: number;
  /** Max decibels */
  maxDecibels?: number;
  /** Height */
  height?: number;
  /** Show frequency axis */
  showAxis?: boolean;
  /** Scroll offset (for offline) */
  offset?: number;
  /** Zoom (pixels per second) */
  zoom?: number;
  /** Custom class */
  className?: string;
}

// ============ Color Schemes ============

const colorSchemes: Record<ColorScheme, (value: number) => [number, number, number]> = {
  heat: (v) => {
    if (v < 0.33) return [Math.floor(v * 3 * 255), 0, 0];
    if (v < 0.66) return [255, Math.floor((v - 0.33) * 3 * 255), 0];
    return [255, 255, Math.floor((v - 0.66) * 3 * 255)];
  },
  grayscale: (v) => {
    const g = Math.floor(v * 255);
    return [g, g, g];
  },
  rainbow: (v) => {
    const h = v * 300;
    const s = 1;
    const l = 0.5;
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = l - c / 2;
    let r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; }
    else if (h < 120) { r = x; g = c; }
    else if (h < 180) { g = c; b = x; }
    else if (h < 240) { g = x; b = c; }
    else if (h < 300) { r = x; b = c; }
    else { r = c; b = x; }
    return [
      Math.floor((r + m) * 255),
      Math.floor((g + m) * 255),
      Math.floor((b + m) * 255),
    ];
  },
  plasma: (v) => {
    const r = Math.floor((0.05 + 0.95 * v) * 255);
    const g = Math.floor(Math.abs(Math.sin(v * Math.PI)) * 255);
    const b = Math.floor((1 - v * 0.8) * 255);
    return [r, g, b];
  },
  viridis: (v) => {
    // Simplified viridis approximation
    const r = Math.floor((0.27 + 0.46 * v) * 255);
    const g = Math.floor((0.02 + 0.91 * Math.pow(v, 0.7)) * 255);
    const b = Math.floor((0.33 + 0.5 * (1 - v)) * 255);
    return [Math.min(255, r), Math.min(255, g), Math.min(255, b)];
  },
};

// ============ Spectrogram Component ============

export function Spectrogram({
  audioBuffer,
  analyserNode,
  fftSize = 2048,
  minFrequency = 20,
  maxFrequency = 20000,
  frequencyScale = 'logarithmic',
  colorScheme = 'heat',
  minDecibels = -90,
  maxDecibels = -10,
  height = 256,
  showAxis = true,
  offset: _offset = 0,
  zoom: _zoom = 100,
  className = '',
}: SpectrogramProps) {
  void _offset; void _zoom; // Reserved for future offline rendering
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const animationRef = useRef<number>(undefined);

  // Get color for magnitude
  const getColor = useCallback(
    (magnitude: number): [number, number, number] => {
      const normalized = Math.max(0, Math.min(1, (magnitude - minDecibels) / (maxDecibels - minDecibels)));
      return colorSchemes[colorScheme](normalized);
    },
    [colorScheme, minDecibels, maxDecibels]
  );

  // Convert frequency to Y position
  const freqToY = useCallback(
    (freq: number, canvasHeight: number): number => {
      const minLog = Math.log10(minFrequency);
      const maxLog = Math.log10(maxFrequency);

      if (frequencyScale === 'logarithmic') {
        const logFreq = Math.log10(Math.max(minFrequency, Math.min(maxFrequency, freq)));
        const normalized = (logFreq - minLog) / (maxLog - minLog);
        return canvasHeight - normalized * canvasHeight;
      } else {
        const normalized = (freq - minFrequency) / (maxFrequency - minFrequency);
        return canvasHeight - normalized * canvasHeight;
      }
    },
    [minFrequency, maxFrequency, frequencyScale]
  );

  // Generate spectrogram from audio buffer (offline)
  useEffect(() => {
    if (!audioBuffer || analyserNode) return;

    const generateSpectrogram = async () => {
      const offlineCtx = new OfflineAudioContext(
        1,
        audioBuffer.length,
        audioBuffer.sampleRate
      );

      const source = offlineCtx.createBufferSource();
      source.buffer = audioBuffer;

      const analyser = offlineCtx.createAnalyser();
      analyser.fftSize = fftSize;
      analyser.minDecibels = minDecibels;
      analyser.maxDecibels = maxDecibels;

      source.connect(analyser);
      analyser.connect(offlineCtx.destination);
      source.start();

      // This is a simplified approach - real implementation would use ScriptProcessor or AudioWorklet
      // For now, just render a placeholder
    };

    generateSpectrogram();
  }, [audioBuffer, analyserNode, fftSize, minDecibels, maxDecibels]);

  // Real-time spectrogram from analyser node
  useEffect(() => {
    if (!analyserNode) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    analyserNode.fftSize = fftSize;
    analyserNode.minDecibels = minDecibels;
    analyserNode.maxDecibels = maxDecibels;

    const bufferLength = analyserNode.frequencyBinCount;
    const dataArray = new Uint8Array(bufferLength);
    const sampleRate = analyserNode.context.sampleRate;
    const nyquist = sampleRate / 2;

    const draw = () => {
      analyserNode.getByteFrequencyData(dataArray);

      const { width } = canvas;
      const canvasHeight = canvas.height;

      // Shift existing image left
      const imageData = ctx.getImageData(1, 0, width - 1, canvasHeight);
      ctx.putImageData(imageData, 0, 0);

      // Draw new column
      for (let i = 0; i < bufferLength; i++) {
        const freq = (i / bufferLength) * nyquist;
        if (freq < minFrequency || freq > maxFrequency) continue;

        const y = freqToY(freq, canvasHeight);
        const magnitude = minDecibels + (dataArray[i] / 255) * (maxDecibels - minDecibels);
        const [r, g, b] = getColor(magnitude);

        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(width - 1, y, 1, 2);
      }

      animationRef.current = requestAnimationFrame(draw);
    };

    draw();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [analyserNode, fftSize, minDecibels, maxDecibels, minFrequency, maxFrequency, freqToY, getColor]);

  // Initial canvas setup
  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const { width } = container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d');
    if (ctx) {
      ctx.scale(dpr, dpr);
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, width, height);
    }
  }, [height]);

  // Frequency axis labels
  const axisLabels = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000].filter(
    (f) => f >= minFrequency && f <= maxFrequency
  );

  return (
    <div ref={containerRef} className={`spectrogram ${className}`} style={{ height }}>
      <canvas ref={canvasRef} className="spectrogram__canvas" />

      {showAxis && (
        <div className="spectrogram__axis">
          {axisLabels.map((freq) => {
            const y = freqToY(freq, height);
            return (
              <div
                key={freq}
                className="spectrogram__axis-label"
                style={{ top: y }}
              >
                {freq >= 1000 ? `${freq / 1000}k` : freq}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ============ useSpectrogram Hook ============

export function useSpectrogram(audioContext: AudioContext | null) {
  const [analyser, setAnalyser] = useState<AnalyserNode | null>(null);

  useEffect(() => {
    if (!audioContext) {
      setAnalyser(null);
      return;
    }

    const analyserNode = audioContext.createAnalyser();
    analyserNode.fftSize = 2048;
    analyserNode.smoothingTimeConstant = 0.8;
    setAnalyser(analyserNode);
  }, [audioContext]);

  return analyser;
}

export default Spectrogram;

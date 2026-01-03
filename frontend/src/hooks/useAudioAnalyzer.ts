/**
 * ReelForge Audio Analyzer Hook
 *
 * Generic real-time audio analysis hook that provides:
 * - FFT spectrum data for visualizers
 * - Time domain waveform data
 * - Peak/RMS level metering
 * - Automatic idle detection
 *
 * Designed to work with PixiSpectrum and PixiWaveform components.
 *
 * @module hooks/useAudioAnalyzer
 */

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { AudioContextManager } from '../core/AudioContextManager';

// ============ Types ============

export interface AudioAnalyzerConfig {
  /** FFT size - must be power of 2 (default: 2048) */
  fftSize: 256 | 512 | 1024 | 2048 | 4096 | 8192;
  /** Smoothing time constant 0-1 (default: 0.8) */
  smoothingTimeConstant: number;
  /** Minimum decibels for range (default: -90) */
  minDecibels: number;
  /** Maximum decibels for range (default: -10) */
  maxDecibels: number;
  /** Target FPS for updates (default: 60) */
  targetFps: number;
  /** Idle detection threshold in dB (default: -80) */
  idleThreshold: number;
  /** Enable waveform data collection (default: true) */
  enableWaveform: boolean;
  /** Enable FFT spectrum data collection (default: true) */
  enableSpectrum: boolean;
}

export interface AudioLevels {
  /** Peak level (0-1) */
  peak: number;
  /** RMS level (0-1) */
  rms: number;
  /** Peak level in dB */
  peakDb: number;
  /** RMS level in dB */
  rmsDb: number;
  /** Left channel peak (if stereo) */
  peakL?: number;
  /** Right channel peak (if stereo) */
  peakR?: number;
}

export interface AudioAnalyzerData {
  /** FFT frequency data (0-255 byte values) */
  fftData: Uint8Array<ArrayBufferLike>;
  /** FFT frequency data in dB (Float32) */
  fftDataDb: Float32Array<ArrayBufferLike>;
  /** Time domain waveform data (-1 to 1) */
  waveformData: Float32Array<ArrayBufferLike>;
  /** Current audio levels */
  levels: AudioLevels;
  /** Number of frequency bins */
  binCount: number;
  /** Frequency resolution (Hz per bin) */
  binWidth: number;
  /** Whether audio is below idle threshold */
  isIdle: boolean;
  /** Sample rate of the audio context */
  sampleRate: number;
}

export interface UseAudioAnalyzerReturn {
  /** Current analyzer data (null if not connected) */
  data: AudioAnalyzerData | null;
  /** Whether analyzer is running */
  isActive: boolean;
  /** Whether audio is idle (below threshold) */
  isIdle: boolean;
  /** Connect to an audio node */
  connect: (source: AudioNode) => void;
  /** Connect to AudioContext destination for master analysis */
  connectToMaster: () => void;
  /** Disconnect from current source */
  disconnect: () => void;
  /** Start the analyzer */
  start: () => void;
  /** Stop the analyzer */
  stop: () => void;
  /** Update configuration */
  updateConfig: (config: Partial<AudioAnalyzerConfig>) => void;
  /** Get the analyzer node (for chaining) */
  getAnalyzerNode: () => AnalyserNode | null;
  /** Audio context reference */
  audioContext: AudioContext | null;
}

// ============ Default Config ============

const DEFAULT_CONFIG: AudioAnalyzerConfig = {
  fftSize: 2048,
  smoothingTimeConstant: 0.8,
  minDecibels: -90,
  maxDecibels: -10,
  targetFps: 60,
  idleThreshold: -80,
  enableWaveform: true,
  enableSpectrum: true,
};

// ============ Utility Functions ============

/**
 * Convert linear amplitude to decibels.
 */
function linearToDb(value: number): number {
  if (value <= 0) return -Infinity;
  return 20 * Math.log10(value);
}

/**
 * Calculate RMS (Root Mean Square) of an array.
 * Includes noise gate: values below -90dB are treated as silence.
 */
function calculateRms(data: Float32Array<ArrayBufferLike>): number {
  // Noise gate threshold: -90dB = ~0.00003 linear
  const NOISE_FLOOR = 0.00003;

  let sum = 0;
  for (let i = 0; i < data.length; i++) {
    sum += data[i] * data[i];
  }
  const rms = Math.sqrt(sum / data.length);

  // Apply noise gate: below threshold = silence
  if (rms < NOISE_FLOOR) {
    return 0;
  }

  return rms;
}

/**
 * Calculate peak value of an array.
 * Includes noise gate: values below -90dB are treated as silence.
 */
function calculatePeak(data: Float32Array<ArrayBufferLike>): number {
  // Noise gate threshold: -90dB = ~0.00003 linear
  const NOISE_FLOOR = 0.00003;

  let peak = 0;
  for (let i = 0; i < data.length; i++) {
    const abs = Math.abs(data[i]);
    if (abs > peak) peak = abs;
  }

  // Apply noise gate: below threshold = silence
  if (peak < NOISE_FLOOR) {
    return 0;
  }

  return peak;
}

// ============ Hook ============

/**
 * Hook for real-time audio analysis.
 *
 * @param existingContext - Optional existing AudioContext to use
 * @param initialConfig - Optional initial configuration
 */
export function useAudioAnalyzer(
  existingContext?: AudioContext | null,
  initialConfig: Partial<AudioAnalyzerConfig> = {}
): UseAudioAnalyzerReturn {
  // State
  const [isActive, setIsActive] = useState(false);
  const [isIdle, setIsIdle] = useState(true);
  const [data, setData] = useState<AudioAnalyzerData | null>(null);

  // Refs
  const audioContextRef = useRef<AudioContext | null>(existingContext || null);
  const analyzerRef = useRef<AnalyserNode | null>(null);
  const splitterRef = useRef<ChannelSplitterNode | null>(null);
  const analyzerLRef = useRef<AnalyserNode | null>(null);
  const analyzerRRef = useRef<AnalyserNode | null>(null);
  const sourceRef = useRef<AudioNode | null>(null);
  const rafRef = useRef<number>(0);
  const lastFrameTimeRef = useRef<number>(0);
  const configRef = useRef<AudioAnalyzerConfig>({ ...DEFAULT_CONFIG, ...initialConfig });

  // Data buffers (reused to avoid GC)
  const fftDataRef = useRef<Uint8Array<ArrayBuffer> | null>(null);
  const fftDataDbRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const waveformDataRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const waveformLRef = useRef<Float32Array<ArrayBuffer> | null>(null);
  const waveformRRef = useRef<Float32Array<ArrayBuffer> | null>(null);

  // Memoized config (accessed via configRef.current)
  useMemo(() => configRef.current, []);

  // Initialize or get AudioContext from singleton
  const getAudioContext = useCallback((): AudioContext => {
    if (!audioContextRef.current) {
      audioContextRef.current = AudioContextManager.getContext();
    }
    return audioContextRef.current;
  }, []);

  // Create analyzer nodes
  const createAnalyzerNodes = useCallback(() => {
    const ctx = getAudioContext();
    const cfg = configRef.current;

    // Main analyzer
    const analyzer = ctx.createAnalyser();
    analyzer.fftSize = cfg.fftSize;
    analyzer.smoothingTimeConstant = cfg.smoothingTimeConstant;
    analyzer.minDecibels = cfg.minDecibels;
    analyzer.maxDecibels = cfg.maxDecibels;
    analyzerRef.current = analyzer;

    // Create data buffers
    const binCount = analyzer.frequencyBinCount;
    fftDataRef.current = new Uint8Array(binCount);
    fftDataDbRef.current = new Float32Array(binCount);
    waveformDataRef.current = new Float32Array(cfg.fftSize);

    // Stereo channel splitter for L/R metering
    const splitter = ctx.createChannelSplitter(2);
    splitterRef.current = splitter;

    const analyzerL = ctx.createAnalyser();
    analyzerL.fftSize = 256; // Smaller for just metering
    analyzerLRef.current = analyzerL;
    waveformLRef.current = new Float32Array(256);

    const analyzerR = ctx.createAnalyser();
    analyzerR.fftSize = 256;
    analyzerRRef.current = analyzerR;
    waveformRRef.current = new Float32Array(256);

    // Connect splitter to L/R analyzers
    splitter.connect(analyzerL, 0);
    splitter.connect(analyzerR, 1);

    return analyzer;
  }, [getAudioContext]);

  // Connect to audio source
  const connect = useCallback((source: AudioNode) => {
    // Disconnect previous source
    if (sourceRef.current && analyzerRef.current) {
      try {
        sourceRef.current.disconnect(analyzerRef.current);
      } catch {
        // May already be disconnected
      }
    }

    // Create analyzer if needed
    if (!analyzerRef.current) {
      createAnalyzerNodes();
    }

    const analyzer = analyzerRef.current!;
    const splitter = splitterRef.current!;

    // Connect source -> analyzer and splitter
    source.connect(analyzer);
    source.connect(splitter);
    sourceRef.current = source;
  }, [createAnalyzerNodes]);

  // Connect to master output
  const connectToMaster = useCallback(() => {
    const ctx = getAudioContext();

    // Create a silent gain node connected to destination
    // and tap into it for analysis
    if (!analyzerRef.current) {
      createAnalyzerNodes();
    }

    // Note: For true master analysis, you'd need to route all audio through
    // the analyzer. This creates a tap point.
    const analyzer = analyzerRef.current!;
    analyzer.connect(ctx.destination);
  }, [getAudioContext, createAnalyzerNodes]);

  // Disconnect
  const disconnect = useCallback(() => {
    if (sourceRef.current && analyzerRef.current) {
      try {
        sourceRef.current.disconnect(analyzerRef.current);
        sourceRef.current.disconnect(splitterRef.current!);
      } catch {
        // May already be disconnected
      }
    }
    sourceRef.current = null;
  }, []);

  // Animation loop
  useEffect(() => {
    if (!isActive || !analyzerRef.current) return;

    const cfg = configRef.current;
    const frameInterval = 1000 / cfg.targetFps;

    const analyzer = analyzerRef.current;
    const analyzerL = analyzerLRef.current;
    const analyzerR = analyzerRRef.current;
    const fftData = fftDataRef.current!;
    const fftDataDb = fftDataDbRef.current!;
    const waveformData = waveformDataRef.current!;
    const waveformL = waveformLRef.current;
    const waveformR = waveformRRef.current;

    const update = (timestamp: number) => {
      // Throttle to target FPS
      const elapsed = timestamp - lastFrameTimeRef.current;
      if (elapsed < frameInterval) {
        rafRef.current = requestAnimationFrame(update);
        return;
      }
      lastFrameTimeRef.current = timestamp;

      // Get FFT data
      if (cfg.enableSpectrum) {
        analyzer.getByteFrequencyData(fftData);
        analyzer.getFloatFrequencyData(fftDataDb);
      }

      // Get waveform data
      if (cfg.enableWaveform) {
        analyzer.getFloatTimeDomainData(waveformData);
      }

      // Calculate levels
      const peak = calculatePeak(waveformData);
      const rms = calculateRms(waveformData);
      const peakDb = linearToDb(peak);
      const rmsDb = linearToDb(rms);

      // Check if idle
      const idle = peakDb < cfg.idleThreshold;
      setIsIdle(idle);

      // Calculate stereo peaks if available
      let peakL: number | undefined;
      let peakR: number | undefined;

      if (analyzerL && analyzerR && waveformL && waveformR) {
        analyzerL.getFloatTimeDomainData(waveformL);
        analyzerR.getFloatTimeDomainData(waveformR);
        peakL = calculatePeak(waveformL);
        peakR = calculatePeak(waveformR);
      }

      // Build data object
      const ctx = audioContextRef.current;
      const newData: AudioAnalyzerData = {
        fftData: fftData.slice(), // Copy for React
        fftDataDb: fftDataDb.slice(),
        waveformData: waveformData.slice(),
        levels: {
          peak,
          rms,
          peakDb,
          rmsDb,
          peakL,
          peakR,
        },
        binCount: analyzer.frequencyBinCount,
        binWidth: ctx ? ctx.sampleRate / cfg.fftSize : 48000 / cfg.fftSize,
        isIdle: idle,
        sampleRate: ctx?.sampleRate || 48000,
      };

      setData(newData);
      rafRef.current = requestAnimationFrame(update);
    };

    rafRef.current = requestAnimationFrame(update);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [isActive]);

  // Start
  const start = useCallback(() => {
    if (!analyzerRef.current) {
      createAnalyzerNodes();
    }
    setIsActive(true);
  }, [createAnalyzerNodes]);

  // Stop
  const stop = useCallback(() => {
    setIsActive(false);
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
    }
  }, []);

  // Update config
  const updateConfig = useCallback((updates: Partial<AudioAnalyzerConfig>) => {
    configRef.current = { ...configRef.current, ...updates };

    // Update analyzer node if exists
    const analyzer = analyzerRef.current;
    if (analyzer) {
      if (updates.fftSize) {
        analyzer.fftSize = updates.fftSize;
        // Recreate buffers
        const binCount = analyzer.frequencyBinCount;
        fftDataRef.current = new Uint8Array(binCount);
        fftDataDbRef.current = new Float32Array(binCount);
        waveformDataRef.current = new Float32Array(updates.fftSize);
      }
      if (updates.smoothingTimeConstant !== undefined) {
        analyzer.smoothingTimeConstant = updates.smoothingTimeConstant;
      }
      if (updates.minDecibels !== undefined) {
        analyzer.minDecibels = updates.minDecibels;
      }
      if (updates.maxDecibels !== undefined) {
        analyzer.maxDecibels = updates.maxDecibels;
      }
    }
  }, []);

  // Get analyzer node
  const getAnalyzerNode = useCallback(() => analyzerRef.current, []);

  // Cleanup
  useEffect(() => {
    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
      disconnect();
    };
  }, [disconnect]);

  return {
    data,
    isActive,
    isIdle,
    connect,
    connectToMaster,
    disconnect,
    start,
    stop,
    updateConfig,
    getAnalyzerNode,
    audioContext: audioContextRef.current,
  };
}

// ============ Demo Data Generator ============

/**
 * Generate demo/placeholder analyzer data for testing or preview.
 */
export function generateDemoAnalyzerData(
  binCount = 1024,
  animate = true
): AudioAnalyzerData {
  const now = animate ? Date.now() / 1000 : 0;
  const fftData = new Uint8Array(binCount);
  const fftDataDb = new Float32Array(binCount);
  const waveformData = new Float32Array(2048);

  // Generate spectrum
  for (let i = 0; i < binCount; i++) {
    const freq = (i / binCount);
    // Pink noise-ish falloff with some peaks
    let value = 200 - freq * 150;
    // Add harmonics
    value += Math.sin(freq * 20 + now * 3) * 20;
    value += Math.sin(freq * 50 + now * 5) * 10;
    // Add bass bump
    if (freq < 0.1) value += 30;
    // Clamp
    value = Math.max(0, Math.min(255, value + Math.random() * 10));
    fftData[i] = value;
    fftDataDb[i] = (value / 255) * 80 - 90; // Map to dB range
  }

  // Generate waveform (sine wave with harmonics)
  for (let i = 0; i < waveformData.length; i++) {
    const t = i / waveformData.length;
    waveformData[i] =
      Math.sin(t * Math.PI * 4 + now * 10) * 0.5 +
      Math.sin(t * Math.PI * 8 + now * 15) * 0.25 +
      Math.sin(t * Math.PI * 16 + now * 20) * 0.125;
  }

  const peak = calculatePeak(waveformData);
  const rms = calculateRms(waveformData);

  return {
    fftData,
    fftDataDb,
    waveformData,
    levels: {
      peak,
      rms,
      peakDb: linearToDb(peak),
      rmsDb: linearToDb(rms),
      peakL: peak * 0.9,
      peakR: peak * 1.1,
    },
    binCount,
    binWidth: 48000 / 2048,
    isIdle: false,
    sampleRate: 48000,
  };
}

export default useAudioAnalyzer;

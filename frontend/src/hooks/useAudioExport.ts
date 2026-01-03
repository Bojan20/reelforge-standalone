/**
 * useAudioExport - Export audio mix functionality
 *
 * Provides offline rendering and export of audio mix:
 * - Render timeline to audio buffer
 * - Export to WAV/MP3 formats
 * - Progress tracking
 * - Quality settings
 *
 * @module hooks/useAudioExport
 */

import { useState, useCallback, useRef } from 'react';
import { TruePeakLimiter } from '../core/dsp/truePeakLimiter';

// ============ Types ============

export type ExportFormat = 'wav' | 'mp3';
export type ExportQuality = 'low' | 'medium' | 'high' | 'lossless';

export interface ExportSettings {
  format: ExportFormat;
  quality: ExportQuality;
  sampleRate: number;
  bitDepth: 16 | 24 | 32;
  channels: 1 | 2;
  normalize: boolean;
  dither: boolean;
  /** Enable true peak limiting */
  truePeakLimit?: boolean;
  /** True peak ceiling in dBTP (default: -1.0) */
  truePeakCeiling?: number;
}

export interface ExportClip {
  id: string;
  name: string;
  startTime: number;
  duration: number;
  audioBuffer: AudioBuffer;
  gainDb?: number;
  pan?: number;
}

export interface ExportProgress {
  stage: 'preparing' | 'rendering' | 'encoding' | 'complete' | 'error';
  progress: number; // 0-1
  message: string;
}

export const DEFAULT_EXPORT_SETTINGS: ExportSettings = {
  format: 'wav',
  quality: 'high',
  sampleRate: 48000,
  bitDepth: 24,
  channels: 2,
  normalize: true,
  dither: false,
  truePeakLimit: true,
  truePeakCeiling: -1.0, // EBU R128 / streaming platforms
};

// ============ WAV Encoder ============

function encodeWAV(
  samples: Float32Array[],
  sampleRate: number,
  bitDepth: 16 | 24 | 32
): ArrayBuffer {
  const numChannels = samples.length;
  const length = samples[0].length;
  const bytesPerSample = bitDepth / 8;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;
  const dataSize = length * blockAlign;
  const bufferSize = 44 + dataSize;

  const buffer = new ArrayBuffer(bufferSize);
  const view = new DataView(buffer);

  // RIFF header
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(view, 8, 'WAVE');

  // fmt chunk
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // chunk size
  view.setUint16(20, bitDepth === 32 ? 3 : 1, true); // format (3 = IEEE float, 1 = PCM)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitDepth, true);

  // data chunk
  writeString(view, 36, 'data');
  view.setUint32(40, dataSize, true);

  // Interleaved samples
  let offset = 44;
  for (let i = 0; i < length; i++) {
    for (let ch = 0; ch < numChannels; ch++) {
      const sample = Math.max(-1, Math.min(1, samples[ch][i]));

      if (bitDepth === 32) {
        view.setFloat32(offset, sample, true);
      } else if (bitDepth === 24) {
        const intSample = Math.round(sample * 8388607);
        view.setUint8(offset, intSample & 0xff);
        view.setUint8(offset + 1, (intSample >> 8) & 0xff);
        view.setUint8(offset + 2, (intSample >> 16) & 0xff);
      } else {
        const intSample = Math.round(sample * 32767);
        view.setInt16(offset, intSample, true);
      }
      offset += bytesPerSample;
    }
  }

  return buffer;
}

function writeString(view: DataView, offset: number, string: string): void {
  for (let i = 0; i < string.length; i++) {
    view.setUint8(offset + i, string.charCodeAt(i));
  }
}

// ============ Audio Processing ============

function normalizeBuffer(samples: Float32Array[], targetPeakDb: number = -1): void {
  let maxPeak = 0;

  // Find max peak across all channels
  for (const channel of samples) {
    for (let i = 0; i < channel.length; i++) {
      const abs = Math.abs(channel[i]);
      if (abs > maxPeak) maxPeak = abs;
    }
  }

  if (maxPeak === 0) return;

  // Calculate gain to reach target peak
  const targetLinear = Math.pow(10, targetPeakDb / 20);
  const gain = targetLinear / maxPeak;

  // Apply gain
  for (const channel of samples) {
    for (let i = 0; i < channel.length; i++) {
      channel[i] *= gain;
    }
  }
}

function applyDither(samples: Float32Array[], bitDepth: 16 | 24 | 32): void {
  if (bitDepth === 32) return; // No dither for float

  const ditherAmount = 1 / (1 << (bitDepth - 1));

  for (const channel of samples) {
    for (let i = 0; i < channel.length; i++) {
      // Triangular probability distribution dither (TPDF)
      const dither = (Math.random() + Math.random() - 1) * ditherAmount;
      channel[i] += dither;
    }
  }
}

/**
 * Apply true peak limiting to stereo samples.
 * Ensures output never exceeds ceiling (dBTP).
 */
function applyTruePeakLimit(
  samples: Float32Array[],
  ceiling: number,
  sampleRate: number
): void {
  if (samples.length < 1) return;

  const limiter = new TruePeakLimiter({
    ceiling,
    release: 100,
    lookahead: 1.5,
    knee: 0,
    truePeak: true,
    sampleRate,
  });

  const blockSize = 512;
  const length = samples[0].length;
  const inputL = samples[0];
  const inputR = samples.length > 1 ? samples[1] : samples[0];

  for (let i = 0; i < length; i += blockSize) {
    const end = Math.min(i + blockSize, length);
    const blockLen = end - i;

    const blockInL = inputL.subarray(i, end);
    const blockInR = inputR.subarray(i, end);
    const blockOutL = new Float32Array(blockLen);
    const blockOutR = new Float32Array(blockLen);

    limiter.process(blockInL, blockInR, blockOutL, blockOutR);

    // Write back in place
    inputL.set(blockOutL, i);
    if (samples.length > 1) {
      inputR.set(blockOutR, i);
    }
  }

  const state = limiter.getState();
  if (state.gainReduction < -0.1) {
    console.log(`[AudioExport] True Peak Limiter: ${state.gainReduction.toFixed(1)} dB GR`);
  }
}

// ============ Hook ============

export function useAudioExport() {
  const [progress, setProgress] = useState<ExportProgress>({
    stage: 'complete',
    progress: 0,
    message: '',
  });
  const [isExporting, setIsExporting] = useState(false);
  const abortRef = useRef(false);

  /**
   * Render clips to a stereo audio buffer.
   */
  const renderMix = useCallback(async (
    clips: ExportClip[],
    duration: number,
    settings: ExportSettings
  ): Promise<AudioBuffer | null> => {
    if (clips.length === 0) {
      return null;
    }

    setProgress({ stage: 'preparing', progress: 0, message: 'Preparing render...' });

    // Create offline context
    const offlineCtx = new OfflineAudioContext(
      settings.channels,
      Math.ceil(duration * settings.sampleRate),
      settings.sampleRate
    );

    setProgress({ stage: 'rendering', progress: 0.1, message: 'Rendering clips...' });

    // Schedule all clips
    for (let i = 0; i < clips.length; i++) {
      if (abortRef.current) return null;

      const clip = clips[i];
      const source = offlineCtx.createBufferSource();
      source.buffer = clip.audioBuffer;

      const gainNode = offlineCtx.createGain();
      gainNode.gain.value = clip.gainDb !== undefined
        ? Math.pow(10, clip.gainDb / 20)
        : 1;

      // Pan (simple stereo pan)
      const panNode = offlineCtx.createStereoPanner?.();
      if (panNode && clip.pan !== undefined) {
        panNode.pan.value = clip.pan;
        source.connect(gainNode);
        gainNode.connect(panNode);
        panNode.connect(offlineCtx.destination);
      } else {
        source.connect(gainNode);
        gainNode.connect(offlineCtx.destination);
      }

      // Schedule clip
      const startTime = Math.max(0, clip.startTime);
      source.start(startTime, 0, clip.duration);

      setProgress({
        stage: 'rendering',
        progress: 0.1 + (i / clips.length) * 0.6,
        message: `Rendering clip ${i + 1}/${clips.length}...`,
      });
    }

    setProgress({ stage: 'rendering', progress: 0.7, message: 'Completing render...' });

    // Render
    const renderedBuffer = await offlineCtx.startRendering();

    return renderedBuffer;
  }, []);

  /**
   * Export clips to a downloadable file.
   */
  const exportMix = useCallback(async (
    clips: ExportClip[],
    duration: number,
    fileName: string,
    settings: ExportSettings = DEFAULT_EXPORT_SETTINGS
  ): Promise<Blob | null> => {
    if (isExporting) {
      console.warn('[AudioExport] Export already in progress');
      return null;
    }

    setIsExporting(true);
    abortRef.current = false;

    try {
      // Render to buffer
      const renderedBuffer = await renderMix(clips, duration, settings);
      if (!renderedBuffer || abortRef.current) {
        throw new Error('Render cancelled or failed');
      }

      setProgress({ stage: 'encoding', progress: 0.75, message: 'Encoding audio...' });

      // Extract channel data
      const samples: Float32Array[] = [];
      for (let ch = 0; ch < renderedBuffer.numberOfChannels; ch++) {
        samples.push(renderedBuffer.getChannelData(ch));
      }

      // Apply true peak limiting (before normalization for transparent operation)
      if (settings.truePeakLimit !== false) {
        const ceiling = settings.truePeakCeiling ?? -1.0;
        applyTruePeakLimit(samples, ceiling, settings.sampleRate);
      }

      // Normalize if requested
      if (settings.normalize) {
        normalizeBuffer(samples, -1);

        // Re-apply limiter after normalization to ensure no inter-sample peaks
        if (settings.truePeakLimit !== false) {
          const ceiling = settings.truePeakCeiling ?? -1.0;
          applyTruePeakLimit(samples, ceiling, settings.sampleRate);
        }
      }

      // Apply dither if requested (after all processing, before encoding)
      if (settings.dither) {
        applyDither(samples, settings.bitDepth);
      }

      setProgress({ stage: 'encoding', progress: 0.85, message: 'Creating file...' });

      // Encode
      let blob: Blob;

      if (settings.format === 'wav') {
        const wavData = encodeWAV(samples, settings.sampleRate, settings.bitDepth);
        blob = new Blob([wavData], { type: 'audio/wav' });
      } else {
        // MP3 encoding would require a library like lamejs
        // For now, fall back to WAV
        console.warn('[AudioExport] MP3 export not yet implemented, using WAV');
        const wavData = encodeWAV(samples, settings.sampleRate, settings.bitDepth);
        blob = new Blob([wavData], { type: 'audio/wav' });
      }

      setProgress({ stage: 'complete', progress: 1, message: 'Export complete!' });

      // Trigger download
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${fileName}.${settings.format === 'mp3' ? 'wav' : settings.format}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);

      console.log(`[AudioExport] Exported ${fileName}.${settings.format}`);

      return blob;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Export failed';
      setProgress({ stage: 'error', progress: 0, message });
      console.error('[AudioExport] Error:', err);
      return null;
    } finally {
      setIsExporting(false);
    }
  }, [isExporting, renderMix]);

  /**
   * Abort current export.
   */
  const abort = useCallback(() => {
    abortRef.current = true;
  }, []);

  return {
    exportMix,
    renderMix,
    abort,
    progress,
    isExporting,
  };
}

export type AudioExportReturn = ReturnType<typeof useAudioExport>;

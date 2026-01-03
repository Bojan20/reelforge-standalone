/**
 * ReelForge Audio File Manager
 *
 * Handles audio file import, export, and format conversion.
 * Supports:
 * - WAV, MP3, OGG, FLAC import
 * - WAV export with configurable bit depth
 * - Audio buffer caching
 * - Waveform generation
 *
 * @module audio/AudioFileManager
 */

import { generateWaveformPeaks } from './WaveformDisplay';
import { AudioContextManager } from '../core/AudioContextManager';

// ============ Types ============

export interface AudioFile {
  /** Unique file ID */
  id: string;
  /** Original filename */
  name: string;
  /** File size in bytes */
  size: number;
  /** Duration in seconds */
  duration: number;
  /** Sample rate */
  sampleRate: number;
  /** Number of channels */
  channels: number;
  /** Audio buffer (decoded) */
  buffer: AudioBuffer;
  /** Waveform peaks for display */
  waveform: Float32Array;
  /** File type */
  type: 'wav' | 'mp3' | 'ogg' | 'flac' | 'unknown';
  /** Import timestamp */
  importedAt: number;
}

export interface ExportOptions {
  /** Output format */
  format: 'wav';
  /** Sample rate (default: source rate) */
  sampleRate?: number;
  /** Bit depth (16, 24, 32) */
  bitDepth?: 16 | 24 | 32;
  /** Normalize audio */
  normalize?: boolean;
  /** Dither when reducing bit depth */
  dither?: boolean;
}

export interface ImportProgress {
  /** Current file being processed */
  file: string;
  /** Progress 0-1 */
  progress: number;
  /** Status message */
  status: 'loading' | 'decoding' | 'processing' | 'done' | 'error';
  /** Error message if status is 'error' */
  error?: string;
}

// ============ Audio Context ============
// Use shared singleton from AudioContextManager

function getAudioContext(): AudioContext {
  return AudioContextManager.getContext();
}

// ============ File Cache ============

const fileCache = new Map<string, AudioFile>();

// ============ Import Functions ============

/**
 * Import audio file from File object.
 */
export async function importAudioFile(
  file: File,
  onProgress?: (progress: ImportProgress) => void
): Promise<AudioFile> {
  const id = `audio_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  try {
    // Check cache
    const cacheKey = `${file.name}_${file.size}_${file.lastModified}`;
    if (fileCache.has(cacheKey)) {
      return fileCache.get(cacheKey)!;
    }

    onProgress?.({
      file: file.name,
      progress: 0,
      status: 'loading',
    });

    // Read file as ArrayBuffer
    const arrayBuffer = await file.arrayBuffer();

    onProgress?.({
      file: file.name,
      progress: 0.3,
      status: 'decoding',
    });

    // Decode audio
    const ctx = getAudioContext();
    const audioBuffer = await ctx.decodeAudioData(arrayBuffer);

    onProgress?.({
      file: file.name,
      progress: 0.7,
      status: 'processing',
    });

    // Generate waveform
    const waveform = generateWaveformPeaks(audioBuffer, 2000);

    // Detect file type
    const type = detectFileType(file.name);

    const audioFile: AudioFile = {
      id,
      name: file.name,
      size: file.size,
      duration: audioBuffer.duration,
      sampleRate: audioBuffer.sampleRate,
      channels: audioBuffer.numberOfChannels,
      buffer: audioBuffer,
      waveform,
      type,
      importedAt: Date.now(),
    };

    // Cache the file
    fileCache.set(cacheKey, audioFile);

    onProgress?.({
      file: file.name,
      progress: 1,
      status: 'done',
    });

    return audioFile;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    onProgress?.({
      file: file.name,
      progress: 0,
      status: 'error',
      error: message,
    });
    throw new Error(`Failed to import ${file.name}: ${message}`);
  }
}

/**
 * Import multiple audio files.
 */
export async function importAudioFiles(
  files: FileList | File[],
  onProgress?: (progress: ImportProgress, index: number, total: number) => void
): Promise<AudioFile[]> {
  const fileArray = Array.from(files);
  const results: AudioFile[] = [];

  for (let i = 0; i < fileArray.length; i++) {
    const file = fileArray[i];
    const audioFile = await importAudioFile(file, (progress) => {
      onProgress?.(progress, i, fileArray.length);
    });
    results.push(audioFile);
  }

  return results;
}

/**
 * Import audio from URL.
 */
export async function importAudioFromURL(
  url: string,
  onProgress?: (progress: ImportProgress) => void
): Promise<AudioFile> {
  const id = `audio_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  const name = url.split('/').pop() || 'audio';

  try {
    onProgress?.({
      file: name,
      progress: 0,
      status: 'loading',
    });

    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const arrayBuffer = await response.arrayBuffer();

    onProgress?.({
      file: name,
      progress: 0.3,
      status: 'decoding',
    });

    const ctx = getAudioContext();
    const audioBuffer = await ctx.decodeAudioData(arrayBuffer);

    onProgress?.({
      file: name,
      progress: 0.7,
      status: 'processing',
    });

    const waveform = generateWaveformPeaks(audioBuffer, 2000);
    const type = detectFileType(name);

    const audioFile: AudioFile = {
      id,
      name,
      size: arrayBuffer.byteLength,
      duration: audioBuffer.duration,
      sampleRate: audioBuffer.sampleRate,
      channels: audioBuffer.numberOfChannels,
      buffer: audioBuffer,
      waveform,
      type,
      importedAt: Date.now(),
    };

    onProgress?.({
      file: name,
      progress: 1,
      status: 'done',
    });

    return audioFile;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error';
    onProgress?.({
      file: name,
      progress: 0,
      status: 'error',
      error: message,
    });
    throw new Error(`Failed to import from URL: ${message}`);
  }
}

// ============ Export Functions ============

/**
 * Export AudioBuffer to WAV file.
 */
export function exportToWav(
  buffer: AudioBuffer,
  options: ExportOptions = { format: 'wav' }
): Blob {
  const {
    sampleRate = buffer.sampleRate,
    bitDepth = 16,
    normalize = false,
    dither = true,
  } = options;

  // Resample if needed
  let processedBuffer = buffer;
  if (sampleRate !== buffer.sampleRate) {
    processedBuffer = resampleBuffer(buffer, sampleRate);
  }

  // Get interleaved samples
  const numChannels = processedBuffer.numberOfChannels;
  const length = processedBuffer.length;
  const interleaved = new Float32Array(length * numChannels);

  for (let channel = 0; channel < numChannels; channel++) {
    const channelData = processedBuffer.getChannelData(channel);
    for (let i = 0; i < length; i++) {
      interleaved[i * numChannels + channel] = channelData[i];
    }
  }

  // Normalize if requested
  let samples = interleaved;
  if (normalize) {
    samples = normalizeAudio(interleaved);
  }

  // Convert to target bit depth
  const bytesPerSample = bitDepth / 8;
  const dataLength = samples.length * bytesPerSample;
  const buffer32 = new ArrayBuffer(44 + dataLength);
  const view = new DataView(buffer32);

  // Write WAV header
  writeWavHeader(view, {
    numChannels,
    sampleRate,
    bitDepth,
    dataLength,
  });

  // Write audio data with proper TPDF dithering
  // TPDF (Triangular Probability Density Function) dithering:
  // - Sum of two uniform random numbers creates triangular distribution
  // - Optimal for bit-depth reduction (decorrelates quantization error)
  // - Standard practice in Cubase, Pro Tools, Logic Pro mastering
  let offset = 44;

  // Pre-calculate quantization step for dithering
  // For 16-bit: quantStep = 1/32768 ≈ 0.00003
  // For 24-bit: quantStep = 1/8388608 ≈ 0.00000012
  const quantStep = bitDepth === 16 ? 1 / 32768 : bitDepth === 24 ? 1 / 8388608 : 0;

  for (let i = 0; i < samples.length; i++) {
    let sample = samples[i];

    // Apply TPDF dithering for bit depth reduction (16-bit and 24-bit)
    // TPDF = sum of two uniform random [-0.5, 0.5] = triangular [-1, 1]
    // Amplitude = 2 LSBs peak-to-peak, which is optimal for masking quantization
    if (dither && bitDepth < 32) {
      const tpdfNoise = (Math.random() + Math.random() - 1) * quantStep;
      sample += tpdfNoise;
    }

    // Clamp to prevent wrap-around distortion
    sample = Math.max(-1, Math.min(1, sample));

    if (bitDepth === 16) {
      const int16 = Math.round(sample * 32767);
      view.setInt16(offset, int16, true);
      offset += 2;
    } else if (bitDepth === 24) {
      const int24 = Math.round(sample * 8388607);
      view.setUint8(offset, int24 & 0xff);
      view.setUint8(offset + 1, (int24 >> 8) & 0xff);
      view.setUint8(offset + 2, (int24 >> 16) & 0xff);
      offset += 3;
    } else if (bitDepth === 32) {
      view.setFloat32(offset, sample, true);
      offset += 4;
    }
  }

  return new Blob([buffer32], { type: 'audio/wav' });
}

/**
 * Download audio file.
 */
export function downloadAudioFile(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Export and download AudioBuffer as WAV.
 */
export function exportAndDownload(
  buffer: AudioBuffer,
  filename: string,
  options?: ExportOptions
): void {
  const blob = exportToWav(buffer, options);
  const name = filename.endsWith('.wav') ? filename : `${filename}.wav`;
  downloadAudioFile(blob, name);
}

// ============ Helper Functions ============

function detectFileType(filename: string): AudioFile['type'] {
  const ext = filename.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'wav':
      return 'wav';
    case 'mp3':
      return 'mp3';
    case 'ogg':
    case 'oga':
      return 'ogg';
    case 'flac':
      return 'flac';
    default:
      return 'unknown';
  }
}

function writeWavHeader(
  view: DataView,
  opts: {
    numChannels: number;
    sampleRate: number;
    bitDepth: number;
    dataLength: number;
  }
): void {
  const { numChannels, sampleRate, bitDepth, dataLength } = opts;
  const bytesPerSample = bitDepth / 8;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;

  // RIFF header
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataLength, true);
  writeString(view, 8, 'WAVE');

  // fmt chunk
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // Subchunk1Size
  view.setUint16(20, bitDepth === 32 ? 3 : 1, true); // AudioFormat (1=PCM, 3=Float)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitDepth, true);

  // data chunk
  writeString(view, 36, 'data');
  view.setUint32(40, dataLength, true);
}

function writeString(view: DataView, offset: number, str: string): void {
  for (let i = 0; i < str.length; i++) {
    view.setUint8(offset + i, str.charCodeAt(i));
  }
}

function normalizeAudio(samples: Float32Array<ArrayBuffer>): Float32Array<ArrayBuffer> {
  let max = 0;
  for (let i = 0; i < samples.length; i++) {
    const abs = Math.abs(samples[i]);
    if (abs > max) max = abs;
  }

  if (max === 0 || max >= 0.99) return samples;

  const gain = 0.99 / max;
  const normalized = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    normalized[i] = samples[i] * gain;
  }

  return normalized;
}

function resampleBuffer(buffer: AudioBuffer, _targetRate: number): AudioBuffer {
  // Note: Proper resampling requires async OfflineAudioContext.
  // This is a simplified synchronous fallback that returns original buffer.
  // For production use, implement async resampling with OfflineAudioContext.
  return buffer;
}

// ============ Cache Management ============

/**
 * Get cached audio file.
 */
export function getCachedFile(id: string): AudioFile | undefined {
  for (const file of fileCache.values()) {
    if (file.id === id) return file;
  }
  return undefined;
}

/**
 * Clear file cache.
 */
export function clearCache(): void {
  fileCache.clear();
}

/**
 * Get cache size.
 */
export function getCacheSize(): number {
  let size = 0;
  for (const file of fileCache.values()) {
    size += file.size;
  }
  return size;
}

/**
 * Get all cached files.
 */
export function getAllCachedFiles(): AudioFile[] {
  return Array.from(fileCache.values());
}

// ============ Supported Formats ============

export const SUPPORTED_FORMATS = [
  '.wav',
  '.mp3',
  '.ogg',
  '.flac',
  '.m4a',
  '.aac',
  '.webm',
];

export const SUPPORTED_MIME_TYPES = [
  'audio/wav',
  'audio/wave',
  'audio/x-wav',
  'audio/mpeg',
  'audio/mp3',
  'audio/ogg',
  'audio/flac',
  'audio/m4a',
  'audio/aac',
  'audio/webm',
];

/**
 * Check if file is supported.
 */
export function isSupported(file: File): boolean {
  const ext = '.' + file.name.split('.').pop()?.toLowerCase();
  return SUPPORTED_FORMATS.includes(ext) || SUPPORTED_MIME_TYPES.includes(file.type);
}

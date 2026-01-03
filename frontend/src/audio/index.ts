/**
 * ReelForge Audio
 *
 * Audio file management and visualization.
 *
 * @module audio
 */

// AudioFileManager exports functions and types, not a class
export {
  importAudioFile,
  importAudioFiles,
  importAudioFromURL,
  exportToWav,
  downloadAudioFile,
  exportAndDownload,
  getCachedFile,
  clearCache,
  getCacheSize,
  getAllCachedFiles,
  isSupported,
  SUPPORTED_FORMATS,
  SUPPORTED_MIME_TYPES,
  type AudioFile,
  type ExportOptions,
  type ImportProgress,
} from './AudioFileManager';

// WaveformDisplay - component and utilities
export {
  WaveformDisplay,
  generateWaveformPeaks,
  generateStereoWaveformPeaks,
  downsampleWaveform as downsampleWaveformDisplay,
  type WaveformDisplayProps,
} from './WaveformDisplay';
export { default as WaveformDisplayDefault } from './WaveformDisplay';

// Waveform Generator - efficient waveform generation with caching
export {
  generateWaveform,
  generateWaveformAtResolution,
  generateWaveformAsync,
  downsampleWaveform,
  waveformToArray,
  waveformToFloat32Array,
  getCachedWaveform,
  clearWaveformCache,
  getWaveformCacheStats,
  calculateOptimalResolution,
  getWaveformSegment,
  normalizeWaveform,
  type WaveformOptions,
  type WaveformData,
  type WaveformCacheEntry,
} from './waveformGenerator';

/**
 * ReelForge Utilities
 *
 * Shared utility functions.
 *
 * @module utils
 */

// Performance utilities (primary)
export {
  FPSCounter,
  PerformanceMonitor,
  RAFScheduler,
  rafScheduler,
  measure,
  measureAsync,
  debounce,
  throttle,
  getMemoryStats,
  perfStart,
  perfEnd,
  type FrameStats,
  type MemoryStats,
  type PerformanceReport,
} from './performance';

// Performance monitor singleton
export { perfMonitor, useRenderTimer } from './performanceMonitor';

// ReelForge integrations - namespace to avoid exampleUsage conflict
export * as ReelForgeLoopIntegrationModule from './reelforgeLoopIntegration';
export * as ReelForgeModelIntegrationModule from './reelforgeModelIntegration';

// Test utilities
export * from './testUtils';

// Audio utilities
export { audioBufferToWav, createAudioBlobUrl } from './audioBufferToWav';
export {
  resampleAudioBuffer,
  resampleAudioBufferWithProgress,
  resampleAudioBuffers,
  needsSampleRateConversion,
  getSampleRateMismatchInfo,
  formatSampleRate,
  DEFAULT_PROJECT_SAMPLE_RATE,
  COMMON_SAMPLE_RATES,
} from './sampleRateConversion';

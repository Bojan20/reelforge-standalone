/**
 * ReelForge Audio Processing
 *
 * Core audio processing modules for professional DAW operations:
 * - Crossfade processing
 * - Time stretching and pitch shifting
 * - Offline bounce/export
 * - Audio normalization
 * - Fade processing
 * - Sample rate conversion
 * - Clip gain and envelope editing
 *
 * @module audio-processing
 */

// Crossfade Engine
export {
  CrossfadeEngine,
  crossfadeEngine,
  getCrossfadeTypeName,
  getCrossfadeTypes,
  getRecommendedCrossfade,
  type CrossfadeType,
  type CrossfadeOptions,
  type CrossfadeRegion,
  type CrossfadeResult,
} from './CrossfadeEngine';

// Time Stretch Engine
export {
  TimeStretchEngine,
  timeStretchEngine,
  bpmToStretchFactor,
  semitonesToRatio,
  ratioToSemitones,
  centsToRatio,
  type TimeStretchAlgorithm,
  type WindowType,
  type TimeStretchOptions,
  type PitchShiftOptions,
  type TimeStretchResult,
} from './TimeStretch';

// Offline Bounce Engine
export {
  OfflineBounceEngine,
  offlineBounceEngine,
  downloadBounceResult,
  formatFileSize,
  formatDuration,
  type ExportFormat,
  type BitDepth,
  type SampleRateOption,
  type BounceOptions,
  type BounceRegion,
  type BounceProgress,
  type BounceResult,
} from './OfflineBounce';

// Normalization Engine
export {
  NormalizationEngine,
  normalizationEngine,
  linearToDb,
  dbToLinear,
  formatLufs,
  formatDb,
  getPlatformTarget,
  type NormalizationType,
  type NormalizationOptions,
  type NormalizationAnalysis,
  type NormalizationResult,
} from './Normalization';

// Fade Processor
export {
  FadeProcessor,
  fadeProcessor,
  getFadeCurves,
  getCurveName,
  getRecommendedCurve,
  type FadeCurve,
  type FadeOptions,
  type FadeRegion,
  type BatchFadeOptions,
} from './FadeProcessor';

// Sample Rate Converter
export {
  SampleRateConverter,
  sampleRateConverter,
  getStandardSampleRate,
  isStandardSampleRate,
  getNearestStandardRate,
  type SRCQuality,
  type SRCAlgorithm,
  type SRCOptions,
  type SRCResult,
} from './SampleRateConverter';

// Clip Gain Engine
export {
  ClipGainEngine,
  clipGainEngine,
  gainToDb,
  dbToGain,
  formatGain,
  getInterpolationName,
  getInterpolationTypes,
  type InterpolationType,
  type EnvelopePoint,
  type ClipGainEnvelope,
  type GainAutomation,
} from './ClipGain';

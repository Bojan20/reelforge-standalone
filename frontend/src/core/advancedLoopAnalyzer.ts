export interface LoopAnalysisResult {
  bpm: number | null;
  beatsPerBar: number | null;
  loopBars: number | null;
  confidence: number;
  candidates: Array<{
    bpm: number;
    score: number;
    barFitError: number;
    loopBarsGuess: number;
  }>;
  debug: {
    sampleRate: number;
    rawDurationSec: number;
    effectiveDurationSec: number;
    usedMethodWeights: Record<string, number>;
    notes: string[];
  };
}

export interface AnalysisSettings {
  bpmMin: number;
  bpmMax: number;
  allowedLoopBars: number[];
  analysisWindowSec: number | null;
  maxTrimLeadingSec: number;
  maxTrimTailSec: number;
  confidenceThreshold: number;
  beatsPerBar: number;
}

export const DEFAULT_ANALYSIS_SETTINGS: AnalysisSettings = {
  bpmMin: 60,
  bpmMax: 180,
  allowedLoopBars: [4, 8, 16, 32],
  analysisWindowSec: null,
  maxTrimLeadingSec: 0.5,
  maxTrimTailSec: 1.0,
  confidenceThreshold: 0.7,
  beatsPerBar: 4,
};

interface AudioSegment {
  samples: Float32Array;
  startSec: number;
  endSec: number;
  durationSec: number;
}

interface BPMCandidate {
  bpm: number;
  rawScore: number;
  onsetScore: number;
  energyScore: number;
  acfScore: number;
  harmonicScore: number;
  barFitScore: number;
  finalScore: number;
  loopBarsGuess: number;
  barFitError: number;
}

const FRAME_SIZE = 2048;
const HOP_SIZE = 512;
const SILENCE_THRESHOLD = 0.01;
const FADE_THRESHOLD = 0.3;

export function analyzeAudioLoop(
  audioBuffer: AudioBuffer,
  settings: Partial<AnalysisSettings> = {}
): LoopAnalysisResult {
  const config: AnalysisSettings = { ...DEFAULT_ANALYSIS_SETTINGS, ...settings };
  const notes: string[] = [];

  const samples = audioBuffer.getChannelData(0);
  const sampleRate = audioBuffer.sampleRate;
  const rawDuration = samples.length / sampleRate;

  notes.push(`Raw audio: ${rawDuration.toFixed(3)}s, ${sampleRate}Hz`);

  const trimmed = trimSilenceAndFade(
    samples,
    sampleRate,
    config.maxTrimLeadingSec,
    config.maxTrimTailSec
  );

  const effectiveDuration = trimmed.durationSec;
  notes.push(
    `Trimmed: ${trimmed.startSec.toFixed(3)}s - ${trimmed.endSec.toFixed(3)}s (${effectiveDuration.toFixed(3)}s effective)`
  );

  const analysisSegment =
    config.analysisWindowSec && config.analysisWindowSec < effectiveDuration
      ? extractAnalysisWindow(trimmed.samples, sampleRate, config.analysisWindowSec)
      : trimmed.samples;

  notes.push(`Analysis window: ${(analysisSegment.length / sampleRate).toFixed(3)}s`);

  const candidates = detectBPMMultiPass(
    analysisSegment,
    sampleRate,
    effectiveDuration,
    config,
    notes
  );

  if (candidates.length === 0) {
    return {
      bpm: null,
      beatsPerBar: null,
      loopBars: null,
      confidence: 0,
      candidates: [],
      debug: {
        sampleRate,
        rawDurationSec: rawDuration,
        effectiveDurationSec: effectiveDuration,
        usedMethodWeights: {},
        notes,
      },
    };
  }

  const best = candidates[0];
  const secondBest = candidates[1];

  const confidenceRatio = secondBest ? best.finalScore / secondBest.finalScore : 2.0;
  const tempoStability = calculateTempoStability(trimmed.samples, sampleRate, best.bpm, notes);
  const barFitQuality = 1.0 - Math.min(1.0, best.barFitError);

  const confidence = Math.min(
    1.0,
    confidenceRatio * 0.4 + tempoStability * 0.3 + barFitQuality * 0.3
  );

  notes.push(
    `Final confidence: ${(confidence * 100).toFixed(1)}% (ratio=${confidenceRatio.toFixed(2)}, stability=${tempoStability.toFixed(2)}, barFit=${barFitQuality.toFixed(2)})`
  );

  const methodWeights = {
    onset: 0.3,
    energy: 0.25,
    acf: 0.25,
    harmonic: 0.1,
    barFit: 0.1,
  };

  return {
    bpm: best.bpm,
    beatsPerBar: config.beatsPerBar,
    loopBars: best.loopBarsGuess,
    confidence,
    candidates: candidates.slice(0, 5).map((c) => ({
      bpm: c.bpm,
      score: c.finalScore,
      barFitError: c.barFitError,
      loopBarsGuess: c.loopBarsGuess,
    })),
    debug: {
      sampleRate,
      rawDurationSec: rawDuration,
      effectiveDurationSec: effectiveDuration,
      usedMethodWeights: methodWeights,
      notes,
    },
  };
}

function trimSilenceAndFade(
  samples: Float32Array,
  sampleRate: number,
  maxLeadingSec: number,
  maxTailSec: number
): AudioSegment {
  const maxLeadingSamples = Math.floor(maxLeadingSec * sampleRate);
  const maxTailSamples = Math.floor(maxTailSec * sampleRate);

  let startIdx = 0;
  for (let i = 0; i < Math.min(maxLeadingSamples, samples.length); i++) {
    if (Math.abs(samples[i]) > SILENCE_THRESHOLD) {
      startIdx = i;
      break;
    }
  }

  let endIdx = samples.length - 1;
  const searchStart = Math.max(0, samples.length - maxTailSamples);

  let maxInTail = 0;
  for (let i = searchStart; i < samples.length; i++) {
    maxInTail = Math.max(maxInTail, Math.abs(samples[i]));
  }

  if (maxInTail < FADE_THRESHOLD) {
    for (let i = samples.length - 1; i >= searchStart; i--) {
      if (Math.abs(samples[i]) > SILENCE_THRESHOLD) {
        endIdx = i;
        break;
      }
    }
  }

  const trimmedSamples = samples.slice(startIdx, endIdx + 1);

  return {
    samples: trimmedSamples,
    startSec: startIdx / sampleRate,
    endSec: (endIdx + 1) / sampleRate,
    durationSec: trimmedSamples.length / sampleRate,
  };
}

function extractAnalysisWindow(
  samples: Float32Array,
  sampleRate: number,
  windowSec: number
): Float32Array {
  const windowSamples = Math.floor(windowSec * sampleRate);
  if (windowSamples >= samples.length) return samples;

  const startIdx = Math.floor((samples.length - windowSamples) / 2);
  return samples.slice(startIdx, startIdx + windowSamples);
}

function detectBPMMultiPass(
  samples: Float32Array,
  sampleRate: number,
  loopDuration: number,
  config: AnalysisSettings,
  notes: string[]
): BPMCandidate[] {
  const onsetEnv = computeOnsetEnvelope(samples, sampleRate);
  const energyEnv = computeLowBandEnergy(samples, sampleRate);

  const onsetCandidates = detectBPMFromEnvelope(
    onsetEnv,
    sampleRate / HOP_SIZE,
    config.bpmMin,
    config.bpmMax
  );
  const energyCandidates = detectBPMFromEnvelope(
    energyEnv,
    sampleRate / HOP_SIZE,
    config.bpmMin,
    config.bpmMax
  );

  notes.push(`Onset candidates: ${onsetCandidates.length}, Energy candidates: ${energyCandidates.length}`);

  const allBPMs = new Set<number>();
  onsetCandidates.forEach((c) => allBPMs.add(Math.round(c.bpm * 10) / 10));
  energyCandidates.forEach((c) => allBPMs.add(Math.round(c.bpm * 10) / 10));

  const octaveVariants = new Set<number>();
  allBPMs.forEach((bpm) => {
    octaveVariants.add(bpm);
    octaveVariants.add(bpm * 2);
    octaveVariants.add(bpm / 2);
    octaveVariants.add(bpm * 1.5);
    octaveVariants.add(bpm / 1.5);
  });

  const candidates: BPMCandidate[] = [];

  octaveVariants.forEach((bpm) => {
    if (bpm < config.bpmMin || bpm > config.bpmMax) return;

    const onsetScore = scoreAgainstCandidates(bpm, onsetCandidates);
    const energyScore = scoreAgainstCandidates(bpm, energyCandidates);
    const acfScore = computeACFScore(bpm, onsetEnv, sampleRate / HOP_SIZE);
    const harmonicScore = computeHarmonicConsistency(bpm, onsetEnv, sampleRate / HOP_SIZE);

    const { loopBars, error } = findBestLoopBars(bpm, loopDuration, config);
    const barFitScore = 1.0 - Math.min(1.0, error);

    const finalScore =
      onsetScore * 0.3 +
      energyScore * 0.25 +
      acfScore * 0.25 +
      harmonicScore * 0.1 +
      barFitScore * 0.1;

    candidates.push({
      bpm,
      rawScore: (onsetScore + energyScore) / 2,
      onsetScore,
      energyScore,
      acfScore,
      harmonicScore,
      barFitScore,
      finalScore,
      loopBarsGuess: loopBars,
      barFitError: error,
    });
  });

  candidates.sort((a, b) => b.finalScore - a.finalScore);

  const grouped = groupSimilarBPMs(candidates, 2.0);

  notes.push(
    `Top 5 candidates: ${grouped
      .slice(0, 5)
      .map((c) => `${c.bpm.toFixed(1)}BPM(${(c.finalScore * 100).toFixed(0)}%)`)
      .join(', ')}`
  );

  return grouped;
}

function computeOnsetEnvelope(samples: Float32Array, _sampleRate: number): Float32Array {
  const numFrames = Math.floor((samples.length - FRAME_SIZE) / HOP_SIZE);
  const envelope = new Float32Array(numFrames);

  const prevSpectrum = new Float32Array(FRAME_SIZE / 2);
  const window = createHannWindow(FRAME_SIZE);

  for (let i = 0; i < numFrames; i++) {
    const frameStart = i * HOP_SIZE;
    const frame = samples.slice(frameStart, frameStart + FRAME_SIZE);

    const windowed = new Float32Array(FRAME_SIZE);
    for (let j = 0; j < FRAME_SIZE; j++) {
      windowed[j] = frame[j] * window[j];
    }

    const spectrum = computeMagnitudeSpectrum(windowed);

    let flux = 0;
    for (let k = 0; k < spectrum.length; k++) {
      const diff = spectrum[k] - prevSpectrum[k];
      if (diff > 0) flux += diff;
      prevSpectrum[k] = spectrum[k];
    }

    envelope[i] = flux;
  }

  return normalizeEnvelope(envelope);
}

function computeLowBandEnergy(samples: Float32Array, sampleRate: number): Float32Array {
  const numFrames = Math.floor((samples.length - FRAME_SIZE) / HOP_SIZE);
  const envelope = new Float32Array(numFrames);
  const window = createHannWindow(FRAME_SIZE);

  const lowBandMax = Math.floor((250 / sampleRate) * FRAME_SIZE);

  for (let i = 0; i < numFrames; i++) {
    const frameStart = i * HOP_SIZE;
    const frame = samples.slice(frameStart, frameStart + FRAME_SIZE);

    const windowed = new Float32Array(FRAME_SIZE);
    for (let j = 0; j < FRAME_SIZE; j++) {
      windowed[j] = frame[j] * window[j];
    }

    const spectrum = computeMagnitudeSpectrum(windowed);

    let energy = 0;
    for (let k = 0; k < Math.min(lowBandMax, spectrum.length); k++) {
      energy += spectrum[k] * spectrum[k];
    }

    envelope[i] = Math.sqrt(energy);
  }

  return normalizeEnvelope(envelope);
}

function computeMagnitudeSpectrum(frame: Float32Array): Float32Array {
  const n = frame.length;
  const real = new Float32Array(frame);
  const imag = new Float32Array(n);

  fft(real, imag);

  const magnitude = new Float32Array(n / 2);
  for (let i = 0; i < n / 2; i++) {
    magnitude[i] = Math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
  }

  return magnitude;
}

function fft(real: Float32Array, imag: Float32Array): void {
  const n = real.length;
  if (n <= 1) return;

  const halfN = n / 2;
  const evenReal = new Float32Array(halfN);
  const evenImag = new Float32Array(halfN);
  const oddReal = new Float32Array(halfN);
  const oddImag = new Float32Array(halfN);

  for (let i = 0; i < halfN; i++) {
    evenReal[i] = real[i * 2];
    evenImag[i] = imag[i * 2];
    oddReal[i] = real[i * 2 + 1];
    oddImag[i] = imag[i * 2 + 1];
  }

  fft(evenReal, evenImag);
  fft(oddReal, oddImag);

  for (let k = 0; k < halfN; k++) {
    const angle = (-2 * Math.PI * k) / n;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);

    const tReal = cos * oddReal[k] - sin * oddImag[k];
    const tImag = cos * oddImag[k] + sin * oddReal[k];

    real[k] = evenReal[k] + tReal;
    imag[k] = evenImag[k] + tImag;
    real[k + halfN] = evenReal[k] - tReal;
    imag[k + halfN] = evenImag[k] - tImag;
  }
}

function createHannWindow(size: number): Float32Array {
  const window = new Float32Array(size);
  for (let i = 0; i < size; i++) {
    window[i] = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (size - 1)));
  }
  return window;
}

function normalizeEnvelope(envelope: Float32Array): Float32Array {
  let max = 0;
  for (let i = 0; i < envelope.length; i++) {
    max = Math.max(max, envelope[i]);
  }

  if (max === 0) return envelope;

  const normalized = new Float32Array(envelope.length);
  for (let i = 0; i < envelope.length; i++) {
    normalized[i] = envelope[i] / max;
  }

  return normalized;
}

function detectBPMFromEnvelope(
  envelope: Float32Array,
  envelopeRate: number,
  minBPM: number,
  maxBPM: number
): Array<{ bpm: number; score: number }> {
  const minLag = Math.floor((60 * envelopeRate) / maxBPM);
  const maxLag = Math.floor((60 * envelopeRate) / minBPM);

  const acf = computeAutocorrelation(envelope, maxLag);
  const peaks = findPeaks(acf, minLag, maxLag);

  return peaks.map((peak) => ({
    bpm: (60 * envelopeRate) / peak.lag,
    score: peak.value,
  }));
}

function computeAutocorrelation(signal: Float32Array, maxLag: number): Float32Array {
  const acf = new Float32Array(maxLag);

  for (let lag = 0; lag < maxLag; lag++) {
    let sum = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < signal.length - lag; i++) {
      sum += signal[i] * signal[i + lag];
      normA += signal[i] * signal[i];
      normB += signal[i + lag] * signal[i + lag];
    }

    const norm = Math.sqrt(normA * normB);
    acf[lag] = norm > 0 ? sum / norm : 0;
  }

  return acf;
}

function findPeaks(
  signal: Float32Array,
  minLag: number,
  maxLag: number
): Array<{ lag: number; value: number }> {
  const peaks: Array<{ lag: number; value: number }> = [];

  let sum = 0;
  let count = 0;
  for (let i = minLag; i < maxLag; i++) {
    sum += signal[i];
    count++;
  }
  const mean = sum / count;

  let variance = 0;
  for (let i = minLag; i < maxLag; i++) {
    variance += Math.pow(signal[i] - mean, 2);
  }
  const stdDev = Math.sqrt(variance / count);

  const threshold = mean + stdDev * 0.5;

  for (let i = minLag + 2; i < maxLag - 2; i++) {
    if (
      signal[i] > threshold &&
      signal[i] > signal[i - 1] &&
      signal[i] > signal[i + 1] &&
      signal[i] > signal[i - 2] &&
      signal[i] > signal[i + 2]
    ) {
      peaks.push({ lag: i, value: signal[i] });
    }
  }

  return peaks;
}

function scoreAgainstCandidates(
  bpm: number,
  candidates: Array<{ bpm: number; score: number }>
): number {
  let bestScore = 0;

  for (const candidate of candidates) {
    const ratio = bpm / candidate.bpm;
    const octaveRatios = [1, 2, 0.5, 1.5, 0.667, 3, 0.333];

    for (const octave of octaveRatios) {
      const diff = Math.abs(ratio - octave);
      if (diff < 0.03) {
        bestScore = Math.max(bestScore, candidate.score * (1 - diff * 10));
      }
    }
  }

  return bestScore;
}

function computeACFScore(bpm: number, envelope: Float32Array, envelopeRate: number): number {
  const lag = Math.round((60 * envelopeRate) / bpm);
  const maxLag = Math.min(envelope.length - 1, Math.floor((60 * envelopeRate) / 60));

  if (lag >= maxLag) return 0;

  const acf = computeAutocorrelation(envelope, maxLag);
  return acf[lag] || 0;
}

function computeHarmonicConsistency(
  bpm: number,
  envelope: Float32Array,
  envelopeRate: number
): number {
  const baseLag = (60 * envelopeRate) / bpm;
  const maxLag = envelope.length - 1;

  const harmonics = [1, 2, 3, 4, 0.5];
  let sum = 0;
  let count = 0;

  const acf = computeAutocorrelation(envelope, maxLag);

  for (const h of harmonics) {
    const lag = Math.round(baseLag * h);
    if (lag > 0 && lag < maxLag) {
      sum += acf[lag];
      count++;
    }
  }

  return count > 0 ? sum / count : 0;
}

function findBestLoopBars(
  bpm: number,
  durationSec: number,
  config: AnalysisSettings
): { loopBars: number; error: number } {
  const beatDuration = 60 / bpm;
  const barDuration = beatDuration * config.beatsPerBar;
  const estimatedBars = durationSec / barDuration;

  let bestBars = config.allowedLoopBars[0];
  let bestError = Math.abs(estimatedBars - bestBars) / bestBars;

  for (const bars of config.allowedLoopBars) {
    const error = Math.abs(estimatedBars - bars) / bars;
    if (error < bestError) {
      bestError = error;
      bestBars = bars;
    }
  }

  return { loopBars: bestBars, error: bestError };
}

function groupSimilarBPMs(candidates: BPMCandidate[], tolerance: number): BPMCandidate[] {
  if (candidates.length === 0) return [];

  const grouped: BPMCandidate[] = [];
  const used = new Set<number>();

  for (let i = 0; i < candidates.length; i++) {
    if (used.has(i)) continue;

    const group = [candidates[i]];
    used.add(i);

    for (let j = i + 1; j < candidates.length; j++) {
      if (used.has(j)) continue;

      if (Math.abs(candidates[i].bpm - candidates[j].bpm) < tolerance) {
        group.push(candidates[j]);
        used.add(j);
      }
    }

    let bestInGroup = group[0];
    for (const c of group) {
      if (c.finalScore > bestInGroup.finalScore) {
        bestInGroup = c;
      }
    }

    grouped.push(bestInGroup);
  }

  return grouped;
}

function calculateTempoStability(
  samples: Float32Array,
  sampleRate: number,
  bpm: number,
  notes: string[]
): number {
  const segmentCount = 3;
  const segmentLength = Math.floor(samples.length / segmentCount);

  const segmentBPMs: number[] = [];

  for (let i = 0; i < segmentCount; i++) {
    const start = i * segmentLength;
    const end = Math.min(start + segmentLength, samples.length);
    const segment = samples.slice(start, end);

    const envelope = computeOnsetEnvelope(segment, sampleRate);
    const candidates = detectBPMFromEnvelope(
      envelope,
      sampleRate / HOP_SIZE,
      bpm * 0.8,
      bpm * 1.2
    );

    if (candidates.length > 0) {
      segmentBPMs.push(candidates[0].bpm);
    }
  }

  if (segmentBPMs.length < 2) return 0.5;

  const mean = segmentBPMs.reduce((a, b) => a + b, 0) / segmentBPMs.length;
  const variance =
    segmentBPMs.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / segmentBPMs.length;
  const stdDev = Math.sqrt(variance);

  const stability = Math.max(0, 1 - stdDev / mean);

  notes.push(
    `Tempo stability: segments=${segmentBPMs.map((b) => b.toFixed(1)).join(',')}, std=${stdDev.toFixed(2)}, stability=${stability.toFixed(2)}`
  );

  return stability;
}

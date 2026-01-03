export interface LoopAnalysisResult {
  bpm: number | null;
  beatsPerBar: number | null;
  loopBars: number | null;
  confidence: number;
  debug?: {
    candidateBpms: Array<{ bpm: number; score: number }>;
    estimatedBeats: number;
    estimatedBars: number;
    duration: number;
  };
}

export interface AnalysisParams {
  samples: Float32Array;
  sampleRate: number;
  minBPM?: number;
  maxBPM?: number;
  expectedBeatsPerBar?: number;
}

const DEFAULT_MIN_BPM = 70;
const DEFAULT_MAX_BPM = 160;
const FRAME_SIZE = 512;
const HOP_SIZE = 256;
const MUSICAL_BARS = [2, 4, 8, 12, 16, 24, 32];
const BAR_TOLERANCE = 0.03;

export function analyzeLoopAudio(params: AnalysisParams): LoopAnalysisResult {
  const {
    samples,
    sampleRate,
    minBPM = DEFAULT_MIN_BPM,
    maxBPM = DEFAULT_MAX_BPM,
    expectedBeatsPerBar = 4,
  } = params;

  const duration = samples.length / sampleRate;

  console.log(`🎵 Analyzing loop: ${duration.toFixed(2)}s @ ${sampleRate}Hz, ${samples.length} samples`);

  const onsetEnvelope = computeOnsetEnvelope(samples, sampleRate);
  console.log(`📊 Onset envelope: ${onsetEnvelope.length} frames`);

  const bpmCandidates = detectBPMCandidates(
    onsetEnvelope,
    sampleRate,
    minBPM,
    maxBPM
  );

  console.log(`🎯 Found ${bpmCandidates.length} BPM candidates:`, bpmCandidates.slice(0, 5));

  if (bpmCandidates.length === 0) {
    console.warn('⚠️ No BPM candidates found');
    return {
      bpm: null,
      beatsPerBar: null,
      loopBars: null,
      confidence: 0,
    };
  }

  let bestCandidate = selectBestBPM(
    bpmCandidates,
    duration,
    expectedBeatsPerBar
  );

  let { bpm, confidence } = bestCandidate;

  const correctedBPM = correctOctaveErrors(bpm, duration, expectedBeatsPerBar, bpmCandidates);
  if (correctedBPM.bpm !== bpm) {
    console.log(`🔄 Octave correction: ${bpm.toFixed(1)} → ${correctedBPM.bpm.toFixed(1)} BPM`);
    bpm = correctedBPM.bpm;
    confidence = Math.max(confidence, correctedBPM.confidence);
  }

  const beatDuration = 60 / bpm;
  const estimatedBeats = duration / beatDuration;
  const estimatedBars = estimatedBeats / expectedBeatsPerBar;

  const loopBars = calculateLoopBars(bpm, duration, expectedBeatsPerBar);

  const calibratedConfidence = calibrateConfidence(
    confidence,
    loopBars,
    estimatedBars,
    bpmCandidates
  );

  console.log(
    `✅ BPM=${bpm.toFixed(1)}, Bars=${loopBars}, Confidence=${(calibratedConfidence * 100).toFixed(0)}%`
  );

  return {
    bpm,
    beatsPerBar: expectedBeatsPerBar,
    loopBars,
    confidence: calibratedConfidence,
    debug: {
      candidateBpms: bpmCandidates.slice(0, 5),
      estimatedBeats,
      estimatedBars,
      duration,
    },
  };
}

function calibrateConfidence(
  baseConfidence: number,
  loopBars: number | null,
  estimatedBars: number,
  candidates: Array<{ bpm: number; score: number }>
): number {
  let calibrated = baseConfidence;

  if (loopBars !== null) {
    const barError = Math.abs(estimatedBars - loopBars);
    if (barError < 0.05) {
      calibrated += 0.15;
    } else if (barError < 0.15) {
      calibrated += 0.08;
    } else if (barError > 0.5) {
      calibrated -= 0.1;
    }
  }

  if (candidates.length >= 3) {
    const topThree = candidates.slice(0, 3);
    const scoreSpread = topThree[0].score - topThree[2].score;
    if (scoreSpread > 0.3) {
      calibrated += 0.1;
    } else if (scoreSpread < 0.1) {
      calibrated -= 0.05;
    }
  }

  if (baseConfidence > 0.7 && loopBars && MUSICAL_BARS.includes(loopBars)) {
    calibrated += 0.05;
  }

  return Math.max(0, Math.min(1.0, calibrated));
}

function correctOctaveErrors(
  bpm: number,
  duration: number,
  beatsPerBar: number,
  candidates: Array<{ bpm: number; score: number }>
): { bpm: number; confidence: number } {
  const beatDuration = 60 / bpm;
  const totalBars = (duration / beatDuration) / beatsPerBar;

  const octaves = [0.5, 2, 3, 4];
  let bestBPM = bpm;
  let bestScore = calculateMusicalFit(totalBars);
  let bestConfidence = candidates[0]?.score || 0;

  for (const octave of octaves) {
    const testBPM = bpm * octave;
    if (testBPM < 60 || testBPM > 180) continue;

    const testBeatDuration = 60 / testBPM;
    const testBars = (duration / testBeatDuration) / beatsPerBar;
    const testFit = calculateMusicalFit(testBars);

    const candidateSupport = candidates.find(c => Math.abs(c.bpm - testBPM) < 3);
    const supportBonus = candidateSupport ? candidateSupport.score * 0.5 : 0;

    const totalScore = testFit + supportBonus;

    if (totalScore > bestScore + 0.2) {
      bestBPM = testBPM;
      bestScore = totalScore;
      bestConfidence = Math.min(bestConfidence + 0.1, 1.0);
    }
  }

  return { bpm: bestBPM, confidence: bestConfidence };
}

function computeOnsetEnvelope(
  samples: Float32Array,
  _sampleRate: number
): Float32Array {
  const frameCount = Math.floor((samples.length - FRAME_SIZE) / HOP_SIZE);
  const envelope = new Float32Array(frameCount);

  let prevEnergy = 0;
  let prevCentroid = 0;

  for (let i = 0; i < frameCount; i++) {
    const offset = i * HOP_SIZE;
    let energy = 0;
    let spectralSum = 0;
    let spectralWeightedSum = 0;
    let zeroCrossings = 0;

    for (let j = 0; j < FRAME_SIZE; j++) {
      const sample = samples[offset + j] || 0;
      energy += sample * sample;

      const magnitude = Math.abs(sample);
      spectralSum += magnitude;
      spectralWeightedSum += magnitude * j;

      if (j > 0) {
        const prevSample = samples[offset + j - 1] || 0;
        if ((sample >= 0 && prevSample < 0) || (sample < 0 && prevSample >= 0)) {
          zeroCrossings++;
        }
      }
    }

    const rms = Math.sqrt(energy / FRAME_SIZE);
    const centroid = spectralSum > 0 ? spectralWeightedSum / spectralSum : 0;
    const zcr = zeroCrossings / FRAME_SIZE;

    const energyFlux = Math.max(0, rms - prevEnergy);
    const centroidFlux = Math.max(0, centroid - prevCentroid);

    envelope[i] = energyFlux * 0.6 + centroidFlux * 0.3 + zcr * 0.1;

    prevEnergy = rms;
    prevCentroid = centroid;
  }

  const filtered = highPassFilter(envelope);
  const enhanced = enhanceBeats(filtered);
  const normalized = normalizeSignal(enhanced);

  console.log(`📊 Envelope stats: min=${Math.min(...normalized).toFixed(3)}, max=${Math.max(...normalized).toFixed(3)}, avg=${(normalized.reduce((a,b)=>a+b,0)/normalized.length).toFixed(3)}`);

  return normalized;
}

function enhanceBeats(signal: Float32Array): Float32Array {
  const enhanced = new Float32Array(signal.length);
  const windowSize = 5;

  for (let i = 0; i < signal.length; i++) {
    let localMax = signal[i];

    for (let j = Math.max(0, i - windowSize); j < Math.min(signal.length, i + windowSize); j++) {
      localMax = Math.max(localMax, signal[j]);
    }

    if (signal[i] > localMax * 0.7) {
      enhanced[i] = signal[i] * signal[i];
    } else {
      enhanced[i] = signal[i] * 0.5;
    }
  }

  return enhanced;
}

function highPassFilter(signal: Float32Array): Float32Array {
  const filtered = new Float32Array(signal.length);
  const alpha = 0.95;

  filtered[0] = signal[0];
  for (let i = 1; i < signal.length; i++) {
    filtered[i] = alpha * (filtered[i - 1] + signal[i] - signal[i - 1]);
  }

  return filtered;
}

function normalizeSignal(signal: Float32Array): Float32Array {
  let max = 0;
  for (let i = 0; i < signal.length; i++) {
    max = Math.max(max, Math.abs(signal[i]));
  }

  if (max === 0) return signal;

  const normalized = new Float32Array(signal.length);
  for (let i = 0; i < signal.length; i++) {
    normalized[i] = signal[i] / max;
  }

  return normalized;
}

function detectBPMCandidates(
  envelope: Float32Array,
  sampleRate: number,
  minBPM: number,
  maxBPM: number
): Array<{ bpm: number; score: number }> {
  const envelopeSampleRate = sampleRate / HOP_SIZE;

  const minLag = Math.floor((60 * envelopeSampleRate) / maxBPM);
  const maxLag = Math.floor((60 * envelopeSampleRate) / minBPM);

  console.log(`🔍 BPM detection: envelope rate=${envelopeSampleRate.toFixed(2)}Hz, lag range=[${minLag}, ${maxLag}]`);

  const acf = computeAutocorrelation(envelope, maxLag);

  console.log(`📊 ACF computed: length=${acf.length}, max=${Math.max(...acf).toFixed(3)}, avg=${(acf.reduce((a,b)=>a+b,0)/acf.length).toFixed(3)}`);

  const peaks = findPeaks(acf, minLag, maxLag);

  if (peaks.length === 0) {
    console.error(`❌ No peaks found in ACF!`);
    return [];
  }

  const candidates = peaks.map((peak) => {
    const bpm = (60 * envelopeSampleRate) / peak.lag;

    const harmonicScore = computeHarmonicWeight(peak.lag, acf, envelopeSampleRate);
    const combScore = computeCombFilterScore(peak.lag, acf, minLag, maxLag);

    const combinedScore = peak.value * 0.4 + harmonicScore * 0.35 + combScore * 0.25;
    const normalizedScore = Math.min(1.0, combinedScore * 4);

    return {
      bpm,
      score: normalizedScore,
    };
  });

  candidates.sort((a, b) => b.score - a.score);

  const grouped = groupSimilarBPMs(candidates, 2);

  console.log(`🎯 Top candidates after harmonic analysis:`, grouped.slice(0, 5).map(c => `${c.bpm.toFixed(1)}BPM (${(c.score*100).toFixed(0)}%)`));

  return grouped;
}

function computeHarmonicWeight(
  lag: number,
  acf: Float32Array,
  envelopeSampleRate: number
): number {
  const harmonics = [0.5, 2, 3, 4];
  let harmonicSum = 0;
  let harmonicCount = 0;

  for (const harmonic of harmonics) {
    const harmonicLag = Math.round(lag * harmonic);
    if (harmonicLag > 0 && harmonicLag < acf.length) {
      harmonicSum += acf[harmonicLag];
      harmonicCount++;
    }
  }

  const bpm = (60 * envelopeSampleRate) / lag;
  let musicalBonus = 0;
  if (bpm >= 80 && bpm <= 140) musicalBonus = 0.15;
  else if (bpm >= 70 && bpm <= 160) musicalBonus = 0.08;

  return harmonicCount > 0 ? (harmonicSum / harmonicCount) + musicalBonus : 0;
}

function computeCombFilterScore(
  lag: number,
  acf: Float32Array,
  minLag: number,
  maxLag: number
): number {
  let combSum = 0;
  let combCount = 0;

  for (let multiple = 1; multiple <= 8; multiple++) {
    const combLag = lag * multiple;
    if (combLag >= minLag && combLag < maxLag && combLag < acf.length) {
      combSum += acf[combLag] * (1 / multiple);
      combCount++;
    }
  }

  return combCount > 0 ? combSum / combCount : 0;
}

function computeAutocorrelation(
  signal: Float32Array,
  maxLag: number
): Float32Array {
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
  const smoothed = medianFilter(signal, 3);

  const peaks: Array<{ lag: number; value: number }> = [];

  let maxValue = 0;
  let avgValue = 0;
  let stdDev = 0;
  let count = 0;

  for (let i = minLag; i < maxLag; i++) {
    maxValue = Math.max(maxValue, smoothed[i]);
    avgValue += smoothed[i];
    count++;
  }
  avgValue /= count;

  for (let i = minLag; i < maxLag; i++) {
    stdDev += Math.pow(smoothed[i] - avgValue, 2);
  }
  stdDev = Math.sqrt(stdDev / count);

  const adaptiveThreshold = Math.max(0.005, avgValue + stdDev * 0.5);

  console.log(`🔍 Finding peaks in range [${minLag}, ${maxLag}]`);
  console.log(`📊 ACF stats: max=${maxValue.toFixed(3)}, avg=${avgValue.toFixed(3)}, std=${stdDev.toFixed(3)}, threshold=${adaptiveThreshold.toFixed(3)}`);

  const windowSize = 3;
  for (let i = minLag + windowSize; i < maxLag - windowSize; i++) {
    let isLocalMax = true;
    const centerValue = smoothed[i];

    for (let j = -windowSize; j <= windowSize; j++) {
      if (j !== 0 && smoothed[i + j] >= centerValue) {
        isLocalMax = false;
        break;
      }
    }

    if (isLocalMax && centerValue > adaptiveThreshold) {
      const prominence = calculateProminence(smoothed, i, windowSize * 2);
      if (prominence > adaptiveThreshold * 0.15) {
        peaks.push({ lag: i, value: centerValue });
      }
    }
  }

  console.log(`📈 Found ${peaks.length} peaks with prominence filtering`);

  if (peaks.length === 0) {
    console.warn(`⚠️ No peaks found! Trying fallback with lower threshold...`);
    const fallbackThreshold = maxValue * 0.1;
    for (let i = minLag + 2; i < maxLag - 2; i++) {
      if (smoothed[i] > smoothed[i-1] && smoothed[i] > smoothed[i+1] && smoothed[i] > fallbackThreshold) {
        peaks.push({ lag: i, value: smoothed[i] });
      }
    }
    console.log(`📈 Fallback found ${peaks.length} peaks`);
  }

  return peaks;
}

function medianFilter(signal: Float32Array, windowSize: number): Float32Array {
  const filtered = new Float32Array(signal.length);
  const halfWindow = Math.floor(windowSize / 2);

  for (let i = 0; i < signal.length; i++) {
    const window: number[] = [];
    for (let j = Math.max(0, i - halfWindow); j <= Math.min(signal.length - 1, i + halfWindow); j++) {
      window.push(signal[j]);
    }
    window.sort((a, b) => a - b);
    filtered[i] = window[Math.floor(window.length / 2)];
  }

  return filtered;
}

function calculateProminence(signal: Float32Array, peakIndex: number, searchRadius: number): number {
  const peakValue = signal[peakIndex];
  let minLeft = peakValue;
  let minRight = peakValue;

  for (let i = Math.max(0, peakIndex - searchRadius); i < peakIndex; i++) {
    minLeft = Math.min(minLeft, signal[i]);
  }

  for (let i = peakIndex + 1; i < Math.min(signal.length, peakIndex + searchRadius); i++) {
    minRight = Math.min(minRight, signal[i]);
  }

  const minBase = Math.max(minLeft, minRight);
  return peakValue - minBase;
}

function groupSimilarBPMs(
  candidates: Array<{ bpm: number; score: number }>,
  tolerance: number
): Array<{ bpm: number; score: number }> {
  const grouped: Array<{ bpm: number; score: number }> = [];

  for (const candidate of candidates) {
    const existing = grouped.find(
      (g) => Math.abs(g.bpm - candidate.bpm) < tolerance
    );

    if (existing) {
      if (candidate.score > existing.score) {
        existing.bpm = candidate.bpm;
        existing.score = candidate.score;
      }
    } else {
      grouped.push({ ...candidate });
    }
  }

  grouped.sort((a, b) => b.score - a.score);
  return grouped;
}

function selectBestBPM(
  candidates: Array<{ bpm: number; score: number }>,
  duration: number,
  beatsPerBar: number
): { bpm: number; confidence: number } {
  let bestCandidate = candidates[0];
  let bestFitScore = -Infinity;

  for (const candidate of candidates) {
    const { bpm, score } = candidate;

    const beatDuration = 60 / bpm;
    const totalBeats = duration / beatDuration;
    const totalBars = totalBeats / beatsPerBar;

    const musicalFit = calculateMusicalFit(totalBars);

    const tempoStability = calculateTempoStability(bpm, candidates);

    const integerBarBonus = Math.abs(totalBars - Math.round(totalBars)) < 0.02 ? 0.15 : 0;

    const combinedScore =
      score * 0.45 +
      musicalFit * 0.30 +
      tempoStability * 0.15 +
      integerBarBonus * 0.10;

    if (combinedScore > bestFitScore) {
      bestFitScore = combinedScore;
      bestCandidate = candidate;
    }
  }

  const baseConfidence = bestCandidate.score;
  const beatDuration = 60 / bestCandidate.bpm;
  const totalBars = (duration / beatDuration) / beatsPerBar;
  const barFit = calculateMusicalFit(totalBars);

  const confidenceBoost = barFit > 0.8 ? 0.15 : barFit > 0.5 ? 0.08 : 0;
  const confidence = Math.min(baseConfidence + confidenceBoost, 1.0);

  return { bpm: bestCandidate.bpm, confidence };
}

function calculateTempoStability(bpm: number, candidates: Array<{ bpm: number; score: number }>): number {
  let stabilityScore = 0;
  let count = 0;

  for (const candidate of candidates.slice(0, 5)) {
    const ratio = candidate.bpm / bpm;

    if (Math.abs(ratio - 1) < 0.02 ||
        Math.abs(ratio - 2) < 0.05 ||
        Math.abs(ratio - 0.5) < 0.05 ||
        Math.abs(ratio - 3) < 0.08) {
      stabilityScore += candidate.score;
      count++;
    }
  }

  return count > 0 ? stabilityScore / count : 0;
}

function calculateMusicalFit(bars: number): number {
  const roundedBars = Math.round(bars);

  if (MUSICAL_BARS.includes(roundedBars)) {
    const error = Math.abs(bars - roundedBars);
    if (error < 0.05) return 1.0;
    if (error < 0.15) return 0.9;
    if (error < 0.3) return 0.75;
  }

  let bestFit = 0;
  for (const targetBars of MUSICAL_BARS) {
    const error = Math.abs(bars - targetBars) / targetBars;

    if (error < 0.02) {
      bestFit = Math.max(bestFit, 1.0);
    } else if (error < 0.05) {
      bestFit = Math.max(bestFit, 0.85);
    } else if (error < 0.1) {
      bestFit = Math.max(bestFit, 0.65);
    } else if (error < BAR_TOLERANCE) {
      bestFit = Math.max(bestFit, 0.4);
    }
  }

  if (bestFit === 0 && bars > 1 && bars < 64) {
    const fractionalPart = bars - Math.floor(bars);
    if (fractionalPart < 0.1 || fractionalPart > 0.9) {
      bestFit = 0.2;
    }
  }

  return bestFit;
}

function calculateLoopBars(
  bpm: number,
  duration: number,
  beatsPerBar: number
): number | null {
  const beatDuration = 60 / bpm;
  const totalBeats = duration / beatDuration;
  const totalBars = totalBeats / beatsPerBar;

  for (const targetBars of MUSICAL_BARS) {
    const error = Math.abs(totalBars - targetBars) / targetBars;
    if (error < BAR_TOLERANCE) {
      return targetBars;
    }
  }

  return Math.round(totalBars);
}

export function mixToMono(buffer: AudioBuffer): Float32Array {
  const numChannels = buffer.numberOfChannels;
  const length = buffer.length;
  const mono = new Float32Array(length);

  if (numChannels === 1) {
    return buffer.getChannelData(0);
  }

  for (let channel = 0; channel < numChannels; channel++) {
    const channelData = buffer.getChannelData(channel);
    for (let i = 0; i < length; i++) {
      mono[i] += channelData[i];
    }
  }

  for (let i = 0; i < length; i++) {
    mono[i] /= numChannels;
  }

  return mono;
}

export async function analyzeAudioBufferLoop(
  audioBuffer: AudioBuffer
): Promise<LoopAnalysisResult> {
  const channelData =
    audioBuffer.numberOfChannels > 1
      ? mixToMono(audioBuffer)
      : audioBuffer.getChannelData(0);

  return analyzeLoopAudio({
    samples: channelData,
    sampleRate: audioBuffer.sampleRate,
  });
}

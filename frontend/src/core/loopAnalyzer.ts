export interface LoopAnalysisResult {
  bpm: number | null;
  beatsPerBar: number | null;
  loopBars: number | null;
  confidence: number;
  candidates?: Array<{ bpm: number; score: number }>;
}

export interface LoopAnalyzerParams {
  samples: Float32Array;
  sampleRate: number;
  minBPM?: number;
  maxBPM?: number;
  expectedBeatsPerBar?: number;
}

export class LoopAnalyzer {
  private static readonly DEFAULT_MIN_BPM = 70;
  private static readonly DEFAULT_MAX_BPM = 160;
  private static readonly FRAME_SIZE = 512;
  private static readonly HOP_SIZE = 256;
  private static readonly MUSICAL_BARS = [4, 8, 16, 32, 2, 12, 24];
  private static readonly BAR_TOLERANCE = 0.025;

  static analyzeLoopAudio(params: LoopAnalyzerParams): LoopAnalysisResult {
    const {
      samples,
      sampleRate,
      minBPM = this.DEFAULT_MIN_BPM,
      maxBPM = this.DEFAULT_MAX_BPM,
      expectedBeatsPerBar = 4,
    } = params;

    const duration = samples.length / sampleRate;

    console.log(`🎵 Analyzing loop: ${duration.toFixed(2)}s, ${sampleRate}Hz`);

    const onsetEnvelope = this.computeOnsetEnvelope(samples, sampleRate);

    const bpmCandidates = this.detectBPMCandidates(
      onsetEnvelope,
      sampleRate,
      minBPM,
      maxBPM
    );

    if (bpmCandidates.length === 0) {
      console.warn('⚠️ No BPM candidates found');
      return {
        bpm: null,
        beatsPerBar: null,
        loopBars: null,
        confidence: 0,
      };
    }

    const bestCandidate = this.selectBestBPM(
      bpmCandidates,
      duration,
      expectedBeatsPerBar
    );

    const { bpm, confidence } = bestCandidate;

    const loopBars = this.calculateLoopBars(bpm, duration, expectedBeatsPerBar);

    console.log(
      `✅ Analysis complete: BPM=${bpm.toFixed(1)}, Bars=${loopBars}, Confidence=${confidence.toFixed(2)}`
    );

    return {
      bpm,
      beatsPerBar: expectedBeatsPerBar,
      loopBars,
      confidence,
      candidates: bpmCandidates.slice(0, 5),
    };
  }

  private static computeOnsetEnvelope(
    samples: Float32Array,
    _sampleRate: number
  ): Float32Array {
    const frameCount = Math.floor(
      (samples.length - this.FRAME_SIZE) / this.HOP_SIZE
    );
    const envelope = new Float32Array(frameCount);

    for (let i = 0; i < frameCount; i++) {
      const offset = i * this.HOP_SIZE;
      let energy = 0;

      for (let j = 0; j < this.FRAME_SIZE; j++) {
        const sample = samples[offset + j] || 0;
        energy += sample * sample;
      }

      envelope[i] = Math.sqrt(energy / this.FRAME_SIZE);
    }

    const filtered = this.highPassFilter(envelope);

    return this.normalizeEnvelope(filtered);
  }

  private static highPassFilter(signal: Float32Array): Float32Array {
    const filtered = new Float32Array(signal.length);
    const alpha = 0.95;

    filtered[0] = signal[0];
    for (let i = 1; i < signal.length; i++) {
      filtered[i] = alpha * (filtered[i - 1] + signal[i] - signal[i - 1]);
    }

    return filtered;
  }

  private static normalizeEnvelope(signal: Float32Array): Float32Array {
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

  private static detectBPMCandidates(
    envelope: Float32Array,
    sampleRate: number,
    minBPM: number,
    maxBPM: number
  ): Array<{ bpm: number; score: number }> {
    const envelopeSampleRate = sampleRate / this.HOP_SIZE;

    const minLag = Math.floor((60 * envelopeSampleRate) / maxBPM);
    const maxLag = Math.floor((60 * envelopeSampleRate) / minBPM);

    const acf = this.autocorrelation(envelope, maxLag);

    const peaks = this.findPeaks(acf, minLag, maxLag);

    const candidates = peaks.map((peak) => ({
      bpm: (60 * envelopeSampleRate) / peak.lag,
      score: peak.value,
    }));

    candidates.sort((a, b) => b.score - a.score);

    const grouped = this.groupSimilarBPMs(candidates, 2);

    return grouped.slice(0, 10);
  }

  private static autocorrelation(
    signal: Float32Array,
    maxLag: number
  ): Float32Array {
    const acf = new Float32Array(maxLag);

    for (let lag = 0; lag < maxLag; lag++) {
      let sum = 0;
      let count = 0;

      for (let i = 0; i < signal.length - lag; i++) {
        sum += signal[i] * signal[i + lag];
        count++;
      }

      acf[lag] = count > 0 ? sum / count : 0;
    }

    return this.normalizeEnvelope(acf);
  }

  private static findPeaks(
    signal: Float32Array,
    minLag: number,
    maxLag: number
  ): Array<{ lag: number; value: number }> {
    const peaks: Array<{ lag: number; value: number }> = [];
    const threshold = 0.3;

    for (let i = minLag + 1; i < maxLag - 1; i++) {
      if (
        signal[i] > signal[i - 1] &&
        signal[i] > signal[i + 1] &&
        signal[i] > threshold
      ) {
        peaks.push({ lag: i, value: signal[i] });
      }
    }

    return peaks;
  }

  private static groupSimilarBPMs(
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

    return grouped;
  }

  private static selectBestBPM(
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

      const musicalFit = this.calculateMusicalFit(totalBars);

      const combinedScore = score * 0.6 + musicalFit * 0.4;

      if (combinedScore > bestFitScore) {
        bestFitScore = combinedScore;
        bestCandidate = candidate;
      }
    }

    const confidence = Math.min(bestCandidate.score, 1.0);

    return { bpm: bestCandidate.bpm, confidence };
  }

  private static calculateMusicalFit(bars: number): number {
    let bestFit = 0;

    for (const targetBars of this.MUSICAL_BARS) {
      const error = Math.abs(bars - targetBars) / targetBars;
      const fit = Math.max(0, 1 - error / this.BAR_TOLERANCE);
      bestFit = Math.max(bestFit, fit);
    }

    return bestFit;
  }

  private static calculateLoopBars(
    bpm: number,
    duration: number,
    beatsPerBar: number
  ): number | null {
    const beatDuration = 60 / bpm;
    const totalBeats = duration / beatDuration;
    const totalBars = totalBeats / beatsPerBar;

    for (const targetBars of this.MUSICAL_BARS) {
      const error = Math.abs(totalBars - targetBars) / targetBars;
      if (error < this.BAR_TOLERANCE) {
        return targetBars;
      }
    }

    return Math.round(totalBars);
  }

  static formatAnalysisResult(result: LoopAnalysisResult): string {
    if (!result.bpm) {
      return '❌ Analysis failed';
    }

    return (
      `📊 Loop Analysis:\n` +
      `  BPM: ${result.bpm.toFixed(1)}\n` +
      `  Beats per bar: ${result.beatsPerBar}\n` +
      `  Loop bars: ${result.loopBars}\n` +
      `  Confidence: ${(result.confidence * 100).toFixed(0)}%\n` +
      (result.candidates
        ? `  Top candidates: ${result.candidates
            .slice(0, 3)
            .map((c) => `${c.bpm.toFixed(1)} (${c.score.toFixed(2)})`)
            .join(', ')}`
        : '')
    );
  }
}

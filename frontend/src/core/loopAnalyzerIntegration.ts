import { analyzeAudioLoop, type AnalysisSettings, type LoopAnalysisResult } from './advancedLoopAnalyzer';
import { AudioContextManager } from './AudioContextManager';

export interface AudioLoopMetadata {
  bpm: number;
  beatsPerBar: number;
  loopBars: number;
  confidence: number;
  analysisMethod: 'auto' | 'manual' | 'library';
  candidates?: Array<{
    bpm: number;
    score: number;
    barFitError: number;
    loopBarsGuess: number;
  }>;
}

export class LoopAnalyzerIntegration {
  private static defaultSettings: AnalysisSettings = {
    bpmMin: 60,
    bpmMax: 180,
    allowedLoopBars: [4, 8, 16, 32],
    analysisWindowSec: null,
    maxTrimLeadingSec: 0.5,
    maxTrimTailSec: 1.0,
    confidenceThreshold: 0.7,
    beatsPerBar: 4,
  };

  static async analyzeLoop(
    audioBuffer: AudioBuffer,
    settings?: Partial<AnalysisSettings>
  ): Promise<AudioLoopMetadata> {
    const config = { ...this.defaultSettings, ...settings };

    console.log(`🎵 Analyzing loop: ${audioBuffer.duration.toFixed(2)}s @ ${audioBuffer.sampleRate}Hz`);

    const result = analyzeAudioLoop(audioBuffer, config);

    console.log(`✅ Analysis complete: ${result.bpm?.toFixed(1)} BPM, ${result.loopBars} bars, ${(result.confidence * 100).toFixed(0)}% confidence`);

    if (result.confidence < config.confidenceThreshold) {
      console.warn(`⚠️ Low confidence (${(result.confidence * 100).toFixed(0)}%). Consider manual verification.`);
      console.log('Top candidates:');
      result.candidates.slice(0, 3).forEach((c, i) => {
        console.log(`  ${i + 1}. ${c.bpm.toFixed(1)} BPM → ${c.loopBarsGuess} bars (score: ${(c.score * 100).toFixed(0)}%)`);
      });
    }

    return {
      bpm: result.bpm || 120,
      beatsPerBar: result.beatsPerBar || 4,
      loopBars: result.loopBars || 4,
      confidence: result.confidence,
      analysisMethod: result.confidence >= config.confidenceThreshold ? 'auto' : 'manual',
      candidates: result.candidates,
    };
  }

  static async analyzeLoopFromFile(
    file: File,
    settings?: Partial<AnalysisSettings>
  ): Promise<AudioLoopMetadata> {
    const arrayBuffer = await file.arrayBuffer();
    const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);
    return this.analyzeLoop(audioBuffer, settings);
  }

  static async analyzeLoopFromURL(
    url: string,
    settings?: Partial<AnalysisSettings>
  ): Promise<AudioLoopMetadata> {
    const response = await fetch(url);
    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);
    return this.analyzeLoop(audioBuffer, settings);
  }

  static async analyzeWithFallback(
    audioBuffer: AudioBuffer,
    settings?: Partial<AnalysisSettings>
  ): Promise<AudioLoopMetadata> {
    try {
      const result = await this.analyzeLoop(audioBuffer, settings);

      if (result.confidence < 0.3) {
        console.warn('⚠️ Very low confidence, falling back to duration-based estimation');
        return this.estimateFromDuration(audioBuffer.duration, settings?.beatsPerBar || 4);
      }

      return result;
    } catch (error) {
      console.error('❌ Analysis failed:', error);
      console.log('Falling back to duration-based estimation');
      return this.estimateFromDuration(audioBuffer.duration, settings?.beatsPerBar || 4);
    }
  }

  private static estimateFromDuration(
    durationSec: number,
    beatsPerBar: number
  ): AudioLoopMetadata {
    const commonBPMs = [90, 100, 110, 120, 128, 130, 140];
    const allowedBars = [4, 8, 16, 32];

    let bestBPM = 120;
    let bestBars = 4;
    let bestError = Infinity;

    for (const bpm of commonBPMs) {
      const beatDuration = 60 / bpm;
      const barDuration = beatDuration * beatsPerBar;
      const estimatedBars = durationSec / barDuration;

      for (const bars of allowedBars) {
        const error = Math.abs(estimatedBars - bars) / bars;
        if (error < bestError) {
          bestError = error;
          bestBPM = bpm;
          bestBars = bars;
        }
      }
    }

    console.log(`📊 Duration-based estimate: ${bestBPM} BPM, ${bestBars} bars (error: ${(bestError * 100).toFixed(1)}%)`);

    return {
      bpm: bestBPM,
      beatsPerBar,
      loopBars: bestBars,
      confidence: Math.max(0, 1 - bestError),
      analysisMethod: 'manual',
    };
  }

  static async batchAnalyze(
    files: File[],
    settings?: Partial<AnalysisSettings>,
    onProgress?: (current: number, total: number, filename: string) => void
  ): Promise<Map<string, AudioLoopMetadata>> {
    const results = new Map<string, AudioLoopMetadata>();

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      onProgress?.(i + 1, files.length, file.name);

      try {
        const metadata = await this.analyzeLoopFromFile(file, settings);
        results.set(file.name, metadata);
      } catch (error) {
        console.error(`Failed to analyze ${file.name}:`, error);
      }
    }

    return results;
  }

  static exportAnalysisReport(
    filename: string,
    metadata: AudioLoopMetadata,
    result: LoopAnalysisResult
  ): string {
    const report = {
      filename,
      timestamp: new Date().toISOString(),
      analysis: {
        bpm: metadata.bpm,
        beatsPerBar: metadata.beatsPerBar,
        loopBars: metadata.loopBars,
        confidence: metadata.confidence,
        method: metadata.analysisMethod,
      },
      candidates: metadata.candidates,
      debug: result.debug,
    };

    return JSON.stringify(report, null, 2);
  }

  static getRecommendedSettings(genre: string): Partial<AnalysisSettings> {
    const presets: Record<string, Partial<AnalysisSettings>> = {
      techno: {
        bpmMin: 120,
        bpmMax: 140,
        allowedLoopBars: [4, 8, 16, 32],
        confidenceThreshold: 0.75,
      },
      house: {
        bpmMin: 120,
        bpmMax: 130,
        allowedLoopBars: [4, 8, 16],
        confidenceThreshold: 0.75,
      },
      'hip-hop': {
        bpmMin: 80,
        bpmMax: 110,
        allowedLoopBars: [4, 8, 16],
        confidenceThreshold: 0.65,
      },
      dnb: {
        bpmMin: 160,
        bpmMax: 180,
        allowedLoopBars: [4, 8, 16],
        confidenceThreshold: 0.7,
      },
      dubstep: {
        bpmMin: 130,
        bpmMax: 150,
        allowedLoopBars: [4, 8, 16],
        confidenceThreshold: 0.7,
      },
      ambient: {
        bpmMin: 60,
        bpmMax: 100,
        allowedLoopBars: [4, 8, 16, 32, 64],
        confidenceThreshold: 0.5,
        analysisWindowSec: 10,
      },
      trance: {
        bpmMin: 130,
        bpmMax: 145,
        allowedLoopBars: [8, 16, 32],
        confidenceThreshold: 0.75,
      },
    };

    return presets[genre.toLowerCase()] || {};
  }
}

export async function quickAnalyze(audioBuffer: AudioBuffer): Promise<AudioLoopMetadata> {
  return LoopAnalyzerIntegration.analyzeLoop(audioBuffer);
}

export async function analyzeWithGenre(
  audioBuffer: AudioBuffer,
  genre: string
): Promise<AudioLoopMetadata> {
  const settings = LoopAnalyzerIntegration.getRecommendedSettings(genre);
  return LoopAnalyzerIntegration.analyzeLoop(audioBuffer, settings);
}

export async function analyzeWithUserConfirmation(
  audioBuffer: AudioBuffer,
  onLowConfidence: (candidates: AudioLoopMetadata['candidates']) => Promise<number>
): Promise<AudioLoopMetadata> {
  const result = await LoopAnalyzerIntegration.analyzeLoop(audioBuffer);

  if (result.confidence < 0.7 && result.candidates) {
    const selectedBPM = await onLowConfidence(result.candidates);
    const selectedCandidate = result.candidates.find((c) => c.bpm === selectedBPM);

    if (selectedCandidate) {
      return {
        bpm: selectedCandidate.bpm,
        beatsPerBar: result.beatsPerBar,
        loopBars: selectedCandidate.loopBarsGuess,
        confidence: result.confidence,
        analysisMethod: 'manual',
        candidates: result.candidates,
      };
    }
  }

  return result;
}

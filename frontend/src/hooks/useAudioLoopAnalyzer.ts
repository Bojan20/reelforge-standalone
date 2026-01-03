import { useState, useCallback } from 'react';
import { analyzeAudioLoop, DEFAULT_ANALYSIS_SETTINGS, type AnalysisSettings } from '../core/advancedLoopAnalyzer';
import { AudioContextManager } from '../core/AudioContextManager';

export interface AudioLoopMetadata {
  fileName: string;
  duration: number;
  bpm: number | null;
  beatsPerBar: number | null;
  loopBars: number | null;
  confidence: number;
  audioBuffer: AudioBuffer;
  candidates?: Array<{
    bpm: number;
    score: number;
    barFitError: number;
    loopBarsGuess: number;
  }>;
  debug?: {
    sampleRate: number;
    rawDurationSec: number;
    effectiveDurationSec: number;
    usedMethodWeights: Record<string, number>;
    notes: string[];
  };
}

export function useAudioLoopAnalyzer(settings?: Partial<AnalysisSettings>) {
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<AudioLoopMetadata | null>(null);
  const [needsUserConfirmation, setNeedsUserConfirmation] = useState(false);

  const analyzeFile = useCallback(async (file: File): Promise<AudioLoopMetadata | null> => {
    setIsAnalyzing(true);
    setError(null);
    setResult(null);
    setNeedsUserConfirmation(false);

    try {
      console.log(`📂 Loading file: ${file.name}`);

      const arrayBuffer = await file.arrayBuffer();

      // Use singleton AudioContext for decoding
      const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);

      console.log(`🎵 Decoded: ${audioBuffer.duration.toFixed(2)}s, ${audioBuffer.sampleRate}Hz`);

      const config = { ...DEFAULT_ANALYSIS_SETTINGS, ...settings };
      const analysis = analyzeAudioLoop(audioBuffer, config);

      const metadata: AudioLoopMetadata = {
        fileName: file.name,
        duration: audioBuffer.duration,
        bpm: analysis.bpm,
        beatsPerBar: analysis.beatsPerBar,
        loopBars: analysis.loopBars,
        confidence: analysis.confidence,
        audioBuffer,
        candidates: analysis.candidates,
        debug: analysis.debug,
      };

      console.log('✅ Analysis complete:', {
        bpm: metadata.bpm?.toFixed(1),
        beatsPerBar: metadata.beatsPerBar,
        loopBars: metadata.loopBars,
        confidence: `${(metadata.confidence * 100).toFixed(0)}%`,
      });

      if (analysis.confidence < config.confidenceThreshold) {
        console.warn(`⚠️ Low confidence (${(analysis.confidence * 100).toFixed(0)}%). User confirmation recommended.`);
        setNeedsUserConfirmation(true);
      }

      if (analysis.debug?.notes) {
        console.log('📝 Analysis notes:');
        analysis.debug.notes.forEach(note => console.log(`  • ${note}`));
      }

      setResult(metadata);
      return metadata;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      console.error('❌ Analysis failed:', errorMessage);
      setError(errorMessage);
      return null;
    } finally {
      setIsAnalyzing(false);
    }
  }, [settings]);

  const updateMetadataWithCandidate = useCallback((candidateIndex: number) => {
    if (!result || !result.candidates) return null;

    const candidate = result.candidates[candidateIndex];
    if (!candidate) return null;

    const updatedMetadata: AudioLoopMetadata = {
      ...result,
      bpm: candidate.bpm,
      loopBars: candidate.loopBarsGuess,
    };

    setResult(updatedMetadata);
    setNeedsUserConfirmation(false);

    console.log(`✅ Updated with candidate: ${candidate.bpm.toFixed(1)} BPM, ${candidate.loopBarsGuess} bars`);

    return updatedMetadata;
  }, [result]);

  return {
    analyzeFile,
    isAnalyzing,
    error,
    result,
    needsUserConfirmation,
    updateMetadataWithCandidate,
  };
}

import { LoopAnalyzer } from '../core/loopAnalyzer';
import { AudioContextManager } from '../core/AudioContextManager';

export interface SoundSpriteMetadata {
  start: number;
  duration: number;
  bpm?: number;
  beatsPerBar?: number;
  loopBars?: number;
  confidence?: number;
}

export class ReelForgeLoopIntegration {
  static async analyzeUploadedLoop(
    audioFile: File,
    audioContext: AudioContext
  ): Promise<SoundSpriteMetadata | null> {
    try {
      console.log(`📂 Analyzing uploaded file: ${audioFile.name}`);

      const arrayBuffer = await audioFile.arrayBuffer();

      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      const samples = audioBuffer.getChannelData(0);
      const sampleRate = audioBuffer.sampleRate;
      const duration = audioBuffer.duration;

      const analysis = LoopAnalyzer.analyzeLoopAudio({
        samples,
        sampleRate,
        minBPM: 70,
        maxBPM: 160,
        expectedBeatsPerBar: 4,
      });

      if (!analysis.bpm || !analysis.loopBars) {
        console.warn('⚠️ Could not analyze loop, using defaults');
        return {
          start: 0,
          duration: Math.round(duration * 1000),
        };
      }

      const metadata: SoundSpriteMetadata = {
        start: 0,
        duration: Math.round(duration * 1000),
        bpm: Math.round(analysis.bpm),
        beatsPerBar: analysis.beatsPerBar || 4,
        loopBars: analysis.loopBars,
        confidence: analysis.confidence,
      };

      console.log('✅ Loop analysis complete:');
      console.log(`   BPM: ${metadata.bpm}`);
      console.log(`   Beats per bar: ${metadata.beatsPerBar}`);
      console.log(`   Loop bars: ${metadata.loopBars}`);
      console.log(`   Confidence: ${(metadata.confidence! * 100).toFixed(0)}%`);

      return metadata;
    } catch (error) {
      console.error('❌ Failed to analyze loop:', error);
      return null;
    }
  }

  static generateSoundSpriteJSON(
    spriteName: string,
    metadata: SoundSpriteMetadata
  ): string {
    const sprite = {
      soundSprites: {
        [spriteName]: metadata,
      },
    };

    return JSON.stringify(sprite, null, 2);
  }

  static async processMultipleLoops(
    files: File[],
    audioContext: AudioContext
  ): Promise<Record<string, SoundSpriteMetadata>> {
    const results: Record<string, SoundSpriteMetadata> = {};

    for (const file of files) {
      const spriteName = file.name.replace(/\.(wav|mp3|ogg)$/i, '');
      const metadata = await this.analyzeUploadedLoop(file, audioContext);

      if (metadata) {
        results[spriteName] = metadata;
      }
    }

    return results;
  }

  static validateLoopMetadata(metadata: SoundSpriteMetadata): {
    valid: boolean;
    warnings: string[];
  } {
    const warnings: string[] = [];

    if (metadata.bpm && (metadata.bpm < 70 || metadata.bpm > 160)) {
      warnings.push(
        `BPM ${metadata.bpm} is outside typical range (70-160). This might be incorrect.`
      );
    }

    if (
      metadata.loopBars &&
      ![2, 4, 8, 12, 16, 24, 32].includes(metadata.loopBars)
    ) {
      warnings.push(
        `Loop bars ${metadata.loopBars} is unusual. Common values are 4, 8, 16.`
      );
    }

    if (metadata.confidence && metadata.confidence < 0.5) {
      warnings.push(
        `Low confidence (${(metadata.confidence * 100).toFixed(0)}%). Manual verification recommended.`
      );
    }

    const valid = warnings.length === 0 || (metadata.confidence || 0) > 0.7;

    return { valid, warnings };
  }

  static async analyzeWithFallback(
    audioFile: File,
    audioContext: AudioContext,
    manualBPM?: number
  ): Promise<SoundSpriteMetadata> {
    const autoAnalysis = await this.analyzeUploadedLoop(audioFile, audioContext);

    if (autoAnalysis && autoAnalysis.confidence! > 0.7) {
      return autoAnalysis;
    }

    if (manualBPM) {
      console.log(`⚠️ Using manual BPM: ${manualBPM}`);

      const arrayBuffer = await audioFile.arrayBuffer();
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
      const duration = audioBuffer.duration;

      const beatsPerBar = 4;
      const beatDuration = 60 / manualBPM;
      const totalBeats = duration / beatDuration;
      const totalBars = totalBeats / beatsPerBar;

      const loopBars = this.roundToMusicalBars(totalBars);

      return {
        start: 0,
        duration: Math.round(duration * 1000),
        bpm: manualBPM,
        beatsPerBar,
        loopBars,
        confidence: 0.5,
      };
    }

    return (
      autoAnalysis || {
        start: 0,
        duration: 0,
      }
    );
  }

  private static roundToMusicalBars(bars: number): number {
    const musicalBars = [2, 4, 8, 12, 16, 24, 32];
    const tolerance = 0.025;

    for (const target of musicalBars) {
      if (Math.abs(bars - target) / target < tolerance) {
        return target;
      }
    }

    return Math.round(bars);
  }
}

export async function exampleUsage() {
  // Use shared AudioContext singleton
  const audioContext = AudioContextManager.getContext();

  const fileInput = document.createElement('input');
  fileInput.type = 'file';
  fileInput.accept = 'audio/*';

  fileInput.onchange = async (e) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    const metadata = await ReelForgeLoopIntegration.analyzeUploadedLoop(
      file,
      audioContext
    );

    if (metadata) {
      const json = ReelForgeLoopIntegration.generateSoundSpriteJSON(
        's_BonusMusicLoop1',
        metadata
      );

      console.log('Generated JSON:');
      console.log(json);

      const validation = ReelForgeLoopIntegration.validateLoopMetadata(metadata);

      if (!validation.valid) {
        console.warn('⚠️ Validation warnings:');
        validation.warnings.forEach((w) => console.warn(`  - ${w}`));
      }
    }
  };
}

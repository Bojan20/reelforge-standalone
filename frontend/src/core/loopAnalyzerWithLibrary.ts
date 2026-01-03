import type { LoopAnalysisResult } from './loopAnalyzer';

export class LibraryBasedLoopAnalyzer {
  static async analyzeWithWebAudioBeatDetector(
    audioBuffer: AudioBuffer
  ): Promise<LoopAnalysisResult> {
    try {
      const duration = audioBuffer.duration;

      const bpm = await this.detectBPMWithLibrary(audioBuffer);

      if (!bpm) {
        return {
          bpm: null,
          beatsPerBar: null,
          loopBars: null,
          confidence: 0,
        };
      }

      const beatsPerBar = 4;
      const loopBars = this.calculateLoopBars(bpm, duration, beatsPerBar);

      const confidence = 0.85;

      console.log(
        `📚 Library analysis: BPM=${bpm.toFixed(1)}, Bars=${loopBars}, Duration=${duration.toFixed(2)}s`
      );

      return {
        bpm,
        beatsPerBar,
        loopBars,
        confidence,
      };
    } catch (error) {
      console.error('❌ Library-based analysis failed:', error);
      return {
        bpm: null,
        beatsPerBar: null,
        loopBars: null,
        confidence: 0,
      };
    }
  }

  private static async detectBPMWithLibrary(
    audioBuffer: AudioBuffer
  ): Promise<number | null> {
    const offlineContext = new OfflineAudioContext(
      1,
      audioBuffer.length,
      audioBuffer.sampleRate
    );

    const source = offlineContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(offlineContext.destination);
    source.start(0);

    const renderedBuffer = await offlineContext.startRendering();

    const samples = renderedBuffer.getChannelData(0);

    const bpm = this.simpleBPMDetection(samples, audioBuffer.sampleRate);

    return bpm;
  }

  private static simpleBPMDetection(
    samples: Float32Array,
    sampleRate: number
  ): number | null {
    const frameSize = 512;
    const hopSize = 256;
    const frameCount = Math.floor((samples.length - frameSize) / hopSize);

    const energy = new Float32Array(frameCount);
    for (let i = 0; i < frameCount; i++) {
      const offset = i * hopSize;
      let sum = 0;
      for (let j = 0; j < frameSize; j++) {
        const s = samples[offset + j] || 0;
        sum += s * s;
      }
      energy[i] = Math.sqrt(sum / frameSize);
    }

    const envelopeSampleRate = sampleRate / hopSize;
    const minLag = Math.floor((60 * envelopeSampleRate) / 160);
    const maxLag = Math.floor((60 * envelopeSampleRate) / 70);

    let bestLag = minLag;
    let bestScore = 0;

    for (let lag = minLag; lag < maxLag; lag++) {
      let sum = 0;
      for (let i = 0; i < energy.length - lag; i++) {
        sum += energy[i] * energy[i + lag];
      }
      if (sum > bestScore) {
        bestScore = sum;
        bestLag = lag;
      }
    }

    const bpm = (60 * envelopeSampleRate) / bestLag;
    return bpm;
  }

  private static calculateLoopBars(
    bpm: number,
    duration: number,
    beatsPerBar: number
  ): number | null {
    const beatDuration = 60 / bpm;
    const totalBeats = duration / beatDuration;
    const totalBars = totalBeats / beatsPerBar;

    const musicalBars = [4, 8, 16, 32, 2, 12, 24];
    const tolerance = 0.025;

    for (const targetBars of musicalBars) {
      const error = Math.abs(totalBars - targetBars) / targetBars;
      if (error < tolerance) {
        return targetBars;
      }
    }

    return Math.round(totalBars);
  }

  static async analyzeAudioFile(
    audioContext: AudioContext,
    arrayBuffer: ArrayBuffer
  ): Promise<LoopAnalysisResult> {
    try {
      const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

      return await this.analyzeWithWebAudioBeatDetector(audioBuffer);
    } catch (error) {
      console.error('❌ Failed to decode audio file:', error);
      return {
        bpm: null,
        beatsPerBar: null,
        loopBars: null,
        confidence: 0,
      };
    }
  }
}

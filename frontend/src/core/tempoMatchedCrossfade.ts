export interface TempoMatchParams {
  currentTime: number;
  bpmA: number;
  bpmB: number;
  phaseA: number;
  phaseB: number;
  windowDuration: number;
  minRateScale?: number;
  maxRateScale?: number;
  maxBeatOffset?: number;
}

export interface CrossfadeSchedule {
  rateScaleForB: number;
  crossfadeStartTime: number;
  crossfadeEndTime: number;
  selectedBeatOffset: number;
  targetBPM: number;
  phaseAlignmentError: number;
  recoveryDuration: number;
}

export class TempoMatchedCrossfade {
  private static readonly DEFAULT_MIN_RATE = 0.85;
  private static readonly DEFAULT_MAX_RATE = 1.15;
  private static readonly DEFAULT_MAX_BEAT_OFFSET = 2;
  private static readonly RECOVERY_DURATION = 2.0;

  static scheduleTempoMatchedCrossfade(params: TempoMatchParams): CrossfadeSchedule {
    const {
      currentTime,
      bpmA,
      bpmB,
      phaseA,
      phaseB,
      windowDuration: T,
      minRateScale = this.DEFAULT_MIN_RATE,
      maxRateScale = this.DEFAULT_MAX_RATE,
      maxBeatOffset = this.DEFAULT_MAX_BEAT_OFFSET,
    } = params;

    const freqA = bpmA / 60;

    const phaseAEnd = (phaseA + freqA * T) % 1.0;

    let bestK = 0;
    let bestBPM = bpmB;
    let bestRateScale = 1.0;
    let bestError = Infinity;

    for (let k = -maxBeatOffset; k <= maxBeatOffset; k++) {
      const phaseDelta = (phaseA - phaseB) + freqA * T + k;
      const targetFreq = phaseDelta / T;
      const targetBPM = targetFreq * 60;
      const rateScale = targetBPM / bpmB;

      if (rateScale < minRateScale || rateScale > maxRateScale) {
        continue;
      }

      const error = Math.abs(targetBPM - bpmB);

      if (error < bestError) {
        bestError = error;
        bestK = k;
        bestBPM = targetBPM;
        bestRateScale = rateScale;
      }
    }

    if (bestRateScale < minRateScale || bestRateScale > maxRateScale) {
      console.warn(
        `⚠️ Tempo matching failed: no valid k found. Falling back to rateScale=1.0. ` +
        `BPM_A=${bpmA}, BPM_B=${bpmB}, T=${T}s`
      );
      bestRateScale = 1.0;
      bestBPM = bpmB;
      bestK = 0;
    }

    const phaseBEnd = (phaseB + (bestBPM / 60) * T) % 1.0;
    const phaseAlignmentError = Math.abs(phaseBEnd - phaseAEnd);

    console.log(
      `🎵 Tempo-matched crossfade scheduled:\n` +
      `  BPM_A=${bpmA.toFixed(1)}, BPM_B=${bpmB.toFixed(1)}\n` +
      `  Phase_A=${phaseA.toFixed(3)} → ${phaseAEnd.toFixed(3)}\n` +
      `  Phase_B=${phaseB.toFixed(3)} → ${phaseBEnd.toFixed(3)}\n` +
      `  Beat offset k=${bestK}\n` +
      `  Target BPM_B'=${bestBPM.toFixed(2)} (rateScale=${bestRateScale.toFixed(4)})\n` +
      `  Phase alignment error=${phaseAlignmentError.toFixed(4)}\n` +
      `  Window duration=${T}s, Recovery=${this.RECOVERY_DURATION}s`
    );

    return {
      rateScaleForB: bestRateScale,
      crossfadeStartTime: currentTime,
      crossfadeEndTime: currentTime + T,
      selectedBeatOffset: bestK,
      targetBPM: bestBPM,
      phaseAlignmentError,
      recoveryDuration: this.RECOVERY_DURATION,
    };
  }

  static applyTempoMatchedCrossfade(
    schedule: CrossfadeSchedule,
    audioContext: AudioContext,
    sourceB: AudioBufferSourceNode,
    gainA: GainNode,
    gainB: GainNode,
    initialVolumeA: number = 1.0,
    initialVolumeB: number = 0.0
  ): void {
    const { rateScaleForB, crossfadeStartTime, crossfadeEndTime, recoveryDuration } = schedule;
    const now = audioContext.currentTime;
    const T = crossfadeEndTime - crossfadeStartTime;

    sourceB.playbackRate.setValueAtTime(rateScaleForB, now);

    gainA.gain.setValueAtTime(initialVolumeA, crossfadeStartTime);
    gainA.gain.linearRampToValueAtTime(0.0, crossfadeEndTime);

    gainB.gain.setValueAtTime(initialVolumeB, crossfadeStartTime);
    gainB.gain.linearRampToValueAtTime(1.0, crossfadeEndTime);

    const recoveryEndTime = crossfadeEndTime + recoveryDuration;
    sourceB.playbackRate.setValueAtTime(rateScaleForB, crossfadeEndTime);
    sourceB.playbackRate.linearRampToValueAtTime(1.0, recoveryEndTime);

    console.log(
      `🎚️ Applied tempo-matched crossfade:\n` +
      `  Crossfade: ${crossfadeStartTime.toFixed(2)}s → ${crossfadeEndTime.toFixed(2)}s (${T.toFixed(2)}s)\n` +
      `  Recovery: ${crossfadeEndTime.toFixed(2)}s → ${recoveryEndTime.toFixed(2)}s (${recoveryDuration.toFixed(2)}s)\n` +
      `  playbackRate: ${rateScaleForB.toFixed(4)} → 1.0`
    );
  }

  static calculateBeatPhase(
    currentPlaybackTime: number,
    loopDuration: number,
    bpm: number
  ): number {
    const beatDuration = 60 / bpm;
    const positionInLoop = currentPlaybackTime % loopDuration;
    const beatPosition = positionInLoop / beatDuration;
    return beatPosition % 1.0;
  }

  static estimatePhaseFromAudioContext(
    startTime: number,
    currentTime: number,
    loopDuration: number,
    bpm: number,
    playbackRate: number = 1.0
  ): number {
    const elapsed = (currentTime - startTime) * playbackRate;
    return this.calculateBeatPhase(elapsed, loopDuration, bpm);
  }
}

export function createTempoMatchedCrossfadeExample() {
  console.log("=== TEMPO-MATCHED CROSSFADE EXAMPLE ===\n");

  const params: TempoMatchParams = {
    currentTime: 0,
    bpmA: 120,
    bpmB: 128,
    phaseA: 0.2,
    phaseB: 0.7,
    windowDuration: 1.5,
  };

  const schedule = TempoMatchedCrossfade.scheduleTempoMatchedCrossfade(params);

  console.log("\n=== VERIFICATION ===");
  const freqA = params.bpmA / 60;
  const freqB_prime = schedule.targetBPM / 60;
  const phaseAEnd = (params.phaseA + freqA * params.windowDuration) % 1.0;
  const phaseBEnd = (params.phaseB + freqB_prime * params.windowDuration) % 1.0;

  console.log(`Phase A at end: ${phaseAEnd.toFixed(4)}`);
  console.log(`Phase B at end: ${phaseBEnd.toFixed(4)}`);
  console.log(`Difference: ${Math.abs(phaseAEnd - phaseBEnd).toFixed(4)}`);
  console.log(`Rate scale: ${schedule.rateScaleForB.toFixed(4)}`);
  console.log(`Tempo deviation: ${Math.abs(schedule.targetBPM - params.bpmB).toFixed(2)} BPM`);
}

import { TempoMatchedCrossfade, type TempoMatchParams, type CrossfadeSchedule } from './tempoMatchedCrossfade';

export interface MusicLoop {
  id: string;
  buffer: AudioBuffer;
  bpm: number;
  source?: AudioBufferSourceNode;
  gainNode?: GainNode;
  startTime?: number;
  isPlaying: boolean;
}

export class AdvancedMusicCrossfadeManager {
  private audioContext: AudioContext;
  private masterGain: GainNode;
  private activeLoops: Map<string, MusicLoop> = new Map();
  private pendingCrossfade: CrossfadeSchedule | null = null;

  constructor(audioContext: AudioContext, masterGain: GainNode) {
    this.audioContext = audioContext;
    this.masterGain = masterGain;
  }

  startLoop(loop: MusicLoop, volume: number = 1.0): void {
    if (loop.isPlaying) {
      console.warn(`Loop ${loop.id} is already playing`);
      return;
    }

    const source = this.audioContext.createBufferSource();
    source.buffer = loop.buffer;
    source.loop = true;

    const gainNode = this.audioContext.createGain();
    gainNode.gain.value = volume;

    source.connect(gainNode);
    gainNode.connect(this.masterGain);

    const startTime = this.audioContext.currentTime;
    source.start(0);

    loop.source = source;
    loop.gainNode = gainNode;
    loop.startTime = startTime;
    loop.isPlaying = true;

    this.activeLoops.set(loop.id, loop);

    console.log(`▶️ Started loop ${loop.id} at ${startTime.toFixed(2)}s (BPM=${loop.bpm})`);
  }

  stopLoop(loopId: string, fadeOutDuration: number = 0.5): void {
    const loop = this.activeLoops.get(loopId);
    if (!loop || !loop.isPlaying) return;

    const now = this.audioContext.currentTime;

    if (loop.gainNode) {
      loop.gainNode.gain.setValueAtTime(loop.gainNode.gain.value, now);
      loop.gainNode.gain.linearRampToValueAtTime(0, now + fadeOutDuration);
    }

    setTimeout(() => {
      if (loop.source) {
        try {
          loop.source.stop();
        } catch (e) {
          console.warn(`Failed to stop loop ${loopId}:`, e);
        }
      }
      loop.isPlaying = false;
      this.activeLoops.delete(loopId);
      console.log(`⏹️ Stopped loop ${loopId}`);
    }, fadeOutDuration * 1000);
  }

  tempoMatchedCrossfade(
    fromLoopId: string,
    toLoop: MusicLoop,
    windowDuration: number = 1.5
  ): void {
    const fromLoop = this.activeLoops.get(fromLoopId);
    if (!fromLoop || !fromLoop.isPlaying) {
      console.error(`Source loop ${fromLoopId} is not playing`);
      return;
    }

    if (this.pendingCrossfade) {
      console.warn('⚠️ Crossfade already in progress, cancelling previous');
    }

    const now = this.audioContext.currentTime;

    const phaseA = TempoMatchedCrossfade.estimatePhaseFromAudioContext(
      fromLoop.startTime!,
      now,
      fromLoop.buffer.duration,
      fromLoop.bpm,
      fromLoop.source!.playbackRate.value
    );

    const phaseB = 0.0;

    const params: TempoMatchParams = {
      currentTime: now,
      bpmA: fromLoop.bpm,
      bpmB: toLoop.bpm,
      phaseA,
      phaseB,
      windowDuration,
    };

    const schedule = TempoMatchedCrossfade.scheduleTempoMatchedCrossfade(params);
    this.pendingCrossfade = schedule;

    const sourceB = this.audioContext.createBufferSource();
    sourceB.buffer = toLoop.buffer;
    sourceB.loop = true;

    const gainB = this.audioContext.createGain();
    gainB.gain.value = 0;

    sourceB.connect(gainB);
    gainB.connect(this.masterGain);

    sourceB.start(0);

    toLoop.source = sourceB;
    toLoop.gainNode = gainB;
    toLoop.startTime = now;
    toLoop.isPlaying = true;

    this.activeLoops.set(toLoop.id, toLoop);

    TempoMatchedCrossfade.applyTempoMatchedCrossfade(
      schedule,
      this.audioContext,
      sourceB,
      fromLoop.gainNode!,
      gainB,
      fromLoop.gainNode!.gain.value,
      0
    );

    setTimeout(() => {
      this.stopLoop(fromLoopId, 0);
      this.pendingCrossfade = null;
    }, (schedule.crossfadeEndTime - now + schedule.recoveryDuration) * 1000);
  }

  getAllActiveLoops(): MusicLoop[] {
    return Array.from(this.activeLoops.values()).filter(loop => loop.isPlaying);
  }

  stopAll(fadeOutDuration: number = 1.0): void {
    this.activeLoops.forEach((loop) => {
      if (loop.isPlaying) {
        this.stopLoop(loop.id, fadeOutDuration);
      }
    });
  }
}

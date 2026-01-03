import type { FadeCommand } from './types';

interface FadeState {
  currentVolume: number;
  targetVolume: number;
  startVolume: number;
  startTime: number;
  duration: number;
  rafId: number | null;  // Changed from intervalId to rafId for RAF-based animation
  isActive: boolean;
}

interface SpriteVolumeState {
  currentVolume: number;
  activeFade: FadeState | null;
}

export class LayeredMusicSystem {
  private spriteStates: Map<string, SpriteVolumeState> = new Map();
  private readonly DEFAULT_FADE_DURATION = 300;
  private readonly MIN_VOLUME = 0;
  private readonly MAX_VOLUME = 1;

  constructor() {
    this.spriteStates = new Map();
  }

  private clampVolume(volume: number): number {
    return Math.max(this.MIN_VOLUME, Math.min(this.MAX_VOLUME, volume));
  }

  private getSpriteState(spriteId: string): SpriteVolumeState {
    if (!this.spriteStates.has(spriteId)) {
      this.spriteStates.set(spriteId, {
        currentVolume: 0,
        activeFade: null,
      });
    }
    return this.spriteStates.get(spriteId)!;
  }

  private cancelActiveFade(spriteState: SpriteVolumeState): void {
    if (spriteState.activeFade && spriteState.activeFade.rafId !== null) {
      cancelAnimationFrame(spriteState.activeFade.rafId);
      spriteState.activeFade.rafId = null;
      spriteState.activeFade.isActive = false;
    }
  }

  private selectFadeDuration(
    cmd: FadeCommand,
    currentVolume: number
  ): number {
    const targetVolume = this.clampVolume(cmd.targetVolume);
    const volumeDelta = targetVolume - currentVolume;

    if (Math.abs(volumeDelta) < 0.001) {
      return 0;
    }

    if (volumeDelta > 0) {
      return cmd.durationUp ?? cmd.duration ?? this.DEFAULT_FADE_DURATION;
    } else {
      return cmd.durationDown ?? cmd.duration ?? this.DEFAULT_FADE_DURATION;
    }
  }

  public executeFade(
    cmd: FadeCommand,
    gainNode: GainNode | null,
    audioElement: HTMLAudioElement | null,
    onComplete?: () => void
  ): void {
    const spriteId = cmd.soundId;
    const spriteState = this.getSpriteState(spriteId);
    const targetVolume = this.clampVolume(cmd.targetVolume);

    this.cancelActiveFade(spriteState);

    const currentVolume = spriteState.currentVolume;
    const duration = this.selectFadeDuration(cmd, currentVolume);

    if (duration === 0 || Math.abs(targetVolume - currentVolume) < 0.001) {
      spriteState.currentVolume = targetVolume;
      if (gainNode) {
        gainNode.gain.value = targetVolume;
      }
      if (audioElement) {
        audioElement.volume = targetVolume;
      }
      if (onComplete) {
        onComplete();
      }
      return;
    }

    const startTime = performance.now();
    const startVolume = currentVolume;
    const volumeDelta = targetVolume - startVolume;

    const fadeState: FadeState = {
      currentVolume: startVolume,
      targetVolume: targetVolume,
      startVolume: startVolume,
      startTime: startTime,
      duration: duration,
      rafId: null,
      isActive: true,
    };

    spriteState.activeFade = fadeState;

    // Use RAF for smooth animation instead of setInterval
    const fadeWithRAF = () => {
      if (!fadeState.isActive) {
        return;
      }

      const elapsed = performance.now() - startTime;
      const progress = Math.min(elapsed / duration, 1.0);

      const newVolume = this.clampVolume(startVolume + volumeDelta * progress);

      spriteState.currentVolume = newVolume;

      if (gainNode) {
        gainNode.gain.value = newVolume;
      }
      if (audioElement) {
        audioElement.volume = newVolume;
      }

      if (progress >= 1.0) {
        fadeState.rafId = null;
        fadeState.isActive = false;

        spriteState.currentVolume = targetVolume;
        if (gainNode) {
          gainNode.gain.value = targetVolume;
        }
        if (audioElement) {
          audioElement.volume = targetVolume;
        }

        if (onComplete) {
          onComplete();
        }
      } else {
        fadeState.rafId = requestAnimationFrame(fadeWithRAF);
      }
    };

    fadeState.rafId = requestAnimationFrame(fadeWithRAF);
  }

  public getCurrentVolume(spriteId: string): number {
    const spriteState = this.getSpriteState(spriteId);
    return spriteState.currentVolume;
  }

  public setCurrentVolume(spriteId: string, volume: number): void {
    const spriteState = this.getSpriteState(spriteId);
    spriteState.currentVolume = this.clampVolume(volume);
  }

  public cancelFade(spriteId: string): void {
    const spriteState = this.getSpriteState(spriteId);
    this.cancelActiveFade(spriteState);
  }

  public reset(): void {
    this.spriteStates.forEach((state) => {
      this.cancelActiveFade(state);
    });
    this.spriteStates.clear();
  }

  public isSpriteFading(spriteId: string): boolean {
    const spriteState = this.getSpriteState(spriteId);
    return spriteState.activeFade !== null && spriteState.activeFade.isActive;
  }
}

export const layeredMusicSystem = new LayeredMusicSystem();

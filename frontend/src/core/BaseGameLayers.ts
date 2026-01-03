export type BaseGameLayerId = 0 | 1 | 2 | 3;

export type BaseGameStateId = 0 | 1 | 2 | 3;

export interface BaseGameAudioSystem {
  ensureLoopingLayer: (spriteId: string, initialVolume: number) => void;
  fadeLayerToVolume: (spriteId: string, targetVolume: number, fadeMs: number) => void;
}

export const BASE_GAME_LAYER_SPRITES: Record<BaseGameLayerId, string> = {
  0: 'bgmLayer0',
  1: 'bgmLayer1',
  2: 'bgmLayer2',
  3: 'bgmLayer3',
};

export const BASE_GAME_LAYER_STATE_MATRIX: Record<
  BaseGameStateId,
  Record<BaseGameLayerId, number>
> = {
  0: {
    0: 0.8,
    1: 0.0,
    2: 0.0,
    3: 0.0,
  },

  1: {
    0: 0.8,
    1: 0.6,
    2: 0.0,
    3: 0.0,
  },

  2: {
    0: 0.8,
    1: 0.7,
    2: 0.7,
    3: 0.0,
  },

  3: {
    0: 0.9,
    1: 0.8,
    2: 0.8,
    3: 0.9,
  },
};

export interface SetBaseGameStateOptions {
  fadeMs?: number;
  ensureLoopOnFirstCall?: boolean;
}

let _baseGameInitialized = false;

export function setBaseGameMusicState(
  audio: BaseGameAudioSystem,
  stateId: BaseGameStateId,
  options: SetBaseGameStateOptions = {}
) {
  const fadeMs = options.fadeMs ?? 600;
  const ensureLoop = options.ensureLoopOnFirstCall ?? true;

  const stateConfig = BASE_GAME_LAYER_STATE_MATRIX[stateId];
  if (!stateConfig) return;

  (Object.keys(BASE_GAME_LAYER_SPRITES) as unknown as BaseGameLayerId[]).forEach(
    (layerId) => {
      const spriteId = BASE_GAME_LAYER_SPRITES[layerId];
      const targetVolume = stateConfig[layerId] ?? 0.0;

      if (!_baseGameInitialized && ensureLoop) {
        audio.ensureLoopingLayer(spriteId, targetVolume);
      }

      audio.fadeLayerToVolume(spriteId, targetVolume, fadeMs);
    }
  );

  _baseGameInitialized = true;
}

export function stopBaseGameMusic(
  audio: BaseGameAudioSystem,
  fadeMs: number = 800
) {
  (Object.keys(BASE_GAME_LAYER_SPRITES) as unknown as BaseGameLayerId[]).forEach(
    (layerId) => {
      const spriteId = BASE_GAME_LAYER_SPRITES[layerId];
      audio.fadeLayerToVolume(spriteId, 0.0, fadeMs);
    }
  );

  _baseGameInitialized = false;
}

/**
 * ReelForge Sound Variations
 *
 * Wwise-inspired variation system for natural-sounding audio.
 * Prevents repetitive "machine gun" effect by varying sounds.
 *
 * Features:
 * - Random container (pick 1 of N)
 * - Sequence container (A→B→C)
 * - Pitch randomization (±semitones)
 * - Volume randomization (±dB)
 * - No-repeat logic (avoid same sound twice)
 *
 * Use cases:
 * - Coin sounds: 5 variations, random pick, ±5% pitch
 * - Reel stops: 3 variations per reel
 * - Button clicks: slight pitch variance for liveliness
 */

export type VariationMode = 'random' | 'sequence' | 'shuffle';

export interface SoundVariation {
  /** Asset ID */
  assetId: string;
  /** Weight for random selection (default 1.0) */
  weight?: number;
  /** Volume offset in dB */
  volumeOffsetDb?: number;
  /** Pitch offset in semitones */
  pitchOffsetSemitones?: number;
}

export interface VariationContainer {
  id: string;
  name: string;
  /** How to select next variation */
  mode: VariationMode;
  /** Sound variations in this container */
  variations: SoundVariation[];
  /** Pitch randomization range in semitones [min, max] */
  pitchRandomRange?: [number, number];
  /** Volume randomization range in dB [min, max] */
  volumeRandomRange?: [number, number];
  /** Avoid repeating same sound N times (0 = allow repeats) */
  avoidRepeatCount?: number;
}

export interface VariationPlayResult {
  assetId: string;
  /** Final pitch multiplier (1.0 = normal) */
  pitchMultiplier: number;
  /** Final volume multiplier (1.0 = normal) */
  volumeMultiplier: number;
  /** Index of selected variation */
  variationIndex: number;
}

interface ContainerState {
  /** Last played indices (for no-repeat) */
  history: number[];
  /** Current sequence index */
  sequenceIndex: number;
  /** Shuffled order for shuffle mode */
  shuffleOrder: number[];
}

// Seeded random for deterministic results (casino compliance)
class SeededRandom {
  private seed: number;

  constructor(seed?: number) {
    this.seed = seed ?? Date.now();
  }

  /** Get next random number 0-1 */
  next(): number {
    // XorShift32
    let x = this.seed;
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    this.seed = x >>> 0;
    return (x >>> 0) / 0xFFFFFFFF;
  }

  /** Get random int in range [min, max] inclusive */
  nextInt(min: number, max: number): number {
    return Math.floor(this.next() * (max - min + 1)) + min;
  }

  /** Get random float in range [min, max] */
  nextFloat(min: number, max: number): number {
    return this.next() * (max - min) + min;
  }

  /** Shuffle array in place */
  shuffle<T>(array: T[]): T[] {
    for (let i = array.length - 1; i > 0; i--) {
      const j = this.nextInt(0, i);
      [array[i], array[j]] = [array[j], array[i]];
    }
    return array;
  }

  /** Set seed for reproducibility */
  setSeed(seed: number): void {
    this.seed = seed;
  }
}

export class SoundVariationManager {
  private containers: Map<string, VariationContainer> = new Map();
  private states: Map<string, ContainerState> = new Map();
  private random: SeededRandom;

  constructor(seed?: number) {
    this.random = new SeededRandom(seed);
  }

  /**
   * Register a variation container
   */
  registerContainer(container: VariationContainer): void {
    this.containers.set(container.id, container);
    this.states.set(container.id, {
      history: [],
      sequenceIndex: 0,
      shuffleOrder: [],
    });
  }

  /**
   * Remove a container
   */
  removeContainer(id: string): boolean {
    this.states.delete(id);
    return this.containers.delete(id);
  }

  /**
   * Get next variation to play
   */
  getNextVariation(containerId: string): VariationPlayResult | null {
    const container = this.containers.get(containerId);
    if (!container || container.variations.length === 0) {
      return null;
    }

    const state = this.states.get(containerId)!;
    let selectedIndex: number;

    switch (container.mode) {
      case 'random':
        selectedIndex = this.selectRandom(container, state);
        break;
      case 'sequence':
        selectedIndex = this.selectSequence(container, state);
        break;
      case 'shuffle':
        selectedIndex = this.selectShuffle(container, state);
        break;
      default:
        selectedIndex = 0;
    }

    const variation = container.variations[selectedIndex];

    // Calculate pitch multiplier
    let pitchMultiplier = 1.0;

    // Apply variation-specific offset
    if (variation.pitchOffsetSemitones) {
      pitchMultiplier *= this.semitonesToMultiplier(variation.pitchOffsetSemitones);
    }

    // Apply random range
    if (container.pitchRandomRange) {
      const [minSemi, maxSemi] = container.pitchRandomRange;
      const randomSemi = this.random.nextFloat(minSemi, maxSemi);
      pitchMultiplier *= this.semitonesToMultiplier(randomSemi);
    }

    // Calculate volume multiplier
    let volumeMultiplier = 1.0;

    // Apply variation-specific offset
    if (variation.volumeOffsetDb) {
      volumeMultiplier *= this.dbToMultiplier(variation.volumeOffsetDb);
    }

    // Apply random range
    if (container.volumeRandomRange) {
      const [minDb, maxDb] = container.volumeRandomRange;
      const randomDb = this.random.nextFloat(minDb, maxDb);
      volumeMultiplier *= this.dbToMultiplier(randomDb);
    }

    // Update history - use splice for consistency with O(1) removal
    state.history.push(selectedIndex);
    const maxHistory = container.avoidRepeatCount ?? 2;
    if (state.history.length > maxHistory) {
      state.history.splice(0, state.history.length - maxHistory);
    }

    return {
      assetId: variation.assetId,
      pitchMultiplier,
      volumeMultiplier,
      variationIndex: selectedIndex,
    };
  }

  /**
   * Select random variation with weights and no-repeat
   */
  private selectRandom(container: VariationContainer, state: ContainerState): number {
    const { variations, avoidRepeatCount = 2 } = container;

    // Build weighted pool excluding recent history
    const candidates: { index: number; weight: number }[] = [];

    for (let i = 0; i < variations.length; i++) {
      // Skip if in recent history (unless we have no choice)
      const inHistory = state.history.slice(-avoidRepeatCount).includes(i);
      if (inHistory && variations.length > avoidRepeatCount) {
        continue;
      }
      candidates.push({
        index: i,
        weight: variations[i].weight ?? 1.0,
      });
    }

    // If all filtered out, allow any
    if (candidates.length === 0) {
      return this.random.nextInt(0, variations.length - 1);
    }

    // Weighted random selection
    const totalWeight = candidates.reduce((sum, c) => sum + c.weight, 0);
    let roll = this.random.next() * totalWeight;

    for (const candidate of candidates) {
      roll -= candidate.weight;
      if (roll <= 0) {
        return candidate.index;
      }
    }

    return candidates[candidates.length - 1].index;
  }

  /**
   * Select next in sequence
   */
  private selectSequence(container: VariationContainer, state: ContainerState): number {
    const index = state.sequenceIndex;
    state.sequenceIndex = (state.sequenceIndex + 1) % container.variations.length;
    return index;
  }

  /**
   * Select from shuffled order (re-shuffle when exhausted)
   */
  private selectShuffle(container: VariationContainer, state: ContainerState): number {
    // Initialize or reshuffle when exhausted
    if (state.shuffleOrder.length === 0) {
      state.shuffleOrder = Array.from({ length: container.variations.length }, (_, i) => i);
      this.random.shuffle(state.shuffleOrder);
    }

    return state.shuffleOrder.shift()!;
  }

  /**
   * Convert semitones to pitch multiplier
   */
  private semitonesToMultiplier(semitones: number): number {
    return Math.pow(2, semitones / 12);
  }

  /**
   * Convert dB to volume multiplier
   */
  private dbToMultiplier(db: number): number {
    return Math.pow(10, db / 20);
  }

  /**
   * Reset container state
   */
  resetContainer(containerId: string): void {
    const state = this.states.get(containerId);
    if (state) {
      state.history = [];
      state.sequenceIndex = 0;
      state.shuffleOrder = [];
    }
  }

  /**
   * Reset all containers
   */
  resetAll(): void {
    this.states.forEach((_, id) => this.resetContainer(id));
  }

  /**
   * Set random seed for reproducibility
   */
  setSeed(seed: number): void {
    this.random.setSeed(seed);
  }

  /**
   * Get all containers
   */
  getContainers(): VariationContainer[] {
    return Array.from(this.containers.values());
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.containers.clear();
    this.states.clear();
  }
}

// Default variation containers for common slot sounds
export const DEFAULT_VARIATION_CONTAINERS: VariationContainer[] = [
  {
    id: 'coin_land',
    name: 'Coin Land Variations',
    mode: 'random',
    variations: [
      { assetId: 'coin_land_1' },
      { assetId: 'coin_land_2' },
      { assetId: 'coin_land_3' },
      { assetId: 'coin_land_4' },
      { assetId: 'coin_land_5' },
    ],
    pitchRandomRange: [-1, 1],  // ±1 semitone
    volumeRandomRange: [-2, 1], // -2 to +1 dB
    avoidRepeatCount: 2,
  },
  {
    id: 'reel_stop',
    name: 'Reel Stop Variations',
    mode: 'sequence',
    variations: [
      { assetId: 'reel_stop_1', pitchOffsetSemitones: 0 },
      { assetId: 'reel_stop_2', pitchOffsetSemitones: 0.5 },
      { assetId: 'reel_stop_3', pitchOffsetSemitones: 1 },
      { assetId: 'reel_stop_4', pitchOffsetSemitones: 1.5 },
      { assetId: 'reel_stop_5', pitchOffsetSemitones: 2 },
    ],
    volumeRandomRange: [-1, 0],
  },
  {
    id: 'button_click',
    name: 'Button Click Variations',
    mode: 'random',
    variations: [
      { assetId: 'btn_click' },
    ],
    pitchRandomRange: [-0.5, 0.5],  // Subtle variance
    volumeRandomRange: [-1, 0],
    avoidRepeatCount: 0,  // Allow repeats (only 1 variation)
  },
];

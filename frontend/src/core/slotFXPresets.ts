/**
 * Slot FX Presets Library
 *
 * Comprehensive preset library for slot game audio:
 * - Win celebration effects
 * - Spin/reel sounds
 * - Bonus round effects
 * - Jackpot sounds
 * - UI feedback
 * - Ambient/music processing
 *
 * Each preset includes:
 * - EQ settings
 * - Compression settings
 * - Reverb/delay settings
 * - Sidechain settings
 * - Category and tags for search
 */

// ============ TYPES ============

export type PresetCategory =
  | 'wins'
  | 'spins'
  | 'bonus'
  | 'jackpot'
  | 'ui'
  | 'music'
  | 'ambience'
  | 'voice'
  | 'master';

export type PresetTag =
  | 'punch'
  | 'bright'
  | 'warm'
  | 'subtle'
  | 'aggressive'
  | 'clean'
  | 'vintage'
  | 'modern'
  | 'big'
  | 'tight'
  | 'wide'
  | 'narrow'
  | 'fast'
  | 'slow';

export interface EQBand {
  type: 'lowshelf' | 'highshelf' | 'peak' | 'lowpass' | 'highpass';
  frequency: number;
  gain: number;
  q: number;
  enabled: boolean;
}

export interface EQPreset {
  bands: EQBand[];
  outputGain: number;
}

export interface CompressorPreset {
  threshold: number;
  ratio: number;
  attack: number;
  release: number;
  knee: number;
  makeupGain: number;
}

export interface ReverbPreset {
  type: 'room' | 'hall' | 'plate' | 'spring' | 'chamber';
  decay: number;
  predelay: number;
  damping: number;
  diffusion: number;
  mix: number;
  lowCut: number;
  highCut: number;
}

export interface DelayPreset {
  time: number;
  feedback: number;
  mix: number;
  sync: boolean;
  pingPong: boolean;
  lowCut: number;
  highCut: number;
}

export interface SidechainPreset {
  enabled: boolean;
  threshold: number;
  ratio: number;
  attack: number;
  release: number;
  range: number;
}

export interface FXChainPreset {
  id: string;
  name: string;
  description: string;
  category: PresetCategory;
  tags: PresetTag[];
  author: string;
  version: string;

  // Effect settings
  eq?: EQPreset;
  compressor?: CompressorPreset;
  reverb?: ReverbPreset;
  delay?: DelayPreset;
  sidechain?: SidechainPreset;

  // Additional processing
  stereoWidth?: number;
  lowCut?: number;
  highCut?: number;
  saturate?: number;
  outputGain?: number;
}

// ============ PRESET LIBRARY ============

export const SLOT_FX_PRESETS: FXChainPreset[] = [
  // ============ WINS ============
  {
    id: 'win_small_punch',
    name: 'Small Win - Punch',
    description: 'Punchy, satisfying small win sound with presence boost',
    category: 'wins',
    tags: ['punch', 'bright', 'tight'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 80, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 2500, gain: 3, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 2, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -18,
      ratio: 4,
      attack: 5,
      release: 100,
      knee: 6,
      makeupGain: 3,
    },
    reverb: {
      type: 'room',
      decay: 0.3,
      predelay: 5,
      damping: 0.6,
      diffusion: 0.7,
      mix: 0.15,
      lowCut: 200,
      highCut: 8000,
    },
    outputGain: 0,
  },

  {
    id: 'win_medium_celebration',
    name: 'Medium Win - Celebration',
    description: 'Exciting medium win with wide stereo and sparkle',
    category: 'wins',
    tags: ['bright', 'wide', 'big'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 60, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 150, gain: 2, q: 0.707, enabled: true },
        { type: 'peak', frequency: 3000, gain: 2.5, q: 1.2, enabled: true },
        { type: 'highshelf', frequency: 10000, gain: 3, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -16,
      ratio: 3,
      attack: 10,
      release: 150,
      knee: 8,
      makeupGain: 2,
    },
    reverb: {
      type: 'plate',
      decay: 0.8,
      predelay: 15,
      damping: 0.4,
      diffusion: 0.8,
      mix: 0.25,
      lowCut: 150,
      highCut: 10000,
    },
    stereoWidth: 1.3,
    outputGain: 1,
  },

  {
    id: 'win_big_epic',
    name: 'Big Win - Epic',
    description: 'Massive, theatrical big win with full spectrum impact',
    category: 'wins',
    tags: ['big', 'aggressive', 'wide'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 40, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 100, gain: 4, q: 0.707, enabled: true },
        { type: 'peak', frequency: 400, gain: -2, q: 1, enabled: true },
        { type: 'peak', frequency: 2500, gain: 3, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 12000, gain: 4, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -14,
      ratio: 6,
      attack: 3,
      release: 200,
      knee: 4,
      makeupGain: 4,
    },
    reverb: {
      type: 'hall',
      decay: 1.5,
      predelay: 25,
      damping: 0.3,
      diffusion: 0.9,
      mix: 0.3,
      lowCut: 100,
      highCut: 12000,
    },
    delay: {
      time: 125,
      feedback: 0.2,
      mix: 0.1,
      sync: false,
      pingPong: true,
      lowCut: 300,
      highCut: 6000,
    },
    stereoWidth: 1.5,
    saturate: 0.15,
    outputGain: 2,
  },

  // ============ SPINS ============
  {
    id: 'spin_mechanical',
    name: 'Spin - Mechanical',
    description: 'Classic mechanical reel spin feel',
    category: 'spins',
    tags: ['vintage', 'tight', 'clean'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 150, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 800, gain: 2, q: 2, enabled: true },
        { type: 'lowpass', frequency: 8000, gain: 0, q: 0.707, enabled: true },
      ],
      outputGain: -2,
    },
    compressor: {
      threshold: -24,
      ratio: 2,
      attack: 20,
      release: 80,
      knee: 12,
      makeupGain: 1,
    },
    outputGain: -3,
  },

  {
    id: 'spin_modern',
    name: 'Spin - Modern',
    description: 'Clean, modern video slot spin sound',
    category: 'spins',
    tags: ['modern', 'clean', 'fast'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 100, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 1200, gain: 1.5, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 6000, gain: 1, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -20,
      ratio: 3,
      attack: 10,
      release: 60,
      knee: 8,
      makeupGain: 2,
    },
    reverb: {
      type: 'room',
      decay: 0.2,
      predelay: 0,
      damping: 0.8,
      diffusion: 0.5,
      mix: 0.08,
      lowCut: 300,
      highCut: 6000,
    },
    outputGain: -2,
  },

  {
    id: 'reel_stop_impact',
    name: 'Reel Stop - Impact',
    description: 'Satisfying reel stop with physical impact',
    category: 'spins',
    tags: ['punch', 'tight', 'fast'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'lowshelf', frequency: 100, gain: 3, q: 0.707, enabled: true },
        { type: 'peak', frequency: 500, gain: 2, q: 2, enabled: true },
        { type: 'highpass', frequency: 50, gain: 0, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -12,
      ratio: 8,
      attack: 0.5,
      release: 50,
      knee: 3,
      makeupGain: 4,
    },
    saturate: 0.1,
    outputGain: 0,
  },

  // ============ BONUS ============
  {
    id: 'bonus_trigger',
    name: 'Bonus - Trigger',
    description: 'Exciting bonus trigger announcement',
    category: 'bonus',
    tags: ['big', 'bright', 'aggressive'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 60, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 120, gain: 3, q: 0.707, enabled: true },
        { type: 'peak', frequency: 2000, gain: 2, q: 1.2, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 4, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -16,
      ratio: 5,
      attack: 5,
      release: 120,
      knee: 6,
      makeupGain: 3,
    },
    reverb: {
      type: 'hall',
      decay: 1.2,
      predelay: 20,
      damping: 0.4,
      diffusion: 0.85,
      mix: 0.25,
      lowCut: 150,
      highCut: 10000,
    },
    stereoWidth: 1.4,
    outputGain: 1,
  },

  {
    id: 'bonus_ambient',
    name: 'Bonus - Ambient',
    description: 'Atmospheric bonus round ambience',
    category: 'bonus',
    tags: ['wide', 'warm', 'slow'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 40, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 200, gain: 2, q: 0.707, enabled: true },
        { type: 'peak', frequency: 400, gain: -1.5, q: 1, enabled: true },
        { type: 'highshelf', frequency: 4000, gain: -2, q: 0.707, enabled: true },
      ],
      outputGain: -3,
    },
    reverb: {
      type: 'hall',
      decay: 2.5,
      predelay: 40,
      damping: 0.5,
      diffusion: 0.9,
      mix: 0.4,
      lowCut: 80,
      highCut: 8000,
    },
    delay: {
      time: 375,
      feedback: 0.35,
      mix: 0.15,
      sync: false,
      pingPong: true,
      lowCut: 200,
      highCut: 4000,
    },
    stereoWidth: 1.6,
    outputGain: -4,
  },

  // ============ JACKPOT ============
  {
    id: 'jackpot_announcement',
    name: 'Jackpot - Announcement',
    description: 'Massive jackpot announcement with full impact',
    category: 'jackpot',
    tags: ['big', 'aggressive', 'wide'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 30, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 80, gain: 5, q: 0.707, enabled: true },
        { type: 'peak', frequency: 250, gain: -2, q: 1.5, enabled: true },
        { type: 'peak', frequency: 2500, gain: 4, q: 1.2, enabled: true },
        { type: 'highshelf', frequency: 10000, gain: 5, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -12,
      ratio: 8,
      attack: 2,
      release: 250,
      knee: 3,
      makeupGain: 5,
    },
    reverb: {
      type: 'hall',
      decay: 2,
      predelay: 30,
      damping: 0.3,
      diffusion: 0.95,
      mix: 0.35,
      lowCut: 80,
      highCut: 14000,
    },
    delay: {
      time: 180,
      feedback: 0.25,
      mix: 0.12,
      sync: false,
      pingPong: true,
      lowCut: 250,
      highCut: 8000,
    },
    stereoWidth: 1.7,
    saturate: 0.2,
    outputGain: 3,
  },

  {
    id: 'jackpot_coins',
    name: 'Jackpot - Coins',
    description: 'Cascading coin shower effect',
    category: 'jackpot',
    tags: ['bright', 'fast', 'wide'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 200, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 3500, gain: 3, q: 2, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 4, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -20,
      ratio: 3,
      attack: 8,
      release: 80,
      knee: 10,
      makeupGain: 2,
    },
    reverb: {
      type: 'plate',
      decay: 0.6,
      predelay: 10,
      damping: 0.3,
      diffusion: 0.8,
      mix: 0.2,
      lowCut: 400,
      highCut: 12000,
    },
    stereoWidth: 1.5,
    outputGain: 0,
  },

  // ============ UI ============
  {
    id: 'ui_button_click',
    name: 'UI - Button Click',
    description: 'Clean, responsive button click',
    category: 'ui',
    tags: ['clean', 'tight', 'subtle'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 300, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 2000, gain: 2, q: 2, enabled: true },
        { type: 'lowpass', frequency: 8000, gain: 0, q: 0.707, enabled: true },
      ],
      outputGain: -6,
    },
    compressor: {
      threshold: -24,
      ratio: 2,
      attack: 1,
      release: 30,
      knee: 6,
      makeupGain: 0,
    },
    outputGain: -8,
  },

  {
    id: 'ui_hover',
    name: 'UI - Hover',
    description: 'Subtle hover feedback',
    category: 'ui',
    tags: ['subtle', 'clean', 'fast'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 500, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 3000, gain: 1, q: 1.5, enabled: true },
        { type: 'lowpass', frequency: 6000, gain: 0, q: 0.707, enabled: true },
      ],
      outputGain: -12,
    },
    outputGain: -15,
  },

  {
    id: 'ui_notification',
    name: 'UI - Notification',
    description: 'Attention-grabbing notification',
    category: 'ui',
    tags: ['bright', 'punch', 'fast'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 400, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 1500, gain: 2, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 5000, gain: 2, q: 0.707, enabled: true },
      ],
      outputGain: -4,
    },
    compressor: {
      threshold: -18,
      ratio: 3,
      attack: 5,
      release: 60,
      knee: 6,
      makeupGain: 2,
    },
    outputGain: -6,
  },

  // ============ MUSIC ============
  {
    id: 'music_base_game',
    name: 'Music - Base Game',
    description: 'Standard base game music processing',
    category: 'music',
    tags: ['warm', 'wide', 'clean'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 30, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 100, gain: 1, q: 0.707, enabled: true },
        { type: 'peak', frequency: 300, gain: -1, q: 1, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 1, q: 0.707, enabled: true },
      ],
      outputGain: -2,
    },
    compressor: {
      threshold: -18,
      ratio: 2,
      attack: 30,
      release: 200,
      knee: 12,
      makeupGain: 1,
    },
    sidechain: {
      enabled: true,
      threshold: -24,
      ratio: 4,
      attack: 5,
      release: 150,
      range: -8,
    },
    stereoWidth: 1.1,
    outputGain: -6,
  },

  {
    id: 'music_freespins',
    name: 'Music - Free Spins',
    description: 'Elevated free spins music with excitement',
    category: 'music',
    tags: ['bright', 'wide', 'big'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 25, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 80, gain: 2, q: 0.707, enabled: true },
        { type: 'peak', frequency: 2500, gain: 1.5, q: 1.2, enabled: true },
        { type: 'highshelf', frequency: 10000, gain: 2, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -16,
      ratio: 3,
      attack: 20,
      release: 180,
      knee: 8,
      makeupGain: 2,
    },
    sidechain: {
      enabled: true,
      threshold: -20,
      ratio: 5,
      attack: 3,
      release: 120,
      range: -10,
    },
    stereoWidth: 1.25,
    saturate: 0.05,
    outputGain: -4,
  },

  // ============ AMBIENCE ============
  {
    id: 'ambience_casino_floor',
    name: 'Ambience - Casino Floor',
    description: 'Immersive casino floor atmosphere',
    category: 'ambience',
    tags: ['wide', 'warm', 'subtle'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 50, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 200, gain: 2, q: 0.707, enabled: true },
        { type: 'peak', frequency: 500, gain: -2, q: 1, enabled: true },
        { type: 'highshelf', frequency: 4000, gain: -3, q: 0.707, enabled: true },
      ],
      outputGain: -6,
    },
    reverb: {
      type: 'hall',
      decay: 1.8,
      predelay: 30,
      damping: 0.6,
      diffusion: 0.85,
      mix: 0.25,
      lowCut: 100,
      highCut: 6000,
    },
    sidechain: {
      enabled: true,
      threshold: -30,
      ratio: 3,
      attack: 10,
      release: 200,
      range: -6,
    },
    stereoWidth: 1.4,
    outputGain: -12,
  },

  // ============ VOICE ============
  {
    id: 'voice_announcer',
    name: 'Voice - Announcer',
    description: 'Clear, authoritative announcer voice',
    category: 'voice',
    tags: ['punch', 'bright', 'clean'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 80, gain: 0, q: 0.707, enabled: true },
        { type: 'peak', frequency: 200, gain: -2, q: 1.5, enabled: true },
        { type: 'peak', frequency: 3000, gain: 3, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 2, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -20,
      ratio: 4,
      attack: 10,
      release: 100,
      knee: 6,
      makeupGain: 3,
    },
    outputGain: 0,
  },

  // ============ MASTER ============
  {
    id: 'master_slot_standard',
    name: 'Master - Slot Standard',
    description: 'Standard master bus processing for slots',
    category: 'master',
    tags: ['clean', 'punch', 'modern'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 30, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 80, gain: 1, q: 0.707, enabled: true },
        { type: 'peak', frequency: 250, gain: -1, q: 1, enabled: true },
        { type: 'highshelf', frequency: 12000, gain: 0.5, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -12,
      ratio: 2,
      attack: 30,
      release: 200,
      knee: 12,
      makeupGain: 1,
    },
    lowCut: 30,
    highCut: 18000,
    outputGain: -0.5,
  },

  {
    id: 'master_mobile',
    name: 'Master - Mobile Optimized',
    description: 'Optimized for mobile device speakers',
    category: 'master',
    tags: ['bright', 'punch', 'narrow'],
    author: 'ReelForge',
    version: '1.0',
    eq: {
      bands: [
        { type: 'highpass', frequency: 80, gain: 0, q: 0.707, enabled: true },
        { type: 'lowshelf', frequency: 150, gain: 3, q: 0.707, enabled: true },
        { type: 'peak', frequency: 300, gain: 2, q: 1, enabled: true },
        { type: 'peak', frequency: 3000, gain: 2, q: 1.5, enabled: true },
        { type: 'highshelf', frequency: 8000, gain: 1, q: 0.707, enabled: true },
      ],
      outputGain: 0,
    },
    compressor: {
      threshold: -10,
      ratio: 4,
      attack: 10,
      release: 150,
      knee: 6,
      makeupGain: 3,
    },
    stereoWidth: 0.8,
    lowCut: 80,
    highCut: 16000,
    outputGain: 0,
  },
];

// ============ PRESET MANAGER ============

export class SlotFXPresetManager {
  private presets: Map<string, FXChainPreset> = new Map();
  private customPresets: Map<string, FXChainPreset> = new Map();

  constructor() {
    // Load built-in presets
    SLOT_FX_PRESETS.forEach(p => this.presets.set(p.id, p));
  }

  /**
   * Get preset by ID
   */
  getPreset(id: string): FXChainPreset | undefined {
    return this.presets.get(id) || this.customPresets.get(id);
  }

  /**
   * Get all presets
   */
  getAllPresets(): FXChainPreset[] {
    return [
      ...Array.from(this.presets.values()),
      ...Array.from(this.customPresets.values()),
    ];
  }

  /**
   * Get presets by category
   */
  getByCategory(category: PresetCategory): FXChainPreset[] {
    return this.getAllPresets().filter(p => p.category === category);
  }

  /**
   * Get presets by tag
   */
  getByTag(tag: PresetTag): FXChainPreset[] {
    return this.getAllPresets().filter(p => p.tags.includes(tag));
  }

  /**
   * Search presets
   */
  search(query: string): FXChainPreset[] {
    const lowerQuery = query.toLowerCase();
    return this.getAllPresets().filter(p =>
      p.name.toLowerCase().includes(lowerQuery) ||
      p.description.toLowerCase().includes(lowerQuery) ||
      p.category.includes(lowerQuery) ||
      p.tags.some(t => t.includes(lowerQuery))
    );
  }

  /**
   * Add custom preset
   */
  addCustomPreset(preset: Omit<FXChainPreset, 'id'>): FXChainPreset {
    const id = `custom_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const fullPreset = { ...preset, id };
    this.customPresets.set(id, fullPreset);
    return fullPreset;
  }

  /**
   * Update custom preset
   */
  updateCustomPreset(id: string, updates: Partial<FXChainPreset>): boolean {
    const preset = this.customPresets.get(id);
    if (!preset) return false;

    Object.assign(preset, updates);
    return true;
  }

  /**
   * Delete custom preset
   */
  deleteCustomPreset(id: string): boolean {
    return this.customPresets.delete(id);
  }

  /**
   * Export preset to JSON
   */
  exportPreset(id: string): string | null {
    const preset = this.getPreset(id);
    if (!preset) return null;
    return JSON.stringify(preset, null, 2);
  }

  /**
   * Import preset from JSON
   */
  importPreset(json: string): FXChainPreset | null {
    try {
      const preset = JSON.parse(json) as FXChainPreset;
      return this.addCustomPreset(preset);
    } catch {
      return null;
    }
  }

  /**
   * Get category counts
   */
  getCategoryCounts(): Record<PresetCategory, number> {
    const counts: Record<PresetCategory, number> = {
      wins: 0,
      spins: 0,
      bonus: 0,
      jackpot: 0,
      ui: 0,
      music: 0,
      ambience: 0,
      voice: 0,
      master: 0,
    };

    this.getAllPresets().forEach(p => {
      counts[p.category]++;
    });

    return counts;
  }
}

// ============ SINGLETON INSTANCE ============

export const slotFXPresets = new SlotFXPresetManager();

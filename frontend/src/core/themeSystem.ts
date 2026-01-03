/**
 * Theme System
 *
 * Provides theme management:
 * - Light/Dark toggle
 * - Custom accent colors
 * - DAW-style presets (Wwise, FMOD, Ableton)
 * - Persistent preferences
 *
 * @module core/themeSystem
 */

// ============ TYPES ============

export type ThemeMode = 'dark' | 'light' | 'system';

export interface ThemeColors {
  // Background levels
  bg0: string;
  bg1: string;
  bg2: string;
  bg3: string;
  bg4: string;

  // Borders
  border: string;
  borderFocus: string;
  borderActive: string;

  // Text
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textDisabled: string;

  // Accent colors
  accentPrimary: string;
  accentSuccess: string;
  accentWarning: string;
  accentError: string;
  accentSelected: string;

  // Object type colors
  colorEvent: string;
  colorSound: string;
  colorBus: string;
  colorState: string;
  colorSwitch: string;
  colorRtpc: string;
  colorMusic: string;
  colorVoice: string;
}

export interface ThemePreset {
  id: string;
  name: string;
  description?: string;
  mode: ThemeMode;
  colors: Partial<ThemeColors> & { accent?: string; background?: string };
}

export interface ThemeState {
  mode: ThemeMode;
  preset: string;
  customColors: Partial<ThemeColors>;
  effectiveMode: 'dark' | 'light';
}

// ============ DEFAULT THEMES ============

const DARK_COLORS: ThemeColors = {
  bg0: '#0a0a0b',
  bg1: '#121214',
  bg2: '#1a1a1e',
  bg3: '#222228',
  bg4: '#2a2a32',

  border: '#2a2a32',
  borderFocus: '#3a3a44',
  borderActive: '#4a4a54',

  textPrimary: '#f0f0f2',
  textSecondary: '#888892',
  textTertiary: '#555560',
  textDisabled: '#444448',

  accentPrimary: '#0ea5e9',
  accentSuccess: '#22c55e',
  accentWarning: '#f59e0b',
  accentError: '#ef4444',
  accentSelected: '#a855f7',

  colorEvent: '#06b6d4',
  colorSound: '#22c55e',
  colorBus: '#f97316',
  colorState: '#a855f7',
  colorSwitch: '#ec4899',
  colorRtpc: '#eab308',
  colorMusic: '#14b8a6',
  colorVoice: '#3b82f6',
};

const LIGHT_COLORS: ThemeColors = {
  bg0: '#ffffff',
  bg1: '#f8f8fa',
  bg2: '#f0f0f4',
  bg3: '#e8e8ec',
  bg4: '#e0e0e6',

  border: '#d0d0d8',
  borderFocus: '#b0b0bc',
  borderActive: '#9090a0',

  textPrimary: '#18181b',
  textSecondary: '#52525b',
  textTertiary: '#71717a',
  textDisabled: '#a1a1aa',

  accentPrimary: '#0284c7',
  accentSuccess: '#16a34a',
  accentWarning: '#d97706',
  accentError: '#dc2626',
  accentSelected: '#9333ea',

  colorEvent: '#0891b2',
  colorSound: '#16a34a',
  colorBus: '#ea580c',
  colorState: '#9333ea',
  colorSwitch: '#db2777',
  colorRtpc: '#ca8a04',
  colorMusic: '#0d9488',
  colorVoice: '#2563eb',
};

// ============ PRESETS ============

const PRESETS: ThemePreset[] = [
  // Default ReelForge themes
  {
    id: 'reelforge-dark',
    name: 'ReelForge Dark',
    description: 'Default dark theme',
    mode: 'dark',
    colors: {
      accent: '#0ea5e9',
      background: '#0a0a0b',
    },
  },
  {
    id: 'reelforge-light',
    name: 'ReelForge Light',
    description: 'Default light theme',
    mode: 'light',
    colors: {
      accent: '#0284c7',
      background: '#f8fafc',
    },
  },

  // Wwise-inspired
  {
    id: 'wwise',
    name: 'Wwise',
    description: 'Audiokinetic Wwise style',
    mode: 'dark',
    colors: {
      bg0: '#1a1a1a',
      bg1: '#242424',
      bg2: '#2e2e2e',
      bg3: '#383838',
      accentPrimary: '#00a0e3',
      accentSelected: '#ff6b00',
      accent: '#00a0e3',
      background: '#1a1a1a',
    },
  },

  // FMOD-inspired
  {
    id: 'fmod',
    name: 'FMOD',
    description: 'FMOD Studio style',
    mode: 'dark',
    colors: {
      bg0: '#1e1e1e',
      bg1: '#252526',
      bg2: '#2d2d30',
      bg3: '#3c3c3c',
      accentPrimary: '#569cd6',
      accentSuccess: '#4ec9b0',
      accentSelected: '#ce9178',
      accent: '#569cd6',
      background: '#1e1e1e',
    },
  },

  // Ableton-inspired
  {
    id: 'ableton',
    name: 'Ableton Live',
    description: 'Ableton Live style',
    mode: 'dark',
    colors: {
      bg0: '#1e1e1e',
      bg1: '#282828',
      bg2: '#323232',
      bg3: '#3c3c3c',
      accentPrimary: '#ff764d',
      accentSuccess: '#92dca4',
      border: '#444444',
      accent: '#ff764d',
      background: '#1e1e1e',
    },
  },

  // Pro Tools-inspired
  {
    id: 'protools',
    name: 'Pro Tools',
    description: 'Avid Pro Tools style',
    mode: 'dark',
    colors: {
      bg0: '#2b2b2b',
      bg1: '#363636',
      bg2: '#404040',
      bg3: '#4a4a4a',
      accentPrimary: '#4aa3df',
      accentWarning: '#ffc000',
      accent: '#4aa3df',
      background: '#2b2b2b',
    },
  },

  // High Contrast
  {
    id: 'high-contrast',
    name: 'High Contrast',
    description: 'Accessibility mode',
    mode: 'dark',
    colors: {
      bg0: '#000000',
      bg1: '#0a0a0a',
      bg2: '#141414',
      bg3: '#1e1e1e',
      textPrimary: '#ffffff',
      accentPrimary: '#00ffff',
      accentSuccess: '#00ff00',
      accentWarning: '#ffff00',
      accentError: '#ff0000',
      border: '#ffffff',
      accent: '#00ffff',
      background: '#000000',
    },
  },

  // Cubase-inspired
  {
    id: 'cubase',
    name: 'Cubase',
    description: 'Steinberg Cubase style',
    mode: 'dark',
    colors: {
      bg0: '#1a1a1e',
      bg1: '#222226',
      bg2: '#2a2a30',
      bg3: '#363640',
      bg4: '#42424e',
      accentPrimary: '#c0a060',
      accentSuccess: '#80c080',
      accentWarning: '#e0a040',
      accentError: '#e06060',
      accentSelected: '#6080c0',
      border: '#3a3a44',
      accent: '#c0a060',
      background: '#1a1a1e',
    },
  },

  // Logic Pro-inspired
  {
    id: 'logic',
    name: 'Logic Pro',
    description: 'Apple Logic Pro style',
    mode: 'dark',
    colors: {
      bg0: '#1c1c1e',
      bg1: '#2c2c2e',
      bg2: '#3a3a3c',
      bg3: '#48484a',
      bg4: '#636366',
      accentPrimary: '#0a84ff',
      accentSuccess: '#30d158',
      accentWarning: '#ffd60a',
      accentError: '#ff453a',
      accentSelected: '#bf5af2',
      border: '#3a3a3c',
      accent: '#0a84ff',
      background: '#1c1c1e',
    },
  },

  // FL Studio-inspired
  {
    id: 'flstudio',
    name: 'FL Studio',
    description: 'Image-Line FL Studio style',
    mode: 'dark',
    colors: {
      bg0: '#1a1a1a',
      bg1: '#242424',
      bg2: '#2e2e2e',
      bg3: '#3a3a3a',
      bg4: '#464646',
      accentPrimary: '#ff6600',
      accentSuccess: '#00cc66',
      accentWarning: '#ffcc00',
      accentError: '#ff3333',
      accentSelected: '#ff6600',
      border: '#444444',
      accent: '#ff6600',
      background: '#1a1a1a',
    },
  },

  // Bitwig-inspired
  {
    id: 'bitwig',
    name: 'Bitwig Studio',
    description: 'Bitwig Studio style',
    mode: 'dark',
    colors: {
      bg0: '#1d1d1d',
      bg1: '#262626',
      bg2: '#303030',
      bg3: '#3a3a3a',
      bg4: '#454545',
      accentPrimary: '#ef5350',
      accentSuccess: '#66bb6a',
      accentWarning: '#ffca28',
      accentError: '#ef5350',
      accentSelected: '#ab47bc',
      border: '#424242',
      accent: '#ef5350',
      background: '#1d1d1d',
    },
  },

  // Studio One-inspired
  {
    id: 'studio-one',
    name: 'Studio One',
    description: 'PreSonus Studio One style',
    mode: 'dark',
    colors: {
      bg0: '#1e1e1e',
      bg1: '#282828',
      bg2: '#323232',
      bg3: '#3c3c3c',
      bg4: '#464646',
      accentPrimary: '#00a0d0',
      accentSuccess: '#60c060',
      accentWarning: '#e0a020',
      accentError: '#e05050',
      accentSelected: '#00a0d0',
      border: '#404040',
      accent: '#00a0d0',
      background: '#1e1e1e',
    },
  },

  // Reaper-inspired
  {
    id: 'reaper',
    name: 'REAPER',
    description: 'Cockos REAPER style',
    mode: 'dark',
    colors: {
      bg0: '#1a1a1a',
      bg1: '#222222',
      bg2: '#2a2a2a',
      bg3: '#333333',
      bg4: '#3c3c3c',
      accentPrimary: '#80c0ff',
      accentSuccess: '#80e080',
      accentWarning: '#e0c040',
      accentError: '#ff6060',
      accentSelected: '#80c0ff',
      border: '#444444',
      accent: '#80c0ff',
      background: '#1a1a1a',
    },
  },

  // Midnight Blue
  {
    id: 'midnight-blue',
    name: 'Midnight Blue',
    description: 'Deep blue professional theme',
    mode: 'dark',
    colors: {
      bg0: '#0a0e1a',
      bg1: '#101828',
      bg2: '#182038',
      bg3: '#202848',
      bg4: '#283058',
      accentPrimary: '#4f8ff0',
      accentSuccess: '#50c878',
      accentWarning: '#f0a030',
      accentError: '#f05050',
      accentSelected: '#8060f0',
      border: '#283050',
      accent: '#4f8ff0',
      background: '#0a0e1a',
    },
  },

  // Warm Gray
  {
    id: 'warm-gray',
    name: 'Warm Gray',
    description: 'Neutral warm tones',
    mode: 'dark',
    colors: {
      bg0: '#1a1816',
      bg1: '#242220',
      bg2: '#2e2c2a',
      bg3: '#3a3836',
      bg4: '#464442',
      accentPrimary: '#d4a574',
      accentSuccess: '#8bc49c',
      accentWarning: '#e4c476',
      accentError: '#d47474',
      accentSelected: '#a48cd4',
      border: '#3c3a38',
      accent: '#d4a574',
      background: '#1a1816',
    },
  },

  // Classic Light
  {
    id: 'classic-light',
    name: 'Classic Light',
    description: 'Clean professional light theme',
    mode: 'light',
    colors: {
      bg0: '#f5f5f5',
      bg1: '#ebebeb',
      bg2: '#e0e0e0',
      bg3: '#d5d5d5',
      bg4: '#cacaca',
      accentPrimary: '#2196f3',
      accentSuccess: '#4caf50',
      accentWarning: '#ff9800',
      accentError: '#f44336',
      accentSelected: '#9c27b0',
      border: '#bdbdbd',
      textPrimary: '#212121',
      textSecondary: '#757575',
      accent: '#2196f3',
      background: '#f5f5f5',
    },
  },
];

const STORAGE_KEY = 'reelforge-theme';

// ============ THEME MANAGER ============

class ThemeManagerClass {
  private state: ThemeState = {
    mode: 'dark',
    preset: 'reelforge-dark',
    customColors: {},
    effectiveMode: 'dark',
  };

  private listeners: Set<() => void> = new Set();
  private mediaQuery: MediaQueryList | null = null;

  constructor() {
    this.loadFromStorage();
    this.setupSystemThemeListener();
  }

  /**
   * Initialize theme (call on app start)
   */
  initialize(): void {
    this.applyTheme();
  }

  /**
   * Set theme mode
   */
  setMode(mode: ThemeMode): void {
    this.state.mode = mode;
    this.updateEffectiveMode();
    this.applyTheme();
    this.saveToStorage();
    this.emit();
  }

  /**
   * Set preset
   */
  setPreset(presetId: string): void {
    const preset = PRESETS.find(p => p.id === presetId);
    if (!preset) {
      console.warn(`Preset ${presetId} not found`);
      return;
    }

    this.state.preset = presetId;
    this.state.mode = preset.mode;
    this.updateEffectiveMode();
    this.applyTheme();
    this.saveToStorage();
    this.emit();
  }

  /**
   * Set custom color
   */
  setCustomColor(key: keyof ThemeColors, value: string): void {
    this.state.customColors[key] = value;
    this.applyTheme();
    this.saveToStorage();
    this.emit();
  }

  /**
   * Reset custom colors
   */
  resetCustomColors(): void {
    this.state.customColors = {};
    this.applyTheme();
    this.saveToStorage();
    this.emit();
  }

  /**
   * Toggle between light and dark
   */
  toggleMode(): void {
    const newMode = this.state.effectiveMode === 'dark' ? 'light' : 'dark';
    this.setMode(newMode);
  }

  // ============ GETTERS ============

  /**
   * Get current theme state
   */
  getState(): ThemeState {
    return { ...this.state };
  }

  /**
   * Get current mode
   */
  getMode(): ThemeMode {
    return this.state.mode;
  }

  /**
   * Get effective mode (resolved 'system')
   */
  getEffectiveMode(): 'dark' | 'light' {
    return this.state.effectiveMode;
  }

  /**
   * Get current preset
   */
  getPreset(): ThemePreset | null {
    return PRESETS.find(p => p.id === this.state.preset) || null;
  }

  /**
   * Get all presets
   */
  getPresets(): ThemePreset[] {
    return [...PRESETS];
  }

  /**
   * Get computed colors
   */
  getColors(): ThemeColors {
    const baseColors = this.state.effectiveMode === 'dark' ? DARK_COLORS : LIGHT_COLORS;
    const preset = this.getPreset();
    const presetColors = preset?.colors || {};

    return {
      ...baseColors,
      ...presetColors,
      ...this.state.customColors,
    } as ThemeColors;
  }

  // ============ INTERNAL ============

  /**
   * Update effective mode from system preference
   */
  private updateEffectiveMode(): void {
    if (this.state.mode === 'system') {
      this.state.effectiveMode = this.getSystemPreference();
    } else {
      this.state.effectiveMode = this.state.mode;
    }
  }

  /**
   * Get system color scheme preference
   */
  private getSystemPreference(): 'dark' | 'light' {
    if (this.mediaQuery) {
      return this.mediaQuery.matches ? 'dark' : 'light';
    }
    return 'dark';
  }

  /**
   * Setup listener for system theme changes
   */
  private setupSystemThemeListener(): void {
    if (typeof window === 'undefined') return;

    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');

    const handleChange = () => {
      if (this.state.mode === 'system') {
        this.updateEffectiveMode();
        this.applyTheme();
        this.emit();
      }
    };

    this.mediaQuery.addEventListener('change', handleChange);
  }

  /**
   * Apply theme to document
   */
  private applyTheme(): void {
    if (typeof document === 'undefined') return;

    const colors = this.getColors();
    const root = document.documentElement;

    // Set CSS variables
    root.style.setProperty('--rf-bg-0', colors.bg0);
    root.style.setProperty('--rf-bg-1', colors.bg1);
    root.style.setProperty('--rf-bg-2', colors.bg2);
    root.style.setProperty('--rf-bg-3', colors.bg3);
    root.style.setProperty('--rf-bg-4', colors.bg4);

    root.style.setProperty('--rf-border', colors.border);
    root.style.setProperty('--rf-border-focus', colors.borderFocus);
    root.style.setProperty('--rf-border-active', colors.borderActive);

    root.style.setProperty('--rf-text-primary', colors.textPrimary);
    root.style.setProperty('--rf-text-secondary', colors.textSecondary);
    root.style.setProperty('--rf-text-tertiary', colors.textTertiary);
    root.style.setProperty('--rf-text-disabled', colors.textDisabled);

    root.style.setProperty('--rf-accent-primary', colors.accentPrimary);
    root.style.setProperty('--rf-accent-success', colors.accentSuccess);
    root.style.setProperty('--rf-accent-warning', colors.accentWarning);
    root.style.setProperty('--rf-accent-error', colors.accentError);
    root.style.setProperty('--rf-accent-selected', colors.accentSelected);

    root.style.setProperty('--rf-color-event', colors.colorEvent);
    root.style.setProperty('--rf-color-sound', colors.colorSound);
    root.style.setProperty('--rf-color-bus', colors.colorBus);
    root.style.setProperty('--rf-color-state', colors.colorState);
    root.style.setProperty('--rf-color-switch', colors.colorSwitch);
    root.style.setProperty('--rf-color-rtpc', colors.colorRtpc);
    root.style.setProperty('--rf-color-music', colors.colorMusic);
    root.style.setProperty('--rf-color-voice', colors.colorVoice);

    // Set data attribute for CSS selectors
    root.dataset.theme = this.state.effectiveMode;
  }

  // ============ PERSISTENCE ============

  /**
   * Save to localStorage
   */
  private saveToStorage(): void {
    if (typeof localStorage === 'undefined') return;

    const data = {
      mode: this.state.mode,
      preset: this.state.preset,
      customColors: this.state.customColors,
    };

    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }

  /**
   * Load from localStorage
   */
  private loadFromStorage(): void {
    if (typeof localStorage === 'undefined') return;

    try {
      const json = localStorage.getItem(STORAGE_KEY);
      if (json) {
        const data = JSON.parse(json);
        this.state.mode = data.mode || 'dark';
        this.state.preset = data.preset || 'reelforge-dark';
        this.state.customColors = data.customColors || {};
        this.updateEffectiveMode();
      }
    } catch {
      // Use defaults
    }
  }

  // ============ EVENTS ============

  /**
   * Subscribe to theme changes
   */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(): void {
    this.listeners.forEach(l => l());
  }
}

// ============ SINGLETON EXPORT ============

export const ThemeManager = new ThemeManagerClass();

// ============ REACT HOOK ============

import { useState, useEffect, useCallback } from 'react';

export interface UseThemeReturn {
  mode: ThemeMode;
  effectiveMode: 'dark' | 'light';
  resolvedMode: 'dark' | 'light';
  preset: string;
  currentPreset: ThemePreset | null;
  colors: ThemeColors;
  presets: ThemePreset[];
  setMode: (mode: ThemeMode) => void;
  setPreset: (presetId: string) => void;
  toggleMode: () => void;
  setCustomColor: (key: keyof ThemeColors, value: string) => void;
  resetCustomColors: () => void;
}

export function useTheme(): UseThemeReturn {
  const [, forceUpdate] = useState({});

  useEffect(() => {
    ThemeManager.initialize();
    const unsubscribe = ThemeManager.subscribe(() => forceUpdate({}));
    return unsubscribe;
  }, []);

  const presetId = ThemeManager.getState().preset;
  const presets = ThemeManager.getPresets();
  const currentPreset = presets.find(p => p.id === presetId) || null;

  return {
    mode: ThemeManager.getMode(),
    effectiveMode: ThemeManager.getEffectiveMode(),
    resolvedMode: ThemeManager.getEffectiveMode(),
    preset: presetId,
    currentPreset,
    colors: ThemeManager.getColors(),
    presets,
    setMode: useCallback((mode: ThemeMode) => ThemeManager.setMode(mode), []),
    setPreset: useCallback((presetId: string) => ThemeManager.setPreset(presetId), []),
    toggleMode: useCallback(() => ThemeManager.toggleMode(), []),
    setCustomColor: useCallback((key: keyof ThemeColors, value: string) =>
      ThemeManager.setCustomColor(key, value), []),
    resetCustomColors: useCallback(() => ThemeManager.resetCustomColors(), []),
  };
}

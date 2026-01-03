/**
 * Plugin Theme Hook
 *
 * Provides consistent theming for plugin UIs.
 *
 * @module plugin-ui/usePluginTheme
 */

import { useMemo } from 'react';
import { useTheme } from '../core/themeSystem';

// ============ Plugin Theme Interface ============

export interface PluginTheme {
  // Backgrounds
  bgPrimary: string;
  bgSecondary: string;
  bgTertiary: string;
  bgPanel: string;
  bgControl: string;
  bgHover: string;
  bgActive: string;

  // Text
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  textDisabled: string;

  // Borders
  border: string;
  borderFocus: string;
  borderActive: string;

  // Accent colors
  accent: string;
  accentHover: string;
  accentActive: string;
  success: string;
  warning: string;
  error: string;

  // Control colors
  knobTrack: string;
  knobFill: string;
  knobIndicator: string;
  faderTrack: string;
  faderThumb: string;
  meterBg: string;
  meterGreen: string;
  meterYellow: string;
  meterRed: string;

  // Graph colors
  graphBg: string;
  graphGrid: string;
  graphLine: string;
  graphFill: string;

  // Shadows
  shadowLight: string;
  shadowMedium: string;
  shadowHeavy: string;

  // Mode
  isDark: boolean;
}

// ============ Default Plugin Theme ============

const DARK_PLUGIN_THEME: PluginTheme = {
  bgPrimary: '#0d0d14',
  bgSecondary: '#14141c',
  bgTertiary: '#1a1a24',
  bgPanel: '#1e1e2a',
  bgControl: '#22222e',
  bgHover: '#2a2a38',
  bgActive: '#32323e',

  textPrimary: '#f0f0f4',
  textSecondary: '#a0a0b0',
  textMuted: '#606070',
  textDisabled: '#404048',

  border: '#2a2a38',
  borderFocus: '#4080c0',
  borderActive: '#60a0e0',

  accent: '#4080c0',
  accentHover: '#5090d0',
  accentActive: '#60a0e0',
  success: '#40c080',
  warning: '#e0a040',
  error: '#e05050',

  knobTrack: '#2a2a38',
  knobFill: '#4080c0',
  knobIndicator: '#f0f0f4',
  faderTrack: '#1a1a24',
  faderThumb: '#4080c0',
  meterBg: '#0d0d14',
  meterGreen: '#40c080',
  meterYellow: '#e0c040',
  meterRed: '#e05050',

  graphBg: '#0a0a10',
  graphGrid: '#1a1a24',
  graphLine: '#4080c0',
  graphFill: 'rgba(64, 128, 192, 0.2)',

  shadowLight: 'rgba(0, 0, 0, 0.2)',
  shadowMedium: 'rgba(0, 0, 0, 0.4)',
  shadowHeavy: 'rgba(0, 0, 0, 0.6)',

  isDark: true,
};

const LIGHT_PLUGIN_THEME: PluginTheme = {
  bgPrimary: '#f8f8fc',
  bgSecondary: '#f0f0f5',
  bgTertiary: '#e8e8f0',
  bgPanel: '#ffffff',
  bgControl: '#f4f4f8',
  bgHover: '#e8e8f0',
  bgActive: '#e0e0e8',

  textPrimary: '#1a1a24',
  textSecondary: '#505060',
  textMuted: '#808090',
  textDisabled: '#b0b0b8',

  border: '#d0d0d8',
  borderFocus: '#3070b0',
  borderActive: '#4080c0',

  accent: '#3070b0',
  accentHover: '#4080c0',
  accentActive: '#5090d0',
  success: '#30a060',
  warning: '#c08020',
  error: '#c04040',

  knobTrack: '#d0d0d8',
  knobFill: '#3070b0',
  knobIndicator: '#1a1a24',
  faderTrack: '#e0e0e8',
  faderThumb: '#3070b0',
  meterBg: '#f0f0f5',
  meterGreen: '#30a060',
  meterYellow: '#c0a020',
  meterRed: '#c04040',

  graphBg: '#ffffff',
  graphGrid: '#e8e8f0',
  graphLine: '#3070b0',
  graphFill: 'rgba(48, 112, 176, 0.15)',

  shadowLight: 'rgba(0, 0, 0, 0.08)',
  shadowMedium: 'rgba(0, 0, 0, 0.12)',
  shadowHeavy: 'rgba(0, 0, 0, 0.2)',

  isDark: false,
};

// ============ Hook ============

/**
 * Hook for accessing plugin theme.
 * Adapts global theme to plugin-specific colors.
 */
export function usePluginTheme(): PluginTheme {
  const { effectiveMode, colors } = useTheme();
  const isDark = effectiveMode === 'dark';

  return useMemo(() => {
    const base = isDark ? DARK_PLUGIN_THEME : LIGHT_PLUGIN_THEME;

    // Merge with global theme colors
    return {
      ...base,
      accent: colors.accentPrimary,
      accentHover: colors.accentPrimary,
      accentActive: colors.accentSelected,
      success: colors.accentSuccess,
      warning: colors.accentWarning,
      error: colors.accentError,
      knobFill: colors.accentPrimary,
      faderThumb: colors.accentPrimary,
      graphLine: colors.accentPrimary,
      borderFocus: colors.accentPrimary,
      isDark,
    };
  }, [isDark, colors]);
}

/**
 * Create plugin theme from custom colors.
 */
export function createPluginTheme(
  colors: Partial<PluginTheme>,
  isDark = true
): PluginTheme {
  const base = isDark ? DARK_PLUGIN_THEME : LIGHT_PLUGIN_THEME;
  return { ...base, ...colors, isDark };
}

export default usePluginTheme;

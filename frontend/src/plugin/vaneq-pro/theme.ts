/**
 * ReelForge VanEQ Pro Theme System
 *
 * Design tokens for Dark and Light themes.
 * Original visual identity - professional audio look.
 *
 * @module plugin/vaneq-pro/theme
 */

export type ThemeMode = 'auto' | 'dark' | 'light';

export interface VanEQTheme {
  // Background colors
  bgPrimary: string;
  bgSecondary: string;
  bgGraph: string;
  bgPanel: string;

  // Text colors
  textPrimary: string;
  textSecondary: string;
  textMuted: string;

  // Grid and lines
  gridLine: string;
  gridLineAccent: string;
  zeroLine: string;

  // Interactive elements
  buttonBg: string;
  buttonBgHover: string;
  buttonBgActive: string;
  buttonText: string;

  // Input controls
  inputBg: string;
  inputBorder: string;
  inputBorderFocus: string;

  // Curve and spectrum
  curveStroke: string;
  curveFill: string;
  spectrumFill: string;

  // Analyzer spectrum colors
  analyzerPre: string;
  analyzerPost: string;
  analyzerHold: string;

  // Band colors (same for both themes)
  bandColors: string[];

  // Shadows and effects
  shadowLight: string;
  shadowMedium: string;
}

/**
 * Dark theme - professional studio look
 */
export const DARK_THEME: VanEQTheme = {
  bgPrimary: '#1a1a24',
  bgSecondary: '#22222e',
  bgGraph: '#0d0d14',
  bgPanel: '#1e1e2a',

  textPrimary: '#ffffff',
  textSecondary: '#b0b0c0',
  textMuted: '#606070',

  gridLine: '#2a2a38',
  gridLineAccent: '#3a3a48',
  zeroLine: '#4a4a5a',

  buttonBg: '#2a2a3a',
  buttonBgHover: '#3a3a4a',
  buttonBgActive: '#4a4a5a',
  buttonText: '#ffffff',

  inputBg: '#1a1a24',
  inputBorder: '#3a3a4a',
  inputBorderFocus: '#5a8fd4',

  curveStroke: '#5a8fd4',
  curveFill: 'rgba(90, 143, 212, 0.15)',
  spectrumFill: 'rgba(90, 143, 212, 0.3)',

  analyzerPre: 'rgba(100, 150, 255, 0.35)',
  analyzerPost: 'rgba(100, 255, 180, 0.5)',
  analyzerHold: 'rgba(255, 180, 100, 0.6)',

  bandColors: [
    '#e74c3c', // Red
    '#e67e22', // Orange
    '#f1c40f', // Yellow
    '#2ecc71', // Green
    '#3498db', // Blue
    '#9b59b6', // Purple
  ],

  shadowLight: 'rgba(0, 0, 0, 0.2)',
  shadowMedium: 'rgba(0, 0, 0, 0.4)',
};

/**
 * Light theme - clean daylight look
 */
export const LIGHT_THEME: VanEQTheme = {
  bgPrimary: '#f0f0f5',
  bgSecondary: '#e8e8f0',
  bgGraph: '#ffffff',
  bgPanel: '#f5f5fa',

  textPrimary: '#1a1a24',
  textSecondary: '#4a4a5a',
  textMuted: '#8a8a9a',

  gridLine: '#d0d0d8',
  gridLineAccent: '#c0c0c8',
  zeroLine: '#a0a0a8',

  buttonBg: '#e0e0e8',
  buttonBgHover: '#d0d0d8',
  buttonBgActive: '#c0c0c8',
  buttonText: '#1a1a24',

  inputBg: '#ffffff',
  inputBorder: '#c0c0c8',
  inputBorderFocus: '#4a7fc4',

  curveStroke: '#4a7fc4',
  curveFill: 'rgba(74, 127, 196, 0.15)',
  spectrumFill: 'rgba(74, 127, 196, 0.2)',

  analyzerPre: 'rgba(60, 120, 220, 0.3)',
  analyzerPost: 'rgba(40, 180, 120, 0.45)',
  analyzerHold: 'rgba(220, 140, 60, 0.55)',

  bandColors: [
    '#d63031', // Red
    '#d35400', // Orange
    '#d4ac0d', // Yellow
    '#27ae60', // Green
    '#2980b9', // Blue
    '#8e44ad', // Purple
  ],

  shadowLight: 'rgba(0, 0, 0, 0.08)',
  shadowMedium: 'rgba(0, 0, 0, 0.15)',
};

/**
 * Get theme based on mode and system preference.
 */
export function getTheme(mode: ThemeMode): VanEQTheme {
  if (mode === 'light') return LIGHT_THEME;
  if (mode === 'dark') return DARK_THEME;

  // Auto: detect system preference
  if (typeof window !== 'undefined') {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    return prefersDark ? DARK_THEME : LIGHT_THEME;
  }

  return DARK_THEME;
}

/**
 * Convert theme to CSS custom properties.
 */
export function themeToCSSVars(theme: VanEQTheme): Record<string, string> {
  return {
    '--veq-bg-primary': theme.bgPrimary,
    '--veq-bg-secondary': theme.bgSecondary,
    '--veq-bg-graph': theme.bgGraph,
    '--veq-bg-panel': theme.bgPanel,
    '--veq-text-primary': theme.textPrimary,
    '--veq-text-secondary': theme.textSecondary,
    '--veq-text-muted': theme.textMuted,
    '--veq-grid-line': theme.gridLine,
    '--veq-grid-line-accent': theme.gridLineAccent,
    '--veq-zero-line': theme.zeroLine,
    '--veq-button-bg': theme.buttonBg,
    '--veq-button-bg-hover': theme.buttonBgHover,
    '--veq-button-bg-active': theme.buttonBgActive,
    '--veq-button-text': theme.buttonText,
    '--veq-input-bg': theme.inputBg,
    '--veq-input-border': theme.inputBorder,
    '--veq-input-border-focus': theme.inputBorderFocus,
    '--veq-curve-stroke': theme.curveStroke,
    '--veq-curve-fill': theme.curveFill,
    '--veq-spectrum-fill': theme.spectrumFill,
    '--veq-analyzer-pre': theme.analyzerPre,
    '--veq-analyzer-post': theme.analyzerPost,
    '--veq-analyzer-hold': theme.analyzerHold,
    '--veq-shadow-light': theme.shadowLight,
    '--veq-shadow-medium': theme.shadowMedium,
    // Band colors
    '--veq-band-1': theme.bandColors[0],
    '--veq-band-2': theme.bandColors[1],
    '--veq-band-3': theme.bandColors[2],
    '--veq-band-4': theme.bandColors[3],
    '--veq-band-5': theme.bandColors[4],
    '--veq-band-6': theme.bandColors[5],
  };
}

/**
 * ReelForge Pro Suite Theme System
 *
 * Shared design tokens for VanEQ, VanComp, VanLimit Pro plugins.
 * Dark and Light themes with original visual identity.
 *
 * @module plugin/pro-suite/theme
 */

export type ThemeMode = 'auto' | 'dark' | 'light';

export interface ProSuiteTheme {
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

  // Meters and visualization
  meterBg: string;
  meterGreen: string;
  meterYellow: string;
  meterRed: string;
  meterGradient: string[];

  // Gain reduction
  grColor: string;
  grColorBright: string;

  // Waveform
  waveformColor: string;
  waveformBg: string;

  // Accent colors
  accentPrimary: string;
  accentSecondary: string;

  // Status colors
  statusActive: string;
  statusBypassed: string;
  statusWarning: string;

  // Shadows and effects
  shadowLight: string;
  shadowMedium: string;

  // EQ-specific: Curve and spectrum
  curveStroke: string;
  curveFill: string;
  spectrumFill: string;

  // EQ-specific: Analyzer spectrum colors
  analyzerPre: string;
  analyzerPost: string;
  analyzerHold: string;

  // EQ-specific: Band colors
  bandColors: string[];
}

/**
 * Dark theme - professional studio look
 */
export const DARK_THEME: ProSuiteTheme = {
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

  meterBg: '#0a0a10',
  meterGreen: '#00cc66',
  meterYellow: '#ffcc00',
  meterRed: '#ff3333',
  meterGradient: ['#00cc66', '#66cc00', '#cccc00', '#ffcc00', '#ff6600', '#ff3333'],

  grColor: '#ff6b35',
  grColorBright: '#ff8855',

  waveformColor: '#5a8fd4',
  waveformBg: '#1a1a24',

  accentPrimary: '#5a8fd4',
  accentSecondary: '#8a6fd4',

  statusActive: '#00cc66',
  statusBypassed: '#666666',
  statusWarning: '#ffcc00',

  shadowLight: 'rgba(0, 0, 0, 0.2)',
  shadowMedium: 'rgba(0, 0, 0, 0.4)',

  // EQ-specific
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
};

/**
 * Light theme - clean daylight look
 */
export const LIGHT_THEME: ProSuiteTheme = {
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

  meterBg: '#e8e8f0',
  meterGreen: '#00aa55',
  meterYellow: '#ddaa00',
  meterRed: '#dd2222',
  meterGradient: ['#00aa55', '#55aa00', '#aaaa00', '#ddaa00', '#dd5500', '#dd2222'],

  grColor: '#dd5522',
  grColorBright: '#ff7744',

  waveformColor: '#4a7fc4',
  waveformBg: '#f5f5fa',

  accentPrimary: '#4a7fc4',
  accentSecondary: '#7a5fc4',

  statusActive: '#00aa55',
  statusBypassed: '#888888',
  statusWarning: '#ddaa00',

  shadowLight: 'rgba(0, 0, 0, 0.08)',
  shadowMedium: 'rgba(0, 0, 0, 0.15)',

  // EQ-specific
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
};

/**
 * Get theme based on mode and system preference.
 */
export function getTheme(mode: ThemeMode): ProSuiteTheme {
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
export function themeToCSSVars(theme: ProSuiteTheme): Record<string, string> {
  return {
    '--vp-bg-primary': theme.bgPrimary,
    '--vp-bg-secondary': theme.bgSecondary,
    '--vp-bg-graph': theme.bgGraph,
    '--vp-bg-panel': theme.bgPanel,
    '--vp-text-primary': theme.textPrimary,
    '--vp-text-secondary': theme.textSecondary,
    '--vp-text-muted': theme.textMuted,
    '--vp-grid-line': theme.gridLine,
    '--vp-grid-line-accent': theme.gridLineAccent,
    '--vp-zero-line': theme.zeroLine,
    '--vp-button-bg': theme.buttonBg,
    '--vp-button-bg-hover': theme.buttonBgHover,
    '--vp-button-bg-active': theme.buttonBgActive,
    '--vp-button-text': theme.buttonText,
    '--vp-input-bg': theme.inputBg,
    '--vp-input-border': theme.inputBorder,
    '--vp-input-border-focus': theme.inputBorderFocus,
    '--vp-meter-bg': theme.meterBg,
    '--vp-meter-green': theme.meterGreen,
    '--vp-meter-yellow': theme.meterYellow,
    '--vp-meter-red': theme.meterRed,
    '--vp-gr-color': theme.grColor,
    '--vp-gr-color-bright': theme.grColorBright,
    '--vp-waveform-color': theme.waveformColor,
    '--vp-waveform-bg': theme.waveformBg,
    '--vp-accent-primary': theme.accentPrimary,
    '--vp-accent-secondary': theme.accentSecondary,
    '--vp-status-active': theme.statusActive,
    '--vp-status-bypassed': theme.statusBypassed,
    '--vp-status-warning': theme.statusWarning,
    '--vp-shadow-light': theme.shadowLight,
    '--vp-shadow-medium': theme.shadowMedium,
    // EQ-specific
    '--vp-curve-stroke': theme.curveStroke,
    '--vp-curve-fill': theme.curveFill,
    '--vp-spectrum-fill': theme.spectrumFill,
    '--vp-analyzer-pre': theme.analyzerPre,
    '--vp-analyzer-post': theme.analyzerPost,
    '--vp-analyzer-hold': theme.analyzerHold,
    // Band colors
    '--vp-band-1': theme.bandColors[0],
    '--vp-band-2': theme.bandColors[1],
    '--vp-band-3': theme.bandColors[2],
    '--vp-band-4': theme.bandColors[3],
    '--vp-band-5': theme.bandColors[4],
    '--vp-band-6': theme.bandColors[5],
  };
}

/**
 * Theme Tokens
 *
 * Design tokens for light and dark themes.
 * Based on WCAG 2.1 AA contrast requirements.
 *
 * @module theme/themeTokens
 */

// ============ Types ============

export interface ThemeTokens {
  // Background colors
  bgPrimary: string;
  bgSecondary: string;
  bgTertiary: string;
  bgElevated: string;
  bgOverlay: string;

  // Surface colors (panels, cards)
  surfaceDefault: string;
  surfaceHover: string;
  surfaceActive: string;
  surfaceDisabled: string;

  // Text colors
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textDisabled: string;
  textInverse: string;

  // Border colors
  borderDefault: string;
  borderFocus: string;
  borderError: string;

  // Accent colors
  accentPrimary: string;
  accentPrimaryHover: string;
  accentSecondary: string;
  accentSuccess: string;
  accentWarning: string;
  accentError: string;

  // Audio-specific colors
  meterGreen: string;
  meterYellow: string;
  meterRed: string;
  meterBackground: string;
  waveformFill: string;
  waveformStroke: string;
  playhead: string;
  loopRegion: string;
  selection: string;

  // Track colors (palette)
  trackColors: string[];

  // Shadows
  shadowSm: string;
  shadowMd: string;
  shadowLg: string;

  // Animation timings
  transitionFast: string;
  transitionNormal: string;
  transitionSlow: string;
}

// ============ Dark Theme ============

export const darkTheme: ThemeTokens = {
  // Backgrounds
  bgPrimary: '#1a1a1a',
  bgSecondary: '#242424',
  bgTertiary: '#2d2d2d',
  bgElevated: '#333333',
  bgOverlay: 'rgba(0, 0, 0, 0.75)',

  // Surfaces
  surfaceDefault: '#2a2a2a',
  surfaceHover: '#353535',
  surfaceActive: '#404040',
  surfaceDisabled: '#1f1f1f',

  // Text (WCAG AA contrast ratios)
  textPrimary: '#ffffff', // 21:1 contrast
  textSecondary: '#b3b3b3', // 7.5:1 contrast
  textTertiary: '#808080', // 4.6:1 contrast
  textDisabled: '#666666',
  textInverse: '#1a1a1a',

  // Borders
  borderDefault: '#404040',
  borderFocus: '#3b82f6',
  borderError: '#ef4444',

  // Accents
  accentPrimary: '#3b82f6', // Blue
  accentPrimaryHover: '#60a5fa',
  accentSecondary: '#8b5cf6', // Purple
  accentSuccess: '#22c55e',
  accentWarning: '#f59e0b',
  accentError: '#ef4444',

  // Audio
  meterGreen: '#22c55e',
  meterYellow: '#f59e0b',
  meterRed: '#ef4444',
  meterBackground: '#1f1f1f',
  waveformFill: '#3b82f6',
  waveformStroke: '#60a5fa',
  playhead: '#ffffff',
  loopRegion: 'rgba(139, 92, 246, 0.3)',
  selection: 'rgba(59, 130, 246, 0.3)',

  // Track colors
  trackColors: [
    '#e74c3c', '#9b59b6', '#3498db', '#2ecc71', '#f39c12',
    '#1abc9c', '#e67e22', '#c0392b', '#8e44ad', '#27ae60',
  ],

  // Shadows
  shadowSm: '0 1px 2px rgba(0, 0, 0, 0.5)',
  shadowMd: '0 4px 6px rgba(0, 0, 0, 0.5)',
  shadowLg: '0 10px 15px rgba(0, 0, 0, 0.5)',

  // Transitions
  transitionFast: '100ms ease-out',
  transitionNormal: '200ms ease-out',
  transitionSlow: '300ms ease-out',
};

// ============ Light Theme ============

export const lightTheme: ThemeTokens = {
  // Backgrounds
  bgPrimary: '#ffffff',
  bgSecondary: '#f5f5f5',
  bgTertiary: '#e5e5e5',
  bgElevated: '#ffffff',
  bgOverlay: 'rgba(255, 255, 255, 0.9)',

  // Surfaces
  surfaceDefault: '#ffffff',
  surfaceHover: '#f0f0f0',
  surfaceActive: '#e0e0e0',
  surfaceDisabled: '#fafafa',

  // Text (WCAG AA contrast ratios)
  textPrimary: '#1a1a1a', // 21:1 contrast
  textSecondary: '#525252', // 7.3:1 contrast
  textTertiary: '#737373', // 4.6:1 contrast
  textDisabled: '#a3a3a3',
  textInverse: '#ffffff',

  // Borders
  borderDefault: '#d4d4d4',
  borderFocus: '#2563eb',
  borderError: '#dc2626',

  // Accents
  accentPrimary: '#2563eb', // Darker blue for better contrast
  accentPrimaryHover: '#1d4ed8',
  accentSecondary: '#7c3aed',
  accentSuccess: '#16a34a',
  accentWarning: '#d97706',
  accentError: '#dc2626',

  // Audio
  meterGreen: '#16a34a',
  meterYellow: '#d97706',
  meterRed: '#dc2626',
  meterBackground: '#e5e5e5',
  waveformFill: '#2563eb',
  waveformStroke: '#1d4ed8',
  playhead: '#1a1a1a',
  loopRegion: 'rgba(124, 58, 237, 0.2)',
  selection: 'rgba(37, 99, 235, 0.2)',

  // Track colors (slightly darker for light bg)
  trackColors: [
    '#c0392b', '#8e44ad', '#2980b9', '#27ae60', '#d68910',
    '#16a085', '#d35400', '#a93226', '#6c3483', '#1e8449',
  ],

  // Shadows
  shadowSm: '0 1px 2px rgba(0, 0, 0, 0.1)',
  shadowMd: '0 4px 6px rgba(0, 0, 0, 0.1)',
  shadowLg: '0 10px 15px rgba(0, 0, 0, 0.1)',

  // Transitions
  transitionFast: '100ms ease-out',
  transitionNormal: '200ms ease-out',
  transitionSlow: '300ms ease-out',
};

// ============ High Contrast Theme ============

export const highContrastTheme: ThemeTokens = {
  ...darkTheme,

  // Maximum contrast text
  textPrimary: '#ffffff',
  textSecondary: '#ffffff',
  textTertiary: '#e5e5e5',

  // Stronger borders
  borderDefault: '#ffffff',
  borderFocus: '#ffff00',
  borderError: '#ff0000',

  // Brighter accents
  accentPrimary: '#00aaff',
  accentPrimaryHover: '#00ccff',
  accentSuccess: '#00ff00',
  accentWarning: '#ffff00',
  accentError: '#ff0000',

  // Audio with high contrast
  meterGreen: '#00ff00',
  meterYellow: '#ffff00',
  meterRed: '#ff0000',
};

// ============ CSS Variable Generator ============

export function generateCSSVariables(theme: ThemeTokens): string {
  return `
    --rf-bg-primary: ${theme.bgPrimary};
    --rf-bg-secondary: ${theme.bgSecondary};
    --rf-bg-tertiary: ${theme.bgTertiary};
    --rf-bg-elevated: ${theme.bgElevated};
    --rf-bg-overlay: ${theme.bgOverlay};

    --rf-surface-default: ${theme.surfaceDefault};
    --rf-surface-hover: ${theme.surfaceHover};
    --rf-surface-active: ${theme.surfaceActive};
    --rf-surface-disabled: ${theme.surfaceDisabled};

    --rf-text-primary: ${theme.textPrimary};
    --rf-text-secondary: ${theme.textSecondary};
    --rf-text-tertiary: ${theme.textTertiary};
    --rf-text-disabled: ${theme.textDisabled};
    --rf-text-inverse: ${theme.textInverse};

    --rf-border-default: ${theme.borderDefault};
    --rf-border-focus: ${theme.borderFocus};
    --rf-border-error: ${theme.borderError};

    --rf-accent-primary: ${theme.accentPrimary};
    --rf-accent-primary-hover: ${theme.accentPrimaryHover};
    --rf-accent-secondary: ${theme.accentSecondary};
    --rf-accent-success: ${theme.accentSuccess};
    --rf-accent-warning: ${theme.accentWarning};
    --rf-accent-error: ${theme.accentError};

    --rf-meter-green: ${theme.meterGreen};
    --rf-meter-yellow: ${theme.meterYellow};
    --rf-meter-red: ${theme.meterRed};
    --rf-meter-bg: ${theme.meterBackground};
    --rf-waveform-fill: ${theme.waveformFill};
    --rf-waveform-stroke: ${theme.waveformStroke};
    --rf-playhead: ${theme.playhead};
    --rf-loop-region: ${theme.loopRegion};
    --rf-selection: ${theme.selection};

    --rf-shadow-sm: ${theme.shadowSm};
    --rf-shadow-md: ${theme.shadowMd};
    --rf-shadow-lg: ${theme.shadowLg};

    --rf-transition-fast: ${theme.transitionFast};
    --rf-transition-normal: ${theme.transitionNormal};
    --rf-transition-slow: ${theme.transitionSlow};
  `.trim();
}

export default { darkTheme, lightTheme, highContrastTheme, generateCSSVariables };

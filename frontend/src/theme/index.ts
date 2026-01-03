/**
 * ReelForge Theme System
 *
 * Complete theme management for ReelForge Editor.
 *
 * @module theme
 */

// Provider and hooks
export {
  ThemeProvider,
  useThemeContext,
  useThemeColors,
  useThemePreset,
  useThemeMode,
  getThemeCSSVar,
  createThemeStyle,
  type ThemeContextValue,
  type ThemeProviderProps,
  type ThemeMode,
  type ThemeColors,
  type ThemePreset,
  type ThemeState,
} from './ThemeProvider';

// Editor
export { ThemeEditor, type ThemeEditorProps } from './ThemeEditor';

// Re-export core
export { ThemeManager, useTheme } from '../core/themeSystem';

// New theme tokens (WCAG AA compliant)
export {
  darkTheme,
  lightTheme,
  highContrastTheme,
  generateCSSVariables,
  type ThemeTokens,
} from './themeTokens';

// Theme mode atom for Jotai integration
export { themeModeAtom } from './useTheme';

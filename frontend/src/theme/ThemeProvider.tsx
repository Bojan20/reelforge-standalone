/**
 * ReelForge Theme Provider
 *
 * React context provider for theme management.
 * Wraps application and provides theme context to all children.
 *
 * @module theme/ThemeProvider
 */

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from 'react';
import {
  ThemeManager,
  useTheme as useCoreTheme,
  type ThemeMode,
  type ThemeColors,
  type ThemePreset,
  type ThemeState,
} from '../core/themeSystem';

// ============ Context ============

export interface ThemeContextValue {
  /** Current theme mode */
  mode: ThemeMode;
  /** Effective mode (resolved 'system') */
  effectiveMode: 'dark' | 'light';
  /** Current preset ID */
  preset: string;
  /** Current preset object */
  currentPreset: ThemePreset | null;
  /** Computed colors */
  colors: ThemeColors;
  /** All available presets */
  presets: ThemePreset[];
  /** Full theme state */
  state: ThemeState;
  /** Set theme mode */
  setMode: (mode: ThemeMode) => void;
  /** Set preset */
  setPreset: (presetId: string) => void;
  /** Toggle dark/light */
  toggleMode: () => void;
  /** Set custom color */
  setCustomColor: (key: keyof ThemeColors, value: string) => void;
  /** Reset custom colors */
  resetCustomColors: () => void;
  /** Check if dark mode */
  isDark: boolean;
  /** Check if light mode */
  isLight: boolean;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

// ============ Provider ============

export interface ThemeProviderProps {
  children: ReactNode;
  /** Initial mode (optional) */
  initialMode?: ThemeMode;
  /** Initial preset (optional) */
  initialPreset?: string;
}

export function ThemeProvider({
  children,
  initialMode,
  initialPreset,
}: ThemeProviderProps) {
  // Initialize theme on mount
  useEffect(() => {
    if (initialMode) {
      ThemeManager.setMode(initialMode);
    }
    if (initialPreset) {
      ThemeManager.setPreset(initialPreset);
    }
    ThemeManager.initialize();
  }, []);

  // Use core theme hook
  const coreTheme = useCoreTheme();

  // Build context value
  const contextValue = useMemo<ThemeContextValue>(() => ({
    mode: coreTheme.mode,
    effectiveMode: coreTheme.effectiveMode,
    preset: coreTheme.preset,
    currentPreset: coreTheme.currentPreset,
    colors: coreTheme.colors,
    presets: coreTheme.presets,
    state: {
      mode: coreTheme.mode,
      preset: coreTheme.preset,
      customColors: {},
      effectiveMode: coreTheme.effectiveMode,
    },
    setMode: coreTheme.setMode,
    setPreset: coreTheme.setPreset,
    toggleMode: coreTheme.toggleMode,
    setCustomColor: coreTheme.setCustomColor,
    resetCustomColors: coreTheme.resetCustomColors,
    isDark: coreTheme.effectiveMode === 'dark',
    isLight: coreTheme.effectiveMode === 'light',
  }), [coreTheme]);

  return (
    <ThemeContext.Provider value={contextValue}>
      <div
        className={`rf-theme-root rf-theme--${coreTheme.effectiveMode}`}
        data-theme={coreTheme.effectiveMode}
        data-preset={coreTheme.preset}
      >
        {children}
      </div>
    </ThemeContext.Provider>
  );
}

// ============ Hooks ============

/**
 * Hook to access theme context.
 * Must be used within ThemeProvider.
 */
export function useThemeContext(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error('useThemeContext must be used within ThemeProvider');
  }
  return context;
}

/**
 * Hook for theme colors only.
 */
export function useThemeColors(): ThemeColors {
  const { colors } = useThemeContext();
  return colors;
}

/**
 * Hook for current preset.
 */
export function useThemePreset(): ThemePreset | null {
  const { currentPreset } = useThemeContext();
  return currentPreset;
}

/**
 * Hook for mode info.
 */
export function useThemeMode() {
  const { mode, effectiveMode, isDark, isLight, toggleMode, setMode } =
    useThemeContext();
  return { mode, effectiveMode, isDark, isLight, toggleMode, setMode };
}

// ============ Utility Functions ============

/**
 * Get CSS variable value for a color.
 */
export function getThemeCSSVar(colorKey: keyof ThemeColors): string {
  const varMap: Record<keyof ThemeColors, string> = {
    bg0: '--rf-bg-0',
    bg1: '--rf-bg-1',
    bg2: '--rf-bg-2',
    bg3: '--rf-bg-3',
    bg4: '--rf-bg-4',
    border: '--rf-border',
    borderFocus: '--rf-border-focus',
    borderActive: '--rf-border-active',
    textPrimary: '--rf-text-primary',
    textSecondary: '--rf-text-secondary',
    textTertiary: '--rf-text-tertiary',
    textDisabled: '--rf-text-disabled',
    accentPrimary: '--rf-accent-primary',
    accentSuccess: '--rf-accent-success',
    accentWarning: '--rf-accent-warning',
    accentError: '--rf-accent-error',
    accentSelected: '--rf-accent-selected',
    colorEvent: '--rf-color-event',
    colorSound: '--rf-color-sound',
    colorBus: '--rf-color-bus',
    colorState: '--rf-color-state',
    colorSwitch: '--rf-color-switch',
    colorRtpc: '--rf-color-rtpc',
    colorMusic: '--rf-color-music',
    colorVoice: '--rf-color-voice',
  };
  return `var(${varMap[colorKey]})`;
}

/**
 * Create inline style object from theme colors.
 */
export function createThemeStyle(
  colors: Partial<ThemeColors>
): React.CSSProperties {
  const style: Record<string, string> = {};

  if (colors.bg0) style['--rf-bg-0'] = colors.bg0;
  if (colors.bg1) style['--rf-bg-1'] = colors.bg1;
  if (colors.bg2) style['--rf-bg-2'] = colors.bg2;
  if (colors.bg3) style['--rf-bg-3'] = colors.bg3;
  if (colors.bg4) style['--rf-bg-4'] = colors.bg4;
  if (colors.border) style['--rf-border'] = colors.border;
  if (colors.accentPrimary) style['--rf-accent-primary'] = colors.accentPrimary;
  if (colors.accentSuccess) style['--rf-accent-success'] = colors.accentSuccess;
  if (colors.accentWarning) style['--rf-accent-warning'] = colors.accentWarning;
  if (colors.accentError) style['--rf-accent-error'] = colors.accentError;
  if (colors.textPrimary) style['--rf-text-primary'] = colors.textPrimary;
  if (colors.textSecondary) style['--rf-text-secondary'] = colors.textSecondary;

  return style as React.CSSProperties;
}

// ============ Exports ============

export type { ThemeMode, ThemeColors, ThemePreset, ThemeState };
export default ThemeProvider;

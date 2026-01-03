/**
 * useTheme - Theme Management Hook
 *
 * Provides theme switching with:
 * - System preference detection
 * - Persistent storage
 * - CSS variable injection
 * - High contrast mode support
 *
 * @module theme/useTheme
 */

import { useEffect, useCallback } from 'react';
import { useAtom } from 'jotai';
import { atomWithStorage } from 'jotai/utils';
import {
  darkTheme,
  lightTheme,
  highContrastTheme,
  generateCSSVariables,
  type ThemeTokens,
} from './themeTokens';

// ============ Types ============

export type ThemeMode = 'light' | 'dark' | 'system' | 'high-contrast';

export interface UseThemeReturn {
  /** Current theme mode */
  mode: ThemeMode;
  /** Set theme mode */
  setMode: (mode: ThemeMode) => void;
  /** Toggle between light and dark */
  toggle: () => void;
  /** Current resolved theme (light or dark) */
  resolvedTheme: 'light' | 'dark' | 'high-contrast';
  /** Current theme tokens */
  tokens: ThemeTokens;
  /** Is dark mode (resolved) */
  isDark: boolean;
  /** Is system preference */
  isSystem: boolean;
}

// ============ Atom ============

export const themeModeAtom = atomWithStorage<ThemeMode>('rf_theme_mode', 'system');

// ============ Hook ============

export function useTheme(): UseThemeReturn {
  const [mode, setMode] = useAtom(themeModeAtom);

  // Detect system preference
  const getSystemPreference = useCallback((): 'light' | 'dark' => {
    if (typeof window === 'undefined') return 'dark';
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }, []);

  // Detect high contrast preference
  const getHighContrastPreference = useCallback((): boolean => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia('(prefers-contrast: more)').matches;
  }, []);

  // Resolve theme
  const resolvedTheme = useCallback((): 'light' | 'dark' | 'high-contrast' => {
    if (mode === 'high-contrast') return 'high-contrast';
    if (mode === 'system') {
      if (getHighContrastPreference()) return 'high-contrast';
      return getSystemPreference();
    }
    return mode;
  }, [mode, getSystemPreference, getHighContrastPreference]);

  // Get current tokens
  const getTokens = useCallback((): ThemeTokens => {
    const resolved = resolvedTheme();
    switch (resolved) {
      case 'light': return lightTheme;
      case 'high-contrast': return highContrastTheme;
      default: return darkTheme;
    }
  }, [resolvedTheme]);

  // Apply theme to DOM
  useEffect(() => {
    const resolved = resolvedTheme();
    const tokens = getTokens();

    // Set data attribute
    document.documentElement.setAttribute('data-theme', resolved);

    // Inject CSS variables
    const cssVars = generateCSSVariables(tokens);
    let styleEl = document.getElementById('rf-theme-vars') as HTMLStyleElement | null;

    if (!styleEl) {
      styleEl = document.createElement('style');
      styleEl.id = 'rf-theme-vars';
      document.head.appendChild(styleEl);
    }

    styleEl.textContent = `:root { ${cssVars} }`;

    // Update meta theme-color for mobile
    let metaTheme = document.querySelector('meta[name="theme-color"]');
    if (!metaTheme) {
      metaTheme = document.createElement('meta');
      metaTheme.setAttribute('name', 'theme-color');
      document.head.appendChild(metaTheme);
    }
    metaTheme.setAttribute('content', tokens.bgPrimary);

  }, [resolvedTheme, getTokens]);

  // Listen for system preference changes
  useEffect(() => {
    if (mode !== 'system') return;

    const darkMatcher = window.matchMedia('(prefers-color-scheme: dark)');
    const contrastMatcher = window.matchMedia('(prefers-contrast: more)');

    const handler = () => {
      // Force re-render by touching the atom
      setMode('system');
    };

    darkMatcher.addEventListener('change', handler);
    contrastMatcher.addEventListener('change', handler);

    return () => {
      darkMatcher.removeEventListener('change', handler);
      contrastMatcher.removeEventListener('change', handler);
    };
  }, [mode, setMode]);

  // Toggle between light and dark
  const toggle = useCallback(() => {
    const resolved = resolvedTheme();
    if (resolved === 'dark' || resolved === 'high-contrast') {
      setMode('light');
    } else {
      setMode('dark');
    }
  }, [resolvedTheme, setMode]);

  const resolved = resolvedTheme();

  return {
    mode,
    setMode,
    toggle,
    resolvedTheme: resolved,
    tokens: getTokens(),
    isDark: resolved === 'dark' || resolved === 'high-contrast',
    isSystem: mode === 'system',
  };
}

export default useTheme;

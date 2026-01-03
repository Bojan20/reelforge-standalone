/**
 * Editor Mode Hook
 *
 * Manages the current editor mode (DAW vs Middleware).
 * Provides mode switching with keyboard shortcuts and persistence.
 *
 * DAW Mode:
 * - Timeline-centric editing
 * - Full mixer in lower zone
 * - Audio clip editing focus
 * - Transport bar prominent
 *
 * Middleware Mode:
 * - Event-centric editing
 * - Routing and states focus
 * - Game integration tools
 * - Console/debug prominent
 *
 * @module hooks/useEditorMode
 */

import { useState, useCallback, useEffect, useMemo } from 'react';

// ============ Types ============

export type EditorMode = 'daw' | 'middleware';

export interface EditorModeConfig {
  /** Mode identifier */
  mode: EditorMode;
  /** Display name */
  name: string;
  /** Short description */
  description: string;
  /** Icon (emoji or component key) */
  icon: string;
  /** Accent color for mode */
  accentColor: string;
  /** Keyboard shortcut */
  shortcut: string;
}

export interface UseEditorModeReturn {
  /** Current mode */
  mode: EditorMode;
  /** Set mode directly */
  setMode: (mode: EditorMode) => void;
  /** Toggle between modes */
  toggleMode: () => void;
  /** Current mode config */
  config: EditorModeConfig;
  /** All available modes */
  modes: EditorModeConfig[];
  /** Check if specific mode is active */
  isMode: (mode: EditorMode) => boolean;
}

// ============ Mode Configurations ============

export const MODE_CONFIGS: Record<EditorMode, EditorModeConfig> = {
  daw: {
    mode: 'daw',
    name: 'DAW',
    description: 'Timeline editing & mixing',
    icon: '🎹',
    accentColor: '#0ea5e9', // Blue
    shortcut: '⌘1',
  },
  middleware: {
    mode: 'middleware',
    name: 'Events',
    description: 'Event routing & game integration',
    icon: '🎮',
    accentColor: '#f97316', // Orange
    shortcut: '⌘2',
  },
};

// ============ Storage Key ============

const STORAGE_KEY = 'reelforge-editor-mode';

// ============ Hook ============

export function useEditorMode(
  initialMode: EditorMode = 'daw'
): UseEditorModeReturn {
  // Load from localStorage or use initial
  const [mode, setModeState] = useState<EditorMode>(() => {
    if (typeof window !== 'undefined') {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored === 'daw' || stored === 'middleware') {
        return stored;
      }
    }
    return initialMode;
  });

  // Set mode with persistence
  const setMode = useCallback((newMode: EditorMode) => {
    setModeState(newMode);
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY, newMode);
    }
  }, []);

  // Toggle between modes
  const toggleMode = useCallback(() => {
    setMode(mode === 'daw' ? 'middleware' : 'daw');
  }, [mode, setMode]);

  // Check if specific mode
  const isMode = useCallback(
    (checkMode: EditorMode) => mode === checkMode,
    [mode]
  );

  // Current config
  const config = MODE_CONFIGS[mode];

  // All modes as array
  const modes = useMemo(() => Object.values(MODE_CONFIGS), []);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore if typing in input
      if (
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLTextAreaElement ||
        e.target instanceof HTMLSelectElement
      ) {
        return;
      }

      const isMeta = e.metaKey || e.ctrlKey;

      // Cmd+1 = DAW mode
      if (isMeta && e.key === '1') {
        e.preventDefault();
        setMode('daw');
      }
      // Cmd+2 = Middleware mode
      else if (isMeta && e.key === '2') {
        e.preventDefault();
        setMode('middleware');
      }
      // Cmd+` = Toggle mode
      else if (isMeta && e.key === '`') {
        e.preventDefault();
        toggleMode();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [setMode, toggleMode]);

  // Update CSS custom property for accent color
  useEffect(() => {
    if (typeof document !== 'undefined') {
      document.documentElement.style.setProperty(
        '--rf-mode-accent',
        config.accentColor
      );
      // Also set a class for mode-specific styling
      document.documentElement.setAttribute('data-editor-mode', mode);
    }
  }, [mode, config.accentColor]);

  return {
    mode,
    setMode,
    toggleMode,
    config,
    modes,
    isMode,
  };
}

export default useEditorMode;

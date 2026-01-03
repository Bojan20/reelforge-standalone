/**
 * ReelForge Keyboard Shortcuts System
 *
 * Global and context-aware keyboard shortcut handling.
 * Features:
 * - Global shortcuts (play, stop, save, etc.)
 * - Context-aware shortcuts (timeline, mixer, editor)
 * - Modifier key support (Ctrl/Cmd, Shift, Alt)
 * - Shortcut conflict detection
 * - User customization support
 *
 * @module shortcuts/useKeyboardShortcuts
 */

import { useEffect, useCallback, useRef, useState } from 'react';

// ============ Types ============

export type ModifierKey = 'ctrl' | 'shift' | 'alt' | 'meta';

export interface ShortcutDefinition {
  /** Unique shortcut ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Key code (e.g., 'KeyS', 'Space', 'ArrowLeft') */
  key: string;
  /** Required modifier keys */
  modifiers?: ModifierKey[];
  /** Context where shortcut is active (null = global) */
  context?: string | null;
  /** Action to execute */
  action: () => void;
  /** Whether shortcut is enabled */
  enabled?: boolean;
  /** Category for organization */
  category?: string;
}

export interface ShortcutEvent {
  key: string;
  code: string;
  ctrl: boolean;
  shift: boolean;
  alt: boolean;
  meta: boolean;
  preventDefault: () => void;
  stopPropagation: () => void;
}

export interface UseKeyboardShortcutsOptions {
  /** Enable/disable all shortcuts */
  enabled?: boolean;
  /** Active context */
  context?: string | null;
  /** Prevent default browser shortcuts */
  preventDefault?: boolean;
  /** Stop event propagation */
  stopPropagation?: boolean;
}

// ============ Constants ============

const IGNORED_ELEMENTS = ['INPUT', 'TEXTAREA', 'SELECT'];

// Detect Mac
const isMac = typeof navigator !== 'undefined' && /Mac/.test(navigator.platform);

// ============ Default Shortcuts ============

export const DEFAULT_SHORTCUTS: Omit<ShortcutDefinition, 'action'>[] = [
  // Transport
  {
    id: 'transport.play',
    name: 'Play/Pause',
    key: 'Space',
    category: 'Transport',
    description: 'Toggle playback',
  },
  {
    id: 'transport.stop',
    name: 'Stop',
    key: 'Period',
    category: 'Transport',
    description: 'Stop and return to start',
  },
  {
    id: 'transport.rewind',
    name: 'Rewind',
    key: 'Comma',
    category: 'Transport',
    description: 'Go to previous marker or start',
  },
  {
    id: 'transport.forward',
    name: 'Forward',
    key: 'Slash',
    category: 'Transport',
    description: 'Go to next marker or end',
  },
  {
    id: 'transport.record',
    name: 'Record',
    key: 'KeyR',
    modifiers: ['ctrl'],
    category: 'Transport',
    description: 'Toggle recording',
  },
  {
    id: 'transport.loop',
    name: 'Toggle Loop',
    key: 'KeyL',
    category: 'Transport',
    description: 'Toggle loop mode',
  },

  // Edit
  {
    id: 'edit.undo',
    name: 'Undo',
    key: 'KeyZ',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'Edit',
    description: 'Undo last action',
  },
  {
    id: 'edit.redo',
    name: 'Redo',
    key: 'KeyZ',
    modifiers: [isMac ? 'meta' : 'ctrl', 'shift'],
    category: 'Edit',
    description: 'Redo last undone action',
  },
  {
    id: 'edit.cut',
    name: 'Cut',
    key: 'KeyX',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'Edit',
    description: 'Cut selection',
  },
  {
    id: 'edit.copy',
    name: 'Copy',
    key: 'KeyC',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'Edit',
    description: 'Copy selection',
  },
  {
    id: 'edit.paste',
    name: 'Paste',
    key: 'KeyV',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'Edit',
    description: 'Paste from clipboard',
  },
  {
    id: 'edit.delete',
    name: 'Delete',
    key: 'Delete',
    category: 'Edit',
    description: 'Delete selection',
  },
  {
    id: 'edit.selectAll',
    name: 'Select All',
    key: 'KeyA',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'Edit',
    description: 'Select all items',
  },

  // File
  {
    id: 'file.save',
    name: 'Save',
    key: 'KeyS',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'File',
    description: 'Save project',
  },
  {
    id: 'file.saveAs',
    name: 'Save As',
    key: 'KeyS',
    modifiers: [isMac ? 'meta' : 'ctrl', 'shift'],
    category: 'File',
    description: 'Save project as new file',
  },
  {
    id: 'file.open',
    name: 'Open',
    key: 'KeyO',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'File',
    description: 'Open project',
  },
  {
    id: 'file.new',
    name: 'New',
    key: 'KeyN',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'File',
    description: 'New project',
  },
  {
    id: 'file.export',
    name: 'Export',
    key: 'KeyE',
    modifiers: [isMac ? 'meta' : 'ctrl', 'shift'],
    category: 'File',
    description: 'Export audio',
  },

  // View
  {
    id: 'view.zoomIn',
    name: 'Zoom In',
    key: 'Equal',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'View',
    description: 'Zoom in timeline',
  },
  {
    id: 'view.zoomOut',
    name: 'Zoom Out',
    key: 'Minus',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'View',
    description: 'Zoom out timeline',
  },
  {
    id: 'view.zoomFit',
    name: 'Zoom to Fit',
    key: 'Digit0',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'View',
    description: 'Fit all content in view',
  },
  {
    id: 'view.toggleMixer',
    name: 'Toggle Mixer',
    key: 'KeyM',
    modifiers: [isMac ? 'meta' : 'ctrl'],
    category: 'View',
    description: 'Show/hide mixer panel',
  },

  // Timeline context
  {
    id: 'timeline.split',
    name: 'Split Clip',
    key: 'KeyS',
    context: 'timeline',
    category: 'Timeline',
    description: 'Split clip at playhead',
  },
  {
    id: 'timeline.snap',
    name: 'Toggle Snap',
    key: 'KeyN',
    context: 'timeline',
    category: 'Timeline',
    description: 'Toggle snap to grid',
  },
  {
    id: 'timeline.addMarker',
    name: 'Add Marker',
    key: 'KeyM',
    context: 'timeline',
    category: 'Timeline',
    description: 'Add marker at playhead',
  },

  // Mixer context
  {
    id: 'mixer.mute',
    name: 'Mute Channel',
    key: 'KeyM',
    context: 'mixer',
    category: 'Mixer',
    description: 'Mute selected channel',
  },
  {
    id: 'mixer.solo',
    name: 'Solo Channel',
    key: 'KeyS',
    context: 'mixer',
    category: 'Mixer',
    description: 'Solo selected channel',
  },
];

// ============ Hook ============

export function useKeyboardShortcuts(
  shortcuts: ShortcutDefinition[],
  options: UseKeyboardShortcutsOptions = {}
) {
  const {
    enabled = true,
    context = null,
    preventDefault = true,
    stopPropagation = false,
  } = options;

  const shortcutsRef = useRef(shortcuts);
  shortcutsRef.current = shortcuts;

  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      // Skip if disabled
      if (!enabled) return;

      // Skip if in text input
      const target = event.target as HTMLElement;
      if (IGNORED_ELEMENTS.includes(target.tagName)) {
        // Allow some shortcuts even in inputs
        const isSpecialShortcut =
          (event.metaKey || event.ctrlKey) &&
          ['s', 'z', 'y'].includes(event.key.toLowerCase());
        if (!isSpecialShortcut) return;
      }

      // Find matching shortcut
      for (const shortcut of shortcutsRef.current) {
        if (shortcut.enabled === false) continue;

        // Check context
        if (shortcut.context && shortcut.context !== context) continue;

        // Check key
        if (shortcut.key !== event.code) continue;

        // Check modifiers
        const requiredMods = shortcut.modifiers || [];
        const hasCtrl = requiredMods.includes('ctrl');
        const hasShift = requiredMods.includes('shift');
        const hasAlt = requiredMods.includes('alt');
        const hasMeta = requiredMods.includes('meta');

        if (hasCtrl !== event.ctrlKey) continue;
        if (hasShift !== event.shiftKey) continue;
        if (hasAlt !== event.altKey) continue;
        if (hasMeta !== event.metaKey) continue;

        // Execute action
        if (preventDefault) {
          event.preventDefault();
        }
        if (stopPropagation) {
          event.stopPropagation();
        }

        shortcut.action();
        return;
      }
    },
    [enabled, context, preventDefault, stopPropagation]
  );

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);
}

// ============ Shortcut Manager Hook ============

export interface ShortcutManager {
  /** All registered shortcuts */
  shortcuts: ShortcutDefinition[];
  /** Register a shortcut */
  register: (shortcut: ShortcutDefinition) => void;
  /** Unregister a shortcut */
  unregister: (id: string) => void;
  /** Update a shortcut */
  update: (id: string, updates: Partial<ShortcutDefinition>) => void;
  /** Get shortcut by ID */
  get: (id: string) => ShortcutDefinition | undefined;
  /** Get shortcuts by category */
  getByCategory: (category: string) => ShortcutDefinition[];
  /** Get shortcuts by context */
  getByContext: (context: string | null) => ShortcutDefinition[];
  /** Check for conflicts */
  checkConflict: (shortcut: ShortcutDefinition) => ShortcutDefinition | null;
  /** Format shortcut for display */
  formatShortcut: (shortcut: ShortcutDefinition) => string;
  /** Active context */
  context: string | null;
  /** Set active context */
  setContext: (context: string | null) => void;
}

export function useShortcutManager(): ShortcutManager {
  const [shortcuts, setShortcuts] = useState<ShortcutDefinition[]>([]);
  const [context, setContext] = useState<string | null>(null);

  const register = useCallback((shortcut: ShortcutDefinition) => {
    setShortcuts((prev) => {
      // Check for existing
      const existing = prev.find((s) => s.id === shortcut.id);
      if (existing) {
        // Update existing
        return prev.map((s) => (s.id === shortcut.id ? shortcut : s));
      }
      return [...prev, shortcut];
    });
  }, []);

  const unregister = useCallback((id: string) => {
    setShortcuts((prev) => prev.filter((s) => s.id !== id));
  }, []);

  const update = useCallback(
    (id: string, updates: Partial<ShortcutDefinition>) => {
      setShortcuts((prev) =>
        prev.map((s) => (s.id === id ? { ...s, ...updates } : s))
      );
    },
    []
  );

  const get = useCallback(
    (id: string) => shortcuts.find((s) => s.id === id),
    [shortcuts]
  );

  const getByCategory = useCallback(
    (category: string) => shortcuts.filter((s) => s.category === category),
    [shortcuts]
  );

  const getByContext = useCallback(
    (ctx: string | null) =>
      shortcuts.filter((s) => s.context === ctx || s.context === undefined),
    [shortcuts]
  );

  const checkConflict = useCallback(
    (shortcut: ShortcutDefinition): ShortcutDefinition | null => {
      for (const existing of shortcuts) {
        if (existing.id === shortcut.id) continue;

        // Same key
        if (existing.key !== shortcut.key) continue;

        // Same context (or both global)
        if (existing.context !== shortcut.context) continue;

        // Same modifiers
        const existingMods = new Set(existing.modifiers || []);
        const newMods = new Set(shortcut.modifiers || []);
        if (existingMods.size !== newMods.size) continue;

        let sameModifiers = true;
        for (const mod of existingMods) {
          if (!newMods.has(mod)) {
            sameModifiers = false;
            break;
          }
        }

        if (sameModifiers) return existing;
      }
      return null;
    },
    [shortcuts]
  );

  const formatShortcut = useCallback((shortcut: ShortcutDefinition): string => {
    const parts: string[] = [];

    if (shortcut.modifiers) {
      if (shortcut.modifiers.includes('ctrl')) {
        parts.push(isMac ? '⌃' : 'Ctrl');
      }
      if (shortcut.modifiers.includes('meta')) {
        parts.push(isMac ? '⌘' : 'Win');
      }
      if (shortcut.modifiers.includes('alt')) {
        parts.push(isMac ? '⌥' : 'Alt');
      }
      if (shortcut.modifiers.includes('shift')) {
        parts.push(isMac ? '⇧' : 'Shift');
      }
    }

    // Format key name
    let keyName = shortcut.key;
    if (keyName.startsWith('Key')) {
      keyName = keyName.slice(3);
    } else if (keyName.startsWith('Digit')) {
      keyName = keyName.slice(5);
    } else if (keyName === 'Space') {
      keyName = isMac ? '␣' : 'Space';
    } else if (keyName === 'ArrowLeft') {
      keyName = '←';
    } else if (keyName === 'ArrowRight') {
      keyName = '→';
    } else if (keyName === 'ArrowUp') {
      keyName = '↑';
    } else if (keyName === 'ArrowDown') {
      keyName = '↓';
    } else if (keyName === 'Period') {
      keyName = '.';
    } else if (keyName === 'Comma') {
      keyName = ',';
    } else if (keyName === 'Slash') {
      keyName = '/';
    } else if (keyName === 'Equal') {
      keyName = '+';
    } else if (keyName === 'Minus') {
      keyName = '-';
    }

    parts.push(keyName);

    return parts.join(isMac ? '' : '+');
  }, []);

  // Activate hook
  useKeyboardShortcuts(shortcuts, { context });

  return {
    shortcuts,
    register,
    unregister,
    update,
    get,
    getByCategory,
    getByContext,
    checkConflict,
    formatShortcut,
    context,
    setContext,
  };
}

// ============ Context Hook ============

export function useShortcutContext(context: string) {
  const [isActive, setIsActive] = useState(false);
  const ref = useRef<HTMLElement>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const handleFocus = () => setIsActive(true);
    const handleBlur = () => setIsActive(false);

    element.addEventListener('focusin', handleFocus);
    element.addEventListener('focusout', handleBlur);
    element.addEventListener('mouseenter', handleFocus);
    element.addEventListener('mouseleave', handleBlur);

    return () => {
      element.removeEventListener('focusin', handleFocus);
      element.removeEventListener('focusout', handleBlur);
      element.removeEventListener('mouseenter', handleFocus);
      element.removeEventListener('mouseleave', handleBlur);
    };
  }, []);

  return { ref, isActive, context };
}

export default useKeyboardShortcuts;

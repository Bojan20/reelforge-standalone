/**
 * ReelForge Keyboard Shortcuts
 *
 * Centralized keyboard shortcut management with:
 * - Global and scoped shortcuts
 * - Conflict detection
 * - Customizable bindings
 * - React integration
 */

import { useEffect, useCallback, useSyncExternalStore } from 'react';

// ============ Types ============

export type ModifierKey = 'ctrl' | 'alt' | 'shift' | 'meta';

export interface KeyBinding {
  key: string;
  modifiers?: ModifierKey[];
}

export interface Shortcut {
  id: string;
  name: string;
  description: string;
  binding: KeyBinding;
  /** Scope where shortcut is active */
  scope: 'global' | 'mixer' | 'timeline' | 'editor' | 'modal';
  /** Category for UI grouping */
  category: 'playback' | 'editing' | 'navigation' | 'file' | 'view';
  /** Whether shortcut can be customized */
  customizable: boolean;
}

export type ShortcutId =
  // Playback
  | 'playback.play'
  | 'playback.stop'
  | 'playback.rewind'
  // Editing
  | 'edit.undo'
  | 'edit.redo'
  | 'edit.cut'
  | 'edit.copy'
  | 'edit.paste'
  | 'edit.delete'
  | 'edit.selectAll'
  // File
  | 'file.save'
  | 'file.saveAs'
  | 'file.open'
  | 'file.new'
  | 'file.export'
  // View
  | 'view.zoomIn'
  | 'view.zoomOut'
  | 'view.zoomFit'
  | 'view.toggleMixer'
  // Navigation
  | 'nav.nextEvent'
  | 'nav.prevEvent'
  | 'nav.escape';

// ============ Default Shortcuts ============

const DEFAULT_SHORTCUTS: Record<ShortcutId, Shortcut> = {
  // Playback
  'playback.play': {
    id: 'playback.play',
    name: 'Play/Pause',
    description: 'Toggle playback',
    binding: { key: ' ' },
    scope: 'global',
    category: 'playback',
    customizable: true,
  },
  'playback.stop': {
    id: 'playback.stop',
    name: 'Stop',
    description: 'Stop playback and return to start',
    binding: { key: 'Escape' },
    scope: 'global',
    category: 'playback',
    customizable: true,
  },
  'playback.rewind': {
    id: 'playback.rewind',
    name: 'Rewind',
    description: 'Return to start',
    binding: { key: 'Home' },
    scope: 'global',
    category: 'playback',
    customizable: true,
  },

  // Editing
  'edit.undo': {
    id: 'edit.undo',
    name: 'Undo',
    description: 'Undo last action',
    binding: { key: 'z', modifiers: ['meta'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },
  'edit.redo': {
    id: 'edit.redo',
    name: 'Redo',
    description: 'Redo last undone action',
    binding: { key: 'z', modifiers: ['meta', 'shift'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },
  'edit.cut': {
    id: 'edit.cut',
    name: 'Cut',
    description: 'Cut selection',
    binding: { key: 'x', modifiers: ['meta'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },
  'edit.copy': {
    id: 'edit.copy',
    name: 'Copy',
    description: 'Copy selection',
    binding: { key: 'c', modifiers: ['meta'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },
  'edit.paste': {
    id: 'edit.paste',
    name: 'Paste',
    description: 'Paste from clipboard',
    binding: { key: 'v', modifiers: ['meta'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },
  'edit.delete': {
    id: 'edit.delete',
    name: 'Delete',
    description: 'Delete selection',
    binding: { key: 'Backspace' },
    scope: 'global',
    category: 'editing',
    customizable: true,
  },
  'edit.selectAll': {
    id: 'edit.selectAll',
    name: 'Select All',
    description: 'Select all items',
    binding: { key: 'a', modifiers: ['meta'] },
    scope: 'global',
    category: 'editing',
    customizable: false,
  },

  // File
  'file.save': {
    id: 'file.save',
    name: 'Save',
    description: 'Save project',
    binding: { key: 's', modifiers: ['meta'] },
    scope: 'global',
    category: 'file',
    customizable: false,
  },
  'file.saveAs': {
    id: 'file.saveAs',
    name: 'Save As',
    description: 'Save project as new file',
    binding: { key: 's', modifiers: ['meta', 'shift'] },
    scope: 'global',
    category: 'file',
    customizable: false,
  },
  'file.open': {
    id: 'file.open',
    name: 'Open',
    description: 'Open project',
    binding: { key: 'o', modifiers: ['meta'] },
    scope: 'global',
    category: 'file',
    customizable: false,
  },
  'file.new': {
    id: 'file.new',
    name: 'New',
    description: 'Create new project',
    binding: { key: 'n', modifiers: ['meta'] },
    scope: 'global',
    category: 'file',
    customizable: false,
  },
  'file.export': {
    id: 'file.export',
    name: 'Export',
    description: 'Export audio',
    binding: { key: 'e', modifiers: ['meta', 'shift'] },
    scope: 'global',
    category: 'file',
    customizable: true,
  },

  // View
  'view.zoomIn': {
    id: 'view.zoomIn',
    name: 'Zoom In',
    description: 'Zoom in timeline',
    binding: { key: '=', modifiers: ['meta'] },
    scope: 'timeline',
    category: 'view',
    customizable: true,
  },
  'view.zoomOut': {
    id: 'view.zoomOut',
    name: 'Zoom Out',
    description: 'Zoom out timeline',
    binding: { key: '-', modifiers: ['meta'] },
    scope: 'timeline',
    category: 'view',
    customizable: true,
  },
  'view.zoomFit': {
    id: 'view.zoomFit',
    name: 'Zoom to Fit',
    description: 'Fit timeline to view',
    binding: { key: '0', modifiers: ['meta'] },
    scope: 'timeline',
    category: 'view',
    customizable: true,
  },
  'view.toggleMixer': {
    id: 'view.toggleMixer',
    name: 'Toggle Mixer',
    description: 'Show/hide mixer panel',
    binding: { key: 'm', modifiers: ['meta'] },
    scope: 'global',
    category: 'view',
    customizable: true,
  },

  // Navigation
  'nav.nextEvent': {
    id: 'nav.nextEvent',
    name: 'Next Event',
    description: 'Go to next event',
    binding: { key: 'ArrowDown' },
    scope: 'global',
    category: 'navigation',
    customizable: true,
  },
  'nav.prevEvent': {
    id: 'nav.prevEvent',
    name: 'Previous Event',
    description: 'Go to previous event',
    binding: { key: 'ArrowUp' },
    scope: 'global',
    category: 'navigation',
    customizable: true,
  },
  'nav.escape': {
    id: 'nav.escape',
    name: 'Escape',
    description: 'Close modal or deselect',
    binding: { key: 'Escape' },
    scope: 'global',
    category: 'navigation',
    customizable: false,
  },
};

// ============ Shortcut Manager ============

type ShortcutHandler = (e: KeyboardEvent) => void;

class ShortcutManager {
  private shortcuts: Map<ShortcutId, Shortcut> = new Map();
  private handlers: Map<ShortcutId, Set<ShortcutHandler>> = new Map();
  private customBindings: Map<ShortcutId, KeyBinding> = new Map();
  private activeScopes: Set<Shortcut['scope']> = new Set(['global']);
  private enabled = true;
  private listeners: Set<() => void> = new Set();

  constructor() {
    this.initializeShortcuts();
    this.loadCustomBindings();
    this.setupGlobalListener();
  }

  private initializeShortcuts(): void {
    for (const [id, shortcut] of Object.entries(DEFAULT_SHORTCUTS)) {
      this.shortcuts.set(id as ShortcutId, { ...shortcut });
      this.handlers.set(id as ShortcutId, new Set());
    }
  }

  private loadCustomBindings(): void {
    try {
      const stored = localStorage.getItem('rf-keyboard-shortcuts');
      if (stored) {
        const bindings = JSON.parse(stored) as Record<string, KeyBinding>;
        for (const [id, binding] of Object.entries(bindings)) {
          this.customBindings.set(id as ShortcutId, binding);
        }
      }
    } catch {
      // Ignore localStorage errors
    }
  }

  private saveCustomBindings(): void {
    try {
      const bindings = Object.fromEntries(this.customBindings);
      localStorage.setItem('rf-keyboard-shortcuts', JSON.stringify(bindings));
    } catch {
      // Ignore localStorage errors
    }
  }

  private setupGlobalListener(): void {
    document.addEventListener('keydown', this.handleKeyDown);
  }

  private handleKeyDown = (e: KeyboardEvent): void => {
    if (!this.enabled) return;

    // Skip if typing in input/textarea
    const target = e.target as HTMLElement;
    if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable) {
      // Allow specific shortcuts even in inputs
      const isEscape = e.key === 'Escape';
      const isMetaShortcut = e.metaKey || e.ctrlKey;
      if (!isEscape && !isMetaShortcut) return;
    }

    // Find matching shortcut
    for (const [id, shortcut] of this.shortcuts) {
      if (!this.isShortcutActive(shortcut)) continue;

      const binding = this.getBinding(id);
      if (this.matchesBinding(e, binding)) {
        const handlers = this.handlers.get(id);
        if (handlers && handlers.size > 0) {
          e.preventDefault();
          e.stopPropagation();
          handlers.forEach((handler) => handler(e));
          return;
        }
      }
    }
  };

  private isShortcutActive(shortcut: Shortcut): boolean {
    return shortcut.scope === 'global' || this.activeScopes.has(shortcut.scope);
  }

  private matchesBinding(e: KeyboardEvent, binding: KeyBinding): boolean {
    // Normalize key
    const key = e.key.toLowerCase();
    const bindingKey = binding.key.toLowerCase();

    if (key !== bindingKey && e.code.toLowerCase() !== bindingKey) {
      // Special case for space
      if (bindingKey === ' ' && key !== ' ') return false;
      if (bindingKey !== ' ' && key !== bindingKey) return false;
    }

    // Check modifiers
    const modifiers = binding.modifiers ?? [];
    const needsCtrl = modifiers.includes('ctrl');
    const needsAlt = modifiers.includes('alt');
    const needsShift = modifiers.includes('shift');
    const needsMeta = modifiers.includes('meta');

    // On Mac, treat Cmd (meta) as primary modifier
    // On Windows/Linux, treat Ctrl as primary modifier
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const primaryModifier = isMac ? e.metaKey : e.ctrlKey;
    const needsPrimary = needsMeta || needsCtrl;

    if (needsPrimary && !primaryModifier) return false;
    if (!needsPrimary && primaryModifier) return false;
    if (needsAlt !== e.altKey) return false;
    if (needsShift !== e.shiftKey) return false;

    return true;
  }

  // ============ Public API ============

  getBinding(id: ShortcutId): KeyBinding {
    return this.customBindings.get(id) ?? this.shortcuts.get(id)?.binding ?? { key: '' };
  }

  getShortcut(id: ShortcutId): Shortcut | undefined {
    const shortcut = this.shortcuts.get(id);
    if (!shortcut) return undefined;
    return { ...shortcut, binding: this.getBinding(id) };
  }

  getAllShortcuts(): Shortcut[] {
    return Array.from(this.shortcuts.values()).map((s) => ({
      ...s,
      binding: this.getBinding(s.id as ShortcutId),
    }));
  }

  getShortcutsByCategory(category: Shortcut['category']): Shortcut[] {
    return this.getAllShortcuts().filter((s) => s.category === category);
  }

  register(id: ShortcutId, handler: ShortcutHandler): () => void {
    const handlers = this.handlers.get(id);
    if (handlers) {
      handlers.add(handler);
    }
    return () => this.unregister(id, handler);
  }

  unregister(id: ShortcutId, handler: ShortcutHandler): void {
    const handlers = this.handlers.get(id);
    if (handlers) {
      handlers.delete(handler);
    }
  }

  setBinding(id: ShortcutId, binding: KeyBinding): void {
    const shortcut = this.shortcuts.get(id);
    if (!shortcut?.customizable) return;

    this.customBindings.set(id, binding);
    this.saveCustomBindings();
    this.notifyListeners();
  }

  resetBinding(id: ShortcutId): void {
    this.customBindings.delete(id);
    this.saveCustomBindings();
    this.notifyListeners();
  }

  resetAllBindings(): void {
    this.customBindings.clear();
    this.saveCustomBindings();
    this.notifyListeners();
  }

  setScope(scope: Shortcut['scope'], active: boolean): void {
    if (active) {
      this.activeScopes.add(scope);
    } else {
      this.activeScopes.delete(scope);
    }
  }

  enable(): void {
    this.enabled = true;
  }

  disable(): void {
    this.enabled = false;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notifyListeners(): void {
    this.listeners.forEach((l) => l());
  }

  /**
   * Format binding for display.
   */
  formatBinding(binding: KeyBinding): string {
    const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
    const parts: string[] = [];

    if (binding.modifiers?.includes('meta') || binding.modifiers?.includes('ctrl')) {
      parts.push(isMac ? '⌘' : 'Ctrl');
    }
    if (binding.modifiers?.includes('alt')) {
      parts.push(isMac ? '⌥' : 'Alt');
    }
    if (binding.modifiers?.includes('shift')) {
      parts.push(isMac ? '⇧' : 'Shift');
    }

    // Format key
    let keyDisplay = binding.key;
    switch (binding.key.toLowerCase()) {
      case ' ':
        keyDisplay = 'Space';
        break;
      case 'arrowup':
        keyDisplay = '↑';
        break;
      case 'arrowdown':
        keyDisplay = '↓';
        break;
      case 'arrowleft':
        keyDisplay = '←';
        break;
      case 'arrowright':
        keyDisplay = '→';
        break;
      case 'escape':
        keyDisplay = 'Esc';
        break;
      case 'backspace':
        keyDisplay = '⌫';
        break;
      case 'enter':
        keyDisplay = '↵';
        break;
      case 'tab':
        keyDisplay = '⇥';
        break;
      default:
        keyDisplay = binding.key.toUpperCase();
    }

    parts.push(keyDisplay);
    return parts.join(isMac ? '' : '+');
  }

  dispose(): void {
    document.removeEventListener('keydown', this.handleKeyDown);
    this.handlers.clear();
    this.listeners.clear();
  }
}

// ============ Singleton Instance ============

export const shortcuts = new ShortcutManager();

// ============ React Hooks ============

/**
 * Register a keyboard shortcut handler.
 */
export function useShortcut(id: ShortcutId, handler: () => void, deps: unknown[] = []): void {
  const stableHandler = useCallback(handler, deps);

  useEffect(() => {
    return shortcuts.register(id, stableHandler);
  }, [id, stableHandler]);
}

/**
 * Get all shortcuts (reactive).
 */
export function useShortcuts(): Shortcut[] {
  return useSyncExternalStore(
    (onStoreChange) => shortcuts.subscribe(onStoreChange),
    () => shortcuts.getAllShortcuts(),
    () => shortcuts.getAllShortcuts()
  );
}

/**
 * Get formatted binding string for a shortcut.
 */
export function useShortcutLabel(id: ShortcutId): string {
  const binding = useSyncExternalStore(
    (onStoreChange) => shortcuts.subscribe(onStoreChange),
    () => shortcuts.getBinding(id),
    () => shortcuts.getBinding(id)
  );
  return shortcuts.formatBinding(binding);
}

/**
 * Hook to set active scope while component is mounted.
 */
export function useShortcutScope(scope: Shortcut['scope']): void {
  useEffect(() => {
    shortcuts.setScope(scope, true);
    return () => shortcuts.setScope(scope, false);
  }, [scope]);
}

// ============ Development Tools ============

if (import.meta.env.DEV) {
  (window as unknown as { rfShortcuts: ShortcutManager }).rfShortcuts = shortcuts;
}

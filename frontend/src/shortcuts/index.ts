/**
 * ReelForge Keyboard Shortcuts Module
 *
 * Global and context-aware keyboard shortcut system.
 *
 * @module shortcuts
 */

export {
  useKeyboardShortcuts,
  useShortcutManager,
  useShortcutContext,
  DEFAULT_SHORTCUTS,
} from './useKeyboardShortcuts';

export type {
  ModifierKey,
  ShortcutDefinition,
  ShortcutEvent,
  UseKeyboardShortcutsOptions,
  ShortcutManager,
} from './useKeyboardShortcuts';

export { ShortcutsPanel } from './ShortcutsPanel';
export type { ShortcutsPanelProps } from './ShortcutsPanel';

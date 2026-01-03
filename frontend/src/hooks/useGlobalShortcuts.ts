/**
 * useGlobalShortcuts - Global keyboard shortcuts for the editor
 *
 * Provides consistent keyboard shortcuts across the application:
 * - Space: Play/Pause
 * - Cmd/Ctrl+S: Save project
 * - Cmd/Ctrl+Z: Undo
 * - Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y: Redo
 * - Delete/Backspace: Delete selected
 * - Escape: Deselect all
 *
 * @module hooks/useGlobalShortcuts
 */

import { useEffect, useCallback, useRef } from 'react';

// ============ Types ============

export interface ShortcutAction {
  /** Play/pause transport */
  onPlayPause?: () => void;
  /** Stop transport */
  onStop?: () => void;
  /** Record toggle */
  onRecord?: () => void;
  /** Save project */
  onSave?: () => void;
  /** Save As */
  onSaveAs?: () => void;
  /** Open project */
  onOpen?: () => void;
  /** New project */
  onNew?: () => void;
  /** Export audio */
  onExport?: () => void;
  /** Undo last action */
  onUndo?: () => void;
  /** Redo last undone action */
  onRedo?: () => void;
  /** Delete selected items */
  onDelete?: () => void;
  /** Deselect all */
  onDeselect?: () => void;
  /** Select all */
  onSelectAll?: () => void;
  /** Cut */
  onCut?: () => void;
  /** Copy */
  onCopy?: () => void;
  /** Paste */
  onPaste?: () => void;
  /** Duplicate */
  onDuplicate?: () => void;
  /** Split at cursor */
  onSplit?: () => void;
  /** Trim to selection */
  onTrim?: () => void;
  /** Mute selected */
  onMute?: () => void;
  /** Solo selected */
  onSolo?: () => void;
  /** Arm for recording */
  onArm?: () => void;
  /** Zoom in */
  onZoomIn?: () => void;
  /** Zoom out */
  onZoomOut?: () => void;
  /** Zoom to fit */
  onZoomToFit?: () => void;
  /** Zoom to selection */
  onZoomToSelection?: () => void;
  /** Toggle loop */
  onToggleLoop?: () => void;
  /** Set loop region from selection (Shift+L) */
  onSetLoopFromSelection?: () => void;
  /** Go to start */
  onGoToStart?: () => void;
  /** Go to end */
  onGoToEnd?: () => void;
  /** Go to left locator */
  onGoToLeftLocator?: () => void;
  /** Go to right locator */
  onGoToRightLocator?: () => void;
  /** Nudge left */
  onNudgeLeft?: () => void;
  /** Nudge right */
  onNudgeRight?: () => void;
  /** Toggle snap to grid */
  onToggleSnap?: () => void;
  /** Toggle metronome */
  onToggleMetronome?: () => void;
  /** Toggle mixer */
  onToggleMixer?: () => void;
  /** Toggle inspector/channel strip */
  onToggleInspector?: () => void;
  /** Toggle browser */
  onToggleBrowser?: () => void;
  /** Toggle transport bar */
  onToggleTransport?: () => void;
  /** Focus timeline */
  onFocusTimeline?: () => void;
  /** Focus mixer */
  onFocusMixer?: () => void;
  /** Add track */
  onAddTrack?: () => void;
  /** Remove track */
  onRemoveTrack?: () => void;
  /** Bounce selection */
  onBounce?: () => void;
  /** Normalize selection */
  onNormalize?: () => void;
  /** Reverse selection */
  onReverse?: () => void;
  /** Fade in */
  onFadeIn?: () => void;
  /** Fade out */
  onFadeOut?: () => void;
  /** Crossfade */
  onCrossfade?: () => void;
  /** Quantize */
  onQuantize?: () => void;
  /** Open preferences */
  onPreferences?: () => void;
  /** Toggle fullscreen */
  onFullscreen?: () => void;
  /** Custom shortcut handler */
  onCustom?: (key: string, modifiers: ShortcutModifiers) => boolean;
}

export interface ShortcutModifiers {
  ctrl: boolean;
  shift: boolean;
  alt: boolean;
  meta: boolean;
  cmd: boolean; // Alias for meta on Mac, ctrl on Windows
}

export interface UseGlobalShortcutsOptions {
  /** Whether shortcuts are enabled */
  enabled?: boolean;
  /** Elements that should not trigger shortcuts (e.g., inputs) */
  ignoreElements?: string[];
  /** Prevent default for handled shortcuts */
  preventDefault?: boolean;
}

// ============ Utility ============

const isMac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad|iPod/.test(navigator.platform);

function getModifiers(e: KeyboardEvent): ShortcutModifiers {
  return {
    ctrl: e.ctrlKey,
    shift: e.shiftKey,
    alt: e.altKey,
    meta: e.metaKey,
    cmd: isMac ? e.metaKey : e.ctrlKey,
  };
}

function shouldIgnoreEvent(e: KeyboardEvent, ignoreElements: string[]): boolean {
  const target = e.target as HTMLElement;

  // Always ignore when typing in input elements
  const tagName = target.tagName.toLowerCase();
  if (['input', 'textarea', 'select'].includes(tagName)) {
    // Allow shortcuts in input if it's a button or checkbox
    const inputType = target.getAttribute('type')?.toLowerCase();
    if (inputType !== 'button' && inputType !== 'checkbox' && inputType !== 'radio') {
      return true;
    }
  }

  // Check if element or parent is contenteditable
  if (target.isContentEditable) {
    return true;
  }

  // Check custom ignore selectors
  for (const selector of ignoreElements) {
    if (target.matches(selector) || target.closest(selector)) {
      return true;
    }
  }

  return false;
}

// ============ Hook ============

export function useGlobalShortcuts(
  actions: ShortcutAction,
  options: UseGlobalShortcutsOptions = {}
) {
  const {
    enabled = true,
    ignoreElements = [],
    preventDefault = true,
  } = options;

  const actionsRef = useRef(actions);
  actionsRef.current = actions;

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (!enabled) return;
    if (shouldIgnoreEvent(e, ignoreElements)) return;

    const mod = getModifiers(e);
    const key = e.key.toLowerCase();
    let handled = false;

    // Custom handler first
    if (actionsRef.current.onCustom?.(key, mod)) {
      handled = true;
    }
    // Space - Play/Pause (only if no modifiers)
    else if (key === ' ' && !mod.cmd && !mod.ctrl && !mod.alt) {
      actionsRef.current.onPlayPause?.();
      handled = true;
    }
    // Enter - Stop (with modifier)
    else if (key === 'enter' && mod.cmd) {
      actionsRef.current.onStop?.();
      handled = true;
    }
    // Cmd/Ctrl+S - Save
    else if (key === 's' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onSave?.();
      handled = true;
    }
    // Cmd/Ctrl+Z - Undo
    else if (key === 'z' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onUndo?.();
      handled = true;
    }
    // Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y - Redo
    else if ((key === 'z' && mod.cmd && mod.shift) || (key === 'y' && mod.cmd)) {
      actionsRef.current.onRedo?.();
      handled = true;
    }
    // Delete/Backspace - Delete selected
    else if ((key === 'delete' || key === 'backspace') && !mod.cmd && !mod.ctrl) {
      actionsRef.current.onDelete?.();
      handled = true;
    }
    // Escape - Deselect
    else if (key === 'escape') {
      actionsRef.current.onDeselect?.();
      handled = true;
    }
    // Cmd/Ctrl+A - Select all
    else if (key === 'a' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onSelectAll?.();
      handled = true;
    }
    // Cmd/Ctrl+X - Cut
    else if (key === 'x' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onCut?.();
      handled = true;
    }
    // Cmd/Ctrl+C - Copy
    else if (key === 'c' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onCopy?.();
      handled = true;
    }
    // Cmd/Ctrl+V - Paste
    else if (key === 'v' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onPaste?.();
      handled = true;
    }
    // Cmd/Ctrl+D - Duplicate
    else if (key === 'd' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onDuplicate?.();
      handled = true;
    }
    // Cmd/Ctrl+= or Cmd/Ctrl++ or H - Zoom in
    else if ((key === '=' || key === '+') && mod.cmd) {
      actionsRef.current.onZoomIn?.();
      handled = true;
    }
    // H - Zoom in (no modifiers)
    else if (key === 'h' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onZoomIn?.();
      handled = true;
    }
    // Cmd/Ctrl+- - Zoom out
    else if (key === '-' && mod.cmd) {
      actionsRef.current.onZoomOut?.();
      handled = true;
    }
    // G - Zoom out (no modifiers)
    else if (key === 'g' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onZoomOut?.();
      handled = true;
    }
    // Cmd/Ctrl+0 - Zoom to fit
    else if (key === '0' && mod.cmd) {
      actionsRef.current.onZoomToFit?.();
      handled = true;
    }
    // L - Toggle loop
    else if (key === 'l' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onToggleLoop?.();
      handled = true;
    }
    // Shift+L - Set loop from selection
    else if (key === 'l' && mod.shift && !mod.cmd && !mod.ctrl && !mod.alt) {
      actionsRef.current.onSetLoopFromSelection?.();
      handled = true;
    }
    // Home or Cmd/Ctrl+Left - Go to start
    else if (key === 'home' || (key === 'arrowleft' && mod.cmd)) {
      actionsRef.current.onGoToStart?.();
      handled = true;
    }
    // End or Cmd/Ctrl+Right - Go to end
    else if (key === 'end' || (key === 'arrowright' && mod.cmd)) {
      actionsRef.current.onGoToEnd?.();
      handled = true;
    }
    // R - Record (no modifiers) or Cmd+R (avoid browser refresh)
    else if (key === 'r' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onRecord?.();
      handled = true;
    }
    // Cmd/Ctrl+Shift+S - Save As
    else if (key === 's' && mod.cmd && mod.shift && !mod.alt) {
      actionsRef.current.onSaveAs?.();
      handled = true;
    }
    // Cmd/Ctrl+O - Open
    else if (key === 'o' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onOpen?.();
      handled = true;
    }
    // Cmd/Ctrl+N - New
    else if (key === 'n' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onNew?.();
      handled = true;
    }
    // Cmd/Ctrl+E - Export
    else if (key === 'e' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onExport?.();
      handled = true;
    }
    // S - Split at cursor (no modifiers)
    else if (key === 's' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onSplit?.();
      handled = true;
    }
    // T - Trim to selection
    else if (key === 't' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onTrim?.();
      handled = true;
    }
    // M - Mute selected
    else if (key === 'm' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onMute?.();
      handled = true;
    }
    // Solo - depends on DAW (Cubase: no key, Logic: S)
    // Using Alt+S to avoid conflict with Save
    else if (key === 's' && mod.alt && !mod.cmd && !mod.ctrl && !mod.shift) {
      actionsRef.current.onSolo?.();
      handled = true;
    }
    // A - Arm for recording (without modifiers, not Select All)
    else if (key === 'a' && mod.alt && !mod.cmd && !mod.ctrl && !mod.shift) {
      actionsRef.current.onArm?.();
      handled = true;
    }
    // Z - Zoom to selection
    else if (key === 'z' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onZoomToSelection?.();
      handled = true;
    }
    // 1 - Go to left locator
    else if (key === '1' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onGoToLeftLocator?.();
      handled = true;
    }
    // 2 - Go to right locator
    else if (key === '2' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onGoToRightLocator?.();
      handled = true;
    }
    // Arrow Left - Nudge left (with Alt for finer control)
    else if (key === 'arrowleft' && !mod.cmd && !mod.ctrl && !mod.shift) {
      actionsRef.current.onNudgeLeft?.();
      handled = true;
    }
    // Arrow Right - Nudge right
    else if (key === 'arrowright' && !mod.cmd && !mod.ctrl && !mod.shift) {
      actionsRef.current.onNudgeRight?.();
      handled = true;
    }
    // N - Toggle snap to grid
    else if (key === 'n' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onToggleSnap?.();
      handled = true;
    }
    // C - Toggle metronome/click
    else if (key === 'c' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onToggleMetronome?.();
      handled = true;
    }
    // F3 - Toggle mixer
    else if (key === 'f3') {
      actionsRef.current.onToggleMixer?.();
      handled = true;
    }
    // I - Toggle inspector/channel strip
    else if (key === 'i' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onToggleInspector?.();
      handled = true;
    }
    // B - Toggle browser
    else if (key === 'b' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onToggleBrowser?.();
      handled = true;
    }
    // F2 - Toggle transport
    else if (key === 'f2') {
      actionsRef.current.onToggleTransport?.();
      handled = true;
    }
    // F5 - Focus timeline
    else if (key === 'f5') {
      actionsRef.current.onFocusTimeline?.();
      handled = true;
    }
    // F6 - Focus mixer
    else if (key === 'f6') {
      actionsRef.current.onFocusMixer?.();
      handled = true;
    }
    // Cmd/Ctrl+T - Add track
    else if (key === 't' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onAddTrack?.();
      handled = true;
    }
    // Cmd/Ctrl+Shift+T - Remove track
    else if (key === 't' && mod.cmd && mod.shift && !mod.alt) {
      actionsRef.current.onRemoveTrack?.();
      handled = true;
    }
    // Cmd/Ctrl+B - Bounce selection
    else if (key === 'b' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onBounce?.();
      handled = true;
    }
    // Cmd/Ctrl+Shift+N - Normalize
    else if (key === 'n' && mod.cmd && mod.shift && !mod.alt) {
      actionsRef.current.onNormalize?.();
      handled = true;
    }
    // Cmd/Ctrl+Shift+R - Reverse
    else if (key === 'r' && mod.cmd && mod.shift && !mod.alt) {
      actionsRef.current.onReverse?.();
      handled = true;
    }
    // F - Fade in (no modifiers)
    else if (key === 'f' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onFadeIn?.();
      handled = true;
    }
    // Shift+F - Fade out
    else if (key === 'f' && mod.shift && !mod.cmd && !mod.ctrl && !mod.alt) {
      actionsRef.current.onFadeOut?.();
      handled = true;
    }
    // X - Crossfade (no modifiers)
    else if (key === 'x' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onCrossfade?.();
      handled = true;
    }
    // Q - Quantize
    else if (key === 'q' && !mod.cmd && !mod.ctrl && !mod.alt && !mod.shift) {
      actionsRef.current.onQuantize?.();
      handled = true;
    }
    // Cmd/Ctrl+, - Preferences
    else if (key === ',' && mod.cmd && !mod.shift && !mod.alt) {
      actionsRef.current.onPreferences?.();
      handled = true;
    }
    // F11 or Cmd/Ctrl+Shift+F - Fullscreen
    else if (key === 'f11' || (key === 'f' && mod.cmd && mod.shift && !mod.alt)) {
      actionsRef.current.onFullscreen?.();
      handled = true;
    }

    if (handled && preventDefault) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, [enabled, ignoreElements, preventDefault]);

  useEffect(() => {
    if (!enabled) return;

    document.addEventListener('keydown', handleKeyDown);

    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [enabled, handleKeyDown]);
}

// ============ Shortcut Display Helper ============

export function formatShortcut(key: string, mod?: Partial<ShortcutModifiers>): string {
  const parts: string[] = [];

  if (mod?.cmd) {
    parts.push(isMac ? '⌘' : 'Ctrl');
  }
  if (mod?.shift) {
    parts.push(isMac ? '⇧' : 'Shift');
  }
  if (mod?.alt) {
    parts.push(isMac ? '⌥' : 'Alt');
  }

  // Format special keys
  let displayKey = key;
  switch (key.toLowerCase()) {
    case ' ':
      displayKey = 'Space';
      break;
    case 'arrowup':
      displayKey = '↑';
      break;
    case 'arrowdown':
      displayKey = '↓';
      break;
    case 'arrowleft':
      displayKey = '←';
      break;
    case 'arrowright':
      displayKey = '→';
      break;
    case 'escape':
      displayKey = 'Esc';
      break;
    case 'backspace':
      displayKey = isMac ? '⌫' : 'Backspace';
      break;
    case 'delete':
      displayKey = isMac ? '⌦' : 'Del';
      break;
    case 'enter':
      displayKey = isMac ? '↵' : 'Enter';
      break;
    default:
      displayKey = key.length === 1 ? key.toUpperCase() : key;
  }

  parts.push(displayKey);

  return parts.join(isMac ? '' : '+');
}

// ============ Common Shortcut Definitions ============

export const SHORTCUTS = {
  // Transport
  playPause: { key: 'Space', display: formatShortcut(' ') },
  stop: { key: 'Enter', mod: { cmd: true }, display: formatShortcut('Enter', { cmd: true }) },
  record: { key: 'R', display: formatShortcut('R') },

  // File operations
  save: { key: 's', mod: { cmd: true }, display: formatShortcut('S', { cmd: true }) },
  saveAs: { key: 's', mod: { cmd: true, shift: true }, display: formatShortcut('S', { cmd: true, shift: true }) },
  open: { key: 'o', mod: { cmd: true }, display: formatShortcut('O', { cmd: true }) },
  new: { key: 'n', mod: { cmd: true }, display: formatShortcut('N', { cmd: true }) },
  export: { key: 'e', mod: { cmd: true }, display: formatShortcut('E', { cmd: true }) },

  // Edit
  undo: { key: 'z', mod: { cmd: true }, display: formatShortcut('Z', { cmd: true }) },
  redo: { key: 'z', mod: { cmd: true, shift: true }, display: formatShortcut('Z', { cmd: true, shift: true }) },
  delete: { key: 'Delete', display: formatShortcut('Delete') },
  selectAll: { key: 'a', mod: { cmd: true }, display: formatShortcut('A', { cmd: true }) },
  cut: { key: 'x', mod: { cmd: true }, display: formatShortcut('X', { cmd: true }) },
  copy: { key: 'c', mod: { cmd: true }, display: formatShortcut('C', { cmd: true }) },
  paste: { key: 'v', mod: { cmd: true }, display: formatShortcut('V', { cmd: true }) },
  duplicate: { key: 'd', mod: { cmd: true }, display: formatShortcut('D', { cmd: true }) },

  // Timeline editing
  split: { key: 'S', display: formatShortcut('S') },
  trim: { key: 'T', display: formatShortcut('T') },
  mute: { key: 'M', display: formatShortcut('M') },
  solo: { key: 's', mod: { alt: true }, display: formatShortcut('S', { alt: true }) },
  arm: { key: 'a', mod: { alt: true }, display: formatShortcut('A', { alt: true }) },

  // Zoom
  zoomIn: { key: 'H', display: 'H' },
  zoomInAlt: { key: '+', mod: { cmd: true }, display: formatShortcut('+', { cmd: true }) },
  zoomOut: { key: 'G', display: 'G' },
  zoomOutAlt: { key: '-', mod: { cmd: true }, display: formatShortcut('-', { cmd: true }) },
  zoomToFit: { key: '0', mod: { cmd: true }, display: formatShortcut('0', { cmd: true }) },
  zoomToSelection: { key: 'Z', display: formatShortcut('Z') },

  // Loop & Locators
  toggleLoop: { key: 'l', display: formatShortcut('L') },
  setLoopFromSelection: { key: 'l', mod: { shift: true }, display: formatShortcut('L', { shift: true }) },
  goToStart: { key: 'Home', display: formatShortcut('Home') },
  goToEnd: { key: 'End', display: formatShortcut('End') },
  goToLeftLocator: { key: '1', display: formatShortcut('1') },
  goToRightLocator: { key: '2', display: formatShortcut('2') },

  // Nudge
  nudgeLeft: { key: 'ArrowLeft', display: formatShortcut('arrowleft') },
  nudgeRight: { key: 'ArrowRight', display: formatShortcut('arrowright') },

  // Toggles
  toggleSnap: { key: 'N', display: formatShortcut('N') },
  toggleMetronome: { key: 'C', display: formatShortcut('C') },

  // Views
  toggleMixer: { key: 'F3', display: formatShortcut('F3') },
  toggleInspector: { key: 'I', display: formatShortcut('I') },
  toggleBrowser: { key: 'B', display: formatShortcut('B') },
  toggleTransport: { key: 'F2', display: formatShortcut('F2') },
  focusTimeline: { key: 'F5', display: formatShortcut('F5') },
  focusMixer: { key: 'F6', display: formatShortcut('F6') },

  // Track operations
  addTrack: { key: 't', mod: { cmd: true }, display: formatShortcut('T', { cmd: true }) },
  removeTrack: { key: 't', mod: { cmd: true, shift: true }, display: formatShortcut('T', { cmd: true, shift: true }) },

  // Audio processing
  bounce: { key: 'b', mod: { cmd: true }, display: formatShortcut('B', { cmd: true }) },
  normalize: { key: 'n', mod: { cmd: true, shift: true }, display: formatShortcut('N', { cmd: true, shift: true }) },
  reverse: { key: 'r', mod: { cmd: true, shift: true }, display: formatShortcut('R', { cmd: true, shift: true }) },

  // Fades
  fadeIn: { key: 'F', display: formatShortcut('F') },
  fadeOut: { key: 'f', mod: { shift: true }, display: formatShortcut('F', { shift: true }) },
  crossfade: { key: 'X', display: formatShortcut('X') },

  // Misc
  quantize: { key: 'Q', display: formatShortcut('Q') },
  preferences: { key: ',', mod: { cmd: true }, display: formatShortcut(',', { cmd: true }) },
  fullscreen: { key: 'F11', display: formatShortcut('F11') },
  escape: { key: 'Escape', display: formatShortcut('Escape') },
} as const;

export type ShortcutName = keyof typeof SHORTCUTS;

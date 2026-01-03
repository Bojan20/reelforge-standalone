/**
 * ReelForge Kbd
 *
 * Keyboard shortcut display:
 * - Single keys
 * - Key combinations
 * - Platform-aware symbols
 *
 * @module kbd/Kbd
 */

import './Kbd.css';

// ============ Types ============

export interface KbdProps {
  /** Key or keys to display */
  children: React.ReactNode;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

export interface KeyComboProps {
  /** Keys in combination */
  keys: string[];
  /** Separator */
  separator?: 'plus' | 'arrow' | 'space' | 'none';
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

// ============ Platform Detection ============

const isMac = typeof navigator !== 'undefined' && /Mac|iPod|iPhone|iPad/.test(navigator.platform);

// ============ Key Symbols ============

const KEY_SYMBOLS: Record<string, string> = {
  // Modifiers
  cmd: '⌘',
  command: '⌘',
  meta: isMac ? '⌘' : '⊞',
  ctrl: isMac ? '⌃' : 'Ctrl',
  control: isMac ? '⌃' : 'Ctrl',
  alt: isMac ? '⌥' : 'Alt',
  option: '⌥',
  shift: '⇧',

  // Special keys
  enter: '↵',
  return: '↵',
  tab: '⇥',
  backspace: '⌫',
  delete: '⌦',
  escape: 'Esc',
  esc: 'Esc',
  space: '␣',

  // Arrows
  up: '↑',
  down: '↓',
  left: '←',
  right: '→',
  arrowup: '↑',
  arrowdown: '↓',
  arrowleft: '←',
  arrowright: '→',

  // Function
  capslock: '⇪',
  fn: 'Fn',

  // Media
  volumeup: '🔊',
  volumedown: '🔉',
  mute: '🔇',
};

// ============ Component ============

export function Kbd({ children, size = 'medium', className = '' }: KbdProps) {
  const content = typeof children === 'string'
    ? KEY_SYMBOLS[children.toLowerCase()] || children
    : children;

  return (
    <kbd className={`kbd kbd--${size} ${className}`}>
      {content}
    </kbd>
  );
}

// ============ Key Combo ============

export function KeyCombo({
  keys,
  separator = 'plus',
  size = 'medium',
  className = '',
}: KeyComboProps) {
  const separatorContent = {
    plus: '+',
    arrow: '→',
    space: ' ',
    none: '',
  }[separator];

  return (
    <span className={`key-combo ${className}`}>
      {keys.map((key, index) => (
        <span key={index} className="key-combo__item">
          <Kbd size={size}>{key}</Kbd>
          {index < keys.length - 1 && separator !== 'none' && (
            <span className="key-combo__separator">{separatorContent}</span>
          )}
        </span>
      ))}
    </span>
  );
}

// ============ Shortcut Parser ============

export function parseShortcut(shortcut: string): string[] {
  return shortcut
    .split('+')
    .map((key) => key.trim())
    .filter(Boolean);
}

export function Shortcut({
  shortcut,
  size = 'medium',
  className = '',
}: {
  shortcut: string;
  size?: 'small' | 'medium' | 'large';
  className?: string;
}) {
  const keys = parseShortcut(shortcut);
  return <KeyCombo keys={keys} size={size} className={className} />;
}

export default Kbd;

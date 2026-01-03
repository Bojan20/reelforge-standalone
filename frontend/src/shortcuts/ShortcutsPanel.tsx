/**
 * ReelForge Shortcuts Panel
 *
 * UI component for viewing and customizing keyboard shortcuts.
 *
 * @module shortcuts/ShortcutsPanel
 */

import { useState, useCallback, useMemo } from 'react';
import type { ShortcutDefinition, ShortcutManager } from './useKeyboardShortcuts';
import './ShortcutsPanel.css';

// ============ Types ============

export interface ShortcutsPanelProps {
  /** Shortcut manager instance */
  manager: ShortcutManager;
  /** On close */
  onClose?: () => void;
  /** Allow editing */
  editable?: boolean;
}

// ============ Component ============

export function ShortcutsPanel({
  manager,
  onClose,
  editable = false,
}: ShortcutsPanelProps) {
  const [filter, setFilter] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [editingShortcut, setEditingShortcut] = useState<string | null>(null);

  // Get unique categories
  const categories = useMemo(() => {
    const cats = new Set<string>();
    for (const shortcut of manager.shortcuts) {
      if (shortcut.category) {
        cats.add(shortcut.category);
      }
    }
    return Array.from(cats).sort();
  }, [manager.shortcuts]);

  // Filter shortcuts
  const filteredShortcuts = useMemo(() => {
    let result = manager.shortcuts;

    if (selectedCategory) {
      result = result.filter((s) => s.category === selectedCategory);
    }

    if (filter) {
      const lowerFilter = filter.toLowerCase();
      result = result.filter(
        (s) =>
          s.name.toLowerCase().includes(lowerFilter) ||
          s.description?.toLowerCase().includes(lowerFilter) ||
          manager.formatShortcut(s).toLowerCase().includes(lowerFilter)
      );
    }

    return result;
  }, [manager, selectedCategory, filter]);

  // Group by category
  const groupedShortcuts = useMemo(() => {
    const groups = new Map<string, ShortcutDefinition[]>();

    for (const shortcut of filteredShortcuts) {
      const category = shortcut.category || 'Other';
      if (!groups.has(category)) {
        groups.set(category, []);
      }
      groups.get(category)!.push(shortcut);
    }

    return groups;
  }, [filteredShortcuts]);

  const handleKeyCapture = useCallback(
    (shortcutId: string, event: React.KeyboardEvent) => {
      event.preventDefault();
      event.stopPropagation();

      // Build modifier array
      const modifiers: Array<'ctrl' | 'shift' | 'alt' | 'meta'> = [];
      if (event.ctrlKey) modifiers.push('ctrl');
      if (event.shiftKey) modifiers.push('shift');
      if (event.altKey) modifiers.push('alt');
      if (event.metaKey) modifiers.push('meta');

      // Don't capture modifier-only keys
      if (['Control', 'Shift', 'Alt', 'Meta'].includes(event.key)) {
        return;
      }

      // Update shortcut
      manager.update(shortcutId, {
        key: event.code,
        modifiers: modifiers.length > 0 ? modifiers : undefined,
      });

      setEditingShortcut(null);
    },
    [manager]
  );

  return (
    <div className="shortcuts-panel">
      {/* Header */}
      <div className="shortcuts-panel__header">
        <h2>Keyboard Shortcuts</h2>
        {onClose && (
          <button className="shortcuts-panel__close" onClick={onClose}>
            ×
          </button>
        )}
      </div>

      {/* Search & Filter */}
      <div className="shortcuts-panel__filters">
        <input
          type="text"
          className="shortcuts-panel__search"
          placeholder="Search shortcuts..."
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <div className="shortcuts-panel__categories">
          <button
            className={`shortcuts-panel__category ${
              selectedCategory === null ? 'active' : ''
            }`}
            onClick={() => setSelectedCategory(null)}
          >
            All
          </button>
          {categories.map((cat) => (
            <button
              key={cat}
              className={`shortcuts-panel__category ${
                selectedCategory === cat ? 'active' : ''
              }`}
              onClick={() => setSelectedCategory(cat)}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* Shortcuts List */}
      <div className="shortcuts-panel__content">
        {Array.from(groupedShortcuts.entries()).map(([category, shortcuts]) => (
          <div key={category} className="shortcuts-panel__group">
            <h3 className="shortcuts-panel__group-title">{category}</h3>
            <div className="shortcuts-panel__list">
              {shortcuts.map((shortcut) => (
                <div key={shortcut.id} className="shortcuts-panel__item">
                  <div className="shortcuts-panel__item-info">
                    <span className="shortcuts-panel__item-name">
                      {shortcut.name}
                    </span>
                    {shortcut.description && (
                      <span className="shortcuts-panel__item-desc">
                        {shortcut.description}
                      </span>
                    )}
                    {shortcut.context && (
                      <span className="shortcuts-panel__item-context">
                        {shortcut.context}
                      </span>
                    )}
                  </div>
                  <div className="shortcuts-panel__item-key">
                    {editingShortcut === shortcut.id ? (
                      <input
                        type="text"
                        className="shortcuts-panel__key-input"
                        placeholder="Press key..."
                        autoFocus
                        onKeyDown={(e) => handleKeyCapture(shortcut.id, e)}
                        onBlur={() => setEditingShortcut(null)}
                        readOnly
                      />
                    ) : (
                      <kbd
                        className="shortcuts-panel__kbd"
                        onClick={() =>
                          editable && setEditingShortcut(shortcut.id)
                        }
                        style={{ cursor: editable ? 'pointer' : 'default' }}
                      >
                        {manager.formatShortcut(shortcut)}
                      </kbd>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}

        {filteredShortcuts.length === 0 && (
          <div className="shortcuts-panel__empty">
            No shortcuts found matching "{filter}"
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="shortcuts-panel__footer">
        <span className="shortcuts-panel__hint">
          {editable
            ? 'Click on a shortcut to change it'
            : 'Press ? to show this panel'}
        </span>
      </div>
    </div>
  );
}

export default ShortcutsPanel;

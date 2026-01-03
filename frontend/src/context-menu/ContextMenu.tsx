/**
 * ReelForge Context Menu
 *
 * Right-click context menu:
 * - Nested submenus
 * - Keyboard navigation
 * - Icons and shortcuts
 * - Separators
 * - Disabled items
 *
 * @module context-menu/ContextMenu
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import './ContextMenu.css';

// ============ Types ============

export interface MenuItem {
  /** Unique ID */
  id: string;
  /** Label */
  label: string;
  /** Icon */
  icon?: string;
  /** Keyboard shortcut display */
  shortcut?: string;
  /** Is disabled */
  disabled?: boolean;
  /** Is checked (for toggle items) */
  checked?: boolean;
  /** Submenu items */
  submenu?: MenuItem[];
  /** Is separator */
  separator?: boolean;
  /** On click handler */
  onClick?: () => void;
}

export interface ContextMenuProps {
  /** Menu items */
  items: MenuItem[];
  /** Position X */
  x: number;
  /** Position Y */
  y: number;
  /** On close */
  onClose: () => void;
}

// ============ Submenu Component ============

interface SubmenuProps {
  items: MenuItem[];
  parentRect: DOMRect;
  onClose: () => void;
  onItemClick: (item: MenuItem) => void;
}

function Submenu({ items, parentRect, onClose, onItemClick }: SubmenuProps) {
  const menuRef = useRef<HTMLDivElement>(null);
  const [activeSubmenu, setActiveSubmenu] = useState<string | null>(null);
  const [submenuRect, setSubmenuRect] = useState<DOMRect | null>(null);

  // Position submenu
  const [position, setPosition] = useState({ x: 0, y: 0 });

  useEffect(() => {
    if (!menuRef.current) return;

    const menuRect = menuRef.current.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    let x = parentRect.right;
    let y = parentRect.top;

    // Flip horizontally if needed
    if (x + menuRect.width > viewportWidth) {
      x = parentRect.left - menuRect.width;
    }

    // Adjust vertically if needed
    if (y + menuRect.height > viewportHeight) {
      y = viewportHeight - menuRect.height - 8;
    }

    setPosition({ x, y });
  }, [parentRect]);

  const handleMouseEnter = useCallback((item: MenuItem, e: React.MouseEvent) => {
    if (item.submenu) {
      setActiveSubmenu(item.id);
      setSubmenuRect((e.currentTarget as HTMLElement).getBoundingClientRect());
    } else {
      setActiveSubmenu(null);
    }
  }, []);

  return (
    <div
      ref={menuRef}
      className="context-menu context-menu--submenu"
      style={{ left: position.x, top: position.y }}
    >
      {items.map((item) => {
        if (item.separator) {
          return <div key={item.id} className="context-menu__separator" />;
        }

        return (
          <div
            key={item.id}
            className={`context-menu__item ${item.disabled ? 'context-menu__item--disabled' : ''} ${
              activeSubmenu === item.id ? 'context-menu__item--active' : ''
            }`}
            onClick={() => !item.disabled && !item.submenu && onItemClick(item)}
            onMouseEnter={(e) => handleMouseEnter(item, e)}
          >
            {item.icon && <span className="context-menu__icon">{item.icon}</span>}
            {item.checked !== undefined && (
              <span className="context-menu__check">{item.checked ? '✓' : ''}</span>
            )}
            <span className="context-menu__label">{item.label}</span>
            {item.shortcut && (
              <span className="context-menu__shortcut">{item.shortcut}</span>
            )}
            {item.submenu && <span className="context-menu__arrow">▶</span>}
          </div>
        );
      })}

      {/* Active submenu */}
      {activeSubmenu && submenuRect && (
        <Submenu
          items={items.find((i) => i.id === activeSubmenu)?.submenu || []}
          parentRect={submenuRect}
          onClose={onClose}
          onItemClick={onItemClick}
        />
      )}
    </div>
  );
}

// ============ Main Component ============

export function ContextMenu({ items, x, y, onClose }: ContextMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ x, y });
  const [activeSubmenu, setActiveSubmenu] = useState<string | null>(null);
  const [submenuRect, setSubmenuRect] = useState<DOMRect | null>(null);
  const [focusedIndex, setFocusedIndex] = useState(-1);

  // Adjust position to stay in viewport
  useEffect(() => {
    if (!menuRef.current) return;

    const menuRect = menuRef.current.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    let newX = x;
    let newY = y;

    if (x + menuRect.width > viewportWidth) {
      newX = viewportWidth - menuRect.width - 8;
    }

    if (y + menuRect.height > viewportHeight) {
      newY = viewportHeight - menuRect.height - 8;
    }

    setPosition({ x: newX, y: newY });
  }, [x, y]);

  // Close on outside click
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    const handleContextMenu = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClick);
    document.addEventListener('contextmenu', handleContextMenu);

    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('contextmenu', handleContextMenu);
    };
  }, [onClose]);

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const navigableItems = items.filter((i) => !i.separator && !i.disabled);

      switch (e.key) {
        case 'Escape':
          onClose();
          break;
        case 'ArrowDown':
          e.preventDefault();
          setFocusedIndex((prev) => {
            const next = prev + 1;
            return next >= navigableItems.length ? 0 : next;
          });
          break;
        case 'ArrowUp':
          e.preventDefault();
          setFocusedIndex((prev) => {
            const next = prev - 1;
            return next < 0 ? navigableItems.length - 1 : next;
          });
          break;
        case 'Enter':
          if (focusedIndex >= 0 && focusedIndex < navigableItems.length) {
            const item = navigableItems[focusedIndex];
            if (!item.submenu) {
              item.onClick?.();
              onClose();
            }
          }
          break;
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [items, focusedIndex, onClose]);

  // Handle item click
  const handleItemClick = useCallback(
    (item: MenuItem) => {
      if (item.disabled) return;
      item.onClick?.();
      onClose();
    },
    [onClose]
  );

  // Handle mouse enter
  const handleMouseEnter = useCallback((item: MenuItem, e: React.MouseEvent) => {
    if (item.submenu && !item.disabled) {
      setActiveSubmenu(item.id);
      setSubmenuRect((e.currentTarget as HTMLElement).getBoundingClientRect());
    } else {
      setActiveSubmenu(null);
    }
  }, []);

  // Get navigable index for focused state
  const getNavigableIndex = (item: MenuItem): number => {
    const navigableItems = items.filter((i) => !i.separator && !i.disabled);
    return navigableItems.findIndex((i) => i.id === item.id);
  };

  const menuContent = (
    <div
      ref={menuRef}
      className="context-menu"
      style={{ left: position.x, top: position.y }}
      role="menu"
    >
      {items.map((item) => {
        if (item.separator) {
          return <div key={item.id} className="context-menu__separator" />;
        }

        const navIndex = getNavigableIndex(item);
        const isFocused = navIndex === focusedIndex;

        return (
          <div
            key={item.id}
            className={`context-menu__item ${item.disabled ? 'context-menu__item--disabled' : ''} ${
              activeSubmenu === item.id ? 'context-menu__item--active' : ''
            } ${isFocused ? 'context-menu__item--focused' : ''}`}
            onClick={() => !item.submenu && handleItemClick(item)}
            onMouseEnter={(e) => handleMouseEnter(item, e)}
            role="menuitem"
            aria-disabled={item.disabled}
          >
            {item.icon && <span className="context-menu__icon">{item.icon}</span>}
            {item.checked !== undefined && (
              <span className="context-menu__check">{item.checked ? '✓' : ''}</span>
            )}
            <span className="context-menu__label">{item.label}</span>
            {item.shortcut && (
              <span className="context-menu__shortcut">{item.shortcut}</span>
            )}
            {item.submenu && <span className="context-menu__arrow">▶</span>}
          </div>
        );
      })}

      {/* Active submenu */}
      {activeSubmenu && submenuRect && (
        <Submenu
          items={items.find((i) => i.id === activeSubmenu)?.submenu || []}
          parentRect={submenuRect}
          onClose={onClose}
          onItemClick={handleItemClick}
        />
      )}
    </div>
  );

  return createPortal(menuContent, document.body);
}

export default ContextMenu;

/**
 * ReelForge Toolbar
 *
 * Toolbar component:
 * - Button groups
 * - Toggle buttons
 * - Dropdown menus
 * - Separators
 * - Tooltips
 *
 * @module toolbar/Toolbar
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Toolbar.css';

// ============ Types ============

export interface ToolbarItem {
  /** Unique ID */
  id: string;
  /** Item type */
  type: 'button' | 'toggle' | 'dropdown' | 'separator' | 'spacer';
  /** Label */
  label?: string;
  /** Icon */
  icon?: string;
  /** Tooltip */
  tooltip?: string;
  /** Is disabled */
  disabled?: boolean;
  /** Is active (for toggle) */
  active?: boolean;
  /** Dropdown items */
  dropdownItems?: DropdownItem[];
  /** On click */
  onClick?: () => void;
}

export interface DropdownItem {
  id: string;
  label: string;
  icon?: string;
  disabled?: boolean;
  checked?: boolean;
  separator?: boolean;
  onClick?: () => void;
}

export interface ToolbarProps {
  /** Toolbar items */
  items: ToolbarItem[];
  /** Toolbar size */
  size?: 'small' | 'medium' | 'large';
  /** Show labels */
  showLabels?: boolean;
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
}

// ============ Dropdown Component ============

interface ToolbarDropdownProps {
  items: DropdownItem[];
  onClose: () => void;
  anchorRect: DOMRect;
}

function ToolbarDropdown({ items, onClose, anchorRect }: ToolbarDropdownProps) {
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [onClose]);

  // Position
  const style = {
    top: anchorRect.bottom + 4,
    left: anchorRect.left,
  };

  return (
    <div ref={dropdownRef} className="toolbar-dropdown" style={style}>
      {items.map((item) => {
        if (item.separator) {
          return <div key={item.id} className="toolbar-dropdown__separator" />;
        }

        return (
          <div
            key={item.id}
            className={`toolbar-dropdown__item ${item.disabled ? 'toolbar-dropdown__item--disabled' : ''}`}
            onClick={() => {
              if (!item.disabled) {
                item.onClick?.();
                onClose();
              }
            }}
          >
            {item.icon && <span className="toolbar-dropdown__icon">{item.icon}</span>}
            {item.checked !== undefined && (
              <span className="toolbar-dropdown__check">{item.checked ? '✓' : ''}</span>
            )}
            <span className="toolbar-dropdown__label">{item.label}</span>
          </div>
        );
      })}
    </div>
  );
}

// ============ Button Component ============

interface ToolbarButtonProps {
  item: ToolbarItem;
  size: 'small' | 'medium' | 'large';
  showLabels: boolean;
}

function ToolbarButton({ item, size, showLabels }: ToolbarButtonProps) {
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [anchorRect, setAnchorRect] = useState<DOMRect | null>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);

  const handleClick = useCallback(() => {
    if (item.type === 'dropdown' && item.dropdownItems) {
      if (buttonRef.current) {
        setAnchorRect(buttonRef.current.getBoundingClientRect());
      }
      setIsDropdownOpen((prev) => !prev);
    } else {
      item.onClick?.();
    }
  }, [item]);

  const isActive = item.type === 'toggle' && item.active;

  return (
    <>
      <button
        ref={buttonRef}
        className={`toolbar-button toolbar-button--${size} ${isActive ? 'toolbar-button--active' : ''} ${
          item.disabled ? 'toolbar-button--disabled' : ''
        }`}
        onClick={handleClick}
        disabled={item.disabled}
        title={item.tooltip || item.label}
      >
        {item.icon && <span className="toolbar-button__icon">{item.icon}</span>}
        {showLabels && item.label && (
          <span className="toolbar-button__label">{item.label}</span>
        )}
        {item.type === 'dropdown' && <span className="toolbar-button__arrow">▼</span>}
      </button>

      {/* Dropdown */}
      {isDropdownOpen && anchorRect && item.dropdownItems && (
        <ToolbarDropdown
          items={item.dropdownItems}
          onClose={() => setIsDropdownOpen(false)}
          anchorRect={anchorRect}
        />
      )}
    </>
  );
}

// ============ Main Component ============

export function Toolbar({
  items,
  size = 'medium',
  showLabels = false,
  orientation = 'horizontal',
}: ToolbarProps) {
  return (
    <div className={`toolbar toolbar--${orientation} toolbar--${size}`}>
      {items.map((item) => {
        if (item.type === 'separator') {
          return <div key={item.id} className="toolbar__separator" />;
        }

        if (item.type === 'spacer') {
          return <div key={item.id} className="toolbar__spacer" />;
        }

        return (
          <ToolbarButton
            key={item.id}
            item={item}
            size={size}
            showLabels={showLabels}
          />
        );
      })}
    </div>
  );
}

export default Toolbar;

/**
 * ReelForge Dropdown
 *
 * Dropdown select component:
 * - Single and multi-select
 * - Searchable/filterable
 * - Keyboard navigation
 * - Groups and dividers
 * - Custom rendering
 *
 * @module dropdown/Dropdown
 */

import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { createPortal } from 'react-dom';
import './Dropdown.css';

// ============ Types ============

export interface DropdownOption {
  /** Value */
  value: string;
  /** Display label */
  label: string;
  /** Icon */
  icon?: string;
  /** Disabled */
  disabled?: boolean;
  /** Group */
  group?: string;
  /** Custom data */
  data?: unknown;
}

export interface DropdownProps {
  /** Options */
  options: DropdownOption[];
  /** Selected value(s) */
  value: string | string[];
  /** On change */
  onChange: (value: string | string[]) => void;
  /** Placeholder */
  placeholder?: string;
  /** Multi-select mode */
  multiple?: boolean;
  /** Searchable */
  searchable?: boolean;
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Max height of dropdown */
  maxHeight?: number;
  /** Custom class */
  className?: string;
  /** No options message */
  noOptionsMessage?: string;
  /** Custom option renderer */
  renderOption?: (option: DropdownOption, isSelected: boolean) => React.ReactNode;
}

// ============ Component ============

export function Dropdown({
  options,
  value,
  onChange,
  placeholder = 'Select...',
  multiple = false,
  searchable = false,
  disabled = false,
  size = 'medium',
  maxHeight = 300,
  className = '',
  noOptionsMessage = 'No options',
  renderOption,
}: DropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [highlightIndex, setHighlightIndex] = useState(-1);
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // Normalize value to array
  const selectedValues = useMemo(
    () => (Array.isArray(value) ? value : value ? [value] : []),
    [value]
  );

  // Filter options by search
  const filteredOptions = useMemo(() => {
    if (!search) return options;
    const lower = search.toLowerCase();
    return options.filter(
      (opt) =>
        opt.label.toLowerCase().includes(lower) ||
        opt.value.toLowerCase().includes(lower)
    );
  }, [options, search]);

  // Group options
  const groupedOptions = useMemo(() => {
    const groups = new Map<string, DropdownOption[]>();
    const ungrouped: DropdownOption[] = [];

    filteredOptions.forEach((opt) => {
      if (opt.group) {
        const group = groups.get(opt.group) || [];
        group.push(opt);
        groups.set(opt.group, group);
      } else {
        ungrouped.push(opt);
      }
    });

    return { groups, ungrouped };
  }, [filteredOptions]);

  // Get selected labels
  const selectedLabels = useMemo(() => {
    return selectedValues
      .map((v) => options.find((o) => o.value === v)?.label)
      .filter(Boolean)
      .join(', ');
  }, [selectedValues, options]);

  // Handle option select
  const handleSelect = useCallback(
    (option: DropdownOption) => {
      if (option.disabled) return;

      if (multiple) {
        const newValue = selectedValues.includes(option.value)
          ? selectedValues.filter((v) => v !== option.value)
          : [...selectedValues, option.value];
        onChange(newValue);
      } else {
        onChange(option.value);
        setIsOpen(false);
        setSearch('');
      }
    },
    [multiple, selectedValues, onChange]
  );

  // Handle keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (disabled) return;

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          if (!isOpen) {
            setIsOpen(true);
          } else {
            setHighlightIndex((prev) =>
              Math.min(prev + 1, filteredOptions.length - 1)
            );
          }
          break;

        case 'ArrowUp':
          e.preventDefault();
          setHighlightIndex((prev) => Math.max(prev - 1, 0));
          break;

        case 'Enter':
          e.preventDefault();
          if (isOpen && highlightIndex >= 0) {
            handleSelect(filteredOptions[highlightIndex]);
          } else {
            setIsOpen(true);
          }
          break;

        case 'Escape':
          setIsOpen(false);
          setSearch('');
          break;

        case 'Tab':
          setIsOpen(false);
          setSearch('');
          break;
      }
    },
    [disabled, isOpen, highlightIndex, filteredOptions, handleSelect]
  );

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;

    const handleClick = (e: MouseEvent) => {
      if (
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setIsOpen(false);
        setSearch('');
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isOpen]);

  // Scroll highlighted option into view
  useEffect(() => {
    if (highlightIndex >= 0 && listRef.current) {
      const item = listRef.current.children[highlightIndex] as HTMLElement;
      item?.scrollIntoView({ block: 'nearest' });
    }
  }, [highlightIndex]);

  // Focus input when opened
  useEffect(() => {
    if (isOpen && searchable && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isOpen, searchable]);

  // Reset highlight on search change
  useEffect(() => {
    setHighlightIndex(filteredOptions.length > 0 ? 0 : -1);
  }, [search, filteredOptions.length]);

  // Render option
  const renderOptionItem = (option: DropdownOption, index: number) => {
    const isSelected = selectedValues.includes(option.value);
    const isHighlighted = index === highlightIndex;

    return (
      <div
        key={option.value}
        className={`dropdown__option ${isSelected ? 'dropdown__option--selected' : ''} ${
          isHighlighted ? 'dropdown__option--highlighted' : ''
        } ${option.disabled ? 'dropdown__option--disabled' : ''}`}
        onClick={() => handleSelect(option)}
        onMouseEnter={() => setHighlightIndex(index)}
      >
        {renderOption ? (
          renderOption(option, isSelected)
        ) : (
          <>
            {multiple && (
              <span className="dropdown__checkbox">
                {isSelected ? '✓' : ''}
              </span>
            )}
            {option.icon && (
              <span className="dropdown__option-icon">{option.icon}</span>
            )}
            <span className="dropdown__option-label">{option.label}</span>
          </>
        )}
      </div>
    );
  };

  // Get dropdown position
  const getDropdownPosition = () => {
    if (!containerRef.current) return { top: 0, left: 0, width: 0 };
    const rect = containerRef.current.getBoundingClientRect();
    return {
      top: rect.bottom + 4,
      left: rect.left,
      width: rect.width,
    };
  };

  const position = isOpen ? getDropdownPosition() : { top: 0, left: 0, width: 0 };

  // Build flattened index for keyboard nav
  let optionIndex = 0;

  return (
    <div
      ref={containerRef}
      className={`dropdown dropdown--${size} ${isOpen ? 'dropdown--open' : ''} ${
        disabled ? 'dropdown--disabled' : ''
      } ${className}`}
      onKeyDown={handleKeyDown}
    >
      {/* Trigger */}
      <div
        className="dropdown__trigger"
        onClick={() => !disabled && setIsOpen(!isOpen)}
        tabIndex={disabled ? -1 : 0}
      >
        <span className={`dropdown__value ${!selectedLabels ? 'dropdown__value--placeholder' : ''}`}>
          {selectedLabels || placeholder}
        </span>
        <span className="dropdown__arrow">{isOpen ? '▲' : '▼'}</span>
      </div>

      {/* Dropdown */}
      {isOpen &&
        createPortal(
          <div
            className={`dropdown__menu dropdown__menu--${size}`}
            style={{
              top: position.top,
              left: position.left,
              width: position.width,
              maxHeight,
            }}
          >
            {/* Search */}
            {searchable && (
              <div className="dropdown__search">
                <input
                  ref={inputRef}
                  type="text"
                  className="dropdown__search-input"
                  placeholder="Search..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  onClick={(e) => e.stopPropagation()}
                />
              </div>
            )}

            {/* Options */}
            <div ref={listRef} className="dropdown__options">
              {filteredOptions.length === 0 ? (
                <div className="dropdown__empty">{noOptionsMessage}</div>
              ) : (
                <>
                  {/* Ungrouped options */}
                  {groupedOptions.ungrouped.map((opt) =>
                    renderOptionItem(opt, optionIndex++)
                  )}

                  {/* Grouped options */}
                  {Array.from(groupedOptions.groups.entries()).map(
                    ([groupName, groupOptions]) => (
                      <div key={groupName} className="dropdown__group">
                        <div className="dropdown__group-label">{groupName}</div>
                        {groupOptions.map((opt) =>
                          renderOptionItem(opt, optionIndex++)
                        )}
                      </div>
                    )
                  )}
                </>
              )}
            </div>
          </div>,
          document.body
        )}
    </div>
  );
}

export default Dropdown;

/**
 * ReelForge Select
 *
 * Custom select dropdown:
 * - Single/multi select
 * - Searchable
 * - Grouped options
 * - Custom rendering
 * - Keyboard navigation
 *
 * @module select/Select
 */

import { useState, useRef, useCallback, useEffect, useMemo } from 'react';
import './Select.css';

// ============ Types ============

export interface SelectOption<T = string> {
  /** Option value */
  value: T;
  /** Display label */
  label: string;
  /** Option disabled */
  disabled?: boolean;
  /** Group name */
  group?: string;
  /** Custom data */
  data?: Record<string, unknown>;
}

export interface SelectProps<T = string> {
  /** Options list */
  options: SelectOption<T>[];
  /** Selected value */
  value?: T | null;
  /** On value change */
  onChange?: (value: T | null, option: SelectOption<T> | null) => void;
  /** Placeholder text */
  placeholder?: string;
  /** Enable search */
  searchable?: boolean;
  /** Search placeholder */
  searchPlaceholder?: string;
  /** Clearable */
  clearable?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Loading state */
  loading?: boolean;
  /** No options message */
  noOptionsMessage?: string;
  /** Custom option renderer */
  renderOption?: (option: SelectOption<T>, isSelected: boolean) => React.ReactNode;
  /** Custom selected renderer */
  renderValue?: (option: SelectOption<T>) => React.ReactNode;
  /** Max dropdown height */
  maxHeight?: number;
  /** Custom class */
  className?: string;
}

export interface MultiSelectProps<T = string> {
  /** Options list */
  options: SelectOption<T>[];
  /** Selected values */
  value?: T[];
  /** On value change */
  onChange?: (values: T[], options: SelectOption<T>[]) => void;
  /** Placeholder text */
  placeholder?: string;
  /** Enable search */
  searchable?: boolean;
  /** Clearable */
  clearable?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Max selected to show */
  maxTagCount?: number;
  /** Custom class */
  className?: string;
}

// ============ Select Component ============

export function Select<T = string>({
  options,
  value,
  onChange,
  placeholder = 'Select...',
  searchable = false,
  searchPlaceholder = 'Search...',
  clearable = false,
  disabled = false,
  loading = false,
  noOptionsMessage = 'No options',
  renderOption,
  renderValue,
  maxHeight = 300,
  className = '',
}: SelectProps<T>) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [highlightedIndex, setHighlightedIndex] = useState(-1);

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // Find selected option
  const selectedOption = useMemo(
    () => options.find((opt) => opt.value === value) ?? null,
    [options, value]
  );

  // Filter options by search
  const filteredOptions = useMemo(() => {
    if (!search) return options;
    const lowerSearch = search.toLowerCase();
    return options.filter((opt) => opt.label.toLowerCase().includes(lowerSearch));
  }, [options, search]);

  // Group options
  const groupedOptions = useMemo(() => {
    const groups: Map<string, SelectOption<T>[]> = new Map();
    const ungrouped: SelectOption<T>[] = [];

    filteredOptions.forEach((opt) => {
      if (opt.group) {
        const existing = groups.get(opt.group) || [];
        existing.push(opt);
        groups.set(opt.group, existing);
      } else {
        ungrouped.push(opt);
      }
    });

    return { groups, ungrouped };
  }, [filteredOptions]);

  // Handle select
  const handleSelect = useCallback(
    (option: SelectOption<T>) => {
      if (option.disabled) return;
      onChange?.(option.value, option);
      setIsOpen(false);
      setSearch('');
    },
    [onChange]
  );

  // Handle clear
  const handleClear = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onChange?.(null, null);
    },
    [onChange]
  );

  // Toggle dropdown
  const toggleOpen = useCallback(() => {
    if (disabled) return;
    setIsOpen((prev) => !prev);
    if (!isOpen && searchable) {
      setTimeout(() => inputRef.current?.focus(), 0);
    }
  }, [disabled, isOpen, searchable]);

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;

    const handleClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) {
        setIsOpen(false);
        setSearch('');
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isOpen]);

  // Keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!isOpen) {
        if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') {
          e.preventDefault();
          setIsOpen(true);
        }
        return;
      }

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setHighlightedIndex((prev) =>
            prev < filteredOptions.length - 1 ? prev + 1 : 0
          );
          break;
        case 'ArrowUp':
          e.preventDefault();
          setHighlightedIndex((prev) =>
            prev > 0 ? prev - 1 : filteredOptions.length - 1
          );
          break;
        case 'Enter':
          e.preventDefault();
          if (highlightedIndex >= 0 && filteredOptions[highlightedIndex]) {
            handleSelect(filteredOptions[highlightedIndex]);
          }
          break;
        case 'Escape':
          e.preventDefault();
          setIsOpen(false);
          setSearch('');
          break;
      }
    },
    [isOpen, filteredOptions, highlightedIndex, handleSelect]
  );

  // Scroll to highlighted
  useEffect(() => {
    if (highlightedIndex >= 0 && listRef.current) {
      const item = listRef.current.children[highlightedIndex] as HTMLElement;
      if (item) {
        item.scrollIntoView({ block: 'nearest' });
      }
    }
  }, [highlightedIndex]);

  // Render option
  const renderOpt = (option: SelectOption<T>, index: number) => {
    const isSelected = option.value === value;
    const isHighlighted = index === highlightedIndex;

    return (
      <div
        key={String(option.value)}
        className={`select__option ${isSelected ? 'select__option--selected' : ''} ${
          isHighlighted ? 'select__option--highlighted' : ''
        } ${option.disabled ? 'select__option--disabled' : ''}`}
        onClick={() => handleSelect(option)}
        onMouseEnter={() => setHighlightedIndex(index)}
        role="option"
        aria-selected={isSelected}
        aria-disabled={option.disabled}
      >
        {renderOption ? renderOption(option, isSelected) : option.label}
        {isSelected && <span className="select__check">✓</span>}
      </div>
    );
  };

  return (
    <div
      ref={containerRef}
      className={`select ${isOpen ? 'select--open' : ''} ${
        disabled ? 'select--disabled' : ''
      } ${className}`}
      onKeyDown={handleKeyDown}
      tabIndex={disabled ? -1 : 0}
      role="combobox"
      aria-expanded={isOpen}
      aria-haspopup="listbox"
    >
      {/* Trigger */}
      <div className="select__trigger" onClick={toggleOpen}>
        <span className="select__value">
          {selectedOption
            ? renderValue
              ? renderValue(selectedOption)
              : selectedOption.label
            : placeholder}
        </span>

        {loading && <span className="select__spinner" />}

        {clearable && selectedOption && !loading && (
          <button
            type="button"
            className="select__clear"
            onClick={handleClear}
            aria-label="Clear"
          >
            ×
          </button>
        )}

        <span className={`select__arrow ${isOpen ? 'select__arrow--up' : ''}`}>
          ▾
        </span>
      </div>

      {/* Dropdown */}
      {isOpen && (
        <div className="select__dropdown" style={{ maxHeight }}>
          {/* Search */}
          {searchable && (
            <div className="select__search">
              <input
                ref={inputRef}
                type="text"
                className="select__search-input"
                placeholder={searchPlaceholder}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onClick={(e) => e.stopPropagation()}
              />
            </div>
          )}

          {/* Options */}
          <div ref={listRef} className="select__options" role="listbox">
            {filteredOptions.length === 0 ? (
              <div className="select__empty">{noOptionsMessage}</div>
            ) : (
              <>
                {/* Ungrouped options */}
                {groupedOptions.ungrouped.map((opt, i) => renderOpt(opt, i))}

                {/* Grouped options */}
                {Array.from(groupedOptions.groups.entries()).map(([group, opts]) => (
                  <div key={group} className="select__group">
                    <div className="select__group-label">{group}</div>
                    {opts.map((opt, i) =>
                      renderOpt(opt, groupedOptions.ungrouped.length + i)
                    )}
                  </div>
                ))}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ============ MultiSelect Component ============

export function MultiSelect<T = string>({
  options,
  value = [],
  onChange,
  placeholder = 'Select...',
  searchable = false,
  clearable = false,
  disabled = false,
  maxTagCount = 3,
  className = '',
}: MultiSelectProps<T>) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Selected options
  const selectedOptions = useMemo(
    () => options.filter((opt) => value.includes(opt.value)),
    [options, value]
  );

  // Filter options
  const filteredOptions = useMemo(() => {
    if (!search) return options;
    const lowerSearch = search.toLowerCase();
    return options.filter((opt) => opt.label.toLowerCase().includes(lowerSearch));
  }, [options, search]);

  // Toggle option
  const toggleOption = useCallback(
    (option: SelectOption<T>) => {
      if (option.disabled) return;

      const isSelected = value.includes(option.value);
      const newValues = isSelected
        ? value.filter((v) => v !== option.value)
        : [...value, option.value];

      const newOptions = options.filter((opt) => newValues.includes(opt.value));
      onChange?.(newValues, newOptions);
    },
    [value, options, onChange]
  );

  // Remove tag
  const removeTag = useCallback(
    (e: React.MouseEvent, optionValue: T) => {
      e.stopPropagation();
      const newValues = value.filter((v) => v !== optionValue);
      const newOptions = options.filter((opt) => newValues.includes(opt.value));
      onChange?.(newValues, newOptions);
    },
    [value, options, onChange]
  );

  // Clear all
  const handleClear = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onChange?.([], []);
    },
    [onChange]
  );

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;

    const handleClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) {
        setIsOpen(false);
        setSearch('');
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isOpen]);

  // Visible tags
  const visibleTags = selectedOptions.slice(0, maxTagCount);
  const hiddenCount = selectedOptions.length - maxTagCount;

  return (
    <div
      ref={containerRef}
      className={`multi-select ${isOpen ? 'multi-select--open' : ''} ${
        disabled ? 'multi-select--disabled' : ''
      } ${className}`}
    >
      {/* Trigger */}
      <div
        className="multi-select__trigger"
        onClick={() => !disabled && setIsOpen(!isOpen)}
      >
        <div className="multi-select__tags">
          {selectedOptions.length === 0 ? (
            <span className="multi-select__placeholder">{placeholder}</span>
          ) : (
            <>
              {visibleTags.map((opt) => (
                <span key={String(opt.value)} className="multi-select__tag">
                  {opt.label}
                  <button
                    type="button"
                    className="multi-select__tag-remove"
                    onClick={(e) => removeTag(e, opt.value)}
                  >
                    ×
                  </button>
                </span>
              ))}
              {hiddenCount > 0 && (
                <span className="multi-select__more">+{hiddenCount}</span>
              )}
            </>
          )}
        </div>

        {clearable && selectedOptions.length > 0 && (
          <button
            type="button"
            className="multi-select__clear"
            onClick={handleClear}
          >
            ×
          </button>
        )}

        <span className={`multi-select__arrow ${isOpen ? 'multi-select__arrow--up' : ''}`}>
          ▾
        </span>
      </div>

      {/* Dropdown */}
      {isOpen && (
        <div className="multi-select__dropdown">
          {searchable && (
            <div className="multi-select__search">
              <input
                ref={inputRef}
                type="text"
                className="multi-select__search-input"
                placeholder="Search..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onClick={(e) => e.stopPropagation()}
                autoFocus
              />
            </div>
          )}

          <div className="multi-select__options">
            {filteredOptions.length === 0 ? (
              <div className="multi-select__empty">No options</div>
            ) : (
              filteredOptions.map((opt) => {
                const isSelected = value.includes(opt.value);
                return (
                  <div
                    key={String(opt.value)}
                    className={`multi-select__option ${
                      isSelected ? 'multi-select__option--selected' : ''
                    } ${opt.disabled ? 'multi-select__option--disabled' : ''}`}
                    onClick={() => toggleOption(opt)}
                  >
                    <span
                      className={`multi-select__checkbox ${
                        isSelected ? 'multi-select__checkbox--checked' : ''
                      }`}
                    >
                      {isSelected && '✓'}
                    </span>
                    {opt.label}
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ============ NativeSelect Component ============

export interface NativeSelectProps {
  /** Options */
  options: Array<{ value: string; label: string; disabled?: boolean }>;
  /** Current value */
  value?: string;
  /** On change */
  onChange?: (value: string) => void;
  /** Placeholder */
  placeholder?: string;
  /** Disabled */
  disabled?: boolean;
  /** Required */
  required?: boolean;
  /** Name */
  name?: string;
  /** Custom class */
  className?: string;
}

export function NativeSelect({
  options,
  value,
  onChange,
  placeholder,
  disabled = false,
  required = false,
  name,
  className = '',
}: NativeSelectProps) {
  return (
    <select
      className={`native-select ${className}`}
      value={value}
      onChange={(e) => onChange?.(e.target.value)}
      disabled={disabled}
      required={required}
      name={name}
    >
      {placeholder && (
        <option value="" disabled>
          {placeholder}
        </option>
      )}
      {options.map((opt) => (
        <option key={opt.value} value={opt.value} disabled={opt.disabled}>
          {opt.label}
        </option>
      ))}
    </select>
  );
}

export default Select;

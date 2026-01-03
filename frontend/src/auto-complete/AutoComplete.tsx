/**
 * ReelForge AutoComplete
 *
 * Input with suggestions:
 * - Async data loading
 * - Keyboard navigation
 * - Custom render
 * - Highlight matching
 *
 * @module auto-complete/AutoComplete
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import './AutoComplete.css';

// ============ Types ============

export interface AutoCompleteOption {
  value: string;
  label?: string;
  disabled?: boolean;
}

export interface AutoCompleteProps {
  /** Current value */
  value?: string;
  /** On value change */
  onChange?: (value: string) => void;
  /** On select option */
  onSelect?: (value: string, option: AutoCompleteOption) => void;
  /** Options */
  options?: AutoCompleteOption[] | string[];
  /** Async load options */
  loadOptions?: (search: string) => Promise<AutoCompleteOption[]>;
  /** Filter options (default: contains) */
  filterOption?: boolean | ((input: string, option: AutoCompleteOption) => boolean);
  /** Placeholder */
  placeholder?: string;
  /** Disabled state */
  disabled?: boolean;
  /** Allow clear */
  allowClear?: boolean;
  /** Highlight match */
  highlightMatch?: boolean;
  /** Min chars to show options */
  minChars?: number;
  /** Debounce delay (ms) */
  debounceDelay?: number;
  /** Custom option render */
  renderOption?: (option: AutoCompleteOption, isHighlighted: boolean) => React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ AutoComplete Component ============

export function AutoComplete({
  value = '',
  onChange,
  onSelect,
  options = [],
  loadOptions,
  filterOption = true,
  placeholder = 'Type to search...',
  disabled = false,
  allowClear = true,
  highlightMatch = true,
  minChars = 0,
  debounceDelay = 300,
  renderOption,
  className = '',
}: AutoCompleteProps) {
  const [inputValue, setInputValue] = useState(value);
  const [isOpen, setIsOpen] = useState(false);
  const [highlightedIndex, setHighlightedIndex] = useState(-1);
  const [asyncOptions, setAsyncOptions] = useState<AutoCompleteOption[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  // Normalize options
  const normalizedOptions = useMemo((): AutoCompleteOption[] => {
    const opts = loadOptions ? asyncOptions : options;
    return opts.map((opt) =>
      typeof opt === 'string' ? { value: opt, label: opt } : opt
    );
  }, [options, asyncOptions, loadOptions]);

  // Filter options
  const filteredOptions = useMemo(() => {
    if (loadOptions) {
      return normalizedOptions; // Already filtered by server
    }

    if (filterOption === false) {
      return normalizedOptions;
    }

    const searchLower = inputValue.toLowerCase();

    if (typeof filterOption === 'function') {
      return normalizedOptions.filter((opt) => filterOption(inputValue, opt));
    }

    return normalizedOptions.filter((opt) => {
      const label = opt.label || opt.value;
      return label.toLowerCase().includes(searchLower);
    });
  }, [normalizedOptions, inputValue, filterOption, loadOptions]);

  // Sync external value
  useEffect(() => {
    setInputValue(value);
  }, [value]);

  // Load async options
  useEffect(() => {
    if (!loadOptions || inputValue.length < minChars) {
      setAsyncOptions([]);
      return;
    }

    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
    }

    debounceRef.current = setTimeout(async () => {
      setIsLoading(true);
      try {
        const result = await loadOptions(inputValue);
        setAsyncOptions(result);
      } catch (err) {
        console.error('AutoComplete loadOptions error:', err);
        setAsyncOptions([]);
      } finally {
        setIsLoading(false);
      }
    }, debounceDelay);

    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, [inputValue, loadOptions, minChars, debounceDelay]);

  // Handle input change
  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      setInputValue(newValue);
      onChange?.(newValue);
      setIsOpen(newValue.length >= minChars);
      setHighlightedIndex(-1);
    },
    [onChange, minChars]
  );

  // Handle option select
  const handleSelect = useCallback(
    (option: AutoCompleteOption) => {
      if (option.disabled) return;

      setInputValue(option.value);
      onChange?.(option.value);
      onSelect?.(option.value, option);
      setIsOpen(false);
      setHighlightedIndex(-1);
    },
    [onChange, onSelect]
  );

  // Handle clear
  const handleClear = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      setInputValue('');
      onChange?.('');
      inputRef.current?.focus();
    },
    [onChange]
  );

  // Keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!isOpen) {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          setIsOpen(true);
          return;
        }
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
          setIsOpen(false);
          setHighlightedIndex(-1);
          break;

        case 'Tab':
          setIsOpen(false);
          break;
      }
    },
    [isOpen, filteredOptions, highlightedIndex, handleSelect]
  );

  // Click outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Highlight matching text
  const highlightText = useCallback(
    (text: string) => {
      if (!highlightMatch || !inputValue) return text;

      const regex = new RegExp(`(${inputValue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
      const parts = text.split(regex);

      return parts.map((part, i) =>
        regex.test(part) ? (
          <mark key={i} className="auto-complete__highlight">
            {part}
          </mark>
        ) : (
          part
        )
      );
    },
    [inputValue, highlightMatch]
  );

  const showDropdown = isOpen && (filteredOptions.length > 0 || isLoading);

  return (
    <div
      ref={containerRef}
      className={`auto-complete ${showDropdown ? 'auto-complete--open' : ''} ${
        disabled ? 'auto-complete--disabled' : ''
      } ${className}`}
    >
      <div className="auto-complete__input-wrapper">
        <input
          ref={inputRef}
          type="text"
          className="auto-complete__input"
          value={inputValue}
          onChange={handleInputChange}
          onKeyDown={handleKeyDown}
          onFocus={() => inputValue.length >= minChars && setIsOpen(true)}
          placeholder={placeholder}
          disabled={disabled}
        />

        {isLoading && <span className="auto-complete__spinner" />}

        {allowClear && inputValue && !disabled && !isLoading && (
          <button type="button" className="auto-complete__clear" onClick={handleClear}>
            ×
          </button>
        )}
      </div>

      {showDropdown && (
        <div className="auto-complete__dropdown">
          {isLoading ? (
            <div className="auto-complete__loading">Loading...</div>
          ) : filteredOptions.length > 0 ? (
            <div className="auto-complete__options">
              {filteredOptions.map((option, index) => (
                <div
                  key={option.value}
                  className={`auto-complete__option ${
                    index === highlightedIndex ? 'auto-complete__option--highlighted' : ''
                  } ${option.disabled ? 'auto-complete__option--disabled' : ''}`}
                  onClick={() => handleSelect(option)}
                  onMouseEnter={() => setHighlightedIndex(index)}
                >
                  {renderOption
                    ? renderOption(option, index === highlightedIndex)
                    : highlightText(option.label || option.value)}
                </div>
              ))}
            </div>
          ) : (
            <div className="auto-complete__empty">No results found</div>
          )}
        </div>
      )}
    </div>
  );
}

export default AutoComplete;

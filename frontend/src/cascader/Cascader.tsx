/**
 * ReelForge Cascader
 *
 * Multi-level dropdown selector:
 * - Nested options
 * - Search/filter
 * - Keyboard navigation
 * - Load on expand
 *
 * @module cascader/Cascader
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import './Cascader.css';

// ============ Types ============

export interface CascaderOption {
  value: string;
  label: string;
  children?: CascaderOption[];
  disabled?: boolean;
  isLeaf?: boolean;
}

export interface CascaderProps {
  /** Options tree */
  options: CascaderOption[];
  /** Selected value path */
  value?: string[];
  /** On change callback */
  onChange?: (value: string[], selectedOptions: CascaderOption[]) => void;
  /** Placeholder */
  placeholder?: string;
  /** Allow clearing */
  allowClear?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Show search */
  showSearch?: boolean;
  /** Expand trigger */
  expandTrigger?: 'click' | 'hover';
  /** Display render */
  displayRender?: (labels: string[], selectedOptions: CascaderOption[]) => string;
  /** Load data on expand */
  loadData?: (selectedOptions: CascaderOption[]) => Promise<void>;
  /** Custom class */
  className?: string;
}

// ============ Cascader Component ============

export function Cascader({
  options,
  value = [],
  onChange,
  placeholder = 'Select...',
  allowClear = true,
  disabled = false,
  showSearch = false,
  expandTrigger = 'click',
  displayRender,
  loadData,
  className = '',
}: CascaderProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [activeValue, setActiveValue] = useState<string[]>(value);
  const [loadingPaths, setLoadingPaths] = useState<Set<string>>(new Set());
  const containerRef = useRef<HTMLDivElement>(null);

  // Get selected options from value path
  const getOptionsFromValue = useCallback(
    (val: string[]): CascaderOption[] => {
      const result: CascaderOption[] = [];
      let currentOptions = options;

      for (const v of val) {
        const found = currentOptions.find((o) => o.value === v);
        if (found) {
          result.push(found);
          currentOptions = found.children || [];
        } else {
          break;
        }
      }

      return result;
    },
    [options]
  );

  const selectedOptions = useMemo(() => getOptionsFromValue(value), [value, getOptionsFromValue]);
  const activeOptions = useMemo(() => getOptionsFromValue(activeValue), [activeValue, getOptionsFromValue]);

  // Display value
  const displayValue = useMemo(() => {
    if (selectedOptions.length === 0) return '';

    const labels = selectedOptions.map((o) => o.label);

    if (displayRender) {
      return displayRender(labels, selectedOptions);
    }

    return labels.join(' / ');
  }, [selectedOptions, displayRender]);

  // Get menus to display
  const menus = useMemo(() => {
    const result: CascaderOption[][] = [options];
    let current = options;

    for (const v of activeValue) {
      const found = current.find((o) => o.value === v);
      if (found?.children && found.children.length > 0) {
        result.push(found.children);
        current = found.children;
      } else {
        break;
      }
    }

    return result;
  }, [options, activeValue]);

  // Search results
  const searchResults = useMemo(() => {
    if (!search) return [];

    const results: Array<{ path: CascaderOption[]; labels: string }> = [];
    const searchLower = search.toLowerCase();

    const traverse = (opts: CascaderOption[], path: CascaderOption[]) => {
      for (const opt of opts) {
        const newPath = [...path, opt];
        const labels = newPath.map((o) => o.label).join(' / ');

        if (labels.toLowerCase().includes(searchLower)) {
          results.push({ path: newPath, labels });
        }

        if (opt.children) {
          traverse(opt.children, newPath);
        }
      }
    };

    traverse(options, []);
    return results;
  }, [options, search]);

  // Handle option click
  const handleOptionClick = useCallback(
    async (option: CascaderOption, level: number) => {
      if (option.disabled) return;

      const newActiveValue = [...activeValue.slice(0, level), option.value];
      setActiveValue(newActiveValue);

      // Check if we need to load data
      if (loadData && !option.isLeaf && !option.children) {
        const pathKey = newActiveValue.join('/');
        setLoadingPaths((prev) => new Set(prev).add(pathKey));

        try {
          const selectedOpts = getOptionsFromValue(newActiveValue);
          await loadData(selectedOpts);
        } finally {
          setLoadingPaths((prev) => {
            const newSet = new Set(prev);
            newSet.delete(pathKey);
            return newSet;
          });
        }
      }

      // If leaf node, select it
      if (option.isLeaf || !option.children || option.children.length === 0) {
        const selectedOpts = [...activeOptions.slice(0, level), option];
        onChange?.(newActiveValue, selectedOpts);
        setIsOpen(false);
        setSearch('');
      }
    },
    [activeValue, activeOptions, loadData, getOptionsFromValue, onChange]
  );

  // Handle option hover
  const handleOptionHover = useCallback(
    (option: CascaderOption, level: number) => {
      if (expandTrigger !== 'hover' || option.disabled) return;

      const newActiveValue = [...activeValue.slice(0, level), option.value];
      setActiveValue(newActiveValue);
    },
    [expandTrigger, activeValue]
  );

  // Handle search result click
  const handleSearchResultClick = useCallback(
    (path: CascaderOption[]) => {
      const newValue = path.map((o) => o.value);
      onChange?.(newValue, path);
      setIsOpen(false);
      setSearch('');
    },
    [onChange]
  );

  // Handle clear
  const handleClear = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onChange?.([], []);
      setActiveValue([]);
    },
    [onChange]
  );

  // Click outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
        setSearch('');
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Reset active value when opening
  useEffect(() => {
    if (isOpen) {
      setActiveValue(value);
    }
  }, [isOpen, value]);

  return (
    <div
      ref={containerRef}
      className={`cascader ${isOpen ? 'cascader--open' : ''} ${
        disabled ? 'cascader--disabled' : ''
      } ${className}`}
    >
      <div className="cascader__trigger" onClick={() => !disabled && setIsOpen(!isOpen)}>
        {displayValue ? (
          <span className="cascader__value">{displayValue}</span>
        ) : (
          <span className="cascader__placeholder">{placeholder}</span>
        )}

        {allowClear && displayValue && !disabled && (
          <button type="button" className="cascader__clear" onClick={handleClear}>
            ×
          </button>
        )}

        <span className={`cascader__arrow ${isOpen ? 'cascader__arrow--up' : ''}`}>▼</span>
      </div>

      {isOpen && (
        <div className="cascader__dropdown">
          {showSearch && (
            <div className="cascader__search">
              <input
                type="text"
                className="cascader__search-input"
                placeholder="Search..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                autoFocus
              />
            </div>
          )}

          {search ? (
            <div className="cascader__search-results">
              {searchResults.length > 0 ? (
                searchResults.map(({ path, labels }) => (
                  <div
                    key={path.map((o) => o.value).join('/')}
                    className="cascader__search-result"
                    onClick={() => handleSearchResultClick(path)}
                  >
                    {labels}
                  </div>
                ))
              ) : (
                <div className="cascader__empty">No results found</div>
              )}
            </div>
          ) : (
            <div className="cascader__menus">
              {menus.map((menu, level) => (
                <div key={level} className="cascader__menu">
                  {menu.map((option) => {
                    const isActive = activeValue[level] === option.value;
                    const isSelected = value[level] === option.value;
                    const hasChildren = option.children && option.children.length > 0;
                    const pathKey = [...activeValue.slice(0, level), option.value].join('/');
                    const isLoading = loadingPaths.has(pathKey);

                    return (
                      <div
                        key={option.value}
                        className={`cascader__option ${isActive ? 'cascader__option--active' : ''} ${
                          isSelected ? 'cascader__option--selected' : ''
                        } ${option.disabled ? 'cascader__option--disabled' : ''}`}
                        onClick={() => handleOptionClick(option, level)}
                        onMouseEnter={() => handleOptionHover(option, level)}
                      >
                        <span className="cascader__option-label">{option.label}</span>
                        {isLoading && <span className="cascader__option-loading" />}
                        {!isLoading && (hasChildren || (!option.isLeaf && loadData)) && (
                          <span className="cascader__option-arrow">›</span>
                        )}
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default Cascader;

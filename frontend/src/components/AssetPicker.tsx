/**
 * ReelForge M6.9 Asset Picker
 *
 * Searchable dropdown for selecting assets from the manifest.
 * Features:
 * - Debounced search (100ms)
 * - Virtual scrolling for large lists (>500 assets)
 * - Keyboard navigation
 * - Quick actions: Copy ID
 */

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import type { AssetMeta } from '../core/assetIndex';
import { createDebouncedSearch, AssetIndex } from '../core/assetIndex';
import './AssetPicker.css';

interface AssetPickerProps {
  /** Current asset ID value */
  value: string;
  /** Callback when value changes */
  onChange: (assetId: string) => void;
  /** Asset index for lookup */
  assetIndex: AssetIndex;
  /** CSS class name for error state */
  hasError?: boolean;
  /** Placeholder text */
  placeholder?: string;
  /** Auto-focus on mount */
  autoFocus?: boolean;
  /** Ref for external focus control */
  inputRef?: { current: HTMLInputElement | null };
}

// Virtual scrolling threshold
const VIRTUALIZATION_THRESHOLD = 500;
const VISIBLE_ITEMS = 8;
const ITEM_HEIGHT = 36;

export default function AssetPicker({
  value,
  onChange,
  assetIndex,
  hasError = false,
  placeholder = 'Search assets...',
  autoFocus = false,
  inputRef: externalInputRef,
}: AssetPickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [results, setResults] = useState<AssetMeta[]>([]);
  const [highlightedIndex, setHighlightedIndex] = useState(0);
  const [scrollOffset, setScrollOffset] = useState(0);
  const [isSearching, setIsSearching] = useState(false);

  const containerRef = useRef<HTMLDivElement>(null);
  const internalInputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const inputRef = externalInputRef || internalInputRef;

  // Debounced search
  const debouncedSearch = useMemo(
    () => createDebouncedSearch(assetIndex, 100),
    [assetIndex]
  );

  // Search when query changes
  useEffect(() => {
    if (!isOpen) return;

    setIsSearching(true);
    debouncedSearch(searchQuery).then((newResults) => {
      setResults(newResults);
      setHighlightedIndex(0);
      setScrollOffset(0);
      setIsSearching(false);
    });
  }, [searchQuery, isOpen, debouncedSearch]);

  // Load initial results when opening
  useEffect(() => {
    if (isOpen && searchQuery === '') {
      setResults(assetIndex.getAll().slice(0, 100));
    }
  }, [isOpen, searchQuery, assetIndex]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Handle keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!isOpen) {
        if (e.key === 'ArrowDown' || e.key === 'Enter') {
          e.preventDefault();
          setIsOpen(true);
        }
        return;
      }

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setHighlightedIndex((prev) => Math.min(prev + 1, results.length - 1));
          break;

        case 'ArrowUp':
          e.preventDefault();
          setHighlightedIndex((prev) => Math.max(prev - 1, 0));
          break;

        case 'Enter':
          e.preventDefault();
          if (results[highlightedIndex]) {
            selectAsset(results[highlightedIndex]);
          }
          break;

        case 'Escape':
          e.preventDefault();
          setIsOpen(false);
          break;

        case 'Tab':
          setIsOpen(false);
          break;
      }
    },
    [isOpen, results, highlightedIndex]
  );

  // Keep highlighted item in view
  useEffect(() => {
    if (results.length > VIRTUALIZATION_THRESHOLD) {
      // Virtual scrolling: adjust scroll offset
      if (highlightedIndex < scrollOffset) {
        setScrollOffset(highlightedIndex);
      } else if (highlightedIndex >= scrollOffset + VISIBLE_ITEMS) {
        setScrollOffset(highlightedIndex - VISIBLE_ITEMS + 1);
      }
    } else {
      // Non-virtual: scroll into view
      const list = listRef.current;
      if (list) {
        const item = list.children[highlightedIndex] as HTMLElement;
        if (item) {
          item.scrollIntoView({ block: 'nearest' });
        }
      }
    }
  }, [highlightedIndex, results.length, scrollOffset]);

  const selectAsset = useCallback(
    (asset: AssetMeta) => {
      onChange(asset.id);
      setSearchQuery('');
      setIsOpen(false);
      inputRef.current?.blur();
    },
    [onChange, inputRef]
  );

  const handleCopyId = useCallback(
    (e: React.MouseEvent, assetId: string) => {
      e.stopPropagation();
      navigator.clipboard.writeText(assetId);
    },
    []
  );

  const handleInputChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchQuery(e.target.value);
    if (!isOpen) {
      setIsOpen(true);
    }
  }, [isOpen]);

  const handleInputFocus = useCallback(() => {
    setIsOpen(true);
    setSearchQuery('');
  }, []);

  // Use virtualization for large lists
  const useVirtualization = results.length > VIRTUALIZATION_THRESHOLD;
  const visibleResults = useVirtualization
    ? results.slice(scrollOffset, scrollOffset + VISIBLE_ITEMS)
    : results;

  // Get display value
  const displayValue = isOpen ? searchQuery : value;
  const currentAsset = value ? assetIndex.get(value) : undefined;

  return (
    <div
      className={`rf-asset-picker ${isOpen ? 'is-open' : ''} ${hasError ? 'has-error' : ''}`}
      ref={containerRef}
    >
      <div className="rf-asset-picker-input-wrapper">
        <input
          ref={inputRef}
          type="text"
          className="rf-asset-picker-input"
          value={displayValue}
          onChange={handleInputChange}
          onFocus={handleInputFocus}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          autoFocus={autoFocus}
        />
        <button
          type="button"
          className="rf-asset-picker-toggle"
          onClick={() => setIsOpen(!isOpen)}
          tabIndex={-1}
        >
          {isOpen ? '▲' : '▼'}
        </button>
      </div>

      {/* Current value info */}
      {!isOpen && value && currentAsset?.path && (
        <div className="rf-asset-picker-path">{currentAsset.path}</div>
      )}

      {/* Dropdown */}
      {isOpen && (
        <div className="rf-asset-picker-dropdown">
          {isSearching && (
            <div className="rf-asset-picker-loading">Searching...</div>
          )}

          {!isSearching && results.length === 0 && (
            <div className="rf-asset-picker-empty">
              {searchQuery ? `No assets matching "${searchQuery}"` : 'No assets available'}
            </div>
          )}

          {!isSearching && results.length > 0 && (
            <>
              <div className="rf-asset-picker-count">
                {results.length} asset{results.length !== 1 ? 's' : ''}
                {useVirtualization && ` (showing ${scrollOffset + 1}-${Math.min(scrollOffset + VISIBLE_ITEMS, results.length)})`}
              </div>

              <div
                className="rf-asset-picker-list"
                ref={listRef}
                style={
                  useVirtualization
                    ? {
                        height: VISIBLE_ITEMS * ITEM_HEIGHT,
                        position: 'relative',
                      }
                    : { maxHeight: VISIBLE_ITEMS * ITEM_HEIGHT }
                }
                onScroll={(e) => {
                  if (useVirtualization) {
                    const newOffset = Math.floor(
                      (e.target as HTMLDivElement).scrollTop / ITEM_HEIGHT
                    );
                    setScrollOffset(newOffset);
                  }
                }}
              >
                {useVirtualization && (
                  <div style={{ height: scrollOffset * ITEM_HEIGHT }} />
                )}

                {visibleResults.map((asset, idx) => {
                  const actualIndex = useVirtualization ? scrollOffset + idx : idx;
                  const isHighlighted = actualIndex === highlightedIndex;
                  const isSelected = asset.id === value;

                  return (
                    <div
                      key={asset.id}
                      className={`rf-asset-picker-item ${isHighlighted ? 'is-highlighted' : ''} ${isSelected ? 'is-selected' : ''}`}
                      onClick={() => selectAsset(asset)}
                      onMouseEnter={() => setHighlightedIndex(actualIndex)}
                    >
                      <div className="rf-asset-picker-item-main">
                        <span className="rf-asset-picker-item-id">{asset.id}</span>
                        {asset.path && (
                          <span className="rf-asset-picker-item-path">{asset.path}</span>
                        )}
                      </div>
                      <button
                        type="button"
                        className="rf-asset-picker-item-copy"
                        onClick={(e) => handleCopyId(e, asset.id)}
                        title="Copy asset ID"
                      >
                        📋
                      </button>
                    </div>
                  );
                })}

                {useVirtualization && (
                  <div
                    style={{
                      height: (results.length - scrollOffset - VISIBLE_ITEMS) * ITEM_HEIGHT,
                    }}
                  />
                )}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

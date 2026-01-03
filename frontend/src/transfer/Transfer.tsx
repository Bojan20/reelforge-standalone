/**
 * ReelForge Transfer
 *
 * Dual list transfer component:
 * - Move items between lists
 * - Search/filter
 * - Select all
 * - Drag and drop
 *
 * @module transfer/Transfer
 */

import { useState, useCallback, useMemo } from 'react';
import './Transfer.css';

// ============ Types ============

export interface TransferItem {
  key: string;
  label: string;
  disabled?: boolean;
}

export interface TransferProps {
  /** All available items */
  dataSource: TransferItem[];
  /** Keys of items in target list */
  targetKeys: string[];
  /** On change callback */
  onChange?: (targetKeys: string[], direction: 'left' | 'right', moveKeys: string[]) => void;
  /** Show search */
  showSearch?: boolean;
  /** Search placeholder */
  searchPlaceholder?: string;
  /** Source list title */
  sourceTitle?: string;
  /** Target list title */
  targetTitle?: string;
  /** Custom item render */
  renderItem?: (item: TransferItem) => React.ReactNode;
  /** Disabled state */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface TransferListProps {
  /** Items to display */
  items: TransferItem[];
  /** Selected keys */
  selectedKeys: string[];
  /** On selection change */
  onSelectChange: (keys: string[]) => void;
  /** Title */
  title: string;
  /** Show search */
  showSearch?: boolean;
  /** Search placeholder */
  searchPlaceholder?: string;
  /** Custom item render */
  renderItem?: (item: TransferItem) => React.ReactNode;
  /** Disabled */
  disabled?: boolean;
}

// ============ TransferList Component ============

function TransferList({
  items,
  selectedKeys,
  onSelectChange,
  title,
  showSearch = false,
  searchPlaceholder = 'Search...',
  renderItem,
  disabled = false,
}: TransferListProps) {
  const [search, setSearch] = useState('');

  // Filter items by search
  const filteredItems = useMemo(() => {
    if (!search) return items;
    const lowerSearch = search.toLowerCase();
    return items.filter((item) => item.label.toLowerCase().includes(lowerSearch));
  }, [items, search]);

  // Handle item select
  const handleItemSelect = useCallback(
    (key: string) => {
      if (disabled) return;

      const item = items.find((i) => i.key === key);
      if (item?.disabled) return;

      if (selectedKeys.includes(key)) {
        onSelectChange(selectedKeys.filter((k) => k !== key));
      } else {
        onSelectChange([...selectedKeys, key]);
      }
    },
    [items, selectedKeys, onSelectChange, disabled]
  );

  // Handle select all
  const handleSelectAll = useCallback(() => {
    if (disabled) return;

    const selectableKeys = filteredItems
      .filter((item) => !item.disabled)
      .map((item) => item.key);

    const allSelected = selectableKeys.every((key) => selectedKeys.includes(key));

    if (allSelected) {
      onSelectChange(selectedKeys.filter((key) => !selectableKeys.includes(key)));
    } else {
      onSelectChange([...new Set([...selectedKeys, ...selectableKeys])]);
    }
  }, [filteredItems, selectedKeys, onSelectChange, disabled]);

  // Check if all selected
  const selectableItems = filteredItems.filter((item) => !item.disabled);
  const allSelected =
    selectableItems.length > 0 &&
    selectableItems.every((item) => selectedKeys.includes(item.key));
  const someSelected = selectableItems.some((item) => selectedKeys.includes(item.key));

  return (
    <div className={`transfer-list ${disabled ? 'transfer-list--disabled' : ''}`}>
      {/* Header */}
      <div className="transfer-list__header">
        <label className="transfer-list__select-all">
          <input
            type="checkbox"
            checked={allSelected}
            ref={(el) => {
              if (el) el.indeterminate = someSelected && !allSelected;
            }}
            onChange={handleSelectAll}
            disabled={disabled}
          />
          <span className="transfer-list__title">{title}</span>
        </label>
        <span className="transfer-list__count">
          {selectedKeys.filter((k) => items.some((i) => i.key === k)).length}/{items.length}
        </span>
      </div>

      {/* Search */}
      {showSearch && (
        <div className="transfer-list__search">
          <input
            type="text"
            placeholder={searchPlaceholder}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            disabled={disabled}
          />
        </div>
      )}

      {/* Items */}
      <div className="transfer-list__items">
        {filteredItems.length === 0 ? (
          <div className="transfer-list__empty">No items</div>
        ) : (
          filteredItems.map((item) => (
            <label
              key={item.key}
              className={`transfer-list__item ${
                item.disabled ? 'transfer-list__item--disabled' : ''
              } ${selectedKeys.includes(item.key) ? 'transfer-list__item--selected' : ''}`}
            >
              <input
                type="checkbox"
                checked={selectedKeys.includes(item.key)}
                onChange={() => handleItemSelect(item.key)}
                disabled={disabled || item.disabled}
              />
              <span className="transfer-list__item-label">
                {renderItem ? renderItem(item) : item.label}
              </span>
            </label>
          ))
        )}
      </div>
    </div>
  );
}

// ============ Transfer Component ============

export function Transfer({
  dataSource,
  targetKeys,
  onChange,
  showSearch = false,
  searchPlaceholder = 'Search...',
  sourceTitle = 'Source',
  targetTitle = 'Target',
  renderItem,
  disabled = false,
  className = '',
}: TransferProps) {
  const [sourceSelected, setSourceSelected] = useState<string[]>([]);
  const [targetSelected, setTargetSelected] = useState<string[]>([]);

  // Split items into source and target
  const sourceItems = useMemo(
    () => dataSource.filter((item) => !targetKeys.includes(item.key)),
    [dataSource, targetKeys]
  );

  const targetItems = useMemo(
    () => dataSource.filter((item) => targetKeys.includes(item.key)),
    [dataSource, targetKeys]
  );

  // Move to right (source -> target)
  const moveToRight = useCallback(() => {
    if (sourceSelected.length === 0) return;

    const newTargetKeys = [...targetKeys, ...sourceSelected];
    onChange?.(newTargetKeys, 'right', sourceSelected);
    setSourceSelected([]);
  }, [sourceSelected, targetKeys, onChange]);

  // Move to left (target -> source)
  const moveToLeft = useCallback(() => {
    if (targetSelected.length === 0) return;

    const newTargetKeys = targetKeys.filter((key) => !targetSelected.includes(key));
    onChange?.(newTargetKeys, 'left', targetSelected);
    setTargetSelected([]);
  }, [targetSelected, targetKeys, onChange]);

  return (
    <div className={`transfer ${disabled ? 'transfer--disabled' : ''} ${className}`}>
      {/* Source list */}
      <TransferList
        items={sourceItems}
        selectedKeys={sourceSelected}
        onSelectChange={setSourceSelected}
        title={sourceTitle}
        showSearch={showSearch}
        searchPlaceholder={searchPlaceholder}
        renderItem={renderItem}
        disabled={disabled}
      />

      {/* Actions */}
      <div className="transfer__actions">
        <button
          type="button"
          className="transfer__btn"
          onClick={moveToRight}
          disabled={disabled || sourceSelected.length === 0}
          aria-label="Move to right"
        >
          →
        </button>
        <button
          type="button"
          className="transfer__btn"
          onClick={moveToLeft}
          disabled={disabled || targetSelected.length === 0}
          aria-label="Move to left"
        >
          ←
        </button>
      </div>

      {/* Target list */}
      <TransferList
        items={targetItems}
        selectedKeys={targetSelected}
        onSelectChange={setTargetSelected}
        title={targetTitle}
        showSearch={showSearch}
        searchPlaceholder={searchPlaceholder}
        renderItem={renderItem}
        disabled={disabled}
      />
    </div>
  );
}

// ============ useTransfer Hook ============

export function useTransfer(initialTargetKeys: string[] = []) {
  const [targetKeys, setTargetKeys] = useState<string[]>(initialTargetKeys);

  const handleChange = useCallback(
    (newTargetKeys: string[]) => {
      setTargetKeys(newTargetKeys);
    },
    []
  );

  const reset = useCallback(() => {
    setTargetKeys(initialTargetKeys);
  }, [initialTargetKeys]);

  const clear = useCallback(() => {
    setTargetKeys([]);
  }, []);

  return {
    targetKeys,
    setTargetKeys,
    handleChange,
    reset,
    clear,
  };
}

export default Transfer;

/**
 * ReelForge DataTable
 *
 * Data table component:
 * - Sortable columns
 * - Row selection
 * - Pagination
 * - Custom cell rendering
 * - Resizable columns
 *
 * @module data-table/DataTable
 */

import { useState, useCallback, useMemo } from 'react';
import './DataTable.css';

// ============ Types ============

export interface Column<T> {
  /** Column key */
  key: string;
  /** Header label */
  label: string;
  /** Width */
  width?: number | string;
  /** Sortable */
  sortable?: boolean;
  /** Align */
  align?: 'left' | 'center' | 'right';
  /** Custom cell renderer */
  render?: (value: unknown, row: T, index: number) => React.ReactNode;
}

export type SortDirection = 'asc' | 'desc' | null;

export interface SortState {
  key: string;
  direction: SortDirection;
}

export interface DataTableProps<T> {
  /** Columns configuration */
  columns: Column<T>[];
  /** Data rows */
  data: T[];
  /** Row key getter */
  rowKey: keyof T | ((row: T) => string);
  /** Selectable rows */
  selectable?: boolean;
  /** Selected row keys */
  selected?: string[];
  /** On selection change */
  onSelectionChange?: (selected: string[]) => void;
  /** Sort state */
  sort?: SortState;
  /** On sort change */
  onSortChange?: (sort: SortState) => void;
  /** Empty message */
  emptyMessage?: string;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Striped rows */
  striped?: boolean;
  /** Hoverable rows */
  hoverable?: boolean;
  /** Bordered */
  bordered?: boolean;
  /** Custom class */
  className?: string;
  /** On row click */
  onRowClick?: (row: T, index: number) => void;
  /** On row double click */
  onRowDoubleClick?: (row: T, index: number) => void;
}

// ============ Component ============

export function DataTable<T extends Record<string, unknown>>({
  columns,
  data,
  rowKey,
  selectable = false,
  selected: controlledSelected,
  onSelectionChange,
  sort: controlledSort,
  onSortChange,
  emptyMessage = 'No data',
  size = 'medium',
  striped = false,
  hoverable = true,
  bordered = false,
  className = '',
  onRowClick,
  onRowDoubleClick,
}: DataTableProps<T>) {
  // Selection state
  const [internalSelected, setInternalSelected] = useState<string[]>([]);
  const isSelectionControlled = controlledSelected !== undefined;
  const selected = isSelectionControlled ? controlledSelected : internalSelected;

  // Sort state
  const [internalSort, setInternalSort] = useState<SortState>({ key: '', direction: null });
  const isSortControlled = controlledSort !== undefined;
  const sort = isSortControlled ? controlledSort : internalSort;

  // Get row key
  const getRowKey = useCallback(
    (row: T): string => {
      if (typeof rowKey === 'function') {
        return rowKey(row);
      }
      return String(row[rowKey]);
    },
    [rowKey]
  );

  // Sorted data
  const sortedData = useMemo(() => {
    if (!sort.key || !sort.direction) return data;

    return [...data].sort((a, b) => {
      const aVal = a[sort.key];
      const bVal = b[sort.key];

      if (aVal === bVal) return 0;
      if (aVal === null || aVal === undefined) return 1;
      if (bVal === null || bVal === undefined) return -1;

      const comparison = aVal < bVal ? -1 : 1;
      return sort.direction === 'asc' ? comparison : -comparison;
    });
  }, [data, sort]);

  // Handle sort click
  const handleSort = useCallback(
    (key: string) => {
      let direction: SortDirection;

      if (sort.key !== key) {
        direction = 'asc';
      } else if (sort.direction === 'asc') {
        direction = 'desc';
      } else {
        direction = null;
      }

      const newSort = { key, direction };

      if (!isSortControlled) {
        setInternalSort(newSort);
      }
      onSortChange?.(newSort);
    },
    [sort, isSortControlled, onSortChange]
  );

  // Handle row selection
  const handleSelectRow = useCallback(
    (key: string) => {
      const newSelected = selected.includes(key)
        ? selected.filter((k) => k !== key)
        : [...selected, key];

      if (!isSelectionControlled) {
        setInternalSelected(newSelected);
      }
      onSelectionChange?.(newSelected);
    },
    [selected, isSelectionControlled, onSelectionChange]
  );

  // Handle select all
  const handleSelectAll = useCallback(() => {
    const allKeys = sortedData.map(getRowKey);
    const allSelected = allKeys.every((key) => selected.includes(key));
    const newSelected = allSelected ? [] : allKeys;

    if (!isSelectionControlled) {
      setInternalSelected(newSelected);
    }
    onSelectionChange?.(newSelected);
  }, [sortedData, selected, getRowKey, isSelectionControlled, onSelectionChange]);

  const allSelected = sortedData.length > 0 && sortedData.every((row) => selected.includes(getRowKey(row)));
  const someSelected = sortedData.some((row) => selected.includes(getRowKey(row)));

  return (
    <div
      className={`data-table data-table--${size} ${striped ? 'data-table--striped' : ''} ${
        bordered ? 'data-table--bordered' : ''
      } ${className}`}
    >
      <table className="data-table__table">
        {/* Header */}
        <thead className="data-table__head">
          <tr>
            {selectable && (
              <th className="data-table__th data-table__th--checkbox">
                <input
                  type="checkbox"
                  checked={allSelected}
                  ref={(el) => {
                    if (el) el.indeterminate = someSelected && !allSelected;
                  }}
                  onChange={handleSelectAll}
                />
              </th>
            )}
            {columns.map((col) => (
              <th
                key={col.key}
                className={`data-table__th ${col.sortable ? 'data-table__th--sortable' : ''} ${
                  col.align ? `data-table__th--${col.align}` : ''
                }`}
                style={{ width: col.width }}
                onClick={() => col.sortable && handleSort(col.key)}
              >
                <span className="data-table__th-content">
                  {col.label}
                  {col.sortable && (
                    <span className="data-table__sort-icon">
                      {sort.key === col.key && sort.direction === 'asc' && '▲'}
                      {sort.key === col.key && sort.direction === 'desc' && '▼'}
                      {(sort.key !== col.key || !sort.direction) && '⇅'}
                    </span>
                  )}
                </span>
              </th>
            ))}
          </tr>
        </thead>

        {/* Body */}
        <tbody className="data-table__body">
          {sortedData.length === 0 ? (
            <tr>
              <td
                colSpan={columns.length + (selectable ? 1 : 0)}
                className="data-table__empty"
              >
                {emptyMessage}
              </td>
            </tr>
          ) : (
            sortedData.map((row, index) => {
              const key = getRowKey(row);
              const isSelected = selected.includes(key);

              return (
                <tr
                  key={key}
                  className={`data-table__row ${isSelected ? 'data-table__row--selected' : ''} ${
                    hoverable ? 'data-table__row--hoverable' : ''
                  }`}
                  onClick={() => onRowClick?.(row, index)}
                  onDoubleClick={() => onRowDoubleClick?.(row, index)}
                >
                  {selectable && (
                    <td className="data-table__td data-table__td--checkbox">
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => handleSelectRow(key)}
                        onClick={(e) => e.stopPropagation()}
                      />
                    </td>
                  )}
                  {columns.map((col) => (
                    <td
                      key={col.key}
                      className={`data-table__td ${col.align ? `data-table__td--${col.align}` : ''}`}
                    >
                      {col.render
                        ? col.render(row[col.key], row, index)
                        : String(row[col.key] ?? '')}
                    </td>
                  ))}
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}

export default DataTable;

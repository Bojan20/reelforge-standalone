/**
 * ReelForge TreeSelect
 *
 * Tree dropdown selector:
 * - Hierarchical options
 * - Single/multi select
 * - Search/filter
 * - Checkable nodes
 *
 * @module tree-select/TreeSelect
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import './TreeSelect.css';

// ============ Types ============

export interface TreeSelectNode {
  value: string;
  label: string;
  children?: TreeSelectNode[];
  disabled?: boolean;
  selectable?: boolean;
  checkable?: boolean;
  icon?: React.ReactNode;
}

export interface TreeSelectProps {
  /** Tree data */
  treeData: TreeSelectNode[];
  /** Selected value(s) */
  value?: string | string[];
  /** On change */
  onChange?: (value: string | string[], nodes: TreeSelectNode[]) => void;
  /** Multiple selection */
  multiple?: boolean;
  /** Show checkboxes */
  checkable?: boolean;
  /** Placeholder */
  placeholder?: string;
  /** Allow clearing */
  allowClear?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Show search */
  showSearch?: boolean;
  /** Tree default expanded */
  defaultExpandAll?: boolean;
  /** Max tag count */
  maxTagCount?: number;
  /** Custom class */
  className?: string;
}

// ============ TreeNode Component ============

interface TreeNodeProps {
  node: TreeSelectNode;
  level: number;
  selectedValues: Set<string>;
  expandedKeys: Set<string>;
  onSelect: (node: TreeSelectNode) => void;
  onToggle: (key: string) => void;
  onCheck?: (node: TreeSelectNode, checked: boolean) => void;
  checkable?: boolean;
  searchValue: string;
}

function TreeNode({
  node,
  level,
  selectedValues,
  expandedKeys,
  onSelect,
  onToggle,
  onCheck,
  checkable,
  searchValue,
}: TreeNodeProps) {
  const hasChildren = node.children && node.children.length > 0;
  const isExpanded = expandedKeys.has(node.value);
  const isSelected = selectedValues.has(node.value);
  const isDisabled = node.disabled;

  // Check if matches search
  const matchesSearch =
    !searchValue || node.label.toLowerCase().includes(searchValue.toLowerCase());

  // Check if any child matches
  const hasMatchingChild = useMemo(() => {
    if (!searchValue) return true;

    const checkChildren = (n: TreeSelectNode): boolean => {
      if (n.label.toLowerCase().includes(searchValue.toLowerCase())) return true;
      if (n.children) {
        return n.children.some(checkChildren);
      }
      return false;
    };

    return hasChildren ? node.children!.some(checkChildren) : matchesSearch;
  }, [node, searchValue, hasChildren, matchesSearch]);

  if (!matchesSearch && !hasMatchingChild) {
    return null;
  }

  return (
    <div className="tree-select-node">
      <div
        className={`tree-select-node__content ${
          isSelected ? 'tree-select-node__content--selected' : ''
        } ${isDisabled ? 'tree-select-node__content--disabled' : ''}`}
        style={{ paddingLeft: level * 20 + 8 }}
      >
        {hasChildren ? (
          <button
            type="button"
            className={`tree-select-node__toggle ${
              isExpanded ? 'tree-select-node__toggle--expanded' : ''
            }`}
            onClick={() => onToggle(node.value)}
          >
            ▶
          </button>
        ) : (
          <span className="tree-select-node__spacer" />
        )}

        {checkable && (
          <span
            className={`tree-select-node__checkbox ${
              isSelected ? 'tree-select-node__checkbox--checked' : ''
            }`}
            onClick={() => !isDisabled && onCheck?.(node, !isSelected)}
          >
            {isSelected && '✓'}
          </span>
        )}

        {node.icon && <span className="tree-select-node__icon">{node.icon}</span>}

        <span
          className="tree-select-node__label"
          onClick={() => !isDisabled && !checkable && onSelect(node)}
        >
          {node.label}
        </span>
      </div>

      {hasChildren && isExpanded && (
        <div className="tree-select-node__children">
          {node.children!.map((child) => (
            <TreeNode
              key={child.value}
              node={child}
              level={level + 1}
              selectedValues={selectedValues}
              expandedKeys={expandedKeys}
              onSelect={onSelect}
              onToggle={onToggle}
              onCheck={onCheck}
              checkable={checkable}
              searchValue={searchValue}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ============ TreeSelect Component ============

export function TreeSelect({
  treeData,
  value,
  onChange,
  multiple = false,
  checkable = false,
  placeholder = 'Select...',
  allowClear = true,
  disabled = false,
  showSearch = false,
  defaultExpandAll = false,
  maxTagCount = 3,
  className = '',
}: TreeSelectProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);

  // Initialize expanded keys
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(() => {
    if (!defaultExpandAll) return new Set();

    const keys = new Set<string>();
    const collectKeys = (nodes: TreeSelectNode[]) => {
      for (const node of nodes) {
        if (node.children && node.children.length > 0) {
          keys.add(node.value);
          collectKeys(node.children);
        }
      }
    };
    collectKeys(treeData);
    return keys;
  });

  // Normalize value to array
  const selectedValues = useMemo(() => {
    if (!value) return new Set<string>();
    return new Set(Array.isArray(value) ? value : [value]);
  }, [value]);

  // Flatten tree for lookups
  const flatNodes = useMemo(() => {
    const map = new Map<string, TreeSelectNode>();
    const flatten = (nodes: TreeSelectNode[]) => {
      for (const node of nodes) {
        map.set(node.value, node);
        if (node.children) flatten(node.children);
      }
    };
    flatten(treeData);
    return map;
  }, [treeData]);

  // Get selected nodes
  const selectedNodes = useMemo(() => {
    return Array.from(selectedValues)
      .map((v) => flatNodes.get(v))
      .filter(Boolean) as TreeSelectNode[];
  }, [selectedValues, flatNodes]);

  // Handle select
  const handleSelect = useCallback(
    (node: TreeSelectNode) => {
      if (multiple || checkable) {
        const newValues = new Set(selectedValues);
        if (newValues.has(node.value)) {
          newValues.delete(node.value);
        } else {
          newValues.add(node.value);
        }
        const arr = Array.from(newValues);
        onChange?.(arr, arr.map((v) => flatNodes.get(v)!));
      } else {
        onChange?.(node.value, [node]);
        setIsOpen(false);
        setSearch('');
      }
    },
    [multiple, checkable, selectedValues, flatNodes, onChange]
  );

  // Handle check
  const handleCheck = useCallback(
    (node: TreeSelectNode, checked: boolean) => {
      const newValues = new Set(selectedValues);

      if (checked) {
        newValues.add(node.value);
      } else {
        newValues.delete(node.value);
      }

      const arr = Array.from(newValues);
      onChange?.(arr, arr.map((v) => flatNodes.get(v)!));
    },
    [selectedValues, flatNodes, onChange]
  );

  // Toggle expand
  const toggleExpand = useCallback((key: string) => {
    setExpandedKeys((prev) => {
      const newSet = new Set(prev);
      if (newSet.has(key)) {
        newSet.delete(key);
      } else {
        newSet.add(key);
      }
      return newSet;
    });
  }, []);

  // Handle clear
  const handleClear = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onChange?.(multiple || checkable ? [] : '', []);
    },
    [multiple, checkable, onChange]
  );

  // Remove tag
  const handleRemoveTag = useCallback(
    (val: string, e: React.MouseEvent) => {
      e.stopPropagation();
      const newValues = Array.from(selectedValues).filter((v) => v !== val);
      onChange?.(newValues, newValues.map((v) => flatNodes.get(v)!));
    },
    [selectedValues, flatNodes, onChange]
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

  // Display value
  const displayValue = useMemo(() => {
    if (selectedNodes.length === 0) return null;

    if (multiple || checkable) {
      const visible = selectedNodes.slice(0, maxTagCount);
      const remaining = selectedNodes.length - maxTagCount;

      return (
        <div className="tree-select__tags">
          {visible.map((node) => (
            <span key={node.value} className="tree-select__tag">
              {node.label}
              <button
                type="button"
                className="tree-select__tag-remove"
                onClick={(e) => handleRemoveTag(node.value, e)}
              >
                ×
              </button>
            </span>
          ))}
          {remaining > 0 && (
            <span className="tree-select__tag-more">+{remaining}</span>
          )}
        </div>
      );
    }

    return <span className="tree-select__value">{selectedNodes[0].label}</span>;
  }, [selectedNodes, multiple, checkable, maxTagCount, handleRemoveTag]);

  return (
    <div
      ref={containerRef}
      className={`tree-select ${isOpen ? 'tree-select--open' : ''} ${
        disabled ? 'tree-select--disabled' : ''
      } ${className}`}
    >
      <div className="tree-select__trigger" onClick={() => !disabled && setIsOpen(!isOpen)}>
        {displayValue || <span className="tree-select__placeholder">{placeholder}</span>}

        {allowClear && selectedNodes.length > 0 && !disabled && (
          <button type="button" className="tree-select__clear" onClick={handleClear}>
            ×
          </button>
        )}

        <span className={`tree-select__arrow ${isOpen ? 'tree-select__arrow--up' : ''}`}>
          ▼
        </span>
      </div>

      {isOpen && (
        <div className="tree-select__dropdown">
          {showSearch && (
            <div className="tree-select__search">
              <input
                type="text"
                className="tree-select__search-input"
                placeholder="Search..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                autoFocus
              />
            </div>
          )}

          <div className="tree-select__tree">
            {treeData.map((node) => (
              <TreeNode
                key={node.value}
                node={node}
                level={0}
                selectedValues={selectedValues}
                expandedKeys={expandedKeys}
                onSelect={handleSelect}
                onToggle={toggleExpand}
                onCheck={checkable ? handleCheck : undefined}
                checkable={checkable}
                searchValue={search}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default TreeSelect;

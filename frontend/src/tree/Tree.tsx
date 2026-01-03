/**
 * ReelForge Tree
 *
 * Tree component:
 * - Hierarchical data display
 * - Expand/collapse nodes
 * - Selection (single/multi)
 * - Checkboxes
 * - Drag and drop (optional)
 * - Icons and badges
 *
 * @module tree/Tree
 */

import { useState, useCallback, useMemo } from 'react';
import './Tree.css';

// ============ Types ============

export interface TreeNode {
  /** Unique ID */
  id: string;
  /** Label */
  label: string;
  /** Icon */
  icon?: React.ReactNode;
  /** Children nodes */
  children?: TreeNode[];
  /** Is disabled */
  disabled?: boolean;
  /** Custom data */
  data?: unknown;
}

export interface TreeProps {
  /** Tree data */
  data: TreeNode[];
  /** Expanded node IDs */
  expanded?: string[];
  /** Default expanded IDs */
  defaultExpanded?: string[];
  /** On expand change */
  onExpandChange?: (expanded: string[]) => void;
  /** Selected node IDs */
  selected?: string[];
  /** Default selected IDs */
  defaultSelected?: string[];
  /** On select change */
  onSelectChange?: (selected: string[]) => void;
  /** Selection mode */
  selectionMode?: 'none' | 'single' | 'multiple';
  /** Show checkboxes */
  checkboxes?: boolean;
  /** Checked node IDs */
  checked?: string[];
  /** On check change */
  onCheckChange?: (checked: string[]) => void;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
  /** On node click */
  onNodeClick?: (node: TreeNode) => void;
  /** On node double click */
  onNodeDoubleClick?: (node: TreeNode) => void;
}

// ============ Component ============

export function Tree({
  data,
  expanded: controlledExpanded,
  defaultExpanded = [],
  onExpandChange,
  selected: controlledSelected,
  defaultSelected = [],
  onSelectChange,
  selectionMode = 'single',
  checkboxes = false,
  checked: controlledChecked,
  onCheckChange,
  size = 'medium',
  className = '',
  onNodeClick,
  onNodeDoubleClick,
}: TreeProps) {
  // Expanded state
  const [internalExpanded, setInternalExpanded] = useState<string[]>(defaultExpanded);
  const isExpandedControlled = controlledExpanded !== undefined;
  const expanded = isExpandedControlled ? controlledExpanded : internalExpanded;

  // Selected state
  const [internalSelected, setInternalSelected] = useState<string[]>(defaultSelected);
  const isSelectedControlled = controlledSelected !== undefined;
  const selected = isSelectedControlled ? controlledSelected : internalSelected;

  // Checked state
  const [internalChecked, setInternalChecked] = useState<string[]>([]);
  const isCheckedControlled = controlledChecked !== undefined;
  const checked = isCheckedControlled ? controlledChecked : internalChecked;

  // Toggle expand
  const toggleExpand = useCallback(
    (nodeId: string) => {
      const newExpanded = expanded.includes(nodeId)
        ? expanded.filter((id) => id !== nodeId)
        : [...expanded, nodeId];

      if (!isExpandedControlled) {
        setInternalExpanded(newExpanded);
      }
      onExpandChange?.(newExpanded);
    },
    [expanded, isExpandedControlled, onExpandChange]
  );

  // Toggle select
  const toggleSelect = useCallback(
    (nodeId: string, node: TreeNode) => {
      if (node.disabled || selectionMode === 'none') return;

      let newSelected: string[];

      if (selectionMode === 'single') {
        newSelected = selected.includes(nodeId) ? [] : [nodeId];
      } else {
        newSelected = selected.includes(nodeId)
          ? selected.filter((id) => id !== nodeId)
          : [...selected, nodeId];
      }

      if (!isSelectedControlled) {
        setInternalSelected(newSelected);
      }
      onSelectChange?.(newSelected);
      onNodeClick?.(node);
    },
    [selected, selectionMode, isSelectedControlled, onSelectChange, onNodeClick]
  );

  // Toggle check
  const toggleCheck = useCallback(
    (nodeId: string, node: TreeNode) => {
      if (node.disabled) return;

      // Get all descendant IDs
      const getAllDescendants = (n: TreeNode): string[] => {
        const ids = [n.id];
        n.children?.forEach((child) => {
          ids.push(...getAllDescendants(child));
        });
        return ids;
      };

      const descendants = getAllDescendants(node);
      const isChecked = checked.includes(nodeId);

      let newChecked: string[];
      if (isChecked) {
        // Uncheck node and all descendants
        newChecked = checked.filter((id) => !descendants.includes(id));
      } else {
        // Check node and all descendants
        newChecked = [...new Set([...checked, ...descendants])];
      }

      if (!isCheckedControlled) {
        setInternalChecked(newChecked);
      }
      onCheckChange?.(newChecked);
    },
    [checked, isCheckedControlled, onCheckChange]
  );

  return (
    <div className={`tree tree--${size} ${className}`} role="tree">
      {data.map((node) => (
        <TreeNodeComponent
          key={node.id}
          node={node}
          level={0}
          expanded={expanded}
          selected={selected}
          checked={checked}
          checkboxes={checkboxes}
          onToggleExpand={toggleExpand}
          onToggleSelect={toggleSelect}
          onToggleCheck={toggleCheck}
          onDoubleClick={onNodeDoubleClick}
        />
      ))}
    </div>
  );
}

// ============ Node Component ============

interface TreeNodeComponentProps {
  node: TreeNode;
  level: number;
  expanded: string[];
  selected: string[];
  checked: string[];
  checkboxes: boolean;
  onToggleExpand: (nodeId: string) => void;
  onToggleSelect: (nodeId: string, node: TreeNode) => void;
  onToggleCheck: (nodeId: string, node: TreeNode) => void;
  onDoubleClick?: (node: TreeNode) => void;
}

function TreeNodeComponent({
  node,
  level,
  expanded,
  selected,
  checked,
  checkboxes,
  onToggleExpand,
  onToggleSelect,
  onToggleCheck,
  onDoubleClick,
}: TreeNodeComponentProps) {
  const hasChildren = node.children && node.children.length > 0;
  const isExpanded = expanded.includes(node.id);
  const isSelected = selected.includes(node.id);
  const isChecked = checked.includes(node.id);

  // Check if partially checked (some children checked)
  const isIndeterminate = useMemo(() => {
    if (!hasChildren || !checkboxes) return false;

    const getAllDescendantIds = (n: TreeNode): string[] => {
      const ids: string[] = [];
      n.children?.forEach((child) => {
        ids.push(child.id);
        ids.push(...getAllDescendantIds(child));
      });
      return ids;
    };

    const descendantIds = getAllDescendantIds(node);
    const checkedDescendants = descendantIds.filter((id) => checked.includes(id));

    return checkedDescendants.length > 0 && checkedDescendants.length < descendantIds.length;
  }, [hasChildren, checkboxes, node, checked]);

  return (
    <div className="tree__node" role="treeitem" aria-expanded={hasChildren ? isExpanded : undefined}>
      {/* Node row */}
      <div
        className={`tree__row ${isSelected ? 'tree__row--selected' : ''} ${
          node.disabled ? 'tree__row--disabled' : ''
        }`}
        style={{ paddingLeft: `${level * 20 + 8}px` }}
        onClick={() => onToggleSelect(node.id, node)}
        onDoubleClick={() => {
          if (hasChildren) {
            onToggleExpand(node.id);
          }
          onDoubleClick?.(node);
        }}
      >
        {/* Expand toggle */}
        <span
          className={`tree__toggle ${hasChildren ? 'tree__toggle--visible' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            if (hasChildren) onToggleExpand(node.id);
          }}
        >
          {hasChildren && (
            <svg width="10" height="10" viewBox="0 0 10 10">
              <path
                d={isExpanded ? 'M2 3L5 6L8 3' : 'M3 2L6 5L3 8'}
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          )}
        </span>

        {/* Checkbox */}
        {checkboxes && (
          <span
            className={`tree__checkbox ${isChecked ? 'tree__checkbox--checked' : ''} ${
              isIndeterminate ? 'tree__checkbox--indeterminate' : ''
            }`}
            onClick={(e) => {
              e.stopPropagation();
              onToggleCheck(node.id, node);
            }}
          >
            {isChecked && !isIndeterminate && '✓'}
            {isIndeterminate && '−'}
          </span>
        )}

        {/* Icon */}
        {node.icon && <span className="tree__icon">{node.icon}</span>}

        {/* Label */}
        <span className="tree__label">{node.label}</span>
      </div>

      {/* Children */}
      {hasChildren && isExpanded && (
        <div className="tree__children" role="group">
          {node.children!.map((child) => (
            <TreeNodeComponent
              key={child.id}
              node={child}
              level={level + 1}
              expanded={expanded}
              selected={selected}
              checked={checked}
              checkboxes={checkboxes}
              onToggleExpand={onToggleExpand}
              onToggleSelect={onToggleSelect}
              onToggleCheck={onToggleCheck}
              onDoubleClick={onDoubleClick}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export default Tree;

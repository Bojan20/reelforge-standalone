/**
 * ReelForge Tabs
 *
 * Tab component:
 * - Draggable tab reordering
 * - Closable tabs
 * - Tab overflow menu
 * - Icons and badges
 *
 * @module tabs/Tabs
 */

import { useState, useCallback, useRef } from 'react';
import './Tabs.css';

// ============ Types ============

export interface Tab {
  /** Unique ID */
  id: string;
  /** Tab label */
  label: string;
  /** Icon */
  icon?: string;
  /** Is closable */
  closable?: boolean;
  /** Is disabled */
  disabled?: boolean;
  /** Badge content */
  badge?: string | number;
  /** Is dirty/modified */
  dirty?: boolean;
}

export interface TabsProps {
  /** Tabs */
  tabs: Tab[];
  /** Active tab ID */
  activeTab: string;
  /** On tab select */
  onSelect: (tabId: string) => void;
  /** On tab close */
  onClose?: (tabId: string) => void;
  /** On tab reorder */
  onReorder?: (tabs: Tab[]) => void;
  /** On new tab */
  onNewTab?: () => void;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Allow dragging */
  draggable?: boolean;
  /** Show add button */
  showAddButton?: boolean;
}

// ============ Component ============

export function Tabs({
  tabs,
  activeTab,
  onSelect,
  onClose,
  onReorder,
  onNewTab,
  size = 'medium',
  draggable = true,
  showAddButton = false,
}: TabsProps) {
  const [draggedTab, setDraggedTab] = useState<string | null>(null);
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  const tabsRef = useRef<HTMLDivElement>(null);

  // Handle tab click
  const handleTabClick = useCallback(
    (tab: Tab) => {
      if (!tab.disabled) {
        onSelect(tab.id);
      }
    },
    [onSelect]
  );

  // Handle tab close
  const handleTabClose = useCallback(
    (e: React.MouseEvent, tab: Tab) => {
      e.stopPropagation();
      if (tab.closable && onClose) {
        onClose(tab.id);
      }
    },
    [onClose]
  );

  // Handle drag start
  const handleDragStart = useCallback(
    (e: React.DragEvent, tab: Tab) => {
      if (!draggable || tab.disabled) return;

      setDraggedTab(tab.id);
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/plain', tab.id);

      // Create drag image
      const dragImage = e.currentTarget.cloneNode(true) as HTMLElement;
      dragImage.style.opacity = '0.8';
      document.body.appendChild(dragImage);
      e.dataTransfer.setDragImage(dragImage, 0, 0);
      setTimeout(() => document.body.removeChild(dragImage), 0);
    },
    [draggable]
  );

  // Handle drag over
  const handleDragOver = useCallback(
    (e: React.DragEvent, tab: Tab) => {
      if (!draggable || !draggedTab || draggedTab === tab.id) return;

      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      setDropTarget(tab.id);
    },
    [draggable, draggedTab]
  );

  // Handle drag leave
  const handleDragLeave = useCallback(() => {
    setDropTarget(null);
  }, []);

  // Handle drop
  const handleDrop = useCallback(
    (e: React.DragEvent, targetTab: Tab) => {
      e.preventDefault();

      if (!draggedTab || !onReorder) {
        setDraggedTab(null);
        setDropTarget(null);
        return;
      }

      const dragIndex = tabs.findIndex((t) => t.id === draggedTab);
      const dropIndex = tabs.findIndex((t) => t.id === targetTab.id);

      if (dragIndex !== dropIndex) {
        const newTabs = [...tabs];
        const [removed] = newTabs.splice(dragIndex, 1);
        newTabs.splice(dropIndex, 0, removed);
        onReorder(newTabs);
      }

      setDraggedTab(null);
      setDropTarget(null);
    },
    [tabs, draggedTab, onReorder]
  );

  // Handle drag end
  const handleDragEnd = useCallback(() => {
    setDraggedTab(null);
    setDropTarget(null);
  }, []);

  return (
    <div className={`tabs tabs--${size}`}>
      <div ref={tabsRef} className="tabs__list" role="tablist">
        {tabs.map((tab) => (
          <div
            key={tab.id}
            className={`tabs__tab ${activeTab === tab.id ? 'tabs__tab--active' : ''} ${
              tab.disabled ? 'tabs__tab--disabled' : ''
            } ${draggedTab === tab.id ? 'tabs__tab--dragging' : ''} ${
              dropTarget === tab.id ? 'tabs__tab--drop-target' : ''
            } ${tab.dirty ? 'tabs__tab--dirty' : ''}`}
            onClick={() => handleTabClick(tab)}
            draggable={draggable && !tab.disabled}
            onDragStart={(e) => handleDragStart(e, tab)}
            onDragOver={(e) => handleDragOver(e, tab)}
            onDragLeave={handleDragLeave}
            onDrop={(e) => handleDrop(e, tab)}
            onDragEnd={handleDragEnd}
            role="tab"
            aria-selected={activeTab === tab.id}
            aria-disabled={tab.disabled}
          >
            {tab.icon && <span className="tabs__tab-icon">{tab.icon}</span>}
            <span className="tabs__tab-label">{tab.label}</span>
            {tab.dirty && <span className="tabs__tab-dirty">●</span>}
            {tab.badge !== undefined && (
              <span className="tabs__tab-badge">{tab.badge}</span>
            )}
            {tab.closable && onClose && (
              <button
                className="tabs__tab-close"
                onClick={(e) => handleTabClose(e, tab)}
                aria-label="Close tab"
              >
                ×
              </button>
            )}
          </div>
        ))}

        {/* Add button */}
        {showAddButton && onNewTab && (
          <button className="tabs__add" onClick={onNewTab} aria-label="New tab">
            +
          </button>
        )}
      </div>
    </div>
  );
}

export default Tabs;

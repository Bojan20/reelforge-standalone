/**
 * ReelForge Validation Panel
 *
 * Displays validation errors and warnings for the project.
 * Features:
 * - Real-time validation as routes change
 * - Click-to-navigate to error location
 * - Filter by type (error/warning)
 * - Missing asset detection
 */

import { useMemo, useState, useCallback } from 'react';
import type { RoutesConfig, RouteValidationError } from '../core/routesTypes';
import { validateRoutes, formatErrorLocation } from '../core/validateRoutes';
import './ValidationPanel.css';

interface ValidationPanelProps {
  /** Routes configuration to validate */
  routes: RoutesConfig | null;
  /** Set of available asset IDs for validation */
  availableAssets: Set<string>;
  /** Callback when user clicks on an error to navigate */
  onNavigateToError?: (error: RouteValidationError) => void;
  /** Optional class name */
  className?: string;
}

type FilterType = 'all' | 'errors' | 'warnings';

export default function ValidationPanel({
  routes,
  availableAssets,
  onNavigateToError,
  className = '',
}: ValidationPanelProps) {
  const [filter, setFilter] = useState<FilterType>('all');
  const [isCollapsed, setIsCollapsed] = useState(false);

  // Run validation
  const validationResult = useMemo(() => {
    if (!routes) {
      return { valid: true, errors: [], warnings: [] };
    }
    return validateRoutes(routes, availableAssets);
  }, [routes, availableAssets]);

  // Additional checks for missing assets in Play/Fade actions
  const missingAssetErrors = useMemo(() => {
    if (!routes || availableAssets.size === 0) return [];

    const errors: RouteValidationError[] = [];

    routes.events.forEach((event, eventIndex) => {
      event.actions.forEach((action, actionIndex) => {
        if ((action.type === 'Play' || action.type === 'Fade') && action.assetId) {
          // Check if asset exists (by name or ID)
          const assetExists = availableAssets.has(action.assetId) ||
            Array.from(availableAssets).some(a =>
              a.toLowerCase() === action.assetId.toLowerCase() ||
              a.replace(/\.[^/.]+$/, '').toLowerCase() === action.assetId.toLowerCase()
            );

          if (!assetExists) {
            errors.push({
              type: 'warning',
              message: `Asset not imported: "${action.assetId}"`,
              eventName: event.name,
              eventIndex,
              actionIndex,
              field: 'assetId',
            });
          }
        }
      });
    });

    return errors;
  }, [routes, availableAssets]);

  // Combine all issues
  const allIssues = useMemo(() => {
    const combined = [
      ...validationResult.errors,
      ...validationResult.warnings,
      ...missingAssetErrors,
    ];

    // Sort: errors first, then warnings, then by event/action index
    return combined.sort((a, b) => {
      if (a.type !== b.type) {
        return a.type === 'error' ? -1 : 1;
      }
      if ((a.eventIndex ?? 0) !== (b.eventIndex ?? 0)) {
        return (a.eventIndex ?? 0) - (b.eventIndex ?? 0);
      }
      return (a.actionIndex ?? 0) - (b.actionIndex ?? 0);
    });
  }, [validationResult, missingAssetErrors]);

  // Filter issues
  const filteredIssues = useMemo(() => {
    if (filter === 'all') return allIssues;
    if (filter === 'errors') return allIssues.filter(i => i.type === 'error');
    return allIssues.filter(i => i.type === 'warning');
  }, [allIssues, filter]);

  // Counts
  const errorCount = allIssues.filter(i => i.type === 'error').length;
  const warningCount = allIssues.filter(i => i.type === 'warning').length;

  const handleIssueClick = useCallback((issue: RouteValidationError) => {
    onNavigateToError?.(issue);
  }, [onNavigateToError]);

  const getIssueIcon = (type: 'error' | 'warning') => {
    return type === 'error' ? '✕' : '⚠';
  };

  if (!routes) {
    return (
      <div className={`rf-validation-panel ${className}`}>
        <div className="rf-validation-empty">No project loaded</div>
      </div>
    );
  }

  return (
    <div className={`rf-validation-panel ${className} ${isCollapsed ? 'is-collapsed' : ''}`}>
      {/* Header */}
      <div className="rf-validation-header">
        <button
          type="button"
          className="rf-validation-collapse"
          onClick={() => setIsCollapsed(!isCollapsed)}
          title={isCollapsed ? 'Expand' : 'Collapse'}
        >
          {isCollapsed ? '▶' : '▼'}
        </button>

        <span className="rf-validation-title">Validation</span>

        <div className="rf-validation-counts">
          <span className={`rf-validation-count is-error ${errorCount > 0 ? 'has-issues' : ''}`}>
            {errorCount} {errorCount === 1 ? 'error' : 'errors'}
          </span>
          <span className={`rf-validation-count is-warning ${warningCount > 0 ? 'has-issues' : ''}`}>
            {warningCount} {warningCount === 1 ? 'warning' : 'warnings'}
          </span>
        </div>

        {/* Filter tabs */}
        {!isCollapsed && (
          <div className="rf-validation-filters">
            <button
              type="button"
              className={`rf-validation-filter ${filter === 'all' ? 'is-active' : ''}`}
              onClick={() => setFilter('all')}
            >
              All
            </button>
            <button
              type="button"
              className={`rf-validation-filter ${filter === 'errors' ? 'is-active' : ''}`}
              onClick={() => setFilter('errors')}
            >
              Errors
            </button>
            <button
              type="button"
              className={`rf-validation-filter ${filter === 'warnings' ? 'is-active' : ''}`}
              onClick={() => setFilter('warnings')}
            >
              Warnings
            </button>
          </div>
        )}
      </div>

      {/* Issues list */}
      {!isCollapsed && (
        <div className="rf-validation-content">
          {filteredIssues.length === 0 ? (
            <div className="rf-validation-empty">
              {allIssues.length === 0 ? (
                <span className="rf-validation-success">✓ No issues found</span>
              ) : (
                <span>No {filter === 'errors' ? 'errors' : 'warnings'}</span>
              )}
            </div>
          ) : (
            <div className="rf-validation-list">
              {filteredIssues.map((issue, idx) => (
                <div
                  key={`${issue.eventName}-${issue.actionIndex}-${idx}`}
                  className={`rf-validation-item is-${issue.type}`}
                  onClick={() => handleIssueClick(issue)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      handleIssueClick(issue);
                    }
                  }}
                >
                  <span className="rf-validation-item-icon">
                    {getIssueIcon(issue.type)}
                  </span>
                  <div className="rf-validation-item-content">
                    <span className="rf-validation-item-message">{issue.message}</span>
                    <span className="rf-validation-item-location">
                      {formatErrorLocation(issue)}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

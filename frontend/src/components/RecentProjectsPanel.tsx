/**
 * Recent Projects Panel
 *
 * Welcome screen / project selector with:
 * - Recent projects list
 * - New project creation
 * - Project import
 * - Quick actions
 *
 * @module components/RecentProjectsPanel
 */

import { memo, useState, useCallback, useRef } from 'react';
import { ProjectPersistence, type RecentProject, type ProjectData } from '../core/projectPersistence';
import './RecentProjectsPanel.css';

// ============ TYPES ============

export interface RecentProjectsPanelProps {
  onNewProject?: (name: string, author?: string) => void;
  onOpenProject?: (project: ProjectData) => void;
  onOpenRecent?: (projectId: string) => void;
  onImportProject?: () => void;
  showWelcome?: boolean;
}

// ============ PANEL ============

export const RecentProjectsPanel = memo(function RecentProjectsPanel({
  onNewProject,
  onOpenProject,
  onImportProject,
  showWelcome = true,
}: RecentProjectsPanelProps) {
  const [recentProjects, setRecentProjects] = useState<RecentProject[]>(
    ProjectPersistence.getRecentProjects()
  );
  const [isCreating, setIsCreating] = useState(false);
  const [newProjectName, setNewProjectName] = useState('');
  const [newProjectAuthor, setNewProjectAuthor] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Refresh recent projects
  const refreshRecent = useCallback(() => {
    setRecentProjects(ProjectPersistence.getRecentProjects());
  }, []);

  // Create new project
  const handleCreate = useCallback(() => {
    if (!newProjectName.trim()) return;

    const project = ProjectPersistence.createNewProject(
      newProjectName.trim(),
      newProjectAuthor.trim() || undefined
    );

    onNewProject?.(newProjectName.trim(), newProjectAuthor.trim() || undefined);
    onOpenProject?.(project);

    setIsCreating(false);
    setNewProjectName('');
    setNewProjectAuthor('');
    refreshRecent();
  }, [newProjectName, newProjectAuthor, onNewProject, onOpenProject, refreshRecent]);

  // Open recent project
  const handleOpenRecent = useCallback(async (recent: RecentProject) => {
    const project = ProjectPersistence.loadFromLocalStorage(recent.id);
    if (project) {
      onOpenProject?.(project);
      refreshRecent();
    }
  }, [onOpenProject, refreshRecent]);

  // Remove from recent
  const handleRemoveRecent = useCallback((e: React.MouseEvent, projectId: string) => {
    e.stopPropagation();
    ProjectPersistence.removeFromRecentProjects(projectId);
    refreshRecent();
  }, [refreshRecent]);

  // Import file
  const handleImportClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const project = await ProjectPersistence.loadFromFile(file);
      onOpenProject?.(project);
      refreshRecent();
    } catch (error) {
      console.error('Failed to import project:', error);
      alert('Failed to import project. Please check the file format.');
    }

    // Reset input
    e.target.value = '';
  };

  // Format date
  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;

    return date.toLocaleDateString();
  };

  return (
    <div className="recent-projects-panel">
      {/* Welcome Section */}
      {showWelcome && (
        <div className="welcome-section">
          <div className="welcome-logo">
            <div className="welcome-logo__icon" />
            <h1>ReelForge</h1>
          </div>
          <p className="welcome-tagline">
            Professional Game Audio Middleware
          </p>
        </div>
      )}

      {/* Quick Actions */}
      <div className="quick-actions">
        <button
          className="quick-action-btn quick-action-btn--primary"
          onClick={() => setIsCreating(true)}
        >
          <span className="quick-action-btn__icon">➕</span>
          <span>New Project</span>
        </button>

        <button
          className="quick-action-btn"
          onClick={handleImportClick}
        >
          <span className="quick-action-btn__icon">📂</span>
          <span>Open Project</span>
        </button>

        <button
          className="quick-action-btn"
          onClick={onImportProject}
        >
          <span className="quick-action-btn__icon">📥</span>
          <span>Import JSON</span>
        </button>

        <input
          ref={fileInputRef}
          type="file"
          accept=".json,.reelforge.json"
          onChange={handleFileChange}
          style={{ display: 'none' }}
        />
      </div>

      {/* New Project Dialog */}
      {isCreating && (
        <div className="new-project-dialog">
          <h3>Create New Project</h3>

          <div className="form-group">
            <label>Project Name</label>
            <input
              type="text"
              value={newProjectName}
              onChange={(e) => setNewProjectName(e.target.value)}
              placeholder="My Awesome Game"
              autoFocus
            />
          </div>

          <div className="form-group">
            <label>Author (optional)</label>
            <input
              type="text"
              value={newProjectAuthor}
              onChange={(e) => setNewProjectAuthor(e.target.value)}
              placeholder="Your Name"
            />
          </div>

          <div className="dialog-actions">
            <button
              className="dialog-btn dialog-btn--secondary"
              onClick={() => setIsCreating(false)}
            >
              Cancel
            </button>
            <button
              className="dialog-btn dialog-btn--primary"
              onClick={handleCreate}
              disabled={!newProjectName.trim()}
            >
              Create Project
            </button>
          </div>
        </div>
      )}

      {/* Recent Projects */}
      <div className="recent-section">
        <h2>Recent Projects</h2>

        {recentProjects.length === 0 ? (
          <div className="empty-state">
            <span className="empty-state__icon">📁</span>
            <p>No recent projects</p>
            <p className="empty-state__hint">
              Create a new project or open an existing one to get started
            </p>
          </div>
        ) : (
          <div className="recent-list">
            {recentProjects.map((project) => (
              <div
                key={project.id}
                className="recent-item"
                onClick={() => handleOpenRecent(project)}
              >
                <div className="recent-item__icon">🎵</div>

                <div className="recent-item__info">
                  <span className="recent-item__name">{project.name}</span>
                  <span className="recent-item__date">
                    {formatDate(project.lastOpened)}
                  </span>
                </div>

                <button
                  className="recent-item__remove"
                  onClick={(e) => handleRemoveRecent(e, project.id)}
                  title="Remove from recent"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Tips Section */}
      <div className="tips-section">
        <h3>Quick Tips</h3>
        <ul>
          <li>
            <kbd>⌘N</kbd> Create new project
          </li>
          <li>
            <kbd>⌘O</kbd> Open project
          </li>
          <li>
            <kbd>⌘S</kbd> Save project
          </li>
          <li>
            <kbd>Space</kbd> Play/Pause preview
          </li>
        </ul>
      </div>

      {/* Version */}
      <div className="version-info">
        ReelForge v1.0.0-preview
      </div>
    </div>
  );
});

export default RecentProjectsPanel;

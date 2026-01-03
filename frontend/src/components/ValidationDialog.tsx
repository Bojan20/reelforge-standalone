/**
 * ValidationDialog Component
 *
 * Modal dialog for displaying validation errors and warnings
 * with auto-fix capabilities.
 */

import type { ValidationIssue } from '../core/validateProject';
import type { ReelForgeProject, AudioFileObject } from '../core/types';
import { autoFixMissingSprites, autoFixMissingSounds } from '../core/validateProject';

export interface ValidationDialogData {
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
  allowExport: boolean;
}

interface ValidationDialogProps {
  data: ValidationDialogData;
  project: ReelForgeProject | null;
  audioFiles: AudioFileObject[];
  onClose: () => void;
  onProjectUpdate: (project: ReelForgeProject) => void;
  onExport: () => void;
}

export function ValidationDialog({
  data,
  project,
  audioFiles,
  onClose,
  onProjectUpdate,
  onExport,
}: ValidationDialogProps) {
  const handleAutoConnectSounds = () => {
    if (!project) return;

    const result = autoFixMissingSounds(project, audioFiles);
    if (result.fixed) {
      onProjectUpdate({ ...project });
      alert(
        `${result.message}\n\nConnected sounds:\n${result.connectedSounds?.map(s => `${s.soundId}${s.fileName}`).join('\n')}`
      );
    } else {
      alert(`${result.message}`);
    }
    onClose();
  };

  const handleAutoFixSprites = () => {
    if (!project) return;

    const result = autoFixMissingSprites(project, audioFiles);
    if (result.fixed) {
      onProjectUpdate({ ...project });
      alert(
        `${result.message}\n\nAdded sprites:\n${result.addedSprites?.map(s => `${s.spriteId}${s.soundId}`).join('\n')}`
      );
    }
    onClose();
  };

  const handleExportAnyway = () => {
    onExport();
    onClose();
  };

  const hasMissingSoundErrors = data.errors.some(e => e.code === 'MISSING_SOUND');
  const hasAutoFixableErrors = data.errors.some(e => e.autoFixable);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div
        className="modal-content"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: '600px' }}
      >
        <div className="modal-header">
          <h2>{data.allowExport ? 'Validation Warnings' : 'Validation Errors'}</h2>
        </div>

        <div className="modal-body" style={{ maxHeight: '400px', overflowY: 'auto' }}>
          {data.errors.length > 0 && (
            <div style={{ marginBottom: '20px' }}>
              <h3 style={{ color: '#dc2626', fontSize: '14px', marginBottom: '12px' }}>
                Errors ({data.errors.length})
              </h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {data.errors.map((issue, idx) => (
                  <div
                    key={idx}
                    style={{
                      padding: '12px',
                      backgroundColor: '#2a1a1a',
                      border: '1px solid #dc2626',
                      borderRadius: '4px'
                    }}
                  >
                    <div style={{ fontWeight: 600, color: '#dc2626', fontSize: '12px', marginBottom: '4px' }}>
                      {issue.code}
                    </div>
                    <div style={{ fontSize: '13px', color: '#ddd' }}>
                      {issue.message}
                    </div>
                    {issue.details && (
                      <div style={{ fontSize: '11px', color: '#888', marginTop: '4px', fontFamily: 'monospace' }}>
                        {JSON.stringify(issue.details)}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {data.warnings.length > 0 && (
            <div>
              <h3 style={{ color: '#f59e0b', fontSize: '14px', marginBottom: '12px' }}>
                Warnings ({data.warnings.length})
              </h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {data.warnings.map((issue, idx) => (
                  <div
                    key={idx}
                    style={{
                      padding: '12px',
                      backgroundColor: '#2a2a1a',
                      border: '1px solid #f59e0b',
                      borderRadius: '4px'
                    }}
                  >
                    <div style={{ fontWeight: 600, color: '#f59e0b', fontSize: '12px', marginBottom: '4px' }}>
                      {issue.code}
                    </div>
                    <div style={{ fontSize: '13px', color: '#ddd' }}>
                      {issue.message}
                    </div>
                    {issue.details && (
                      <div style={{ fontSize: '11px', color: '#888', marginTop: '4px', fontFamily: 'monospace' }}>
                        {JSON.stringify(issue.details)}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="modal-footer">
          <button className="btn-cancel" onClick={onClose}>
            Cancel
          </button>
          {hasMissingSoundErrors && (
            <button
              className="btn-save-confirm"
              onClick={handleAutoConnectSounds}
              style={{ backgroundColor: '#16a34a' }}
            >
              Auto-Connect Sounds
            </button>
          )}
          {hasAutoFixableErrors && (
            <button
              className="btn-save-confirm"
              onClick={handleAutoFixSprites}
              style={{ backgroundColor: '#16a34a' }}
            >
              Auto-Fix Missing Sprites
            </button>
          )}
          {data.allowExport && (
            <button
              className="btn-save-confirm"
              onClick={handleExportAnyway}
              style={{ backgroundColor: '#f59e0b' }}
            >
              Export Anyway
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

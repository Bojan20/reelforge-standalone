/**
 * ReelForge File Upload
 *
 * File upload component:
 * - Drag and drop
 * - Multiple files
 * - File type validation
 * - Progress display
 *
 * @module file-upload/FileUpload
 */

import { useState, useRef, useCallback } from 'react';
import './FileUpload.css';

// ============ Types ============

export interface UploadFile {
  /** File object */
  file: File;
  /** Unique id */
  id: string;
  /** Upload status */
  status: 'pending' | 'uploading' | 'success' | 'error';
  /** Progress (0-100) */
  progress: number;
  /** Error message */
  error?: string;
}

export interface FileUploadProps {
  /** Accepted file types */
  accept?: string;
  /** Allow multiple files */
  multiple?: boolean;
  /** Max file size in bytes */
  maxSize?: number;
  /** Max files */
  maxFiles?: number;
  /** On files selected */
  onFilesChange?: (files: UploadFile[]) => void;
  /** On upload */
  onUpload?: (file: File) => Promise<void>;
  /** Disabled */
  disabled?: boolean;
  /** Show file list */
  showFileList?: boolean;
  /** Custom class */
  className?: string;
  /** Custom content */
  children?: React.ReactNode;
}

// ============ Utilities ============

function generateId(): string {
  return Math.random().toString(36).substring(2, 9);
}

function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

// ============ Component ============

export function FileUpload({
  accept,
  multiple = false,
  maxSize,
  maxFiles,
  onFilesChange,
  onUpload,
  disabled = false,
  showFileList = true,
  className = '',
  children,
}: FileUploadProps) {
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const validateFile = (file: File): string | null => {
    if (maxSize && file.size > maxSize) {
      return `File too large. Max size: ${formatFileSize(maxSize)}`;
    }
    return null;
  };

  const processFiles = useCallback(
    (fileList: FileList | File[]) => {
      const newFiles: UploadFile[] = [];

      const filesToProcess = Array.from(fileList);
      const limit = maxFiles ? maxFiles - files.length : filesToProcess.length;

      for (let i = 0; i < Math.min(filesToProcess.length, limit); i++) {
        const file = filesToProcess[i];
        const error = validateFile(file);

        newFiles.push({
          file,
          id: generateId(),
          status: error ? 'error' : 'pending',
          progress: 0,
          error: error || undefined,
        });
      }

      const updatedFiles = multiple ? [...files, ...newFiles] : newFiles;
      setFiles(updatedFiles);
      onFilesChange?.(updatedFiles);

      // Auto upload if handler provided
      if (onUpload) {
        newFiles
          .filter((f) => f.status === 'pending')
          .forEach((f) => uploadFile(f.id));
      }
    },
    [files, maxFiles, maxSize, multiple, onFilesChange, onUpload]
  );

  const uploadFile = async (fileId: string) => {
    if (!onUpload) return;

    setFiles((prev) =>
      prev.map((f) =>
        f.id === fileId ? { ...f, status: 'uploading' as const, progress: 0 } : f
      )
    );

    const fileToUpload = files.find((f) => f.id === fileId);
    if (!fileToUpload) return;

    try {
      await onUpload(fileToUpload.file);
      setFiles((prev) =>
        prev.map((f) =>
          f.id === fileId ? { ...f, status: 'success' as const, progress: 100 } : f
        )
      );
    } catch (err) {
      setFiles((prev) =>
        prev.map((f) =>
          f.id === fileId
            ? { ...f, status: 'error' as const, error: 'Upload failed' }
            : f
        )
      );
    }
  };

  const removeFile = (fileId: string) => {
    const updatedFiles = files.filter((f) => f.id !== fileId);
    setFiles(updatedFiles);
    onFilesChange?.(updatedFiles);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    if (!disabled) setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    if (disabled) return;

    const droppedFiles = e.dataTransfer.files;
    if (droppedFiles.length > 0) {
      processFiles(droppedFiles);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFiles = e.target.files;
    if (selectedFiles && selectedFiles.length > 0) {
      processFiles(selectedFiles);
    }
    // Reset input
    e.target.value = '';
  };

  const handleClick = () => {
    if (!disabled) {
      inputRef.current?.click();
    }
  };

  return (
    <div className={`file-upload ${className}`}>
      {/* Drop zone */}
      <div
        className={`file-upload__dropzone ${isDragging ? 'file-upload__dropzone--dragging' : ''} ${
          disabled ? 'file-upload__dropzone--disabled' : ''
        }`}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={handleClick}
        role="button"
        tabIndex={disabled ? -1 : 0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') handleClick();
        }}
      >
        <input
          ref={inputRef}
          type="file"
          accept={accept}
          multiple={multiple}
          onChange={handleInputChange}
          className="file-upload__input"
          disabled={disabled}
        />

        {children || (
          <div className="file-upload__content">
            <div className="file-upload__icon">
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M19.35 10.04A7.49 7.49 0 0012 4C9.11 4 6.6 5.64 5.35 8.04A5.994 5.994 0 000 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5 5 5h-3z" />
              </svg>
            </div>
            <div className="file-upload__text">
              <span className="file-upload__text-primary">
                Drop files here or click to upload
              </span>
              {accept && (
                <span className="file-upload__text-secondary">
                  Accepted: {accept}
                </span>
              )}
            </div>
          </div>
        )}
      </div>

      {/* File list */}
      {showFileList && files.length > 0 && (
        <div className="file-upload__list">
          {files.map((file) => (
            <div
              key={file.id}
              className={`file-upload__file file-upload__file--${file.status}`}
            >
              <div className="file-upload__file-info">
                <span className="file-upload__file-name">{file.file.name}</span>
                <span className="file-upload__file-size">
                  {formatFileSize(file.file.size)}
                </span>
              </div>

              {file.status === 'uploading' && (
                <div className="file-upload__progress">
                  <div
                    className="file-upload__progress-bar"
                    style={{ width: `${file.progress}%` }}
                  />
                </div>
              )}

              {file.error && (
                <span className="file-upload__file-error">{file.error}</span>
              )}

              <button
                type="button"
                className="file-upload__file-remove"
                onClick={() => removeFile(file.id)}
                aria-label="Remove file"
              >
                ×
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default FileUpload;

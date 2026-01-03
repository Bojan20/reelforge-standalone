/**
 * ReelForge Error Boundary
 *
 * Centralized error handling for React component tree.
 * Catches JS errors, reports them, and shows fallback UI.
 */

import { Component, useState, useCallback, type ErrorInfo, type ReactNode } from 'react';

// ============ Error Types ============

export type ErrorCode =
  | 'RF_RENDER_ERROR'
  | 'RF_DSP_ERROR'
  | 'RF_AUDIO_CONTEXT_ERROR'
  | 'RF_PLUGIN_ERROR'
  | 'RF_PROJECT_ERROR'
  | 'RF_ROUTES_ERROR'
  | 'RF_NETWORK_ERROR'
  | 'RF_ASYNC_ERROR'
  | 'RF_UNKNOWN_ERROR';

export interface ReelForgeError {
  code: ErrorCode;
  message: string;
  originalError?: Error;
  componentStack?: string;
  timestamp: number;
  context?: Record<string, unknown>;
}

// ============ Error Registry ============

class ErrorRegistry {
  private errors: ReelForgeError[] = [];
  private maxErrors = 50;
  private listeners: Set<(errors: ReelForgeError[]) => void> = new Set();

  add(error: ReelForgeError): void {
    this.errors.unshift(error);
    if (this.errors.length > this.maxErrors) {
      this.errors.pop();
    }
    this.notify();
  }

  getAll(): ReelForgeError[] {
    return [...this.errors];
  }

  getRecent(count: number = 5): ReelForgeError[] {
    return this.errors.slice(0, count);
  }

  clear(): void {
    this.errors = [];
    this.notify();
  }

  subscribe(listener: (errors: ReelForgeError[]) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    this.listeners.forEach((listener) => listener(this.getAll()));
  }
}

export const errorRegistry = new ErrorRegistry();

// ============ Error Helpers ============

export function classifyError(error: Error): ErrorCode {
  const message = error.message.toLowerCase();

  if (message.includes('audiocontext') || message.includes('audio context')) {
    return 'RF_AUDIO_CONTEXT_ERROR';
  }
  if (message.includes('dsp') || message.includes('worklet')) {
    return 'RF_DSP_ERROR';
  }
  if (message.includes('plugin')) {
    return 'RF_PLUGIN_ERROR';
  }
  if (message.includes('project') || message.includes('manifest')) {
    return 'RF_PROJECT_ERROR';
  }
  if (message.includes('route') || message.includes('event')) {
    return 'RF_ROUTES_ERROR';
  }

  return 'RF_UNKNOWN_ERROR';
}

export function createReelForgeError(
  error: Error,
  componentStack?: string,
  context?: Record<string, unknown>
): ReelForgeError {
  return {
    code: classifyError(error),
    message: error.message,
    originalError: error,
    componentStack,
    timestamp: Date.now(),
    context,
  };
}

export function logError(error: ReelForgeError): void {
  const prefix = `[${error.code}]`;
  console.error(prefix, error.message);

  if (error.originalError?.stack) {
    console.error('Stack:', error.originalError.stack);
  }

  if (error.componentStack) {
    console.error('Component Stack:', error.componentStack);
  }

  if (error.context) {
    console.error('Context:', error.context);
  }

  errorRegistry.add(error);
}

// ============ Error Boundary Component ============

interface ErrorBoundaryProps {
  children: ReactNode;
  /** Fallback UI to show on error */
  fallback?: ReactNode | ((error: ReelForgeError, reset: () => void) => ReactNode);
  /** Error scope for context */
  scope?: string;
  /** Callback when error occurs */
  onError?: (error: ReelForgeError) => void;
  /** Whether to show detailed error info in fallback */
  showDetails?: boolean;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: ReelForgeError | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    return {
      hasError: true,
      error: createReelForgeError(error),
    };
  }

  override componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    const rfError = createReelForgeError(
      error,
      errorInfo.componentStack ?? undefined,
      { scope: this.props.scope }
    );

    // Update state with full error info
    this.setState({ error: rfError });

    // Log error
    logError(rfError);

    // Call error callback
    this.props.onError?.(rfError);
  }

  handleReset = (): void => {
    this.setState({ hasError: false, error: null });
  };

  override render(): ReactNode {
    if (this.state.hasError && this.state.error) {
      const { fallback, showDetails = false } = this.props;
      const { error } = this.state;

      // Custom fallback function
      if (typeof fallback === 'function') {
        return fallback(error, this.handleReset);
      }

      // Custom fallback element
      if (fallback) {
        return fallback;
      }

      // Default fallback UI
      return (
        <div className="rf-error-boundary">
          <div className="rf-error-boundary-icon">⚠️</div>
          <div className="rf-error-boundary-title">Something went wrong</div>
          <div className="rf-error-boundary-code">{error.code}</div>
          {showDetails && (
            <div className="rf-error-boundary-message">{error.message}</div>
          )}
          <button
            className="rf-error-boundary-retry"
            onClick={this.handleReset}
          >
            Try Again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

// ============ Specialized Boundaries ============

interface SectionErrorBoundaryProps {
  children: ReactNode;
  section: string;
}

export function SectionErrorBoundary({ children, section }: SectionErrorBoundaryProps) {
  return (
    <ErrorBoundary
      scope={section}
      fallback={(_error, reset) => (
        <div className="rf-section-error">
          <span className="rf-section-error-icon">⚠️</span>
          <span className="rf-section-error-text">{section} error</span>
          <button className="rf-section-error-retry" onClick={reset}>
            Retry
          </button>
        </div>
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

// ============ Component-Specific Boundaries ============

interface ComponentErrorFallbackProps {
  name: string;
  icon: string;
  onRetry: () => void;
  compact?: boolean;
}

function ComponentErrorFallback({ name, icon, onRetry, compact }: ComponentErrorFallbackProps) {
  if (compact) {
    return (
      <div className="rf-compact-error">
        <span className="rf-compact-error-icon">{icon}</span>
        <span className="rf-compact-error-text">{name}</span>
        <button className="rf-compact-error-btn" onClick={onRetry}>↺</button>
      </div>
    );
  }

  return (
    <div className="rf-component-error">
      <div className="rf-component-error-icon">{icon}</div>
      <div className="rf-component-error-title">{name} Error</div>
      <div className="rf-component-error-message">
        An error occurred in this component.
      </div>
      <button className="rf-component-error-retry" onClick={onRetry}>
        Reload {name}
      </button>
    </div>
  );
}

/**
 * Error boundary for Timeline component.
 */
export function TimelineErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      scope="timeline"
      fallback={(_error, reset) => (
        <ComponentErrorFallback
          name="Timeline"
          icon="📐"
          onRetry={reset}
        />
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

/**
 * Error boundary for Mixer component.
 */
export function MixerErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      scope="mixer"
      fallback={(_error, reset) => (
        <ComponentErrorFallback
          name="Mixer"
          icon="🎚️"
          onRetry={reset}
        />
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

/**
 * Error boundary for Plugin Editor.
 */
export function PluginEditorErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      scope="plugin-editor"
      fallback={(_error, reset) => (
        <ComponentErrorFallback
          name="Plugin"
          icon="🔌"
          onRetry={reset}
          compact
        />
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

/**
 * Error boundary for Inspector panel.
 */
export function InspectorErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      scope="inspector"
      fallback={(_error, reset) => (
        <ComponentErrorFallback
          name="Inspector"
          icon="🔍"
          onRetry={reset}
        />
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

/**
 * Error boundary for Browser/Tree panel.
 */
export function BrowserErrorBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary
      scope="browser"
      fallback={(_error, reset) => (
        <ComponentErrorFallback
          name="Browser"
          icon="📁"
          onRetry={reset}
        />
      )}
    >
      {children}
    </ErrorBoundary>
  );
}

// ============ Async Error Handling ============

/**
 * Safe async wrapper that catches and logs errors.
 * Use for async operations that shouldn't crash the app.
 */
export async function safeAsync<T>(
  operation: () => Promise<T>,
  context?: string
): Promise<{ success: true; data: T } | { success: false; error: ReelForgeError }> {
  try {
    const data = await operation();
    return { success: true, data };
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    const rfError = createReelForgeError(error, undefined, { context, async: true });

    // Override code for async errors
    rfError.code = error.message.includes('fetch') || error.message.includes('network')
      ? 'RF_NETWORK_ERROR'
      : 'RF_ASYNC_ERROR';

    logError(rfError);
    return { success: false, error: rfError };
  }
}

/**
 * Hook for handling async errors in React components.
 * Returns error state and wrapped async executor.
 */
export function useAsyncError(): {
  error: ReelForgeError | null;
  clearError: () => void;
  handleAsync: <T>(operation: () => Promise<T>, context?: string) => Promise<T | null>;
} {
  const [error, setError] = useState<ReelForgeError | null>(null);

  const clearError = useCallback(() => setError(null), []);

  const handleAsync = useCallback(async <T,>(
    operation: () => Promise<T>,
    context?: string
  ): Promise<T | null> => {
    const result = await safeAsync(operation, context);
    if (result.success) {
      return result.data;
    } else {
      setError(result.error);
      return null;
    }
  }, []);

  return { error, clearError, handleAsync };
}

// ============ Global Unhandled Error Handler ============

/**
 * Setup global handlers for unhandled promise rejections.
 * Call once at app initialization.
 */
export function setupGlobalErrorHandlers(): void {
  // Unhandled promise rejections
  window.addEventListener('unhandledrejection', (event) => {
    const error = event.reason instanceof Error
      ? event.reason
      : new Error(String(event.reason));

    const rfError = createReelForgeError(error, undefined, {
      type: 'unhandledrejection',
      async: true,
    });
    rfError.code = 'RF_ASYNC_ERROR';

    logError(rfError);

    // Prevent default browser error logging
    event.preventDefault();
  });

  // Global errors
  window.addEventListener('error', (event) => {
    const rfError = createReelForgeError(event.error || new Error(event.message), undefined, {
      type: 'error',
      filename: event.filename,
      lineno: event.lineno,
      colno: event.colno,
    });

    logError(rfError);
  });
}

export default ErrorBoundary;

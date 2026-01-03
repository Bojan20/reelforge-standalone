import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";
import { MixerProvider } from "./MixerContext";
import { ErrorBoundary, setupGlobalErrorHandlers } from "./components/ErrorBoundary";

// Setup global error handlers before React mounts
setupGlobalErrorHandlers();

// Root-level error fallback UI
function RootErrorFallback({ error, reset }: { error: { code: string; message: string }; reset: () => void }) {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100vh',
      background: '#1a1a2e',
      color: '#fff',
      fontFamily: 'system-ui, sans-serif',
      gap: '16px',
      padding: '24px',
      textAlign: 'center',
    }}>
      <div style={{ fontSize: '48px' }}>⚠️</div>
      <h1 style={{ margin: 0, fontSize: '24px', fontWeight: 600 }}>ReelForge Crashed</h1>
      <p style={{ margin: 0, color: '#888', maxWidth: '400px' }}>
        An unexpected error occurred. Your work may have been auto-saved.
      </p>
      <code style={{
        background: '#2a2a3e',
        padding: '8px 16px',
        borderRadius: '4px',
        fontSize: '12px',
        color: '#f87171',
      }}>
        {error.code}: {error.message}
      </code>
      <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
        <button
          onClick={reset}
          style={{
            padding: '10px 20px',
            background: '#3b82f6',
            color: '#fff',
            border: 'none',
            borderRadius: '6px',
            cursor: 'pointer',
            fontWeight: 500,
          }}
        >
          Try Again
        </button>
        <button
          onClick={() => window.location.reload()}
          style={{
            padding: '10px 20px',
            background: '#374151',
            color: '#fff',
            border: 'none',
            borderRadius: '6px',
            cursor: 'pointer',
            fontWeight: 500,
          }}
        >
          Reload App
        </button>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ErrorBoundary
      scope="root"
      showDetails
      fallback={(error, reset) => <RootErrorFallback error={error} reset={reset} />}
    >
      <MixerProvider>
        <App />
      </MixerProvider>
    </ErrorBoundary>
  </React.StrictMode>
);

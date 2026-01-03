/**
 * ReelForge Result
 *
 * Result page components:
 * - Success/Error/Warning/Info states
 * - Custom icons
 * - Action buttons
 * - Subtitle support
 *
 * @module result/Result
 */

import './Result.css';

// ============ Types ============

export type ResultStatus = 'success' | 'error' | 'warning' | 'info' | '404' | '403' | '500';

export interface ResultProps {
  /** Result status */
  status?: ResultStatus;
  /** Title */
  title?: React.ReactNode;
  /** Subtitle/description */
  subtitle?: React.ReactNode;
  /** Custom icon */
  icon?: React.ReactNode;
  /** Action buttons */
  extra?: React.ReactNode;
  /** Additional content */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Icons ============

function SuccessIcon() {
  return (
    <svg viewBox="0 0 64 64" className="result__icon result__icon--success">
      <circle cx="32" cy="32" r="30" fill="none" strokeWidth="3" />
      <path d="M20 32l8 8 16-16" fill="none" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function ErrorIcon() {
  return (
    <svg viewBox="0 0 64 64" className="result__icon result__icon--error">
      <circle cx="32" cy="32" r="30" fill="none" strokeWidth="3" />
      <path d="M22 22l20 20M42 22l-20 20" fill="none" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

function WarningIcon() {
  return (
    <svg viewBox="0 0 64 64" className="result__icon result__icon--warning">
      <path d="M32 6L4 58h56L32 6z" fill="none" strokeWidth="3" strokeLinejoin="round" />
      <path d="M32 26v16M32 48v2" fill="none" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

function InfoIcon() {
  return (
    <svg viewBox="0 0 64 64" className="result__icon result__icon--info">
      <circle cx="32" cy="32" r="30" fill="none" strokeWidth="3" />
      <path d="M32 20v2M32 28v16" fill="none" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

function NotFoundIcon() {
  return (
    <svg viewBox="0 0 120 80" className="result__icon result__icon--404">
      <text x="60" y="55" textAnchor="middle" fontSize="48" fontWeight="bold" fill="currentColor">404</text>
    </svg>
  );
}

function ForbiddenIcon() {
  return (
    <svg viewBox="0 0 120 80" className="result__icon result__icon--403">
      <text x="60" y="55" textAnchor="middle" fontSize="48" fontWeight="bold" fill="currentColor">403</text>
    </svg>
  );
}

function ServerErrorIcon() {
  return (
    <svg viewBox="0 0 120 80" className="result__icon result__icon--500">
      <text x="60" y="55" textAnchor="middle" fontSize="48" fontWeight="bold" fill="currentColor">500</text>
    </svg>
  );
}

// ============ Default Titles ============

const defaultTitles: Record<ResultStatus, string> = {
  success: 'Success',
  error: 'Error',
  warning: 'Warning',
  info: 'Information',
  '404': 'Page Not Found',
  '403': 'Access Denied',
  '500': 'Server Error',
};

const defaultSubtitles: Record<ResultStatus, string> = {
  success: 'Operation completed successfully.',
  error: 'Something went wrong.',
  warning: 'Please review this carefully.',
  info: 'Here is some information.',
  '404': 'The page you are looking for does not exist.',
  '403': 'You do not have permission to access this resource.',
  '500': 'An internal server error occurred.',
};

// ============ Result Component ============

export function Result({
  status = 'info',
  title,
  subtitle,
  icon,
  extra,
  children,
  className = '',
}: ResultProps) {
  const renderIcon = () => {
    if (icon) return icon;

    switch (status) {
      case 'success':
        return <SuccessIcon />;
      case 'error':
        return <ErrorIcon />;
      case 'warning':
        return <WarningIcon />;
      case 'info':
        return <InfoIcon />;
      case '404':
        return <NotFoundIcon />;
      case '403':
        return <ForbiddenIcon />;
      case '500':
        return <ServerErrorIcon />;
      default:
        return <InfoIcon />;
    }
  };

  return (
    <div className={`result result--${status} ${className}`}>
      <div className="result__icon-wrapper">{renderIcon()}</div>

      <div className="result__title">{title ?? defaultTitles[status]}</div>

      {(subtitle || defaultSubtitles[status]) && (
        <div className="result__subtitle">{subtitle ?? defaultSubtitles[status]}</div>
      )}

      {extra && <div className="result__extra">{extra}</div>}

      {children && <div className="result__content">{children}</div>}
    </div>
  );
}

// ============ Preset Components ============

export function SuccessResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="success" {...props} />;
}

export function ErrorResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="error" {...props} />;
}

export function WarningResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="warning" {...props} />;
}

export function InfoResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="info" {...props} />;
}

export function NotFoundResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="404" {...props} />;
}

export function ForbiddenResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="403" {...props} />;
}

export function ServerErrorResult(props: Omit<ResultProps, 'status'>) {
  return <Result status="500" {...props} />;
}

export default Result;

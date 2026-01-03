/**
 * ReelForge ConfigProvider
 *
 * Global configuration context:
 * - Theme settings
 * - Locale/i18n
 * - Component defaults
 * - Size presets
 *
 * @module config-provider/ConfigProvider
 */

import { createContext, useContext, useMemo } from 'react';
import './ConfigProvider.css';

// ============ Types ============

export type ThemeMode = 'dark' | 'light' | 'auto';
export type ComponentSize = 'small' | 'default' | 'large';

export interface ThemeConfig {
  /** Primary color */
  primaryColor?: string;
  /** Success color */
  successColor?: string;
  /** Warning color */
  warningColor?: string;
  /** Error color */
  errorColor?: string;
  /** Info color */
  infoColor?: string;
  /** Border radius */
  borderRadius?: number;
  /** Font family */
  fontFamily?: string;
  /** Motion enabled */
  motion?: boolean;
}

export interface LocaleConfig {
  /** Locale code */
  locale?: string;
  /** Empty text */
  empty?: string;
  /** Loading text */
  loading?: string;
  /** Confirm text */
  confirm?: string;
  /** Cancel text */
  cancel?: string;
  /** OK text */
  ok?: string;
  /** Close text */
  close?: string;
  /** Search placeholder */
  searchPlaceholder?: string;
  /** Select placeholder */
  selectPlaceholder?: string;
  /** Custom messages */
  messages?: Record<string, string>;
}

export interface ConfigProviderProps {
  /** Children */
  children: React.ReactNode;
  /** Theme mode */
  theme?: ThemeMode;
  /** Theme config */
  themeConfig?: ThemeConfig;
  /** Locale config */
  locale?: LocaleConfig;
  /** Component size */
  componentSize?: ComponentSize;
  /** Prefix for class names */
  prefixCls?: string;
  /** Icon prefix */
  iconPrefix?: string;
  /** Auto insert CSS variables */
  cssVariables?: boolean;
}

export interface ConfigContextValue {
  theme: ThemeMode;
  themeConfig: ThemeConfig;
  locale: LocaleConfig;
  componentSize: ComponentSize;
  prefixCls: string;
  iconPrefix: string;
  getPrefixCls: (component: string, customPrefix?: string) => string;
  t: (key: string, fallback?: string) => string;
}

// ============ Default Values ============

const defaultLocale: LocaleConfig = {
  locale: 'en',
  empty: 'No data',
  loading: 'Loading...',
  confirm: 'Confirm',
  cancel: 'Cancel',
  ok: 'OK',
  close: 'Close',
  searchPlaceholder: 'Search...',
  selectPlaceholder: 'Select...',
  messages: {},
};

const defaultThemeConfig: ThemeConfig = {
  primaryColor: '#6366f1',
  successColor: '#22c55e',
  warningColor: '#f59e0b',
  errorColor: '#ef4444',
  infoColor: '#3b82f6',
  borderRadius: 6,
  fontFamily: 'inherit',
  motion: true,
};

// ============ Context ============

const ConfigContext = createContext<ConfigContextValue>({
  theme: 'dark',
  themeConfig: defaultThemeConfig,
  locale: defaultLocale,
  componentSize: 'default',
  prefixCls: 'rf',
  iconPrefix: 'rf-icon',
  getPrefixCls: (component) => `rf-${component}`,
  t: (key, fallback) => fallback || key,
});

// ============ ConfigProvider Component ============

export function ConfigProvider({
  children,
  theme = 'dark',
  themeConfig = {},
  locale = {},
  componentSize = 'default',
  prefixCls = 'rf',
  iconPrefix = 'rf-icon',
  cssVariables = true,
}: ConfigProviderProps) {
  // Merge configs
  const mergedTheme = useMemo(
    () => ({ ...defaultThemeConfig, ...themeConfig }),
    [themeConfig]
  );

  const mergedLocale = useMemo(
    () => ({
      ...defaultLocale,
      ...locale,
      messages: { ...defaultLocale.messages, ...locale.messages },
    }),
    [locale]
  );

  // Get prefixed class name
  const getPrefixCls = (component: string, customPrefix?: string) => {
    return customPrefix || `${prefixCls}-${component}`;
  };

  // Translation function
  const t = (key: string, fallback?: string): string => {
    // Check custom messages first
    if (mergedLocale.messages?.[key]) {
      return mergedLocale.messages[key];
    }

    // Check locale keys
    const localeKey = key as keyof LocaleConfig;
    if (localeKey in mergedLocale && typeof mergedLocale[localeKey] === 'string') {
      return mergedLocale[localeKey] as string;
    }

    return fallback || key;
  };

  const contextValue: ConfigContextValue = useMemo(
    () => ({
      theme,
      themeConfig: mergedTheme,
      locale: mergedLocale,
      componentSize,
      prefixCls,
      iconPrefix,
      getPrefixCls,
      t,
    }),
    [theme, mergedTheme, mergedLocale, componentSize, prefixCls, iconPrefix]
  );

  // Generate CSS variables
  const cssVars = useMemo(() => {
    if (!cssVariables) return {};

    return {
      '--rf-primary': mergedTheme.primaryColor,
      '--rf-success': mergedTheme.successColor,
      '--rf-warning': mergedTheme.warningColor,
      '--rf-error': mergedTheme.errorColor,
      '--rf-info': mergedTheme.infoColor,
      '--rf-radius': `${mergedTheme.borderRadius}px`,
      '--rf-font-family': mergedTheme.fontFamily,
    } as React.CSSProperties;
  }, [cssVariables, mergedTheme]);

  return (
    <ConfigContext.Provider value={contextValue}>
      <div
        className={`config-provider config-provider--${theme} config-provider--${componentSize} ${
          !mergedTheme.motion ? 'config-provider--no-motion' : ''
        }`}
        style={cssVars}
        data-theme={theme}
      >
        {children}
      </div>
    </ConfigContext.Provider>
  );
}

// ============ useConfig Hook ============

export function useConfig() {
  return useContext(ConfigContext);
}

// ============ useTheme Hook ============

export function useTheme() {
  const { theme, themeConfig } = useContext(ConfigContext);
  return { theme, ...themeConfig };
}

// ============ useLocale Hook ============

export function useLocale() {
  const { locale, t } = useContext(ConfigContext);
  return { locale, t };
}

// ============ useSize Hook ============

export function useSize() {
  const { componentSize } = useContext(ConfigContext);
  return componentSize;
}

export { ConfigContext };
export default ConfigProvider;

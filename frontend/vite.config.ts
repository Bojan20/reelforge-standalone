import { defineConfig } from 'vite'
import { resolve } from 'path'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => ({
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
      '@audio': resolve(__dirname, 'src/audio'),
      '@core': resolve(__dirname, 'src/core'),
      '@components': resolve(__dirname, 'src/components'),
      '@hooks': resolve(__dirname, 'src/hooks'),
      '@utils': resolve(__dirname, 'src/utils'),
      '@tauri': resolve(__dirname, 'src/tauri'),
    },
  },
  // Strip console.log/warn in production builds
  esbuild: {
    drop: mode === 'production' ? ['console', 'debugger'] : [],
  },
  plugins: [
    react(),
  ],
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
      },
    },
    // Target modern browsers for Tauri
    target: ['es2021', 'chrome100', 'safari15'],
    minify: 'esbuild',
    sourcemap: mode !== 'production',
  },
  publicDir: 'public',
  server: {
    hmr: {
      timeout: 0,
      overlay: true,
    },
    watch: {
      usePolling: false,
      ignored: ['**/node_modules/**', '**/.git/**'],
    },
    strictPort: true,
    port: 5174,
    open: false,
    cors: true,
    host: true,
  },
  clearScreen: false,
  optimizeDeps: {
    force: false,
  },
}))

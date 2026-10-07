/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon.svg'],
      manifest: {
        name: 'Story Sounds', short_name: 'Story Sounds', description: 'Gentle daily phonics practice for early readers.',
        theme_color: '#2f6f5e', background_color: '#fff8ec', display: 'standalone', orientation: 'any', start_url: '.', scope: '.',
        icons: [{ src: 'icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any maskable' }],
      },
      workbox: { globPatterns: ['**/*.{js,css,html,svg,json,mp3,ogg,wav,webmanifest}'], navigateFallback: 'index.html' },
    }),
  ],
  test: { environment: 'jsdom', include: ['tests/unit/**/*.test.ts?(x)'], setupFiles: ['tests/unit/setup.ts'] },
});

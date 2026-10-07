import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: 'tests/e2e', timeout: 60_000, fullyParallel: false, workers: 1, retries: 0,
  use: { baseURL: 'http://localhost:4173', launchOptions: { executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' } },
  webServer: { command: 'npm run build && npm run preview', url: 'http://localhost:4173', reuseExistingServer: true, timeout: 180_000 },
  projects: [
    { name: 'phone', use: { viewport: { width: 390, height: 844 }, hasTouch: true } },
    { name: 'tablet', use: { viewport: { width: 820, height: 1180 }, hasTouch: true } },
  ],
});

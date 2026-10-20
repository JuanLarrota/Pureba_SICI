import { defineConfig, devices } from "@playwright/test";

// Los recorridos corren contra la aplicación en modo demo (Supabase de mentira
// con public/demo/datos.json): sin sesión real y sin tocar la base.
const PUERTO = process.env.PUERTO_PRUEBAS || "3199";

export default defineConfig({
  testDir: "./e2e",
  outputDir: "./e2e/salida",
  timeout: 60_000,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: `http://localhost:${PUERTO}`,
    screenshot: "only-on-failure",
    ...devices["iPhone 14"],   // primero el celular: su tamaño y su escala
    browserName: "chromium",   // solo se instala Chromium (npx playwright install chromium)
  },
  webServer: {
    command: `node scripts/demo/demo.mjs`,
    url: `http://localhost:${PUERTO}`,
    env: { PUERTO },
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});

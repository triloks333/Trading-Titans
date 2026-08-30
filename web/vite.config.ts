import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    // Pinned so the origin can be added to Supabase Auth -> URL Configuration ->
    // Redirect URLs. A random port cannot be allow-listed, which would break
    // Google sign-in and the guest upgrade.
    port: 5173,
    strictPort: true,
  },
})

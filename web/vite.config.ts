import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// GitHub Pages project site: https://futurifydesigns.github.io/Jobsy/
const isPages = process.env.GITHUB_PAGES === 'true'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: isPages ? '/Jobsy/' : '/',
  build: {
    // Avoid colliding with Flutter's top-level /assets folder on the same Pages root.
    assetsDir: 'site-assets',
  },
})

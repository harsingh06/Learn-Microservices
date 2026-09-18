import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The dev server plays the same reverse-proxy role nginx plays in the
// container: /api/* is forwarded to the services, so the app code is
// identical in dev and in production.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api/candidates': {
        target: 'http://localhost:5101',
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
      '/api/jobs': {
        target: 'http://localhost:5102',
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
      '/api/applications': {
        target: 'http://localhost:5103',
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
})

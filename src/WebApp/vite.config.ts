import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The dev server stands in for ACA's rule-based routing: /api/<resource>/* is
// forwarded to the owning service with the /api prefix stripped, so the app
// code is identical in dev and in Azure.
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

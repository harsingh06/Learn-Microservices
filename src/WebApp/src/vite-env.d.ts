/// <reference types="vite/client" />

// Build-time settings (VITE_* are inlined by Vite). Auth values: src/WebApp/.env.
interface ImportMetaEnv {
  readonly VITE_API_URL?: string
  readonly VITE_AUTH_TENANT_ID: string
  readonly VITE_AUTH_CLIENT_ID: string
  readonly VITE_API_SCOPE_CANDIDATES: string
  readonly VITE_API_SCOPE_JOBS: string
  readonly VITE_API_SCOPE_APPLICATIONS: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

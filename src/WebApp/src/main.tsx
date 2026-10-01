import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { MsalProvider } from '@azure/msal-react'
import './index.css'
import App from './App.tsx'
import { initializeAuth, msal } from './auth/msal'

// MSAL must be initialized before the first render; MsalProvider then handles the
// redirect back from Entra ID after sign-in.
void initializeAuth().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <MsalProvider instance={msal}>
        <App />
      </MsalProvider>
    </StrictMode>,
  )
})

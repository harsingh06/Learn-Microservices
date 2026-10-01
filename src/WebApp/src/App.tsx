import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react'
import { BrowserRouter, Navigate, NavLink, Route, Routes } from 'react-router-dom'
import CandidatesPage from './pages/CandidatesPage'
import JobsPage from './pages/JobsPage'
import ApplyPage from './pages/ApplyPage'
import ApplicationsPage from './pages/ApplicationsPage'
import { useRoles } from './auth/useRoles'

// Nothing but the sign-in page until the user has signed in with Entra ID.
export default function App() {
  return (
    <>
      <UnauthenticatedTemplate>
        <SignInPage />
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <SignedInApp />
      </AuthenticatedTemplate>
    </>
  )
}

function SignInPage() {
  const { instance } = useMsal()
  return (
    <main className="signin">
      <h1>Learn Microservices</h1>
      <p>Applicant tracking for recruiters and hiring managers.</p>
      <button type="button" onClick={() => void instance.loginRedirect()}>
        Sign in with Microsoft
      </button>
    </main>
  )
}

function SignedInApp() {
  const { instance } = useMsal()
  const { name, roles, isRecruiter } = useRoles()

  return (
    <BrowserRouter>
      <nav>
        <span className="brand">Learn Microservices</span>
        <NavLink to="/candidates">Candidates</NavLink>
        <NavLink to="/jobs">Jobs</NavLink>
        {isRecruiter && <NavLink to="/apply">Apply</NavLink>}
        <NavLink to="/applications">Applications</NavLink>
        <span className="user">
          {name} · {roles.length > 0 ? roles.join(', ') : 'no role'}
          <button type="button" onClick={() => void instance.logoutRedirect()}>Sign out</button>
        </span>
      </nav>
      <main>
        {roles.length === 0 && (
          <p className="error">Your account has no ATS role yet — ask an administrator to assign one.</p>
        )}
        <Routes>
          <Route path="/" element={<Navigate to="/candidates" replace />} />
          <Route path="/candidates" element={<CandidatesPage />} />
          <Route path="/jobs" element={<JobsPage />} />
          <Route
            path="/apply"
            element={isRecruiter ? <ApplyPage /> : <Navigate to="/applications" replace />}
          />
          <Route path="/applications" element={<ApplicationsPage />} />
        </Routes>
      </main>
    </BrowserRouter>
  )
}

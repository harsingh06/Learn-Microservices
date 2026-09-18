import { BrowserRouter, Navigate, NavLink, Route, Routes } from 'react-router-dom'
import CandidatesPage from './pages/CandidatesPage'
import JobsPage from './pages/JobsPage'
import ApplyPage from './pages/ApplyPage'
import ApplicationsPage from './pages/ApplicationsPage'

export default function App() {
  return (
    <BrowserRouter>
      <nav>
        <span className="brand">ATS</span>
        <NavLink to="/candidates">Candidates</NavLink>
        <NavLink to="/jobs">Jobs</NavLink>
        <NavLink to="/apply">Apply</NavLink>
        <NavLink to="/applications">Applications</NavLink>
      </nav>
      <main>
        <Routes>
          <Route path="/" element={<Navigate to="/candidates" replace />} />
          <Route path="/candidates" element={<CandidatesPage />} />
          <Route path="/jobs" element={<JobsPage />} />
          <Route path="/apply" element={<ApplyPage />} />
          <Route path="/applications" element={<ApplicationsPage />} />
        </Routes>
      </main>
    </BrowserRouter>
  )
}

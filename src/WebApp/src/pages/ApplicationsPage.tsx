import { useEffect, useState } from 'react'
import { listApplications, listCandidates, listJobs, updateApplicationStatus } from '../api'
import type { ApplicationStatus, Candidate, Job, JobApplication } from '../types'
import { ALL_STATUSES } from '../types'

export default function ApplicationsPage() {
  const [applications, setApplications] = useState<JobApplication[]>([])
  const [candidates, setCandidates] = useState<Candidate[]>([])
  const [jobs, setJobs] = useState<Job[]>([])
  const [candidateId, setCandidateId] = useState('')
  const [jobId, setJobId] = useState('')
  const [error, setError] = useState('')

  async function load(filter: { candidateId?: string; jobId?: string }) {
    try {
      setError('')
      setApplications(await listApplications(filter))
    } catch (e) {
      setError((e as Error).message)
    }
  }

  useEffect(() => {
    void load({})
    listCandidates().then(setCandidates).catch(() => {})
    listJobs().then(setJobs).catch(() => {})
  }, [])

  // The status workflow is enforced by ApplicationService; the UI just shows
  // the server's answer (including rejections of invalid transitions).
  async function handleStatusChange(application: JobApplication, status: ApplicationStatus) {
    try {
      setError('')
      const updated = await updateApplicationStatus(application.id, status)
      setApplications((current) => current.map((a) => (a.id === updated.id ? updated : a)))
    } catch (e) {
      setError((e as Error).message)
    }
  }

  function applyFilter(nextCandidateId: string, nextJobId: string) {
    setCandidateId(nextCandidateId)
    setJobId(nextJobId)
    void load({ candidateId: nextCandidateId || undefined, jobId: nextJobId || undefined })
  }

  return (
    <section>
      <h1>Applications</h1>
      {error && <p className="error">{error}</p>}

      <div className="row">
        <select value={candidateId} onChange={(e) => applyFilter(e.target.value, jobId)}>
          <option value="">All candidates</option>
          {candidates.map((c) => (
            <option key={c.id} value={c.id}>{c.fullName}</option>
          ))}
        </select>
        <select value={jobId} onChange={(e) => applyFilter(candidateId, e.target.value)}>
          <option value="">All jobs</option>
          {jobs.map((j) => (
            <option key={j.id} value={j.id}>{j.title}</option>
          ))}
        </select>
      </div>

      <table>
        <thead>
          <tr><th>Candidate</th><th>Job</th><th>Status</th><th>Submitted</th><th>Change status</th></tr>
        </thead>
        <tbody>
          {applications.map((a) => (
            <tr key={a.id}>
              <td>{a.candidateName}</td>
              <td>{a.jobTitle}</td>
              <td><span className={`status status-${a.status.toLowerCase()}`}>{a.status}</span></td>
              <td>{new Date(a.submittedAtUtc).toLocaleString()}</td>
              <td>
                <select
                  value={a.status}
                  onChange={(e) => void handleStatusChange(a, e.target.value as ApplicationStatus)}
                >
                  {ALL_STATUSES.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </td>
            </tr>
          ))}
          {applications.length === 0 && (
            <tr><td colSpan={5} className="empty">No applications yet.</td></tr>
          )}
        </tbody>
      </table>
    </section>
  )
}

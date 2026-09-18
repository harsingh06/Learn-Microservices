import { useEffect, useState } from 'react'
import { listCandidates, listJobs, submitApplication } from '../api'
import type { Candidate, Job } from '../types'

export default function ApplyPage() {
  const [candidates, setCandidates] = useState<Candidate[]>([])
  const [jobs, setJobs] = useState<Job[]>([])
  const [candidateId, setCandidateId] = useState('')
  const [jobId, setJobId] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  useEffect(() => {
    Promise.all([listCandidates(), listJobs()])
      .then(([c, j]) => {
        setCandidates(c)
        setJobs(j)
      })
      .catch((e: Error) => setError(e.message))
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setSuccess('')
    try {
      const application = await submitApplication(candidateId, jobId)
      setSuccess(`${application.candidateName} applied to "${application.jobTitle}".`)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <section>
      <h1>Apply to a job</h1>
      {error && <p className="error">{error}</p>}
      {success && <p className="success">{success}</p>}

      <form className="row" onSubmit={handleSubmit}>
        <select value={candidateId} onChange={(e) => setCandidateId(e.target.value)}>
          <option value="">Select a candidate…</option>
          {candidates.map((c) => (
            <option key={c.id} value={c.id}>{c.fullName}</option>
          ))}
        </select>
        <select value={jobId} onChange={(e) => setJobId(e.target.value)}>
          <option value="">Select a job…</option>
          {jobs.map((j) => (
            <option key={j.id} value={j.id}>{j.title}</option>
          ))}
        </select>
        <button type="submit" disabled={!candidateId || !jobId}>Apply</button>
      </form>
    </section>
  )
}

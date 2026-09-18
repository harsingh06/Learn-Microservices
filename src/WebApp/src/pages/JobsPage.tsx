import { useEffect, useState } from 'react'
import { createJob, listJobs } from '../api'
import type { Job } from '../types'

export default function JobsPage() {
  const [jobs, setJobs] = useState<Job[]>([])
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [location, setLocation] = useState('')
  const [error, setError] = useState('')

  async function load() {
    try {
      setError('')
      setJobs(await listJobs())
    } catch (e) {
      setError((e as Error).message)
    }
  }

  useEffect(() => {
    void load()
  }, [])

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    try {
      setError('')
      await createJob(title, description, location)
      setTitle('')
      setDescription('')
      setLocation('')
      await load()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <section>
      <h1>Jobs</h1>
      {error && <p className="error">{error}</p>}

      <form className="row" onSubmit={handleCreate}>
        <input placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
        <input
          placeholder="Description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />
        <input
          placeholder="Location (optional)"
          value={location}
          onChange={(e) => setLocation(e.target.value)}
        />
        <button type="submit">Add job</button>
      </form>

      <table>
        <thead>
          <tr><th>Title</th><th>Description</th><th>Location</th><th>Created</th></tr>
        </thead>
        <tbody>
          {jobs.map((j) => (
            <tr key={j.id}>
              <td>{j.title}</td>
              <td>{j.description}</td>
              <td>{j.location || '—'}</td>
              <td>{new Date(j.createdAtUtc).toLocaleString()}</td>
            </tr>
          ))}
          {jobs.length === 0 && (
            <tr><td colSpan={4} className="empty">No jobs yet.</td></tr>
          )}
        </tbody>
      </table>
    </section>
  )
}

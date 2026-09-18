import { useEffect, useState } from 'react'
import { createCandidate, listCandidates } from '../api'
import type { Candidate } from '../types'

export default function CandidatesPage() {
  const [candidates, setCandidates] = useState<Candidate[]>([])
  const [search, setSearch] = useState('')
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [error, setError] = useState('')

  async function load(term?: string) {
    try {
      setError('')
      setCandidates(await listCandidates(term))
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
      await createCandidate(fullName, email)
      setFullName('')
      setEmail('')
      await load(search)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <section>
      <h1>Candidates</h1>
      {error && <p className="error">{error}</p>}

      <form className="row" onSubmit={handleCreate}>
        <input
          placeholder="Full name"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
        />
        <input
          placeholder="Email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <button type="submit">Add candidate</button>
      </form>

      <div className="row">
        <input
          placeholder="Search by name…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button type="button" onClick={() => void load(search)}>Search</button>
        <button type="button" onClick={() => { setSearch(''); void load() }}>Clear</button>
      </div>

      <table>
        <thead>
          <tr><th>Name</th><th>Email</th><th>Created</th></tr>
        </thead>
        <tbody>
          {candidates.map((c) => (
            <tr key={c.id}>
              <td>{c.fullName}</td>
              <td>{c.email}</td>
              <td>{new Date(c.createdAtUtc).toLocaleString()}</td>
            </tr>
          ))}
          {candidates.length === 0 && (
            <tr><td colSpan={3} className="empty">No candidates yet.</td></tr>
          )}
        </tbody>
      </table>
    </section>
  )
}

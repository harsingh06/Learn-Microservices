import type { ApplicationStatus, Candidate, Job, JobApplication } from './types'

// Phase 1: the UI calls each service directly (no API gateway yet).
const CANDIDATE_API = import.meta.env.VITE_CANDIDATE_API ?? 'http://localhost:5101'
const JOB_API = import.meta.env.VITE_JOB_API ?? 'http://localhost:5102'
const APPLICATION_API = import.meta.env.VITE_APPLICATION_API ?? 'http://localhost:5103'

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  let response: Response
  try {
    response = await fetch(url, init)
  } catch {
    throw new Error(`Cannot reach ${new URL(url).origin} — is that service running?`)
  }
  if (!response.ok) {
    throw new Error(await readErrorMessage(response))
  }
  return response.json() as Promise<T>
}

// The APIs return error details as a JSON string ("...") for 400/409.
async function readErrorMessage(response: Response): Promise<string> {
  const text = await response.text()
  if (!text) return `Request failed with status ${response.status}`
  try {
    const parsed: unknown = JSON.parse(text)
    return typeof parsed === 'string' ? parsed : text
  } catch {
    return text
  }
}

function post<T>(url: string, body: unknown): Promise<T> {
  return request<T>(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

function put<T>(url: string, body: unknown): Promise<T> {
  return request<T>(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}

export function listCandidates(search?: string): Promise<Candidate[]> {
  const query = search ? `?search=${encodeURIComponent(search)}` : ''
  return request(`${CANDIDATE_API}/candidates${query}`)
}

export function createCandidate(fullName: string, email: string): Promise<Candidate> {
  return post(`${CANDIDATE_API}/candidates`, { fullName, email })
}

export function listJobs(): Promise<Job[]> {
  return request(`${JOB_API}/jobs`)
}

export function createJob(title: string, description: string, location: string): Promise<Job> {
  return post(`${JOB_API}/jobs`, { title, description, location })
}

export function listApplications(filter: { candidateId?: string; jobId?: string } = {}): Promise<JobApplication[]> {
  const params = new URLSearchParams()
  if (filter.candidateId) params.set('candidateId', filter.candidateId)
  if (filter.jobId) params.set('jobId', filter.jobId)
  const query = params.size > 0 ? `?${params}` : ''
  return request(`${APPLICATION_API}/applications${query}`)
}

export function submitApplication(candidateId: string, jobId: string): Promise<JobApplication> {
  return post(`${APPLICATION_API}/applications`, { candidateId, jobId })
}

export function updateApplicationStatus(id: string, status: ApplicationStatus): Promise<JobApplication> {
  return put(`${APPLICATION_API}/applications/${id}/status`, { status })
}

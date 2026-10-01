import type { ApplicationStatus, Candidate, Job, JobApplication } from './types'
import { apiScopes, getAccessToken } from './auth/msal'

// All API calls hit one base URL with /api/<resource>/* paths. In Azure the base
// is empty — the webapp and the APIs share one origin (the route config); in
// docker-compose it's the local dev-router (:5104); under `npm run dev` it's
// same-origin via Vite's proxy.
const API_BASE =
  import.meta.env.VITE_API_URL ?? (import.meta.env.DEV ? '' : 'http://localhost:5104')

// Every API is its own token audience: pick the scope of the service a path belongs to.
function scopeFor(url: string): string {
  if (url.includes('/api/candidates')) return apiScopes.candidates
  if (url.includes('/api/jobs')) return apiScopes.jobs
  if (url.includes('/api/applications')) return apiScopes.applications
  throw new Error(`No API scope configured for ${url}`)
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const headers = new Headers(init?.headers)
  headers.set('Authorization', `Bearer ${await getAccessToken(scopeFor(url))}`)

  let response: Response
  try {
    response = await fetch(url, { ...init, headers })
  } catch {
    throw new Error(`Cannot reach ${API_BASE || 'the API'} — is the stack running?`)
  }
  if (response.status === 401) {
    throw new Error('Your session has expired or the token was rejected — please sign out and in again.')
  }
  if (response.status === 403) {
    throw new Error("You don't have permission to do that.")
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
  return request(`${API_BASE}/api/candidates${query}`)
}

export function createCandidate(fullName: string, email: string): Promise<Candidate> {
  return post(`${API_BASE}/api/candidates`, { fullName, email })
}

export function listJobs(): Promise<Job[]> {
  return request(`${API_BASE}/api/jobs`)
}

export function createJob(title: string, description: string, location: string): Promise<Job> {
  return post(`${API_BASE}/api/jobs`, { title, description, location })
}

export function listApplications(filter: { candidateId?: string; jobId?: string } = {}): Promise<JobApplication[]> {
  const params = new URLSearchParams()
  if (filter.candidateId) params.set('candidateId', filter.candidateId)
  if (filter.jobId) params.set('jobId', filter.jobId)
  const query = params.size > 0 ? `?${params}` : ''
  return request(`${API_BASE}/api/applications${query}`)
}

export function submitApplication(candidateId: string, jobId: string): Promise<JobApplication> {
  return post(`${API_BASE}/api/applications`, { candidateId, jobId })
}

export function updateApplicationStatus(id: string, status: ApplicationStatus): Promise<JobApplication> {
  return put(`${API_BASE}/api/applications/${id}/status`, { status })
}

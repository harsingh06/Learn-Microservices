import type { ApplicationStatus, Candidate, Job, JobApplication } from './types'

// All API calls hit one base URL with /api/<resource>/* paths. In Azure the base
// is empty — the webapp and the APIs share one origin (the route config); in
// docker-compose it's the local dev-router (:5104); under `npm run dev` it's
// same-origin via Vite's proxy.
const API_BASE =
  import.meta.env.VITE_API_URL ?? (import.meta.env.DEV ? '' : 'http://localhost:5104')

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  let response: Response
  try {
    response = await fetch(url, init)
  } catch {
    throw new Error(`Cannot reach ${API_BASE || 'the API'} — is the stack running?`)
  }
  if (!response.ok) {
    throw new Error(await readErrorMessage(response))
  }
  return response.json() as Promise<T>
}

// The APIs return error details as a JSON string ("...") for 400/409, and as
// RFC 7807 problem details ({ title, detail }) for 503 — e.g. "CandidateService
// is temporarily unavailable" when a dependency can't be reached.
async function readErrorMessage(response: Response): Promise<string> {
  const text = await response.text()
  if (!text) return `Request failed with status ${response.status}`
  try {
    const parsed: unknown = JSON.parse(text)
    if (typeof parsed === 'string') return parsed
    if (isProblem(parsed)) return [parsed.title, parsed.detail].filter(Boolean).join('. ')
    return text
  } catch {
    return text
  }
}

function isProblem(value: unknown): value is { title?: string; detail?: string } {
  return typeof value === 'object' && value !== null && ('title' in value || 'detail' in value)
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

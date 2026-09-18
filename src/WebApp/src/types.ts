// The UI's own view of each service's API — mirrors the JSON contracts,
// not any C# class.

export interface Candidate {
  id: string
  fullName: string
  email: string
  createdAtUtc: string
}

export interface Job {
  id: string
  title: string
  description: string
  location: string
  createdAtUtc: string
}

export type ApplicationStatus = 'Submitted' | 'InReview' | 'Accepted' | 'Rejected'

export const ALL_STATUSES: ApplicationStatus[] = ['Submitted', 'InReview', 'Accepted', 'Rejected']

export interface JobApplication {
  id: string
  candidateId: string
  jobId: string
  candidateName: string
  jobTitle: string
  status: ApplicationStatus
  submittedAtUtc: string
}

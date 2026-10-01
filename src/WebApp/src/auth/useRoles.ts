import { useMsal } from '@azure/msal-react'

export type Role = 'Recruiter' | 'HiringManager'

// The signed-in user's ATS roles, from the ID token Entra issued to this app.
// Used only to show or hide actions — every API enforces the same rules itself,
// so hiding a button is about usability, not security.
export function useRoles() {
  const { instance, accounts } = useMsal()
  const account = instance.getActiveAccount() ?? accounts[0]
  const roles = (account?.idTokenClaims?.roles ?? []) as Role[]

  return {
    name: account?.name ?? account?.username ?? '',
    roles,
    isRecruiter: roles.includes('Recruiter'),
    isHiringManager: roles.includes('HiringManager'),
  }
}

/** Shared form validation for Jobsy web */

const EMAIL_RE =
  /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/

const PHONE_RE = /^[+]?[\d\s()-]{7,20}$/

export function validateEmail(value: string): string | null {
  const v = value.trim()
  if (!v) return 'Email is required'
  if (!EMAIL_RE.test(v)) return 'Enter a valid email address'
  return null
}

export function validateFullName(value: string): string | null {
  const v = value.trim()
  if (!v) return 'Full name is required'
  if (v.length < 2) return 'Name must be at least 2 characters'
  if (v.length > 80) return 'Name is too long'
  return null
}

export function validatePasswordSignIn(value: string): string | null {
  if (!value) return 'Password is required'
  return null
}

export type PasswordStrength = {
  score: 0 | 1 | 2 | 3 | 4
  label: string
  percent: number
  color: string
  ok: boolean
  hints: string[]
}

export function getPasswordStrength(password: string): PasswordStrength {
  const hints: string[] = []
  if (!password) {
    return { score: 0, label: 'Enter a password', percent: 0, color: '#94a3b8', ok: false, hints: [] }
  }

  let score = 0
  if (password.length >= 8) score += 1
  else hints.push('At least 8 characters')
  if (password.length >= 12) score += 1
  if (/[a-z]/.test(password) && /[A-Z]/.test(password)) score += 1
  else hints.push('Mix upper & lowercase')
  if (/\d/.test(password)) score += 1
  else hints.push('Add a number')
  if (/[^A-Za-z0-9]/.test(password)) score += 1
  else hints.push('Add a symbol')

  // Cap display score 0–4
  const capped = Math.min(4, score) as 0 | 1 | 2 | 3 | 4
  const labels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'] as const
  const colors = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#1E4FD7'] as const

  return {
    score: capped,
    label: labels[capped],
    percent: (capped / 4) * 100,
    color: colors[capped],
    ok: password.length >= 8 && capped >= 2,
    hints: hints.slice(0, 3),
  }
}

export function validatePasswordSignUp(value: string): string | null {
  if (!value) return 'Password is required'
  const s = getPasswordStrength(value)
  if (value.length < 8) return 'Password must be at least 8 characters'
  if (!s.ok) return 'Choose a stronger password (mix letters, numbers, or symbols)'
  return null
}

export function validatePhone(value: string, required = false): string | null {
  const v = value.trim()
  if (!v) return required ? 'Phone is required' : null
  if (!PHONE_RE.test(v)) return 'Enter a valid phone number'
  return null
}

export function validateRequired(value: string, label: string, min = 1): string | null {
  const v = value.trim()
  if (!v) return `${label} is required`
  if (v.length < min) return `${label} must be at least ${min} characters`
  return null
}

export function validatePositiveNumber(value: string, label: string): string | null {
  if (!value.trim()) return `${label} is required`
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return `Enter a valid ${label.toLowerCase()}`
  return null
}

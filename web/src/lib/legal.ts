/** Botswana Data Protection Act, 2024 (Act No. 18 of 2024) — Jobsy legal helpers */

export const LEGAL = {
  controller: 'Jobsy (operated by Futurify Designs)',
  email: 'futurifydesigns@gmail.com',
  jurisdiction: 'Republic of Botswana',
  act: 'Data Protection Act, 2024 (Act No. 18 of 2024)',
  commission: 'Information and Data Protection Commission (Botswana)',
  effective: '16 July 2026',
  websiteUrl: typeof window !== 'undefined' ? window.location.origin : '',
} as const

export const COOKIE_CONSENT_KEY = 'jobsy_cookie_consent'
export const COOKIE_PREFS_KEY = 'jobsy_cookie_prefs'

export type CookieConsentValue = 'accepted' | 'declined'

export type CookiePrefs = {
  essential: true
  analytics: boolean
  preferences: boolean
}

export const defaultPrefs = (enabled: boolean): CookiePrefs => ({
  essential: true,
  analytics: enabled,
  preferences: enabled,
})

export function readConsent(): CookieConsentValue | null {
  try {
    const v = localStorage.getItem(COOKIE_CONSENT_KEY)
    if (v === 'accepted' || v === 'declined') return v
  } catch {
    /* ignore */
  }
  return null
}

export function readPrefs(): CookiePrefs {
  const consent = readConsent()
  if (consent === 'accepted') {
    try {
      const raw = localStorage.getItem(COOKIE_PREFS_KEY)
      if (raw) {
        const parsed = JSON.parse(raw) as Partial<CookiePrefs>
        return {
          essential: true,
          analytics: Boolean(parsed.analytics),
          preferences: Boolean(parsed.preferences),
        }
      }
    } catch {
      /* ignore */
    }
    return defaultPrefs(true)
  }
  return defaultPrefs(false)
}

export function writeConsent(value: CookieConsentValue) {
  const prefs = defaultPrefs(value === 'accepted')
  try {
    localStorage.setItem(COOKIE_CONSENT_KEY, value)
    localStorage.setItem(COOKIE_PREFS_KEY, JSON.stringify(prefs))
  } catch {
    /* ignore */
  }
  // Mirror as a first-party cookie (1 year) for server-side awareness later
  const maxAge = 60 * 60 * 24 * 365
  document.cookie = `${COOKIE_CONSENT_KEY}=${value};path=/;max-age=${maxAge};SameSite=Lax`
  document.cookie = `${COOKIE_PREFS_KEY}=${encodeURIComponent(JSON.stringify(prefs))};path=/;max-age=${maxAge};SameSite=Lax`

  if (value === 'declined') {
    // Clear non-essential preference markers only (keep consent record)
    try {
      localStorage.removeItem('jobsy_analytics_id')
    } catch {
      /* ignore */
    }
  } else if (prefs.analytics) {
    try {
      if (!localStorage.getItem('jobsy_analytics_id')) {
        localStorage.setItem('jobsy_analytics_id', crypto.randomUUID())
      }
    } catch {
      /* ignore */
    }
  }

  window.dispatchEvent(
    new CustomEvent('jobsy:cookie-consent', { detail: { value, prefs } }),
  )
}

export function canUseAnalytics(): boolean {
  return readConsent() === 'accepted' && readPrefs().analytics
}

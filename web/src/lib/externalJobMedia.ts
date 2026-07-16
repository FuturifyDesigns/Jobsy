import type { ExternalJob } from './supabase'

/** Mirror Flutter ExternalJobPresentation image resolution. */
export function externalJobLogoUrl(job: ExternalJob): string | null {
  const meta = job.metadata
  if (!meta) return null
  for (const key of ['image_url', 'thumbnail', 'logo_url'] as const) {
    const raw = meta[key]
    if (typeof raw === 'string' && raw.trim().startsWith('http')) {
      return enhanceImageUrl(raw.trim(), true)
    }
  }
  return null
}

export function companyInitial(job: ExternalJob): string {
  const name = (job.company_name || job.title || '?').trim()
  return (name[0] || '?').toUpperCase()
}

/** Resize Google thumbs + clean broken encrypted-tbn suffixes (Flutter parity). */
export function enhanceImageUrl(url: string, forLogo: boolean): string {
  let u = url.trim()
  const lower = u.toLowerCase()

  // encrypted-tbn: never append size params (breaks load); strip bad =sXXX suffixes
  if (lower.includes('encrypted-tbn') || lower.includes('tbn:')) {
    return u.replace(/=s\d+(-c)?$/i, '')
  }

  if (lower.includes('googleusercontent.com')) {
    const target = forLogo ? 256 : 1200
    u = u.replace(/=s\d+(-c)?(?=&|$)/gi, `=s${target}`)
    if (!/=s\d+/i.test(u)) u = `${u}=s${target}`
    return u.replace(/&amp;/g, '&')
  }

  if (!forLogo) {
    u = u.replace(/=w\d+-h\d+/gi, '=w1200-h800')
  }
  return u
}

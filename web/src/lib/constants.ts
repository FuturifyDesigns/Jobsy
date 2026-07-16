/** GitHub Pages auth + legal (Supabase email redirects). */
export const PAGES_BASE = 'https://futurifydesigns.github.io/Jobsy'
export const AUTH_EMAIL_VERIFIED_URL = `${PAGES_BASE}/email-verified.html?from=web`
export const AUTH_RESET_PASSWORD_URL = `${PAGES_BASE}/reset-password.html`
/** Must match Supabase Auth → URL Configuration → Redirect URLs exactly. */
export const AUTH_OAUTH_CALLBACK_URL = `${PAGES_BASE}/auth/callback`

export const JOB_CATEGORIES = [
  'Construction',
  'Cleaning',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Painting',
  'Gardening',
  'Welding',
  'Masonry',
  'Roofing',
  'General Labor',
  'Administrative',
  'Retail & Sales',
  'Hospitality',
  'Security',
  'Transport & Driving',
  'Healthcare',
  'Technology',
  'Finance',
  'Other',
] as const

export const BUDGET_TYPES = ['fixed', 'hourly', 'daily', 'weekly'] as const

export const EXPERIENCE_LEVELS = ['beginner', 'intermediate', 'expert'] as const

export const BUSINESS_TYPES = [
  'Individual',
  'Small Business',
  'Company',
  'NGO',
  'Government',
  'Other',
] as const

export const JOB_SELECT =
  'id, title, description, category, location, budget_amount, budget_type, status, employer_id, created_at, required_skills, job_photos, experience_level, employer:profiles!jobs_employer_id_fkey(id, full_name, avatar_url, company_name)'

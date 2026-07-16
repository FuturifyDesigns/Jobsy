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
  'id, title, description, category, location, budget_amount, budget_type, status, employer_id, created_at, required_skills, job_photos, experience_level'

import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!url || !anonKey) {
  console.warn('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY')
}

export const supabase = createClient(url ?? '', anonKey ?? '', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
})

export type Profile = {
  id: string
  full_name: string | null
  user_type: 'worker' | 'employer' | string | null
  avatar_url: string | null
  location: string | null
  bio: string | null
  phone: string | null
  skills: string[] | null
  company_name: string | null
  business_type: string | null
  hourly_rate: number | null
  experience_level: string | null
  rating: number | null
  is_profile_complete: boolean | null
  last_role_switch_at: string | null
}

export type Job = {
  id: string
  title: string
  description: string | null
  category: string | null
  location: string | null
  budget_amount: number | null
  budget_type: string | null
  status: string | null
  employer_id: string | null
  created_at: string
  required_skills: string[] | null
  job_photos: string[] | null
  experience_level: string | null
}

export type ExternalJob = {
  id: string
  title: string
  description: string | null
  category: string | null
  location: string | null
  company_name: string | null
  salary_text: string | null
  external_url: string
  source: string
  posted_at: string | null
  is_active: boolean | null
  metadata: Record<string, unknown> | null
}

export type JobApplication = {
  id: string
  job_id: string
  worker_id: string
  status: string
  cover_letter: string | null
  created_at: string
  updated_at: string | null
  worker?: {
    id: string
    full_name: string | null
    avatar_url: string | null
    location: string | null
    skills: string[] | null
    rating: number | null
  } | null
}

export type ChatMessage = {
  id: string
  conversation_id: string
  sender_id: string
  message: string | null
  message_type: string | null
  attachment_url: string | null
  attachment_meta: Record<string, unknown> | null
  created_at: string
}

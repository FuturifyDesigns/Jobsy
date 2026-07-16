import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { supabase, type Job } from '../../lib/supabase'
import { useAuth } from '../../lib/auth'
import { Avatar } from '../../components/Avatar'
import { GlassCard, PageHero, useStaggerReveal } from '../../components/AppUi'

export function JobsPage() {
  const { user } = useAuth()
  const [jobs, setJobs] = useState<Job[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)

  useStaggerReveal(rootRef, [loading, jobs.length, query], '.job-card-reveal')

  useEffect(() => {
    let alive = true

    async function load() {
      setLoading(true)
      const { data, error: err } = await supabase
        .from('jobs')
        .select(JOB_SELECT)
        .eq('status', 'active')
        .order('created_at', { ascending: false })
        .limit(60)

      if (!alive) return
      if (err) {
        const fb = await supabase
          .from('jobs')
          .select(
            'id, title, description, category, location, budget_amount, budget_type, status, employer_id, created_at, required_skills, job_photos, experience_level',
          )
          .eq('status', 'active')
          .order('created_at', { ascending: false })
          .limit(60)
        if (fb.error) setError(fb.error.message)
        else {
          const rows = (fb.data as unknown as Job[]) ?? []
          const withEmployers = await Promise.all(
            rows.map(async (job) => {
              if (!job.employer_id) return job
              const { data: emp } = await supabase
                .from('profiles')
                .select('id, full_name, avatar_url, company_name')
                .eq('id', job.employer_id)
                .maybeSingle()
              return { ...job, employer: emp }
            }),
          )
          setJobs(withEmployers)
        }
      } else setJobs((data as unknown as Job[]) ?? [])
      setLoading(false)
    }

    void load()

    const channel = supabase
      .channel('web-jobs-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'jobs' }, () => void load())
      .subscribe()

    return () => {
      alive = false
      void supabase.removeChannel(channel)
    }
  }, [])

  const filtered = jobs.filter((j) => {
    const q = query.trim().toLowerCase()
    if (!q) return true
    return (
      j.title.toLowerCase().includes(q) ||
      (j.location ?? '').toLowerCase().includes(q) ||
      (j.category ?? '').toLowerCase().includes(q) ||
      (j.employer?.full_name ?? '').toLowerCase().includes(q) ||
      (j.employer?.company_name ?? '').toLowerCase().includes(q)
    )
  })

  return (
    <div ref={rootRef}>
      <PageHero
        brush="Nearby work"
        title="Find Jobs"
        subtitle="Browse live postings from employers across Botswana."
        action={
          <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:flex-wrap">
            <Link
              to="/app/saved"
              className="rounded-full border border-white/15 px-4 py-2 text-center text-sm font-semibold text-white/80 hover:border-white/35"
            >
              Saved
            </Link>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search title, city, company…"
              className="w-full rounded-full border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white outline-none placeholder:text-white/35 focus:border-paint/40 focus:ring-2 focus:ring-paint/30 sm:min-w-[16rem]"
            />
          </div>
        }
      />

      {loading && <p className="text-white/50">Loading jobs…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && !error && filtered.length === 0 && (
        <p className="text-white/50">No active jobs yet. Check Web Jobs.</p>
      )}

      <div className="grid gap-3">
        {filtered.map((job) => {
          const poster = job.employer?.company_name || job.employer?.full_name || 'Employer'
          return (
            <Link key={job.id} to={`/app/jobs/${job.id}`} className="job-card-reveal block">
              <GlassCard>
                <div className="flex items-start gap-2.5 sm:gap-3">
                  <Avatar url={job.employer?.avatar_url} name={poster} size="md" />
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div className="min-w-0">
                        <h2 className="text-base font-semibold text-white sm:text-lg">{job.title}</h2>
                        <p className="mt-1 text-sm text-white/50">
                          {poster}
                          {[job.category, job.location].filter(Boolean).length
                            ? ` · ${[job.category, job.location].filter(Boolean).join(' · ')}`
                            : ''}
                        </p>
                      </div>
                      {job.budget_amount != null && (
                        <p className="shrink-0 rounded-full bg-paint/15 px-3 py-1 text-sm font-bold text-paint-soft">
                          P{job.budget_amount}
                          {job.budget_type ? ` / ${job.budget_type}` : ''}
                        </p>
                      )}
                    </div>
                    {job.description && (
                      <p className="mt-3 line-clamp-2 text-sm leading-relaxed text-white/55">{job.description}</p>
                    )}
                    {user && job.employer_id === user.id && (
                      <p className="mt-2 text-xs text-white/35">Your posting</p>
                    )}
                  </div>
                </div>
              </GlassCard>
            </Link>
          )
        })}
      </div>
    </div>
  )
}

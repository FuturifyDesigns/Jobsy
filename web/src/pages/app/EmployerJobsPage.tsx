import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase, type Job } from '../../lib/supabase'
import { Avatar } from '../../components/Avatar'
import { GlassCard, PageHero, StatusPill, useStaggerReveal } from '../../components/AppUi'

export function EmployerJobsPage() {
  const { user, profile } = useAuth()
  const [jobs, setJobs] = useState<Job[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)

  useStaggerReveal(rootRef, [loading, jobs.length], '.job-card-reveal')

  useEffect(() => {
    if (!user) return
    let alive = true

    async function load() {
      setLoading(true)
      const { data, error: err } = await supabase
        .from('jobs')
        .select(JOB_SELECT)
        .eq('employer_id', user!.id)
        .order('created_at', { ascending: false })
        .limit(80)
      if (!alive) return
      if (err) {
        // Fallback without employer join
        const fb = await supabase
          .from('jobs')
          .select(
            'id, title, description, category, location, budget_amount, budget_type, status, employer_id, created_at, required_skills, job_photos, experience_level',
          )
          .eq('employer_id', user!.id)
          .order('created_at', { ascending: false })
          .limit(80)
        if (fb.error) setError(fb.error.message)
        else setJobs((fb.data as unknown as Job[]) ?? [])
      } else setJobs((data as unknown as Job[]) ?? [])
      setLoading(false)
    }

    void load()
    const channel = supabase
      .channel('employer-jobs')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'jobs' }, () => void load())
      .subscribe()

    return () => {
      alive = false
      void supabase.removeChannel(channel)
    }
  }, [user])

  return (
    <div ref={rootRef}>
      <PageHero
        brush="Hiring"
        title="My Jobs"
        subtitle="Manage postings, review applicants, and keep hiring moving."
        action={
          <Link
            to="/app/post"
            className="inline-flex rounded-full bg-paint px-4 py-2.5 text-sm font-bold text-white shadow-[0_16px_40px_-18px_rgba(30,79,215,0.85)] transition hover:brightness-110 sm:px-5"
          >
            Post a Job
          </Link>
        }
      />

      {loading && <p className="text-white/50">Loading…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && jobs.length === 0 && (
        <GlassCard hover={false} className="text-center !py-12">
          <p className="text-white/55">No jobs yet. Post your first one.</p>
          <Link to="/app/post" className="mt-4 inline-flex text-sm font-semibold text-paint-soft hover:underline">
            Create a posting →
          </Link>
        </GlassCard>
      )}

      <div className="grid gap-3">
        {jobs.map((job) => (
          <GlassCard key={job.id} className="job-card-reveal">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex min-w-0 flex-1 gap-2.5 sm:gap-3">
                <Avatar
                  url={profile?.avatar_url}
                  name={profile?.full_name ?? profile?.company_name}
                  size="md"
                />
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="truncate text-base font-semibold sm:text-lg">{job.title}</h2>
                    <StatusPill status={job.status} />
                  </div>
                  <p className="mt-1 text-sm text-white/50">
                    {[job.category, job.location].filter(Boolean).join(' · ') || 'Botswana'}
                  </p>
                </div>
              </div>
              {job.budget_amount != null && (
                <p className="shrink-0 rounded-full bg-paint/15 px-3 py-1 text-sm font-bold text-paint-soft">
                  P{job.budget_amount}
                  {job.budget_type ? ` / ${job.budget_type}` : ''}
                </p>
              )}
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              <Link
                to={`/app/jobs/${job.id}/applications`}
                className="rounded-full bg-white px-4 py-2 text-xs font-bold text-black transition hover:scale-[1.02]"
              >
                Applications
              </Link>
              <Link
                to={`/app/jobs/${job.id}`}
                className="rounded-full border border-white/15 px-4 py-2 text-xs font-semibold text-white/80 hover:border-white/35"
              >
                View
              </Link>
            </div>
          </GlassCard>
        ))}
      </div>
    </div>
  )
}

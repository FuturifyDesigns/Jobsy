import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase, type Job } from '../../lib/supabase'
import { Avatar } from '../../components/Avatar'
import { GlassCard, PageHero } from '../../components/AppUi'

export function SavedJobsPage() {
  const { user } = useAuth()
  const [jobs, setJobs] = useState<Job[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!user) return
    let alive = true

    async function load() {
      setLoading(true)
      const { data: saved, error: err } = await supabase
        .from('saved_jobs')
        .select('job_id')
        .eq('worker_id', user!.id)
      if (!alive) return
      if (err) {
        setError(err.message)
        setLoading(false)
        return
      }
      const ids = (saved ?? []).map((r) => r.job_id as string)
      if (ids.length === 0) {
        setJobs([])
        setLoading(false)
        return
      }
      const { data: jobRows, error: jobErr } = await supabase
        .from('jobs')
        .select(JOB_SELECT)
        .in('id', ids)
      if (!alive) return
      if (jobErr) setError(jobErr.message)
      else setJobs((jobRows as unknown as Job[]) ?? [])
      setLoading(false)
    }

    void load()
    return () => {
      alive = false
    }
  }, [user])

  async function unsave(jobId: string) {
    if (!user) return
    await supabase.from('saved_jobs').delete().eq('job_id', jobId).eq('worker_id', user.id)
    setJobs((prev) => prev.filter((j) => j.id !== jobId))
  }

  return (
    <div>
      <PageHero
        brush="Bookmarks"
        title="Saved Jobs"
        subtitle="Jobs you want to revisit later."
      />
      {loading && <p className="text-white/50">Loading…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && jobs.length === 0 && (
        <p className="text-white/50">
          No saved jobs yet. Tap Save on a listing in{' '}
          <Link to="/app" className="text-paint-soft hover:underline">
            Find Jobs
          </Link>
          .
        </p>
      )}
      <div className="grid gap-3">
        {jobs.map((job) => {
          const poster = job.employer?.company_name || job.employer?.full_name || 'Employer'
          return (
            <GlassCard key={job.id}>
              <Link to={`/app/jobs/${job.id}`} className="flex items-start gap-2.5 sm:gap-3">
                <Avatar url={job.employer?.avatar_url} name={poster} size="md" />
                <div className="min-w-0 flex-1">
                  <h2 className="text-base font-semibold hover:text-paint-soft sm:text-lg">{job.title}</h2>
                  <p className="mt-1 text-sm text-white/50">
                    {poster}
                    {[job.category, job.location].filter(Boolean).length
                      ? ` · ${[job.category, job.location].filter(Boolean).join(' · ')}`
                      : ''}
                  </p>
                  {job.budget_amount != null && (
                    <p className="mt-2 text-sm font-semibold text-paint-soft">
                      P{job.budget_amount}
                      {job.budget_type ? ` / ${job.budget_type}` : ''}
                    </p>
                  )}
                </div>
              </Link>
              <button
                type="button"
                onClick={() => void unsave(job.id)}
                className="mt-3 text-xs font-semibold text-white/45 hover:text-white"
              >
                Remove
              </button>
            </GlassCard>
          )
        })}
      </div>
    </div>
  )
}

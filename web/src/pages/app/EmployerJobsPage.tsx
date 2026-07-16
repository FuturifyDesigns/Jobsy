import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase, type Job } from '../../lib/supabase'

export function EmployerJobsPage() {
  const { user } = useAuth()
  const [jobs, setJobs] = useState<Job[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

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
      if (err) setError(err.message)
      else setJobs((data as Job[]) ?? [])
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
    <div>
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="font-[family-name:var(--font-brush)] text-2xl text-[#4d7ef0]" style={{ fontWeight: 700 }}>
            Hiring
          </p>
          <h1 className="font-[family-name:var(--font-display)] text-3xl tracking-tight" style={{ fontWeight: 800 }}>
            My Jobs
          </h1>
        </div>
        <Link
          to="/app/post"
          className="inline-flex rounded-full bg-[#1e4fd7] px-5 py-2.5 text-sm font-semibold text-white"
        >
          Post a Job
        </Link>
      </div>

      {loading && <p className="text-white/50">Loading…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && jobs.length === 0 && (
        <p className="text-white/50">No jobs yet. Post your first one.</p>
      )}

      <div className="grid gap-3">
        {jobs.map((job) => (
          <div
            key={job.id}
            className="rounded-2xl border border-white/8 bg-white/[0.03] p-4"
          >
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold">{job.title}</h2>
                <p className="mt-1 text-sm text-white/50">
                  {[job.category, job.location, job.status].filter(Boolean).join(' · ')}
                </p>
              </div>
              {job.budget_amount != null && (
                <p className="text-sm font-semibold text-[#4d7ef0]">
                  P{job.budget_amount}
                  {job.budget_type ? ` / ${job.budget_type}` : ''}
                </p>
              )}
            </div>
            <div className="mt-4 flex flex-wrap gap-2">
              <Link
                to={`/app/jobs/${job.id}/applications`}
                className="rounded-full bg-white px-4 py-2 text-xs font-bold text-ink"
              >
                Applications
              </Link>
              <Link
                to={`/app/jobs/${job.id}`}
                className="rounded-full border border-white/15 px-4 py-2 text-xs font-semibold text-white/80"
              >
                View
              </Link>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

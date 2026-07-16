import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase, type Job } from '../../lib/supabase'

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
      else setJobs((jobRows as Job[]) ?? [])
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
      <h1
        className="mb-6 font-[family-name:var(--font-display)] text-3xl tracking-tight"
        style={{ fontWeight: 800 }}
      >
        Saved Jobs
      </h1>
      {loading && <p className="text-white/50">Loading…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && jobs.length === 0 && (
        <p className="text-white/50">
          No saved jobs yet. Tap Save on a listing in{' '}
          <Link to="/app" className="text-[#4d7ef0] hover:underline">
            Find Jobs
          </Link>
          .
        </p>
      )}
      <div className="grid gap-3">
        {jobs.map((job) => (
          <div
            key={job.id}
            className="rounded-2xl border border-white/8 bg-white/[0.03] p-4"
          >
            <Link to={`/app/jobs/${job.id}`}>
              <h2 className="text-lg font-semibold hover:text-[#4d7ef0]">{job.title}</h2>
              <p className="mt-1 text-sm text-white/50">
                {[job.category, job.location].filter(Boolean).join(' · ')}
              </p>
              {job.budget_amount != null && (
                <p className="mt-2 text-sm font-semibold text-[#4d7ef0]">
                  P{job.budget_amount}
                  {job.budget_type ? ` / ${job.budget_type}` : ''}
                </p>
              )}
            </Link>
            <button
              type="button"
              onClick={() => void unsave(job.id)}
              className="mt-3 text-xs font-semibold text-white/45 hover:text-white"
            >
              Remove
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

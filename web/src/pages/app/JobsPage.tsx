import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { supabase, type Job } from '../../lib/supabase'
import { useAuth } from '../../lib/auth'

export function JobsPage() {
  const { user } = useAuth()
  const [jobs, setJobs] = useState<Job[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

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
      if (err) setError(err.message)
      else setJobs((data as Job[]) ?? [])
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
      (j.category ?? '').toLowerCase().includes(q)
    )
  })

  return (
    <div>
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="font-[family-name:var(--font-brush)] text-2xl text-[#4d7ef0]" style={{ fontWeight: 700 }}>
            Nearby work
          </p>
          <h1 className="font-[family-name:var(--font-display)] text-3xl tracking-tight" style={{ fontWeight: 800 }}>
            Find Jobs
          </h1>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            to="/app/saved"
            className="rounded-full border border-white/15 px-4 py-2 text-sm font-semibold text-white/80 hover:border-white/35"
          >
            Saved
          </Link>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search title, city, category…"
            className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white outline-none ring-[#1e4fd7]/40 placeholder:text-white/35 focus:ring-2 sm:max-w-xs"
          />
        </div>
      </div>

      {loading && <p className="text-white/50">Loading jobs…</p>}
      {error && <p className="text-red-400">{error}</p>}
      {!loading && !error && filtered.length === 0 && (
        <p className="text-white/50">No active jobs yet. Check Web Jobs.</p>
      )}

      <div className="grid gap-3">
        {filtered.map((job) => (
          <Link
            key={job.id}
            to={`/app/jobs/${job.id}`}
            className="block rounded-2xl border border-white/8 bg-white/[0.03] p-4 transition hover:border-[#1e4fd7]/45 hover:bg-white/[0.05]"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold text-white">{job.title}</h2>
                <p className="mt-1 text-sm text-white/50">
                  {[job.category, job.location].filter(Boolean).join(' · ') || 'Botswana'}
                </p>
              </div>
              {job.budget_amount != null && (
                <p className="shrink-0 text-sm font-semibold text-[#4d7ef0]">
                  P{job.budget_amount}
                  {job.budget_type ? ` / ${job.budget_type}` : ''}
                </p>
              )}
            </div>
            {job.description && (
              <p className="mt-3 line-clamp-2 text-sm leading-relaxed text-white/60">{job.description}</p>
            )}
            {user && job.employer_id === user.id && (
              <p className="mt-2 text-xs text-white/35">Your posting</p>
            )}
          </Link>
        ))}
      </div>
    </div>
  )
}

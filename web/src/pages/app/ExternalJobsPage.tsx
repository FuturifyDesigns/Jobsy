import { useEffect, useState } from 'react'
import { supabase, type ExternalJob } from '../../lib/supabase'

export function ExternalJobsPage() {
  const [jobs, setJobs] = useState<ExternalJob[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true

    async function load() {
      setLoading(true)
      const { data } = await supabase
        .from('external_jobs')
        .select(
          'id, title, description, category, location, company_name, salary_text, external_url, source, posted_at, is_active, metadata',
        )
        .eq('is_active', true)
        .order('posted_at', { ascending: false })
        .limit(80)
      if (alive) {
        setJobs((data as ExternalJob[]) ?? [])
        setLoading(false)
      }
    }

    void load()

    const channel = supabase
      .channel('web-external-jobs')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'external_jobs' },
        () => void load(),
      )
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
      (j.company_name ?? '').toLowerCase().includes(q) ||
      (j.location ?? '').toLowerCase().includes(q) ||
      j.source.toLowerCase().includes(q)
    )
  })

  return (
    <div>
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="font-[family-name:var(--font-brush)] text-2xl text-[#4d7ef0]" style={{ fontWeight: 700 }}>
            From the boards
          </p>
          <h1
            className="font-[family-name:var(--font-display)] text-3xl tracking-tight"
            style={{ fontWeight: 800 }}
          >
            Web Jobs
          </h1>
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search imported listings…"
          className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm outline-none ring-[#1e4fd7]/40 placeholder:text-white/35 focus:ring-2 sm:max-w-xs"
        />
      </div>

      {loading && <p className="text-white/50">Loading…</p>}
      {!loading && filtered.length === 0 && (
        <p className="text-white/50">No web jobs yet — run the import edge function.</p>
      )}

      <div className="grid gap-3">
        {filtered.map((job) => (
          <a
            key={job.id}
            href={job.external_url}
            target="_blank"
            rel="noreferrer"
            className="block rounded-2xl border border-white/8 bg-white/[0.03] p-4 transition hover:border-[#1e4fd7]/45"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-semibold">{job.title}</h2>
                <p className="mt-1 text-sm text-white/50">
                  {[job.company_name, job.location, sourceLabel(job.source)]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
              </div>
              {job.salary_text && (
                <p className="shrink-0 text-sm text-[#4d7ef0]">{job.salary_text}</p>
              )}
            </div>
            {job.description && (
              <p className="mt-3 line-clamp-2 text-sm text-white/55">{job.description}</p>
            )}
          </a>
        ))}
      </div>
    </div>
  )
}

function sourceLabel(source: string) {
  if (source === 'google_jobs') return 'Google Jobs'
  if (source === 'facebook') return 'Facebook'
  return source.replace(/_/g, ' ')
}

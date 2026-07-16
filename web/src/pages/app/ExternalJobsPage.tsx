import { useEffect, useRef, useState } from 'react'
import { supabase, type ExternalJob } from '../../lib/supabase'
import { companyInitial, externalJobLogoUrl } from '../../lib/externalJobMedia'
import { GlassCard, PageHero, useStaggerReveal } from '../../components/AppUi'

export function ExternalJobsPage() {
  const [jobs, setJobs] = useState<ExternalJob[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const rootRef = useRef<HTMLDivElement>(null)

  useStaggerReveal(rootRef, [loading, jobs.length, query])

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
    <div ref={rootRef}>
      <PageHero
        brush="From the boards"
        title="Web Jobs"
        subtitle="Imported listings from Google Jobs and other boards — open on the original site to apply."
        action={
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search company, city, source…"
            className="w-full rounded-full border border-white/10 bg-white/5 px-4 py-2.5 text-sm outline-none placeholder:text-white/35 focus:border-paint/40 focus:ring-2 focus:ring-paint/30 sm:min-w-[16rem]"
          />
        }
      />

      {loading && <p className="text-white/50">Loading…</p>}
      {!loading && filtered.length === 0 && (
        <GlassCard hover={false} className="text-center !py-12">
          <p className="text-white/50">No web jobs yet — run the import edge function.</p>
        </GlassCard>
      )}

      <div className="grid gap-3">
        {filtered.map((job) => (
          <a
            key={job.id}
            href={job.external_url}
            target="_blank"
            rel="noreferrer"
            className="reveal-item block"
          >
            <GlassCard>
              <div className="flex items-start gap-3.5">
                <CompanyLogoTile job={job} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="min-w-0">
                      <h2 className="text-lg font-semibold text-white transition group-hover:text-paint-soft">
                        {job.title}
                      </h2>
                      <p className="mt-1 text-sm text-white/50">
                        {[job.company_name, job.location, sourceLabel(job.source)]
                          .filter(Boolean)
                          .join(' · ')}
                      </p>
                    </div>
                    {job.salary_text && (
                      <p className="shrink-0 rounded-full bg-paint/15 px-3 py-1 text-sm font-bold text-paint-soft">
                        {job.salary_text}
                      </p>
                    )}
                  </div>
                  {job.description && (
                    <p className="mt-3 line-clamp-2 text-sm leading-relaxed text-white/55">{job.description}</p>
                  )}
                  <p className="mt-3 text-xs font-semibold tracking-wide text-paint-soft/80 uppercase">
                    Open listing →
                  </p>
                </div>
              </div>
            </GlassCard>
          </a>
        ))}
      </div>
    </div>
  )
}

/** 56×56 logo tile — matches Flutter ExternalJobLogoTile. */
function CompanyLogoTile({ job }: { job: ExternalJob }) {
  const url = externalJobLogoUrl(job)
  const [failed, setFailed] = useState(false)
  const initial = companyInitial(job)

  return (
    <div className="web-job-logo grid h-14 w-14 shrink-0 place-items-center overflow-hidden rounded-2xl border border-white/10 bg-white shadow-[0_8px_24px_-12px_rgba(0,0,0,0.5)]">
      {url && !failed ? (
        <img
          src={url}
          alt=""
          referrerPolicy="no-referrer"
          className="h-full w-full object-contain p-1.5"
          loading="lazy"
          onError={() => setFailed(true)}
        />
      ) : (
        <span className="font-[family-name:var(--font-display)] text-lg font-extrabold text-black">
          {initial}
        </span>
      )}
    </div>
  )
}

function sourceLabel(source: string) {
  if (source === 'google_jobs') return 'Google Jobs'
  if (source === 'facebook') return 'Facebook'
  return source.replace(/_/g, ' ')
}

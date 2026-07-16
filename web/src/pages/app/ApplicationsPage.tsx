import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../../lib/auth'
import { supabase, type JobApplication } from '../../lib/supabase'
import { Avatar } from '../../components/Avatar'
import { GlassCard, PageHero, StatusPill } from '../../components/AppUi'
import { useToast } from '../../components/Toast'

export function ApplicationsPage() {
  const { id: jobId } = useParams()
  const { user } = useAuth()
  const toast = useToast()
  const [jobTitle, setJobTitle] = useState('')
  const [apps, setApps] = useState<JobApplication[]>([])
  const [tab, setTab] = useState<'pending' | 'active' | 'closed'>('pending')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  useEffect(() => {
    if (!jobId) return
    let alive = true

    async function load() {
      setLoading(true)
      const [{ data: job }, { data, error: err }] = await Promise.all([
        supabase.from('jobs').select('title, employer_id').eq('id', jobId!).maybeSingle(),
        supabase
          .from('job_applications')
          .select(
            'id, job_id, worker_id, status, cover_letter, created_at, updated_at, worker:profiles!job_applications_worker_id_fkey(id, full_name, avatar_url, location, skills, rating)',
          )
          .eq('job_id', jobId!)
          .order('created_at', { ascending: false }),
      ])

      if (!alive) return
      if (job) setJobTitle(job.title ?? '')
      if (err) {
        // Fallback without join if FK name differs
        const fallback = await supabase
          .from('job_applications')
          .select('id, job_id, worker_id, status, cover_letter, created_at, updated_at')
          .eq('job_id', jobId!)
          .order('created_at', { ascending: false })
        if (fallback.error) setError(fallback.error.message)
        else {
          const rows = (fallback.data as JobApplication[]) ?? []
          const withWorkers = await Promise.all(
            rows.map(async (row) => {
              const { data: w } = await supabase
                .from('profiles')
                .select('id, full_name, avatar_url, location, skills, rating')
                .eq('id', row.worker_id)
                .maybeSingle()
              return { ...row, worker: w }
            }),
          )
          setApps(withWorkers)
        }
      } else {
        setApps((data as unknown as JobApplication[]) ?? [])
      }
      setLoading(false)
    }

    void load()

    const channel = supabase
      .channel(`apps-${jobId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'job_applications', filter: `job_id=eq.${jobId}` },
        () => void load(),
      )
      .subscribe()

    return () => {
      alive = false
      void supabase.removeChannel(channel)
    }
  }, [jobId])

  const filtered = apps.filter((a) => {
    if (tab === 'pending') return a.status === 'pending'
    if (tab === 'active') return a.status === 'accepted' || a.status === 'in_progress'
    return ['rejected', 'withdrawn', 'cancelled', 'completed'].includes(a.status)
  })

  async function decide(app: JobApplication, next: 'accepted' | 'rejected') {
    if (!user || !jobId) return
    setBusyId(app.id)
    setError(null)
    const { error: err } = await supabase
      .from('job_applications')
      .update({ status: next, updated_at: new Date().toISOString() })
      .eq('id', app.id)
    if (err) {
      setError(err.message)
      toast.error('Update failed', err.message)
      setBusyId(null)
      return
    }
    if (next === 'accepted') {
      await supabase
        .from('jobs')
        .update({ status: 'in_progress', updated_at: new Date().toISOString() })
        .eq('id', jobId)
      const existing = await supabase
        .from('conversations')
        .select('id')
        .eq('application_id', app.id)
        .maybeSingle()
      if (!existing.data) {
        await supabase.from('conversations').insert({
          application_id: app.id,
          job_id: jobId,
          employer_id: user.id,
          worker_id: app.worker_id,
        })
      }
      toast.success('Applicant accepted', 'A chat thread is ready in Messages.')
    } else {
      toast.info('Application declined')
    }
    setApps((prev) => prev.map((a) => (a.id === app.id ? { ...a, status: next } : a)))
    setBusyId(null)
  }

  return (
    <div>
      <Link to="/app" className="text-sm text-white/45 hover:text-white">
        ← My Jobs
      </Link>
      <PageHero brush="Hiring" title="Applications" subtitle={jobTitle || 'Job'} />

      <div className="mt-2 flex flex-wrap gap-2">
        {(['pending', 'active', 'closed'] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`rounded-full px-4 py-1.5 text-xs font-bold capitalize transition ${
              tab === t ? 'bg-white text-black' : 'border border-white/15 text-white/60 hover:border-white/30'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {loading && <p className="mt-6 text-white/50">Loading…</p>}
      {error && <p className="mt-4 text-red-400">{error}</p>}
      {!loading && filtered.length === 0 && (
        <p className="mt-6 text-white/50">No applications in this tab.</p>
      )}

      <div className="mt-4 grid gap-3">
        {filtered.map((app) => (
          <GlassCard key={app.id}>
            <div className="flex items-start gap-2.5 sm:gap-3">
              <Avatar
                url={app.worker?.avatar_url}
                name={app.worker?.full_name ?? 'Worker'}
                size="md"
              />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="truncate font-semibold">{app.worker?.full_name ?? 'Worker'}</p>
                      <StatusPill status={app.status} />
                    </div>
                    <p className="mt-1 text-xs text-white/45">
                      {app.worker?.location || 'Botswana'}
                    </p>
                  </div>
                  {app.worker?.rating != null && (
                    <p className="text-sm font-semibold text-paint-soft">★ {app.worker.rating.toFixed(1)}</p>
                  )}
                </div>
                {app.cover_letter && (
                  <p className="mt-3 text-sm text-white/65">{app.cover_letter}</p>
                )}
                {app.status === 'pending' && (
                  <div className="mt-4 flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={busyId === app.id}
                      onClick={() => void decide(app, 'accepted')}
                      className="rounded-full bg-emerald-500 px-4 py-2 text-xs font-bold text-black disabled:opacity-50"
                    >
                      Accept
                    </button>
                    <button
                      type="button"
                      disabled={busyId === app.id}
                      onClick={() => void decide(app, 'rejected')}
                      className="rounded-full border border-red-400/40 px-4 py-2 text-xs font-bold text-red-300 disabled:opacity-50"
                    >
                      Reject
                    </button>
                  </div>
                )}
                {(app.status === 'accepted' || app.status === 'in_progress') && (
                  <Link
                    to="/app/messages"
                    className="mt-4 inline-block text-sm font-semibold text-paint-soft hover:underline"
                  >
                    Open messages →
                  </Link>
                )}
              </div>
            </div>
          </GlassCard>
        ))}
      </div>
    </div>
  )
}

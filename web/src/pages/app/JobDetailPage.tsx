import { useEffect, useState, type FormEvent } from 'react'
import { Link, useParams } from 'react-router-dom'
import { JOB_SELECT } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase, type Job } from '../../lib/supabase'

export function JobDetailPage() {
  const { id } = useParams()
  const { user, isEmployer } = useAuth()
  const [job, setJob] = useState<Job | null>(null)
  const [cover, setCover] = useState('')
  const [saved, setSaved] = useState(false)
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!id) return
    void supabase
      .from('jobs')
      .select(JOB_SELECT)
      .eq('id', id)
      .maybeSingle()
      .then(({ data, error: err }) => {
        if (err) setError(err.message)
        else setJob(data as Job | null)
      })
  }, [id])

  useEffect(() => {
    if (!user || !id || isEmployer) return
    void supabase
      .from('saved_jobs')
      .select('job_id')
      .eq('job_id', id)
      .eq('worker_id', user.id)
      .maybeSingle()
      .then(({ data }) => setSaved(!!data))
  }, [user, id, isEmployer])

  async function toggleSave() {
    if (!user || !job) return
    setBusy(true)
    if (saved) {
      await supabase.from('saved_jobs').delete().eq('job_id', job.id).eq('worker_id', user.id)
      setSaved(false)
    } else {
      const { error: err } = await supabase
        .from('saved_jobs')
        .insert({ job_id: job.id, worker_id: user.id })
      if (err) setError(err.message)
      else setSaved(true)
    }
    setBusy(false)
  }

  async function apply(e: FormEvent) {
    e.preventDefault()
    if (!user || !job) return
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.from('job_applications').insert({
      job_id: job.id,
      worker_id: user.id,
      cover_letter: cover.trim() || null,
      qualification_files: [],
      status: 'pending',
    })
    setBusy(false)
    if (err) {
      setError(err.message)
      return
    }
    setStatus('Application sent')
  }

  if (error && !job) return <p className="text-red-400">{error}</p>
  if (!job) return <p className="text-white/50">Loading…</p>

  const isOwner = user?.id === job.employer_id

  return (
    <div className="max-w-2xl">
      <Link to="/app" className="text-sm text-white/45 hover:text-white">
        ← Back
      </Link>
      <div className="mt-3 flex flex-wrap items-start justify-between gap-3 sm:mt-4">
        <h1
          className="font-[family-name:var(--font-display)] text-[1.9rem] tracking-tight sm:text-3xl"
          style={{ fontWeight: 800 }}
        >
          {job.title}
        </h1>
        {!isEmployer && !isOwner && (
          <button
            type="button"
            disabled={busy}
            onClick={() => void toggleSave()}
            className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-bold ${
              saved ? 'bg-[#1e4fd7] text-white' : 'border border-white/20 text-white/70'
            }`}
          >
            {saved ? 'Saved' : 'Save'}
          </button>
        )}
      </div>
      <p className="mt-2 text-white/50">
        {[job.category, job.location, job.status].filter(Boolean).join(' · ')}
      </p>
      {job.budget_amount != null && (
        <p className="mt-3 text-lg font-semibold text-[#4d7ef0]">
          P{job.budget_amount}
          {job.budget_type ? ` / ${job.budget_type}` : ''}
        </p>
      )}
      {job.job_photos && job.job_photos.length > 0 && (
        <div className="mt-4 flex gap-2 overflow-x-auto">
          {job.job_photos.map((url) => (
            <img
              key={url}
              src={url}
              alt=""
              className="h-24 w-32 shrink-0 rounded-xl object-cover sm:h-28 sm:w-40"
            />
          ))}
        </div>
      )}
      <p className="mt-5 whitespace-pre-wrap leading-relaxed text-white/75 sm:mt-6">
        {job.description || 'No description.'}
      </p>
      {job.required_skills && job.required_skills.length > 0 && (
        <div className="mt-5 flex flex-wrap gap-2 sm:mt-6">
          {job.required_skills.map((s) => (
            <span
              key={s}
              className="rounded-full border border-white/10 px-3 py-1 text-xs text-white/70"
            >
              {s}
            </span>
          ))}
        </div>
      )}

      {isOwner && (
        <Link
          to={`/app/jobs/${job.id}/applications`}
          className="mt-6 inline-flex rounded-full bg-white px-5 py-2.5 text-sm font-bold text-black sm:mt-8"
        >
          View applications
        </Link>
      )}

      {!isEmployer && !isOwner && (
        <form
          onSubmit={apply}
          className="mt-7 space-y-3 rounded-2xl border border-white/10 bg-white/[0.03] p-4 sm:mt-10 sm:p-5"
        >
          <h2 className="font-semibold">Apply</h2>
          <textarea
            value={cover}
            onChange={(e) => setCover(e.target.value)}
            rows={4}
            placeholder="Short cover note (optional)"
            className="w-full rounded-xl border border-white/10 bg-black/30 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-[#1e4fd7]/50"
          />
          {error && <p className="text-sm text-red-400">{error}</p>}
          {status && <p className="text-sm text-emerald-400">{status}</p>}
          <button
            type="submit"
            disabled={busy || !!status}
            className="rounded-full bg-[#1e4fd7] px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
          >
            {busy ? 'Sending…' : status ? 'Applied' : 'Submit application'}
          </button>
        </form>
      )}
    </div>
  )
}

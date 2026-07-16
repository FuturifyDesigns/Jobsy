import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { BUDGET_TYPES, EXPERIENCE_LEVELS, JOB_CATEGORIES } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import { validatePositiveNumber, validateRequired } from '../../lib/validation'
import { GlassCard, PageHero } from '../../components/AppUi'
import { useToast } from '../../components/Toast'

export function PostJobPage() {
  const { user, profile } = useAuth()
  const toast = useToast()
  const navigate = useNavigate()
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<string>(JOB_CATEGORIES[0])
  const [location, setLocation] = useState(profile?.location ?? 'Gaborone')
  const [budgetAmount, setBudgetAmount] = useState('')
  const [budgetType, setBudgetType] = useState<string>('fixed')
  const [experience, setExperience] = useState('')
  const [skills, setSkills] = useState('')
  const [photos, setPhotos] = useState<FileList | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const setupReady = Boolean(profile?.company_name?.trim() && profile?.business_type?.trim())

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (!user) return
    if (!setupReady) {
      setError('Add company name and business type in Profile before posting.')
      return
    }
    const titleErr = validateRequired(title, 'Title', 3)
    if (titleErr) {
      setError(titleErr)
      return
    }
    const descErr = validateRequired(description, 'Description', 20)
    if (descErr) {
      setError(descErr)
      return
    }
    const locErr = validateRequired(location, 'Location', 2)
    if (locErr) {
      setError(locErr)
      return
    }
    const amountErr = validatePositiveNumber(budgetAmount, 'Budget amount')
    if (amountErr) {
      setError(amountErr)
      return
    }
    const amount = Number(budgetAmount)
    if (photos && photos.length > 5) {
      setError('You can upload up to 5 photos.')
      return
    }
    if (photos) {
      for (const file of Array.from(photos)) {
        if (!file.type.startsWith('image/')) {
          setError('Photos must be image files.')
          return
        }
        if (file.size > 8 * 1024 * 1024) {
          setError('Each photo must be under 8 MB.')
          return
        }
      }
    }

    setBusy(true)
    setError(null)

    try {
      const urls: string[] = []
      if (photos) {
        const list = Array.from(photos).slice(0, 5)
        for (let i = 0; i < list.length; i++) {
          const file = list[i]
          const ext = file.name.split('.').pop()?.toLowerCase() || 'jpg'
          const path = `${user.id}/${Date.now()}_${i}.${ext}`
          const { error: upErr } = await supabase.storage.from('job-photos').upload(path, file, {
            contentType: file.type || 'image/jpeg',
            upsert: false,
          })
          if (upErr) throw upErr
          const { data } = supabase.storage.from('job-photos').getPublicUrl(path)
          urls.push(data.publicUrl)
        }
      }

      const skillList = skills
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
        .slice(0, 5)

      const { data, error: insertErr } = await supabase
        .from('jobs')
        .insert({
          employer_id: user.id,
          title: title.trim(),
          description: description.trim(),
          category,
          location: location.trim(),
          budget_amount: amount,
          budget_type: budgetType,
          status: 'active',
          required_skills: skillList.length ? skillList : null,
          experience_level: experience || null,
          job_photos: urls.length ? urls : null,
        })
        .select('id')
        .single()

      if (insertErr) throw insertErr
      toast.success('Job published', 'Workers nearby can see it now.')
      navigate(`/app/jobs/${data.id}/applications`)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      setError(msg)
      toast.error('Could not post', msg)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mx-auto max-w-3xl">
      <Link to="/app" className="text-sm text-white/45 hover:text-white">
        ← My Jobs
      </Link>
      <PageHero
        brush="Hiring"
        title="Post a Job"
        subtitle="Goes live immediately for workers nearby."
      />

      {!setupReady && (
        <div className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
          Complete employer setup on{' '}
          <Link to="/app/profile" className="underline">
            Profile
          </Link>{' '}
          (company name + business type) before posting.
        </div>
      )}

      <GlassCard hover={false} className="!p-6 md:!p-8">
      <form onSubmit={onSubmit} className="grid gap-4 lg:grid-cols-2" noValidate>
        <Field
          label="Title"
          value={title}
          onChange={setTitle}
          required
          placeholder="e.g. Need a painter for 2 days"
          hint="At least 3 characters"
        />
        <label className="block lg:col-span-2">
          <span className="mb-1.5 block text-sm text-white/60">Description</span>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={5}
            required
            placeholder="Describe the work, timing, and what’s included…"
            className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 outline-none placeholder:text-white/25 focus:ring-2 focus:ring-paint/30"
          />
          <span className="mt-1.5 block text-xs text-white/35">At least 20 characters</span>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm text-white/60">Category</span>
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="w-full rounded-xl border border-white/10 bg-[#0e0e14] px-4 py-2.5 outline-none"
          >
            {JOB_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <Field
          label="Location"
          value={location}
          onChange={setLocation}
          required
          placeholder="Gaborone, Broadhurst"
        />
        <div className="grid gap-3 sm:grid-cols-2">
          <Field
            label="Budget (Pula)"
            value={budgetAmount}
            onChange={setBudgetAmount}
            type="number"
            required
            placeholder="e.g. 500"
          />
          <label className="block">
            <span className="mb-1.5 block text-sm text-white/60">Budget type</span>
            <select
              value={budgetType}
              onChange={(e) => setBudgetType(e.target.value)}
              className="w-full rounded-xl border border-white/10 bg-[#0e0e14] px-4 py-2.5 outline-none"
            >
              {BUDGET_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </label>
        </div>
        <label className="block">
          <span className="mb-1.5 block text-sm text-white/60">Experience (optional)</span>
          <select
            value={experience}
            onChange={(e) => setExperience(e.target.value)}
            className="w-full rounded-xl border border-white/10 bg-[#0e0e14] px-4 py-2.5 outline-none"
          >
            <option value="">Any</option>
            {EXPERIENCE_LEVELS.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        <Field
          label="Skills (comma-separated, max 5)"
          value={skills}
          onChange={setSkills}
          placeholder="welding, scaffolding"
          hint="Optional — helps workers match faster"
        />
        <label className="block">
          <span className="mb-1.5 block text-sm text-white/60">Photos (optional, max 5)</span>
          <input
            type="file"
            accept="image/*"
            multiple
            onChange={(e) => setPhotos(e.target.files)}
            className="w-full text-sm text-white/70"
          />
          <span className="mt-1.5 block text-xs text-white/35">Images only, under 8 MB each</span>
        </label>
        {error && <p className="text-sm text-red-400 lg:col-span-2">{error}</p>}
        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-paint px-6 py-3 text-sm font-bold text-white shadow-[0_16px_40px_-18px_rgba(30,79,215,0.85)] transition hover:brightness-110 disabled:opacity-50 lg:col-span-2 lg:justify-self-start"
        >
          {busy ? 'Posting…' : 'Publish job'}
        </button>
      </form>
      </GlassCard>
    </div>
  )
}

function Field({
  label,
  value,
  onChange,
  type = 'text',
  required,
  placeholder,
  hint,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  type?: string
  required?: boolean
  placeholder?: string
  hint?: string
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm text-white/60">{label}</span>
      <input
        type={type}
        value={value}
        required={required}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 outline-none placeholder:text-white/25 focus:ring-2 focus:ring-[#1e4fd7]/50"
      />
      {hint && <span className="mt-1.5 block text-xs text-white/35">{hint}</span>}
    </label>
  )
}

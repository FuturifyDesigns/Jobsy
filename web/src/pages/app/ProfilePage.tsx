import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { BUSINESS_TYPES } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import { openCookieSettings } from '../../components/CookieConsent'
import { Avatar } from '../../components/Avatar'
import { ConfirmDialog, GlassCard, PageHero } from '../../components/AppUi'
import { useToast } from '../../components/Toast'
import {
  validateFullName,
  validatePhone,
  validatePositiveNumber,
} from '../../lib/validation'

gsap.registerPlugin(useGSAP)

export function ProfilePage() {
  const { user, profile, refreshProfile, signOut, switchRole, isEmployer } = useAuth()
  const toast = useToast()
  const navigate = useNavigate()
  const rootRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const [fullName, setFullName] = useState('')
  const [location, setLocation] = useState('')
  const [bio, setBio] = useState('')
  const [phone, setPhone] = useState('')
  const [companyName, setCompanyName] = useState('')
  const [businessType, setBusinessType] = useState('')
  const [hourlyRate, setHourlyRate] = useState('')
  const [busy, setBusy] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [switching, setSwitching] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)

  useGSAP(
    () => {
      gsap.from('.profile-reveal', {
        opacity: 0,
        y: 22,
        stagger: 0.08,
        duration: 0.55,
        ease: 'power3.out',
      })
    },
    { scope: rootRef },
  )

  useEffect(() => {
    setFullName(profile?.full_name ?? '')
    setLocation(profile?.location ?? '')
    setBio(profile?.bio ?? '')
    setPhone(profile?.phone ?? '')
    setCompanyName(profile?.company_name ?? '')
    setBusinessType(profile?.business_type ?? '')
    setHourlyRate(profile?.hourly_rate != null ? String(profile.hourly_rate) : '')
    setPreviewUrl(profile?.avatar_url ?? null)
  }, [profile])

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!user) return
    const nameErr = validateFullName(fullName)
    const phoneErr = validatePhone(phone)
    if (nameErr) {
      toast.error('Check your name', nameErr)
      return
    }
    if (phoneErr) {
      toast.error('Check your phone', phoneErr)
      return
    }
    if (isEmployer) {
      if (!companyName.trim()) {
        toast.error('Company required', 'Add a company name for employers')
        return
      }
      if (!businessType) {
        toast.error('Business type', 'Select a business type')
        return
      }
    } else if (hourlyRate.trim()) {
      const rateErr = validatePositiveNumber(hourlyRate, 'Hourly rate')
      if (rateErr) {
        toast.error('Hourly rate', rateErr)
        return
      }
    }
    setBusy(true)
    const payload: Record<string, unknown> = {
      full_name: fullName.trim(),
      location: location.trim() || null,
      bio: bio.trim() || null,
      phone: phone.trim() || null,
    }
    if (isEmployer) {
      payload.company_name = companyName.trim() || null
      payload.business_type = businessType || null
    } else {
      const rate = Number(hourlyRate)
      payload.hourly_rate = Number.isFinite(rate) && rate > 0 ? rate : null
    }
    const { error: err } = await supabase.from('profiles').update(payload).eq('id', user.id)
    setBusy(false)
    if (err) {
      toast.error('Could not save', err.message)
      return
    }
    toast.success('Profile saved', 'Your details are up to date.')
    await refreshProfile()
  }

  async function uploadAvatar(file: File) {
    if (!user) return
    if (!file.type.startsWith('image/')) {
      toast.error('Invalid file', 'Choose an image for your profile photo.')
      return
    }
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Too large', 'Keep photos under 2 MB.')
      return
    }
    setUploading(true)
    try {
      const path = `${user.id}/avatar.jpg`
      const { error: upErr } = await supabase.storage.from('avatars').upload(path, file, {
        contentType: 'image/jpeg',
        upsert: true,
      })
      if (upErr) throw upErr
      const { data } = supabase.storage.from('avatars').getPublicUrl(path)
      const publicUrl = `${data.publicUrl}?v=${Date.now()}`
      const { error: dbErr } = await supabase
        .from('profiles')
        .update({ avatar_url: publicUrl })
        .eq('id', user.id)
      if (dbErr) throw dbErr
      setPreviewUrl(publicUrl)
      await refreshProfile()
      toast.success('Photo updated', 'Your profile picture is live.')
    } catch (err) {
      toast.error('Upload failed', err instanceof Error ? err.message : String(err))
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function confirmSwitch() {
    const target = isEmployer ? 'worker' : 'employer'
    setSwitching(true)
    const res = await switchRole(target)
    setSwitching(false)
    setConfirmOpen(false)
    if (res.error) {
      toast.error('Could not switch', res.error)
      return
    }
    toast.success(
      target === 'worker' ? 'Switched to Worker' : 'Switched to Employer',
      target === 'worker'
        ? 'You can now browse and apply for jobs.'
        : 'You can now post jobs and hire talent.',
    )
    navigate('/app')
  }

  const targetRole = isEmployer ? 'Worker' : 'Employer'

  return (
    <div ref={rootRef} className="mx-auto max-w-3xl">
      <PageHero
        brush="You"
        title="Profile"
        subtitle={`${user?.email ?? ''} · ${isEmployer ? 'Employer' : 'Worker'}`}
      />

      <GlassCard className="profile-reveal mb-4 !p-4 sm:mb-6 sm:!p-6" hover={false}>
        <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-start sm:gap-5">
          <div className="relative">
            <Avatar url={previewUrl} name={fullName || user?.email} size="xl" />
            <button
              type="button"
              disabled={uploading}
              onClick={() => fileRef.current?.click()}
              className="absolute -right-1 -bottom-1 grid h-10 w-10 place-items-center rounded-full border border-white/20 bg-[#0c0c12] text-white shadow-lg transition hover:border-paint hover:text-paint-soft disabled:opacity-50"
              aria-label="Change photo"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" />
                <circle cx="12" cy="13" r="4" />
              </svg>
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) void uploadAvatar(f)
              }}
            />
          </div>
          <div className="flex-1 text-center sm:text-left">
            <h2 className="font-[family-name:var(--font-display)] text-xl sm:text-2xl" style={{ fontWeight: 800 }}>
              {fullName || 'Your name'}
            </h2>
            <p className="mt-1 text-sm text-white/45">
              {uploading ? 'Uploading photo…' : 'Tap the camera to update your picture — same as the app.'}
            </p>
            <button
              type="button"
              onClick={() => setConfirmOpen(true)}
              className="mt-4 rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white/90 transition hover:border-paint-soft hover:text-white"
            >
              Switch to {targetRole}
            </button>
          </div>
        </div>
      </GlassCard>

      <form onSubmit={(e) => void save(e)} className="profile-reveal space-y-3 sm:space-y-4" noValidate>
        <GlassCard hover={false} className="!p-4 space-y-3 sm:!p-6 sm:space-y-4">
          <Field label="Full name" value={fullName} onChange={setFullName} placeholder="e.g. Thabo Molefe" required />
          <Field
            label="Phone"
            value={phone}
            onChange={setPhone}
            placeholder="+267 71 234 567"
            hint="Include country code if outside Botswana"
          />
          <Field
            label="Location"
            value={location}
            onChange={setLocation}
            placeholder="Gaborone"
            hint="City or area where you work"
          />
          <label className="block">
            <span className="mb-1.5 block text-sm text-white/60">Bio</span>
            <textarea
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              rows={4}
              placeholder="Short intro about your skills or business…"
              maxLength={500}
              className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 outline-none transition focus:border-paint/40 focus:ring-2 focus:ring-paint/30"
            />
          </label>

          {isEmployer ? (
            <>
              <Field
                label="Company name"
                value={companyName}
                onChange={setCompanyName}
                placeholder="e.g. Molefe Builders"
                required
              />
              <label className="block">
                <span className="mb-1.5 block text-sm text-white/60">Business type</span>
                <select
                  value={businessType}
                  onChange={(e) => setBusinessType(e.target.value)}
                  required
                  className="w-full rounded-xl border border-white/10 bg-[#0e0e14] px-4 py-3 outline-none"
                >
                  <option value="">Select…</option>
                  {BUSINESS_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {t}
                    </option>
                  ))}
                </select>
              </label>
            </>
          ) : (
            <Field
              label="Hourly rate (Pula)"
              value={hourlyRate}
              onChange={setHourlyRate}
              type="number"
              placeholder="e.g. 80"
              hint="Optional — shown to employers"
            />
          )}

          <button
            type="submit"
            disabled={busy}
            className="rounded-full bg-paint px-6 py-3 text-sm font-bold text-white shadow-[0_16px_40px_-18px_rgba(30,79,215,0.9)] transition hover:brightness-110 disabled:opacity-50"
          >
            {busy ? 'Saving…' : 'Save profile'}
          </button>
        </GlassCard>
      </form>

      <button
        type="button"
        onClick={() => void signOut()}
        className="profile-reveal mt-6 text-sm text-white/40 hover:text-white sm:mt-8"
      >
        Sign out
      </button>

      <div className="profile-reveal mt-8 border-t border-white/10 pt-5 sm:mt-10 sm:pt-6">
        <p className="mb-3 text-xs font-bold tracking-[0.2em] text-white/40 uppercase">Legal & privacy</p>
        <ul className="space-y-2 text-sm text-white/65">
          <li>
            <Link to="/privacy" className="hover:text-white">
              Privacy Policy (Data Protection Act, 2024)
            </Link>
          </li>
          <li>
            <Link to="/terms" className="hover:text-white">
              Terms of Service
            </Link>
          </li>
          <li>
            <Link to="/cookies" className="hover:text-white">
              Cookie Policy
            </Link>
          </li>
          <li>
            <button type="button" onClick={() => openCookieSettings()} className="hover:text-white">
              Cookie settings
            </button>
          </li>
        </ul>
      </div>

      <ConfirmDialog
        open={confirmOpen}
        title={`Switch to ${targetRole}?`}
        message={
          isEmployer
            ? 'You’ll browse and apply for jobs as a worker. You can switch back anytime.'
            : 'You’ll post jobs and hire as an employer. You can switch back anytime.'
        }
        confirmLabel={`Switch to ${targetRole}`}
        busy={switching}
        onConfirm={() => void confirmSwitch()}
        onCancel={() => setConfirmOpen(false)}
      />
    </div>
  )
}

function Field({
  label,
  value,
  onChange,
  type = 'text',
  placeholder,
  hint,
  required,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  type?: string
  placeholder?: string
  hint?: string
  required?: boolean
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm text-white/60">{label}</span>
      <input
        type={type}
        value={value}
        placeholder={placeholder}
        required={required}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 outline-none placeholder:text-white/25 transition focus:border-paint/40 focus:ring-2 focus:ring-paint/30"
      />
      {hint && <span className="mt-1.5 block text-xs text-white/35">{hint}</span>}
    </label>
  )
}

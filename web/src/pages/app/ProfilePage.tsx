import { useEffect, useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { BUSINESS_TYPES } from '../../lib/constants'
import { useAuth } from '../../lib/auth'
import { supabase } from '../../lib/supabase'
import { openCookieSettings } from '../../components/CookieConsent'
import {
  validateFullName,
  validatePhone,
  validatePositiveNumber,
} from '../../lib/validation'

export function ProfilePage() {
  const { user, profile, refreshProfile, signOut, switchRole, isEmployer } = useAuth()
  const navigate = useNavigate()
  const [fullName, setFullName] = useState('')
  const [location, setLocation] = useState('')
  const [bio, setBio] = useState('')
  const [phone, setPhone] = useState('')
  const [companyName, setCompanyName] = useState('')
  const [businessType, setBusinessType] = useState('')
  const [hourlyRate, setHourlyRate] = useState('')
  const [status, setStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [switching, setSwitching] = useState(false)

  useEffect(() => {
    setFullName(profile?.full_name ?? '')
    setLocation(profile?.location ?? '')
    setBio(profile?.bio ?? '')
    setPhone(profile?.phone ?? '')
    setCompanyName(profile?.company_name ?? '')
    setBusinessType(profile?.business_type ?? '')
    setHourlyRate(profile?.hourly_rate != null ? String(profile.hourly_rate) : '')
  }, [profile])

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!user) return
    setStatus(null)
    const nameErr = validateFullName(fullName)
    const phoneErr = validatePhone(phone)
    if (nameErr) {
      setError(nameErr)
      return
    }
    if (phoneErr) {
      setError(phoneErr)
      return
    }
    if (isEmployer) {
      if (!companyName.trim()) {
        setError('Company name is required for employers')
        return
      }
      if (!businessType) {
        setError('Select a business type')
        return
      }
    } else if (hourlyRate.trim()) {
      const rateErr = validatePositiveNumber(hourlyRate, 'Hourly rate')
      if (rateErr) {
        setError(rateErr)
        return
      }
    }
    setBusy(true)
    setError(null)
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
      setError(err.message)
      return
    }
    setStatus('Saved')
    await refreshProfile()
  }

  async function onSwitchRole() {
    const target = isEmployer ? 'worker' : 'employer'
    if (!window.confirm(`Switch to ${target} mode?`)) return
    setSwitching(true)
    setError(null)
    const res = await switchRole(target)
    setSwitching(false)
    if (res.error) {
      setError(res.error)
      return
    }
    navigate('/app')
  }

  return (
    <div className="max-w-lg">
      <h1
        className="font-[family-name:var(--font-display)] text-3xl tracking-tight"
        style={{ fontWeight: 800 }}
      >
        Profile
      </h1>
      <p className="mt-2 text-sm text-white/45">
        {user?.email} · {isEmployer ? 'Employer' : 'Worker'}
      </p>

      <button
        type="button"
        disabled={switching}
        onClick={() => void onSwitchRole()}
        className="mt-5 rounded-full border border-white/20 px-4 py-2 text-sm font-semibold text-white/85 hover:border-white/40 disabled:opacity-50"
      >
        {switching
          ? 'Switching…'
          : isEmployer
            ? 'Switch to Worker'
            : 'Switch to Employer'}
      </button>

      <form onSubmit={save} className="mt-8 space-y-4" noValidate>
        <Field
          label="Full name"
          value={fullName}
          onChange={setFullName}
          placeholder="e.g. Thabo Molefe"
          required
        />
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
            className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 outline-none focus:ring-2 focus:ring-[#1e4fd7]/50"
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
                className="w-full rounded-xl border border-white/10 bg-[#0e0e14] px-4 py-2.5 outline-none"
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

        {error && <p className="text-sm text-red-400">{error}</p>}
        {status && <p className="text-sm text-emerald-400">{status}</p>}
        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-[#1e4fd7] px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
        >
          {busy ? 'Saving…' : 'Save profile'}
        </button>
      </form>

      <button
        type="button"
        onClick={() => void signOut()}
        className="mt-10 text-sm text-white/45 hover:text-white"
      >
        Sign out
      </button>

      <div className="mt-10 border-t border-white/10 pt-6">
        <p className="mb-3 text-xs font-bold tracking-[0.2em] text-white/40 uppercase">
          Legal & privacy
        </p>
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
            <button
              type="button"
              onClick={() => openCookieSettings()}
              className="hover:text-white"
            >
              Cookie settings
            </button>
          </li>
        </ul>
        <p className="mt-4 text-xs leading-relaxed text-white/40">
          Jobsy processes personal data under Botswana&apos;s Data Protection Act, 2024. Contact{' '}
          futurifydesigns@gmail.com for access, correction, or erasure requests.
        </p>
      </div>
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
        className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 outline-none placeholder:text-white/25 focus:ring-2 focus:ring-[#1e4fd7]/50"
      />
      {hint && <span className="mt-1.5 block text-xs text-white/35">{hint}</span>}
    </label>
  )
}

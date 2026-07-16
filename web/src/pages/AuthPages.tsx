import { useRef, useState, type FormEvent, type ReactNode } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { Logo } from '../components/Logo'
import { MagneticButton } from '../components/MagneticButton'
import { useAuth } from '../lib/auth'
import {
  getPasswordStrength,
  validateEmail,
  validateFullName,
  validatePasswordSignIn,
  validatePasswordSignUp,
} from '../lib/validation'

gsap.registerPlugin(useGSAP)

export function SignInPage() {
  const { signIn, signInWithGoogle, user, loading } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (!loading && user) return <Navigate to="/app" replace />

  function validate(): boolean {
    const next: Record<string, string> = {}
    const e = validateEmail(email)
    const p = validatePasswordSignIn(password)
    if (e) next.email = e
    if (p) next.password = p
    setFieldErrors(next)
    return Object.keys(next).length === 0
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (!validate()) return
    setBusy(true)
    const res = await signIn(email.trim(), password)
    setBusy(false)
    if (res.error) {
      setError(res.error)
      return
    }
    navigate('/app')
  }

  async function onGoogle() {
    setBusy(true)
    setError(null)
    const res = await signInWithGoogle()
    if (res.error) {
      setBusy(false)
      setError(res.error)
    }
  }

  return (
    <AuthShell
      kicker="Welcome back"
      title="Sign in to Jobsy"
      subtitle="Pick up where you left off — jobs, chats, and hires sync with the app."
      imageSrc="/auth/sign-in.png"
      imageAlt="Jobsy — Sign in"
    >
      <form onSubmit={onSubmit} className="space-y-4" noValidate>
        <Field
          label="Email"
          type="email"
          value={email}
          onChange={(v) => {
            setEmail(v)
            if (fieldErrors.email) setFieldErrors((f) => ({ ...f, email: '' }))
          }}
          autoComplete="email"
          placeholder="you@email.com"
          hint="Use the email linked to your Jobsy account"
          error={fieldErrors.email}
        />
        <Field
          label="Password"
          type="password"
          value={password}
          onChange={(v) => {
            setPassword(v)
            if (fieldErrors.password) setFieldErrors((f) => ({ ...f, password: '' }))
          }}
          autoComplete="current-password"
          placeholder="Your password"
          error={fieldErrors.password}
        />
        {error && <p className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-600">{error}</p>}
        <MagneticButton type="submit" className="w-full" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign In'}
        </MagneticButton>
      </form>
      <AuthDivider />
      <GoogleButton onClick={() => void onGoogle()} disabled={busy} />
      <p className="mt-7 text-center text-sm text-mute">
        New to Jobsy?{' '}
        <Link to="/signup" className="font-semibold text-paint hover:underline">
          Create an account
        </Link>
      </p>
    </AuthShell>
  )
}

export function SignUpPage() {
  const { signUp, signInWithGoogle, user, loading } = useAuth()
  const navigate = useNavigate()
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [accepted, setAccepted] = useState(false)
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)

  const strength = getPasswordStrength(password)

  if (!loading && user) return <Navigate to="/app" replace />

  function validate(): boolean {
    const next: Record<string, string> = {}
    const n = validateFullName(fullName)
    const e = validateEmail(email)
    const p = validatePasswordSignUp(password)
    if (n) next.fullName = n
    if (e) next.email = e
    if (p) next.password = p
    if (!confirm) next.confirm = 'Confirm your password'
    else if (confirm !== password) next.confirm = 'Passwords do not match'
    if (!accepted) next.accepted = 'Please accept the Terms and Privacy Policy'
    setFieldErrors(next)
    return Object.keys(next).length === 0
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (!validate()) return
    setBusy(true)
    const res = await signUp(email.trim(), password, fullName.trim())
    setBusy(false)
    if (res.error) {
      setError(res.error)
      return
    }
    setDone(true)
    navigate('/app')
  }

  async function onGoogle() {
    setError(null)
    if (!accepted) {
      setFieldErrors((f) => ({ ...f, accepted: 'Please accept the Terms and Privacy Policy' }))
      return
    }
    setBusy(true)
    const res = await signInWithGoogle()
    if (res.error) {
      setBusy(false)
      setError(res.error)
    }
  }

  return (
    <AuthShell
      kicker="Get started"
      title="Join Jobsy"
      subtitle="Find work. Get paid. Keep moving — across Botswana."
      imageSrc="/auth/sign-up.png"
      imageAlt="Jobsy — Sign up"
    >
      {done ? (
        <p className="rounded-xl bg-paint/10 px-4 py-3 text-mute">
          Account created — check your email if verification is required.
        </p>
      ) : (
        <>
          <form onSubmit={onSubmit} className="space-y-4" noValidate>
            <Field
              label="Full name"
              value={fullName}
              onChange={(v) => {
                setFullName(v)
                if (fieldErrors.fullName) setFieldErrors((f) => ({ ...f, fullName: '' }))
              }}
              autoComplete="name"
              placeholder="e.g. Thabo Molefe"
              hint="As it should appear on your profile"
              error={fieldErrors.fullName}
            />
            <Field
              label="Email"
              type="email"
              value={email}
              onChange={(v) => {
                setEmail(v)
                if (fieldErrors.email) setFieldErrors((f) => ({ ...f, email: '' }))
              }}
              autoComplete="email"
              placeholder="you@email.com"
              hint="We’ll use this to sign you in"
              error={fieldErrors.email}
            />
            <div>
              <Field
                label="Password"
                type="password"
                value={password}
                onChange={(v) => {
                  setPassword(v)
                  if (fieldErrors.password) setFieldErrors((f) => ({ ...f, password: '' }))
                }}
                autoComplete="new-password"
                placeholder="Create a strong password"
                error={fieldErrors.password}
              />
              <PasswordStrengthBar strength={strength} visible={password.length > 0} />
            </div>
            <Field
              label="Confirm password"
              type="password"
              value={confirm}
              onChange={(v) => {
                setConfirm(v)
                if (fieldErrors.confirm) setFieldErrors((f) => ({ ...f, confirm: '' }))
              }}
              autoComplete="new-password"
              placeholder="Re-enter your password"
              error={fieldErrors.confirm}
            />
            <label className="flex items-start gap-3 text-sm leading-relaxed text-mute">
              <input
                type="checkbox"
                checked={accepted}
                onChange={(e) => {
                  setAccepted(e.target.checked)
                  if (fieldErrors.accepted) setFieldErrors((f) => ({ ...f, accepted: '' }))
                }}
                className="mt-1 size-4 rounded border-ink/20 text-paint focus:ring-paint/30"
              />
              <span>
                I agree to the{' '}
                <Link to="/terms" className="font-semibold text-paint hover:underline">
                  Terms of Service
                </Link>{' '}
                and{' '}
                <Link to="/privacy" className="font-semibold text-paint hover:underline">
                  Privacy Policy
                </Link>
                , and understand Jobsy processes my data under Botswana&apos;s Data Protection Act,
                2024.
              </span>
            </label>
            {fieldErrors.accepted && (
              <p className="text-sm text-red-600">{fieldErrors.accepted}</p>
            )}
            {error && <p className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-600">{error}</p>}
            <MagneticButton type="submit" className="w-full" disabled={busy}>
              {busy ? 'Creating…' : 'Create account'}
            </MagneticButton>
          </form>
          <AuthDivider />
          <GoogleButton onClick={() => void onGoogle()} disabled={busy} />
        </>
      )}
      <p className="mt-7 text-center text-sm text-mute">
        Already have an account?{' '}
        <Link to="/signin" className="font-semibold text-paint hover:underline">
          Sign In
        </Link>
      </p>
    </AuthShell>
  )
}

function PasswordStrengthBar({
  strength,
  visible,
}: {
  strength: ReturnType<typeof getPasswordStrength>
  visible: boolean
}) {
  if (!visible) return null
  return (
    <div className="mt-2.5" aria-live="polite">
      <div className="h-1.5 overflow-hidden rounded-full bg-ink/10">
        <div
          className="h-full rounded-full transition-all duration-300 ease-out"
          style={{ width: `${strength.percent}%`, backgroundColor: strength.color }}
        />
      </div>
      <div className="mt-1.5 flex items-center justify-between gap-2 text-xs">
        <span className="font-semibold" style={{ color: strength.color }}>
          {strength.label}
        </span>
        {strength.hints.length > 0 && (
          <span className="truncate text-mute">{strength.hints[0]}</span>
        )}
      </div>
    </div>
  )
}

function AuthDivider() {
  return (
    <div className="my-5 flex items-center gap-3 text-xs font-semibold tracking-wide text-mute uppercase">
      <span className="h-px flex-1 bg-ink/10" />
      or
      <span className="h-px flex-1 bg-ink/10" />
    </div>
  )
}

function GoogleButton({ onClick, disabled }: { onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="flex w-full items-center justify-center gap-3 rounded-full border border-ink/12 bg-white px-5 py-3 text-sm font-semibold text-ink transition hover:border-ink/25 disabled:opacity-50"
    >
      <svg viewBox="0 0 24 24" className="size-5" aria-hidden>
        <path
          fill="#EA4335"
          d="M12 10.2v3.6h5.1c-.2 1.2-.9 2.3-1.9 3l3.1 2.4c1.8-1.7 2.9-4.1 2.9-7 0-.7-.1-1.3-.2-1.9H12z"
        />
        <path
          fill="#34A853"
          d="M6.6 14.3l-.7.5-2.4 1.9C5.1 19.5 8.3 21.5 12 21.5c2.7 0 4.9-.9 6.5-2.4l-3.1-2.4c-.9.6-2 .9-3.4.9-2.6 0-4.8-1.7-5.6-4.1z"
        />
        <path
          fill="#4A90E2"
          d="M3.5 7.3C2.9 8.5 2.5 9.9 2.5 11.5s.4 3 1 4.2l3.1-2.4c-.2-.6-.3-1.2-.3-1.8 0-.6.1-1.2.3-1.8L3.5 7.3z"
        />
        <path
          fill="#FBBC05"
          d="M12 5.5c1.5 0 2.8.5 3.8 1.5l2.8-2.8C16.9 2.5 14.7 1.5 12 1.5 8.3 1.5 5.1 3.5 3.5 7.3l3.1 2.4C7.2 7.2 9.4 5.5 12 5.5z"
        />
      </svg>
      Continue with Google
    </button>
  )
}

function AuthShell({
  kicker,
  title,
  subtitle,
  imageSrc,
  imageAlt,
  children,
}: {
  kicker: string
  title: string
  subtitle: string
  imageSrc: string
  imageAlt: string
  children: ReactNode
}) {
  const root = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return
      gsap.from('.auth-visual', { x: -40, opacity: 0, duration: 0.9, ease: 'power3.out' })
      gsap.from('.auth-panel', { x: 40, opacity: 0, duration: 0.9, ease: 'power3.out', delay: 0.1 })

      gsap.to('.auth-float', {
        y: -14,
        rotate: 1.1,
        duration: 3,
        ease: 'sine.inOut',
        yoyo: true,
        repeat: -1,
      })
    },
    { scope: root },
  )

  return (
    <div ref={root} className="relative min-h-screen overflow-hidden bg-[#F2F2F2]">
      <div className="relative z-10 mx-auto flex min-h-screen max-w-6xl flex-col px-5 py-6 md:py-8">
        <div className="mb-6 flex items-center justify-between">
          <Logo />
          <Link to="/" className="text-sm font-semibold text-mute hover:text-ink">
            ← Back home
          </Link>
        </div>

        <div className="grid flex-1 items-center gap-8 lg:grid-cols-2 lg:gap-12 xl:gap-16">
          <div className="auth-visual relative mx-auto w-full max-w-lg lg:mx-0 lg:max-w-none">
            <div className="auth-float will-change-transform">
              <img
                src={imageSrc}
                alt={imageAlt}
                className="h-auto w-full rounded-[1.75rem] object-contain object-center shadow-[0_28px_56px_-24px_rgba(30,79,215,0.4)] md:rounded-[2rem]"
                decoding="async"
              />
            </div>
          </div>

          <div className="auth-panel relative w-full max-w-md justify-self-center lg:justify-self-end">
            <div className="relative rounded-[1.75rem] border border-ink/8 bg-white/95 p-8 shadow-[0_40px_80px_-40px_rgba(10,10,10,0.35)] backdrop-blur-xl md:p-10">
              <p className="mb-2 text-xs font-bold tracking-[0.22em] text-paint uppercase">{kicker}</p>
              <h1
                className="font-[family-name:var(--font-display)] text-3xl tracking-tight text-ink md:text-[2.1rem]"
                style={{ fontWeight: 800 }}
              >
                {title}
              </h1>
              <p className="mt-2 mb-8 text-[0.95rem] leading-relaxed text-mute">{subtitle}</p>
              {children}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({
  label,
  value,
  onChange,
  type = 'text',
  autoComplete,
  placeholder,
  hint,
  error,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  type?: string
  autoComplete?: string
  placeholder?: string
  hint?: string
  error?: string
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium text-ink/80">{label}</span>
      <input
        type={type}
        value={value}
        autoComplete={autoComplete}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        aria-invalid={Boolean(error)}
        className={`w-full rounded-xl border bg-paper/80 px-4 py-3.5 outline-none transition focus:bg-white focus:ring-2 ${
          error
            ? 'border-red-400 focus:border-red-400 focus:ring-red-200'
            : 'border-ink/10 focus:border-paint/40 focus:ring-paint/25'
        }`}
      />
      {error ? (
        <span className="mt-1.5 block text-xs text-red-600">{error}</span>
      ) : hint ? (
        <span className="mt-1.5 block text-xs text-mute">{hint}</span>
      ) : null}
    </label>
  )
}

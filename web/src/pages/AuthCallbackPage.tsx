import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { transitionToApp } from '../lib/authTransition'

/** Auth user older than this was already registered before this Google flow. */
const EXISTING_ACCOUNT_MIN_AGE_MS = 90_000

/** Handles Google OAuth / email redirect PKCE exchange. */
export function AuthCallbackPage() {
  const navigate = useNavigate()
  const [notice, setNotice] = useState<{ title: string; message: string } | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let alive = true

    async function finish() {
      const url = new URL(window.location.href)
      const code = url.searchParams.get('code')
      const fromSignUp = url.searchParams.get('from') === 'signup'

      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code)
        if (!alive) return
        if (error) {
          navigate(fromSignUp ? '/signup' : '/signin', {
            replace: true,
            state: { authError: error.message },
          })
          return
        }
      } else {
        const { data } = await supabase.auth.getSession()
        if (!alive) return
        if (!data.session) {
          navigate(fromSignUp ? '/signup' : '/signin', { replace: true })
          return
        }
      }

      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!alive) return

      if (fromSignUp && user?.created_at) {
        const ageMs = Date.now() - new Date(user.created_at).getTime()
        if (ageMs > EXISTING_ACCOUNT_MIN_AGE_MS) {
          const { data: profile } = await supabase
            .from('profiles')
            .select('is_profile_complete')
            .eq('id', user.id)
            .maybeSingle()

          if (!alive) return
          setNotice({
            title: 'Account already exists',
            message: profile?.is_profile_complete
              ? 'This Google account is already registered. Signing you in now.'
              : "This Google account is already registered. Let's finish your profile.",
          })
          return
        }
      }

      await transitionToApp(() => navigate('/app', { replace: true }))
    }

    void finish()
    return () => {
      alive = false
    }
  }, [navigate])

  async function continueToApp() {
    setBusy(true)
    await transitionToApp(() => navigate('/app', { replace: true }))
  }

  if (notice) {
    return (
      <div className="grid min-h-screen place-items-center bg-[#F2F2F2] px-5">
        <div className="auth-notice w-full max-w-md rounded-[1.75rem] border border-ink/8 bg-white p-8 text-center shadow-[0_40px_80px_-40px_rgba(10,10,10,0.35)]">
          <p className="mb-2 text-xs font-bold tracking-[0.22em] text-paint uppercase">Welcome back</p>
          <h1
            className="font-[family-name:var(--font-display)] text-2xl tracking-tight text-ink"
            style={{ fontWeight: 800 }}
          >
            {notice.title}
          </h1>
          <p className="mt-3 text-sm leading-relaxed text-mute">{notice.message}</p>
          <button
            type="button"
            disabled={busy}
            onClick={() => void continueToApp()}
            className="mt-6 w-full rounded-full bg-paint px-5 py-3 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-50"
          >
            {busy ? 'Entering…' : 'Continue to Jobsy'}
          </button>
          <p className="mt-4 text-sm text-mute">
            Prefer the sign-in page?{' '}
            <Link to="/signin" className="font-semibold text-paint hover:underline">
              Sign in
            </Link>
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="app-shell grid min-h-screen place-items-center text-white/60">
      Completing sign-in…
    </div>
  )
}

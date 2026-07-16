import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

/** Handles Google OAuth / email redirect PKCE exchange. */
export function AuthCallbackPage() {
  const navigate = useNavigate()

  useEffect(() => {
    let alive = true

    async function finish() {
      const url = new URL(window.location.href)
      const code = url.searchParams.get('code')

      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code)
        if (!alive) return
        if (error) {
          navigate('/signin', { replace: true })
          return
        }
      } else {
        const { data } = await supabase.auth.getSession()
        if (!alive) return
        if (!data.session) {
          navigate('/signin', { replace: true })
          return
        }
      }

      navigate('/app', { replace: true })
    }

    void finish()
    return () => {
      alive = false
    }
  }, [navigate])

  return (
    <div className="app-shell grid min-h-screen place-items-center text-white/60">
      Completing sign-in…
    </div>
  )
}

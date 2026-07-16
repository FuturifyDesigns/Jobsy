import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { AUTH_EMAIL_VERIFIED_URL } from './constants'
import { supabase, type Profile } from './supabase'

type AuthState = {
  session: Session | null
  user: User | null
  profile: Profile | null
  loading: boolean
  isEmployer: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signUp: (email: string, password: string, fullName: string) => Promise<{ error: string | null }>
  signInWithGoogle: () => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  refreshProfile: () => Promise<void>
  switchRole: (target: 'worker' | 'employer') => Promise<{ error: string | null; role?: string }>
}

const PROFILE_SELECT =
  'id, full_name, user_type, avatar_url, location, bio, phone, skills, company_name, business_type, hourly_rate, experience_level, rating, is_profile_complete, last_role_switch_at'

const AuthContext = createContext<AuthState | null>(null)

async function ensureProfile(user: User, fullNameFallback = 'User') {
  const { data: existing } = await supabase
    .from('profiles')
    .select('id')
    .eq('id', user.id)
    .maybeSingle()
  if (existing) return

  const email = user.email ?? ''
  const fullName =
    (user.user_metadata?.full_name as string | undefined) ||
    (user.user_metadata?.name as string | undefined) ||
    fullNameFallback

  await supabase.rpc('create_profile_for_user', {
    user_id: user.id,
    user_email: email,
    user_full_name: fullName,
    user_type: 'worker',
  })
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  const loadProfile = useCallback(async (userId: string) => {
    const { data } = await supabase
      .from('profiles')
      .select(PROFILE_SELECT)
      .eq('id', userId)
      .maybeSingle()
    setProfile((data as Profile | null) ?? null)
  }, [])

  const refreshProfile = useCallback(async () => {
    if (!session?.user?.id) return
    await loadProfile(session.user.id)
  }, [loadProfile, session?.user?.id])

  useEffect(() => {
    let mounted = true

    supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted) return
      setSession(data.session)
      if (data.session?.user) {
        await ensureProfile(data.session.user)
        await loadProfile(data.session.user.id)
      }
      if (mounted) setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      if (next?.user) {
        void (async () => {
          await ensureProfile(next.user)
          await loadProfile(next.user.id)
        })()
      } else {
        setProfile(null)
      }
    })

    return () => {
      mounted = false
      sub.subscription.unsubscribe()
    }
  }, [loadProfile])

  const signIn = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error?.message ?? null }
  }, [])

  const signUp = useCallback(async (email: string, password: string, fullName: string) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
        emailRedirectTo: AUTH_EMAIL_VERIFIED_URL,
      },
    })
    if (error) return { error: error.message }
    if (data.user?.id) {
      await supabase.rpc('create_profile_for_user', {
        user_id: data.user.id,
        user_email: email.trim(),
        user_full_name: fullName,
        user_type: 'worker',
      })
    }
    return { error: null }
  }, [])

  const signInWithGoogle = useCallback(async () => {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: `${window.location.origin}${import.meta.env.BASE_URL}auth/callback`.replace(
          /([^:]\/)\/+/g,
          '$1',
        ),
        queryParams: { access_type: 'offline', prompt: 'consent' },
      },
    })
    return { error: error?.message ?? null }
  }, [])

  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
    setProfile(null)
  }, [])

  const switchRole = useCallback(
    async (target: 'worker' | 'employer') => {
      const { data, error } = await supabase.rpc('switch_user_role', {
        p_target_role: target,
      })
      if (error) return { error: error.message }
      await refreshProfile()
      return { error: null, role: (data as string) ?? target }
    },
    [refreshProfile],
  )

  const isEmployer = profile?.user_type === 'employer'

  const value = useMemo<AuthState>(
    () => ({
      session,
      user: session?.user ?? null,
      profile,
      loading,
      isEmployer,
      signIn,
      signUp,
      signInWithGoogle,
      signOut,
      refreshProfile,
      switchRole,
    }),
    [
      session,
      profile,
      loading,
      isEmployer,
      signIn,
      signUp,
      signInWithGoogle,
      signOut,
      refreshProfile,
      switchRole,
    ],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}

import { useRef } from 'react'
import { NavLink, Outlet, Navigate, Link } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { useAuth } from '../../lib/auth'
import { Logo } from '../../components/Logo'
import { Avatar } from '../../components/Avatar'
import { ToastProvider } from '../../components/Toast'
import { AmbientField } from '../../components/AppUi'

gsap.registerPlugin(useGSAP)

export function AppLayout() {
  return (
    <ToastProvider>
      <AppShell />
    </ToastProvider>
  )
}

function AppShell() {
  const { user, profile, loading, signOut, isEmployer } = useAuth()
  const rootRef = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      gsap.from('.app-nav-item', {
        opacity: 0,
        y: -8,
        stagger: 0.04,
        duration: 0.45,
        ease: 'power2.out',
      })
    },
    { scope: rootRef, dependencies: [isEmployer, loading] },
  )

  if (loading) {
    return (
      <div className="app-shell grid min-h-screen place-items-center">
        <div className="flex flex-col items-center gap-3">
          <div className="h-10 w-10 animate-pulse rounded-2xl bg-paint/40" />
          <p className="text-sm text-white/50">Loading Jobsy…</p>
        </div>
      </div>
    )
  }

  if (!user) return <Navigate to="/signin" replace />

  const workerLinks = [
    { to: '/app', end: true, label: 'Find Jobs' },
    { to: '/app/saved', label: 'Saved' },
    { to: '/app/web-jobs', label: 'Web Jobs' },
    { to: '/app/wallet', label: 'Wallet' },
    { to: '/app/messages', label: 'Messages' },
    { to: '/app/profile', label: 'Profile' },
  ]

  const employerLinks = [
    { to: '/app', end: true, label: 'My Jobs' },
    { to: '/app/post', label: 'Post Job' },
    { to: '/app/wallet', label: 'Wallet' },
    { to: '/app/messages', label: 'Messages' },
    { to: '/app/profile', label: 'Profile' },
  ]

  const links = isEmployer ? employerLinks : workerLinks
  const role = isEmployer ? 'Employer' : 'Worker'

  return (
    <div ref={rootRef} className="app-shell relative overflow-x-hidden">
      <AmbientField />

      <header className="sticky top-0 z-40 border-b border-white/8 bg-[#050508]/75 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4">
          <Logo dark to="/app" />
          <nav className="hidden items-center gap-1 md:flex">
            {links.map((l) => (
              <NavLink
                key={l.to}
                to={l.to}
                end={l.end}
                className={({ isActive }) =>
                  `app-nav-item rounded-full px-3.5 py-1.5 text-sm font-medium transition duration-300 ${
                    isActive
                      ? 'bg-white text-black shadow-[0_8px_24px_-12px_rgba(255,255,255,0.5)]'
                      : 'text-white/60 hover:-translate-y-0.5 hover:text-white'
                  }`
                }
              >
                {l.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-3">
            <Link
              to="/app/profile"
              className="group flex items-center gap-2.5 rounded-full border border-white/10 bg-white/[0.03] py-1 pr-3 pl-1 transition hover:border-paint/40"
            >
              <Avatar url={profile?.avatar_url} name={profile?.full_name ?? user.email} size="sm" ring={false} />
              <span className="hidden text-left sm:block">
                <span className="block text-xs font-semibold text-white group-hover:text-white">
                  {profile?.full_name ?? 'Profile'}
                </span>
                <span className="block text-[10px] tracking-wide text-white/40 uppercase">{role}</span>
              </span>
            </Link>
            <button
              type="button"
              onClick={() => void signOut()}
              className="rounded-full border border-white/15 px-3 py-1.5 text-xs font-semibold text-white/75 transition hover:border-white/35 hover:text-white"
            >
              Sign out
            </button>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto border-t border-white/5 px-3 py-2 md:hidden">
          {links.map((l) => (
            <NavLink
              key={l.to}
              to={l.to}
              end={l.end}
              className={({ isActive }) =>
                `shrink-0 rounded-full px-3 py-1.5 text-xs font-medium ${
                  isActive ? 'bg-white text-black' : 'text-white/60'
                }`
              }
            >
              {l.label}
            </NavLink>
          ))}
        </nav>
      </header>

      <main className="relative mx-auto max-w-6xl px-4 py-8 pb-20">
        <Outlet />
      </main>
    </div>
  )
}

import { NavLink, Outlet, Navigate, Link } from 'react-router-dom'
import { useAuth } from '../../lib/auth'
import { Logo } from '../../components/Logo'

export function AppLayout() {
  const { user, profile, loading, signOut, isEmployer } = useAuth()

  if (loading) {
    return (
      <div className="app-shell grid min-h-screen place-items-center text-white/60">
        Loading Jobsy…
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
    <div className="app-shell">
      <header className="sticky top-0 z-40 border-b border-white/8 bg-[#050508]/90 backdrop-blur-md">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-4 px-4">
          <Logo dark to="/app" />
          <nav className="hidden items-center gap-1 md:flex">
            {links.map((l) => (
              <NavLink
                key={l.to}
                to={l.to}
                end={l.end}
                className={({ isActive }) =>
                  `rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                    isActive ? 'bg-white text-ink' : 'text-white/65 hover:text-white'
                  }`
                }
              >
                {l.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-3">
            <span className="hidden text-xs text-white/45 sm:inline">
              {profile?.full_name ?? user.email} · {role}
            </span>
            <button
              type="button"
              onClick={() => void signOut()}
              className="rounded-full border border-white/15 px-3 py-1.5 text-xs font-semibold text-white/80 hover:border-white/35"
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
                  isActive ? 'bg-white text-ink' : 'text-white/60'
                }`
              }
            >
              {l.label}
            </NavLink>
          ))}
        </nav>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-6 pb-16">
        <Outlet />
      </main>

      <div className="fixed bottom-4 right-4 md:hidden">
        <Link
          to="/"
          className="rounded-full bg-paint px-4 py-2 text-xs font-bold text-white shadow-lg"
        >
          Marketing site
        </Link>
      </div>
    </div>
  )
}

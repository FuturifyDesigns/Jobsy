import type { ReactNode } from 'react'
import { Link, NavLink } from 'react-router-dom'
import { Logo } from './Logo'
import { MagneticButton } from './MagneticButton'
import { LivePaintBackground } from './LivePaintBackground'
import { openCookieSettings } from './CookieConsent'

const nav = [
  { to: '/features', label: 'Features' },
  { to: '/how-it-works', label: 'How it works' },
]

export function SiteShell({
  children,
  showPaint = true,
}: {
  children: ReactNode
  showPaint?: boolean
}) {
  return (
    <div className="relative min-h-screen overflow-x-hidden bg-paper">
      {showPaint && <LivePaintBackground />}
      <SiteHeader />
      {children}
      <SiteFooter />
    </div>
  )
}

export function SiteHeader() {
  return (
    <header className="hero-nav fixed inset-x-0 top-0 z-50 border-b border-ink/5 bg-paper/70 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5">
        <Logo />
        <nav className="hidden items-center gap-8 text-sm font-medium text-mute md:flex">
          {nav.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (isActive ? 'text-ink' : 'hover:text-ink')}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <Link to="/signup">
          <MagneticButton className="!px-5 !py-2.5 text-sm">Get Started</MagneticButton>
        </Link>
      </div>
    </header>
  )
}

export function SiteFooter() {
  const linkClass =
    'footer-link group relative inline-flex items-center text-white/75 transition-colors duration-300 hover:text-white'

  return (
    <footer className="site-footer relative overflow-hidden">
      <div className="relative mx-auto max-w-6xl px-5 pb-10 pt-6">
        <div className="overflow-hidden rounded-[2rem] bg-ink text-white">
          <div className="relative px-8 py-12 md:px-12 md:py-14">
            <div className="pointer-events-none absolute -right-10 -top-16 h-64 w-64 rounded-full bg-paint/40 blur-3xl" />
            <div className="pointer-events-none absolute -bottom-20 left-10 h-56 w-56 rounded-full bg-paint-soft/25 blur-3xl" />

            <div className="relative grid gap-10 md:grid-cols-[1.4fr_1fr_1fr]">
              <div>
                <Logo dark to="/" />
                <p
                  className="mt-5 max-w-sm font-[family-name:var(--font-display)] text-3xl leading-tight tracking-tight"
                  style={{ fontWeight: 800 }}
                >
                  Find work. <span className="text-paint-soft">Get paid.</span>
                  <br />
                  Keep moving.
                </p>
                <div className="mt-8">
                  <Link to="/signup" className="inline-block transition-transform duration-300 hover:-translate-y-0.5">
                    <MagneticButton className="footer-cta shadow-[0_18px_40px_-14px_rgba(30,79,215,0.9)] transition-shadow duration-300 hover:shadow-[0_22px_48px_-12px_rgba(30,79,215,1)]">
                      Get Started
                    </MagneticButton>
                  </Link>
                </div>
              </div>

              <div>
                <p className="mb-4 text-xs font-bold tracking-[0.22em] text-white/40 uppercase">
                  Product
                </p>
                <ul className="space-y-3 text-sm">
                  <li>
                    <Link to="/features" className={linkClass}>
                      <FooterLinkLabel>Features</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <Link to="/how-it-works" className={linkClass}>
                      <FooterLinkLabel>How it works</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <Link to="/app/web-jobs" className={linkClass}>
                      <FooterLinkLabel>Web Jobs</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <a
                      href="https://play.google.com/store"
                      target="_blank"
                      rel="noreferrer"
                      className={linkClass}
                    >
                      <FooterLinkLabel>Google Play</FooterLinkLabel>
                    </a>
                  </li>
                </ul>
              </div>

              <div>
                <p className="mb-4 text-xs font-bold tracking-[0.22em] text-white/40 uppercase">
                  Company
                </p>
                <ul className="space-y-3 text-sm">
                  <li>
                    <Link to="/privacy" className={linkClass}>
                      <FooterLinkLabel>Privacy Policy</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <Link to="/terms" className={linkClass}>
                      <FooterLinkLabel>Terms of Service</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <Link to="/cookies" className={linkClass}>
                      <FooterLinkLabel>Cookie Policy</FooterLinkLabel>
                    </Link>
                  </li>
                  <li>
                    <button
                      type="button"
                      onClick={() => openCookieSettings()}
                      className={linkClass}
                    >
                      <FooterLinkLabel>Cookie settings</FooterLinkLabel>
                    </button>
                  </li>
                </ul>
              </div>
            </div>

            <div className="relative mt-12 flex flex-col gap-3 border-t border-white/10 pt-6 text-sm text-white/45 md:flex-row md:items-center md:justify-between">
              <p>
                © {new Date().getFullYear()} Jobsy. Aligned with Botswana&apos;s Data Protection Act,
                2024.
              </p>
              <p>
                Built by{' '}
                <a
                  href="https://futurifydesigns.com"
                  target="_blank"
                  rel="noreferrer"
                  className="group relative inline-flex font-semibold text-paint-soft transition-colors duration-300 hover:text-white"
                >
                  <span className="relative">
                    Futurify Designs
                    <span className="absolute -bottom-0.5 left-0 h-px w-full origin-left scale-x-0 bg-current transition-transform duration-300 ease-out group-hover:scale-x-100" />
                  </span>
                </a>
              </p>
            </div>
          </div>
        </div>
      </div>
    </footer>
  )
}

function FooterLinkLabel({ children }: { children: ReactNode }) {
  return (
    <span className="relative inline-flex translate-x-0 items-center gap-1.5 transition-transform duration-300 ease-out group-hover:translate-x-1.5">
      <span
        className="inline-block h-px w-0 bg-paint-soft transition-all duration-300 ease-out group-hover:w-3"
        aria-hidden
      />
      <span className="relative">
        {children}
        <span className="absolute -bottom-0.5 left-0 h-px w-full origin-left scale-x-0 bg-paint-soft transition-transform duration-300 ease-out group-hover:scale-x-100" />
      </span>
    </span>
  )
}

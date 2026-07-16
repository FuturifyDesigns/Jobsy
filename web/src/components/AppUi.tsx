import { useEffect, useId, useRef, type ReactNode, type RefObject } from 'react'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'

gsap.registerPlugin(useGSAP)

type ConfirmDialogProps = {
  open: boolean
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  busy,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  const titleId = useId()
  const panelRef = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      if (!open || !panelRef.current) return
      gsap.fromTo(
        panelRef.current,
        { opacity: 0, y: 24, scale: 0.96 },
        { opacity: 1, y: 0, scale: 1, duration: 0.4, ease: 'power3.out' },
      )
    },
    { dependencies: [open] },
  )

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !busy) onCancel()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, busy, onCancel])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-[130] grid place-items-center bg-black/70 p-4 backdrop-blur-sm"
      role="presentation"
      onClick={() => {
        if (!busy) onCancel()
      }}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className="w-[min(100%,26rem)] rounded-[1.75rem] border border-white/12 bg-[#0c0c12] p-6 shadow-[0_40px_100px_-40px_rgba(30,79,215,0.55)]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-paint/20 text-paint-soft">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M16 3h5v5M8 21H3v-5M21 3l-7 7M3 21l7-7" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <h2 id={titleId} className="font-[family-name:var(--font-display)] text-xl tracking-tight" style={{ fontWeight: 800 }}>
          {title}
        </h2>
        <p className="mt-2 text-sm leading-relaxed text-white/55">{message}</p>
        <div className="mt-6 flex flex-wrap gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={onConfirm}
            className="rounded-full bg-paint px-5 py-2.5 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-50"
          >
            {busy ? 'Switching…' : confirmLabel}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onCancel}
            className="rounded-full border border-white/15 px-5 py-2.5 text-sm font-semibold text-white/75 hover:border-white/30 disabled:opacity-50"
          >
            {cancelLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

/** Branch.co-style page intro: trunk accent + brush + title. */
export function PageHero({
  brush,
  title,
  subtitle,
  action,
}: {
  brush?: string
  title: string
  subtitle?: string
  action?: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const tl = gsap.timeline({ defaults: { ease: 'power3.out' } })
      tl.from('.hero-trunk', { scaleY: 0, transformOrigin: 'top', duration: 0.55 })
        .from('.hero-copy > *', { opacity: 0, y: 18, stagger: 0.07, duration: 0.45 }, '-=0.25')
        .from('.hero-action', { opacity: 0, x: 16, duration: 0.4 }, '-=0.25')
    },
    { scope: ref },
  )

  return (
    <div ref={ref} className="mb-6 flex flex-col gap-3 sm:mb-8 sm:gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div className="flex gap-3 sm:gap-4">
        <div className="hero-trunk relative mt-1 hidden w-px shrink-0 bg-gradient-to-b from-paint via-paint/50 to-transparent sm:block" style={{ minHeight: '4.5rem' }}>
          <span className="absolute -top-1 left-1/2 h-2.5 w-2.5 -translate-x-1/2 rounded-full bg-paint shadow-[0_0_16px_rgba(30,79,215,0.8)]" />
        </div>
        <div className="hero-copy">
          {brush && (
              <p className="font-[family-name:var(--font-brush)] text-xl text-paint-soft sm:text-2xl" style={{ fontWeight: 700 }}>
              {brush}
            </p>
          )}
          <h1
            className="font-[family-name:var(--font-display)] text-[1.95rem] leading-none tracking-tight sm:text-3xl md:text-[2.75rem]"
            style={{ fontWeight: 800 }}
          >
            {title}
          </h1>
          {subtitle && <p className="mt-1.5 max-w-xl text-sm leading-relaxed text-white/50 sm:mt-2">{subtitle}</p>}
        </div>
      </div>
      {action && <div className="hero-action w-full sm:w-auto">{action}</div>}
    </div>
  )
}

export function StatusPill({ status }: { status: string | null | undefined }) {
  const s = (status ?? 'unknown').toLowerCase()
  const tone =
    s === 'active' || s === 'accepted' || s === 'in_progress'
      ? 'bg-emerald-500/15 text-emerald-300 border-emerald-400/25'
      : s === 'completed'
        ? 'bg-paint/20 text-paint-soft border-paint/30'
        : s === 'pending'
          ? 'bg-amber-500/15 text-amber-200 border-amber-400/25'
          : s === 'cancelled' || s === 'rejected'
            ? 'bg-red-500/15 text-red-300 border-red-400/25'
            : 'bg-white/8 text-white/60 border-white/10'
  return (
    <span className={`inline-flex rounded-full border px-2.5 py-0.5 text-[11px] font-bold tracking-wide capitalize ${tone}`}>
      {s.replace('_', ' ')}
    </span>
  )
}

/** Lusion-style magnetic glass card — tilt + glow follow cursor. */
export function GlassCard({
  children,
  className = '',
  hover = true,
  magnetic = true,
}: {
  children: ReactNode
  className?: string
  hover?: boolean
  magnetic?: boolean
}) {
  const root = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      if (!hover || !magnetic) return
      const el = root.current
      if (!el) return
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return

      const onMove = (e: MouseEvent) => {
        const rect = el.getBoundingClientRect()
        const px = (e.clientX - rect.left) / rect.width - 0.5
        const py = (e.clientY - rect.top) / rect.height - 0.5
        gsap.to(el, {
          rotateY: px * 6,
          rotateX: -py * 6,
          y: -4,
          duration: 0.35,
          ease: 'power3.out',
          transformPerspective: 800,
        })
        const glow = el.querySelector('.card-glow') as HTMLElement | null
        if (glow) {
          gsap.to(glow, {
            x: px * 40,
            y: py * 40,
            opacity: 0.55,
            duration: 0.35,
            ease: 'power3.out',
          })
        }
      }
      const onLeave = () => {
        gsap.to(el, { rotateX: 0, rotateY: 0, y: 0, duration: 0.6, ease: 'power3.out' })
        const glow = el.querySelector('.card-glow') as HTMLElement | null
        if (glow) gsap.to(glow, { x: 0, y: 0, opacity: 0.25, duration: 0.5 })
      }
      el.addEventListener('mousemove', onMove)
      el.addEventListener('mouseleave', onLeave)
      return () => {
        el.removeEventListener('mousemove', onMove)
        el.removeEventListener('mouseleave', onLeave)
      }
    },
    { scope: root, dependencies: [hover, magnetic] },
  )

  return (
    <div
      ref={root}
      className={`group relative overflow-hidden rounded-[1.2rem] border border-white/8 bg-white/[0.035] p-3.5 sm:rounded-[1.35rem] sm:p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] backdrop-blur-sm transition-[border-color,background] duration-300 will-change-transform ${
        hover ? 'hover:border-paint/40 hover:bg-white/[0.055]' : ''
      } ${className}`}
      style={{ transformStyle: 'preserve-3d' }}
    >
      <div className="card-glow pointer-events-none absolute -right-10 -top-10 h-36 w-36 rounded-full bg-paint/25 opacity-25 blur-3xl" />
      <div className="pointer-events-none absolute inset-y-3 left-0 w-px bg-gradient-to-b from-paint via-paint/30 to-transparent opacity-0 transition group-hover:opacity-100" />
      <div className="relative">{children}</div>
    </div>
  )
}

/** Floating paint orbs — Lusion ambient field for the app shell. */
export function AmbientField() {
  const ref = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return
      gsap.to('.orb-a', { y: 40, x: 20, duration: 7, yoyo: true, repeat: -1, ease: 'sine.inOut' })
      gsap.to('.orb-b', { y: -30, x: -25, duration: 9, yoyo: true, repeat: -1, ease: 'sine.inOut' })
      gsap.to('.orb-c', { y: 24, x: -18, duration: 6.5, yoyo: true, repeat: -1, ease: 'sine.inOut' })
    },
    { scope: ref },
  )

  return (
    <div ref={ref} className="pointer-events-none absolute inset-0 -z-10 overflow-hidden" aria-hidden>
      <div className="orb-a absolute -left-24 top-0 h-80 w-80 rounded-full bg-paint/25 blur-[110px]" />
      <div className="orb-b absolute right-[-4rem] top-32 h-96 w-96 rounded-full bg-[#4d7ef0]/15 blur-[130px]" />
      <div className="orb-c absolute bottom-20 left-1/3 h-64 w-64 rounded-full bg-paint/10 blur-[100px]" />
    </div>
  )
}

export function useStaggerReveal(
  scope: RefObject<HTMLElement | null>,
  deps: unknown[],
  selector = '.reveal-item',
) {
  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return
      gsap.from(selector, {
        opacity: 0,
        y: 22,
        stagger: 0.055,
        duration: 0.5,
        ease: 'power3.out',
        clearProps: 'all',
      })
    },
    { scope, dependencies: deps },
  )
}

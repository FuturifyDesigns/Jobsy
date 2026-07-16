import { useEffect, useId, useRef, type ReactNode } from 'react'
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
  return (
    <div className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        {brush && (
          <p className="font-[family-name:var(--font-brush)] text-2xl text-paint-soft" style={{ fontWeight: 700 }}>
            {brush}
          </p>
        )}
        <h1
          className="font-[family-name:var(--font-display)] text-3xl tracking-tight md:text-4xl"
          style={{ fontWeight: 800 }}
        >
          {title}
        </h1>
        {subtitle && <p className="mt-2 max-w-xl text-sm leading-relaxed text-white/50">{subtitle}</p>}
      </div>
      {action}
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

export function GlassCard({
  children,
  className = '',
  hover = true,
}: {
  children: ReactNode
  className?: string
  hover?: boolean
}) {
  return (
    <div
      className={`group relative overflow-hidden rounded-[1.35rem] border border-white/8 bg-white/[0.035] p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] backdrop-blur-sm transition duration-300 ${
        hover ? 'hover:-translate-y-0.5 hover:border-paint/35 hover:bg-white/[0.055]' : ''
      } ${className}`}
    >
      <div className="pointer-events-none absolute -right-8 -top-8 h-28 w-28 rounded-full bg-paint/10 blur-2xl transition group-hover:bg-paint/20" />
      <div className="relative">{children}</div>
    </div>
  )
}

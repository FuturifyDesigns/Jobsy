import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import gsap from 'gsap'

export type ToastTone = 'ok' | 'info' | 'warn' | 'error'

type ToastItem = { id: number; title: string; message?: string; tone: ToastTone }

type ToastApi = {
  push: (title: string, opts?: { message?: string; tone?: ToastTone }) => void
  success: (title: string, message?: string) => void
  error: (title: string, message?: string) => void
  info: (title: string, message?: string) => void
}

const ToastContext = createContext<ToastApi | null>(null)

let toastSeq = 0

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([])

  const push = useCallback((title: string, opts?: { message?: string; tone?: ToastTone }) => {
    const id = ++toastSeq
    setItems((prev) => [...prev, { id, title, message: opts?.message, tone: opts?.tone ?? 'info' }])
    window.setTimeout(() => {
      setItems((prev) => prev.filter((t) => t.id !== id))
    }, 4200)
  }, [])

  const api = useMemo<ToastApi>(
    () => ({
      push,
      success: (title, message) => push(title, { message, tone: 'ok' }),
      error: (title, message) => push(title, { message, tone: 'error' }),
      info: (title, message) => push(title, { message, tone: 'info' }),
    }),
    [push],
  )

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="pointer-events-none fixed top-20 right-4 z-[120] flex w-[min(100%,22rem)] flex-col gap-2 md:right-6">
        {items.map((t) => (
          <ToastCard key={t.id} item={t} />
        ))}
      </div>
    </ToastContext.Provider>
  )
}

function ToastCard({ item }: { item: ToastItem }) {
  const ref = useCallback((node: HTMLDivElement | null) => {
    if (!node) return
    gsap.fromTo(
      node,
      { opacity: 0, y: -16, scale: 0.96 },
      { opacity: 1, y: 0, scale: 1, duration: 0.45, ease: 'power3.out' },
    )
  }, [])

  const tone =
    item.tone === 'ok'
      ? 'border-emerald-400/35 bg-emerald-500/15 text-emerald-50'
      : item.tone === 'error'
        ? 'border-red-400/35 bg-red-500/15 text-red-50'
        : item.tone === 'warn'
          ? 'border-amber-400/35 bg-amber-500/15 text-amber-50'
          : 'border-paint-soft/40 bg-[#1e4fd7]/20 text-white'

  return (
    <div
      ref={ref}
      role="status"
      className={`pointer-events-auto rounded-2xl border px-4 py-3 shadow-[0_20px_50px_-24px_rgba(0,0,0,0.8)] backdrop-blur-xl ${tone}`}
    >
      <p className="text-sm font-bold tracking-tight">{item.title}</p>
      {item.message && <p className="mt-1 text-xs leading-relaxed opacity-80">{item.message}</p>}
    </div>
  )
}

export function useToast() {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used within ToastProvider')
  return ctx
}

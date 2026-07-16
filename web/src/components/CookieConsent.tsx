import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import {
  canUseAnalytics,
  readConsent,
  writeConsent,
  type CookieConsentValue,
} from '../lib/legal'

type Toast = { id: number; message: string; tone: 'ok' | 'muted' }

let toastId = 0

export function CookieProvider({ children }: { children: ReactNode }) {
  const [showBanner, setShowBanner] = useState(false)
  const [toasts, setToasts] = useState<Toast[]>([])

  useEffect(() => {
    setShowBanner(readConsent() === null)
  }, [])

  const pushToast = useCallback((message: string, tone: Toast['tone'] = 'ok') => {
    const id = ++toastId
    setToasts((t) => [...t, { id, message, tone }])
    window.setTimeout(() => {
      setToasts((t) => t.filter((x) => x.id !== id))
    }, 4200)
  }, [])

  const decide = useCallback(
    (value: CookieConsentValue) => {
      writeConsent(value)
      setShowBanner(false)
      if (value === 'accepted') {
        pushToast('Cookies enabled. Optional cookies are now active.', 'ok')
      } else {
        pushToast('Cookies declined. Only essential cookies will be used.', 'muted')
      }
    },
    [pushToast],
  )

  useEffect(() => {
    const open = () => setShowBanner(true)
    window.addEventListener('jobsy:open-cookie-settings', open)
    return () => window.removeEventListener('jobsy:open-cookie-settings', open)
  }, [])

  // Expose analytics gate for future scripts
  useEffect(() => {
    ;(window as unknown as { __JOBSY_ANALYTICS__?: boolean }).__JOBSY_ANALYTICS__ =
      canUseAnalytics()
    const onChange = () => {
      ;(window as unknown as { __JOBSY_ANALYTICS__?: boolean }).__JOBSY_ANALYTICS__ =
        canUseAnalytics()
    }
    window.addEventListener('jobsy:cookie-consent', onChange)
    return () => window.removeEventListener('jobsy:cookie-consent', onChange)
  }, [])

  return (
    <>
      {children}

      {showBanner && (
        <div
          role="dialog"
          aria-labelledby="cookie-title"
          aria-describedby="cookie-desc"
          className="fixed inset-x-4 bottom-4 z-[100] mx-auto max-w-2xl rounded-2xl border border-ink/10 bg-white/95 p-5 shadow-[0_24px_64px_-20px_rgba(10,10,10,0.45)] backdrop-blur-xl md:inset-x-auto md:right-6 md:bottom-6 md:left-auto md:w-[min(100%,28rem)]"
        >
          <p id="cookie-title" className="text-sm font-bold tracking-wide text-ink uppercase">
            Cookies & data
          </p>
          <p id="cookie-desc" className="mt-2 text-sm leading-relaxed text-mute">
            We use essential cookies to run Jobsy securely. Optional cookies help us understand
            usage.             Under Botswana&apos;s{' '}
            <strong className="font-semibold text-ink">Data Protection Act, 2024</strong>, you
            choose whether optional cookies are enabled.{' '}
            <Link to="/cookies" className="font-semibold text-paint hover:underline">
              Cookie Policy
            </Link>
            {' · '}
            <Link to="/privacy" className="font-semibold text-paint hover:underline">
              Privacy
            </Link>
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => decide('accepted')}
              className="rounded-full bg-paint px-5 py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
            >
              Enable cookies
            </button>
            <button
              type="button"
              onClick={() => decide('declined')}
              className="rounded-full border border-ink/15 bg-white px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-ink/30"
            >
              Decline
            </button>
          </div>
        </div>
      )}

      <div className="pointer-events-none fixed top-20 right-4 z-[110] flex w-[min(100%,20rem)] flex-col gap-2 md:right-6">
        {toasts.map((t) => (
          <div
            key={t.id}
            role="status"
            className={`pointer-events-auto rounded-xl border px-4 py-3 text-sm font-medium shadow-lg backdrop-blur-md ${
              t.tone === 'ok'
                ? 'border-paint/25 bg-white/95 text-ink'
                : 'border-ink/10 bg-white/95 text-mute'
            }`}
          >
            {t.message}
          </div>
        ))}
      </div>
    </>
  )
}

export function openCookieSettings() {
  window.dispatchEvent(new Event('jobsy:open-cookie-settings'))
}

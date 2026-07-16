import { useRef } from 'react'
import { Link } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { GlassCard, PageHero } from '../../components/AppUi'

gsap.registerPlugin(useGSAP)

/** Wallet is a placeholder in the mobile app — keep parity with a richer web shell. */
export function WalletPage() {
  const rootRef = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      gsap.from('.wallet-reveal', {
        opacity: 0,
        y: 24,
        stagger: 0.1,
        duration: 0.55,
        ease: 'power3.out',
      })
      gsap.to('.wallet-orb', {
        y: 12,
        duration: 2.4,
        yoyo: true,
        repeat: -1,
        ease: 'sine.inOut',
      })
    },
    { scope: rootRef },
  )

  return (
    <div ref={rootRef} className="relative mx-auto max-w-2xl py-3 text-center sm:py-6">
      <div className="wallet-orb pointer-events-none absolute left-1/2 top-8 h-40 w-40 -translate-x-1/2 rounded-full bg-paint/25 blur-3xl" />
      <PageHero brush="Coming soon" title="Wallet" subtitle="Payments and payouts are on the way." />
      <GlassCard className="wallet-reveal !p-5 sm:!p-8" hover={false}>
        <div className="mx-auto mb-4 grid h-14 w-14 place-items-center rounded-2xl bg-paint/20 text-paint-soft sm:mb-5 sm:h-16 sm:w-16">
          <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="2" y="5" width="20" height="14" rx="3" />
            <path d="M2 10h20" />
          </svg>
        </div>
        <p className="text-sm leading-relaxed text-white/55">
          Posting, applying, and messaging stay free while we finish Wallet. You’ll get in-app
          notifications when payouts go live.
        </p>
        <Link
          to="/app"
          className="mt-6 inline-flex rounded-full bg-paint px-5 py-2.5 text-sm font-bold text-white shadow-[0_16px_40px_-18px_rgba(30,79,215,0.85)] transition hover:brightness-110 sm:mt-8 sm:px-6 sm:py-3"
        >
          Back to jobs
        </Link>
      </GlassCard>
    </div>
  )
}

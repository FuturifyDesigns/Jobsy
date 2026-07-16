import { useRef } from 'react'
import { Link } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { MagneticButton } from '../components/MagneticButton'
import { SiteShell } from '../components/SiteShell'
import { BranchTimeline } from '../components/BranchTimeline'

gsap.registerPlugin(useGSAP, ScrollTrigger)

const highlights = [
  {
    n: '01',
    title: 'Instant Connections',
    body: 'Match with real work near you — no endless scrolling, no noise.',
  },
  {
    n: '02',
    title: 'No Hassle',
    body: 'Verified people. Clear rates. Chat and get moving the same day.',
  },
  {
    n: '03',
    title: 'Post in Minutes',
    body: 'Employers go live fast. Workers apply with one tap.',
  },
]

const branchFeatures = [
  {
    n: '01',
    label: 'Match',
    title: 'Instant Connections',
    body: 'See nearby work that fits your skills — not a feed full of noise.',
    to: '/signup',
  },
  {
    n: '02',
    label: 'Trust',
    title: 'No Hassle',
    body: 'Verified people, clear rates, and chat that keeps things moving.',
    to: '/signup',
  },
  {
    n: '03',
    label: 'Speed',
    title: 'Post in Minutes',
    body: 'Employers go live fast. Workers apply with one short note.',
    to: '/signup',
  },
  {
    n: '04',
    label: 'Web',
    title: 'Web Jobs',
    body: 'Imported listings from boards across Botswana — apply on the source site.',
    to: '/app/web-jobs',
  },
  {
    n: '05',
    label: 'Chat',
    title: 'In-app messaging',
    body: 'After a hire, message with text, images, and files in one thread.',
    to: '/signup',
  },
  {
    n: '06',
    label: 'Roles',
    title: 'One account, two modes',
    body: 'Switch between worker and employer whenever you need to hire or find work.',
    to: '/signup',
  },
]

export function FeaturesPage() {
  const root = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return

      const intro = gsap.timeline({ defaults: { ease: 'power3.out' } })
      intro
        .from('.feat-kicker', { y: 24, opacity: 0, duration: 0.6 })
        .from('.feat-line', { yPercent: 110, duration: 0.95, stagger: 0.1 }, '-=0.35')
        .from('.feat-sub', { y: 20, opacity: 0, duration: 0.55 }, '-=0.45')

      // Lusion-style pinned horizontal feature strip
      const panels = gsap.utils.toArray<HTMLElement>('.feat-panel')
      if (panels.length) {
        gsap.to(panels, {
          xPercent: -100 * (panels.length - 1),
          ease: 'none',
          scrollTrigger: {
            trigger: '.feat-pin',
            start: 'top top',
            end: () => `+=${panels.length * 85}%`,
            pin: true,
            scrub: 0.8,
            anticipatePin: 1,
            invalidateOnRefresh: true,
          },
        })
      }

      // Pin changes document height — refresh so BranchTimeline below recalculates
      requestAnimationFrame(() => {
        requestAnimationFrame(() => ScrollTrigger.refresh())
      })

      gsap.from('.feat-cta', {
        y: 32,
        duration: 0.8,
        ease: 'power3.out',
        immediateRender: false,
        scrollTrigger: { trigger: '.feat-cta', start: 'top 90%', once: true },
      })
    },
    { scope: root },
  )

  return (
    <SiteShell>
      <div ref={root}>
        <section className="mx-auto max-w-6xl px-5 pt-28 pb-20 md:pt-32 md:pb-24">
          <p
            className="feat-kicker font-[family-name:var(--font-brush)] text-3xl text-paint"
            style={{ fontWeight: 700 }}
          >
            Features
          </p>
          <h1 className="mt-2 font-[family-name:var(--font-display)] text-[clamp(2.8rem,8vw,5.5rem)] leading-[0.92] tracking-[-0.04em] text-ink">
            <span className="block overflow-hidden">
              <span className="feat-line inline-block" style={{ fontWeight: 800 }}>
                Work that moves
              </span>
            </span>
            <span className="block overflow-hidden">
              <span className="feat-line inline-block text-paint" style={{ fontWeight: 800 }}>
                as fast as you do.
              </span>
            </span>
          </h1>
          <p className="feat-sub mt-6 max-w-lg text-lg text-mute">
            Everything you need to find work or hire nearby — built for Botswana.
          </p>
        </section>

        {/* Lusion horizontal pin */}
        <section className="feat-pin relative h-screen overflow-hidden bg-ink text-white">
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_15%_20%,rgba(30,79,215,0.4),transparent_55%)]" />
          <div className="relative flex h-full items-center">
            <div className="flex h-full w-full">
              {highlights.map((item) => (
                <article
                  key={item.n}
                  className="feat-panel flex h-full w-full shrink-0 flex-col justify-center px-8 md:px-16 lg:px-24"
                >
                  <p
                    className="font-[family-name:var(--font-brush)] text-4xl text-paint-soft md:text-5xl"
                    style={{ fontWeight: 700 }}
                  >
                    {item.n}
                  </p>
                  <h2
                    className="mt-4 max-w-2xl font-[family-name:var(--font-display)] text-[clamp(2.4rem,6vw,4.5rem)] leading-[0.95] tracking-tight"
                    style={{ fontWeight: 800 }}
                  >
                    {item.title}
                  </h2>
                  <p className="mt-6 max-w-md text-lg leading-relaxed text-white/60">{item.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <BranchTimeline
          eyebrow="All the tools"
          heading={
            <>
              Six ways Jobsy
              <br />
              keeps you moving.
            </>
          }
          items={branchFeatures}
        />

        <section className="mx-auto max-w-6xl px-5 pb-24">
          <div className="feat-cta overflow-hidden rounded-[2rem] bg-ink p-8 text-white md:flex md:items-center md:justify-between md:gap-8 md:p-10">
            <div>
              <p
                className="font-[family-name:var(--font-brush)] text-3xl text-paint-soft"
                style={{ fontWeight: 700 }}
              >
                Ready to try it?
              </p>
              <p className="mt-2 max-w-md text-white/65">
                Create one account. Find work or hire — on web and mobile.
              </p>
            </div>
            <div className="mt-6 md:mt-0">
              <Link to="/signup">
                <MagneticButton>Get Started</MagneticButton>
              </Link>
            </div>
          </div>
        </section>
      </div>
    </SiteShell>
  )
}

import { useRef } from 'react'
import { Link } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { MagneticButton } from '../components/MagneticButton'
import { PhoneMockup } from '../components/PhoneMockup'
import { SiteShell } from '../components/SiteShell'
import { BranchTimeline } from '../components/BranchTimeline'

gsap.registerPlugin(useGSAP, ScrollTrigger)

const marquee = [
  'FIND WORK',
  'GET PAID',
  'KEEP MOVING',
  'GABORONE',
  'HIRE FAST',
  'BOTSWANA',
]

const branchItems = [
  {
    n: '01',
    label: 'Feature',
    title: 'Instant Connections',
    body: 'Match with real work near you — no endless scrolling.',
    to: '/features',
  },
  {
    n: '02',
    label: 'Feature',
    title: 'No Hassle',
    body: 'Verified people. Clear rates. Chat and get moving.',
    to: '/features',
  },
  {
    n: '03',
    label: 'Feature',
    title: 'Post in Minutes',
    body: 'Employers go live fast. Workers apply with one tap.',
    to: '/features',
  },
  {
    n: '04',
    label: 'Features',
    title: 'See what Jobsy can do',
    body: 'Connections, chat, Web Jobs, and dual roles — all in one account.',
    to: '/features',
  },
  {
    n: '05',
    label: 'How it works',
    title: 'Four steps. Zero fuss.',
    body: 'Sign up, match, hire or apply, then chat and complete.',
    to: '/how-it-works',
  },
  {
    n: '06',
    label: 'Botswana',
    title: 'Built for our people',
    body: 'Local-first across Gaborone, Francistown, Maun, and beyond.',
    to: '/how-it-works#botswana',
  },
]

export function LandingPage() {
  const root = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      const rootEl = root.current
      if (!rootEl) return

      const track = rootEl.querySelector('.marquee-track') as HTMLElement | null
      if (track && !reduce) {
        const half = track.scrollWidth / 2
        gsap.set(track, { x: 0 })
        gsap.to(track, { x: -half, duration: 28, ease: 'none', repeat: -1 })
      }

      if (reduce) return

      const intro = gsap.timeline({ defaults: { ease: 'power3.out' } })
      intro
        .from('.hero-kicker', { y: 28, opacity: 0, duration: 0.7 })
        .from('.hero-line', { yPercent: 110, duration: 1, stagger: 0.12 }, '-=0.45')
        .from('.hero-brush', { y: 36, opacity: 0, duration: 0.7 }, '-=0.55')
        .from('.hero-copy', { y: 24, opacity: 0, duration: 0.6 }, '-=0.4')
        .from('.hero-cta', { y: 20, opacity: 0, duration: 0.5, stagger: 0.08 }, '-=0.35')
        .from('.hero-visual', { x: 60, opacity: 0, duration: 1 }, '-=0.9')

      gsap.to('.hero-visual', {
        yPercent: -8,
        ease: 'none',
        scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: 1 },
      })

      gsap.from('.home-cta', {
        y: 28,
        duration: 0.85,
        ease: 'power3.out',
        immediateRender: false,
        scrollTrigger: {
          trigger: '.home-cta',
          start: 'top 92%',
          once: true,
        },
      })
    },
    { scope: root },
  )

  const marqueeItems = [...marquee, ...marquee]

  return (
    <SiteShell>
      <div ref={root}>
        <section className="hero relative min-h-[100svh] pt-16">
          <div className="relative mx-auto grid max-w-6xl gap-12 px-5 pb-16 pt-12 md:grid-cols-[1.05fr_0.95fr] md:items-center md:pt-20">
            <div className="relative z-10 max-w-xl">
              <p className="hero-kicker mb-5 text-[0.95rem] font-medium text-mute">
                Real work. Real people.{' '}
                <span className="brush-underline font-semibold text-paint">Real fast.</span>
              </p>

              <h1 className="font-[family-name:var(--font-display)] text-[clamp(2.75rem,8vw,5.4rem)] leading-[0.92] tracking-[-0.04em] text-ink">
                <span className="block overflow-hidden">
                  <span className="hero-line inline-block" style={{ fontWeight: 800 }}>
                    FIND WORK.
                  </span>
                </span>
                <span className="block overflow-hidden">
                  <span className="hero-line inline-block" style={{ fontWeight: 800 }}>
                    GET PAID.
                  </span>
                </span>
              </h1>

              <p
                className="hero-brush mt-3 font-[family-name:var(--font-brush)] text-[clamp(2.4rem,6vw,3.6rem)] leading-none text-paint"
                style={{ fontWeight: 700 }}
              >
                KEEP MOVING.
                <span className="mt-1 block h-2 w-48 origin-left rounded-full bg-paint/90 md:w-64" />
              </p>

              <p className="hero-copy mt-6 max-w-md text-[1.05rem] leading-relaxed text-mute">
                Jobsy connects you with real opportunities in your area — fast and easy.
              </p>

              <div className="hero-cta mt-8 flex flex-wrap items-center gap-3">
                <Link to="/signup">
                  <MagneticButton>Get Started</MagneticButton>
                </Link>
                <Link to="/how-it-works">
                  <MagneticButton variant="ghost">How it works</MagneticButton>
                </Link>
              </div>
            </div>

            <div className="hero-visual relative z-10 mx-auto w-full max-w-sm md:max-w-md">
              <PhoneMockup className="relative z-10" />
            </div>
          </div>
        </section>

        <section className="marquee-section relative overflow-hidden border-y border-ink/8 py-8">
          <div className="marquee-track flex w-max gap-10 whitespace-nowrap px-6 will-change-transform">
            {marqueeItems.map((word, i) => (
              <span
                key={`${word}-${i}`}
                className="font-[family-name:var(--font-display)] text-[clamp(2.5rem,6vw,4.5rem)] tracking-tight text-ink/90"
                style={{ fontWeight: 800 }}
              >
                {word}
                <span className="mx-6 inline-block text-paint">/</span>
              </span>
            ))}
          </div>
        </section>

        <BranchTimeline
          eyebrow="Explore Jobsy"
          heading={
            <>
              Built for speed.
              <br />
              Made for Botswana.
            </>
          }
          items={branchItems}
        />

        <section className="mx-auto max-w-6xl px-5 pb-24">
          <div className="home-cta overflow-hidden rounded-[2rem] bg-ink p-8 text-white md:flex md:items-center md:justify-between md:gap-8 md:p-10">
            <div>
              <p
                className="font-[family-name:var(--font-brush)] text-3xl text-paint-soft"
                style={{ fontWeight: 700 }}
              >
                Ready to keep moving?
              </p>
              <p className="mt-2 max-w-md text-white/65">
                Same Jobsy account on web and mobile. Find work or hire nearby.
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

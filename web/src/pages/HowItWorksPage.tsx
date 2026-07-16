import { useEffect, useRef } from 'react'
import { Link, useLocation } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { ScrollTrigger } from 'gsap/ScrollTrigger'
import { MagneticButton } from '../components/MagneticButton'
import { SiteShell } from '../components/SiteShell'
import { BranchTimeline } from '../components/BranchTimeline'

gsap.registerPlugin(useGSAP, ScrollTrigger)

const steps = [
  {
    n: '01',
    label: 'Start',
    title: 'Create your profile',
    body: 'Sign up once. Choose worker or employer — switch anytime when your profile is ready.',
    to: '/signup',
  },
  {
    n: '02',
    label: 'Discover',
    title: 'Find matches nearby',
    body: 'Browse local jobs or post one. Filters, skills, and location help you move faster.',
    to: '/signup',
  },
  {
    n: '03',
    label: 'Act',
    title: 'Apply or hire',
    body: 'Workers apply with a short note. Employers review applications and accept the right person.',
    to: '/signup',
  },
  {
    n: '04',
    label: 'Finish',
    title: 'Chat, complete, rate',
    body: 'Message in-app, finish the job, and leave a rating so the next hire is even easier.',
    to: '/signup',
  },
]

const cities = [
  'Gaborone',
  'Francistown',
  'Maun',
  'Serowe',
  'Palapye',
  'Lobatse',
  'Kasane',
  'Jwaneng',
]

const sectors = [
  'Construction',
  'Cleaning',
  'Driving',
  'Retail',
  'Hospitality',
  'Security',
  'Tech',
  'Healthcare',
]

export function HowItWorksPage() {
  const root = useRef<HTMLDivElement>(null)
  const location = useLocation()

  useEffect(() => {
    if (location.hash !== '#botswana') return
    const t = window.setTimeout(() => {
      document.getElementById('botswana')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }, 80)
    return () => window.clearTimeout(t)
  }, [location.hash])

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      if (reduce) return

      const intro = gsap.timeline({ defaults: { ease: 'power3.out' } })
      intro
        .from('.how-kicker', { y: 24, opacity: 0, duration: 0.6 })
        .from('.how-line', { yPercent: 110, duration: 0.95, stagger: 0.1 }, '-=0.35')
        .from('.how-sub', { y: 20, opacity: 0, duration: 0.55 }, '-=0.45')

      // Lusion pinned story scrub
      const pinTl = gsap.timeline({
        scrollTrigger: {
          trigger: '.pin-story',
          start: 'top top',
          end: '+=160%',
          pin: true,
          scrub: 1,
          anticipatePin: 1,
          invalidateOnRefresh: true,
        },
      })
      pinTl
        .fromTo(
          '.pin-word',
          { yPercent: 120, opacity: 0 },
          { yPercent: 0, opacity: 1, stagger: 0.18, ease: 'none' },
        )
        .fromTo('.pin-sub', { opacity: 0, y: 36 }, { opacity: 1, y: 0, ease: 'none' }, '-=0.15')
        .fromTo(
          '.pin-panel',
          { xPercent: 36, opacity: 0 },
          { xPercent: 0, opacity: 1, ease: 'none' },
          '-=0.3',
        )

      requestAnimationFrame(() => {
        requestAnimationFrame(() => ScrollTrigger.refresh())
      })

      // Botswana section — Lusion scale-in + chip stagger
      gsap.fromTo(
        '.bw-panel',
        { scale: 0.92, borderRadius: '2.75rem' },
        {
          scale: 1,
          borderRadius: '1.75rem',
          ease: 'none',
          scrollTrigger: {
            trigger: '.bw-section',
            start: 'top 80%',
            end: 'top 45%',
            scrub: true,
          },
        },
      )

      gsap.from('.bw-chip', {
        y: 28,
        opacity: 0,
        stagger: 0.04,
        duration: 0.5,
        ease: 'power2.out',
        immediateRender: false,
        scrollTrigger: { trigger: '.bw-chips', start: 'top 88%', once: true },
      })

      gsap.from('.how-cta', {
        y: 32,
        duration: 0.8,
        ease: 'power3.out',
        immediateRender: false,
        scrollTrigger: { trigger: '.how-cta', start: 'top 90%', once: true },
      })
    },
    { scope: root },
  )

  return (
    <SiteShell showPaint={false}>
      <div ref={root} className="bg-paper">
        <section className="mx-auto max-w-6xl px-5 pt-28 pb-16 md:pt-32">
          <p
            className="how-kicker font-[family-name:var(--font-brush)] text-3xl text-paint"
            style={{ fontWeight: 700 }}
          >
            How it works
          </p>
          <h1 className="mt-2 font-[family-name:var(--font-display)] text-[clamp(2.6rem,7vw,5rem)] leading-[0.92] tracking-[-0.04em] text-ink">
            <span className="block overflow-hidden">
              <span className="how-line inline-block" style={{ fontWeight: 800 }}>
                From signup
              </span>
            </span>
            <span className="block overflow-hidden">
              <span className="how-line inline-block" style={{ fontWeight: 800 }}>
                to payday —
              </span>
            </span>
            <span className="block overflow-hidden">
              <span className="how-line inline-block text-paint" style={{ fontWeight: 800 }}>
                without the hassle.
              </span>
            </span>
          </h1>
          <p className="how-sub mt-6 max-w-lg text-lg text-mute">
            Four simple steps. Same account on web and mobile. Built for Botswana.
          </p>
        </section>

        <section className="pin-story relative h-screen overflow-hidden bg-ink text-white">
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_20%_20%,rgba(30,79,215,0.35),transparent_50%)]" />
          <div className="relative mx-auto flex h-full max-w-6xl flex-col justify-center gap-10 px-5 py-16 md:flex-row md:items-center md:justify-between">
            <div className="max-w-xl">
              <div className="overflow-hidden">
                <p
                  className="pin-word font-[family-name:var(--font-display)] text-[clamp(2.8rem,7vw,5rem)] leading-[0.95] tracking-tight"
                  style={{ fontWeight: 800 }}
                >
                  Your next
                </p>
              </div>
              <div className="overflow-hidden">
                <p
                  className="pin-word font-[family-name:var(--font-display)] text-[clamp(2.8rem,7vw,5rem)] leading-[0.95] tracking-tight text-paint-soft"
                  style={{ fontWeight: 800 }}
                >
                  opportunity
                </p>
              </div>
              <div className="overflow-hidden">
                <p
                  className="pin-word font-[family-name:var(--font-display)] text-[clamp(2.8rem,7vw,5rem)] leading-[0.95] tracking-tight"
                  style={{ fontWeight: 800 }}
                >
                  is closer than you think.
                </p>
              </div>
              <p className="pin-sub mt-6 max-w-md text-lg text-white/60">
                Browse local gigs, apply in seconds, chat with employers, and get paid.
              </p>
            </div>

            <div className="pin-panel w-full max-w-sm rounded-[1.75rem] border border-white/10 bg-white/5 p-7 backdrop-blur-md">
              <ol className="space-y-5">
                {steps.map((step) => (
                  <li key={step.n} className="flex gap-4">
                    <span
                      className="font-[family-name:var(--font-brush)] text-3xl text-paint-soft"
                      style={{ fontWeight: 700 }}
                    >
                      {step.n}
                    </span>
                    <span className="pt-1.5 font-medium text-white/85">{step.title}</span>
                  </li>
                ))}
              </ol>
              <Link to="/signup" className="mt-8 inline-block">
                <MagneticButton>Get Started</MagneticButton>
              </Link>
            </div>
          </div>
        </section>

        <BranchTimeline
          eyebrow="The path"
          heading={
            <>
              Four steps.
              <br />
              Zero fuss.
            </>
          }
          items={steps}
        />

        {/* Botswana content (former /botswana page) */}
        <section id="botswana" className="bw-section mx-auto max-w-6xl px-5 py-20 md:py-28">
          <p className="text-xs font-bold tracking-[0.28em] text-mute uppercase">Proudly Botswana</p>
          <h2
            className="mt-3 max-w-3xl font-[family-name:var(--font-display)] text-4xl tracking-tight text-ink md:text-5xl"
            style={{ fontWeight: 800 }}
          >
            Powered by our people.
            <br />
            <span className="text-paint">For our communities.</span>
          </h2>
          <p className="mt-5 max-w-xl text-lg text-mute">
            Jobsy is built for workers and employers across Botswana — real work, real people, real
            fast.
          </p>

          <div className="bw-panel mt-12 overflow-hidden border border-ink/10 bg-white/70 p-8 backdrop-blur-md md:flex md:items-center md:justify-between md:gap-10 md:p-12">
            <div>
              <h3
                className="font-[family-name:var(--font-display)] text-3xl tracking-tight text-ink md:text-4xl"
                style={{ fontWeight: 800 }}
              >
                Local first. Everywhere that matters.
              </h3>
              <p className="mt-4 max-w-xl text-mute">
                From Gaborone to Maun — construction, cleaning, driving, retail, tech, and everything
                in between.
              </p>
            </div>
            <div className="mt-8 flex shrink-0 items-center gap-3 md:mt-0">
              <span className="grid size-14 place-items-center rounded-2xl bg-paint text-white">
                <svg viewBox="0 0 24 24" className="size-6" fill="currentColor" aria-hidden>
                  <path d="M12 2C8.1 2 5 5.1 5 9c0 5.2 7 13 7 13s7-7.8 7-13c0-3.9-3.1-7-7-7zm0 9.5A2.5 2.5 0 1 1 12 6a2.5 2.5 0 0 1 0 5.5z" />
                </svg>
              </span>
              <div>
                <p className="font-bold text-ink">Local first</p>
                <p className="text-sm text-mute">Gaborone & beyond</p>
              </div>
            </div>
          </div>

          <div className="bw-chips mt-12">
            <h3 className="mb-4 text-sm font-bold tracking-[0.2em] text-mute uppercase">Cities</h3>
            <div className="mb-10 flex flex-wrap gap-2">
              {cities.map((c) => (
                <span
                  key={c}
                  className="bw-chip rounded-full border border-ink/10 bg-white/70 px-4 py-2 text-sm font-semibold text-ink"
                >
                  {c}
                </span>
              ))}
            </div>
            <h3 className="mb-4 text-sm font-bold tracking-[0.2em] text-mute uppercase">Sectors</h3>
            <div className="flex flex-wrap gap-2">
              {sectors.map((s) => (
                <span
                  key={s}
                  className="bw-chip rounded-full bg-paint/10 px-4 py-2 text-sm font-semibold text-paint-deep"
                >
                  {s}
                </span>
              ))}
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-5 pb-24">
          <div className="how-cta overflow-hidden rounded-[2rem] bg-ink p-8 text-white md:flex md:items-center md:justify-between md:gap-8 md:p-10">
            <div>
              <p
                className="font-[family-name:var(--font-brush)] text-3xl text-paint-soft"
                style={{ fontWeight: 700 }}
              >
                Ready to keep moving?
              </p>
              <p className="mt-2 max-w-md text-white/65">
                Join Jobsy and find work — or hire — near you today.
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

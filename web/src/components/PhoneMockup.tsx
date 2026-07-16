import { useRef } from 'react'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'

gsap.registerPlugin(useGSAP)

const JOBS = [
  {
    employer: 'Thabo M.',
    ago: '2h ago',
    category: 'Construction',
    match: 'Strong match · 92%',
    title: 'Site Helper — Phase 2 Build',
    desc: 'Assist with material handling and site cleanup. Transport provided from CBD.',
    location: 'Gaborone',
    pay: 'P180 / day',
  },
  {
    employer: 'Kelebogile R.',
    ago: '5h ago',
    category: 'Cleaning',
    match: 'Good match · 78%',
    title: 'Office Deep Clean — Weekend',
    desc: 'Two-day clean for a small office park. Bring your own gear if you have it.',
    location: 'Phakalane',
    pay: 'P1,200',
  },
  {
    employer: 'Delta Logistics',
    ago: '1d ago',
    category: 'Driving',
    match: 'Nearby · 85%',
    title: 'Delivery Driver — Same Day',
    desc: 'Light van runs around greater Gaborone. Valid licence required.',
    location: 'Broadhurst',
    pay: 'P250 / day',
  },
]

/** Phone frame that cycles real Jobsy app screens (Welcome → Find Jobs). */
export function PhoneMockup({ className = '' }: { className?: string }) {
  const root = useRef<HTMLDivElement>(null)
  const labelRef = useRef<HTMLSpanElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches

      gsap.to('.phone-float', {
        y: -12,
        rotate: -1.2,
        duration: 3.4,
        ease: 'sine.inOut',
        yoyo: true,
        repeat: -1,
      })

      if (reduce) {
        gsap.set('.screen-jobs', { autoAlpha: 0 })
        gsap.set('.screen-welcome', { autoAlpha: 1 })
        return
      }

      gsap.to('.phone-orbit', {
        rotate: 360,
        duration: 32,
        ease: 'none',
        repeat: -1,
      })

      gsap.set('.screen-jobs', { autoAlpha: 0 })
      gsap.set('.screen-welcome', { autoAlpha: 1 })

      const setLabel = (text: string) => {
        if (labelRef.current) labelRef.current.textContent = text
      }

      const cycle = gsap.timeline({ repeat: -1 })
      cycle
        .call(() => setLabel('Welcome'))
        .fromTo(
          '.screen-welcome',
          { autoAlpha: 0, y: 10 },
          { autoAlpha: 1, y: 0, duration: 0.55, ease: 'power2.out' },
        )
        .to({}, { duration: 3.4 })
        .to('.screen-welcome', { autoAlpha: 0, y: -8, duration: 0.4, ease: 'power2.in' })
        .call(() => setLabel('Find Jobs'))
        .fromTo(
          '.screen-jobs',
          { autoAlpha: 0, y: 12 },
          { autoAlpha: 1, y: 0, duration: 0.55, ease: 'power2.out' },
        )
        .from(
          '.job-card-mock',
          { y: 16, opacity: 0, stagger: 0.1, duration: 0.4, ease: 'power2.out' },
          '-=0.25',
        )
        .to({}, { duration: 4.4 })
        .to('.screen-jobs', { autoAlpha: 0, y: -8, duration: 0.4, ease: 'power2.in' })
    },
    { scope: root },
  )

  return (
    <div ref={root} className={`relative ${className}`}>
      <div className="phone-orbit pointer-events-none absolute inset-[-12%] rounded-full border border-paint/15" />
      <div className="pointer-events-none absolute inset-[8%] rounded-full border border-dashed border-paint/20" />

      <div className="phone-float relative mx-auto w-[min(100%,290px)]">
        <div className="absolute -inset-8 -z-10 rounded-[40%] bg-paint/20 blur-3xl" />
        <div
          className="relative overflow-hidden rounded-[2.25rem] border-[5px] border-[#0a0a0a] bg-[#020204] shadow-[0_40px_80px_-28px_rgba(10,10,10,0.7)]"
          style={{ aspectRatio: '9 / 19.2' }}
        >
          <div className="absolute inset-x-[30%] top-2.5 z-30 h-[18px] rounded-full bg-black" />

          <div className="absolute inset-x-0 top-0 z-20 flex items-center justify-between px-5 pt-3 text-[9px] font-semibold text-[#fafafa]/80">
            <span>9:41</span>
            <span className="inline-block h-1.5 w-3 rounded-[1px] border border-white/70">
              <span className="ml-px mt-px block h-0.5 w-1.5 rounded-[0.5px] bg-white/80" />
            </span>
          </div>

          <div className="screen-welcome absolute inset-0 z-10 pt-8">
            <WelcomeScreenMock />
          </div>
          <div className="screen-jobs absolute inset-0 z-10 pt-8">
            <FindJobsScreenMock />
          </div>
        </div>
      </div>

      <div className="pointer-events-none absolute -left-3 top-[22%] rounded-2xl border border-ink/8 bg-white/95 px-3 py-2 text-xs font-semibold text-ink shadow-lg backdrop-blur">
        <span className="text-paint">●</span> Live from the app
      </div>
      <div className="pointer-events-none absolute -right-1 bottom-[28%] rounded-2xl border border-ink/8 bg-white/95 px-3 py-2 text-xs font-semibold text-ink shadow-lg backdrop-blur">
        <span ref={labelRef}>Welcome</span>
      </div>
    </div>
  )
}

/** Mirrors Flutter `WelcomeScreen` */
function WelcomeScreenMock() {
  return (
    <div className="flex h-full flex-col px-5 pb-5 text-center" style={{ background: '#020204' }}>
      <div className="flex flex-1 flex-col items-center justify-center">
        <div
          className="mb-4 grid size-[72px] place-items-center overflow-hidden rounded-full shadow-[0_0_40px_rgba(136,153,170,0.18)]"
          style={{
            background: 'linear-gradient(145deg, #e2e8f0 0%, #94a3b8 45%, #1a1a2e 100%)',
          }}
        >
          <div className="grid size-[64px] place-items-center rounded-full bg-[#0a0a0a]">
            <span
              className="font-[family-name:var(--font-display)] text-[28px] leading-none text-white"
              style={{ fontWeight: 800 }}
            >
              J
            </span>
          </div>
        </div>

        <h1
          className="bg-gradient-to-r from-[#e2e8f0] via-[#94a3b8] to-[#e2e8f0] bg-clip-text font-[family-name:var(--font-display)] text-[28px] tracking-[-1px] text-transparent"
          style={{ fontWeight: 800 }}
        >
          Jobsy
        </h1>
        <p className="mt-1.5 max-w-[200px] text-[11px] leading-snug tracking-wide text-[#a1a1aa]">
          Find work or hire workers near you
        </p>
      </div>

      <div className="pb-1">
        <p className="mb-4 text-[11px] leading-snug text-[#a1a1aa]">
          One account. Hire or find work anytime.
        </p>

        <div
          className="mb-2.5 flex h-[42px] w-full items-center justify-center rounded-[14px] text-[13px] font-bold text-white"
          style={{
            background: 'linear-gradient(135deg, #53789E 0%, #0F3460 50%, #1A1A2E 100%)',
          }}
        >
          Get Started
        </div>

        <div className="flex h-[42px] w-full items-center justify-center rounded-[14px] border border-[#3f3f46]/80 text-[13px] font-bold text-[#fafafa]">
          Sign In
        </div>

        <p className="mt-4 text-[9px] text-[#71717a]">Built by Futurify Designs</p>
      </div>
    </div>
  )
}

/** Mirrors worker Find Jobs browse + bottom nav */
function FindJobsScreenMock() {
  return (
    <div className="flex h-full flex-col" style={{ background: '#020204' }}>
      <div className="px-3.5 pb-2 pt-1">
        <div className="mb-2 flex items-center justify-between">
          <div>
            <p className="text-[9px] text-[#71717a]">Good afternoon</p>
            <p className="text-[13px] font-bold text-[#fafafa]">Find Jobs</p>
          </div>
          <div className="flex size-7 items-center justify-center rounded-full bg-[#14141c] text-[10px] text-[#cbd5e1]">
            ●
          </div>
        </div>
        <div className="flex h-8 items-center rounded-xl border border-[#27272a] bg-[#0e0e14] px-2.5 text-[10px] text-[#71717a]">
          Search jobs, skills, location…
        </div>
        <div className="mt-2 flex gap-1.5 overflow-hidden">
          {['All', 'Construction', 'Driving', 'Cleaning'].map((c, i) => (
            <span
              key={c}
              className={`shrink-0 rounded-full px-2 py-0.5 text-[8px] font-bold ${
                i === 0
                  ? 'bg-[#cbd5e1] text-[#0a0a0a]'
                  : 'border border-[#27272a] text-[#a1a1aa]'
              }`}
            >
              {c}
            </span>
          ))}
        </div>
      </div>

      <div className="flex-1 space-y-2 overflow-hidden px-3 pb-1">
        {JOBS.map((job) => (
          <div
            key={job.title}
            className="job-card-mock rounded-2xl border border-[#27272a]/80 bg-[#08080c] p-2.5"
          >
            <div className="mb-1.5 flex items-center gap-2">
              <div className="grid size-7 shrink-0 place-items-center rounded-full bg-[#14141c] text-[10px] text-[#cbd5e1]">
                {job.employer.charAt(0)}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[9px] font-semibold text-[#fafafa]">{job.employer}</p>
                <p className="text-[8px] text-[#71717a]">{job.ago}</p>
              </div>
              <span className="shrink-0 rounded-full border border-[#cbd5e1]/30 bg-[#cbd5e1]/10 px-1.5 py-0.5 text-[7px] font-bold text-[#cbd5e1]">
                {job.category}
              </span>
            </div>
            <span className="mb-1 inline-block rounded-md border border-[#cbd5e1]/30 bg-[#cbd5e1]/10 px-1.5 py-0.5 text-[7px] font-bold text-[#cbd5e1]">
              {job.match}
            </span>
            <p className="text-[11px] font-bold leading-snug tracking-tight text-[#fafafa]">
              {job.title}
            </p>
            <p className="mt-0.5 line-clamp-2 text-[8px] leading-snug text-[#a1a1aa]">{job.desc}</p>
            <div className="mt-1.5 flex items-center justify-between">
              <p className="text-[8px] text-[#71717a]">Job site: {job.location}</p>
              <p className="text-[9px] font-bold text-[#cbd5e1]">{job.pay}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="border-t border-[#18181b] bg-[#040406] px-1 pb-2 pt-1.5">
        <div className="grid grid-cols-5 gap-0.5 text-center text-[7px]">
          {[
            { label: 'Find Jobs', active: true },
            { label: 'My Jobs', active: false },
            { label: 'Wallet', active: false },
            { label: 'Messages', active: false },
            { label: 'Profile', active: false },
          ].map((tab) => (
            <div
              key={tab.label}
              className={tab.active ? 'font-bold text-[#cbd5e1]' : 'text-[#71717a]'}
            >
              <div
                className={`mx-auto mb-0.5 h-1 w-1 rounded-full ${
                  tab.active ? 'bg-[#cbd5e1]' : 'bg-transparent'
                }`}
              />
              {tab.label}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

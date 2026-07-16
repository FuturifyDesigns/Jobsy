import { useRef, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { ScrollTrigger } from 'gsap/ScrollTrigger'

gsap.registerPlugin(useGSAP, ScrollTrigger)

export type BranchItem = {
  n: string
  label?: string
  title: string
  body: string
  to: string
}

/**
 * Branch.co-style reveal:
 * trunk + each card scrub with scroll — open on the way down, close on the way up.
 */
export function BranchTimeline({
  items,
  eyebrow,
  heading,
}: {
  items: BranchItem[]
  eyebrow: string
  heading: ReactNode
}) {
  const root = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      const el = root.current
      if (!el) return

      const steps = gsap.utils.toArray<HTMLElement>(el.querySelectorAll('.branch-step'))
      const fill = el.querySelector('.trunk-fill') as HTMLElement | null
      const track = el.querySelector('.branch-track')

      if (reduce) {
        gsap.set(el.querySelectorAll('.branch-card'), { clearProps: 'all', opacity: 1, x: 0, y: 0 })
        gsap.set(el.querySelectorAll('.branch-arm'), { scaleX: 1 })
        gsap.set(el.querySelectorAll('.branch-dot'), { scale: 1, opacity: 1 })
        if (fill) gsap.set(fill, { scaleY: 1 })
        return
      }

      // Closed state first
      steps.forEach((step) => {
        const side = step.dataset.side === 'left' ? -1 : 1
        const card = step.querySelector('.branch-card')
        const arms = step.querySelectorAll('.branch-arm')
        const dot = step.querySelector('.branch-dot')
        gsap.set(card, { opacity: 0, x: side * 48, y: 24 })
        arms.forEach((arm) => {
          const mobile = arm.classList.contains('md:hidden')
          gsap.set(arm, {
            scaleX: 0,
            transformOrigin: mobile
              ? 'left center'
              : side === -1
                ? 'right center'
                : 'left center',
          })
        })
        gsap.set(dot, { scale: 0.35, opacity: 0.35 })
      })
      if (fill) gsap.set(fill, { scaleY: 0, transformOrigin: 'top center' })

      const triggers: ScrollTrigger[] = []

      const build = () => {
        triggers.forEach((t) => t.kill())
        triggers.length = 0

        if (fill && track) {
          const trunkTween = gsap.fromTo(
            fill,
            { scaleY: 0 },
            {
              scaleY: 1,
              ease: 'none',
              scrollTrigger: {
                trigger: track,
                start: 'top 70%',
                end: 'bottom 35%',
                scrub: 0.45,
                invalidateOnRefresh: true,
              },
            },
          )
          if (trunkTween.scrollTrigger) triggers.push(trunkTween.scrollTrigger)
        }

        steps.forEach((step) => {
          const side = step.dataset.side === 'left' ? -1 : 1
          const card = step.querySelector('.branch-card')
          const arms = step.querySelectorAll('.branch-arm')
          const dot = step.querySelector('.branch-dot')

          // Same scrub range feel as trunk — reverses when scrolling up
          const tl = gsap.timeline({
            scrollTrigger: {
              trigger: step,
              start: 'top 82%',
              end: 'top 48%',
              scrub: 0.55,
              invalidateOnRefresh: true,
            },
          })

          tl.fromTo(
            dot,
            { scale: 0.35, opacity: 0.35 },
            { scale: 1, opacity: 1, ease: 'none', duration: 0.25 },
            0,
          )
            .fromTo(arms, { scaleX: 0 }, { scaleX: 1, ease: 'none', duration: 0.4 }, 0.05)
            .fromTo(
              card,
              { opacity: 0, x: side * 48, y: 24 },
              { opacity: 1, x: 0, y: 0, ease: 'none', duration: 0.5 },
              0.15,
            )

          if (tl.scrollTrigger) triggers.push(tl.scrollTrigger)
        })
      }

      // Wait for parent pin spacers (Features / How it works), then build + refresh
      const t1 = window.setTimeout(() => {
        ScrollTrigger.refresh()
        build()
        ScrollTrigger.refresh()
      }, 80)

      const t2 = window.setTimeout(() => ScrollTrigger.refresh(), 320)

      return () => {
        window.clearTimeout(t1)
        window.clearTimeout(t2)
        triggers.forEach((t) => t.kill())
      }
    },
    { scope: root, dependencies: [items.length], revertOnUpdate: true },
  )

  return (
    <section ref={root} className="branch-section relative py-24 md:py-28">
      <div className="mx-auto max-w-6xl px-5">
        <div className="mb-16 max-w-2xl md:mx-auto md:text-center">
          <p
            className="font-[family-name:var(--font-brush)] text-3xl text-paint"
            style={{ fontWeight: 700 }}
          >
            {eyebrow}
          </p>
          <h2
            className="mt-1 font-[family-name:var(--font-display)] text-4xl tracking-tight text-ink md:text-5xl"
            style={{ fontWeight: 800 }}
          >
            {heading}
          </h2>
        </div>

        <div className="branch-track relative mx-auto max-w-4xl">
          <div
            className="pointer-events-none absolute top-0 bottom-0 left-6 w-[3px] md:left-1/2 md:-ml-[1.5px]"
            aria-hidden
          >
            <div className="absolute inset-0 rounded-full bg-paint/15" />
            <div className="trunk-fill absolute inset-x-0 top-0 h-full origin-top rounded-full bg-paint" />
          </div>

          <div className="space-y-10 md:space-y-16">
            {items.map((item, i) => {
              const left = i % 2 === 0
              return (
                <div
                  key={item.n}
                  className="branch-step relative"
                  data-side={left ? 'left' : 'right'}
                >
                  <div className="grid items-center gap-4 md:grid-cols-2 md:gap-0">
                    <div
                      className={`relative pl-14 md:pl-0 ${
                        left ? 'md:pr-14 md:text-right' : 'md:order-2 md:pl-14'
                      }`}
                    >
                      <div
                        className={`branch-arm pointer-events-none absolute top-1/2 hidden h-[2px] w-12 bg-paint md:block ${
                          left ? 'right-0 origin-right' : 'left-0 origin-left'
                        }`}
                        aria-hidden
                      />

                      <Link
                        to={item.to}
                        className="branch-card group inline-block w-full rounded-[1.5rem] border border-ink/8 bg-white/80 p-6 text-left shadow-[0_20px_50px_-36px_rgba(30,79,215,0.35)] backdrop-blur-sm transition hover:border-paint/40 md:p-7"
                      >
                        <div
                          className={`flex flex-wrap items-baseline gap-2 ${
                            left ? 'md:justify-end' : ''
                          }`}
                        >
                          <span
                            className="font-[family-name:var(--font-brush)] text-2xl text-paint"
                            style={{ fontWeight: 700 }}
                          >
                            {item.n}
                          </span>
                          {item.label && (
                            <span className="text-[10px] font-bold tracking-[0.2em] text-paint uppercase">
                              {item.label}
                            </span>
                          )}
                        </div>
                        <h3
                          className="mt-1 font-[family-name:var(--font-display)] text-xl tracking-tight text-ink md:text-2xl"
                          style={{ fontWeight: 800 }}
                        >
                          {item.title}
                        </h3>
                        <p className="mt-2 text-sm leading-relaxed text-mute">{item.body}</p>
                        <span className="mt-4 inline-flex text-sm font-semibold text-paint transition group-hover:translate-x-0.5">
                          Open →
                        </span>
                      </Link>
                    </div>

                    <div className={`hidden md:block ${left ? '' : 'md:order-1'}`} />
                  </div>

                  <div
                    className="branch-dot absolute top-1/2 left-6 z-10 flex size-4 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-paint shadow-[0_0_0_6px_rgba(30,79,215,0.18)] md:left-1/2"
                    aria-hidden
                  >
                    <span className="size-1.5 rounded-full bg-white" />
                  </div>

                  <div
                    className="branch-arm pointer-events-none absolute top-1/2 left-6 h-[2px] w-8 origin-left -translate-y-1/2 bg-paint md:hidden"
                    aria-hidden
                  />
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </section>
  )
}

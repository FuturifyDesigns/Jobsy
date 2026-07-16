import { useRef, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { useGSAP } from '@gsap/react'
import gsap from 'gsap'

gsap.registerPlugin(useGSAP)

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode
  variant?: 'primary' | 'ghost' | 'dark'
}

/** Soft magnetic pull toward the cursor — Lusion-style micro-interaction. */
export function MagneticButton({
  children,
  variant = 'primary',
  className = '',
  ...rest
}: Props) {
  const root = useRef<HTMLButtonElement>(null)
  const inner = useRef<HTMLSpanElement>(null)

  useGSAP(
    () => {
      const el = root.current
      const label = inner.current
      if (!el || !label) return

      const onMove = (e: MouseEvent) => {
        const rect = el.getBoundingClientRect()
        const x = e.clientX - rect.left - rect.width / 2
        const y = e.clientY - rect.top - rect.height / 2
        gsap.to(el, { x: x * 0.28, y: y * 0.28, duration: 0.35, ease: 'power3.out' })
        gsap.to(label, { x: x * 0.12, y: y * 0.12, duration: 0.35, ease: 'power3.out' })
      }

      const onLeave = () => {
        gsap.to(el, { x: 0, y: 0, duration: 0.55, ease: 'elastic.out(1, 0.45)' })
        gsap.to(label, { x: 0, y: 0, duration: 0.55, ease: 'elastic.out(1, 0.45)' })
      }

      el.addEventListener('mousemove', onMove)
      el.addEventListener('mouseleave', onLeave)
      return () => {
        el.removeEventListener('mousemove', onMove)
        el.removeEventListener('mouseleave', onLeave)
      }
    },
    { scope: root },
  )

  const styles =
    variant === 'primary'
      ? 'bg-paint text-white shadow-[0_18px_40px_-18px_rgba(30,79,215,0.85)] hover:bg-paint-deep'
      : variant === 'dark'
        ? 'bg-ink text-white hover:bg-black'
        : 'border-2 border-ink/15 bg-transparent text-ink hover:border-ink/40'

  return (
    <button
      ref={root}
      className={`inline-flex cursor-pointer items-center justify-center rounded-full px-7 py-3.5 text-[0.95rem] font-semibold transition-colors will-change-transform ${styles} ${className}`}
      {...rest}
    >
      <span ref={inner} className="inline-flex items-center gap-2 will-change-transform">
        {children}
      </span>
    </button>
  )
}

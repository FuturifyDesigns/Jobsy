import { Link } from 'react-router-dom'

type LogoProps = {
  to?: string
  dark?: boolean
  className?: string
}

export function Logo({ to = '/', dark = false, className = '' }: LogoProps) {
  const mark = (
    <span className={`inline-flex items-center gap-2.5 ${className}`}>
      <span
        className={`grid size-9 place-items-center rounded-[10px] font-[family-name:var(--font-display)] text-lg font-800 ${
          dark ? 'bg-white text-ink' : 'bg-ink text-white'
        }`}
        style={{ fontWeight: 800 }}
      >
        J
      </span>
      <span
        className={`font-[family-name:var(--font-display)] text-[1.15rem] tracking-tight ${
          dark ? 'text-white' : 'text-ink'
        }`}
        style={{ fontWeight: 800 }}
      >
        JOBSY
      </span>
    </span>
  )

  if (!to) return mark
  return <Link to={to}>{mark}</Link>
}

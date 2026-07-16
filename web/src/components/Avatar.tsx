type AvatarProps = {
  url?: string | null
  name?: string | null
  size?: 'sm' | 'md' | 'lg' | 'xl'
  className?: string
  ring?: boolean
}

const sizes = {
  sm: 'h-9 w-9 text-xs',
  md: 'h-11 w-11 text-sm',
  lg: 'h-16 w-16 text-xl',
  xl: 'h-24 w-24 text-3xl',
} as const

export function Avatar({ url, name, size = 'md', className = '', ring = true }: AvatarProps) {
  const initial = (name?.trim()?.[0] || '?').toUpperCase()
  return (
    <div
      className={`relative shrink-0 overflow-hidden rounded-full bg-gradient-to-br from-paint to-paint-deep ${sizes[size]} ${
        ring ? 'ring-2 ring-white/25 ring-offset-2 ring-offset-[#050508]' : ''
      } ${className}`}
      aria-hidden={!url}
    >
      {url ? (
        <img src={url} alt="" className="h-full w-full object-cover" loading="lazy" />
      ) : (
        <span className="grid h-full w-full place-items-center font-bold text-white">{initial}</span>
      )}
    </div>
  )
}

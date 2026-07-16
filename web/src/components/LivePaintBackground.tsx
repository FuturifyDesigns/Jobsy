import { useEffect, useRef } from 'react'

type Blob = {
  x: number
  y: number
  r: number
  vx: number
  vy: number
  hue: number
  alpha: number
}

type Stroke = {
  points: { x: number; y: number }[]
  width: number
  alpha: number
  speed: number
  phase: number
  color: string
}

/**
 * Continuous paint-field background — soft blobs + drifting brush strokes.
 * Respects prefers-reduced-motion (static frame only).
 */
export function LivePaintBackground({ className = '' }: { className?: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d', { alpha: true })
    if (!ctx) return

    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    let raf = 0
    let w = 0
    let h = 0
    let dpr = 1

    const blobs: Blob[] = []
    const strokes: Stroke[] = []

    function resize() {
      dpr = Math.min(window.devicePixelRatio || 1, 2)
      w = window.innerWidth
      h = window.innerHeight
      canvas!.width = Math.floor(w * dpr)
      canvas!.height = Math.floor(h * dpr)
      canvas!.style.width = `${w}px`
      canvas!.style.height = `${h}px`
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0)
    }

    function seed() {
      blobs.length = 0
      strokes.length = 0
      const count = Math.max(5, Math.floor(w / 280))
      for (let i = 0; i < count; i++) {
        blobs.push({
          x: Math.random() * w,
          y: Math.random() * h,
          r: 90 + Math.random() * 180,
          vx: (Math.random() - 0.5) * 0.35,
          vy: (Math.random() - 0.5) * 0.28,
          hue: 215 + Math.random() * 18,
          alpha: 0.08 + Math.random() * 0.1,
        })
      }
      for (let i = 0; i < 4; i++) {
        const startX = Math.random() * w
        const startY = Math.random() * h
        const pts: { x: number; y: number }[] = []
        let x = startX
        let y = startY
        for (let p = 0; p < 8; p++) {
          x += 40 + Math.random() * 90
          y += (Math.random() - 0.5) * 70
          pts.push({ x, y })
        }
        strokes.push({
          points: pts,
          width: 18 + Math.random() * 42,
          alpha: 0.12 + Math.random() * 0.18,
          speed: 0.0004 + Math.random() * 0.0006,
          phase: Math.random() * Math.PI * 2,
          color: i % 2 === 0 ? '#1e4fd7' : '#4d7ef0',
        })
      }
    }

    function drawFrame(t: number) {
      ctx!.clearRect(0, 0, w, h)

      for (const b of blobs) {
        if (!reduce) {
          b.x += b.vx
          b.y += b.vy
          if (b.x < -b.r) b.x = w + b.r
          if (b.x > w + b.r) b.x = -b.r
          if (b.y < -b.r) b.y = h + b.r
          if (b.y > h + b.r) b.y = -b.r
        }
        const g = ctx!.createRadialGradient(b.x, b.y, 0, b.x, b.y, b.r)
        g.addColorStop(0, `hsla(${b.hue}, 78%, 48%, ${b.alpha})`)
        g.addColorStop(0.55, `hsla(${b.hue}, 72%, 45%, ${b.alpha * 0.45})`)
        g.addColorStop(1, `hsla(${b.hue}, 70%, 40%, 0)`)
        ctx!.fillStyle = g
        ctx!.beginPath()
        ctx!.arc(b.x, b.y, b.r, 0, Math.PI * 2)
        ctx!.fill()
      }

      for (const s of strokes) {
        const drift = reduce ? 0 : Math.sin(t * s.speed + s.phase) * 28
        const driftY = reduce ? 0 : Math.cos(t * s.speed * 0.8 + s.phase) * 18
        ctx!.save()
        ctx!.translate(drift, driftY)
        ctx!.lineCap = 'round'
        ctx!.lineJoin = 'round'
        ctx!.strokeStyle = s.color
        ctx!.globalAlpha = s.alpha
        ctx!.lineWidth = s.width
        ctx!.beginPath()
        s.points.forEach((p, i) => {
          if (i === 0) ctx!.moveTo(p.x, p.y)
          else ctx!.lineTo(p.x, p.y)
        })
        ctx!.stroke()
        ctx!.restore()
      }
    }

    resize()
    seed()
    drawFrame(0)

    const onResize = () => {
      resize()
      seed()
      drawFrame(performance.now())
    }
    window.addEventListener('resize', onResize)

    if (!reduce) {
      const loop = (t: number) => {
        drawFrame(t)
        raf = requestAnimationFrame(loop)
      }
      raf = requestAnimationFrame(loop)
    }

    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener('resize', onResize)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className={`pointer-events-none fixed inset-0 -z-10 h-full w-full ${className}`}
      aria-hidden
    />
  )
}

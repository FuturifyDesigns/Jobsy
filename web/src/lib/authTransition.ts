import gsap from 'gsap'

const OVERLAY_ID = 'jobsy-auth-transition'
const ENTER_FLAG = 'jobsy_auth_enter'

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function ensureOverlay() {
  let overlay = document.getElementById(OVERLAY_ID)
  if (overlay) return overlay

  overlay = document.createElement('div')
  overlay.id = OVERLAY_ID
  overlay.setAttribute('aria-hidden', 'true')
  overlay.style.cssText = [
    'position:fixed',
    'inset:0',
    'z-index:200',
    'pointer-events:none',
    'opacity:0',
    'background:radial-gradient(ellipse 70% 50% at 20% 0%, rgba(30,79,215,0.35), transparent 55%), radial-gradient(ellipse 50% 40% at 90% 30%, rgba(30,79,215,0.18), transparent 50%), #050508',
  ].join(';')
  document.body.appendChild(overlay)
  return overlay
}

/** Cover the current auth screen, then run `navigate`. App shell will reveal itself. */
export function transitionToApp(navigate: () => void): Promise<void> {
  return new Promise((resolve) => {
    sessionStorage.setItem(ENTER_FLAG, '1')

    if (prefersReducedMotion()) {
      navigate()
      resolve()
      return
    }

    const overlay = ensureOverlay()
    const authBits = document.querySelectorAll('.auth-panel, .auth-visual, .auth-notice')

    const tl = gsap.timeline({
      defaults: { ease: 'power2.inOut' },
      onComplete: () => {
        navigate()
        resolve()
      },
    })

    if (authBits.length) {
      tl.to(authBits, { opacity: 0, y: -12, scale: 0.985, duration: 0.35, stagger: 0.04 }, 0)
    }
    tl.fromTo(overlay, { opacity: 0 }, { opacity: 1, duration: 0.4 }, authBits.length ? 0.12 : 0)
  })
}

/** Call once when AppShell mounts after an auth → app handoff. */
export function playAppEnter(root: HTMLElement | null) {
  if (sessionStorage.getItem(ENTER_FLAG) !== '1') return
  sessionStorage.removeItem(ENTER_FLAG)

  const overlay = document.getElementById(OVERLAY_ID)
  const reduce = prefersReducedMotion()

  if (reduce) {
    overlay?.remove()
    return
  }

  if (root) {
    gsap.fromTo(
      root,
      { opacity: 0, y: 18 },
      { opacity: 1, y: 0, duration: 0.55, ease: 'power3.out', clearProps: 'opacity,transform' },
    )
  }

  if (overlay) {
    gsap.to(overlay, {
      opacity: 0,
      duration: 0.55,
      delay: 0.05,
      ease: 'power2.out',
      onComplete: () => overlay.remove(),
    })
  }
}

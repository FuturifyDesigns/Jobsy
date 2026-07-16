type PaintSmudgeProps = {
  className?: string
  variant?: 'hero' | 'corner' | 'splash' | 'footer'
  opacity?: number
}

/** Organic royal-blue paint strokes matching the Jobsy campaign look. */
export function PaintSmudge({
  className = '',
  variant = 'hero',
  opacity = 1,
}: PaintSmudgeProps) {
  if (variant === 'hero') {
    return (
      <svg
        className={className}
        viewBox="0 0 720 520"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden
        style={{ opacity }}
      >
        <path
          d="M620 18c-70 12-118 58-148 118-28 56-78 92-148 98-62 5-118 38-148 92-24 44-18 98 22 132 48 42 128 38 188 8 72-36 118-42 188-28 58 12 112-8 148-48 42-48 48-128 12-186-28-46-78-82-114-98-18-8-28-4-0-88z"
          fill="#1e4fd7"
        />
        <path
          d="M540 70c-42 28-78 78-92 128-12 44-48 78-98 86"
          stroke="#4d7ef0"
          strokeWidth="18"
          strokeLinecap="round"
          opacity="0.55"
        />
        <path
          d="M410 210c48 8 96-6 138-34"
          stroke="#1438a8"
          strokeWidth="12"
          strokeLinecap="round"
          opacity="0.45"
        />
      </svg>
    )
  }

  if (variant === 'corner') {
    return (
      <svg
        className={className}
        viewBox="0 0 280 220"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden
        style={{ opacity }}
      >
        <path
          d="M250 8c-54 10-96 46-118 96-18 42-58 70-112 74"
          stroke="#1e4fd7"
          strokeWidth="28"
          strokeLinecap="round"
        />
        <path
          d="M210 48c-36 22-58 58-66 98"
          stroke="#4d7ef0"
          strokeWidth="14"
          strokeLinecap="round"
          opacity="0.7"
        />
      </svg>
    )
  }

  if (variant === 'footer') {
    return (
      <svg
        className={className}
        viewBox="0 0 1440 160"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        preserveAspectRatio="none"
        aria-hidden
        style={{ opacity }}
      >
        <path
          d="M0 96c120-48 240-72 380-48 160 28 260 18 400-24 120-36 240-28 360 8 100 30 200 28 300-8v128H0V96z"
          fill="#1e4fd7"
        />
        <path
          d="M0 118c140-36 280-52 420-28 180 30 300 8 460-30 140-34 280-20 420 16 90 24 100 20 140 8v76H0v-42z"
          fill="#1438a8"
          opacity="0.85"
        />
      </svg>
    )
  }

  return (
    <svg
      className={className}
      viewBox="0 0 360 200"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden
      style={{ opacity }}
    >
      <path
        d="M24 120c48-64 120-96 188-78 52 14 88 8 128-28"
        stroke="#1e4fd7"
        strokeWidth="36"
        strokeLinecap="round"
      />
      <path
        d="M48 148c60-40 120-54 180-36"
        stroke="#4d7ef0"
        strokeWidth="16"
        strokeLinecap="round"
        opacity="0.65"
      />
    </svg>
  )
}

import { Link } from 'react-router-dom'

/** Wallet is a placeholder in the mobile app — keep parity. */
export function WalletPage() {
  return (
    <div className="mx-auto max-w-lg py-10 text-center">
      <p
        className="font-[family-name:var(--font-brush)] text-3xl text-[#4d7ef0]"
        style={{ fontWeight: 700 }}
      >
        Coming soon
      </p>
      <h1
        className="mt-2 font-[family-name:var(--font-display)] text-4xl tracking-tight"
        style={{ fontWeight: 800 }}
      >
        Wallet
      </h1>
      <p className="mt-4 text-white/55">
        Payments and payouts are on the way. Posting, applying, and messaging stay free while we
        finish Wallet.
      </p>
      <Link
        to="/app"
        className="mt-8 inline-flex rounded-full bg-[#1e4fd7] px-5 py-2.5 text-sm font-semibold"
      >
        Back to jobs
      </Link>
    </div>
  )
}

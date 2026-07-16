import { Navigate } from 'react-router-dom'
import type { ReactNode } from 'react'
import { useAuth } from '../../lib/auth'
import { JobsPage } from './JobsPage'
import { EmployerJobsPage } from './EmployerJobsPage'

/** Role-aware home: workers browse, employers manage posts. */
export function HomePage() {
  const { isEmployer, loading } = useAuth()
  if (loading) return <p className="text-white/50">Loading…</p>
  return isEmployer ? <EmployerJobsPage /> : <JobsPage />
}

export function RequireEmployer({ children }: { children: ReactNode }) {
  const { isEmployer, loading } = useAuth()
  if (loading) return null
  if (!isEmployer) return <Navigate to="/app" replace />
  return children
}

export function RequireWorker({ children }: { children: ReactNode }) {
  const { isEmployer, loading } = useAuth()
  if (loading) return null
  if (isEmployer) return <Navigate to="/app" replace />
  return children
}

import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider } from './lib/auth'
import { CookieProvider } from './components/CookieConsent'
import { LandingPage } from './pages/LandingPage'
import { FeaturesPage } from './pages/FeaturesPage'
import { HowItWorksPage } from './pages/HowItWorksPage'
import { PrivacyPage, TermsPage, CookiesPage } from './pages/LegalPages'
import { SignInPage, SignUpPage, ForgotPasswordPage } from './pages/AuthPages'
import { AuthCallbackPage } from './pages/AuthCallbackPage'
import { AppLayout } from './pages/app/AppLayout'
import { HomePage, RequireEmployer, RequireWorker } from './pages/app/HomePage'
import { JobDetailPage } from './pages/app/JobDetailPage'
import { ExternalJobsPage } from './pages/app/ExternalJobsPage'
import { MessagesPage, ChatThreadPage } from './pages/app/MessagesPage'
import { ProfilePage } from './pages/app/ProfilePage'
import { PostJobPage } from './pages/app/PostJobPage'
import { ApplicationsPage } from './pages/app/ApplicationsPage'
import { SavedJobsPage } from './pages/app/SavedJobsPage'
import { WalletPage } from './pages/app/WalletPage'

const routerBasename = import.meta.env.BASE_URL.replace(/\/$/, '') || undefined

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter basename={routerBasename}>
        <CookieProvider>
          <Routes>
            <Route path="/" element={<LandingPage />} />
            <Route path="/features" element={<FeaturesPage />} />
            <Route path="/how-it-works" element={<HowItWorksPage />} />
            <Route path="/botswana" element={<Navigate to="/how-it-works" replace />} />
            <Route path="/privacy" element={<PrivacyPage />} />
            <Route path="/terms" element={<TermsPage />} />
            <Route path="/cookies" element={<CookiesPage />} />
            <Route path="/signin" element={<SignInPage />} />
            <Route path="/signup" element={<SignUpPage />} />
            <Route path="/forgot-password" element={<ForgotPasswordPage />} />
            <Route path="/auth/callback" element={<AuthCallbackPage />} />
            <Route path="/app" element={<AppLayout />}>
              <Route index element={<HomePage />} />
              <Route path="jobs/:id" element={<JobDetailPage />} />
              <Route
                path="jobs/:id/applications"
                element={
                  <RequireEmployer>
                    <ApplicationsPage />
                  </RequireEmployer>
                }
              />
              <Route
                path="post"
                element={
                  <RequireEmployer>
                    <PostJobPage />
                  </RequireEmployer>
                }
              />
              <Route
                path="saved"
                element={
                  <RequireWorker>
                    <SavedJobsPage />
                  </RequireWorker>
                }
              />
              <Route
                path="web-jobs"
                element={
                  <RequireWorker>
                    <ExternalJobsPage />
                  </RequireWorker>
                }
              />
              <Route path="wallet" element={<WalletPage />} />
              <Route path="messages" element={<MessagesPage />} />
              <Route path="messages/:id" element={<ChatThreadPage />} />
              <Route path="profile" element={<ProfilePage />} />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </CookieProvider>
      </BrowserRouter>
    </AuthProvider>
  )
}

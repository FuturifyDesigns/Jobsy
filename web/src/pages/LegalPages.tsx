import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { SiteShell } from '../components/SiteShell'
import { LEGAL } from '../lib/legal'
import { openCookieSettings } from '../components/CookieConsent'

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-10">
      <h2
        className="font-[family-name:var(--font-display)] text-2xl tracking-tight text-ink"
        style={{ fontWeight: 800 }}
      >
        {title}
      </h2>
      <div className="mt-3 space-y-3 text-[0.95rem] leading-relaxed text-mute">{children}</div>
    </section>
  )
}

function LegalLayout({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string
  title: string
  children: ReactNode
}) {
  return (
    <SiteShell showPaint={false}>
      <article className="mx-auto max-w-3xl px-5 pt-28 pb-24">
        <p
          className="font-[family-name:var(--font-brush)] text-3xl text-paint"
          style={{ fontWeight: 700 }}
        >
          {eyebrow}
        </p>
        <h1
          className="mt-2 font-[family-name:var(--font-display)] text-4xl tracking-tight text-ink md:text-5xl"
          style={{ fontWeight: 800 }}
        >
          {title}
        </h1>
        <p className="mt-3 text-sm text-mute">
          Effective {LEGAL.effective} · Governed by the laws of {LEGAL.jurisdiction}
        </p>
        <p className="mt-2 text-sm text-mute">
          Aligned with Botswana&apos;s <strong className="text-ink">{LEGAL.act}</strong>.
        </p>
        <div className="mt-10 border-t border-ink/10 pt-2">{children}</div>
        <p className="mt-14 text-sm text-mute">
          Questions?{' '}
          <a href={`mailto:${LEGAL.email}`} className="font-semibold text-paint hover:underline">
            {LEGAL.email}
          </a>
        </p>
      </article>
    </SiteShell>
  )
}

export function PrivacyPage() {
  return (
    <LegalLayout eyebrow="Legal" title="Privacy Policy">
      <Section title="1. Who we are">
        <p>
          {LEGAL.controller} (“Jobsy”, “we”, “us”) provides a marketplace connecting workers and
          employers in Botswana via our website and mobile application. We are the data controller
          for personal data processed through Jobsy.
        </p>
        <p>
          Contact: <a href={`mailto:${LEGAL.email}`} className="text-paint hover:underline">{LEGAL.email}</a>
        </p>
      </Section>

      <Section title="2. Legal framework">
        <p>
          We process personal data in accordance with the <strong className="text-ink">{LEGAL.act}</strong>{' '}
          and related guidelines of the {LEGAL.commission}. Personal data must be processed lawfully,
          fairly, and transparently; collected for specified purposes; limited to what is necessary;
          kept accurate; retained only as long as needed; and protected with appropriate security.
        </p>
      </Section>

      <Section title="3. What we collect">
        <p>Depending on how you use Jobsy, we may process:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>Identity & contact data (name, email, phone, location)</li>
          <li>Account & profile data (role, bio, skills, company details, photos)</li>
          <li>Job & application data (listings, applications, ratings, messages)</li>
          <li>Payment / wallet-related records needed to operate the service</li>
          <li>Device & usage data (IP, browser, app version, approximate location if you allow it)</li>
          <li>Cookie and similar technology data (see our <Link to="/cookies" className="text-paint hover:underline">Cookie Policy</Link>)</li>
        </ul>
      </Section>

      <Section title="4. Why we process your data (lawful bases)">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">Contract</strong> — to create your account, match jobs,
            enable chat, and provide the Jobsy service you request.
          </li>
          <li>
            <strong className="text-ink">Consent</strong> — for optional cookies/analytics, marketing
            messages (if any), and certain device permissions. You may withdraw consent at any time.
          </li>
          <li>
            <strong className="text-ink">Legitimate interests</strong> — to secure the platform,
            prevent fraud, improve reliability, and support users — balanced against your rights.
          </li>
          <li>
            <strong className="text-ink">Legal obligation</strong> — where Botswana law requires
            retention or disclosure.
          </li>
        </ul>
      </Section>

      <Section title="5. Sharing">
        <p>
          We do not sell your personal data. We may share data with: service providers (e.g. hosting,
          authentication, storage such as Supabase), payment partners where applicable, and
          authorities when legally required. Cross-border transfers are only made with appropriate
          safeguards or your consent, consistent with the Act.
        </p>
      </Section>

      <Section title="6. Retention & security">
        <p>
          We keep data only as long as needed for the purposes above (e.g. while your account is
          active and for a reasonable period afterward for disputes, security, and legal compliance).
          We use access controls, encryption in transit, and other safeguards appropriate to the risk.
        </p>
      </Section>

      <Section title="7. Your rights under the Data Protection Act">
        <p>Subject to the Act, you may request to:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>Access a copy of your personal data</li>
          <li>Correct inaccurate data</li>
          <li>Erase data in certain cases</li>
          <li>Object to certain processing (including direct marketing)</li>
          <li>Withdraw consent where processing is based on consent</li>
          <li>Lodge a complaint with the {LEGAL.commission}</li>
        </ul>
        <p>
          To exercise these rights, email{' '}
          <a href={`mailto:${LEGAL.email}`} className="text-paint hover:underline">{LEGAL.email}</a>.
          We will respond within a reasonable time as required by law.
        </p>
      </Section>

      <Section title="8. Children">
        <p>Jobsy is intended for users aged 18 and over. We do not knowingly collect data from children.</p>
      </Section>

      <Section title="9. Changes">
        <p>
          We may update this policy. Material changes will be posted on this page with an updated
          effective date. Continued use after changes means you acknowledge the updated policy.
        </p>
      </Section>

      <Section title="10. Related">
        <p>
          <Link to="/terms" className="text-paint hover:underline">Terms of Service</Link>
          {' · '}
          <Link to="/cookies" className="text-paint hover:underline">Cookie Policy</Link>
          {' · '}
          <button type="button" onClick={() => openCookieSettings()} className="text-paint hover:underline">
            Cookie settings
          </button>
        </p>
      </Section>
    </LegalLayout>
  )
}

export function TermsPage() {
  return (
    <LegalLayout eyebrow="Legal" title="Terms of Service">
      <Section title="1. Agreement">
        <p>
          These Terms govern your use of the Jobsy website and mobile app. By creating an account or
          using Jobsy, you agree to these Terms and our{' '}
          <Link to="/privacy" className="text-paint hover:underline">Privacy Policy</Link>. If you do
          not agree, do not use the service.
        </p>
      </Section>

      <Section title="2. The service">
        <p>
          Jobsy connects workers and employers for local work opportunities in Botswana. We provide
          tools to post jobs, apply, message, and manage related activity. We are a platform — we are
          not the employer or worker for engagements arranged between users unless expressly stated.
        </p>
      </Section>

      <Section title="3. Eligibility & accounts">
        <ul className="list-disc space-y-1 pl-5">
          <li>You must be 18+ and able to form a binding contract under Botswana law.</li>
          <li>Provide accurate information and keep one account per person.</li>
          <li>You are responsible for safeguarding your login credentials.</li>
          <li>You may switch between worker and employer modes where the product allows.</li>
        </ul>
      </Section>

      <Section title="4. User obligations">
        <ul className="list-disc space-y-1 pl-5">
          <li>Post truthful job details and fair pay expectations.</li>
          <li>Represent your skills and availability honestly.</li>
          <li>Comply with Botswana labour and other applicable laws.</li>
          <li>No fraud, harassment, spam, illegal work, or attempts to bypass platform safeguards.</li>
        </ul>
      </Section>

      <Section title="5. Fees & payments">
        <p>
          Where platform fees apply (including any service fees disclosed in-app), they are charged as
          described at the time of the transaction. Payment flows (including escrow-style holds if
          offered) are described in the product. Disputes should be raised promptly through support.
        </p>
      </Section>

      <Section title="6. Content & messaging">
        <p>
          You retain rights to content you submit, and grant Jobsy a licence to host and display it to
          operate the service. Do not upload unlawful, infringing, or harmful content. We may remove
          content or suspend accounts that violate these Terms.
        </p>
      </Section>

      <Section title="7. Privacy & data protection">
        <p>
          Personal data is handled under our Privacy Policy and Botswana&apos;s {LEGAL.act}. By using
          Jobsy you acknowledge that processing necessary to provide the service will occur as
          described there.
        </p>
      </Section>

      <Section title="8. Disclaimers">
        <p>
          Jobsy is provided “as is” to the fullest extent permitted by law. We do not guarantee
          continuous availability, job outcomes, or the conduct of other users. You are responsible
          for verifying counterparties and work arrangements.
        </p>
      </Section>

      <Section title="9. Liability">
        <p>
          To the maximum extent permitted by Botswana law, Jobsy and Futurify Designs are not liable
          for indirect or consequential losses arising from use of the platform. Nothing in these
          Terms excludes liability that cannot be excluded by law.
        </p>
      </Section>

      <Section title="10. Suspension & termination">
        <p>
          We may suspend or terminate accounts for Terms violations or risk to users. You may stop
          using Jobsy and request account deletion via profile settings or by emailing{' '}
          <a href={`mailto:${LEGAL.email}`} className="text-paint hover:underline">{LEGAL.email}</a>.
        </p>
      </Section>

      <Section title="11. Governing law">
        <p>
          These Terms are governed by the laws of the Republic of Botswana. Courts of Botswana have
          jurisdiction, without prejudice to mandatory consumer protections.
        </p>
      </Section>

      <Section title="12. Contact">
        <p>
          Legal: <a href={`mailto:${LEGAL.email}`} className="text-paint hover:underline">{LEGAL.email}</a>
        </p>
      </Section>
    </LegalLayout>
  )
}

export function CookiesPage() {
  return (
    <LegalLayout eyebrow="Legal" title="Cookie Policy">
      <Section title="1. What are cookies?">
        <p>
          Cookies are small text files stored on your device. Similar technologies (local storage,
          pixels) may be used for the same purposes. Under Botswana&apos;s {LEGAL.act}, information
          that identifies you (or can be linked to you) is personal data and is processed with a
          lawful basis — including consent for non-essential cookies.
        </p>
      </Section>

      <Section title="2. How Jobsy uses cookies">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">Essential</strong> — required for security, authentication,
            load balancing, and remembering your cookie choice. These do not require optional consent.
          </li>
          <li>
            <strong className="text-ink">Preferences</strong> — remember UI choices (optional; only if
            you enable cookies).
          </li>
          <li>
            <strong className="text-ink">Analytics</strong> — understand how the site is used to improve
            Jobsy (optional; only if you enable cookies).
          </li>
        </ul>
      </Section>

      <Section title="3. Your choice">
        <p>
          On first visit we ask you to <strong className="text-ink">Enable cookies</strong> or{' '}
          <strong className="text-ink">Decline</strong>. You will see a confirmation notification
          either way. You can change your mind anytime:
        </p>
        <p>
          <button
            type="button"
            onClick={() => openCookieSettings()}
            className="rounded-full bg-paint px-5 py-2.5 text-sm font-semibold text-white"
          >
            Open cookie settings
          </button>
        </p>
      </Section>

      <Section title="4. What we store when you choose">
        <ul className="list-disc space-y-1 pl-5">
          <li>
            <code className="text-ink">jobsy_cookie_consent</code> — accepted or declined
          </li>
          <li>
            <code className="text-ink">jobsy_cookie_prefs</code> — which optional categories are on
          </li>
          <li>
            If enabled: a random analytics id in local storage (not sold, used only for product
            improvement)
          </li>
        </ul>
      </Section>

      <Section title="5. Managing cookies in your browser">
        <p>
          You can also clear or block cookies in your browser settings. Blocking essential cookies may
          prevent sign-in or other core features from working.
        </p>
      </Section>

      <Section title="6. More information">
        <p>
          See our <Link to="/privacy" className="text-paint hover:underline">Privacy Policy</Link> for
          your rights under the {LEGAL.act}, including access, correction, erasure, and objection.
        </p>
      </Section>
    </LegalLayout>
  )
}

import Link from "next/link"

export const metadata = {
  title: "Privacy policy — SuccessfulSuccess",
  description: "What SuccessfulSuccess does with your data.",
}

const CONTACT_EMAIL = "annadizhak8@gmail.com"

export default function PrivacyPage() {
  return (
    <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-12">
      <Link href="/" className="text-primary text-sm font-semibold">
        ← SuccessfulSuccess
      </Link>

      <h1 className="mt-6 text-3xl font-bold tracking-tight">Privacy policy</h1>
      <p className="text-muted-foreground mt-2 text-sm">
        Last updated: 7 October 2026
      </p>

      <div className="mt-8 space-y-6 leading-relaxed">
        <section>
          <h2 className="text-lg font-bold">What this site is</h2>
          <p className="mt-2">
            SuccessfulSuccess is a small student project that shows today&apos;s
            meetings and lets you add new ones.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-bold">Signing in</h2>
          <p className="mt-2">
            You can sign in with an email and a password, or with your Google
            account. Sign-in is handled by Amazon Cognito. From Google or
            Cognito we only use your <strong>email address</strong> and{" "}
            <strong>name</strong>, and only to show who is signed in. We never
            see your Google password.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-bold">Meetings</h2>
          <p className="mt-2">
            The meetings you create, including their names, descriptions,
            locations and participants, are stored in our database so they can
            be shown on the site.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-bold">Sharing</h2>
          <p className="mt-2">
            We do not sell your data, and we do not share it with anyone. The
            site runs on Amazon Web Services, which stores it on our behalf.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-bold">Contact</h2>
          <p className="mt-2">
            Questions, or want your data deleted? Email{" "}
            <a
              href={`mailto:${CONTACT_EMAIL}`}
              className="text-primary underline"
            >
              {CONTACT_EMAIL}
            </a>
            .
          </p>
        </section>
      </div>
    </main>
  )
}

defmodule DiagramForgeWeb.PrivacyLive do
  @moduledoc """
  Privacy Policy page.
  """
  use DiagramForgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Privacy Policy")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100">
      <%!-- Simple Header --%>
      <div class="bg-slate-900 border-b border-slate-800">
        <div class="container mx-auto px-4 py-3">
          <div class="flex items-center gap-3">
            <a href="/" class="flex items-center gap-3 hover:opacity-80 transition">
              <img src={~p"/images/logo.png"} alt="DiagramForge" class="h-10 w-10" />
              <span class="text-xl font-bold text-slate-100">DiagramForge</span>
            </a>
          </div>
        </div>
      </div>

      <%!-- Content --%>
      <div class="container mx-auto px-4 py-12 max-w-3xl">
        <h1 class="text-3xl font-bold mb-8">Privacy Policy</h1>

        <div class="prose prose-invert prose-slate max-w-none space-y-6 text-slate-300">
          <p class="text-sm text-slate-500">Last updated: {Date.utc_today()}</p>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">1. Information We Collect</h2>

            <h3 class="text-lg font-medium text-slate-200 mt-6 mb-3">Account Information</h3>
            <p>When you sign in via GitHub OAuth, we collect:</p>
            <ul class="list-disc pl-6 space-y-2">
              <li>Your GitHub username and user ID</li>
              <li>Your email address (from your GitHub profile)</li>
              <li>Your display name (from your GitHub profile)</li>
              <li>Your avatar URL (from your GitHub profile)</li>
            </ul>

            <h3 class="text-lg font-medium text-slate-200 mt-6 mb-3">User-Generated Content</h3>
            <p>We store content you create, including:</p>
            <ul class="list-disc pl-6 space-y-2">
              <li>Diagrams you create or generate</li>
              <li>Documents you upload for diagram generation</li>
              <li>Tags and filters you create</li>
              <li>Your visibility preferences for diagrams</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">
              2. How We Use Your Information
            </h2>
            <p>We use your information to:</p>
            <ul class="list-disc pl-6 space-y-2">
              <li>Provide and maintain the Service</li>
              <li>Authenticate your identity</li>
              <li>Store and display your diagrams</li>
              <li>Enable sharing features (public diagrams, forking)</li>
              <li>Improve the Service based on usage patterns</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">3. Third-Party Services</h2>
            <p>DiagramForge uses the following third-party services:</p>

            <h3 class="text-lg font-medium text-slate-200 mt-6 mb-3">GitHub</h3>
            <p>
              We use GitHub for authentication. When you sign in, GitHub shares your profile
              information with us according to their <a
                href="https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement"
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:text-blue-300"
              >
                privacy policy
              </a>.
            </p>

            <h3 class="text-lg font-medium text-slate-200 mt-6 mb-3">OpenAI</h3>
            <p>
              We use OpenAI's API to generate diagrams from your documents and prompts. Content
              you submit for diagram generation is sent to OpenAI and processed according to their <a
                href="https://openai.com/policies/privacy-policy"
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:text-blue-300"
              >
                privacy policy
              </a>.
            </p>

            <h3 class="text-lg font-medium text-slate-200 mt-6 mb-3">Stripe</h3>
            <p>
              If you choose to support the project via Stripe, your payment information is handled
              by Stripe according to their <a
                href="https://stripe.com/privacy"
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:text-blue-300"
              >
                privacy policy
              </a>. We do not store your payment card details.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">4. Data Retention</h2>
            <ul class="list-disc pl-6 space-y-2">
              <li>Your account information is retained as long as your account is active.</li>
              <li>Diagrams and content are retained until you delete them.</li>
              <li>Uploaded documents are processed and then deleted after diagram generation.</li>
              <li>You can request deletion of your account and all associated data.</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">5. Your Rights</h2>
            <p>You have the right to:</p>
            <ul class="list-disc pl-6 space-y-2">
              <li>Access your personal data</li>
              <li>Correct inaccurate data</li>
              <li>Delete your account and associated data</li>
              <li>Export your diagrams</li>
              <li>Control the visibility of your diagrams (private, unlisted, public)</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">6. Data Security</h2>
            <p>
              We implement reasonable security measures to protect your data, including:
            </p>
            <ul class="list-disc pl-6 space-y-2">
              <li>HTTPS encryption for all data in transit</li>
              <li>Secure database storage</li>
              <li>OAuth-based authentication (no passwords stored)</li>
            </ul>
            <p class="mt-4">
              However, no method of transmission over the Internet is 100% secure.
              We cannot guarantee absolute security of your data.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">7. Cookies</h2>
            <p>
              We use essential cookies for authentication and session management.
              We do not use tracking or advertising cookies.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">8. Changes to This Policy</h2>
            <p>
              We may update this Privacy Policy from time to time. We will notify users of
              significant changes by posting a notice on the Service. Your continued use of the
              Service after changes constitutes acceptance of the updated policy.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">9. Contact</h2>
            <p>
              For questions about this Privacy Policy or to exercise your data rights,
              please contact us via
              <a
                href={Application.get_env(:diagram_forge, :linkedin_url)}
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:text-blue-300"
              >
                LinkedIn
              </a>
              or open an issue on <a
                href={Application.get_env(:diagram_forge, :github_issues_url)}
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:text-blue-300"
              >
                GitHub
              </a>.
            </p>
          </section>
        </div>

        <div class="mt-12 pt-8 border-t border-slate-800 text-center">
          <a href="/" class="text-blue-400 hover:text-blue-300 transition">
            &larr; Back to DiagramForge
          </a>
        </div>
      </div>
    </div>
    """
  end
end

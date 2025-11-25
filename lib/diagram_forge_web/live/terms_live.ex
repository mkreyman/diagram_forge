defmodule DiagramForgeWeb.TermsLive do
  @moduledoc """
  Terms of Service page.
  """
  use DiagramForgeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Terms of Service")}
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
        <h1 class="text-3xl font-bold mb-8">Terms of Service</h1>

        <div class="prose prose-invert prose-slate max-w-none space-y-6 text-slate-300">
          <p class="text-sm text-slate-500">Last updated: {Date.utc_today()}</p>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">1. Acceptance of Terms</h2>
            <p>
              By accessing and using DiagramForge ("the Service"), you agree to be bound by these
              Terms of Service. If you do not agree to these terms, please do not use the Service.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">2. Description of Service</h2>
            <p>
              DiagramForge is a web application that helps developers create and manage technical
              diagrams using AI-powered generation from documents and prompts. The Service uses
              Mermaid syntax for diagram rendering.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">3. User Accounts</h2>
            <ul class="list-disc pl-6 space-y-2">
              <li>You must authenticate via GitHub to use certain features of the Service.</li>
              <li>You are responsible for maintaining the security of your GitHub account.</li>
              <li>You are responsible for all activities that occur under your account.</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">4. Acceptable Use</h2>
            <p>You agree not to:</p>
            <ul class="list-disc pl-6 space-y-2">
              <li>Use the Service for any unlawful purpose or in violation of any laws.</li>
              <li>Upload malicious content or attempt to compromise the Service.</li>
              <li>Abuse or overload the Service with excessive requests.</li>
              <li>Share content that infringes on intellectual property rights.</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">5. User Content</h2>
            <ul class="list-disc pl-6 space-y-2">
              <li>You retain ownership of diagrams and documents you create.</li>
              <li>By making content public, you grant other users the right to view and fork it.</li>
              <li>We do not claim ownership of your content.</li>
            </ul>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">6. Service Availability</h2>
            <p>
              The Service is provided "as is" without warranty of any kind. We do not guarantee
              that the Service will be available at all times or free from errors. We may modify,
              suspend, or discontinue the Service at any time without notice.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">7. Limitation of Liability</h2>
            <p>
              To the maximum extent permitted by law, DiagramForge and its maintainers shall not
              be liable for any indirect, incidental, special, consequential, or punitive damages
              arising from your use of the Service.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">8. Termination</h2>
            <p>
              We reserve the right to terminate or suspend your access to the Service at any time,
              with or without cause, and with or without notice. Upon termination, your right to
              use the Service will immediately cease.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">9. Changes to Terms</h2>
            <p>
              We may update these Terms of Service from time to time. We will notify users of
              significant changes by posting a notice on the Service. Your continued use of the
              Service after changes constitutes acceptance of the new terms.
            </p>
          </section>

          <section>
            <h2 class="text-xl font-semibold text-slate-100 mt-8 mb-4">10. Contact</h2>
            <p>
              For questions about these Terms of Service, please contact us via
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

defmodule DiagramForgeWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard with platform statistics.
  """

  use DiagramForgeWeb, :live_view

  import Ecto.Query

  alias DiagramForge.Accounts.User
  alias DiagramForge.Diagrams.Diagram
  alias DiagramForge.Diagrams.Document
  alias DiagramForge.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Backpex.HTML.Layout.app_shell fluid={false}>
      <:topbar>
        <Backpex.HTML.Layout.topbar_branding title="DiagramForge Admin" />

        <div class="flex items-center gap-2">
          <.link navigate={~p"/admin/dashboard"} class="btn btn-ghost btn-sm">
            Dashboard
          </.link>
          <.link navigate={~p"/admin/users"} class="btn btn-ghost btn-sm">
            Users
          </.link>
          <.link navigate={~p"/admin/diagrams"} class="btn btn-ghost btn-sm">
            Diagrams
          </.link>
          <.link navigate={~p"/admin/documents"} class="btn btn-ghost btn-sm">
            Documents
          </.link>
          <.link navigate={~p"/admin/prompts"} class="btn btn-ghost btn-sm">
            Prompts
          </.link>
        </div>

        <Backpex.HTML.Layout.topbar_dropdown>
          <:label>
            <div class="btn btn-square btn-ghost">
              <Backpex.HTML.CoreComponents.icon name="hero-user" class="size-6" />
            </div>
          </:label>
          <li>
            <span class="text-sm text-base-content/70">
              {if assigns[:current_user], do: assigns.current_user.email}
            </span>
          </li>
          <li>
            <.link navigate={~p"/"} class="flex justify-between hover:bg-base-200">
              <p>Back to App</p>
              <Backpex.HTML.CoreComponents.icon name="hero-arrow-left" class="size-5" />
            </.link>
          </li>
          <li>
            <.link href="/auth/logout" class="text-error flex justify-between hover:bg-base-200">
              <p>Logout</p>
              <Backpex.HTML.CoreComponents.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            </.link>
          </li>
        </Backpex.HTML.Layout.topbar_dropdown>
      </:topbar>
      <:sidebar>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/dashboard"}>
          <Backpex.HTML.CoreComponents.icon name="hero-home" class="size-5" /> Dashboard
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/users"}>
          <Backpex.HTML.CoreComponents.icon name="hero-users" class="size-5" /> Users
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/diagrams"}>
          <Backpex.HTML.CoreComponents.icon name="hero-rectangle-group" class="size-5" /> Diagrams
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/documents"}>
          <Backpex.HTML.CoreComponents.icon name="hero-document-text" class="size-5" /> Documents
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/prompts"}>
          <Backpex.HTML.CoreComponents.icon name="hero-chat-bubble-bottom-center-text" class="size-5" />
          Prompts
        </Backpex.HTML.Layout.sidebar_item>
      </:sidebar>
      <Backpex.HTML.Layout.flash_messages flash={@flash} />

      <div class="space-y-8">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
          <p class="mt-1 text-sm text-base-content/70">Platform overview and statistics</p>
        </div>

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <.stat_card
            title="Total Users"
            value={@user_count}
            icon="hero-users"
            href={~p"/admin/users"}
          />
          <.stat_card
            title="Total Diagrams"
            value={@diagram_count}
            icon="hero-rectangle-group"
            href={~p"/admin/diagrams"}
          />
          <.stat_card
            title="Total Documents"
            value={@document_count}
            icon="hero-document-text"
            href={~p"/admin/documents"}
          />
        </div>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
            <h2 class="text-lg font-semibold text-base-content mb-4">Diagram Statistics</h2>
            <dl class="space-y-3">
              <div class="flex justify-between">
                <dt class="text-sm text-base-content/70">Public Diagrams</dt>
                <dd class="text-sm font-medium">{@public_diagram_count}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-sm text-base-content/70">Private Diagrams</dt>
                <dd class="text-sm font-medium">{@private_diagram_count}</dd>
              </div>
            </dl>
          </div>

          <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
            <h2 class="text-lg font-semibold text-base-content mb-4">Document Statistics</h2>
            <dl class="space-y-3">
              <div class="flex justify-between">
                <dt class="text-sm text-base-content/70">Ready</dt>
                <dd class="text-sm font-medium">{@docs_ready}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-sm text-base-content/70">Processing</dt>
                <dd class="text-sm font-medium">{@docs_processing}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-sm text-base-content/70">Errors</dt>
                <dd class="text-sm font-medium text-error">{@docs_error}</dd>
              </div>
            </dl>
          </div>
        </div>

        <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
          <h2 class="text-lg font-semibold text-base-content mb-4">Recent Users</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Joined</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={user <- @recent_users}>
                  <td>{user.email}</td>
                  <td class="text-base-content/70">
                    {Calendar.strftime(user.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Backpex.HTML.Layout.app_shell>
    """
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :href, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm hover:shadow-md transition-shadow"
    >
      <div class="flex items-center">
        <div class="shrink-0">
          <.icon name={@icon} class="h-8 w-8 text-primary" />
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-base-content/70">{@title}</p>
          <p class="text-2xl font-bold text-base-content">{@value}</p>
        </div>
      </div>
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_url, ~p"/admin/dashboard")
     |> load_stats()}
  end

  defp load_stats(socket) do
    socket
    |> assign(:user_count, Repo.aggregate(User, :count))
    |> assign(:diagram_count, Repo.aggregate(Diagram, :count))
    |> assign(:document_count, Repo.aggregate(Document, :count))
    |> assign(
      :public_diagram_count,
      Repo.aggregate(from(d in Diagram, where: d.visibility == :public), :count)
    )
    |> assign(
      :private_diagram_count,
      Repo.aggregate(from(d in Diagram, where: d.visibility == :private), :count)
    )
    |> assign(:docs_ready, Repo.aggregate(from(d in Document, where: d.status == :ready), :count))
    |> assign(
      :docs_processing,
      Repo.aggregate(from(d in Document, where: d.status == :processing), :count)
    )
    |> assign(:docs_error, Repo.aggregate(from(d in Document, where: d.status == :error), :count))
    |> assign(:recent_users, Repo.all(from(u in User, order_by: [desc: u.inserted_at], limit: 5)))
  end
end

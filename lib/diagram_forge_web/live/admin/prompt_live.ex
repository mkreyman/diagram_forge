defmodule DiagramForgeWeb.Admin.PromptLive do
  @moduledoc """
  Admin page for managing AI prompts.

  Shows all known prompts with their current status (default or customized).
  Allows editing prompts and resetting to defaults.
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.AI

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
          <h1 class="text-2xl font-bold text-base-content">AI Prompts</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Customize AI prompts for concept extraction and diagram generation.
            Changes take effect immediately.
          </p>
        </div>

        <div class="space-y-4">
          <div
            :for={prompt <- @prompts}
            class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm"
          >
            <div class="flex justify-between items-start gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-3">
                  <h3 class="text-lg font-semibold text-base-content">{prompt.key}</h3>
                  <span class={[
                    "text-xs px-2 py-0.5 rounded font-medium",
                    prompt.source == :default && "bg-base-200 text-base-content/70",
                    prompt.source == :database && "bg-primary/10 text-primary"
                  ]}>
                    {if prompt.source == :default, do: "Default", else: "Customized"}
                  </span>
                </div>
                <p class="mt-1 text-sm text-base-content/70">{prompt.description}</p>
              </div>
              <div class="flex gap-2 shrink-0">
                <.link
                  navigate={~p"/admin/prompts/#{prompt.key}/edit"}
                  class="btn btn-sm btn-primary"
                >
                  <Backpex.HTML.CoreComponents.icon name="hero-pencil" class="size-4" /> Edit
                </.link>
                <button
                  phx-click="reset_to_default"
                  phx-value-key={prompt.key}
                  disabled={prompt.source == :default}
                  data-confirm="Are you sure you want to reset this prompt to its default value?"
                  class={[
                    "btn btn-sm",
                    prompt.source == :default && "btn-disabled",
                    prompt.source == :database && "btn-error"
                  ]}
                >
                  <Backpex.HTML.CoreComponents.icon name="hero-arrow-path" class="size-4" /> Reset
                </button>
              </div>
            </div>
            <div class="mt-4">
              <pre class="p-4 bg-base-200 rounded-lg text-sm overflow-x-auto max-h-48 whitespace-pre-wrap">{String.trim(prompt.content)}</pre>
            </div>
          </div>
        </div>
      </div>
    </Backpex.HTML.Layout.app_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI Prompts")
     |> assign(:current_url, ~p"/admin/prompts")
     |> load_prompts()}
  end

  @impl true
  def handle_event("reset_to_default", %{"key" => key}, socket) do
    prompt = Enum.find(socket.assigns.prompts, &(&1.key == key))

    case prompt do
      %{source: :database, db_record: record} ->
        case AI.delete_prompt(record) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prompt \"#{key}\" has been reset to default.")
             |> load_prompts()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to reset prompt.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp load_prompts(socket) do
    assign(socket, :prompts, AI.list_all_prompts_with_status())
  end
end

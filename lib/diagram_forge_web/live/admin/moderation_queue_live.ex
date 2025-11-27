defmodule DiagramForgeWeb.Admin.ModerationQueueLive do
  @moduledoc """
  Admin moderation queue for reviewing diagrams flagged for manual review.
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.Content
  alias DiagramForge.Diagrams.Diagram
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
          <.link navigate={~p"/admin/moderation"} class="btn btn-ghost btn-sm btn-active">
            Moderation
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
          <.link navigate={~p"/admin/usage/dashboard"} class="btn btn-ghost btn-sm">
            Usage
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
        </Backpex.HTML.Layout.topbar_dropdown>
      </:topbar>
      <:sidebar>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/dashboard"}>
          <Backpex.HTML.CoreComponents.icon name="hero-home" class="size-5" /> Dashboard
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/moderation"}>
          <Backpex.HTML.CoreComponents.icon name="hero-shield-check" class="size-5" /> Moderation
          <span :if={@pending_count > 0} class="badge badge-warning badge-sm ml-auto">
            {@pending_count}
          </span>
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

        <div class="divider my-2 text-xs text-base-content/50">API Usage</div>

        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/usage/dashboard"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-chart-bar" class="size-5" /> Usage Dashboard
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/usage/alerts"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-bell-alert" class="size-5" /> Alerts
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/ai-providers"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-server" class="size-5" /> AI Providers
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/ai-models"}>
          <Backpex.HTML.CoreComponents.icon name="hero-cpu-chip" class="size-5" /> AI Models
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/ai-model-prices"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-currency-dollar" class="size-5" /> Model Prices
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/alert-thresholds"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-adjustments-horizontal" class="size-5" />
          Thresholds
        </Backpex.HTML.Layout.sidebar_item>
      </:sidebar>
      <Backpex.HTML.Layout.flash_messages flash={@flash} />

      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Moderation Queue</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Review and moderate flagged diagrams
          </p>
        </div>
        
    <!-- Stats -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-4">
          <div class="stat bg-base-100 rounded-lg border border-base-300 shadow-sm">
            <div class="stat-title">Pending Review</div>
            <div class="stat-value text-warning">{@stats.manual_review}</div>
          </div>
          <div class="stat bg-base-100 rounded-lg border border-base-300 shadow-sm">
            <div class="stat-title">Approved</div>
            <div class="stat-value text-success">{@stats.approved}</div>
          </div>
          <div class="stat bg-base-100 rounded-lg border border-base-300 shadow-sm">
            <div class="stat-title">Rejected</div>
            <div class="stat-value text-error">{@stats.rejected}</div>
          </div>
          <div class="stat bg-base-100 rounded-lg border border-base-300 shadow-sm">
            <div class="stat-title">Pending AI</div>
            <div class="stat-value text-info">{@stats.pending}</div>
          </div>
        </div>
        
    <!-- Queue -->
        <div class="bg-base-100 rounded-lg border border-base-300 shadow-sm">
          <div class="p-4 border-b border-base-300">
            <h2 class="text-lg font-semibold">Items Requiring Review</h2>
          </div>

          <div :if={@diagrams == []} class="p-8 text-center text-base-content/70">
            <Backpex.HTML.CoreComponents.icon
              name="hero-check-circle"
              class="size-12 mx-auto mb-2 text-success"
            />
            <p>No diagrams pending review!</p>
          </div>

          <div :if={@diagrams != []} class="divide-y divide-base-300">
            <div
              :for={diagram <- @diagrams}
              class="p-4 hover:bg-base-200/50 transition-colors"
              id={"diagram-#{diagram.id}"}
            >
              <div class="flex items-start justify-between gap-4">
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <h3 class="font-medium text-base-content truncate">
                      {diagram.title || "Untitled Diagram"}
                    </h3>
                    <span class="badge badge-warning badge-sm">Review</span>
                  </div>
                  <p class="mt-1 text-sm text-base-content/70 line-clamp-2">
                    {diagram.summary || "No summary"}
                  </p>
                  <div class="mt-2 flex items-center gap-4 text-xs text-base-content/50">
                    <span>ID: {String.slice(diagram.id, 0..7)}...</span>
                    <span>Created: {Calendar.strftime(diagram.inserted_at, "%Y-%m-%d %H:%M")}</span>
                    <span :if={diagram.moderation_reason}>
                      Reason: {diagram.moderation_reason}
                    </span>
                  </div>
                </div>

                <div class="flex items-center gap-2 shrink-0">
                  <button
                    type="button"
                    class="btn btn-sm btn-ghost"
                    phx-click="preview"
                    phx-value-id={diagram.id}
                  >
                    <Backpex.HTML.CoreComponents.icon name="hero-eye" class="size-4" /> Preview
                  </button>
                  <button
                    type="button"
                    class="btn btn-sm btn-success"
                    phx-click="approve"
                    phx-value-id={diagram.id}
                  >
                    <Backpex.HTML.CoreComponents.icon name="hero-check" class="size-4" /> Approve
                  </button>
                  <button
                    type="button"
                    class="btn btn-sm btn-error"
                    phx-click="reject"
                    phx-value-id={diagram.id}
                  >
                    <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="size-4" /> Reject
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Reject Modal -->
        <div
          :if={@reject_diagram_id}
          id="reject-modal"
          class="modal modal-open"
          phx-window-keydown="close_modal"
          phx-key="escape"
        >
          <div class="modal-box">
            <h3 class="font-bold text-lg">Reject Diagram</h3>
            <p class="py-4 text-base-content/70">
              This diagram will be rejected and made private. Please provide a reason.
            </p>
            <.form for={@reject_form} phx-submit="confirm_reject">
              <input type="hidden" name="diagram_id" value={@reject_diagram_id} />
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Reason for rejection</span>
                </label>
                <textarea
                  name="reason"
                  class="textarea textarea-bordered"
                  rows="3"
                  required
                >Violates service policy.</textarea>
              </div>
              <div class="modal-action">
                <button type="button" class="btn" phx-click="close_modal">Cancel</button>
                <button type="submit" class="btn btn-error">Reject</button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close_modal"></div>
        </div>
        
    <!-- Preview Modal -->
        <div
          :if={@preview_diagram}
          id="preview-modal"
          class="modal modal-open"
          phx-window-keydown="close_preview"
          phx-key="escape"
        >
          <div class="modal-box max-w-4xl">
            <h3 class="font-bold text-lg">{@preview_diagram.title}</h3>
            <div class="py-4">
              <div class="space-y-4">
                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Summary</h4>
                  <p class="mt-1">{@preview_diagram.summary || "No summary"}</p>
                </div>
                <div>
                  <h4 class="text-sm font-medium text-base-content/70">Diagram Source</h4>
                  <pre class="mt-1 p-4 bg-base-200 rounded-lg text-sm overflow-x-auto max-h-96"><code>{@preview_diagram.diagram_source}</code></pre>
                </div>
                <div :if={@preview_diagram.moderation_reason}>
                  <h4 class="text-sm font-medium text-base-content/70">AI Moderation Reason</h4>
                  <p class="mt-1 text-warning">{@preview_diagram.moderation_reason}</p>
                </div>
              </div>
            </div>
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_preview">Close</button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close_preview"></div>
        </div>
      </div>
    </Backpex.HTML.Layout.app_shell>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Moderation Queue")
     |> assign(:current_url, ~p"/admin/moderation")
     |> assign(:reject_form, to_form(%{}))
     |> assign(:reject_diagram_id, nil)
     |> assign(:preview_diagram, nil)
     |> load_data()}
  end

  @impl true
  def handle_event("approve", %{"id" => diagram_id}, socket) do
    diagram = Repo.get!(Diagram, diagram_id)
    admin_id = socket.assigns.current_user.id

    case Content.admin_approve(diagram, admin_id) do
      {:ok, _diagram} ->
        {:noreply,
         socket
         |> put_flash(:info, "Diagram approved successfully")
         |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve diagram")}
    end
  end

  def handle_event("reject", %{"id" => diagram_id}, socket) do
    {:noreply, assign(socket, :reject_diagram_id, diagram_id)}
  end

  def handle_event("confirm_reject", %{"diagram_id" => diagram_id, "reason" => reason}, socket) do
    diagram = Repo.get!(Diagram, diagram_id)
    admin_id = socket.assigns.current_user.id

    case Content.admin_reject(diagram, admin_id, reason) do
      {:ok, _diagram} ->
        {:noreply,
         socket
         |> assign(:reject_diagram_id, nil)
         |> put_flash(:info, "Diagram rejected and made private")
         |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject diagram")}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :reject_diagram_id, nil)}
  end

  def handle_event("preview", %{"id" => diagram_id}, socket) do
    diagram = Repo.get!(Diagram, diagram_id)
    {:noreply, assign(socket, :preview_diagram, diagram)}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview_diagram, nil)}
  end

  defp load_data(socket) do
    socket
    |> assign(:stats, Content.get_moderation_stats())
    |> assign(:diagrams, Content.list_pending_review())
    |> assign(:pending_count, Content.get_moderation_stats().manual_review)
  end
end

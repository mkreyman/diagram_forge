defmodule DiagramForgeWeb.Admin.PromptEditLive do
  @moduledoc """
  Admin page for editing an AI prompt.
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.AI
  alias DiagramForge.AI.Prompt

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
        <div class="flex items-center gap-4">
          <.link navigate={~p"/admin/prompts"} class="btn btn-ghost btn-sm">
            <Backpex.HTML.CoreComponents.icon name="hero-arrow-left" class="size-4" /> Back
          </.link>
          <div>
            <h1 class="text-2xl font-bold text-base-content">Edit Prompt</h1>
            <p class="mt-1 text-sm text-base-content/70">{@prompt_data.description}</p>
          </div>
        </div>

        <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
          <div class="flex items-center gap-3 mb-6">
            <h3 class="text-lg font-semibold text-base-content">{@prompt_data.key}</h3>
            <span class={[
              "text-xs px-2 py-0.5 rounded font-medium",
              @prompt_data.source == :default && "bg-base-200 text-base-content/70",
              @prompt_data.source == :database && "bg-primary/10 text-primary"
            ]}>
              {if @prompt_data.source == :default, do: "Default", else: "Customized"}
            </span>
          </div>

          <.form
            for={@form}
            phx-submit="save"
            phx-change="validate"
            id="prompt-form"
            class="space-y-6"
          >
            <div>
              <label class="label">
                <span class="label-text font-medium">Content</span>
              </label>
              <textarea
                name={@form[:content].name}
                id={@form[:content].id}
                rows="20"
                class={[
                  "textarea textarea-bordered w-full font-mono text-sm",
                  @form[:content].errors != [] && "textarea-error"
                ]}
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:content].value)}</textarea>
              <p
                :for={msg <- Enum.map(@form[:content].errors, &translate_error/1)}
                class="text-sm text-error mt-1"
              >
                {msg}
              </p>
            </div>

            <div class="flex gap-4">
              <button type="submit" class="btn btn-primary">
                <Backpex.HTML.CoreComponents.icon name="hero-check" class="size-4" /> Save Changes
              </button>
              <.link navigate={~p"/admin/prompts"} class="btn btn-ghost">
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </div>
    </Backpex.HTML.Layout.app_shell>
    """
  end

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    prompt_data = AI.get_prompt_with_status(key)

    form =
      case prompt_data.db_record do
        nil ->
          %Prompt{key: key, content: prompt_data.content, description: prompt_data.description}
          |> Prompt.changeset(%{})
          |> to_form()

        record ->
          record |> Prompt.changeset(%{}) |> to_form()
      end

    {:ok,
     socket
     |> assign(:page_title, "Edit Prompt - #{key}")
     |> assign(:current_url, ~p"/admin/prompts")
     |> assign(:prompt_data, prompt_data)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"prompt" => params}, socket) do
    form =
      case socket.assigns.prompt_data.db_record do
        nil ->
          %Prompt{key: socket.assigns.prompt_data.key}
          |> Prompt.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()

        record ->
          record
          |> Prompt.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()
      end

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"prompt" => params}, socket) do
    result =
      case socket.assigns.prompt_data.db_record do
        nil ->
          AI.create_prompt(Map.put(params, "key", socket.assigns.prompt_data.key))

        record ->
          AI.update_prompt(record, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt saved successfully.")
         |> push_navigate(to: ~p"/admin/prompts")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end

defmodule DiagramForgeWeb.DiagramStudioLive do
  @moduledoc """
  Main LiveView for the Diagram Studio.

  Two-column layout:
  - Left sidebar: Tag filtering, saved filters, and diagrams list
  - Right main area: Large diagram display and generate from prompt
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.Workers.ProcessDocumentJob

  on_mount DiagramForgeWeb.UserLive

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "documents")
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "diagrams")
      # Schedule periodic document refresh to auto-hide completed documents after 5 minutes
      schedule_document_refresh()
    end

    current_user = socket.assigns[:current_user]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:documents, list_documents())
      |> assign(:selected_document, nil)
      |> assign(:active_tag_filter, [])
      |> assign(:available_tags, [])
      |> assign(:tag_counts, %{})
      |> assign(:pinned_filters, [])
      |> assign(:owned_diagrams, [])
      |> assign(:bookmarked_diagrams, [])
      |> assign(:public_diagrams, [])
      |> assign(:selected_diagram, nil)
      |> assign(:generated_diagram, nil)
      |> assign(:prompt, "")
      |> assign(:uploaded_files, [])
      |> assign(:generating, false)
      |> assign(:diagram_theme, "dark")
      |> assign(:show_save_filter_modal, false)
      |> assign(:editing_filter, nil)
      |> assign(:editing_diagram, nil)
      |> assign(:new_tag_input, "")
      |> load_diagrams()
      |> load_tags()
      |> load_filters()
      |> allow_upload(:document,
        accept: ~w(.pdf .md .markdown),
        max_entries: 1,
        max_file_size: 50_000_000
      )

    # Handle permalink access via /d/:id
    socket =
      case params do
        %{"id" => id} ->
          try do
            diagram = Diagrams.get_diagram!(id)

            if Diagrams.can_view_diagram?(diagram, current_user) do
              socket |> assign(:selected_diagram, diagram)
            else
              socket
              |> put_flash(:error, "You don't have permission to view this diagram")
              |> push_navigate(to: "/")
            end
          rescue
            Ecto.NoResultsError ->
              socket
              |> put_flash(:error, "Diagram not found")
              |> push_navigate(to: "/")
          end

        _ ->
          socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    diagram_id = params["id"]

    # If diagram ID is provided, load the diagram and set it as selected
    socket =
      if diagram_id do
        try do
          diagram = Diagrams.get_diagram!(diagram_id)

          socket
          |> assign(:selected_diagram, diagram)
          |> assign(:generated_diagram, nil)
        rescue
          Ecto.NoResultsError ->
            socket
            |> put_flash(:error, "Diagram not found")
            |> push_navigate(to: ~p"/")
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # Tag filtering events

  @impl true
  def handle_event("add_tag_to_filter", %{"tag" => tag}, socket) do
    current_filter = socket.assigns.active_tag_filter
    new_filter = (current_filter ++ [tag]) |> Enum.uniq()

    socket =
      socket
      |> assign(:active_tag_filter, new_filter)
      |> assign(:new_tag_input, "")
      |> load_diagrams()

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_tag_from_filter", %{"tag" => tag}, socket) do
    current_filter = socket.assigns.active_tag_filter
    new_filter = current_filter -- [tag]

    socket =
      socket
      |> assign(:active_tag_filter, new_filter)
      |> load_diagrams()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    socket =
      socket
      |> assign(:active_tag_filter, [])
      |> load_diagrams()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_tag_input", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :new_tag_input, tag)}
  end

  # Saved filter events

  @impl true
  def handle_event("apply_saved_filter", %{"id" => filter_id}, socket) do
    filter = Diagrams.get_saved_filter!(filter_id)

    socket =
      socket
      |> assign(:active_tag_filter, filter.tag_filter)
      |> load_diagrams()

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_save_filter_modal", _params, socket) do
    {:noreply, assign(socket, :show_save_filter_modal, true)}
  end

  @impl true
  def handle_event("hide_save_filter_modal", _params, socket) do
    {:noreply, assign(socket, :show_save_filter_modal, false)}
  end

  @impl true
  def handle_event("save_current_filter", %{"name" => name}, socket) do
    user_id = socket.assigns.current_user.id
    tag_filter = socket.assigns.active_tag_filter

    case Diagrams.create_saved_filter(%{name: name, tag_filter: tag_filter}, user_id) do
      {:ok, _filter} ->
        socket =
          socket
          |> assign(:show_save_filter_modal, false)
          |> load_filters()
          |> put_flash(:info, "Filter saved successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save filter")}
    end
  end

  @impl true
  def handle_event("delete_filter", %{"id" => id}, socket) do
    filter = Diagrams.get_saved_filter!(id)
    user_id = socket.assigns.current_user.id

    case Diagrams.delete_saved_filter(filter, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_filters()
          |> put_flash(:info, "Filter deleted successfully")

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("toggle_filter_pin", %{"id" => id}, socket) do
    filter = Diagrams.get_saved_filter!(id)
    user_id = socket.assigns.current_user.id

    case Diagrams.update_saved_filter(filter, %{is_pinned: !filter.is_pinned}, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_filters()

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  # Tag management on diagrams

  @impl true
  def handle_event("add_tags_to_diagram", %{"id" => id, "tags" => tags_str}, socket) do
    diagram = Diagrams.get_diagram!(id)
    user_id = socket.assigns.current_user.id
    tags = String.split(tags_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    case Diagrams.add_tags(diagram, tags, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_diagrams()
          |> load_tags()
          |> put_flash(:info, "Tags added successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tags")}
    end
  end

  @impl true
  def handle_event("remove_tag_from_diagram", %{"id" => id, "tag" => tag}, socket) do
    diagram = Diagrams.get_diagram!(id)
    user_id = socket.assigns.current_user.id

    case Diagrams.remove_tags(diagram, [tag], user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_diagrams()
          |> load_tags()
          |> put_flash(:info, "Tag removed successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove tag")}
    end
  end

  # Fork and bookmark (no concept selection needed)

  @impl true
  def handle_event("fork_diagram", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user.id

    case Diagrams.fork_diagram(id, user_id) do
      {:ok, _forked} ->
        socket =
          socket
          |> load_diagrams()
          |> put_flash(:info, "Diagram forked successfully")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to fork diagram")}
    end
  end

  @impl true
  def handle_event("bookmark_diagram", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user.id

    case Diagrams.bookmark_diagram(id, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_diagrams()
          |> put_flash(:info, "Diagram bookmarked successfully")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to bookmark diagram")}
    end
  end

  @impl true
  def handle_event("remove_bookmark", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user.id

    :ok = Diagrams.remove_diagram_bookmark(id, user_id)

    socket =
      socket
      |> load_diagrams()
      |> put_flash(:info, "Diagram removed from your collection")

    {:noreply, socket}
  end

  # Diagram edit/delete actions

  @impl true
  def handle_event("edit_diagram", %{"id" => id}, socket) do
    diagram = Diagrams.get_diagram!(id)

    if Diagrams.can_edit_diagram?(diagram, socket.assigns.current_user) do
      {:noreply, assign(socket, :editing_diagram, diagram)}
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to edit this diagram")}
    end
  end

  @impl true
  def handle_event("cancel_edit_diagram", _params, socket) do
    {:noreply, assign(socket, :editing_diagram, nil)}
  end

  @impl true
  def handle_event("save_diagram_edit", %{"diagram" => params}, socket) do
    diagram = socket.assigns.editing_diagram
    user_id = socket.assigns.current_user.id

    # Convert tags from comma-separated string to array if present
    params =
      if tags_str = params["tags"] do
        tags = String.split(tags_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "tags", tags)
      else
        params
      end

    # Convert visibility to atom if present
    params =
      if visibility = params["visibility"] do
        Map.put(params, "visibility", String.to_existing_atom(visibility))
      else
        params
      end

    case Diagrams.update_diagram(diagram, params, user_id) do
      {:ok, updated} ->
        socket =
          socket
          |> assign(:editing_diagram, nil)
          |> assign(:selected_diagram, updated)
          |> load_diagrams()
          |> load_tags()
          |> put_flash(:info, "Diagram updated successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :diagram_changeset, changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("delete_diagram", %{"id" => id}, socket) do
    diagram = Diagrams.get_diagram!(id)
    user_id = socket.assigns.current_user.id

    case Diagrams.delete_diagram(diagram, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:selected_diagram, nil)
          |> load_diagrams()
          |> put_flash(:info, "Diagram deleted successfully")

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("change_visibility", %{"id" => id, "visibility" => visibility}, socket) do
    diagram = Diagrams.get_diagram!(id)
    user_id = socket.assigns.current_user.id
    visibility_atom = String.to_existing_atom(visibility)

    case Diagrams.update_diagram(diagram, %{visibility: visibility_atom}, user_id) do
      {:ok, updated} ->
        socket =
          socket
          |> assign(:selected_diagram, updated)
          |> load_diagrams()
          |> put_flash(:info, "Visibility updated to #{visibility}")

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  # Filter management handlers

  @impl true
  def handle_event("edit_filter", %{"id" => id}, socket) do
    filter = Diagrams.get_saved_filter!(id)
    {:noreply, assign(socket, :editing_filter, filter)}
  end

  @impl true
  def handle_event("cancel_edit_filter", _params, socket) do
    {:noreply, assign(socket, :editing_filter, nil)}
  end

  @impl true
  def handle_event("save_filter_edit", %{"filter" => params}, socket) do
    filter = socket.assigns.editing_filter
    user_id = socket.assigns.current_user.id

    # Convert tags from comma-separated string to array if present
    params =
      if tags_str = params["tags"] do
        tags = String.split(tags_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "tags", tags)
      else
        params
      end

    case Diagrams.update_saved_filter(filter, params, user_id) do
      {:ok, _updated} ->
        socket =
          socket
          |> assign(:editing_filter, nil)
          |> load_filters()
          |> put_flash(:info, "Filter updated successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :filter_changeset, changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("reorder_filters", %{"ids" => ids}, socket) do
    user_id = socket.assigns.current_user.id

    case Diagrams.reorder_saved_filters(ids, user_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_filters()

        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  # Other event handlers

  @impl true
  def handle_event("toggle_public_diagrams", _params, socket) do
    current_user = socket.assigns.current_user
    new_value = !current_user.show_public_diagrams

    case Diagrams.update_user_public_diagrams_preference(current_user, new_value) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> load_diagrams()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  @impl true
  def handle_event("toggle_diagram_theme", _params, socket) do
    new_theme = if socket.assigns.diagram_theme == "light", do: "dark", else: "light"
    {:noreply, assign(socket, :diagram_theme, new_theme)}
  end

  @impl true
  def handle_event("copy_share_link", _params, socket) do
    case socket.assigns[:selected_diagram] do
      nil ->
        {:noreply, put_flash(socket, :error, "No diagram selected")}

      diagram ->
        url = url(~p"/d/#{diagram.id}")
        {:noreply, push_event(socket, "copy-to-clipboard", %{text: url})}
    end
  end

  @impl true
  def handle_event("select_diagram", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/d/#{id}")}
  end

  @impl true
  def handle_event("update_prompt", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :prompt, prompt)}
  end

  @impl true
  def handle_event("generate_from_prompt", _params, socket) do
    prompt = String.trim(socket.assigns.prompt)

    if prompt == "" do
      {:noreply, put_flash(socket, :error, "Please enter a prompt")}
    else
      # Set generating state and send async message for actual generation
      send(self(), {:do_generate_from_prompt, prompt})

      {:noreply,
       socket
       |> assign(:generating, true)
       |> assign(:prompt, "")}
    end
  end

  @impl true
  def handle_event("save_generated_diagram", _params, socket) do
    cond do
      is_nil(socket.assigns[:current_user]) ->
        diagram = socket.assigns.generated_diagram

        # Extract diagram attributes for session storage
        attrs = %{
          title: diagram.title,
          slug: diagram.slug,
          diagram_source: diagram.diagram_source,
          summary: diagram.summary,
          notes_md: diagram.notes_md,
          tags: diagram.tags
        }

        # Encode attrs as JSON to pass via query parameter
        pending_json = Jason.encode!(attrs)

        {:noreply,
         socket
         |> put_flash(:info, "Sign in to save your diagram")
         |> redirect(to: "/auth/github?pending_diagram=#{URI.encode_www_form(pending_json)}")}

      is_nil(socket.assigns.generated_diagram) ->
        {:noreply, put_flash(socket, :error, "No diagram to save")}

      true ->
        diagram = socket.assigns.generated_diagram
        current_user = socket.assigns.current_user

        # Extract diagram attributes
        attrs = %{
          title: diagram.title,
          slug: diagram.slug,
          diagram_source: diagram.diagram_source,
          summary: diagram.summary,
          notes_md: diagram.notes_md,
          tags: diagram.tags || []
        }

        case Diagrams.create_diagram_for_user(attrs, current_user.id) do
          {:ok, saved_diagram} ->
            {:noreply,
             socket
             |> assign(:generated_diagram, nil)
             |> assign(:selected_diagram, saved_diagram)
             |> load_diagrams()
             |> put_flash(:info, "Diagram saved successfully!")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save diagram")}
        end
    end
  end

  @impl true
  def handle_event("discard_generated_diagram", _params, socket) do
    {:noreply,
     socket
     |> assign(:generated_diagram, nil)
     |> assign(:selected_diagram, nil)
     |> put_flash(:info, "Diagram discarded")}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        dest = Path.join([System.tmp_dir(), "#{entry.uuid}#{Path.extname(entry.client_name)}"])
        File.cp!(path, dest)

        source_type =
          case Path.extname(entry.client_name) do
            ".pdf" -> :pdf
            _ -> :markdown
          end

        attrs = %{
          title: Path.basename(entry.client_name, Path.extname(entry.client_name)),
          source_type: source_type,
          path: dest
        }

        user_id = socket.assigns.current_user.id

        case Diagrams.create_document(attrs, user_id) do
          {:ok, document} ->
            %{"document_id" => document.id}
            |> ProcessDocumentJob.new()
            |> Oban.insert()

            {:ok, document}

          {:error, _changeset} ->
            {:postpone, :error}
        end
      end)

    {:noreply,
     socket
     |> assign(:documents, list_documents())
     |> put_flash(:info, "Uploaded #{length(uploaded_files)} file(s)")}
  end

  # PubSub and async message handlers

  @impl true
  def handle_info({:do_generate_from_prompt, prompt}, socket) do
    case Diagrams.generate_diagram_from_prompt(prompt, []) do
      {:ok, diagram} ->
        {:noreply,
         socket
         |> assign(:selected_diagram, diagram)
         |> assign(:generated_diagram, diagram)
         |> assign(:generating, false)
         |> put_flash(:info, "Diagram generated! Click Save to persist it.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:generating, false)
         |> put_flash(:error, "Failed to generate diagram: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:document_updated, _document_id}, socket) do
    {:noreply, assign(socket, :documents, list_documents())}
  end

  @impl true
  def handle_info({:diagram_created, _diagram_id}, socket) do
    {:noreply, socket |> load_diagrams()}
  end

  @impl true
  def handle_info(:refresh_documents, socket) do
    # Reload documents to auto-hide completed documents after 5 minutes
    documents = list_documents()

    # Schedule the next refresh
    schedule_document_refresh()

    {:noreply, assign(socket, :documents, documents)}
  end

  # Private helper functions

  defp load_diagrams(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    tag_filter = socket.assigns[:active_tag_filter] || []

    if user_id do
      owned = Diagrams.list_diagrams_by_tags(user_id, tag_filter, :owned)
      bookmarked = Diagrams.list_diagrams_by_tags(user_id, tag_filter, :bookmarked)

      public =
        if socket.assigns.current_user.show_public_diagrams do
          Diagrams.list_public_diagrams()
        else
          []
        end

      socket
      |> assign(:owned_diagrams, owned)
      |> assign(:bookmarked_diagrams, bookmarked)
      |> assign(:public_diagrams, public)
    else
      socket
      |> assign(:owned_diagrams, [])
      |> assign(:bookmarked_diagrams, [])
      |> assign(:public_diagrams, [])
    end
  end

  defp load_tags(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id

    if user_id do
      socket
      |> assign(:available_tags, Diagrams.list_available_tags(user_id))
      |> assign(:tag_counts, Diagrams.get_tag_counts(user_id))
    else
      socket
    end
  end

  defp load_filters(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id

    if user_id do
      assign(socket, :pinned_filters, Diagrams.list_pinned_filters(user_id))
    else
      socket
    end
  end

  defp list_documents do
    Diagrams.list_documents()
  end

  defp schedule_document_refresh do
    # Refresh documents every minute to auto-hide completed documents after 5 minutes
    Process.send_after(self(), :refresh_documents, 60_000)
  end

  defp format_status(status) do
    case status do
      :uploaded -> "Uploaded"
      :processing -> "Processing..."
      :ready -> "Ready"
      :error -> "Error"
      _ -> to_string(status)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <%!-- Top Navbar --%>
      <div class="bg-slate-900 border-b border-slate-800">
        <div class="container mx-auto px-4 py-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <img src={~p"/images/logo.png"} alt="DiagramForge" class="h-10 w-10" />
              <h1 class="text-xl font-bold text-slate-100">DiagramForge Studio</h1>
            </div>
            <div class="flex items-center gap-4">
              <%= if @current_user do %>
                <div class="flex items-center gap-3">
                  <%= if @current_user.avatar_url do %>
                    <img
                      src={@current_user.avatar_url}
                      alt={@current_user.name || @current_user.email}
                      class="w-8 h-8 rounded-full"
                    />
                  <% end %>
                  <span class="text-sm text-slate-300">
                    {@current_user.name || @current_user.email}
                  </span>
                  <%= if @is_superadmin do %>
                    <span class="px-2 py-1 text-xs bg-purple-600 text-white rounded">
                      Admin
                    </span>
                  <% end %>
                  <.link
                    href="/auth/logout"
                    class="px-3 py-1.5 text-sm bg-slate-800 hover:bg-slate-700 text-slate-300 rounded transition"
                  >
                    Sign Out
                  </.link>
                </div>
              <% else %>
                <.link
                  href="/auth/github"
                  class="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-white rounded transition flex items-center gap-2"
                >
                  <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                  </svg>
                  Sign in with GitHub
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- Flash messages --%>
      <div class="container mx-auto px-4 pt-4">
        <%= if msg = Phoenix.Flash.get(@flash, :info) do %>
          <div
            id="diagram-studio-flash-info"
            class="mb-4 p-4 bg-blue-900/30 border border-blue-700/50 rounded-lg text-blue-200 flex items-center gap-3"
            phx-click={
              JS.push("lv:clear-flash", value: %{key: :info})
              |> JS.hide(to: "#diagram-studio-flash-info")
            }
          >
            <svg class="w-5 h-5 shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clip-rule="evenodd"
              />
            </svg>
            <p class="flex-1">{msg}</p>
            <button type="button" class="text-blue-400 hover:text-blue-300" aria-label="close">
              ✕
            </button>
          </div>
        <% end %>
        <%= if msg = Phoenix.Flash.get(@flash, :error) do %>
          <div
            id="diagram-studio-flash-error"
            class="mb-4 p-4 bg-red-900/30 border border-red-700/50 rounded-lg text-red-200 flex items-center gap-3"
            phx-click={
              JS.push("lv:clear-flash", value: %{key: :error})
              |> JS.hide(to: "#diagram-studio-flash-error")
            }
          >
            <svg class="w-5 h-5 shrink-0" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                clip-rule="evenodd"
              />
            </svg>
            <p class="flex-1">{msg}</p>
            <button type="button" class="text-red-400 hover:text-red-300" aria-label="close">
              ✕
            </button>
          </div>
        <% end %>
      </div>

      <div class="container mx-auto px-4 py-4 flex-1 flex flex-col">
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6 flex-1">
          <%!-- Left Sidebar --%>
          <div class="lg:col-span-1 flex flex-col gap-3">
            <%!-- Documents Section --%>
            <div class="bg-slate-900 rounded-xl p-3">
              <h2 class="text-lg font-semibold mb-2">Source Documents</h2>

              <form phx-change="validate" phx-submit="save" id="upload-form">
                <div class="space-y-2 mb-3">
                  <div
                    class="border-2 border-dashed border-slate-700 rounded-lg p-4 text-center cursor-pointer hover:border-slate-600 transition"
                    phx-drop-target={@uploads.document.ref}
                  >
                    <.live_file_input upload={@uploads.document} class="hidden" />
                    <label for={@uploads.document.ref} class="cursor-pointer">
                      <div class="text-slate-400">
                        <p class="text-xs">Click or drag PDF/MD</p>
                      </div>
                    </label>
                  </div>

                  <%= for entry <- @uploads.document.entries do %>
                    <div class="text-xs text-slate-300">
                      {entry.client_name}
                    </div>
                  <% end %>

                  <button
                    type="submit"
                    class="w-full px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 rounded transition"
                    disabled={@uploads.document.entries == []}
                  >
                    Upload
                  </button>
                </div>
              </form>

              <div class="space-y-0.5 max-h-48 overflow-y-auto">
                <%= for doc <- @documents do %>
                  <div class="px-2 py-1 rounded bg-slate-800/50">
                    <div class="flex items-center justify-between">
                      <span class="text-xs font-medium truncate">{doc.title}</span>
                      <span class={[
                        "text-xs px-1.5 py-0.5 rounded font-medium",
                        doc.status == :ready && "bg-green-900/50 text-green-300",
                        doc.status == :processing &&
                          "bg-yellow-900/50 text-yellow-300 animate-pulse",
                        doc.status == :uploaded && "bg-blue-900/50 text-blue-300",
                        doc.status == :error && "bg-red-900/50 text-red-300"
                      ]}>
                        {format_status(doc.status)}
                      </span>
                    </div>
                    <%= if doc.status == :error and doc.error_message do %>
                      <div class="text-xs text-red-400 mt-1">
                        {doc.error_message}
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @documents == [] do %>
                  <p class="text-xs text-slate-400 text-center py-4">No documents yet</p>
                <% end %>
              </div>
            </div>

            <%!-- Diagrams Section --%>
            <div class="bg-slate-900 rounded-xl p-4 flex flex-col overflow-hidden">
              <%!-- Tag Filter Input --%>
              <div class="mb-3">
                <form phx-submit="add_tag_to_filter" class="w-full">
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="tag"
                      value={@new_tag_input}
                      placeholder="Filter by tag..."
                      phx-change="update_tag_input"
                      list="tag-suggestions"
                      class="flex-1 px-3 py-2 text-sm bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                    />
                    <datalist id="tag-suggestions">
                      <%= for tag <- @available_tags do %>
                        <option value={tag}>{tag}</option>
                      <% end %>
                    </datalist>
                    <button
                      type="submit"
                      class="px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 rounded transition"
                    >
                      Add
                    </button>
                  </div>
                </form>
              </div>

              <%!-- Active Filter Chips --%>
              <%= if @active_tag_filter != [] do %>
                <div class="flex flex-wrap gap-2 mb-3">
                  <%= for tag <- @active_tag_filter do %>
                    <div class="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
                      <span>{tag}</span>
                      <button
                        type="button"
                        phx-click="remove_tag_from_filter"
                        phx-value-tag={tag}
                        class="hover:bg-blue-200 rounded-full p-0.5"
                      >
                        ✕
                      </button>
                    </div>
                  <% end %>
                  <button
                    type="button"
                    phx-click="clear_filter"
                    class="text-sm text-slate-400 hover:text-slate-300"
                  >
                    Clear all
                  </button>
                </div>
              <% end %>

              <%!-- Save Current Filter Button --%>
              <%= if @current_user && @active_tag_filter != [] do %>
                <button
                  phx-click="show_save_filter_modal"
                  class="mb-3 px-3 py-2 text-sm bg-green-600 hover:bg-green-700 rounded transition"
                >
                  Save Current Filter
                </button>
              <% end %>

              <%!-- Pinned Filters Section --%>
              <%= if @pinned_filters != [] do %>
                <div class="mb-3 pb-3 border-b border-slate-800">
                  <h3 class="text-sm font-semibold mb-2 text-slate-400">PINNED FILTERS</h3>
                  <%= for filter <- @pinned_filters do %>
                    <% count = Diagrams.get_saved_filter_count(@current_user.id, filter) %>
                    <div class="flex items-center justify-between py-2 px-3 hover:bg-slate-800/50 rounded group mb-1">
                      <button
                        type="button"
                        phx-click="apply_saved_filter"
                        phx-value-id={filter.id}
                        class="flex-1 flex items-center gap-2 text-left text-sm"
                      >
                        <span class="font-medium">{filter.name}</span>
                        <span class="text-xs text-slate-500">({count})</span>
                      </button>
                      <div class="flex gap-1">
                        <button
                          type="button"
                          phx-click="edit_filter"
                          phx-value-id={filter.id}
                          class="p-1 hover:bg-blue-900/50 rounded text-xs text-blue-400"
                          title="Edit"
                        >
                          ✏️
                        </button>
                        <button
                          type="button"
                          phx-click="toggle_filter_pin"
                          phx-value-id={filter.id}
                          class="p-1 hover:bg-slate-700 rounded text-xs"
                          title="Unpin"
                        >
                          📌
                        </button>
                        <button
                          type="button"
                          phx-click="delete_filter"
                          phx-value-id={filter.id}
                          data-confirm="Delete this filter?"
                          class="p-1 hover:bg-red-900/50 rounded text-xs text-red-400"
                          title="Delete"
                        >
                          🗑
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- MY DIAGRAMS Section --%>
              <div class="mb-4">
                <h2 class="text-lg font-semibold mb-2 text-slate-300">
                  MY DIAGRAMS ({length(@owned_diagrams)})
                </h2>
                <div class="space-y-2 max-h-64 overflow-y-auto">
                  <%= for diagram <- @owned_diagrams do %>
                    <div
                      class={[
                        "p-3 rounded-lg border transition cursor-pointer",
                        @selected_diagram && @selected_diagram.id == diagram.id &&
                          "bg-blue-900/30 border-blue-500",
                        (!@selected_diagram || @selected_diagram.id != diagram.id) &&
                          "border-slate-700 hover:bg-slate-800/50"
                      ]}
                      phx-click="select_diagram"
                      phx-value-id={diagram.id}
                    >
                      <h3 class="font-medium text-sm mb-1">{diagram.title}</h3>
                      <div class="flex flex-wrap gap-1">
                        <%= for tag <- diagram.tags do %>
                          <span class="text-xs px-2 py-0.5 bg-slate-700 rounded">
                            {tag}
                          </span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                  <%= if @owned_diagrams == [] do %>
                    <p class="text-sm text-slate-400 text-center py-4">
                      No diagrams yet. Upload a document or generate from prompt.
                    </p>
                  <% end %>
                </div>
              </div>

              <%!-- FORKED DIAGRAMS Section --%>
              <%= if @bookmarked_diagrams != [] do %>
                <div class="mb-4 border-t border-slate-800 pt-4">
                  <h2 class="text-lg font-semibold mb-2 text-slate-300">
                    FORKED DIAGRAMS ({length(@bookmarked_diagrams)})
                  </h2>
                  <div class="space-y-2 max-h-64 overflow-y-auto">
                    <%= for diagram <- @bookmarked_diagrams do %>
                      <div
                        class={[
                          "p-3 rounded-lg border transition cursor-pointer",
                          @selected_diagram && @selected_diagram.id == diagram.id &&
                            "bg-blue-900/30 border-blue-500",
                          (!@selected_diagram || @selected_diagram.id != diagram.id) &&
                            "border-slate-700 hover:bg-slate-800/50"
                        ]}
                        phx-click="select_diagram"
                        phx-value-id={diagram.id}
                      >
                        <h3 class="font-medium text-sm mb-1">{diagram.title}</h3>
                        <div class="flex flex-wrap gap-1">
                          <%= for tag <- diagram.tags do %>
                            <span class="text-xs px-2 py-0.5 bg-slate-700 rounded">
                              {tag}
                            </span>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- PUBLIC DIAGRAMS Section --%>
              <%= if @current_user do %>
                <div class="border-t border-slate-800 pt-4">
                  <div class="flex items-center justify-between mb-2">
                    <h2 class="text-lg font-semibold text-slate-300">
                      PUBLIC DIAGRAMS
                    </h2>
                    <button
                      phx-click="toggle_public_diagrams"
                      class={[
                        "px-2 py-1 text-xs rounded transition",
                        @current_user.show_public_diagrams &&
                          "bg-green-600 hover:bg-green-700",
                        !@current_user.show_public_diagrams && "bg-slate-700 hover:bg-slate-600"
                      ]}
                    >
                      <%= if @current_user.show_public_diagrams do %>
                        Hide
                      <% else %>
                        Show
                      <% end %>
                    </button>
                  </div>

                  <%= if @current_user.show_public_diagrams do %>
                    <div class="space-y-2 max-h-64 overflow-y-auto">
                      <%= for diagram <- @public_diagrams do %>
                        <div
                          class={[
                            "p-3 rounded-lg border transition cursor-pointer",
                            @selected_diagram && @selected_diagram.id == diagram.id &&
                              "bg-blue-900/30 border-blue-500",
                            (!@selected_diagram || @selected_diagram.id != diagram.id) &&
                              "border-slate-700 hover:bg-slate-800/50"
                          ]}
                          phx-click="select_diagram"
                          phx-value-id={diagram.id}
                        >
                          <h3 class="font-medium text-sm mb-1">{diagram.title}</h3>
                          <div class="flex flex-wrap gap-1">
                            <%= for tag <- diagram.tags do %>
                              <span class="text-xs px-2 py-0.5 bg-slate-700 rounded">
                                {tag}
                              </span>
                            <% end %>
                          </div>
                        </div>
                      <% end %>

                      <%= if @public_diagrams == [] do %>
                        <p class="text-sm text-slate-400 text-center py-4">
                          No public diagrams available
                        </p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Right Main Area: Diagram Display + Generate --%>
          <div class="lg:col-span-3 space-y-4 flex flex-col">
            <%!-- Diagram Display --%>
            <div class="bg-slate-900 rounded-xl p-6 flex-1 overflow-auto">
              <%= if @selected_diagram do %>
                <div class="space-y-4">
                  <%!-- Visibility Banner --%>
                  <div class={[
                    "px-4 py-2 rounded-lg border flex items-center justify-between",
                    @selected_diagram.visibility == :private && "bg-red-900/20 border-red-700/50",
                    @selected_diagram.visibility == :unlisted &&
                      "bg-yellow-900/20 border-yellow-700/50",
                    @selected_diagram.visibility == :public && "bg-green-900/20 border-green-700/50"
                  ]}>
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-medium">
                        Visibility:
                        <%= case @selected_diagram.visibility do %>
                          <% :private -> %>
                            <span class="text-red-400">Private</span> - Only you can view
                          <% :unlisted -> %>
                            <span class="text-yellow-400">Unlisted</span> - Anyone with the link
                          <% :public -> %>
                            <span class="text-green-400">Public</span> - Discoverable by all
                        <% end %>
                      </span>
                    </div>
                  </div>

                  <div class="grid grid-cols-2 gap-6">
                    <div>
                      <h2 class="text-2xl font-semibold mb-2">{@selected_diagram.title}</h2>
                      <p class="text-slate-300 mb-2">{@selected_diagram.summary}</p>
                      <p class="text-sm text-slate-400 mb-2">
                        Source:
                        <%= if @selected_diagram.document_id && @selected_diagram.document do %>
                          {@selected_diagram.document.title}
                        <% else %>
                          User prompt
                        <% end %>
                      </p>
                      <div class="flex gap-2 mt-2 flex-wrap">
                        <%= for tag <- @selected_diagram.tags do %>
                          <span class="text-xs px-2 py-1 bg-slate-700 rounded">
                            {tag}
                          </span>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex flex-col justify-between">
                      <%= if @selected_diagram.notes_md do %>
                        <div class="text-sm text-slate-400">
                          <div class="font-semibold text-slate-300 mb-1.5">Notes</div>
                          <div class="overflow-y-auto max-h-24 [&_ul]:list-disc [&_ul]:pl-5 [&_ul]:space-y-0.5 [&_li]:ml-0">
                            {raw(markdown_to_html(@selected_diagram.notes_md))}
                          </div>
                        </div>
                      <% end %>

                      <div class="flex flex-wrap gap-2 mt-3">
                        <button
                          phx-click="toggle_diagram_theme"
                          class="px-3 py-1 text-xs bg-slate-800 hover:bg-slate-700 text-slate-300 rounded transition whitespace-nowrap"
                        >
                          <%= if @diagram_theme == "light" do %>
                            Theme: Black on White
                          <% else %>
                            Theme: White on Black
                          <% end %>
                        </button>

                        <button
                          phx-click="copy_share_link"
                          phx-hook="CopyToClipboard"
                          id="copy-share-link-btn"
                          class="px-3 py-1 text-xs bg-cyan-800 hover:bg-cyan-700 text-white rounded transition whitespace-nowrap"
                        >
                          Copy Share Link
                        </button>

                        <%= if @current_user && Diagrams.can_edit_diagram?(@selected_diagram, @current_user) do %>
                          <button
                            phx-click="edit_diagram"
                            phx-value-id={@selected_diagram.id}
                            class="px-3 py-1 text-xs bg-blue-800 hover:bg-blue-700 text-white rounded transition whitespace-nowrap"
                          >
                            Edit
                          </button>

                          <button
                            phx-click="delete_diagram"
                            phx-value-id={@selected_diagram.id}
                            data-confirm="Are you sure you want to delete this diagram?"
                            class="px-3 py-1 text-xs bg-red-800 hover:bg-red-700 text-white rounded transition whitespace-nowrap"
                          >
                            Delete
                          </button>
                        <% end %>

                        <%= if @current_user do %>
                          <%= if Diagrams.user_owns_diagram?(@selected_diagram.id, @current_user.id) do %>
                            <%!-- Owner can fork their own diagram --%>
                            <button
                              phx-click="fork_diagram"
                              phx-value-id={@selected_diagram.id}
                              class="px-3 py-1 text-xs bg-purple-800 hover:bg-purple-700 text-white rounded transition whitespace-nowrap"
                            >
                              Fork
                            </button>
                          <% else %>
                            <%= if Diagrams.user_bookmarked_diagram?(@selected_diagram.id, @current_user.id) do %>
                              <button
                                phx-click="remove_bookmark"
                                phx-value-id={@selected_diagram.id}
                                class="px-3 py-1 text-xs bg-amber-800 hover:bg-amber-700 text-white rounded transition whitespace-nowrap"
                              >
                                Remove Bookmark
                              </button>
                            <% else %>
                              <button
                                phx-click="bookmark_diagram"
                                phx-value-id={@selected_diagram.id}
                                class="px-3 py-1 text-xs bg-green-800 hover:bg-green-700 text-white rounded transition whitespace-nowrap"
                              >
                                Bookmark
                              </button>
                            <% end %>

                            <button
                              phx-click="fork_diagram"
                              phx-value-id={@selected_diagram.id}
                              class="px-3 py-1 text-xs bg-purple-800 hover:bg-purple-700 text-white rounded transition whitespace-nowrap"
                            >
                              Fork
                            </button>
                          <% end %>
                        <% else %>
                          <button
                            phx-click="fork_diagram"
                            phx-value-id={@selected_diagram.id}
                            class="px-3 py-1 text-xs bg-purple-800 hover:bg-purple-700 text-white rounded transition whitespace-nowrap"
                          >
                            Fork
                          </button>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <%= if @generated_diagram do %>
                    <div class="flex gap-3 p-4 bg-blue-900/20 border border-blue-700/50 rounded-lg">
                      <button
                        phx-click="save_generated_diagram"
                        class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition-colors flex-1"
                      >
                        Save Diagram
                      </button>
                      <button
                        phx-click="discard_generated_diagram"
                        class="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-medium transition-colors flex-1"
                      >
                        Discard
                      </button>
                    </div>
                  <% end %>

                  <div
                    id="mermaid-preview"
                    phx-hook="Mermaid"
                    class={[
                      "rounded-lg p-8 transition-colors",
                      @diagram_theme == "light" && "bg-white",
                      @diagram_theme == "dark" && "bg-slate-950"
                    ]}
                    data-diagram={@selected_diagram.diagram_source}
                    data-theme={@diagram_theme}
                  >
                    <pre class="mermaid">{@selected_diagram.diagram_source}</pre>
                  </div>
                </div>
              <% else %>
                <div class="h-full flex items-center justify-center text-slate-500">
                  <div class="text-center">
                    <svg
                      class="mx-auto h-16 w-16 mb-4 opacity-50"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="1.5"
                        d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                      />
                    </svg>
                    <p class="text-lg">Select a diagram to view</p>
                    <p class="text-sm mt-1">Click on a diagram from the sidebar</p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Generate from Prompt --%>
            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-xl font-semibold mb-3">Generate from Prompt</h2>

              <form phx-submit="generate_from_prompt" class="space-y-3">
                <textarea
                  name="prompt"
                  value={@prompt}
                  phx-change="update_prompt"
                  placeholder="e.g., Create a diagram showing how GenServer handles messages"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-slate-600 focus:outline-none resize-y"
                  rows="3"
                  disabled={@generating}
                />

                <button
                  type="submit"
                  class={[
                    "w-full px-4 py-2 rounded transition flex items-center justify-center gap-2",
                    @generating && "bg-purple-800 cursor-wait",
                    !@generating && "bg-purple-600 hover:bg-purple-700"
                  ]}
                  disabled={String.trim(@prompt) == "" or @generating}
                >
                  <%= if @generating do %>
                    <svg
                      class="animate-spin h-5 w-5"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      >
                      </circle>
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      >
                      </path>
                    </svg>
                    <span>Generating...</span>
                  <% else %>
                    <span>Generate Diagram</span>
                  <% end %>
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>

      <%!-- Save Filter Modal --%>
      <%= if @show_save_filter_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-slate-900 rounded-lg p-6 max-w-md w-full mx-4">
            <h2 class="text-xl font-bold mb-4">Save Current Filter</h2>

            <form phx-submit="save_current_filter" class="space-y-4">
              <div>
                <label class="block text-sm font-medium mb-2">Filter Name</label>
                <input
                  type="text"
                  name="name"
                  placeholder="e.g., Interview Prep"
                  required
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                />
              </div>

              <div class="text-sm text-slate-400">
                <p class="mb-1">Current tags:</p>
                <div class="flex flex-wrap gap-2">
                  <%= for tag <- @active_tag_filter do %>
                    <span class="px-2 py-1 bg-slate-700 rounded text-xs">
                      {tag}
                    </span>
                  <% end %>
                </div>
              </div>

              <div class="flex justify-end gap-2 mt-6">
                <button
                  type="button"
                  phx-click="hide_save_filter_modal"
                  class="px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
                >
                  Save Filter
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <%!-- Edit Diagram Modal --%>
      <%= if @editing_diagram do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-slate-900 rounded-lg p-6 max-w-4xl w-full max-h-[90vh] overflow-y-auto mx-4">
            <h2 class="text-2xl font-bold mb-4">Edit Diagram</h2>

            <form phx-submit="save_diagram_edit" id="edit-diagram-form" class="space-y-4">
              <div>
                <label class="block text-sm font-medium mb-2">Title</label>
                <input
                  type="text"
                  name="diagram[title]"
                  value={@editing_diagram.title}
                  required
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Mermaid Source</label>
                <textarea
                  name="diagram[diagram_source]"
                  required
                  rows="15"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none font-mono text-sm"
                >{@editing_diagram.diagram_source}</textarea>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Summary</label>
                <textarea
                  name="diagram[summary]"
                  rows="3"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                >{@editing_diagram.summary}</textarea>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Notes (Markdown)</label>
                <textarea
                  name="diagram[notes_md]"
                  rows="5"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                >{@editing_diagram.notes_md}</textarea>
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Tags (comma-separated)</label>
                <input
                  type="text"
                  name="diagram[tags]"
                  value={Enum.join(@editing_diagram.tags, ", ")}
                  placeholder="elixir, oauth, patterns"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Visibility</label>
                <select
                  name="diagram[visibility]"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                >
                  <option value="private" selected={@editing_diagram.visibility == :private}>
                    Private (only you)
                  </option>
                  <option value="unlisted" selected={@editing_diagram.visibility == :unlisted}>
                    Unlisted (anyone with link)
                  </option>
                  <option value="public" selected={@editing_diagram.visibility == :public}>
                    Public (discoverable)
                  </option>
                </select>
              </div>

              <div class="flex justify-end gap-2 mt-6">
                <button
                  type="button"
                  phx-click="cancel_edit_diagram"
                  class="px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
                >
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <%!-- Edit Filter Modal --%>
      <%= if @editing_filter do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-slate-900 rounded-lg p-6 max-w-2xl w-full max-h-[90vh] overflow-y-auto mx-4">
            <h2 class="text-2xl font-bold mb-4">Edit Filter</h2>

            <form phx-submit="save_filter_edit" id="edit-filter-form" class="space-y-4">
              <div>
                <label class="block text-sm font-medium mb-2">Filter Name</label>
                <input
                  type="text"
                  name="filter[name]"
                  value={@editing_filter.name}
                  required
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-2">Tags (comma-separated)</label>
                <input
                  type="text"
                  name="filter[tags]"
                  value={Enum.join(@editing_filter.tag_filter, ", ")}
                  required
                  placeholder="elixir, phoenix, otp"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-blue-500 focus:outline-none"
                />
              </div>

              <div class="flex justify-end gap-2 mt-6">
                <button
                  type="button"
                  phx-click="cancel_edit_filter"
                  class="px-4 py-2 bg-slate-800 hover:bg-slate-700 rounded transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded transition"
                >
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

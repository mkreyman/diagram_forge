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

  # Default pagination settings
  @default_page_size 10
  @page_size_options [5, 10, 25, 50]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "documents")
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "diagrams")
      # Schedule periodic document refresh to auto-hide completed documents after 5 minutes
      schedule_document_refresh()
    end

    current_user = socket.assigns[:current_user]

    # Set up initial state - URL-dependent data will be loaded in handle_params
    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:documents, list_documents())
      |> assign(:document_progress, %{})
      |> assign(:selected_document, nil)
      |> assign(:active_tag_filter, [])
      |> assign(:available_tags, [])
      |> assign(:tag_counts, %{})
      |> assign(:tag_search, "")
      |> assign(:pinned_filters, [])
      |> assign(:owned_diagrams, [])
      |> assign(:bookmarked_diagrams, [])
      |> assign(:public_diagrams, [])
      |> assign(
        :show_public_diagrams,
        current_user == nil || (current_user && current_user.show_public_diagrams)
      )
      |> assign(:selected_diagram, nil)
      |> assign(:generated_diagram, nil)
      |> assign(:prompt, "")
      |> assign(:uploaded_files, [])
      |> assign(:generating, false)
      |> assign(:uploading, false)
      |> assign(:fixing_syntax, false)
      |> assign(:diagram_theme, "dark")
      |> assign(:mermaid_error, nil)
      |> assign(:awaiting_fix_result, false)
      |> assign(:fix_expected_hash, nil)
      |> assign(:show_save_filter_modal, false)
      |> assign(:editing_filter, nil)
      |> assign(:editing_diagram, nil)
      |> assign(:new_tag_input, "")
      # Pagination state for owned diagrams
      |> assign(:page, 1)
      |> assign(:page_size, @default_page_size)
      |> assign(:page_size_options, @page_size_options)
      |> assign(:total_owned_diagrams, 0)
      # Pagination state for public diagrams
      |> assign(:public_page, 1)
      |> assign(:total_public_diagrams, 0)
      |> load_tags()
      |> load_filters()
      |> allow_upload(:document,
        accept: ~w(.pdf .md .markdown .txt),
        max_entries: 1,
        max_file_size: 2_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    current_user = socket.assigns.current_user

    # Parse URL params
    diagram_id = params["id"]
    tags = parse_tags_param(params["tags"])
    page = parse_int(params["page"], 1)
    page_size = parse_int(params["page_size"], @default_page_size)
    public_page = parse_int(params["public_page"], 1)

    # Update filter and pagination state from URL
    socket =
      socket
      |> assign(:active_tag_filter, tags)
      |> assign(:page, page)
      |> assign(:page_size, page_size)
      |> assign(:public_page, public_page)
      |> load_diagrams()

    # Handle diagram selection
    socket =
      if diagram_id do
        try do
          diagram = Diagrams.get_diagram!(diagram_id)

          if Diagrams.can_view_diagram?(diagram, current_user) do
            socket
            |> assign(:selected_diagram, diagram)
            |> assign(:generated_diagram, nil)
            # Reset fix-related state when selecting a new diagram
            |> assign(:awaiting_fix_result, false)
            |> assign(:fix_expected_hash, nil)
            |> assign(:mermaid_error, nil)
          else
            socket
            |> put_flash(:error, "You don't have permission to view this diagram")
            |> push_navigate(to: "/")
          end
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

  # Parse comma-separated tags from URL param
  defp parse_tags_param(nil), do: []
  defp parse_tags_param(""), do: []

  defp parse_tags_param(tags_str) do
    tags_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Parse integer from param with default
  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  # Tag filtering events

  @impl true
  def handle_event("add_tag_to_filter", %{"tag" => tag}, socket) do
    current_filter = socket.assigns.active_tag_filter
    new_filter = (current_filter ++ [tag]) |> Enum.uniq()

    # Push URL with new filter, reset to page 1
    {:noreply,
     socket
     |> assign(:new_tag_input, "")
     |> push_filter_url(new_filter, 1, socket.assigns.page_size)}
  end

  @impl true
  def handle_event("remove_tag_from_filter", %{"tag" => tag}, socket) do
    current_filter = socket.assigns.active_tag_filter
    new_filter = current_filter -- [tag]

    # Push URL with updated filter, reset to page 1
    {:noreply, push_filter_url(socket, new_filter, 1, socket.assigns.page_size)}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    # Push URL with empty filter, reset to page 1
    {:noreply, push_filter_url(socket, [], 1, socket.assigns.page_size)}
  end

  @impl true
  def handle_event("update_tag_input", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :new_tag_input, tag)}
  end

  @impl true
  def handle_event("search_tags", %{"value" => search}, socket) do
    {:noreply, assign(socket, :tag_search, search)}
  end

  @impl true
  def handle_event("clear_tag_search", _params, socket) do
    {:noreply, assign(socket, :tag_search, "")}
  end

  # Pagination events for owned diagrams

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    page = parse_int(page, 1)

    {:noreply,
     push_filter_url(
       socket,
       socket.assigns.active_tag_filter,
       page,
       socket.assigns.page_size,
       socket.assigns.public_page
     )}
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = parse_int(page_size, @default_page_size)
    # Reset both pages to 1 when changing page size
    {:noreply, push_filter_url(socket, socket.assigns.active_tag_filter, 1, page_size, 1)}
  end

  # Pagination events for public diagrams

  @impl true
  def handle_event("change_public_page", %{"page" => page}, socket) do
    page = parse_int(page, 1)

    {:noreply,
     push_filter_url(
       socket,
       socket.assigns.active_tag_filter,
       socket.assigns.page,
       socket.assigns.page_size,
       page
     )}
  end

  # Saved filter events

  @impl true
  def handle_event("apply_saved_filter", %{"id" => filter_id}, socket) do
    filter = Diagrams.get_saved_filter!(filter_id)
    # Apply saved filter via URL params, reset to page 1
    {:noreply, push_filter_url(socket, filter.tag_filter, 1, socket.assigns.page_size)}
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

      {:error, changeset} ->
        error_message = format_changeset_error(changeset, "Failed to save filter")
        {:noreply, put_flash(socket, :error, error_message)}
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
  def handle_event("fix_syntax", %{"id" => id}, socket) do
    if socket.assigns.fixing_syntax do
      {:noreply, socket}
    else
      diagram = Diagrams.get_diagram!(id)
      send(self(), {:do_fix_syntax, diagram})
      {:noreply, assign(socket, :fixing_syntax, true)}
    end
  end

  @impl true
  def handle_event("fix_generated_syntax", _params, socket) do
    if socket.assigns.fixing_syntax do
      {:noreply, socket}
    else
      diagram = socket.assigns.generated_diagram
      send(self(), {:do_fix_generated_syntax, diagram})
      {:noreply, assign(socket, :fixing_syntax, true)}
    end
  end

  # Mermaid render error/success events from JS hook
  @impl true
  def handle_event("mermaid_render_error", params, socket) do
    error_info = %{
      message: params["message"],
      line: params["line"],
      expected: params["expected"],
      mermaid_version: params["mermaidVersion"]
    }

    socket = assign(socket, :mermaid_error, error_info)

    # Only show flash if this is the diagram we're waiting for (hash matches)
    # Normalize both to integers for comparison (JS might send as int or string)
    source_hash = normalize_hash(params["sourceHash"])
    expected_hash = socket.assigns.fix_expected_hash
    awaiting = socket.assigns.awaiting_fix_result
    hashes_match = source_hash != nil && source_hash == expected_hash

    socket =
      if awaiting && hashes_match do
        socket
        |> assign(:awaiting_fix_result, false)
        |> assign(:fix_expected_hash, nil)
        |> put_flash(:error, "Unable to fix automatically. Try editing the diagram manually.")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("mermaid_render_success", params, socket) do
    socket = assign(socket, :mermaid_error, nil)

    # Only show flash if this is the diagram we're waiting for (hash matches)
    # Normalize both to integers for comparison (JS might send as int or string)
    source_hash = normalize_hash(params["sourceHash"])
    expected_hash = socket.assigns.fix_expected_hash
    hashes_match = source_hash != nil && source_hash == expected_hash

    socket =
      if socket.assigns.awaiting_fix_result && hashes_match do
        socket
        |> assign(:awaiting_fix_result, false)
        |> assign(:fix_expected_hash, nil)
        |> put_flash(:info, "Syntax fixed successfully!")
      else
        socket
      end

    {:noreply, socket}
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
         |> load_diagrams()
         |> load_tags()}

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
    # Preserve filter and pagination when selecting a diagram
    params =
      build_url_params(
        socket.assigns.active_tag_filter,
        socket.assigns.page,
        socket.assigns.page_size
      )

    {:noreply, push_patch(socket, to: ~p"/d/#{id}?#{params}")}
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
    # Prevent double-clicks while processing
    if socket.assigns.uploading do
      {:noreply, socket}
    else
      # Set uploading state immediately for UI feedback
      socket = assign(socket, :uploading, true)

      uploaded_files =
        consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
          process_uploaded_entry(path, entry, socket.assigns.current_user.id)
        end)

      {:noreply,
       socket
       |> assign(:uploading, false)
       |> assign(:documents, list_documents())
       |> put_flash(:info, "Uploaded #{length(uploaded_files)} file(s)")}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  @impl true
  def handle_event("cancel_processing", %{"doc-id" => doc_id}, socket) do
    case Diagrams.cancel_document_processing(doc_id) do
      {:ok, _document} ->
        {:noreply,
         socket
         |> assign(:documents, list_documents())
         |> put_flash(:info, "Document processing cancelled")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel processing")}
    end
  end

  defp process_uploaded_entry(path, entry, user_id) do
    dest = Path.join([System.tmp_dir(), "#{entry.uuid}#{Path.extname(entry.client_name)}"])
    File.cp!(path, dest)

    source_type =
      case Path.extname(entry.client_name) do
        ".pdf" -> :pdf
        ".txt" -> :text
        _ -> :markdown
      end

    attrs = %{
      title: Path.basename(entry.client_name, Path.extname(entry.client_name)),
      source_type: source_type,
      path: dest
    }

    case Diagrams.create_document(attrs, user_id) do
      {:ok, document} ->
        %{"document_id" => document.id}
        |> ProcessDocumentJob.new()
        |> Oban.insert()

        {:ok, document}

      {:error, _changeset} ->
        {:postpone, :error}
    end
  end

  # PubSub and async message handlers

  @impl true
  def handle_info({:do_generate_from_prompt, prompt}, socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    # If user is not authenticated, disable usage tracking since we can't attribute it
    opts = build_ai_opts(user_id)

    case Diagrams.generate_diagram_from_prompt(prompt, opts) do
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
  def handle_info({:document_progress, document_id, current, total}, socket) do
    progress = Map.put(socket.assigns.document_progress, document_id, {current, total})
    {:noreply, assign(socket, :document_progress, progress)}
  end

  @impl true
  def handle_info({:diagram_created, _diagram_id}, socket) do
    {:noreply, socket |> load_diagrams() |> load_tags()}
  end

  @impl true
  def handle_info(:refresh_documents, socket) do
    # Reload documents to auto-hide completed documents after 5 minutes
    documents = list_documents()

    # Schedule the next refresh
    schedule_document_refresh()

    {:noreply, assign(socket, :documents, documents)}
  end

  @impl true
  def handle_info({:do_fix_syntax, diagram}, socket) do
    user_id = socket.assigns.current_user.id
    mermaid_error = socket.assigns.mermaid_error
    opts = build_ai_opts(user_id) ++ [mermaid_error: mermaid_error]

    case Diagrams.fix_diagram_syntax(diagram, opts) do
      {:ok, fixed_source} ->
        case Diagrams.update_diagram(diagram, %{diagram_source: fixed_source}, user_id) do
          {:ok, updated_diagram} ->
            # Don't show success flash yet - wait for Mermaid render confirmation
            # Track the hash of fixed source so we only respond to events for THIS fix
            expected_hash = :erlang.phash2(fixed_source)

            {:noreply,
             socket
             |> assign(:fixing_syntax, false)
             |> assign(:awaiting_fix_result, true)
             |> assign(:fix_expected_hash, expected_hash)
             |> assign(:selected_diagram, updated_diagram)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:fixing_syntax, false)
             |> put_flash(:error, "Failed to save fixed diagram")}
        end

      {:unchanged, _source} ->
        {:noreply,
         socket
         |> assign(:fixing_syntax, false)
         |> put_flash(:warning, "AI couldn't identify syntax issues to fix")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:fixing_syntax, false)
         |> put_flash(:error, "Failed to fix syntax: #{reason}")}
    end
  end

  @impl true
  def handle_info({:do_fix_generated_syntax, diagram}, socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    mermaid_error = socket.assigns.mermaid_error
    opts = build_ai_opts(user_id) ++ [mermaid_error: mermaid_error]

    case Diagrams.fix_diagram_syntax_source(diagram.diagram_source, diagram.summary, opts) do
      {:ok, fixed_source} ->
        updated_diagram = %{diagram | diagram_source: fixed_source}

        # Don't show success flash yet - wait for Mermaid render confirmation
        # Track the hash of fixed source so we only respond to events for THIS fix
        expected_hash = :erlang.phash2(fixed_source)

        {:noreply,
         socket
         |> assign(:fixing_syntax, false)
         |> assign(:awaiting_fix_result, true)
         |> assign(:fix_expected_hash, expected_hash)
         |> assign(:selected_diagram, updated_diagram)
         |> assign(:generated_diagram, updated_diagram)}

      {:unchanged, _source} ->
        {:noreply,
         socket
         |> assign(:fixing_syntax, false)
         |> put_flash(:warning, "AI couldn't identify syntax issues to fix")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:fixing_syntax, false)
         |> put_flash(:error, "Failed to fix syntax: #{reason}")}
    end
  end

  # Private helper functions

  # Normalize hash to integer (JS might send as int or string)
  defp normalize_hash(nil), do: nil
  defp normalize_hash(hash) when is_integer(hash), do: hash
  defp normalize_hash(hash) when is_binary(hash), do: String.to_integer(hash)
  defp normalize_hash(_), do: nil

  # Helper to build URL with filter and pagination params
  defp push_filter_url(socket, tags, page, page_size, public_page \\ 1) do
    params = build_url_params(tags, page, page_size, public_page)
    push_patch(socket, to: ~p"/?#{params}")
  end

  defp build_url_params(tags, page, page_size, public_page \\ 1) do
    params = []

    params =
      if tags != [] do
        [{:tags, Enum.join(tags, ",")} | params]
      else
        params
      end

    params =
      if page != 1 do
        [{:page, page} | params]
      else
        params
      end

    params =
      if page_size != @default_page_size do
        [{:page_size, page_size} | params]
      else
        params
      end

    params =
      if public_page != 1 do
        [{:public_page, public_page} | params]
      else
        params
      end

    params
  end

  defp load_diagrams(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    tag_filter = socket.assigns[:active_tag_filter] || []
    page = socket.assigns[:page] || 1
    page_size = socket.assigns[:page_size] || @default_page_size
    public_page = socket.assigns[:public_page] || 1

    if user_id do
      # Get all owned diagrams to count total, then paginate
      all_owned = Diagrams.list_diagrams_by_tags(user_id, tag_filter, :owned)
      total_owned = length(all_owned)

      # Paginate owned diagrams
      owned =
        all_owned
        |> Enum.drop((page - 1) * page_size)
        |> Enum.take(page_size)

      bookmarked = Diagrams.list_diagrams_by_tags(user_id, tag_filter, :bookmarked)

      # For logged-in users, respect their show_public_diagrams preference
      show_public = socket.assigns.current_user.show_public_diagrams

      # Always get public diagrams (filtered by tags) for count
      all_public = Diagrams.list_public_diagrams(tag_filter)
      total_public = length(all_public)

      # Paginate public diagrams with separate page
      public =
        if show_public do
          all_public
          |> Enum.drop((public_page - 1) * page_size)
          |> Enum.take(page_size)
        else
          []
        end

      socket
      |> assign(:owned_diagrams, owned)
      |> assign(:total_owned_diagrams, total_owned)
      |> assign(:bookmarked_diagrams, bookmarked)
      |> assign(:public_diagrams, public)
      |> assign(:total_public_diagrams, total_public)
      |> assign(:show_public_diagrams, show_public)
    else
      # For logged-out users, show public diagrams filtered by tags
      all_public = Diagrams.list_public_diagrams(tag_filter)
      total_public = length(all_public)

      # Paginate public diagrams with separate page
      public =
        all_public
        |> Enum.drop((public_page - 1) * page_size)
        |> Enum.take(page_size)

      socket
      |> assign(:owned_diagrams, [])
      |> assign(:total_owned_diagrams, 0)
      |> assign(:bookmarked_diagrams, [])
      |> assign(:public_diagrams, public)
      |> assign(:total_public_diagrams, total_public)
      |> assign(:show_public_diagrams, true)
    end
  end

  defp load_tags(socket) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    show_public = socket.assigns[:show_public_diagrams] || false

    tag_counts = compute_tag_counts(user_id, show_public)
    # Sort tags alphabetically, case-insensitive
    available_tags = tag_counts |> Map.keys() |> Enum.sort_by(&String.downcase/1)

    socket
    |> assign(:available_tags, available_tags)
    |> assign(:tag_counts, tag_counts)
  end

  defp compute_tag_counts(nil, _show_public) do
    Diagrams.get_public_tag_counts()
  end

  defp compute_tag_counts(user_id, true) do
    user_tags = Diagrams.get_tag_counts(user_id)
    public_tags = Diagrams.get_public_tag_counts()
    Map.merge(user_tags, public_tags, fn _k, v1, v2 -> v1 + v2 end)
  end

  defp compute_tag_counts(user_id, false) do
    Diagrams.get_tag_counts(user_id)
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

  defp upload_error_to_string(:too_large), do: "File is too large (max 2MB)"
  defp upload_error_to_string(:not_accepted), do: "Invalid file type (use PDF, Markdown, or Text)"
  defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded at a time"
  defp upload_error_to_string(_), do: "Upload error"

  defp visibility_tooltip(:private), do: "Only you can view"
  defp visibility_tooltip(:unlisted), do: "Anyone with the link"
  defp visibility_tooltip(:public), do: "Discoverable by all"
  defp visibility_tooltip(_), do: ""

  # Builds AI options with proper user_id handling.
  # If user is not authenticated (nil user_id), disables usage tracking since
  # we can't attribute the usage to anyone.
  defp build_ai_opts(nil) do
    [user_id: nil, track_usage: false]
  end

  defp build_ai_opts(user_id) do
    [user_id: user_id]
  end

  # Formats changeset errors into a user-friendly message.
  # Handles common constraint violations with specific messages.
  defp format_changeset_error(changeset, default_message) do
    cond do
      # Composite unique constraint on [:user_id, :name] reports error on user_id
      has_constraint_error?(changeset, "saved_filters_user_id_name_index") ->
        "A filter with that name already exists"

      changeset.errors != [] ->
        {field, {msg, _}} = hd(changeset.errors)
        "#{Phoenix.Naming.humanize(field)} #{msg}"

      true ->
        default_message
    end
  end

  defp has_constraint_error?(changeset, constraint_name) do
    Enum.any?(changeset.errors, fn
      {_field, {_msg, opts}} -> opts[:constraint_name] == constraint_name
      _ -> false
    end)
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
            <%!-- Support Links - visible to all --%>
            <div class="hidden sm:flex items-center gap-2 text-sm text-slate-400">
              <span>Support this project →</span>
              <a
                href={Application.get_env(:diagram_forge, :github_sponsors_url)}
                target="_blank"
                rel="noopener"
                class="hover:text-slate-200 transition"
              >
                GitHub
              </a>
              <span>|</span>
              <a
                href={Application.get_env(:diagram_forge, :stripe_tip_url)}
                target="_blank"
                rel="noopener"
                class="hover:text-slate-200 transition"
              >
                Stripe
              </a>
              <span class="mx-2">·</span>
              <a
                href={Application.get_env(:diagram_forge, :linkedin_url)}
                target="_blank"
                rel="noopener"
                class="hover:text-slate-200 transition"
              >
                Get in touch
              </a>
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
            <%!-- Upload Zone (compact when no documents) --%>
            <%= if @current_user do %>
              <form phx-change="validate" phx-submit="save" id="upload-form">
                <div
                  class="border-2 border-dashed border-slate-700 rounded-lg p-3 text-center cursor-pointer hover:border-slate-600 transition bg-slate-900/50"
                  phx-drop-target={@uploads.document.ref}
                >
                  <.live_file_input upload={@uploads.document} class="hidden" />
                  <label for={@uploads.document.ref} class="cursor-pointer">
                    <div class="text-slate-400">
                      <div class="flex items-center justify-center gap-2 mb-1">
                        <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                        <span class="text-xs font-medium">Upload a document</span>
                      </div>
                      <p class="text-xs text-slate-500">
                        PDF, Markdown, or Text (max 2MB)
                      </p>
                    </div>
                  </label>
                </div>

                <%!-- Show selected files --%>
                <%= for entry <- @uploads.document.entries do %>
                  <div class="mt-2 p-2 bg-slate-800 rounded">
                    <div class="flex items-center justify-between text-xs text-slate-300">
                      <span class="truncate">{entry.client_name}</span>
                      <button
                        type="button"
                        phx-click="cancel_upload"
                        phx-value-ref={entry.ref}
                        class="text-red-400 hover:text-red-300"
                        aria-label="Cancel upload"
                      >
                        ✕
                      </button>
                    </div>
                    <%!-- Progress bar during upload --%>
                    <%= if entry.progress > 0 and entry.progress < 100 do %>
                      <div class="w-full bg-slate-700 rounded-full h-1.5 mt-1">
                        <div
                          class="bg-blue-500 h-1.5 rounded-full transition-all duration-300"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <%= for err <- upload_errors(@uploads.document, entry) do %>
                    <p class="text-xs text-red-400 mt-1">{upload_error_to_string(err)}</p>
                  <% end %>
                <% end %>

                <%= for err <- upload_errors(@uploads.document) do %>
                  <p class="text-xs text-red-400 mt-1">{upload_error_to_string(err)}</p>
                <% end %>

                <%!-- Upload button with immediate loading feedback --%>
                <%= if @uploads.document.entries != [] do %>
                  <button
                    type="submit"
                    disabled={@uploading}
                    class="w-full mt-2 px-3 py-2 text-sm rounded transition bg-blue-600 hover:bg-blue-700 disabled:bg-blue-600/50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                  >
                    <%= if @uploading do %>
                      <svg
                        class="animate-spin w-4 h-4"
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
                      Uploading...
                    <% else %>
                      <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> Upload
                    <% end %>
                  </button>
                <% end %>
              </form>
            <% else %>
              <%!-- Login prompt for document upload --%>
              <div class="border-2 border-dashed border-slate-700 rounded-lg p-3 text-center bg-slate-900/50">
                <div class="text-slate-400">
                  <div class="flex items-center justify-center gap-2 mb-1">
                    <.icon name="hero-arrow-up-tray" class="w-4 h-4" />
                    <span class="text-xs font-medium">Upload a document</span>
                  </div>
                  <p class="text-xs text-slate-500 mb-2">
                    PDF, Markdown, or Text (max 2MB)
                  </p>
                  <.link
                    href={~p"/auth/github"}
                    class="text-xs text-blue-400 hover:text-blue-300 underline"
                  >
                    Sign in to upload documents
                  </.link>
                </div>
              </div>
            <% end %>

            <%!-- Documents Section (only shown when documents exist) --%>
            <%= if @documents != [] do %>
              <div class="bg-slate-900 rounded-xl p-3 mt-3">
                <h2 class="text-lg font-semibold mb-2">Source Documents</h2>
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
                      <%= if doc.status == :processing do %>
                        <% progress = Map.get(@document_progress, doc.id) %>
                        <div class="flex items-center justify-between mt-1">
                          <%= if progress do %>
                            <% {current, total} = progress %>
                            <span class="text-xs text-yellow-400">
                              Generating diagram {current}/{total}
                            </span>
                          <% else %>
                            <span class="text-xs text-slate-400">
                              Extracting text...
                            </span>
                          <% end %>
                          <button
                            type="button"
                            phx-click="cancel_processing"
                            phx-value-doc-id={doc.id}
                            class="text-xs text-red-400 hover:text-red-300 hover:underline"
                            title="Cancel processing"
                          >
                            Cancel
                          </button>
                        </div>
                      <% end %>
                      <%= if doc.status == :error and doc.error_message do %>
                        <div class="text-xs text-red-400 mt-1">
                          {doc.error_message}
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Diagrams Section --%>
            <div class="bg-slate-900 rounded-xl p-4 flex flex-col overflow-hidden flex-1">
              <%!-- Tag Cloud - clickable tags for filtering --%>
              <%= if @tag_counts != %{} do %>
                <% filtered_tags =
                  if String.length(@tag_search) >= 3 do
                    search_lower = String.downcase(@tag_search)

                    @tag_counts
                    |> Enum.filter(fn {tag, _count} ->
                      String.contains?(String.downcase(tag), search_lower)
                    end)
                  else
                    @tag_counts |> Enum.to_list()
                  end %>
                <div class="mb-3 pb-3 border-b border-slate-800">
                  <h2 class="text-lg font-semibold mb-2">Available Tags ({map_size(@tag_counts)})</h2>
                  <div class="relative mb-2">
                    <input
                      type="text"
                      value={@tag_search}
                      placeholder="Search tags..."
                      phx-keyup="search_tags"
                      phx-debounce="300"
                      class="w-full px-3 py-1.5 pr-8 text-sm bg-slate-800 border border-slate-700 rounded-lg text-slate-200 placeholder-slate-500 focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                    />
                    <%= if @tag_search != "" do %>
                      <button
                        type="button"
                        phx-click="clear_tag_search"
                        class="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </button>
                    <% end %>
                  </div>
                  <div class="flex flex-wrap gap-1.5 max-h-24 overflow-y-auto">
                    <%= for {tag, count} <- Enum.sort_by(filtered_tags, fn {tag, _count} -> String.downcase(tag) end) do %>
                      <button
                        type="button"
                        phx-click="add_tag_to_filter"
                        phx-value-tag={tag}
                        class={[
                          "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs transition",
                          tag in @active_tag_filter &&
                            "bg-blue-600 text-white cursor-default",
                          tag not in @active_tag_filter &&
                            "bg-slate-700 hover:bg-slate-600 text-slate-300"
                        ]}
                        disabled={tag in @active_tag_filter}
                      >
                        <span>{tag}</span>
                        <span class="text-slate-400">({count})</span>
                      </button>
                    <% end %>
                    <%= if filtered_tags == [] and String.length(@tag_search) >= 3 do %>
                      <span class="text-sm text-slate-500 italic">No matching tags</span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Active Filter Display (below tag cloud, matching style) --%>
              <%= if @active_tag_filter != [] do %>
                <div class="mb-3 pb-3 border-b border-slate-800">
                  <div class="flex items-center gap-2 mb-2">
                    <span class="text-xs text-slate-400">Filter:</span>
                    <div class="flex flex-wrap gap-1.5">
                      <%= for tag <- @active_tag_filter do %>
                        <button
                          type="button"
                          phx-click="remove_tag_from_filter"
                          phx-value-tag={tag}
                          class="inline-flex items-center gap-1 px-2 py-1 bg-blue-600 text-white rounded-full text-xs transition hover:bg-blue-700"
                        >
                          <span>{tag}</span>
                          <span class="text-blue-200">✕</span>
                        </button>
                      <% end %>
                    </div>
                  </div>
                  <%!-- Clear and Save buttons on same line --%>
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      phx-click="clear_filter"
                      class="px-2 py-1 text-xs bg-green-600 hover:bg-green-500 text-white rounded-full transition"
                    >
                      Clear
                    </button>
                    <%= if @current_user do %>
                      <button
                        phx-click="show_save_filter_modal"
                        class="px-2 py-1 text-xs bg-slate-700 hover:bg-slate-600 text-white rounded-full transition"
                      >
                        Save Filter
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Pinned Filters Section --%>
              <%= if @pinned_filters != [] do %>
                <div class="mb-3 pb-3 border-b border-slate-800">
                  <h2 class="text-lg font-semibold mb-2">Pinned Filters</h2>
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

              <%!-- My Diagrams Section --%>
              <div class="mb-4">
                <h2 class="text-lg font-semibold mb-2">
                  My Diagrams ({@total_owned_diagrams})
                </h2>

                <%!-- Pagination Controls --%>
                <% total_pages = max(1, ceil(@total_owned_diagrams / @page_size)) %>
                <%= if @total_owned_diagrams > 0 do %>
                  <div class="flex items-center justify-between mb-3 pb-2 border-b border-slate-800 text-xs">
                    <form phx-change="change_page_size" class="flex items-center gap-2">
                      <span class="text-slate-400">Show:</span>
                      <select
                        name="page_size"
                        class="bg-slate-800 text-slate-300 rounded px-2 py-1 text-xs"
                      >
                        <%= for size <- @page_size_options do %>
                          <option value={size} selected={@page_size == size}>
                            {size}
                          </option>
                        <% end %>
                      </select>
                    </form>
                    <div class="flex items-center gap-2">
                      <span class="text-slate-400">
                        Page {@page} of {total_pages}
                      </span>
                      <div class="flex gap-1">
                        <button
                          type="button"
                          phx-click="change_page"
                          phx-value-page={@page - 1}
                          disabled={@page == 1}
                          class={[
                            "px-2 py-1 rounded transition",
                            @page == 1 && "bg-slate-800 text-slate-600 cursor-not-allowed",
                            @page > 1 && "bg-slate-700 hover:bg-slate-600 text-slate-300"
                          ]}
                        >
                          ←
                        </button>
                        <button
                          type="button"
                          phx-click="change_page"
                          phx-value-page={@page + 1}
                          disabled={@page >= total_pages}
                          class={[
                            "px-2 py-1 rounded transition",
                            @page >= total_pages &&
                              "bg-slate-800 text-slate-600 cursor-not-allowed",
                            @page < total_pages &&
                              "bg-slate-700 hover:bg-slate-600 text-slate-300"
                          ]}
                        >
                          →
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>

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

              <%!-- Bookmarked Diagrams Section --%>
              <%= if @bookmarked_diagrams != [] do %>
                <div class="mb-4 border-t border-slate-800 pt-4">
                  <h2 class="text-lg font-semibold mb-2">
                    Bookmarked Diagrams ({length(@bookmarked_diagrams)})
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

              <%!-- Public Diagrams Section - visible to all users --%>
              <div class="border-t border-slate-800 pt-4">
                <div class="flex items-center justify-between mb-2">
                  <h2 class="text-lg font-semibold">
                    Public Diagrams ({@total_public_diagrams})
                  </h2>
                  <%!-- Toggle only shown for logged-in users --%>
                  <%= if @current_user do %>
                    <button
                      phx-click="toggle_public_diagrams"
                      class="flex items-center gap-1.5 text-xs text-slate-400 hover:text-slate-200 transition"
                      title={
                        if @show_public_diagrams,
                          do: "Hide public diagrams",
                          else: "Show public diagrams"
                      }
                    >
                      <%= if @show_public_diagrams do %>
                        <.icon name="hero-eye" class="w-4 h-4 text-green-500" />
                      <% else %>
                        <.icon name="hero-eye-slash" class="w-4 h-4 text-slate-500" />
                      <% end %>
                    </button>
                  <% end %>
                </div>

                <%= if @show_public_diagrams do %>
                  <%!-- Public Diagrams Pagination Controls --%>
                  <% public_total_pages = max(1, ceil(@total_public_diagrams / @page_size)) %>
                  <%= if @total_public_diagrams > 0 do %>
                    <div class="flex items-center justify-between mb-3 pb-2 border-b border-slate-800 text-xs">
                      <form phx-change="change_page_size" class="flex items-center gap-2">
                        <span class="text-slate-400">Show:</span>
                        <select
                          name="page_size"
                          class="bg-slate-800 text-slate-300 rounded px-2 py-1 text-xs"
                        >
                          <%= for size <- @page_size_options do %>
                            <option value={size} selected={@page_size == size}>
                              {size}
                            </option>
                          <% end %>
                        </select>
                      </form>
                      <div class="flex items-center gap-2">
                        <span class="text-slate-400">
                          Page {@public_page} of {public_total_pages}
                        </span>
                        <div class="flex gap-1">
                          <button
                            type="button"
                            phx-click="change_public_page"
                            phx-value-page={@public_page - 1}
                            disabled={@public_page <= 1}
                            class={[
                              "px-2 py-1 rounded transition",
                              @public_page <= 1 &&
                                "bg-slate-800 text-slate-600 cursor-not-allowed",
                              @public_page > 1 &&
                                "bg-slate-700 hover:bg-slate-600 text-slate-300"
                            ]}
                          >
                            ←
                          </button>
                          <button
                            type="button"
                            phx-click="change_public_page"
                            phx-value-page={@public_page + 1}
                            disabled={@public_page >= public_total_pages}
                            class={[
                              "px-2 py-1 rounded transition",
                              @public_page >= public_total_pages &&
                                "bg-slate-800 text-slate-600 cursor-not-allowed",
                              @public_page < public_total_pages &&
                                "bg-slate-700 hover:bg-slate-600 text-slate-300"
                            ]}
                          >
                            →
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>

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

              <%!-- Tips Section --%>
              <div class="mt-auto pt-4 border-t border-slate-800">
                <h2 class="text-lg font-semibold mb-2 flex items-center gap-2">
                  <.icon name="hero-light-bulb" class="w-4 h-4 text-amber-400" /> Tips
                </h2>
                <div class="text-xs text-slate-400 space-y-1">
                  <div>• Click tags to filter diagrams</div>
                  <div>• Save filters for quick access</div>
                  <div>• Fork public diagrams to customize</div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Right Main Area: Diagram Display + Generate --%>
          <div class="lg:col-span-3 space-y-4 flex flex-col">
            <%!-- Diagram Display --%>
            <div class="bg-slate-900 rounded-xl p-6 flex-1 overflow-auto">
              <%= if @selected_diagram do %>
                <div class="space-y-4">
                  <div class="grid grid-cols-2 gap-6">
                    <div>
                      <div class="flex items-center gap-2 mb-2">
                        <h2 class="text-2xl font-semibold">{@selected_diagram.title}</h2>
                        <span
                          class={[
                            "inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium",
                            @selected_diagram.visibility == :private &&
                              "bg-red-900/30 text-red-400",
                            @selected_diagram.visibility == :unlisted &&
                              "bg-yellow-900/30 text-yellow-400",
                            @selected_diagram.visibility == :public &&
                              "bg-green-900/30 text-green-400"
                          ]}
                          title={visibility_tooltip(@selected_diagram.visibility)}
                        >
                          <%= case @selected_diagram.visibility do %>
                            <% :private -> %>
                              <.icon name="hero-lock-closed" class="w-3.5 h-3.5" />
                              <span>Private</span>
                            <% :unlisted -> %>
                              <.icon name="hero-link" class="w-3.5 h-3.5" />
                              <span>Unlisted</span>
                            <% :public -> %>
                              <.icon name="hero-globe-alt" class="w-3.5 h-3.5" />
                              <span>Public</span>
                          <% end %>
                        </span>
                      </div>
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
                          Copy Link
                        </button>

                        <%!-- Unsaved diagram buttons --%>
                        <%= if @generated_diagram do %>
                          <button
                            phx-click="save_generated_diagram"
                            class="px-3 py-1 text-xs bg-green-700 hover:bg-green-600 text-white rounded transition whitespace-nowrap"
                          >
                            Save
                          </button>
                          <button
                            phx-click="fix_generated_syntax"
                            disabled={@fixing_syntax}
                            class={[
                              "px-3 py-1 text-xs text-white rounded transition whitespace-nowrap flex items-center gap-1",
                              @fixing_syntax && "bg-orange-800/50 cursor-wait",
                              !@fixing_syntax && "bg-orange-700 hover:bg-orange-600"
                            ]}
                          >
                            <%= if @fixing_syntax do %>
                              <svg
                                class="animate-spin h-3 w-3"
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
                              <span>Fixing...</span>
                            <% else %>
                              Fix Syntax
                            <% end %>
                          </button>
                          <button
                            phx-click="discard_generated_diagram"
                            class="px-3 py-1 text-xs bg-slate-700 hover:bg-slate-600 text-white rounded transition whitespace-nowrap"
                          >
                            Discard
                          </button>
                        <% end %>

                        <%!-- Saved diagram owner buttons --%>
                        <%= if !@generated_diagram && @current_user && Diagrams.can_edit_diagram?(@selected_diagram, @current_user) do %>
                          <button
                            phx-click="edit_diagram"
                            phx-value-id={@selected_diagram.id}
                            class="px-3 py-1 text-xs bg-blue-800 hover:bg-blue-700 text-white rounded transition whitespace-nowrap"
                          >
                            Edit
                          </button>

                          <button
                            phx-click="fix_syntax"
                            phx-value-id={@selected_diagram.id}
                            disabled={@fixing_syntax}
                            class={[
                              "px-3 py-1 text-xs text-white rounded transition whitespace-nowrap flex items-center gap-1",
                              @fixing_syntax && "bg-orange-800/50 cursor-wait",
                              !@fixing_syntax && "bg-orange-700 hover:bg-orange-600"
                            ]}
                          >
                            <%= if @fixing_syntax do %>
                              <svg
                                class="animate-spin h-3 w-3"
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
                              <span>Fixing...</span>
                            <% else %>
                              Fix Syntax
                            <% end %>
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

                        <%!-- Show Bookmark/Fork only for non-owners and saved diagrams --%>
                        <%= if @current_user && !@generated_diagram && !Diagrams.user_owns_diagram?(@selected_diagram.id, @current_user.id) do %>
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

                        <%!-- Show Fork for non-logged-in users viewing saved diagrams --%>
                        <%= if is_nil(@current_user) && !@generated_diagram do %>
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

                  <div
                    id={"mermaid-preview-#{:erlang.phash2(@selected_diagram.diagram_source)}"}
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

      <%!-- Footer --%>
      <footer class="bg-slate-900 border-t border-slate-800 py-4 mt-auto">
        <div class="container mx-auto px-4 text-center text-sm text-slate-500">
          <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
            <span>© {Date.utc_today().year} DiagramForge</span>
            <span class="hidden sm:inline">·</span>
            <a href="/terms" class="hover:text-slate-300 transition">Terms of Service</a>
            <span class="hidden sm:inline">·</span>
            <a href="/privacy" class="hover:text-slate-300 transition">Privacy Policy</a>
            <span class="hidden sm:inline">·</span>
            <a
              href={Application.get_env(:diagram_forge, :github_issues_url)}
              target="_blank"
              rel="noopener"
              class="hover:text-slate-300 transition"
            >
              Report an Issue
            </a>
          </div>
        </div>
      </footer>

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

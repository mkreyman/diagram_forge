defmodule DiagramForgeWeb.DiagramStudioLive do
  @moduledoc """
  Main LiveView for the Diagram Studio.

  Two-column layout:
  - Left sidebar: Collapsible concepts tree with diagrams, upload, and documents
  - Right main area: Large diagram display and generate from prompt
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.Workers.{GenerateDiagramJob, ProcessDocumentJob}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "documents")
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "diagrams")
    end

    {:ok,
     socket
     |> assign(:documents, list_documents())
     |> assign(:selected_document, nil)
     |> assign(:concepts_page, 1)
     |> assign(:concepts_page_size, 10)
     |> assign(:concepts_total, 0)
     |> assign(:concepts, [])
     |> assign(:category_filter, nil)
     |> assign(:selected_concepts, MapSet.new())
     |> assign(:expanded_concepts, MapSet.new())
     |> assign(:diagrams, [])
     |> assign(:selected_diagram, nil)
     |> assign(:generated_diagram, nil)
     |> assign(:prompt, "")
     |> assign(:uploaded_files, [])
     |> assign(:generating, false)
     |> assign(:generating_concepts, MapSet.new())
     |> assign(:generation_total, 0)
     |> assign(:generation_completed, 0)
     |> assign(:failed_generations, %{})
     |> allow_upload(:document,
       accept: ~w(.pdf .md .markdown),
       max_entries: 1,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = parse_int(params["page"], 1)
    page_size = parse_int(params["page_size"], 10)

    {:noreply,
     socket
     |> assign(:concepts_page, page)
     |> assign(:concepts_page_size, page_size)
     |> assign(:concepts_total, count_concepts())
     |> assign(:concepts, list_concepts(page: page, page_size: page_size))}
  end

  @impl true
  def handle_event("select_document", %{"id" => id}, socket) do
    document = Diagrams.get_document!(id)
    diagrams = Diagrams.list_diagrams_for_document(document.id)

    # Subscribe to generation progress for this document
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "diagram_generation:#{document.id}")
    end

    {:noreply,
     socket
     |> assign(:selected_document, document)
     |> assign(:diagrams, diagrams)
     |> assign(:selected_concepts, MapSet.new())
     |> assign(:selected_diagram, nil)
     |> assign(:generated_diagram, nil)
     |> assign(:generating_concepts, MapSet.new())
     |> assign(:generation_total, 0)
     |> assign(:generation_completed, 0)
     |> assign(:failed_generations, %{})}
  end

  @impl true
  def handle_event("toggle_concept", %{"id" => id}, socket) do
    concept_id = String.to_integer(id)
    selected = socket.assigns.selected_concepts

    selected =
      if MapSet.member?(selected, concept_id) do
        MapSet.delete(selected, concept_id)
      else
        MapSet.put(selected, concept_id)
      end

    {:noreply, assign(socket, :selected_concepts, selected)}
  end

  @impl true
  def handle_event("toggle_concept_expand", %{"id" => id}, socket) do
    concept_id = String.to_integer(id)
    expanded = socket.assigns.expanded_concepts

    expanded =
      if MapSet.member?(expanded, concept_id) do
        MapSet.delete(expanded, concept_id)
      else
        MapSet.put(expanded, concept_id)
      end

    {:noreply, assign(socket, :expanded_concepts, expanded)}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    new_filter = if socket.assigns.category_filter == category, do: nil, else: category
    {:noreply, assign(socket, :category_filter, new_filter)}
  end

  @impl true
  def handle_event("generate_diagrams", _params, socket) do
    selected_concept_ids = socket.assigns.selected_concepts

    # Get document_id from each concept since concepts can be from different documents
    selected_concept_ids
    |> Enum.each(fn concept_id ->
      concept = Diagrams.get_concept!(concept_id)

      %{"concept_id" => concept_id, "document_id" => concept.document_id}
      |> GenerateDiagramJob.new()
      |> Oban.insert()
    end)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Generating #{MapSet.size(selected_concept_ids)} diagram(s)..."
     )
     |> assign(:selected_concepts, MapSet.new())
     |> assign(:generating_concepts, selected_concept_ids)
     |> assign(:generation_total, MapSet.size(selected_concept_ids))
     |> assign(:generation_completed, 0)
     |> assign(:failed_generations, %{})}
  end

  @impl true
  def handle_event("select_diagram", %{"id" => id}, socket) do
    diagram = Diagrams.get_diagram!(id)

    {:noreply,
     socket
     |> assign(:selected_diagram, diagram)
     |> assign(:generated_diagram, nil)}
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
      socket = assign(socket, :generating, true)

      case Diagrams.generate_diagram_from_prompt(prompt, []) do
        {:ok, diagram} ->
          {:noreply,
           socket
           |> assign(:selected_diagram, diagram)
           |> assign(:generated_diagram, diagram)
           |> assign(:prompt, "")
           |> assign(:generating, false)
           |> put_flash(:info, "Diagram generated! Click Save to persist it.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> put_flash(:error, "Failed to generate diagram: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("save_generated_diagram", _params, socket) do
    case socket.assigns.generated_diagram do
      nil ->
        {:noreply, put_flash(socket, :error, "No diagram to save")}

      diagram ->
        case Diagrams.save_generated_diagram(diagram) do
          {:ok, saved_diagram} ->
            {:noreply,
             socket
             |> assign(:generated_diagram, nil)
             |> assign(:selected_diagram, saved_diagram)
             |> assign(:diagrams, [saved_diagram | socket.assigns.diagrams])
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
  def handle_event("concepts_change_page", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/?page=#{page}&page_size=#{socket.assigns.concepts_page_size}")}
  end

  @impl true
  def handle_event("concepts_change_page_size", %{"page_size" => page_size}, socket) do
    # Reset to page 1 when changing page size
    {:noreply, push_patch(socket, to: ~p"/?page=1&page_size=#{page_size}")}
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

        case Diagrams.create_document(attrs) do
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

  @impl true
  def handle_info({:document_updated, document_id}, socket) do
    {:noreply,
     socket
     |> assign(:documents, list_documents())
     |> maybe_update_selected_document(document_id)}
  end

  @impl true
  def handle_info({:concepts_updated, _document_id}, socket) do
    # Reload concepts with current pagination settings
    concepts =
      list_concepts(
        page: socket.assigns.concepts_page,
        page_size: socket.assigns.concepts_page_size
      )

    {:noreply,
     socket
     |> assign(:concepts, concepts)
     |> assign(:concepts_total, count_concepts())}
  end

  @impl true
  def handle_info({:diagram_created, _diagram_id}, socket) do
    if socket.assigns.selected_document do
      diagrams = Diagrams.list_diagrams_for_document(socket.assigns.selected_document.id)
      {:noreply, assign(socket, :diagrams, diagrams)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:generation_started, _concept_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:generation_completed, concept_id, _diagram_id}, socket) do
    generating_concepts = MapSet.delete(socket.assigns.generating_concepts, concept_id)
    generation_completed = socket.assigns.generation_completed + 1

    # Refresh diagrams list
    diagrams =
      if socket.assigns.selected_document do
        Diagrams.list_diagrams_for_document(socket.assigns.selected_document.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:generating_concepts, generating_concepts)
     |> assign(:generation_completed, generation_completed)
     |> assign(:diagrams, diagrams)}
  end

  @impl true
  def handle_info({:generation_failed, concept_id, reason, category, severity}, socket) do
    generating_concepts = MapSet.delete(socket.assigns.generating_concepts, concept_id)

    # Store the error details
    failed_generations =
      Map.put(socket.assigns.failed_generations, concept_id, %{
        reason: reason,
        category: category,
        severity: severity
      })

    {:noreply,
     socket
     |> assign(:generating_concepts, generating_concepts)
     |> assign(:failed_generations, failed_generations)
     |> put_flash(:error, "Failed to generate diagram: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <%!-- Top Navbar --%>
      <div class="bg-slate-900 border-b border-slate-800">
        <div class="container mx-auto px-4 py-3">
          <h1 class="text-xl font-bold text-slate-100">DiagramForge Studio</h1>
        </div>
      </div>

      <div class="container mx-auto px-4 py-4 flex-1 flex flex-col">
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6 flex-1">
          <%!-- Left Sidebar --%>
          <div class="lg:col-span-1 flex flex-col gap-4">
            <%!-- Upload Section (Top) --%>
            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-lg font-semibold mb-3">Upload Document</h2>

              <form phx-change="validate" phx-submit="save" id="upload-form">
                <div class="space-y-3">
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
            </div>

            <%!-- Documents Section --%>
            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-lg font-semibold mb-3">Documents</h2>

              <div class="space-y-2 max-h-48 overflow-y-auto">
                <%= for doc <- @documents do %>
                  <div
                    class={[
                      "p-2 rounded cursor-pointer transition",
                      @selected_document && @selected_document.id == doc.id &&
                        "bg-slate-800 border border-slate-600",
                      (!@selected_document || @selected_document.id != doc.id) &&
                        "bg-slate-800/50 hover:bg-slate-800"
                    ]}
                    phx-click="select_document"
                    phx-value-id={doc.id}
                  >
                    <div class="flex items-center justify-between mb-1">
                      <span class="text-xs font-medium truncate">{doc.title}</span>
                      <span class={[
                        "text-xs px-1.5 py-0.5 rounded font-medium",
                        doc.status == :ready && "bg-green-900/50 text-green-300",
                        doc.status == :processing && "bg-yellow-900/50 text-yellow-300 animate-pulse",
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

            <%!-- Concepts Section (Bottom, scrollable) --%>
            <div class="bg-slate-900 rounded-xl p-4 flex flex-col overflow-hidden">
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-xl font-semibold">Concepts</h2>
                <%= if MapSet.size(@selected_concepts) > 0 do %>
                  <button
                    phx-click="generate_diagrams"
                    class="px-3 py-1 text-sm bg-green-600 hover:bg-green-700 rounded transition"
                  >
                    Generate ({MapSet.size(@selected_concepts)})
                  </button>
                <% end %>
              </div>

              <%!-- Pagination Controls --%>
              <% total_pages = ceil(@concepts_total / @concepts_page_size) %>
              <div class="flex items-center justify-between mb-3 pb-3 border-b border-slate-800 text-xs">
                <form phx-change="concepts_change_page_size" class="flex items-center gap-2">
                  <span class="text-slate-400">Page size:</span>
                  <select
                    name="page_size"
                    class="bg-slate-800 text-slate-300 rounded px-2 py-1"
                  >
                    <%= for size <- [5, 10, 25, 50] do %>
                      <option value={size} selected={@concepts_page_size == size}>
                        {size}
                      </option>
                    <% end %>
                  </select>
                </form>
                <div class="flex items-center gap-2">
                  <span class="text-slate-400">
                    Page {@concepts_page} of {total_pages} ({@concepts_total} total)
                  </span>
                  <div class="flex gap-1">
                    <button
                      phx-click="concepts_change_page"
                      phx-value-page={@concepts_page - 1}
                      disabled={@concepts_page == 1}
                      class={[
                        "px-2 py-1 rounded transition",
                        @concepts_page == 1 &&
                          "bg-slate-800 text-slate-600 cursor-not-allowed",
                        @concepts_page > 1 && "bg-slate-700 hover:bg-slate-600 text-slate-300"
                      ]}
                    >
                      ←
                    </button>
                    <button
                      phx-click="concepts_change_page"
                      phx-value-page={@concepts_page + 1}
                      disabled={@concepts_page >= total_pages}
                      class={[
                        "px-2 py-1 rounded transition",
                        @concepts_page >= total_pages &&
                          "bg-slate-800 text-slate-600 cursor-not-allowed",
                        @concepts_page < total_pages &&
                          "bg-slate-700 hover:bg-slate-600 text-slate-300"
                      ]}
                    >
                      →
                    </button>
                  </div>
                </div>
              </div>

              <%!-- Category Filter Tags --%>
              <% categories = @concepts |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort() %>
              <%= if categories != [] do %>
                <div class="flex flex-wrap gap-2 mb-3 pb-3 border-b border-slate-800">
                  <span class="text-xs text-slate-400 self-center">Filter:</span>
                  <%= for category <- categories do %>
                    <button
                      phx-click="filter_category"
                      phx-value-category={category}
                      class={[
                        "text-xs px-2 py-1 rounded transition",
                        @category_filter == category &&
                          "bg-blue-600 text-white font-medium",
                        @category_filter != category &&
                          "bg-slate-700 hover:bg-slate-600 text-slate-300"
                      ]}
                    >
                      {category}
                    </button>
                  <% end %>
                  <%= if @category_filter do %>
                    <button
                      phx-click="filter_category"
                      phx-value-category={@category_filter}
                      class="text-xs px-2 py-1 rounded bg-slate-800 text-slate-400 hover:text-slate-300"
                    >
                      ✕ Clear
                    </button>
                  <% end %>
                </div>
              <% end %>

              <%= if @generation_total > 0 and MapSet.size(@generating_concepts) > 0 do %>
                <div class="mb-4 p-3 bg-blue-900/30 border border-blue-700/50 rounded-lg">
                  <div class="flex items-center justify-between text-sm">
                    <span class="text-blue-300">
                      Generating: {@generation_completed} of {@generation_total}
                    </span>
                    <div class="w-24 h-2 bg-slate-700 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-blue-500 transition-all duration-300"
                        style={"width: #{if @generation_total > 0, do: (@generation_completed / @generation_total * 100), else: 0}%"}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <%!-- Scrollable Concepts List --%>
              <div class="overflow-y-auto space-y-1 max-h-[800px]">
                <% filtered_concepts =
                  if @category_filter,
                    do: Enum.filter(@concepts, &(&1.category == @category_filter)),
                    else: @concepts %>
                <%= for concept <- filtered_concepts do %>
                  <% concept_diagrams = diagrams_for_concept(@diagrams, concept.id) %>
                  <% is_expanded = MapSet.member?(@expanded_concepts, concept.id) %>

                  <div class="border border-slate-800 rounded-lg overflow-hidden">
                    <%!-- Concept Header --%>
                    <div
                      class="p-2 bg-slate-800/50 hover:bg-slate-800 cursor-pointer flex items-center gap-2"
                      phx-click="toggle_concept_expand"
                      phx-value-id={concept.id}
                    >
                      <span class="text-slate-400">
                        {if is_expanded, do: "▼", else: "▶"}
                      </span>
                      <div class="flex-1">
                        <div class="font-medium text-sm">{concept.name}</div>
                        <div class="flex gap-1 mt-1">
                          <span class="text-xs px-1.5 py-0.5 bg-slate-700 rounded">
                            {concept.category}
                          </span>
                          <%= if length(concept_diagrams) > 0 do %>
                            <span class="text-xs px-1.5 py-0.5 bg-blue-900/50 text-blue-300 rounded">
                              {length(concept_diagrams)} diagrams
                            </span>
                          <% end %>
                          <%= if Map.has_key?(@failed_generations, concept.id) do %>
                            <% error = @failed_generations[concept.id] %>
                            <span class={[
                              "text-xs px-1.5 py-0.5 rounded font-semibold",
                              error.severity == :critical && "bg-red-900/50 text-red-300",
                              error.severity == :high && "bg-orange-900/50 text-orange-300",
                              error.severity == :medium && "bg-yellow-900/50 text-yellow-300",
                              error.severity == :low && "bg-blue-900/50 text-blue-300"
                            ]}>
                              ⚠
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <%!-- Diagrams List (Expandable) --%>
                    <%= if is_expanded do %>
                      <div class="bg-slate-900/30">
                        <%= if length(concept_diagrams) > 0 do %>
                          <%= for diagram <- concept_diagrams do %>
                            <div
                              class={[
                                "pl-8 pr-2 py-2 text-sm cursor-pointer transition border-l-2",
                                @selected_diagram && @selected_diagram.id == diagram.id &&
                                  "bg-blue-900/30 border-blue-500 text-blue-200",
                                (!@selected_diagram || @selected_diagram.id != diagram.id) &&
                                  "border-transparent hover:bg-slate-800/50"
                              ]}
                              phx-click="select_diagram"
                              phx-value-id={diagram.id}
                            >
                              → {diagram.title}
                            </div>
                          <% end %>
                        <% else %>
                          <div class="pl-8 pr-2 py-2 text-sm text-slate-500">
                            <label class="flex items-center gap-2 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={MapSet.member?(@selected_concepts, concept.id)}
                                phx-click="toggle_concept"
                                phx-value-id={concept.id}
                              />
                              <span>Select to generate</span>
                            </label>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @concepts == [] do %>
                  <p class="text-sm text-slate-400 text-center py-4">
                    No concepts extracted yet. Upload a document to get started.
                  </p>
                <% end %>
              </div>
            </div>

            <%!-- Tips & Shortcuts (Bottom) --%>
            <div class="bg-slate-900 rounded-xl p-4 mt-auto">
              <div class="text-xs text-slate-400">
                <div class="font-semibold text-slate-300 mb-1.5">💡 Tips & Shortcuts</div>
                <ul class="space-y-0.5 list-disc pl-5">
                  <li>Click concept names to expand/collapse diagram lists</li>
                  <li>Select diagrams to view them in the main area</li>
                  <li>Use "Generate from Prompt" for custom diagrams</li>
                </ul>
              </div>
            </div>
          </div>

          <%!-- Right Main Area: Diagram Display + Generate --%>
          <div class="lg:col-span-3 space-y-4 flex flex-col">
            <%!-- Diagram Display (Top, Large) --%>
            <div class="bg-slate-900 rounded-xl p-6 flex-1 overflow-auto">
              <%= if @selected_diagram do %>
                <div class="space-y-4">
                  <%!-- Two-column header: Title/Summary + Notes --%>
                  <div class="grid grid-cols-2 gap-6">
                    <%!-- Left: Title, Summary, Tags --%>
                    <div>
                      <h2 class="text-2xl font-semibold mb-2">{@selected_diagram.title}</h2>
                      <p class="text-slate-300">{@selected_diagram.summary}</p>
                      <div class="flex gap-2 mt-2">
                        <span class="text-xs px-2 py-1 bg-slate-800 rounded">
                          {@selected_diagram.domain}
                        </span>
                        <%= for tag <- @selected_diagram.tags do %>
                          <span class="text-xs px-2 py-1 bg-slate-700 rounded">
                            {tag}
                          </span>
                        <% end %>
                      </div>
                    </div>

                    <%!-- Right: Notes --%>
                    <div>
                      <%= if @selected_diagram.notes_md do %>
                        <div class="text-sm text-slate-400">
                          <div class="font-semibold text-slate-300 mb-1.5">Notes</div>
                          <div class="overflow-y-auto max-h-24 [&_ul]:list-disc [&_ul]:pl-5 [&_ul]:space-y-0.5 [&_li]:ml-0">
                            {raw(markdown_to_html(@selected_diagram.notes_md))}
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <%!-- Save/Discard buttons for generated diagrams --%>
                  <%= if @generated_diagram do %>
                    <div class="flex gap-3 p-4 bg-blue-900/20 border border-blue-700/50 rounded-lg">
                      <button
                        phx-click="save_generated_diagram"
                        class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition-colors flex-1"
                      >
                        💾 Save Diagram
                      </button>
                      <button
                        phx-click="discard_generated_diagram"
                        class="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-medium transition-colors flex-1"
                      >
                        🗑️ Discard
                      </button>
                    </div>
                  <% end %>

                  <div
                    id="mermaid-preview"
                    phx-hook="Mermaid"
                    class="bg-white rounded-lg p-8"
                    data-diagram={@selected_diagram.diagram_source}
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
                    <p class="text-sm mt-1">Click on a diagram from the concepts tree</p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Generate from Prompt (Bottom) --%>
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
    </div>
    """
  end

  defp list_documents do
    Diagrams.list_documents()
  end

  defp list_concepts(opts) do
    Diagrams.list_concepts(opts)
  end

  defp count_concepts do
    Diagrams.count_concepts()
  end

  defp maybe_update_selected_document(socket, document_id) do
    if socket.assigns.selected_document && socket.assigns.selected_document.id == document_id do
      document = Diagrams.get_document!(document_id)
      # Reload all concepts since new concepts may have been added, using current pagination
      concepts =
        list_concepts(
          page: socket.assigns.concepts_page,
          page_size: socket.assigns.concepts_page_size
        )

      concepts_total = count_concepts()

      socket
      |> assign(:selected_document, document)
      |> assign(:concepts, concepts)
      |> assign(:concepts_total, concepts_total)
    else
      socket
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp format_status(status) do
    case status do
      :uploaded -> "Uploaded"
      :processing -> "Processing..."
      :ready -> "Ready"
      :error -> "Error"
      _ -> to_string(status)
    end
  end

  defp diagrams_for_concept(diagrams, concept_id) do
    Enum.filter(diagrams, fn d -> d.concept_id == concept_id end)
  end
end

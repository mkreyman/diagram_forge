defmodule DiagramForgeWeb.DiagramStudioLive do
  @moduledoc """
  Main LiveView for the Diagram Studio.

  Three-column layout:
  - Left: Document upload and listing
  - Middle: Concepts from selected document
  - Right: Diagrams and free-form generation
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
     |> assign(:concepts, [])
     |> assign(:selected_concepts, MapSet.new())
     |> assign(:diagrams, [])
     |> assign(:selected_diagram, nil)
     |> assign(:prompt, "")
     |> assign(:uploaded_files, [])
     |> assign(:generating, false)
     |> assign(:generating_concepts, MapSet.new())
     |> assign(:generation_total, 0)
     |> assign(:generation_completed, 0)
     |> allow_upload(:document,
       accept: ~w(.pdf .md .markdown),
       max_entries: 1,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_event("select_document", %{"id" => id}, socket) do
    document = Diagrams.get_document!(id)
    concepts = Diagrams.list_concepts_for_document(document.id)
    diagrams = Diagrams.list_diagrams_for_document(document.id)

    # Subscribe to generation progress for this document
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DiagramForge.PubSub, "diagram_generation:#{document.id}")
    end

    {:noreply,
     socket
     |> assign(:selected_document, document)
     |> assign(:concepts, concepts)
     |> assign(:diagrams, diagrams)
     |> assign(:selected_concepts, MapSet.new())
     |> assign(:selected_diagram, nil)
     |> assign(:generating_concepts, MapSet.new())
     |> assign(:generation_total, 0)
     |> assign(:generation_completed, 0)}
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
  def handle_event("generate_diagrams", _params, socket) do
    document_id = socket.assigns.selected_document.id
    selected_concept_ids = socket.assigns.selected_concepts

    selected_concept_ids
    |> Enum.each(fn concept_id ->
      %{"concept_id" => concept_id, "document_id" => document_id}
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
     |> assign(:generation_completed, 0)}
  end

  @impl true
  def handle_event("select_diagram", %{"id" => id}, socket) do
    diagram = Diagrams.get_diagram!(id)

    {:noreply, assign(socket, :selected_diagram, diagram)}
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
           |> assign(:diagrams, [diagram | socket.assigns.diagrams])
           |> assign(:prompt, "")
           |> assign(:generating, false)
           |> put_flash(:info, "Diagram generated!")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> put_flash(:error, "Failed to generate diagram: #{inspect(reason)}")}
      end
    end
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
  def handle_info({:generation_failed, concept_id, reason}, socket) do
    generating_concepts = MapSet.delete(socket.assigns.generating_concepts, concept_id)

    {:noreply,
     socket
     |> assign(:generating_concepts, generating_concepts)
     |> put_flash(:error, "Failed to generate diagram: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100">
      <div class="container mx-auto px-4 py-8">
        <h1 class="text-4xl font-bold mb-8 text-center">DiagramForge Studio</h1>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Left Column: Documents --%>
          <div class="space-y-4">
            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-xl font-semibold mb-4">Upload Document</h2>

              <form phx-change="validate" phx-submit="save" id="upload-form">
                <div class="space-y-4">
                  <div
                    class="border-2 border-dashed border-slate-700 rounded-lg p-6 text-center cursor-pointer hover:border-slate-600 transition"
                    phx-drop-target={@uploads.document.ref}
                  >
                    <.live_file_input upload={@uploads.document} class="hidden" />
                    <label for={@uploads.document.ref} class="cursor-pointer">
                      <div class="text-slate-400">
                        <p class="text-sm">Click to upload or drag and drop</p>
                        <p class="text-xs mt-1">PDF or Markdown (max 50MB)</p>
                      </div>
                    </label>
                  </div>

                  <%= for entry <- @uploads.document.entries do %>
                    <div class="text-sm text-slate-300">
                      {entry.client_name} ({div(entry.client_size, 1024)} KB)
                    </div>
                  <% end %>

                  <button
                    type="submit"
                    class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition"
                    disabled={@uploads.document.entries == []}
                  >
                    Upload
                  </button>
                </div>
              </form>
            </div>

            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-xl font-semibold mb-4">Documents</h2>

              <div class="space-y-2">
                <%= for doc <- @documents do %>
                  <div
                    class={[
                      "p-3 rounded-lg cursor-pointer transition",
                      @selected_document && @selected_document.id == doc.id &&
                        "bg-slate-800 border border-slate-600",
                      (!@selected_document || @selected_document.id != doc.id) &&
                        "bg-slate-800/50 hover:bg-slate-800"
                    ]}
                    phx-click="select_document"
                    phx-value-id={doc.id}
                  >
                    <div class="flex items-center justify-between mb-1">
                      <span class="text-sm font-medium truncate">{doc.title}</span>
                      <span class={[
                        "text-xs px-2 py-1 rounded font-medium",
                        doc.status == :ready && "bg-green-900/50 text-green-300",
                        doc.status == :processing && "bg-yellow-900/50 text-yellow-300 animate-pulse",
                        doc.status == :uploaded && "bg-blue-900/50 text-blue-300",
                        doc.status == :error && "bg-red-900/50 text-red-300"
                      ]}>
                        {format_status(doc.status)}
                      </span>
                    </div>
                    <%= if doc.status == :error and doc.error_message do %>
                      <div class="text-xs text-red-400 mt-2">
                        Error: {doc.error_message}
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if @documents == [] do %>
                  <p class="text-sm text-slate-400 text-center py-4">No documents yet</p>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Middle Column: Concepts --%>
          <div class="space-y-4">
            <div class="bg-slate-900 rounded-xl p-4">
              <div class="flex items-center justify-between mb-4">
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

              <%= if @generation_total > 0 do %>
                <div class="mb-4 p-3 bg-blue-900/30 border border-blue-700/50 rounded-lg">
                  <div class="flex items-center justify-between text-sm">
                    <span class="text-blue-300">
                      Generating diagrams: {@generation_completed} of {@generation_total}
                    </span>
                    <div class="w-32 h-2 bg-slate-700 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-blue-500 transition-all duration-300"
                        style={"width: #{if @generation_total > 0, do: (@generation_completed / @generation_total * 100), else: 0}%"}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <div class="space-y-2">
                <%= if @selected_document do %>
                  <%= for concept <- @concepts do %>
                    <div class="p-3 bg-slate-800/50 rounded-lg">
                      <label class="flex items-start gap-3 cursor-pointer">
                        <input
                          type="checkbox"
                          class="mt-1"
                          checked={MapSet.member?(@selected_concepts, concept.id)}
                          phx-click="toggle_concept"
                          phx-value-id={concept.id}
                        />
                        <div class="flex-1">
                          <div class="font-medium">{concept.name}</div>
                          <div class="text-sm text-slate-400 mt-1">
                            {concept.short_description}
                          </div>
                          <div class="flex gap-2 mt-2">
                            <span class="text-xs px-2 py-1 bg-slate-700 rounded">
                              {concept.category}
                            </span>
                            <span class="text-xs px-2 py-1 bg-slate-700 rounded">
                              {concept.level}
                            </span>
                          </div>
                        </div>
                      </label>
                    </div>
                  <% end %>

                  <%= if @concepts == [] do %>
                    <p class="text-sm text-slate-400 text-center py-4">
                      <%= if @selected_document.status == :processing do %>
                        Processing document...
                      <% else %>
                        No concepts extracted yet
                      <% end %>
                    </p>
                  <% end %>
                <% else %>
                  <p class="text-sm text-slate-400 text-center py-4">
                    Select a document to view concepts
                  </p>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right Column: Diagrams --%>
          <div class="space-y-4">
            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-xl font-semibold mb-4">Diagrams</h2>

              <%= if @diagrams != [] do %>
                <div class="space-y-2 mb-4">
                  <%= for diagram <- @diagrams do %>
                    <div
                      class={[
                        "p-2 rounded cursor-pointer transition",
                        @selected_diagram && @selected_diagram.id == diagram.id &&
                          "bg-slate-700",
                        (!@selected_diagram || @selected_diagram.id != diagram.id) &&
                          "bg-slate-800 hover:bg-slate-700"
                      ]}
                      phx-click="select_diagram"
                      phx-value-id={diagram.id}
                    >
                      <div class="text-sm font-medium">{diagram.title}</div>
                      <div class="text-xs text-slate-400">{diagram.domain} · {diagram.level}</div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if @selected_diagram do %>
                <div class="space-y-3 border-t border-slate-800 pt-4">
                  <h3 class="font-semibold">{@selected_diagram.title}</h3>
                  <p class="text-sm text-slate-300">{@selected_diagram.summary}</p>

                  <div
                    id="mermaid-preview"
                    phx-hook="Mermaid"
                    class="bg-white rounded p-4"
                    data-diagram={@selected_diagram.diagram_source}
                  >
                    <pre class="mermaid">{@selected_diagram.diagram_source}</pre>
                  </div>

                  <%= if @selected_diagram.notes_md do %>
                    <div class="text-sm text-slate-300 prose prose-invert max-w-none">
                      {raw(@selected_diagram.notes_md)}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="bg-slate-900 rounded-xl p-4">
              <h2 class="text-xl font-semibold mb-4">Generate from Prompt</h2>

              <form phx-submit="generate_from_prompt" class="space-y-3">
                <textarea
                  name="prompt"
                  value={@prompt}
                  phx-change="update_prompt"
                  placeholder="e.g., Create a diagram showing how GenServer handles messages"
                  class="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded focus:border-slate-600 focus:outline-none resize-y"
                  rows="4"
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

  defp maybe_update_selected_document(socket, document_id) do
    if socket.assigns.selected_document && socket.assigns.selected_document.id == document_id do
      document = Diagrams.get_document!(document_id)
      concepts = Diagrams.list_concepts_for_document(document.id)

      socket
      |> assign(:selected_document, document)
      |> assign(:concepts, concepts)
    else
      socket
    end
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
end

defmodule DiagramForge.Diagrams do
  @moduledoc """
  The Diagrams context - handles documents, concepts, and diagrams.
  """

  import Ecto.Query, warn: false
  alias DiagramForge.Repo

  alias DiagramForge.Diagrams.{Concept, Diagram, Document}
  alias DiagramForge.Diagrams.Workers.ProcessDocumentJob

  # Documents

  @doc """
  Returns the list of documents.

  ## Examples

      iex> list_documents()
      [%Document{}, ...]

  """
  def list_documents do
    Repo.all(from d in Document, order_by: [desc: d.inserted_at])
  end

  @doc """
  Gets a single document.

  Raises `Ecto.NoResultsError` if the Document does not exist.
  """
  def get_document!(id), do: Repo.get!(Document, id)

  @doc """
  Updates a document.

  ## Examples

      iex> update_document(document, %{title: "New Title"})
      {:ok, %Document{}}

  """
  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_doc} ->
        Phoenix.PubSub.broadcast(
          DiagramForge.PubSub,
          "documents",
          {:document_updated, updated_doc.id}
        )

        {:ok, updated_doc}

      error ->
        error
    end
  end

  @doc """
  Creates a document.

  ## Examples

      iex> create_document(%{title: "My Doc", source_type: :pdf, path: "/path/to/doc.pdf"})
      {:ok, %Document{}}

  """
  def create_document(attrs \\ %{}) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a document and enqueues it for processing.

  ## Examples

      iex> upload_document(%{title: "My Doc", source_type: :pdf, path: "/path/to/doc.pdf"})
      {:ok, %Document{}}

  """
  def upload_document(attrs \\ %{}) do
    changeset = Document.changeset(%Document{}, attrs)

    case Repo.insert(changeset) do
      {:ok, document} ->
        # Enqueue the background job to process this document
        %{"document_id" => document.id}
        |> ProcessDocumentJob.new()
        |> Oban.insert()

        {:ok, document}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Concepts

  @doc """
  Lists all concepts with pagination.

  ## Options

    * `:page` - Page number (default: 1)
    * `:page_size` - Number of concepts per page (default: 10)
    * `:only_with_diagrams` - Only return concepts that have diagrams (default: false)

  ## Examples

      iex> list_concepts(page: 1, page_size: 20)
      [%Concept{}, ...]

      iex> list_concepts(page: 2, page_size: 50, only_with_diagrams: true)
      [%Concept{}, ...]
  """
  def list_concepts(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    only_with_diagrams = Keyword.get(opts, :only_with_diagrams, false)
    document_id = Keyword.get(opts, :document_id)
    search_query = Keyword.get(opts, :search_query, "")
    offset = (page - 1) * page_size

    base_query = from(c in Concept)

    needs_distinct = document_id != nil or only_with_diagrams or search_query != ""

    query =
      base_query
      |> maybe_filter_by_document(document_id)
      |> maybe_filter_by_diagrams(only_with_diagrams, document_id)
      |> maybe_filter_by_search(search_query)
      |> maybe_add_distinct(needs_distinct)
      |> order_by([c], asc: c.name)
      |> limit(^page_size)
      |> offset(^offset)

    Repo.all(query)
  end

  defp maybe_filter_by_document(query, nil), do: query

  defp maybe_filter_by_document(query, document_id) do
    # Filter by either:
    # 1. Concepts that originated from this document (document_id set), OR
    # 2. Concepts that have diagrams for this document
    from c in query,
      left_join: d in assoc(c, :diagrams),
      where: c.document_id == ^document_id or d.document_id == ^document_id
  end

  defp maybe_filter_by_diagrams(query, false, _document_id), do: query

  defp maybe_filter_by_diagrams(query, true, nil) do
    # No document selected - show concepts with any diagrams
    from c in query,
      join: d in assoc(c, :diagrams)
  end

  defp maybe_filter_by_diagrams(query, true, document_id) do
    # Document selected - show concepts with diagrams for this document
    from c in query,
      join: d in assoc(c, :diagrams),
      where: d.document_id == ^document_id
  end

  defp maybe_filter_by_search(query, ""), do: query

  defp maybe_filter_by_search(query, search_query) do
    # Search diagrams by title or summary, then filter concepts that have matching diagrams
    search_pattern = "%#{search_query}%"

    from c in query,
      join: d in assoc(c, :diagrams),
      where: ilike(d.title, ^search_pattern) or ilike(d.summary, ^search_pattern)
  end

  defp maybe_add_distinct(query, false), do: query

  defp maybe_add_distinct(query, true) do
    from c in query, distinct: true
  end

  # Count-specific filters that don't use distinct (since count uses count(distinct))
  defp maybe_filter_by_document_for_count(query, nil), do: query

  defp maybe_filter_by_document_for_count(query, document_id) do
    from c in query,
      left_join: d in assoc(c, :diagrams),
      where: c.document_id == ^document_id or d.document_id == ^document_id
  end

  defp maybe_filter_by_diagrams_for_count(query, false, _document_id), do: query

  defp maybe_filter_by_diagrams_for_count(query, true, nil) do
    # No document selected - count concepts with any diagrams
    from c in query,
      join: d in assoc(c, :diagrams)
  end

  defp maybe_filter_by_diagrams_for_count(query, true, document_id) do
    # Document selected - count concepts with diagrams for this document
    from c in query,
      join: d in assoc(c, :diagrams),
      where: d.document_id == ^document_id
  end

  defp maybe_filter_by_search_for_count(query, ""), do: query

  defp maybe_filter_by_search_for_count(query, search_query) do
    # Search diagrams by title or summary, then count concepts that have matching diagrams
    search_pattern = "%#{search_query}%"

    from c in query,
      join: d in assoc(c, :diagrams),
      where: ilike(d.title, ^search_pattern) or ilike(d.summary, ^search_pattern)
  end

  @doc """
  Counts total number of concepts.

  ## Options

    * `:only_with_diagrams` - Only count concepts that have diagrams (default: false)
    * `:document_id` - Only count concepts for a specific document (optional)
    * `:search_query` - Search query for filtering by diagram title/summary (optional)
  """
  def count_concepts(opts \\ []) do
    only_with_diagrams = Keyword.get(opts, :only_with_diagrams, false)
    document_id = Keyword.get(opts, :document_id)
    search_query = Keyword.get(opts, :search_query, "")

    base_query = from(c in Concept, select: count(c.id, :distinct))

    query =
      base_query
      |> maybe_filter_by_document_for_count(document_id)
      |> maybe_filter_by_diagrams_for_count(only_with_diagrams, document_id)
      |> maybe_filter_by_search_for_count(search_query)

    Repo.one(query) || 0
  end

  @doc """
  Lists concepts for a given document.

  Since concepts are globally unique, this finds all concepts that have
  diagrams associated with the given document.
  """
  def list_concepts_for_document(document_id) do
    Repo.all(
      from c in Concept,
        join: d in assoc(c, :diagrams),
        where: d.document_id == ^document_id,
        distinct: c.id,
        order_by: [asc: c.name]
    )
  end

  @doc """
  Gets a single concept.
  """
  def get_concept!(id), do: Repo.get!(Concept, id)

  # Diagrams

  @doc """
  Lists all diagrams.
  """
  def list_diagrams do
    Repo.all(from d in Diagram, order_by: [desc: d.inserted_at])
  end

  @doc """
  Lists diagrams for a given concept.
  """
  def list_diagrams_for_concept(concept_id) do
    Repo.all(
      from d in Diagram,
        where: d.concept_id == ^concept_id,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc """
  Lists diagrams for a given document.
  """
  def list_diagrams_for_document(document_id) do
    Repo.all(
      from d in Diagram,
        where: d.document_id == ^document_id,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc """
  Gets a single diagram.
  """
  def get_diagram!(id) do
    Diagram
    |> Repo.get!(id)
    |> Repo.preload(:document)
  end

  @doc """
  Gets a diagram by slug.
  """
  def get_diagram_by_slug(slug) do
    Diagram
    |> Repo.get_by(slug: slug)
    |> Repo.preload(:document)
  end

  @doc """
  Saves a generated diagram to the database.

  Takes an unsaved diagram struct (typically from `generate_diagram_from_prompt/2`)
  and persists it to the database.

  ## Examples

      iex> {:ok, unsaved_diagram} = generate_diagram_from_prompt("...", [])
      iex> save_generated_diagram(unsaved_diagram)
      {:ok, %Diagram{id: 123, ...}}
  """
  def save_generated_diagram(%Diagram{} = diagram) do
    diagram
    |> Diagram.changeset(%{})
    |> Repo.insert()
  end

  @doc """
  Generates a diagram from a free-form text prompt.

  ## Examples

      iex> generate_diagram_from_prompt("Create a diagram about GenServer message handling", [])
      {:ok, %Diagram{}}

  ## Options

    * `:ai_client` - AI client module to use (defaults to configured client)

  """
  def generate_diagram_from_prompt(prompt, opts) do
    alias DiagramForge.Diagrams.DiagramGenerator

    DiagramGenerator.generate_from_prompt(prompt, opts)
  end
end

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
    offset = (page - 1) * page_size

    base_query = from(c in Concept)

    query =
      base_query
      |> maybe_filter_by_document(document_id)
      |> maybe_filter_by_diagrams(only_with_diagrams)
      |> order_by([c], asc: c.name)
      |> limit(^page_size)
      |> offset(^offset)

    Repo.all(query)
  end

  defp maybe_filter_by_document(query, nil), do: query

  defp maybe_filter_by_document(query, document_id) do
    from c in query, where: c.document_id == ^document_id
  end

  defp maybe_filter_by_diagrams(query, false), do: query

  defp maybe_filter_by_diagrams(query, true) do
    from c in query,
      join: d in assoc(c, :diagrams),
      distinct: c.id
  end

  @doc """
  Counts total number of concepts.

  ## Options

    * `:only_with_diagrams` - Only count concepts that have diagrams (default: false)
    * `:document_id` - Only count concepts for a specific document (optional)
  """
  def count_concepts(opts \\ []) do
    only_with_diagrams = Keyword.get(opts, :only_with_diagrams, false)
    document_id = Keyword.get(opts, :document_id)

    base_query = from(c in Concept)

    query =
      base_query
      |> maybe_filter_by_document(document_id)
      |> maybe_filter_by_diagrams(only_with_diagrams)

    Repo.aggregate(query, :count)
  end

  @doc """
  Lists concepts for a given document.
  """
  def list_concepts_for_document(document_id) do
    Repo.all(
      from c in Concept,
        where: c.document_id == ^document_id,
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
  def get_diagram!(id), do: Repo.get!(Diagram, id)

  @doc """
  Gets a diagram by slug.
  """
  def get_diagram_by_slug(slug), do: Repo.get_by(Diagram, slug: slug)

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

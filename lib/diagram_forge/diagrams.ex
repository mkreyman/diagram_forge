defmodule DiagramForge.Diagrams do
  @moduledoc """
  The Diagrams context - handles documents, concepts, and diagrams.
  """

  import Ecto.Query, warn: false
  alias DiagramForge.Repo

  alias DiagramForge.Diagrams.{Diagram, Document}
  alias DiagramForge.Diagrams.Workers.ProcessDocumentJob

  # Documents

  @doc """
  Returns the list of documents that should be visible.

  Documents are visible if:
  - They are currently being processed (status: :uploaded or :processing), OR
  - They were completed within the last 5 minutes (status: :ready or :error with completed_at within 5 minutes)

  ## Examples

      iex> list_documents()
      [%Document{}, ...]

  """
  def list_documents do
    five_minutes_ago = DateTime.utc_now() |> DateTime.add(-5, :minute)

    query =
      from d in Document,
        where:
          d.status in [:uploaded, :processing] or
            (d.status in [:ready, :error] and d.completed_at >= ^five_minutes_ago),
        order_by: [desc: d.inserted_at]

    Repo.all(query)
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

  # Diagrams

  @doc """
  Lists all diagrams.
  """
  def list_diagrams do
    Repo.all(from d in Diagram, order_by: [desc: d.inserted_at])
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

  # Tag Management Functions

  @doc """
  Lists all unique tags across all diagrams a user can access.

  Used for tag autocomplete and tag cloud.
  """
  def list_available_tags(_user_id) do
    # For now, just get all tags from all diagrams
    # In the future when we have user_diagrams join table, we'll filter by user
    query =
      from d in Diagram,
        select: d.tags

    Repo.all(query)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Gets tag counts for all diagrams.

  Returns a map of tag => count for displaying tag clouds.
  """
  def get_tag_counts(_user_id) do
    # For now, just get all tags from all diagrams
    # In the future when we have user_diagrams join table, we'll filter by user
    query =
      from d in Diagram,
        select: d.tags

    Repo.all(query)
    |> List.flatten()
    |> Enum.frequencies()
  end

  @doc """
  Adds tags to a diagram.
  """
  def add_tags(%Diagram{} = diagram, new_tags, _user_id) when is_list(new_tags) do
    current_tags = diagram.tags || []
    updated_tags = (current_tags ++ new_tags) |> Enum.uniq()

    diagram
    |> Diagram.changeset(%{tags: updated_tags})
    |> Repo.update()
  end

  @doc """
  Removes tags from a diagram.
  """
  def remove_tags(%Diagram{} = diagram, tags_to_remove, _user_id) when is_list(tags_to_remove) do
    current_tags = diagram.tags || []
    updated_tags = current_tags -- tags_to_remove

    diagram
    |> Diagram.changeset(%{tags: updated_tags})
    |> Repo.update()
  end

  # Saved Filter Functions

  alias DiagramForge.Diagrams.SavedFilter

  @doc """
  Lists all saved filters for a user.
  """
  def list_saved_filters(user_id) do
    Repo.all(
      from f in SavedFilter,
        where: f.user_id == ^user_id,
        order_by: [asc: f.sort_order]
    )
  end

  @doc """
  Lists only pinned saved filters for a user (for sidebar display).
  """
  def list_pinned_filters(user_id) do
    Repo.all(
      from f in SavedFilter,
        where: f.user_id == ^user_id and f.is_pinned == true,
        order_by: [asc: f.sort_order]
    )
  end

  @doc """
  Gets a saved filter by ID.
  """
  def get_saved_filter!(id), do: Repo.get!(SavedFilter, id)

  @doc """
  Creates a saved filter for a user.
  """
  def create_saved_filter(attrs, user_id) do
    # Get current max sort_order for user
    max_sort_order =
      Repo.one(
        from f in SavedFilter,
          where: f.user_id == ^user_id,
          select: max(f.sort_order)
      ) || 0

    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put_new(:sort_order, max_sort_order + 1)

    %SavedFilter{}
    |> SavedFilter.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a saved filter (only owner can update).
  """
  def update_saved_filter(%SavedFilter{} = filter, attrs, user_id) do
    if filter.user_id == user_id do
      filter
      |> SavedFilter.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a saved filter (only owner can delete).
  """
  def delete_saved_filter(%SavedFilter{} = filter, user_id) do
    if filter.user_id == user_id do
      Repo.delete(filter)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Reorders saved filters by updating sort_order.

  Takes a list of filter IDs in the desired order.
  """
  def reorder_saved_filters(filter_ids, user_id) when is_list(filter_ids) do
    Repo.transaction(fn ->
      filter_ids
      |> Enum.with_index()
      |> Enum.each(&update_filter_sort_order(&1, user_id))
    end)
  end

  defp update_filter_sort_order({filter_id, index}, user_id) do
    filter = Repo.get!(SavedFilter, filter_id)

    if filter.user_id == user_id do
      filter
      |> SavedFilter.changeset(%{sort_order: index})
      |> Repo.update!()
    else
      Repo.rollback(:unauthorized)
    end
  end

  # Tag-Based Query Functions

  @doc """
  Lists diagrams matching a tag filter.

  Empty tag list means "show all diagrams".
  Tags are combined with AND logic (diagram must have ALL tags).
  """
  def list_diagrams_by_tags(_user_id, tags, _ownership \\ :all)

  def list_diagrams_by_tags(_user_id, [], _ownership) do
    # Empty tags means show all
    list_diagrams()
  end

  def list_diagrams_by_tags(_user_id, tags, _ownership) when is_list(tags) do
    # Build query with tag filter (must have ALL tags)
    query =
      Enum.reduce(tags, from(d in Diagram), fn tag, acc ->
        from d in acc,
          where: ^tag in d.tags
      end)

    # Execute with ordering
    query
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists diagrams matching a saved filter.
  """
  def list_diagrams_by_saved_filter(user_id, %SavedFilter{} = filter) do
    list_diagrams_by_tags(user_id, filter.tag_filter, :all)
  end

  @doc """
  Gets counts for a saved filter (how many diagrams match).
  """
  def get_saved_filter_count(user_id, %SavedFilter{} = filter) do
    diagrams = list_diagrams_by_tags(user_id, filter.tag_filter, :all)
    length(diagrams)
  end

  # Fork and Bookmark Functions

  @doc """
  Forks a diagram.

  Creates a new diagram with:
  - All data copied from original
  - Tags copied from original (user can edit after)
  - New ID generated
  - forked_from_id set to original
  """
  def fork_diagram(original_id, _user_id) do
    Repo.transaction(fn ->
      original = Repo.get!(Diagram, original_id)

      # Create new diagram with copied data
      new_diagram_attrs = %{
        title: original.title,
        diagram_source: original.diagram_source,
        summary: original.summary,
        notes_md: original.notes_md,
        tags: original.tags,
        format: original.format,
        slug: generate_unique_slug(original.slug),
        visibility: :unlisted,
        forked_from_id: original.id
      }

      case %Diagram{}
           |> Diagram.changeset(new_diagram_attrs)
           |> Repo.insert() do
        {:ok, diagram} -> diagram
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Bookmarks/saves a diagram for a user.

  For now this is a placeholder - we'll implement user_diagrams join table later.
  """
  def bookmark_diagram(_diagram_id, _user_id) do
    {:error, :not_implemented}
  end

  defp generate_unique_slug(original_slug) do
    timestamp = :os.system_time(:millisecond)
    "#{original_slug}-fork-#{timestamp}"
  end
end

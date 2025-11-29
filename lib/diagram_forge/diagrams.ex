defmodule DiagramForge.Diagrams do
  @moduledoc """
  The Diagrams context - handles documents, concepts, and diagrams.
  """

  import Ecto.Query, warn: false
  alias DiagramForge.Repo

  alias DiagramForge.Accounts.User
  alias DiagramForge.Diagrams.{Diagram, Document, UserDiagram}
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
  Cancels document processing by cancelling any pending Oban jobs and marking
  the document as error with a cancelled message.

  ## Examples

      iex> cancel_document_processing(document_id)
      {:ok, %Document{}}

  """
  def cancel_document_processing(document_id) do
    document = get_document!(document_id)

    # Cancel any pending/scheduled Oban jobs for this document
    cancel_oban_jobs_for_document(document_id)

    # Mark document as cancelled (using error status)
    update_document(document, %{
      status: :error,
      error_message: "Cancelled by user",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp cancel_oban_jobs_for_document(document_id) do
    import Ecto.Query

    # Find all jobs for this document that are available or scheduled
    jobs =
      Oban.Job
      |> where([j], j.queue == "documents")
      |> where([j], j.state in ["available", "scheduled"])
      |> where([j], fragment("?->>'document_id' = ?", j.args, ^to_string(document_id)))
      |> Repo.all()

    # Cancel each job
    Enum.each(jobs, fn job ->
      Oban.cancel_job(job.id)
    end)

    length(jobs)
  end

  @doc """
  Creates a document for a user.

  ## Examples

      iex> create_document(%{title: "My Doc", source_type: :pdf, path: "/path/to/doc.pdf"}, user_id)
      {:ok, %Document{}}

  """
  def create_document(attrs, user_id) do
    %Document{user_id: user_id}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a document for a user and enqueues it for processing.

  ## Examples

      iex> upload_document(%{title: "My Doc", source_type: :pdf, path: "/path/to/doc.pdf"}, user_id)
      {:ok, %Document{}}

  """
  def upload_document(attrs, user_id) do
    changeset = Document.changeset(%Document{user_id: user_id}, attrs)

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

  # Authorization Functions

  @doc """
  Checks if a user owns a diagram.
  """
  def user_owns_diagram?(nil, _user_id), do: false

  def user_owns_diagram?(diagram_id, user_id) do
    Repo.exists?(
      from ud in UserDiagram,
        where:
          ud.diagram_id == ^diagram_id and
            ud.user_id == ^user_id and
            ud.is_owner == true
    )
  end

  @doc """
  Checks if a user has bookmarked a diagram.
  """
  def user_bookmarked_diagram?(nil, _user_id), do: false

  def user_bookmarked_diagram?(diagram_id, user_id) do
    Repo.exists?(
      from ud in UserDiagram,
        where:
          ud.diagram_id == ^diagram_id and
            ud.user_id == ^user_id and
            ud.is_owner == false
    )
  end

  @doc """
  Gets the owner of a diagram (first user with is_owner: true).
  Returns nil if no owner exists.
  """
  def get_diagram_owner(diagram_id) do
    Repo.one(
      from u in User,
        join: ud in UserDiagram,
        on: ud.user_id == u.id,
        where: ud.diagram_id == ^diagram_id and ud.is_owner == true,
        limit: 1
    )
  end

  @doc """
  Checks if a user can view a diagram based on visibility rules.

  - Private: Only owner can view
  - Unlisted: Anyone can view
  - Public: Anyone can view
  """
  def can_view_diagram?(%Diagram{} = diagram, user) do
    case diagram.visibility do
      :private -> user && user_owns_diagram?(diagram.id, user.id)
      :unlisted -> true
      :public -> true
    end
  end

  @doc """
  Checks if a user can edit a diagram (must be owner).
  """
  def can_edit_diagram?(%Diagram{} = diagram, user) do
    user && user_owns_diagram?(diagram.id, user.id)
  end

  @doc """
  Checks if a user can delete a diagram (must be owner).
  """
  def can_delete_diagram?(%Diagram{} = diagram, user) do
    user && user_owns_diagram?(diagram.id, user.id)
  end

  # Diagrams

  @doc """
  Lists all diagrams.
  """
  def list_diagrams do
    Repo.all(from d in Diagram, order_by: [desc: d.inserted_at])
  end

  @doc """
  Gets a single diagram by ID.

  Returns `{:ok, diagram}` or `{:error, :not_found}`.
  """
  def get_diagram(id) do
    case Repo.get(Diagram, id) do
      nil -> {:error, :not_found}
      diagram -> {:ok, diagram}
    end
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
  Lists diagrams owned by a user (is_owner: true).
  """
  def list_owned_diagrams(user_id) do
    Repo.all(
      from d in Diagram,
        join: ud in UserDiagram,
        on: ud.diagram_id == d.id,
        where: ud.user_id == ^user_id and ud.is_owner == true,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc """
  Lists diagrams bookmarked by a user (is_owner: false).
  """
  def list_bookmarked_diagrams(user_id) do
    Repo.all(
      from d in Diagram,
        join: ud in UserDiagram,
        on: ud.diagram_id == d.id,
        where: ud.user_id == ^user_id and ud.is_owner == false,
        order_by: [desc: d.inserted_at]
    )
  end

  @doc """
  Lists all public diagrams for discovery feed.
  Optionally filters by tags (AND logic - must have ALL tags).
  """
  def list_public_diagrams(tags \\ [])

  def list_public_diagrams([]) do
    Repo.all(
      from d in Diagram,
        where: d.visibility == :public,
        order_by: [desc: d.inserted_at]
    )
  end

  def list_public_diagrams(tags) when is_list(tags) do
    base_query =
      from d in Diagram,
        where: d.visibility == :public

    # Add tag filter (OR logic - diagram must have at least one of the tags)
    query =
      if tags == [] do
        base_query
      else
        from d in base_query,
          where: fragment("? && ?", d.tags, ^tags)
      end

    query
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns all public and approved diagrams for sitemap generation.

  Only returns diagrams that are:
  - visibility: :public
  - moderation_status: :approved

  Results are ordered by updated_at descending.
  """
  def list_public_approved_diagrams do
    Repo.all(
      from d in Diagram,
        where: d.visibility == :public and d.moderation_status == :approved,
        order_by: [desc: d.updated_at],
        select: %{id: d.id, title: d.title, updated_at: d.updated_at}
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
  Creates a diagram with user ownership.

  Creates both the diagram and the user_diagrams entry with is_owner: true.
  Broadcasts `:diagram_created` message for real-time UI updates.
  """
  def create_diagram_for_user(attrs, user_id) do
    result =
      Repo.transaction(fn ->
        diagram_changeset = Diagram.changeset(%Diagram{}, attrs)

        case Repo.insert(diagram_changeset) do
          {:ok, diagram} ->
            create_user_diagram_entry(diagram, user_id)

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    broadcast_if_created(result)
  end

  defp broadcast_if_created({:ok, diagram}) do
    Phoenix.PubSub.broadcast(
      DiagramForge.PubSub,
      "diagrams",
      {:diagram_created, diagram.id}
    )

    {:ok, diagram}
  end

  defp broadcast_if_created(error), do: error

  defp create_user_diagram_entry(diagram, user_id) do
    user_diagram_changeset =
      UserDiagram.changeset(%UserDiagram{}, %{
        user_id: user_id,
        diagram_id: diagram.id,
        is_owner: true
      })

    case Repo.insert(user_diagram_changeset) do
      {:ok, _user_diagram} -> diagram
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Updates a diagram (only owner can update).
  """
  def update_diagram(%Diagram{} = diagram, attrs, user_id) do
    if can_edit_diagram?(diagram, %{id: user_id}) do
      diagram
      |> Diagram.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a diagram (only owner can delete).

  Cascades to user_diagrams automatically.
  """
  def delete_diagram(%Diagram{} = diagram, user_id) do
    if can_delete_diagram?(diagram, %{id: user_id}) do
      Repo.delete(diagram)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Generates a diagram from a free-form text prompt.

  ## Examples

      iex> generate_diagram_from_prompt("Create a diagram about GenServer message handling", [])
      {:ok, %Diagram{}}

  ## Options

    * `:ai_client` - AI client module to use (defaults to configured client)
    * `:user_id` - User ID for usage tracking
    * `:operation` - Operation type for usage tracking (defaults to "diagram_generation")

  """
  def generate_diagram_from_prompt(prompt, opts) do
    alias DiagramForge.Diagrams.DiagramGenerator

    DiagramGenerator.generate_from_prompt(prompt, opts)
  end

  @doc """
  Attempts to fix Mermaid syntax errors in a diagram.

  First tries programmatic sanitization for common issues (fast, free, deterministic).
  If no changes are made, falls back to AI-based fixing with retries.

  Returns {:ok, fixed_source}, {:unchanged, source}, or {:error, reason}.

  ## Options

    * `:ai_client` - AI client module to use (defaults to configured client)
    * `:user_id` - User ID for usage tracking (required unless track_usage: false)
    * `:operation` - Operation type for usage tracking (defaults to "syntax_fix")
    * `:track_usage` - Whether to track token usage (default: true)
    * `:skip_sanitizer` - Skip programmatic sanitizer, go straight to AI (default: false)

  ## Raises

  Raises `ArgumentError` if `:user_id` is missing when usage tracking is enabled.
  """
  def fix_diagram_syntax(%Diagram{} = diagram, opts \\ []) do
    fix_diagram_syntax_source(diagram.diagram_source, diagram.summary, opts)
  end

  defp do_fix_diagram_syntax_with_ai(original_source, summary, opts, retries_left) do
    alias DiagramForge.AI.Client
    alias DiagramForge.AI.Prompts

    # Validate options early - fail fast if user_id missing with tracking enabled
    ai_opts = build_ai_opts!(opts, "syntax_fix")
    ai_client = opts[:ai_client] || Application.get_env(:diagram_forge, :ai_client, Client)
    mermaid_error = opts[:mermaid_error]
    user_prompt = Prompts.fix_mermaid_syntax_prompt(original_source, summary, mermaid_error)

    try do
      json =
        ai_client.chat!(
          [
            %{"role" => "system", "content" => Prompts.diagram_system_prompt()},
            %{"role" => "user", "content" => user_prompt}
          ],
          ai_opts
        )
        |> Jason.decode!()

      case json do
        %{"mermaid" => fixed_mermaid} when is_binary(fixed_mermaid) ->
          # If the AI returned unchanged code, retry or report unchanged
          if normalize_whitespace(fixed_mermaid) == normalize_whitespace(original_source) do
            if retries_left > 0 do
              do_fix_diagram_syntax_with_ai(original_source, summary, opts, retries_left - 1)
            else
              # All retries exhausted, AI couldn't fix it
              {:unchanged, original_source}
            end
          else
            {:ok, fixed_mermaid}
          end

        _ ->
          {:error, "Invalid response from AI"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp normalize_whitespace(str) do
    str
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  @doc """
  Attempts to fix Mermaid syntax errors, working directly with source code.

  First tries programmatic sanitization for common issues (fast, free, deterministic).
  If no changes are made, falls back to AI-based fixing with retries.

  This is useful for fixing unsaved/generated diagrams that don't have an ID yet.

  ## Options

    * `:ai_client` - AI client module to use (defaults to configured client)
    * `:user_id` - User ID for usage tracking (required unless track_usage: false)
    * `:operation` - Operation type for usage tracking (defaults to "syntax_fix")
    * `:track_usage` - Whether to track token usage (default: true)
    * `:skip_sanitizer` - Skip programmatic sanitizer, go straight to AI (default: false)

  ## Raises

  Raises `ArgumentError` if `:user_id` is missing when usage tracking is enabled.
  """
  def fix_diagram_syntax_source(diagram_source, summary, opts \\ []) do
    alias DiagramForge.Diagrams.MermaidSanitizer

    skip_sanitizer = Keyword.get(opts, :skip_sanitizer, false)

    # Step 1: Try programmatic sanitization first (fast, free, deterministic)
    case {skip_sanitizer, MermaidSanitizer.sanitize(diagram_source)} do
      {false, {:ok, sanitized}} ->
        # Programmatic fix worked!
        {:ok, sanitized}

      _ ->
        # No programmatic fix available, try AI
        max_retries = Keyword.get(opts, :max_retries, 3)
        do_fix_diagram_syntax_with_ai(diagram_source, summary, opts, max_retries)
    end
  end

  # Tag Management Functions

  @doc """
  Lists all unique tags across all diagrams a user can access.

  Used for tag autocomplete and tag cloud.
  """
  def list_available_tags(user_id) do
    query =
      from d in Diagram,
        join: ud in UserDiagram,
        on: ud.diagram_id == d.id,
        where: ud.user_id == ^user_id,
        select: d.tags

    Repo.all(query)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort_by(&String.downcase/1)
  end

  @doc """
  Gets tag counts for all diagrams a user can access.

  Returns a map of tag => count for displaying tag clouds.
  """
  def get_tag_counts(user_id) do
    query =
      from d in Diagram,
        join: ud in UserDiagram,
        on: ud.diagram_id == d.id,
        where: ud.user_id == ^user_id,
        select: d.tags

    Repo.all(query)
    |> List.flatten()
    |> Enum.frequencies()
  end

  @doc """
  Gets tag counts from public diagrams.

  Returns a map of tag => count for public diagrams.
  """
  def get_public_tag_counts do
    query =
      from d in Diagram,
        where: d.visibility == :public,
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
  Gets a saved filter by ID. Returns nil if not found.
  """
  def get_saved_filter(id), do: Repo.get(SavedFilter, id)

  @doc """
  Gets a saved filter by ID. Raises if not found.
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
  def list_diagrams_by_tags(user_id, tags, ownership \\ :all)

  def list_diagrams_by_tags(user_id, [], ownership) do
    # Empty tags means show all
    case ownership do
      :owned -> list_owned_diagrams(user_id)
      :bookmarked -> list_bookmarked_diagrams(user_id)
      :all -> list_owned_diagrams(user_id) ++ list_bookmarked_diagrams(user_id)
    end
  end

  def list_diagrams_by_tags(user_id, tags, ownership) when is_list(tags) do
    # Build base query with ownership filter
    base_query =
      from d in Diagram,
        join: ud in UserDiagram,
        on: ud.diagram_id == d.id,
        where: ud.user_id == ^user_id

    # Add ownership filter
    query =
      case ownership do
        :owned -> from [d, ud] in base_query, where: ud.is_owner == true
        :bookmarked -> from [d, ud] in base_query, where: ud.is_owner == false
        :all -> base_query
      end

    # Add tag filter (OR logic - diagram must have at least one of the tags)
    query =
      if tags == [] do
        query
      else
        from [d, ud] in query,
          where: fragment("? && ?", d.tags, ^tags)
      end

    # Execute with ordering
    query
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists diagrams matching a saved filter.

  Includes:
  - User's owned diagrams matching the filter tags
  - User's bookmarked diagrams matching the filter tags
  - Public diagrams matching the filter tags (even if not bookmarked)

  Results are deduplicated and sorted by insertion date (newest first).
  """
  def list_diagrams_by_saved_filter(user_id, %SavedFilter{} = filter) do
    # Get user's owned/bookmarked diagrams
    user_diagrams = list_diagrams_by_tags(user_id, filter.tag_filter, :all)

    # Get public diagrams matching the filter
    public_diagrams = list_public_diagrams(filter.tag_filter)

    # Combine and deduplicate (user might own a public diagram)
    user_diagram_ids = MapSet.new(user_diagrams, & &1.id)

    additional_public =
      Enum.reject(public_diagrams, fn d -> MapSet.member?(user_diagram_ids, d.id) end)

    # Combine and sort by inserted_at desc
    (user_diagrams ++ additional_public)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @doc """
  Gets counts for a saved filter (how many diagrams match).
  """
  def get_saved_filter_count(user_id, %SavedFilter{} = filter) do
    diagrams = list_diagrams_by_saved_filter(user_id, filter)
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
  - New user_diagrams entry with is_owner: true
  """
  def fork_diagram(original_id, user_id) do
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
        visibility: :unlisted,
        forked_from_id: original.id
      }

      case create_diagram_for_user(new_diagram_attrs, user_id) do
        {:ok, diagram} -> diagram
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Bookmarks/saves a diagram for a user.

  Creates user_diagrams entry with is_owner: false.
  User can add their own tags to bookmarked diagrams.
  """
  def bookmark_diagram(diagram_id, user_id) do
    user_diagram_changeset =
      UserDiagram.changeset(%UserDiagram{}, %{
        user_id: user_id,
        diagram_id: diagram_id,
        is_owner: false
      })

    Repo.insert(user_diagram_changeset)
  end

  @doc """
  Removes a diagram bookmark (removes user_diagrams entry with is_owner: false).
  """
  def remove_diagram_bookmark(diagram_id, user_id) do
    Repo.delete_all(
      from ud in UserDiagram,
        where:
          ud.diagram_id == ^diagram_id and
            ud.user_id == ^user_id and
            ud.is_owner == false
    )

    :ok
  end

  @doc """
  Assigns a diagram to a user with ownership.
  Primarily used for test fixtures where diagrams are created without users.
  """
  def assign_diagram_to_user(diagram_id, user_id, is_owner \\ true) do
    user_diagram_changeset =
      UserDiagram.changeset(%UserDiagram{}, %{
        user_id: user_id,
        diagram_id: diagram_id,
        is_owner: is_owner
      })

    Repo.insert(user_diagram_changeset)
  end

  # User Preferences

  @doc """
  Updates user's show_public_diagrams preference.
  """
  def update_user_public_diagrams_preference(user, show_public) do
    user
    |> User.preferences_changeset(%{show_public_diagrams: show_public})
    |> Repo.update()
  end

  # ============================================================================
  # Admin Functions
  # ============================================================================

  @doc """
  Admin-only function to bulk update diagram visibility.
  Bypasses user authorization checks.

  ## Examples

      iex> admin_bulk_update_visibility(diagrams, :public)
      {:ok, 5}

      iex> admin_bulk_update_visibility([], :public)
      {:ok, 0}
  """
  def admin_bulk_update_visibility([], _visibility), do: {:ok, 0}

  def admin_bulk_update_visibility(diagrams, visibility)
      when visibility in [:public, :unlisted, :private] do
    ids = Enum.map(diagrams, & &1.id)

    {count, _} =
      from(d in Diagram, where: d.id in ^ids)
      |> Repo.update_all(
        set: [
          visibility: visibility,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

    {:ok, count}
  end

  # ============================================================================
  # AI Options Validation
  # ============================================================================

  # Validates and builds AI options, raising on invalid configuration.
  # This ensures fail-fast behavior when required options are missing.
  defp build_ai_opts!(opts, default_operation) do
    alias DiagramForge.AI.Options

    validated_opts =
      opts
      |> Keyword.put_new(:operation, default_operation)
      |> Options.new!()

    Options.to_keyword_list(validated_opts)
  end
end

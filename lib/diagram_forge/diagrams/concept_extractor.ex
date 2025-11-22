defmodule DiagramForge.Diagrams.ConceptExtractor do
  @moduledoc """
  Extracts concepts from documents using LLM-powered analysis.
  """

  require Logger

  import Ecto.Query

  alias DiagramForge.AI.Client
  alias DiagramForge.AI.Prompts
  alias DiagramForge.Diagrams.{Concept, Document, DocumentIngestor}
  alias DiagramForge.Repo

  @doc """
  Extracts concepts from a document's raw text and stores them in the database.

  The document's `raw_text` is chunked and each chunk is analyzed by the LLM.
  Concepts are deduplicated by lowercased name across all chunks.

  Returns a list of inserted/updated concept records.

  ## Options

    * `:ai_client` - AI client module to use (defaults to DiagramForge.AI.Client)
  """
  def extract_for_document(%Document{} = doc, opts \\ []) do
    ai_client = opts[:ai_client] || Client
    text = doc.raw_text
    chunks = DocumentIngestor.chunk_text(text)

    Logger.info(
      "Processing document chunks: document_id=#{doc.id}, total_chunks=#{length(chunks)}"
    )

    # Track seen concept names (case-insensitive) to avoid duplicates
    {concepts, _seen} =
      chunks
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new()}, fn {chunk, idx}, {acc_concepts, seen_names} ->
        Logger.info("Processing chunk #{idx + 1}/#{length(chunks)} for document_id=#{doc.id}")
        concepts = extract_concepts_from_chunk(chunk, ai_client)
        Logger.info("Extracted #{length(concepts)} concepts from chunk #{idx + 1}")

        # Filter out concepts with empty names and already-seen names (case-insensitive)
        {new_concepts, updated_seen} =
          insert_unique_concepts(doc, concepts, seen_names)

        Logger.info(
          "Saved #{length(new_concepts)} new concepts from chunk #{idx + 1} for document_id=#{doc.id}"
        )

        # Broadcast to LiveView for real-time UI updates if we added new concepts
        if length(new_concepts) > 0 do
          Phoenix.PubSub.broadcast(
            DiagramForge.PubSub,
            "documents",
            {:concepts_updated, doc.id}
          )
        end

        {new_concepts ++ acc_concepts, updated_seen}
      end)

    Logger.info(
      "Processing complete. Total concepts: #{length(concepts)} for document_id=#{doc.id}"
    )

    concepts
  end

  defp extract_concepts_from_chunk(chunk, ai_client) do
    user = Prompts.concept_user_prompt(chunk)

    json =
      ai_client.chat!(
        [
          %{"role" => "system", "content" => Prompts.concept_system_prompt()},
          %{"role" => "user", "content" => user}
        ],
        []
      )
      |> Jason.decode!()

    json["concepts"] || []
  end

  defp insert_unique_concepts(doc, concepts, seen_names) do
    concepts
    |> Enum.reject(fn c -> String.trim(c["name"] || "") == "" end)
    |> Enum.reduce({[], seen_names}, fn concept, {new_acc, seen_acc} ->
      name_lower = String.downcase(concept["name"])

      if MapSet.member?(seen_acc, name_lower) do
        # Already seen this concept, skip it
        {new_acc, seen_acc}
      else
        # New concept, insert it
        inserted = insert_or_update_concept(doc, concept)
        {[inserted | new_acc], MapSet.put(seen_acc, name_lower)}
      end
    end)
  end

  defp insert_or_update_concept(doc, attrs) do
    # Look up concept globally by name (case-insensitive)
    name = attrs["name"]

    existing =
      Repo.one(
        from c in Concept,
          where: fragment("LOWER(?)", c.name) == ^String.downcase(name),
          limit: 1
      )

    if existing do
      # Concept already exists globally, reuse it as-is
      existing
    else
      # Create new concept with this document as its origin
      %Concept{}
      |> Concept.changeset(%{
        document_id: doc.id,
        name: name,
        short_description: attrs["short_description"],
        category: attrs["category"]
      })
      |> Repo.insert!()
    end
  end
end

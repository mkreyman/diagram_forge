defmodule DiagramForge.Diagrams.Workers.ProcessDocumentJob do
  @moduledoc """
  Oban worker that processes newly uploaded documents.

  This job:
  1. Extracts text from the document (PDF, Markdown, or Text)
  2. Chunks the text for LLM processing
  3. Generates diagrams from each chunk
  4. Updates the document status accordingly
  """

  use Oban.Worker, queue: :documents, max_attempts: 3

  require Logger

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.{DiagramGenerator, Document, DocumentIngestor}
  alias DiagramForge.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    doc_id = args["document_id"]
    ai_opts = if args["ai_client"], do: [ai_client: args["ai_client"]], else: []

    doc = Repo.get!(Document, doc_id)

    Logger.info("Starting document processing: document_id=#{doc.id}, title=#{doc.title}")

    doc
    |> Document.changeset(%{status: :processing})
    |> Repo.update!()

    case DocumentIngestor.extract_text(doc) do
      {:ok, text} ->
        Logger.info(
          "Text extracted successfully: document_id=#{doc.id}, text_length=#{String.length(text)}"
        )

        # Update raw_text
        doc =
          doc
          |> Document.changeset(%{raw_text: text})
          |> Repo.update!()

        # Chunk text and generate diagrams
        chunks = DocumentIngestor.chunk_text(text)
        Logger.info("Text chunked: document_id=#{doc.id}, chunks_count=#{length(chunks)}")

        diagrams_created = generate_diagrams_from_chunks(doc, chunks, ai_opts)

        Logger.info(
          "Diagram generation complete: document_id=#{doc.id}, diagrams_created=#{diagrams_created}"
        )

        # Update status to ready
        doc
        |> Document.changeset(%{
          status: :ready,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

        Logger.info("Document processing complete: document_id=#{doc.id}")

        :ok

      {:error, reason} ->
        doc
        |> Document.changeset(%{
          status: :error,
          error_message: reason,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

        {:error, reason}
    end
  rescue
    e ->
      # Extract doc_id from args since it's not in scope here
      doc_id = args["document_id"]
      doc = Repo.get(Document, doc_id)

      if doc do
        doc
        |> Document.changeset(%{
          status: :error,
          error_message: Exception.message(e),
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
      end

      {:error, Exception.message(e)}
  end

  defp generate_diagrams_from_chunks(doc, chunks, ai_opts) do
    total = length(chunks)

    # Add user_id for usage tracking
    ai_opts = Keyword.put(ai_opts, :user_id, doc.user_id)

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce(0, fn {chunk, index}, count ->
      Logger.info("Generating diagram #{index}/#{total} for document_id=#{doc.id}")

      # Broadcast progress for real-time UI updates
      broadcast_progress(doc.id, index, total)

      case generate_and_save_diagram(doc, chunk, index, ai_opts) do
        :ok -> count + 1
        :error -> count
      end
    end)
  end

  defp broadcast_progress(document_id, current, total) do
    Phoenix.PubSub.broadcast(
      DiagramForge.PubSub,
      "documents",
      {:document_progress, document_id, current, total}
    )
  end

  defp generate_and_save_diagram(doc, chunk, index, ai_opts) do
    case DiagramGenerator.generate_from_prompt(chunk, ai_opts) do
      {:ok, diagram} ->
        save_diagram(doc, diagram, index)

      {:error, reason} ->
        Logger.error(
          "Failed to generate diagram: document_id=#{doc.id}, chunk=#{index}, reason=#{inspect(reason)}"
        )

        :error
    end
  end

  defp save_diagram(doc, diagram, index) do
    attrs = %{
      title: diagram.title,
      slug: diagram.slug,
      tags: diagram.tags,
      format: diagram.format,
      diagram_source: diagram.diagram_source,
      summary: diagram.summary,
      notes_md: diagram.notes_md,
      document_id: doc.id
    }

    case Diagrams.create_diagram_for_user(attrs, doc.user_id) do
      {:ok, _saved_diagram} ->
        Logger.info("Diagram saved: document_id=#{doc.id}, chunk=#{index}")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to save diagram: document_id=#{doc.id}, chunk=#{index}, reason=#{inspect(reason)}"
        )

        :error
    end
  end
end

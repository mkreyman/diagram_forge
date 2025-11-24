defmodule DiagramForge.Diagrams.Workers.ProcessDocumentJob do
  @moduledoc """
  Oban worker that processes newly uploaded documents.

  This job:
  1. Extracts text from the document (PDF or Markdown)
  2. Updates the document status accordingly
  """

  use Oban.Worker, queue: :documents, max_attempts: 3

  require Logger

  alias DiagramForge.Diagrams.{Document, DocumentIngestor}
  alias DiagramForge.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    doc_id = args["document_id"]

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

        # Update raw_text and set status to ready
        doc
        |> Document.changeset(%{
          raw_text: text,
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
end

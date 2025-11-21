defmodule DiagramForge.Diagrams.Workers.GenerateDiagramJob do
  @moduledoc """
  Oban worker that generates diagrams for concepts.
  """

  use Oban.Worker, queue: :diagrams

  alias DiagramForge.Diagrams.{Concept, DiagramGenerator}
  alias DiagramForge.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    concept_id = args["concept_id"]
    document_id = args["document_id"]

    opts =
      if args["ai_client"], do: [ai_client: String.to_existing_atom(args["ai_client"])], else: []

    concept = Repo.get!(Concept, concept_id)

    # Broadcast generation start
    Phoenix.PubSub.broadcast(
      DiagramForge.PubSub,
      "diagram_generation:#{document_id}",
      {:generation_started, concept_id}
    )

    result =
      case DiagramGenerator.generate_for_concept(concept, opts) do
        {:ok, diagram} ->
          # Broadcast generation complete
          Phoenix.PubSub.broadcast(
            DiagramForge.PubSub,
            "diagram_generation:#{document_id}",
            {:generation_completed, concept_id, diagram.id}
          )

          :ok

        {:error, reason} ->
          # Broadcast generation failed
          Phoenix.PubSub.broadcast(
            DiagramForge.PubSub,
            "diagram_generation:#{document_id}",
            {:generation_failed, concept_id, reason}
          )

          {:error, reason}
      end

    result
  end
end

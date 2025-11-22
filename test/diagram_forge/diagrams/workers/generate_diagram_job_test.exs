defmodule DiagramForge.Diagrams.Workers.GenerateDiagramJobTest do
  use DiagramForge.DataCase, async: true
  use Oban.Testing, repo: DiagramForge.Repo

  import Mox

  alias DiagramForge.Diagrams.Diagram
  alias DiagramForge.Diagrams.Workers.GenerateDiagramJob
  alias DiagramForge.MockAIClient
  alias DiagramForge.Repo

  setup :verify_on_exit!

  describe "perform/1" do
    test "successfully generates diagram for concept" do
      document = fixture(:document, raw_text: "Content about GenServer")
      concept = fixture(:concept, document: document, name: "GenServer")

      ai_response = %{
        "title" => "GenServer Flow",
        "domain" => "elixir",
        "level" => "intermediate",
        "tags" => ["otp"],
        "mermaid" => "flowchart TD\n  A --> B",
        "summary" => "GenServer message flow",
        "notes_md" => "Notes"
      }

      stub(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      # Perform the job
      assert :ok =
               perform_job(GenerateDiagramJob, %{
                 "concept_id" => concept.id,
                 "ai_client" => "Elixir.DiagramForge.MockAIClient"
               })

      # Verify diagram was created
      diagrams = Repo.all(from d in Diagram, where: d.concept_id == ^concept.id)
      assert length(diagrams) == 1

      diagram = hd(diagrams)
      assert diagram.concept_id == concept.id
      assert diagram.document_id == document.id
      assert diagram.title == "GenServer Flow"
    end

    test "returns error when concept not found" do
      # Non-existent concept ID (using a random UUID)
      non_existent_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        perform_job(GenerateDiagramJob, %{"concept_id" => non_existent_id})
      end
    end

    test "associates generated diagram with concept and document" do
      document = fixture(:document, raw_text: "Technical content")
      concept = fixture(:concept, document: document, name: "Architecture")

      ai_response = %{
        "title" => "System Architecture",
        "domain" => "system-design",
        "level" => "advanced",
        "tags" => ["architecture"],
        "mermaid" => "graph LR\n  A --> B",
        "summary" => "Architecture overview",
        "notes_md" => "Notes"
      }

      stub(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      assert :ok =
               perform_job(GenerateDiagramJob, %{
                 "concept_id" => concept.id,
                 "ai_client" => "Elixir.DiagramForge.MockAIClient"
               })

      # Verify associations
      diagram = Repo.one!(from d in Diagram, where: d.concept_id == ^concept.id)
      loaded_diagram = Repo.preload(diagram, [:concept, :document])

      assert loaded_diagram.concept.id == concept.id
      assert loaded_diagram.document.id == document.id
    end
  end
end

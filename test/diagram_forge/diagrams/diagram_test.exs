defmodule DiagramForge.Diagrams.DiagramTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams.Diagram
  alias DiagramForge.Repo

  describe "Diagram schema" do
    test "has correct default values" do
      diagram = %Diagram{}
      assert diagram.format == :mermaid
      assert diagram.tags == []
    end

    test "validates required fields" do
      changeset = Diagram.changeset(%Diagram{}, %{})

      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).diagram_source
    end

    test "allows valid format values" do
      for format <- [:mermaid, :plantuml] do
        changeset = build(:diagram, format: format)
        assert {:ok, _} = Repo.insert(changeset)
      end
    end

    test "has many-to-many association with users" do
      alias DiagramForge.Diagrams

      user = fixture(:user)
      diagram = fixture(:diagram)
      Diagrams.assign_diagram_to_user(diagram.id, user.id)

      loaded = Repo.preload(diagram, :users)
      assert length(loaded.users) == 1
      assert hd(loaded.users).id == user.id
    end

    test "optionally belongs to a document" do
      document = fixture(:document)
      diagram = fixture(:diagram, document: document)

      loaded = Repo.preload(diagram, :document)
      assert loaded.document.id == document.id
    end

    test "creates diagram with all fields" do
      alias DiagramForge.Diagrams

      user = fixture(:user)

      diagram =
        fixture(:diagram,
          title: "GenServer Flow",
          tags: ["otp", "concurrency", "elixir"],
          format: :mermaid,
          diagram_source: "flowchart TD\n  A --> B",
          summary: "Shows GenServer message flow",
          notes_md: "- Call\n- Cast\n- Info"
        )

      Diagrams.assign_diagram_to_user(diagram.id, user.id)

      assert diagram.title == "GenServer Flow"
      assert diagram.tags == ["otp", "concurrency", "elixir"]
      assert diagram.format == :mermaid
      assert diagram.diagram_source == "flowchart TD\n  A --> B"
      assert diagram.summary == "Shows GenServer message flow"
      assert diagram.notes_md == "- Call\n- Cast\n- Info"

      # Verify user association through user_diagrams
      loaded = Repo.preload(diagram, :users)
      assert length(loaded.users) == 1
      assert hd(loaded.users).id == user.id
    end
  end
end

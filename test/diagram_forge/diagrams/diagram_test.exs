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
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "enforces unique slug" do
      _diagram1 = fixture(:diagram, slug: "unique-slug")

      changeset = build(:diagram, slug: "unique-slug")
      {:error, changeset} = Repo.insert(changeset)

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "allows valid format values" do
      for format <- [:mermaid, :plantuml] do
        changeset = build(:diagram, format: format)
        assert {:ok, _} = Repo.insert(changeset)
      end
    end

    test "optionally belongs to a user" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user)

      loaded = Repo.preload(diagram, :user)
      assert loaded.user.id == user.id
    end

    test "optionally belongs to a document" do
      document = fixture(:document)
      diagram = fixture(:diagram, document: document)

      loaded = Repo.preload(diagram, :document)
      assert loaded.document.id == document.id
    end

    test "creates diagram with all fields" do
      user = fixture(:user)

      changeset =
        build(:diagram,
          user: user,
          title: "GenServer Flow",
          slug: "genserver-flow",
          tags: ["otp", "concurrency", "elixir"],
          format: :mermaid,
          diagram_source: "flowchart TD\n  A --> B",
          summary: "Shows GenServer message flow",
          notes_md: "- Call\n- Cast\n- Info"
        )

      assert {:ok, diagram} = Repo.insert(changeset)
      assert diagram.user_id == user.id
      assert diagram.title == "GenServer Flow"
      assert diagram.slug == "genserver-flow"
      assert diagram.tags == ["otp", "concurrency", "elixir"]
      assert diagram.format == :mermaid
      assert diagram.diagram_source == "flowchart TD\n  A --> B"
      assert diagram.summary == "Shows GenServer message flow"
      assert diagram.notes_md == "- Call\n- Cast\n- Info"
    end
  end
end

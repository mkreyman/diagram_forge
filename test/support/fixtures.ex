defmodule DiagramForge.Fixtures do
  @moduledoc """
  This module defines test helpers for creating entities for testing.
  It consolidates all fixtures into a single module with a consistent interface.
  """

  alias DiagramForge.Accounts.User
  alias DiagramForge.Diagrams.{Concept, Diagram, Document}
  alias DiagramForge.Repo

  @doc """
  Creates a record in the database based on the given schema and attributes.

  This is the main fixture function that builds a struct and inserts it.
  """
  def fixture(schema, attrs \\ %{}) do
    schema
    |> build(attrs)
    |> Repo.insert!()
  end

  @doc """
  Builds a struct without inserting it into the database.
  """
  def build(:document, attrs) do
    %Document{}
    |> Document.changeset(
      attrs
      |> Enum.into(%{
        title: "Test Document #{System.unique_integer([:positive])}",
        source_type: :markdown,
        path: "/tmp/test-#{System.unique_integer([:positive])}.md",
        status: :uploaded
      })
    )
  end

  def build(:concept, attrs) do
    document = attrs[:document] || fixture(:document)

    %Concept{}
    |> Concept.changeset(
      attrs
      |> Enum.into(%{
        document_id: document.id,
        name: "Test Concept #{System.unique_integer([:positive])}",
        short_description: "A test concept for testing purposes",
        category: "elixir"
      })
    )
  end

  def build(:diagram, attrs) do
    concept = attrs[:concept]
    document = attrs[:document]

    base_attrs = %{
      slug: "test-diagram-#{System.unique_integer([:positive])}",
      title: "Test Diagram #{System.unique_integer([:positive])}",
      domain: "elixir",
      tags: ["test"],
      format: :mermaid,
      diagram_source: "flowchart TD\n  A[Start] --> B[End]",
      summary: "A test diagram"
    }

    base_attrs =
      if concept do
        Map.merge(base_attrs, %{concept_id: concept.id, document_id: concept.document_id})
      else
        if document do
          Map.put(base_attrs, :document_id, document.id)
        else
          base_attrs
        end
      end

    %Diagram{}
    |> Diagram.changeset(
      attrs
      |> Enum.into(base_attrs)
    )
  end

  def build(:user, attrs) do
    unique_id = System.unique_integer([:positive])

    %User{}
    |> User.changeset(
      attrs
      |> Enum.into(%{
        email: "user#{unique_id}@example.com",
        name: "Test User #{unique_id}",
        provider: "github",
        provider_uid: "github_uid_#{unique_id}",
        provider_token: "test_token_#{unique_id}"
      })
    )
  end
end

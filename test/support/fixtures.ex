defmodule DiagramForge.Fixtures do
  @moduledoc """
  This module defines test helpers for creating entities for testing.
  It consolidates all fixtures into a single module with a consistent interface.
  """

  alias DiagramForge.Accounts.User
  alias DiagramForge.Diagrams.{Diagram, Document, SavedFilter}
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

  def build(:diagram, attrs) do
    user = attrs[:user]
    document = attrs[:document]

    base_attrs = %{
      slug: "test-diagram-#{System.unique_integer([:positive])}",
      title: "Test Diagram #{System.unique_integer([:positive])}",
      tags: ["test"],
      format: :mermaid,
      diagram_source: "flowchart TD\n  A[Start] --> B[End]",
      summary: "A test diagram"
    }

    base_attrs =
      cond do
        user -> Map.put(base_attrs, :user_id, user.id)
        document -> Map.put(base_attrs, :document_id, document.id)
        true -> base_attrs
      end

    %Diagram{}
    |> Diagram.changeset(
      attrs
      |> Enum.into(base_attrs)
    )
  end

  def build(:saved_filter, attrs) do
    user = attrs[:user] || fixture(:user)

    %SavedFilter{}
    |> SavedFilter.changeset(
      attrs
      |> Enum.into(%{
        user_id: user.id,
        name: "Test Filter #{System.unique_integer([:positive])}",
        tag_filter: ["elixir", "test"],
        is_pinned: true,
        sort_order: 0
      })
    )
  end

  def build(:diagram_with_tags, attrs) do
    default_tags = ["elixir", "phoenix", "test"]
    attrs = Map.put_new(attrs, :tags, default_tags)
    build(:diagram, attrs)
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

defmodule Mix.Tasks.Export.Diagrams do
  @moduledoc """
  Export diagrams to a JSON file.

  ## Usage

      mix export.diagrams --user admin@example.com --output /path/to/diagrams.json

  ## Options

    * `--user` - Email of the user whose diagrams to export (required)
    * `--output` - Path to the output JSON file (required)

  """
  use Mix.Task

  @shortdoc "Export diagrams to a JSON file"

  @switches [user: :string, output: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    user_email = opts[:user]
    output_path = opts[:output]

    if is_nil(user_email) or is_nil(output_path) do
      print_usage()
      System.halt(0)
    end

    Mix.Task.run("app.start")

    alias DiagramForge.Accounts.User
    alias DiagramForge.Diagrams.Diagram
    alias DiagramForge.Repo
    import Ecto.Query

    user = Repo.get_by(User, email: user_email)

    unless user do
      Mix.raise("User not found: #{user_email}")
    end

    diagrams =
      Diagram
      |> join(:inner, [d], ud in "user_diagrams", on: ud.diagram_id == d.id)
      |> where([d, ud], ud.user_id == ^user.id and ud.is_owner == true)
      |> preload(:document)
      |> Repo.all()

    export_data = %{
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      user_email: user_email,
      diagram_count: length(diagrams),
      diagrams: Enum.map(diagrams, &serialize_diagram/1)
    }

    json = Jason.encode!(export_data, pretty: true)

    # Expand path (handle ~) and resolve relative paths
    full_path = Path.expand(output_path)

    # Ensure directory exists
    full_path |> Path.dirname() |> File.mkdir_p!()

    File.write!(full_path, json)

    Mix.shell().info("Exported #{length(diagrams)} diagrams to #{full_path}")
  end

  defp serialize_diagram(diagram) do
    %{
      title: diagram.title,
      description: diagram.description,
      source: diagram.source,
      tags: diagram.tags || [],
      visibility: diagram.visibility,
      inserted_at: diagram.inserted_at |> DateTime.to_iso8601(),
      updated_at: diagram.updated_at |> DateTime.to_iso8601(),
      document: serialize_document(diagram.document)
    }
  end

  defp serialize_document(nil), do: nil

  defp serialize_document(document) do
    %{
      content: document.content,
      status: document.status,
      inserted_at: document.inserted_at |> DateTime.to_iso8601(),
      updated_at: document.updated_at |> DateTime.to_iso8601()
    }
  end

  defp print_usage do
    Mix.shell().info("""
    Export diagrams to a JSON file.

    Usage:
      mix export.diagrams --user EMAIL --output PATH

    Options:
      --user    Email of the user whose diagrams to export (required)
      --output  Path to the output JSON file (required)

    Examples:
      mix export.diagrams --user admin@example.com --output ~/backups/diagrams.json
      mix export.diagrams --user admin@example.com --output ./diagrams.json
    """)
  end
end

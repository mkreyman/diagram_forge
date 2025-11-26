defmodule Mix.Tasks.Import.Diagrams do
  @moduledoc """
  Import diagrams from a JSON file.

  ## Usage

      mix import.diagrams --user admin@example.com --input /path/to/diagrams.json

  ## Options

    * `--user` - Email of the user to assign diagrams to (required)
    * `--input` - Path to the input JSON file (required)

  Diagrams with existing titles will be skipped to avoid duplicates.
  """
  use Mix.Task

  @shortdoc "Import diagrams from a JSON file"

  @switches [user: :string, input: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    user_email = opts[:user]
    input_path = opts[:input]

    if is_nil(user_email) or is_nil(input_path) do
      print_usage()
      System.halt(0)
    end

    Mix.Task.run("app.start")

    user = DiagramForge.Repo.get_by(DiagramForge.Accounts.User, email: user_email)

    unless user do
      Mix.raise("User not found: #{user_email}")
    end

    # Expand path (handle ~) and resolve relative paths
    full_path = Path.expand(input_path)

    unless File.exists?(full_path) do
      Mix.raise("File not found: #{full_path}")
    end

    json = File.read!(full_path)
    export_data = Jason.decode!(json)

    diagrams_data = export_data["diagrams"] || []

    Mix.shell().info("Found #{length(diagrams_data)} diagrams to import...")

    results =
      Enum.map(diagrams_data, fn diagram_data ->
        import_diagram(user, diagram_data)
      end)

    imported = Enum.count(results, &match?({:ok, _}, &1))
    skipped = Enum.count(results, &match?({:skipped, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Mix.shell().info("")
    Mix.shell().info("Import complete:")
    Mix.shell().info("  - Imported: #{imported}")
    Mix.shell().info("  - Skipped (already exists): #{skipped}")

    if failed > 0 do
      Mix.shell().error("  - Failed: #{failed}")
    end
  end

  defp import_diagram(user, diagram_data) do
    alias DiagramForge.Diagrams
    alias DiagramForge.Repo

    title = diagram_data["title"]

    # Check if diagram with this title already exists for this user
    if Repo.get_by(Diagrams.Diagram, title: title) do
      Mix.shell().info("  Skipping '#{title}' (title exists)")
      {:skipped, title}
    else
      Repo.transaction(fn ->
        document = maybe_create_document(user, diagram_data["document"])

        diagram_attrs = %{
          title: title,
          description: diagram_data["description"],
          source: diagram_data["source"],
          tags: diagram_data["tags"] || [],
          visibility: diagram_data["visibility"] || "private",
          document_id: document && document.id
        }

        {:ok, diagram} = Diagrams.create_diagram_for_user(diagram_attrs, user.id)

        Mix.shell().info("  Imported '#{diagram.title}'")
        diagram
      end)
    end
  end

  defp maybe_create_document(_user, nil), do: nil

  defp maybe_create_document(user, doc_data) do
    alias DiagramForge.Diagrams.Document
    alias DiagramForge.Repo

    struct!(Document)
    |> Document.changeset(%{
      user_id: user.id,
      content: doc_data["content"],
      status: doc_data["status"] || "completed"
    })
    |> Repo.insert!()
  end

  defp print_usage do
    Mix.shell().info("""
    Import diagrams from a JSON file.

    Usage:
      mix import.diagrams --user EMAIL --input PATH

    Options:
      --user   Email of the user to assign diagrams to (required)
      --input  Path to the input JSON file (required)

    Examples:
      mix import.diagrams --user admin@example.com --input ~/backups/diagrams.json
      mix import.diagrams --user admin@example.com --input ./diagrams.json

    Note: Diagrams with existing titles will be skipped to avoid duplicates.
    """)
  end
end

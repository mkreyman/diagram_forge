defmodule DiagramForge.Diagrams.DiagramGenerator do
  @moduledoc """
  Generates Mermaid diagrams from free-form prompts using LLM.
  """

  alias DiagramForge.AI.Client
  alias DiagramForge.AI.Options
  alias DiagramForge.AI.Prompts
  alias DiagramForge.Diagrams.Diagram

  @doc """
  Generates a diagram from a free-form text prompt.

  Returns `{:ok, diagram}` on success or `{:error, reason}` on failure.

  ## Options

    * `:ai_client` - AI client module to use (defaults to configured client)
    * `:user_id` - User ID for usage tracking (required unless track_usage: false)
    * `:operation` - Operation type for usage tracking (defaults to "diagram_generation")
    * `:track_usage` - Whether to track token usage (default: true)

  ## Raises

  Raises `ArgumentError` if `:user_id` is missing when usage tracking is enabled.
  This fail-fast behavior prevents silent failures in usage tracking.
  """
  def generate_from_prompt(text, opts) do
    # Validate options early - fail fast if user_id missing with tracking enabled
    ai_opts = build_ai_opts!(opts, "diagram_generation")
    ai_client = opts[:ai_client] || ai_client()
    user_prompt = Prompts.diagram_from_prompt_user_prompt(text)

    json =
      ai_client.chat!(
        [
          %{"role" => "system", "content" => Prompts.diagram_system_prompt()},
          %{"role" => "user", "content" => user_prompt}
        ],
        ai_opts
      )
      |> Jason.decode!()

    attrs = %{
      title: json["title"],
      slug: slugify(json["title"]),
      tags: json["tags"] || [],
      format: :mermaid,
      diagram_source: json["mermaid"],
      summary: json["summary"],
      notes_md: json["notes_md"]
    }

    changeset = Diagram.changeset(%Diagram{}, attrs)

    if changeset.valid? do
      diagram = Ecto.Changeset.apply_changes(changeset)
      {:ok, diagram}
    else
      {:error, changeset}
    end
  end

  defp slugify(nil), do: "diagram-#{:os.system_time(:millisecond)}"

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp ai_client do
    Application.get_env(:diagram_forge, :ai_client, Client)
  end

  # Validates and builds AI options, raising on invalid configuration.
  # This ensures fail-fast behavior when required options are missing.
  defp build_ai_opts!(opts, default_operation) do
    validated_opts =
      opts
      |> Keyword.put_new(:operation, default_operation)
      |> Options.new!()

    Options.to_keyword_list(validated_opts)
  end
end

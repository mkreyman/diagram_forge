defmodule DiagramForge.Diagrams.MermaidSanitizer do
  @moduledoc """
  Programmatically sanitizes Mermaid diagram syntax.

  Fixes common issues like unquoted special characters in node
  and edge labels that cause parse errors in Mermaid 11.x.

  ## Common Issues Fixed

  - Empty edge labels: `-->|""|` → `-->`
  - Escaped quotes: `-->|"[\\"a\\"]"|` → `-->|"['a']"|`
  - Unquoted special chars in nodes: `A[File.open]` → `A["File.open"]`
  - Unquoted edge labels with curly braces: `-->|{:ok}|` → `-->|"{:ok}"|`
  - Nested quotes in edge labels: `-->|"{self, "World!"}"|` → `-->|"{self, World!}"|`
  - Trailing periods after nodes: `D["text"].` → `D["text"]`

  ## Usage

      iex> MermaidSanitizer.sanitize("flowchart TD\\n    A[File.open] --> B")
      {:ok, "flowchart TD\\n    A[\\"File.open\\"] --> B"}

      iex> MermaidSanitizer.sanitize("flowchart TD\\n    A[\\"Done\\"] --> B")
      {:unchanged, "flowchart TD\\n    A[\\"Done\\"] --> B"}
  """

  # Characters that require quoting in node labels
  @node_special_chars ~r/[.()!:&|]/

  # Characters that require quoting in edge labels
  @edge_special_chars ~r/[{}:&]/

  @doc """
  Sanitizes a Mermaid diagram source, fixing common syntax issues.

  Returns `{:ok, sanitized_source}` if changes were made,
  or `{:unchanged, source}` if no issues were found.

  ## Examples

      iex> DiagramForge.Diagrams.MermaidSanitizer.sanitize("flowchart TD\\n    A[File.open] --> B")
      {:ok, "flowchart TD\\n    A[\\"File.open\\"] --> B"}

      iex> DiagramForge.Diagrams.MermaidSanitizer.sanitize("flowchart TD\\n    A[Start] --> B[End]")
      {:unchanged, "flowchart TD\\n    A[Start] --> B[End]"}
  """
  @spec sanitize(String.t()) :: {:ok, String.t()} | {:unchanged, String.t()}
  def sanitize(source) when is_binary(source) do
    sanitized =
      source
      |> fix_empty_edge_labels()
      |> fix_escaped_quotes()
      |> fix_nested_quotes_in_edge_labels()
      |> fix_unquoted_node_labels()
      |> fix_unquoted_edge_labels()
      |> fix_trailing_periods()

    if sanitized == source do
      {:unchanged, source}
    else
      {:ok, sanitized}
    end
  end

  # Remove empty edge labels: -->|""| becomes -->
  defp fix_empty_edge_labels(source) do
    source
    |> String.replace(~r/-->\|""\|/, "-->")
    |> String.replace(~r/---\|""\|/, "---")
  end

  # Convert backslash-escaped quotes to single quotes: [\"a\"] becomes ['a']
  defp fix_escaped_quotes(source) do
    String.replace(source, ~r/\\"/, "'")
  end

  # Remove nested quotes inside edge labels: |"{self, "World!"}"| becomes |"{self, World!}"|
  # Pattern: find edge labels with quotes inside the outer quotes
  defp fix_nested_quotes_in_edge_labels(source) do
    # Match edge labels: |"...content..."| where content has inner quotes
    Regex.replace(
      ~r/\|"([^|]*)"([^|"]+)"([^|]*)"\|/,
      source,
      fn _full, before, inner, after_text ->
        ~s(|"#{before}#{inner}#{after_text}"|)
      end
    )
  end

  # Quote node labels with special characters
  # Handles square bracket nodes: A[content] -> A["content"]
  defp fix_unquoted_node_labels(source) do
    # Match unquoted node labels in square brackets
    # Pattern: NodeId[unquoted content] where content is NOT already quoted
    Regex.replace(
      ~r/([A-Za-z][A-Za-z0-9_]*)\[([^\]"]+)\]/,
      source,
      fn full_match, node_id, content ->
        if needs_node_quoting?(content) do
          ~s(#{node_id}["#{content}"])
        else
          full_match
        end
      end
    )
  end

  # Quote edge labels with special characters
  # Handles: -->|content| -> -->|"content"|
  defp fix_unquoted_edge_labels(source) do
    # Match unquoted edge labels
    # Pattern: -->|unquoted content| or ---|unquoted content|
    Regex.replace(
      ~r/(-->|---)\|([^|"]+)\|/,
      source,
      fn full_match, arrow, content ->
        if needs_edge_quoting?(content) do
          ~s(#{arrow}|"#{content}"|)
        else
          full_match
        end
      end
    )
  end

  # Remove trailing periods after node definitions
  # Pattern: ]["text"]. or ][text]. at end of line
  defp fix_trailing_periods(source) do
    # Match closing bracket followed by period at end of line or before whitespace
    String.replace(source, ~r/(\])\.\s*$/, "\\1", global: true)
    |> String.replace(~r/(\])\.(\s)/m, "\\1\\2")
  end

  defp needs_node_quoting?(content) do
    Regex.match?(@node_special_chars, content)
  end

  defp needs_edge_quoting?(content) do
    Regex.match?(@edge_special_chars, content)
  end
end

defmodule DiagramForge.Content.MermaidSanitizer do
  @moduledoc """
  Sanitizes Mermaid diagram source code to prevent script injection
  and other dangerous directives.

  Mermaid supports various directives that can enable external links
  or JavaScript execution. This module removes or neutralizes these
  potentially dangerous features while preserving valid diagram syntax.
  """

  # Directives that allow script execution or external links
  @dangerous_patterns [
    # Click handlers with href or call (can execute JavaScript)
    ~r/click\s+\w+\s+(?:href|call)\s*[^\n]*/i,
    # JSON config blocks that can enable scripts (handles nested braces)
    ~r/%%\{[^\n]*\}%%\n?/,
    # Direct href links in nodes
    ~r/href\s+"[^"]*"/i,
    # Callback definitions
    ~r/callback\s+\w+\s+"[^"]*"/i
  ]

  @doc """
  Sanitizes Mermaid source code by removing dangerous directives.

  ## Examples

      iex> MermaidSanitizer.sanitize("flowchart TD\\nA-->B\\nclick A href \\"https://evil.com\\"")
      "flowchart TD\\nA-->B\\n"
  """
  def sanitize(nil), do: nil

  def sanitize(source) when is_binary(source) do
    if enabled?() do
      Enum.reduce(@dangerous_patterns, source, fn pattern, acc ->
        Regex.replace(pattern, acc, "")
      end)
      |> String.trim()
    else
      source
    end
  end

  @doc """
  Checks if Mermaid sanitization is enabled.
  """
  def enabled? do
    Application.get_env(:diagram_forge, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Returns a list of the dangerous patterns being filtered.
  Useful for documentation and testing.
  """
  def dangerous_patterns, do: @dangerous_patterns
end

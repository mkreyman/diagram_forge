defmodule DiagramForge.Content.Sanitizer do
  @moduledoc """
  Sanitizes user-provided content to prevent injection attacks and remove spam.

  This module provides functions to:
  - Strip HTML tags from text content
  - Remove URLs to prevent spam and external links
  - Provide a complete sanitization pipeline for diagram content
  """

  @doc """
  Strips HTML tags from text, preserving only plain text content.

  ## Examples

      iex> Sanitizer.strip_html("<script>alert('xss')</script>Hello")
      "Hello"

      iex> Sanitizer.strip_html(nil)
      nil
  """
  def strip_html(nil), do: nil

  def strip_html(text) when is_binary(text) do
    text
    # Remove script and style tag contents (HtmlSanitizeEx only strips tags, not contents)
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> HtmlSanitizeEx.strip_tags()
    |> String.trim()
  end

  @doc """
  Removes URLs from text content.
  Returns `{sanitized_text, removed_urls}`.

  ## Examples

      iex> Sanitizer.strip_urls("Check out https://spam.com for deals!")
      {"Check out [link removed] for deals!", ["https://spam.com"]}

      iex> Sanitizer.strip_urls(nil)
      {nil, []}
  """
  def strip_urls(nil), do: {nil, []}

  def strip_urls(text) when is_binary(text) do
    url_pattern = ~r/https?:\/\/[^\s<>"]+/i
    urls = Regex.scan(url_pattern, text) |> List.flatten()
    sanitized = Regex.replace(url_pattern, text, "[link removed]")
    {sanitized, urls}
  end

  @doc """
  Full sanitization pipeline for diagram text content.
  Strips HTML and removes URLs.

  ## Examples

      iex> Sanitizer.sanitize_text("<b>Visit</b> https://spam.com")
      "Visit [link removed]"
  """
  def sanitize_text(nil), do: nil

  def sanitize_text(text) when is_binary(text) do
    text
    |> strip_html()
    |> strip_urls()
    |> elem(0)
  end

  @doc """
  Sanitizes diagram content based on field type.
  Returns the sanitized text or original if sanitization is disabled.
  """
  def sanitize_field(text, opts \\ []) do
    if enabled?() do
      if Keyword.get(opts, :strip_urls, config(:strip_urls, true)) do
        sanitize_text(text)
      else
        strip_html(text)
      end
    else
      text
    end
  end

  @doc """
  Checks if content sanitization is enabled.
  """
  def enabled? do
    config(:enabled, true)
  end

  defp config(key, default) do
    Application.get_env(:diagram_forge, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end

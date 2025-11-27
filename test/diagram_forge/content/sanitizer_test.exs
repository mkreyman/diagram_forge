defmodule DiagramForge.Content.SanitizerTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Content.Sanitizer

  describe "strip_html/1" do
    test "returns nil for nil input" do
      assert Sanitizer.strip_html(nil) == nil
    end

    test "strips basic HTML tags" do
      assert Sanitizer.strip_html("<p>Hello</p>") == "Hello"
      assert Sanitizer.strip_html("<div><span>Content</span></div>") == "Content"
    end

    test "strips script tags" do
      input = "<script>alert('xss')</script>Safe content"
      assert Sanitizer.strip_html(input) == "Safe content"
    end

    test "strips style tags" do
      input = "<style>body { color: red; }</style>Visible text"
      assert Sanitizer.strip_html(input) == "Visible text"
    end

    test "handles nested HTML" do
      input = "<div><p><strong>Bold <em>and italic</em></strong></p></div>"
      assert Sanitizer.strip_html(input) == "Bold and italic"
    end

    test "preserves plain text" do
      plain_text = "This is just plain text"
      assert Sanitizer.strip_html(plain_text) == plain_text
    end

    test "trims whitespace" do
      assert Sanitizer.strip_html("  <p>Content</p>  ") == "Content"
    end

    test "handles HTML entities" do
      assert Sanitizer.strip_html("&lt;script&gt;") =~ "script"
    end
  end

  describe "strip_urls/1" do
    test "returns nil tuple for nil input" do
      assert Sanitizer.strip_urls(nil) == {nil, []}
    end

    test "removes HTTP URLs" do
      input = "Check out http://example.com for more"
      {sanitized, urls} = Sanitizer.strip_urls(input)

      assert sanitized == "Check out [link removed] for more"
      assert urls == ["http://example.com"]
    end

    test "removes HTTPS URLs" do
      input = "Visit https://secure.example.com/path?query=1"
      {sanitized, urls} = Sanitizer.strip_urls(input)

      assert sanitized == "Visit [link removed]"
      assert urls == ["https://secure.example.com/path?query=1"]
    end

    test "removes multiple URLs" do
      input = "Link 1: http://first.com and link 2: https://second.com"
      {sanitized, urls} = Sanitizer.strip_urls(input)

      assert sanitized == "Link 1: [link removed] and link 2: [link removed]"
      assert length(urls) == 2
      assert "http://first.com" in urls
      assert "https://second.com" in urls
    end

    test "preserves text without URLs" do
      plain_text = "This text has no URLs at all"
      {sanitized, urls} = Sanitizer.strip_urls(plain_text)

      assert sanitized == plain_text
      assert urls == []
    end

    test "handles URLs with various characters" do
      input = "Complex URL: https://example.com/path/to/resource?param=value&other=123#anchor"
      {sanitized, urls} = Sanitizer.strip_urls(input)

      assert sanitized == "Complex URL: [link removed]"
      assert length(urls) == 1
    end
  end

  describe "sanitize_field/1" do
    test "returns nil for nil input" do
      assert Sanitizer.sanitize_field(nil) == nil
    end

    test "strips HTML and URLs by default" do
      input = "<p>Visit http://spam.com for deals!</p>"
      result = Sanitizer.sanitize_field(input)

      assert result == "Visit [link removed] for deals!"
    end

    test "handles text without HTML or URLs" do
      input = "Clean technical diagram"
      assert Sanitizer.sanitize_field(input) == input
    end

    test "strips HTML but preserves content" do
      input = "<b>Important</b> diagram about <i>architecture</i>"
      assert Sanitizer.sanitize_field(input) == "Important diagram about architecture"
    end
  end
end

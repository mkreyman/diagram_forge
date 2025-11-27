defmodule DiagramForge.Content.MermaidSanitizerTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Content.MermaidSanitizer

  describe "sanitize/1" do
    test "returns nil for nil input" do
      assert MermaidSanitizer.sanitize(nil) == nil
    end

    test "preserves valid flowchart syntax" do
      source = """
      flowchart TD
        A[Start] --> B[Process]
        B --> C[End]
      """

      # String.trim() is applied, so trailing newline is removed
      assert MermaidSanitizer.sanitize(source) == String.trim(source)
    end

    test "preserves valid sequence diagram syntax" do
      source = """
      sequenceDiagram
        participant A as Alice
        participant B as Bob
        A->>B: Hello Bob!
        B->>A: Hi Alice!
      """

      # String.trim() is applied, so trailing newline is removed
      assert MermaidSanitizer.sanitize(source) == String.trim(source)
    end

    test "removes click handlers with href" do
      source = """
      flowchart TD
        A[Start] --> B[End]
        click A href "http://malicious.com"
      """

      result = MermaidSanitizer.sanitize(source)

      refute result =~ "click"
      refute result =~ "href"
      refute result =~ "malicious"
      assert result =~ "flowchart TD"
      assert result =~ "A[Start]"
    end

    test "removes click handlers with call" do
      source = """
      flowchart TD
        A[Start] --> B[End]
        click B call callback()
      """

      result = MermaidSanitizer.sanitize(source)

      refute result =~ "click"
      refute result =~ "call"
      assert result =~ "flowchart TD"
    end

    test "removes JSON config blocks" do
      source = """
      %%{init: {"theme": "dark", "securityLevel": "loose"}}%%
      flowchart TD
        A --> B
      """

      result = MermaidSanitizer.sanitize(source)

      refute result =~ "init"
      refute result =~ "securityLevel"
      assert result =~ "flowchart TD"
    end

    test "handles multiple dangerous patterns" do
      source = """
      %%{init: {"securityLevel": "loose"}}%%
      flowchart TD
        A[Start] --> B[End]
        click A href "http://evil.com"
        click B call maliciousFunc()
      """

      result = MermaidSanitizer.sanitize(source)

      refute result =~ "init"
      refute result =~ "securityLevel"
      refute result =~ "click"
      refute result =~ "href"
      refute result =~ "call"
      assert result =~ "flowchart TD"
      assert result =~ "A[Start]"
    end

    test "preserves regular comments" do
      source = """
      flowchart TD
        %% This is a comment
        A[Start] --> B[End]
      """

      result = MermaidSanitizer.sanitize(source)

      assert result =~ "%% This is a comment"
      assert result =~ "flowchart TD"
    end

    test "preserves node labels with special characters" do
      source = """
      flowchart TD
        A["Database (PostgreSQL)"] --> B["API Server"]
        B --> C["Client App"]
      """

      # String.trim() is applied, so trailing newline is removed
      assert MermaidSanitizer.sanitize(source) == String.trim(source)
    end

    test "handles empty string" do
      assert MermaidSanitizer.sanitize("") == ""
    end
  end

  describe "enabled?/0" do
    test "returns boolean based on configuration" do
      result = MermaidSanitizer.enabled?()
      assert is_boolean(result)
    end
  end
end

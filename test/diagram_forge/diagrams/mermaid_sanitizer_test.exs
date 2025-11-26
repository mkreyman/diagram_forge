defmodule DiagramForge.Diagrams.MermaidSanitizerTest do
  use ExUnit.Case, async: true

  alias DiagramForge.Diagrams.MermaidSanitizer

  describe "sanitize/1 - Empty edge labels" do
    test "removes empty quoted edge labels" do
      input = "flowchart TD\n    B -->|\"\"| D[\"IO.puts\"]"
      expected = "flowchart TD\n    B --> D[\"IO.puts\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "removes empty edge labels with dashes" do
      input = "flowchart TD\n    B ---|\"\"| D[Done]"
      expected = "flowchart TD\n    B --- D[Done]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "preserves non-empty edge labels" do
      input = "flowchart TD\n    B -->|\"calls\"| D[\"IO.puts\"]"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Escaped quotes in labels" do
    test "converts backslash-escaped quotes to single quotes" do
      input = "flowchart TD\n    B -->|\"[\\\"a\\\"]\"| F[\"Result\"]"
      expected = "flowchart TD\n    B -->|\"['a']\"| F[\"Result\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "handles multiple escaped quotes" do
      input = "B -->|\"[[\\\"a\\\"], [\\\"e\\\"]]\"| F"
      expected = "B -->|\"[['a'], ['e']]\"| F"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Nested quotes in edge labels" do
    test "removes inner quotes from edge labels" do
      input = "B -->|\"{self, \"World!\"}\"| C[\"receive\"]"
      expected = "B -->|\"{self, World!}\"| C[\"receive\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "handles tuple-like syntax with nested quotes" do
      input = "C -->|\"{:ok, \"message\"}\"| D[\"puts\"]"
      expected = "C -->|\"{:ok, message}\"| D[\"puts\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Unquoted special characters in node labels" do
    test "quotes node labels with dots" do
      input = "flowchart TD\n    A[File.open] --> B[Done]"
      expected = "flowchart TD\n    A[\"File.open\"] --> B[Done]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes node labels with parentheses" do
      input = "flowchart TD\n    A[process(file)] --> B"
      expected = "flowchart TD\n    A[\"process(file)\"] --> B"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes node labels with exclamation marks" do
      input = "flowchart TD\n    A[File.open!] --> B"
      expected = "flowchart TD\n    A[\"File.open!\"] --> B"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes node labels with colons" do
      input = "flowchart TD\n    A[key: value] --> B"
      expected = "flowchart TD\n    A[\"key: value\"] --> B"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes node labels with ampersand" do
      input = "flowchart TD\n    B[&(&1 + 1)]"
      expected = "flowchart TD\n    B[\"&(&1 + 1)\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes node labels with pipe character" do
      input = "flowchart TD\n    A[a || b]"
      expected = "flowchart TD\n    A[\"a || b\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Unquoted special characters in edge labels" do
    test "quotes edge labels with curly braces" do
      input = "flowchart TD\n    D -->|{:fib, n, client}| E"
      expected = "flowchart TD\n    D -->|\"{:fib, n, client}\"| E"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes edge labels with colons" do
      input = "flowchart TD\n    A -->|key: value| B"
      expected = "flowchart TD\n    A -->|\"key: value\"| B"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "quotes edge labels with ampersand" do
      input = "flowchart TD\n    A -->|a & b| B"
      expected = "flowchart TD\n    A -->|\"a & b\"| B"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Trailing characters" do
    test "removes trailing period after node definition" do
      input = "flowchart TD\n    A --> D[\"inner function\"]."
      expected = "flowchart TD\n    A --> D[\"inner function\"]"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end

    test "removes trailing period in middle of diagram" do
      input = "flowchart TD\n    A --> D[\"text\"].\n    D --> E"
      expected = "flowchart TD\n    A --> D[\"text\"]\n    D --> E"

      assert {:ok, ^expected} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Already valid diagrams" do
    test "doesn't modify already quoted node labels" do
      input = "flowchart TD\n    A[\"File.open\"] --> B[\"process(file)\"]"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "doesn't modify simple labels without special chars" do
      input = "flowchart TD\n    A[Start] --> B[End]"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "doesn't modify properly quoted edge labels" do
      input = "flowchart TD\n    A -->|\"{:ok, pid}\"| B"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Complex real-world diagrams" do
    test "handles multiple issues in one diagram" do
      input = """
      flowchart TD
          A[File.open] -->|{:ok, file}| B[process(file)]
          A -->|{:error, msg}| C[IO.puts]
          B -->|""| D[Done]
      """

      {:ok, result} = MermaidSanitizer.sanitize(input)

      assert result =~ "A[\"File.open\"]"
      assert result =~ "|\"{:ok, file}\"|"
      assert result =~ "B[\"process(file)\"]"
      assert result =~ "|\"{:error, msg}\"|"
      assert result =~ "C[\"IO.puts\"]"
      assert result =~ "B --> D"
      refute result =~ "-->|\"\"|"
    end

    test "handles Elixir code in labels" do
      input = """
      flowchart TD
          A[Enum.map] -->|"[1, 3, 5, 7]"| B[&(&1 + 1)]
          B --> C[Stream]
      """

      {:ok, result} = MermaidSanitizer.sanitize(input)

      assert result =~ "A[\"Enum.map\"]"
      assert result =~ "B[\"&(&1 + 1)\"]"
    end

    test "fixes the real Tracer Module diagram" do
      # This is the actual failing diagram from production
      input = """
      flowchart TD
          A["Test"] -->|"calls"| B["puts_sum_three/3"]
          A -->|"calls"| C["add_list/1"]
          B -->|""| D["IO.puts"]
          C -->|""| E["Enum.reduce"]
          D -->|"logs trace"| F["Tracer.dump_defn"]
          E -->|"logs result"| F
      """

      {:ok, result} = MermaidSanitizer.sanitize(input)

      # Empty edge labels should be removed
      assert result =~ "B --> D"
      assert result =~ "C --> E"
      refute result =~ "-->|\"\"|"
    end
  end

  describe "sanitize/1 - Sequence diagrams" do
    test "preserves valid sequence diagrams" do
      input = """
      sequenceDiagram
          participant C as Client
          participant G as GenServer
          C->>+G: call(:get_state)
          G-->>-C: {:ok, state}
      """

      # Sequence diagrams have different syntax - should be unchanged
      # (colons are valid in sequence diagram messages)
      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Subgraphs and special constructs" do
    test "preserves valid subgraphs" do
      input = """
      flowchart LR
          subgraph Online
          A[API] --> O["Redis"]
          end
      """

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "handles HTML line breaks in labels" do
      input = "flowchart TD\n    A[Line 1<br/>Line 2] --> B"

      # HTML should be preserved (no special chars to fix)
      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "handles style directives" do
      input = """
      flowchart TD
          A[Start] --> B[End]
          style A fill:#48bb78
      """

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end
  end

  describe "sanitize/1 - Edge cases" do
    test "handles empty input" do
      assert {:unchanged, ""} = MermaidSanitizer.sanitize("")
    end

    test "handles flowchart with semicolons" do
      input = "flowchart TD;\n    A[Start] --> B[End]"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "handles multiple node shapes" do
      input = """
      flowchart TD
          A[Rectangle]
          B(Round)
          C{Diamond}
          D((Circle))
          E[[Subroutine]]
      """

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "handles whitespace-only input" do
      input = "   \n   \n   "

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end

    test "handles input with only diagram type declaration" do
      input = "flowchart TD"

      assert {:unchanged, ^input} = MermaidSanitizer.sanitize(input)
    end
  end
end

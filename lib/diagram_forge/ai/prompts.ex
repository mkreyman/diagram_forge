defmodule DiagramForge.AI.Prompts do
  @moduledoc """
  Prompt templates for AI-powered concept extraction and diagram generation.

  These are default prompts. Database-stored prompts (via admin) take precedence
  when available.
  """

  @concept_system_prompt """
  You are a technical teaching assistant.

  Given an excerpt from a technical document, identify the most important concepts that would be useful to explain visually in a diagram.

  Focus on:
  - architecture and components
  - data flow and message flow
  - lifecycles and state transitions
  - interactions between services or modules

  Only output strictly valid JSON. Do not include any explanation outside the JSON object.
  """

  # Mermaid version from package.json (used in prompts for version-specific syntax)
  @mermaid_version "11.12.1"

  @diagram_system_prompt """
  You generate small, interview-friendly technical diagrams in Mermaid syntax.
  Target Mermaid version: #{@mermaid_version}

  Constraints:
  - The diagram must fit on a single screen and stay readable.
  - Use at most 10 nodes and 15 edges.
  - Prefer 'flowchart' or 'sequenceDiagram' unless another type is clearly better.
  - Use concise labels, avoid sentences on nodes.

  CRITICAL Mermaid 11.x syntax rules:

  NODE LABELS - ALWAYS use proper syntax with brackets:
  - WRONG: A"text"  RIGHT: A["text"]
  - Quote with double quotes if they contain special chars:
    - Parentheses: A["process(file)"] not A[process(file)]
    - Dots: A["File.open"] not A[File.open]
    - Exclamation: A["File.open!"] not A[File.open!]
    - Colons: A["key: value"] not A[key: value]
    - @ symbol: A["@spec"] not A[@spec]
    - Curly braces: NEVER use {} unquoted, they define shapes

  EDGE LABELS - MUST be quoted if they contain { } [ ] ( ):
  - -->|"{:ok, pid}"| not -->|{:ok, pid}|
  - -->|"[1,2,3]"| not -->|[1,2,3]|
  - -->|"func(arg)"| not -->|func(arg)|

  NEVER USE CODE LITERALS IN LABELS - Use descriptive text instead:
  - WRONG: A["File.open!(\"config.txt\")"]  RIGHT: A["File.open!(config)"]
  - WRONG: |"[\"cat\", \"dog\"]"|  RIGHT: |"list of strings"| or |"[&quot;cat&quot;, &quot;dog&quot;]"|
  - WRONG: C["name: \"\""]  RIGHT: C["name: empty string"]
  - WRONG: G["@color_map[\":hsb\"]"]  RIGHT: G["@color_map[:hsb]"]
  - WRONG: |"Enum.join(list, \", \")"|  RIGHT: |"Enum.join with separator"|

  NEVER USE ESCAPE SEQUENCES:
  - NO backslash escapes: Never use \" or \' or \n inside labels
  - WRONG: A["say \"hello\""] or D["split(\"\n\")"]
  - RIGHT: A["say hello"] or D["split by newline"]

  NESTED QUOTES - Two options:
  1. SIMPLIFY (preferred): Remove inner quotes entirely
     - A["print_table(headers)"] not A["print_table([\"a\", \"b\"])"]
     - G["@color_map[:hsb]"] not G["@color_map[\":hsb\"]"]
  2. HTML ENTITY (when quotes essential): Use &quot;
     - F["Result: &quot;cat&quot;"] for quotes inside labels
     - |"[&quot;a&quot;, &quot;b&quot;]"| for edge labels with inner quotes

  BRACKETS MUST MATCH:
  - Every [ needs ], every " needs ", every { needs }
  - WRONG: B["Result: [1,2,3"]] or I["text"}
  - RIGHT: B["Result: [1,2,3]"] or I["text"]

  NEVER USE PLACEHOLDER SYNTAX:
  - WRONG: ... or %% more edges here
  - RIGHT: Write out all nodes/edges explicitly or omit them

  When in doubt: QUOTE the label AND SIMPLIFY the content to avoid inner quotes.

  Only output strictly valid JSON with the requested fields.
  """

  # Template uses {{MERMAID_CODE}}, {{SUMMARY}}, and {{ERROR_CONTEXT}} placeholders
  @fix_mermaid_syntax_prompt """
  The following Mermaid diagram has a syntax error and won't render:

  ```mermaid
  {{MERMAID_CODE}}
  ```

  Context about what this diagram should show:
  {{SUMMARY}}
  {{ERROR_CONTEXT}}

  SCAN EVERY NODE AND EDGE LABEL for these issues:

  1. MISSING BRACKETS ON NODE LABELS:
     WRONG: A"text"  or  B"value"
     RIGHT: A["text"]  or  B["value"]
     Every node with a label MUST have brackets: ID["label"] not ID"label"

  2. PARENTHESES in node labels - MUST be quoted or removed:
     WRONG: B[process(file)]  or  A[func(arg)]
     RIGHT: B["process(file)"]  or  B[process file]  or  A["func(arg)"]

  3. EDGE LABELS WITH SPECIAL CHARS - MUST be quoted in Mermaid 11.x:
     WRONG: -->|{:ok, pid}|  or  -->|[1,2,3]|  or  -->|func(arg)|
     RIGHT: -->|"{:ok, pid}"|  or  -->|"[1,2,3]"|  or  -->|"func(arg)"|
     ANY edge label containing { } [ ] ( ) MUST be wrapped in quotes: |"..."|

  4. DOTS in node labels - safer to quote:
     WRONG: A[File.open]  or  C[IO.puts]
     RIGHT: A["File.open"]  or  C["IO.puts"]

  5. EXCLAMATION MARKS - must be quoted:
     WRONG: F[File.open!]
     RIGHT: F["File.open!"]

  6. NESTED QUOTES - remove inner quotes or use HTML entities:
     WRONG: A[raise "error"]  or  A["raise \"error\""]
     RIGHT: A[raise error]  or  A["raise error"]  or  A["raise &quot;error&quot;"]

  7. COLONS, PIPES, and other special chars need quotes:
     WRONG: A[key: value]
     RIGHT: A["key: value"]

  8. MISMATCHED BRACKETS - opening and closing must match:
     WRONG: A["label']  or  B["text}  or  C['value"]
     RIGHT: A["label"]  or  B["text"]  or  C["value"]
     Check that [ matches ], " matches ", ' matches '

  9. INVALID ARROW SYNTAX - use only valid Mermaid arrows:
     WRONG: A -->> B  or  A ~~> B
     RIGHT: A --> B  or  A ---> B  or  A -.-> B  or  A ==> B
     Valid arrows: -->, --->, -.->, -.-, ==>, <-->, ---|text|

  10. MIXED QUOTE TYPES - don't mix " and ' in the same label:
      WRONG: A["it's here']  or  B['say "hello"']
      RIGHT: A["its here"]  or  B["say hello"]  or  A["it is here"]

  11. NO ESCAPED QUOTES - Mermaid CANNOT have \" or \' inside labels:
      WRONG: A["say \"hello\""]  or  B["it\'s here"]  or  |"colors[\"red\"]"|
      RIGHT: A["say hello"]  or  B["its here"]  or  |"colors red"|
      CRITICAL: Remove ALL backslash escapes. Simplify text to avoid inner quotes entirely.

  12. ESCAPED PARENTHESES - remove backslash escapes:
      WRONG: A["File.open\\(file\\)"]  or  B["func\\(arg\\)"]
      RIGHT: A["File.open(file)"]  or  B["func(arg)"]

  13. UNQUOTED @ SYMBOL - @ must be quoted in node labels:
      WRONG: A[@spec]  or  B[@type]  or  C[@doc]
      RIGHT: A["@spec"]  or  B["@type"]  or  C["@doc"]

  14. UNCLOSED OR MISSING QUOTES:
      WRONG: E["IO.puts 'End of macro]  or  F["some text]
      RIGHT: E["IO.puts End of macro"]  or  F["some text"]

  15. EMPTY STRING LITERALS - replace "" with descriptive text:
      WRONG: C["name: \"\""]  or  C["name: ""]
      RIGHT: C["name: empty string"]
      Replace empty string literals with descriptive words.

  16. FUNCTION CALLS WITH STRING ARGUMENTS - remove inner string quotes:
      WRONG: D["File.open!(\"config.txt\")"]  or  F["case File.open(\"file\")"]
      RIGHT: D["File.open!(config)"]  or  F["case File.open(file)"]
      Remove quotes around function arguments to avoid nesting.

  17. MAP/KEYWORD ACCESS WITH INNER QUOTES - simplify the syntax:
      WRONG: G["@color_map[\":hsb\"]"]  or  C["map[\":key\"]"]
      RIGHT: G["@color_map[:hsb]"]  or  C["map[:key]"]
      Remove the inner quotes around atom keys.

  18. Enum.join WITH SEPARATOR - use descriptive text:
      WRONG: |"Enum.join(list, \", \")"|  or  C["Enum.join(list, \", \")"]
      RIGHT: |"Enum.join with separator"|  or  C["Enum.join with separator"]
      Replace separator string arguments with descriptive words.

  19. DOUBLED QUOTES - normalize to single pair:
      WRONG: C[""caterpillar""]  or  A[""text""]
      RIGHT: C["caterpillar"]  or  A["text"]
      Remove extra quotes, keep only one outer pair.

  20. NESTED QUOTES WITH SPECIAL CHARS - simplify or use &quot;:
      WRONG: G["@color_map[\":hsb\"]"]  or  A["colors[\":red\"]"]
      RIGHT: G["@color_map[:hsb]"]  or  A["colors[:red]"]
      When quotes appear inside already-quoted labels, remove inner quotes.

  21. HTML ENTITIES FOR ESSENTIAL QUOTES - use &quot; when quotes are necessary:
      WRONG: F["Result: [{1, :a, \"cat\"}, {2, :b, \"dog\"}]"]
      RIGHT: F["Result: [{1, :a, &quot;cat&quot;}, {2, :b, &quot;dog&quot;}]"]
      ALSO RIGHT: F["Result: tuples with strings"] (simpler)
      When you MUST show quotes inside a quoted label, replace inner " with &quot;

  22. ESCAPE SEQUENCES - replace \n, \t, \r with words:
      WRONG: D["split(\"\n\")"]  or  D[split("\n")]
      RIGHT: D["split by newline"]  or  D["split newline"]

  23. STRING ARRAYS IN FUNCTION CALLS - use descriptive words:
      WRONG: G["print_table([\"a\", \"b\", \"c\"])"]  or  |"[[\"a\"], [\"b\"]]"|
      RIGHT: G["print_table(headers)"]  or  |"nested list"| or |"[[&quot;a&quot;], [&quot;b&quot;]]"|

  24. ELLIPSIS OR PLACEHOLDER SYNTAX - remove or expand:
      WRONG: ...  or  % more edges  or  %%
      RIGHT: (remove the line entirely or write out actual nodes/edges)
      Mermaid does not understand placeholder syntax.

  25. UNRECOVERABLE TRUNCATED LINES - remove completely:
      WRONG: K -->|"[{  or  A["incomplete
      RIGHT: (delete the entire broken line)

  26. INTERPOLATION IN ERROR STRINGS - replace with summary:
      WRONG: H["raise \"Failed: \#{msg}\""]
      RIGHT: H["raise error message"]
      Replace complex error strings with simple descriptions.

  APPROACH: Go through EACH node label [like this] and EACH edge label |like this| and fix any that contain ( ) { } . ! : | @ \ or quotes. Edge labels with special chars MUST be quoted. Verify all brackets match, arrows are valid, no escape sequences. For nested quotes, prefer simplification; if quotes are essential, use &quot; HTML entity. Remove unrecoverable truncated lines.

  Return ONLY valid JSON:

  {
    "mermaid": "fixed mermaid code here"
  }

  Keep the diagram's structure. Only fix syntax, don't redesign.
  """

  # Default functions - return module attributes directly (used by DiagramForge.AI fallback)

  @doc """
  Returns the default system prompt for concept extraction.
  Used as fallback when no DB customization exists.
  """
  def default_concept_system_prompt, do: @concept_system_prompt

  @doc """
  Returns the default system prompt for diagram generation.
  Used as fallback when no DB customization exists.
  """
  def default_diagram_system_prompt, do: @diagram_system_prompt

  @doc """
  Returns the default template for fixing Mermaid syntax errors.
  Uses {{MERMAID_CODE}}, {{SUMMARY}}, and {{ERROR_CONTEXT}} placeholders.
  Used as fallback when no DB customization exists.
  """
  def default_fix_mermaid_syntax_prompt, do: @fix_mermaid_syntax_prompt

  # Public API - checks DB first, falls back to defaults

  @doc """
  Returns the system prompt for concept extraction.
  Checks database for customized version first, falls back to default.
  """
  def concept_system_prompt do
    DiagramForge.AI.get_prompt("concept_system")
  end

  @doc """
  Returns the system prompt for diagram generation.
  Checks database for customized version first, falls back to default.
  """
  def diagram_system_prompt do
    DiagramForge.AI.get_prompt("diagram_system")
  end

  @doc """
  Returns the user prompt for concept extraction from a text chunk.

  ## Examples

      iex> DiagramForge.AI.Prompts.concept_user_prompt("some text")
      \"\"\"
      Text:
      ```text
      some text
      ```

      Return JSON in this exact structure:

      {
        "concepts": [
          {
            "name": "short name for the concept",
            "short_description": "1–2 sentence description suitable for learners or interview prep.",
            "category": "elixir | phoenix | http | kafka | llm | agents | other"
          }
        ]
      }

      Do not mention the JSON format in your response. Just output JSON.
      \"\"\"

  """
  def concept_user_prompt(text) do
    """
    Text:
    ```text
    #{text}
    ```

    Return JSON in this exact structure:

    {
      "concepts": [
        {
          "name": "short name for the concept",
          "short_description": "1–2 sentence description suitable for learners or interview prep.",
          "category": "elixir | phoenix | http | kafka | llm | agents | other"
        }
      ]
    }

    Do not mention the JSON format in your response. Just output JSON.
    """
  end

  @doc """
  Returns the user prompt for generating a diagram from a concept with context.

  ## Examples

      iex> concept = %{name: "GenServer", category: "elixir", level: :intermediate, short_description: "OTP behavior"}
      iex> DiagramForge.AI.Prompts.diagram_from_concept_user_prompt(concept, "some context")
      # Returns a formatted prompt string

  """
  def diagram_from_concept_user_prompt(concept, context_excerpt) do
    """
    Create a Mermaid diagram for this concept:

    Name: #{concept.name}
    Category: #{concept.category}
    Short description: #{concept.short_description}

    Context from the source document (optional, you may ignore irrelevant parts):
    ```text
    #{context_excerpt}
    ```

    Return JSON like:

    {
      "title": "Readable title for the diagram",
      "domain": "elixir | phoenix | http | kafka | llm | agents | other",
      "tags": ["list", "of", "short", "tags"],
      "mermaid": "mermaid code here (flowchart or sequenceDiagram, escaped as needed)",
      "summary": "1–2 sentence explanation of what the diagram shows.",
      "notes_md": "- bullet point explanation in markdown\\n- keep it concise"
    }

    Do not include markdown fences around the mermaid code.
    Do not include any explanation outside the JSON object.
    """
  end

  @doc """
  Returns the user prompt for generating a diagram from a free-form text prompt.

  ## Examples

      iex> DiagramForge.AI.Prompts.diagram_from_prompt_user_prompt("Create a diagram about how tokenization works")
      # Returns a formatted prompt string

  """
  def diagram_from_prompt_user_prompt(text) do
    """
    The user wants a small technical diagram based on this description:

    "#{text}"

    Assume the reader is a curious developer preparing for interviews.

    Return JSON with both diagram and concept information:

    {
      "title": "Readable title for the diagram",
      "domain": "elixir | phoenix | http | kafka | llm | agents | other",
      "tags": ["list", "of", "short", "tags"],
      "mermaid": "mermaid code here",
      "summary": "1–2 sentence explanation of what the diagram shows",
      "notes_md": "markdown bullets explaining key points",
      "concept": {
        "name": "short name for the main concept (e.g., 'GenServer', 'ElevenLabs', 'OAuth')",
        "short_description": "1–2 sentence description suitable for learners",
        "category": "elixir | phoenix | http | kafka | llm | agents | other"
      }
    }

    The concept should identify the main topic/entity being explained, not just repeat the diagram title.
    Only output JSON.
    """
  end

  @doc """
  Returns the user prompt for fixing Mermaid syntax errors.

  Takes the broken Mermaid code, the diagram's summary/context, and optionally
  the actual parse error from the client. Checks database for customized template
  first, falls back to default.

  Template uses {{MERMAID_CODE}}, {{SUMMARY}}, and {{ERROR_CONTEXT}} placeholders.
  """
  def fix_mermaid_syntax_prompt(broken_mermaid, summary, mermaid_error \\ nil) do
    error_context = format_error_context(mermaid_error)

    DiagramForge.AI.get_prompt("fix_mermaid_syntax")
    |> String.replace("{{MERMAID_CODE}}", broken_mermaid)
    |> String.replace("{{SUMMARY}}", summary || "")
    |> String.replace("{{ERROR_CONTEXT}}", error_context)
  end

  # Format the Mermaid error for inclusion in the AI prompt
  defp format_error_context(nil), do: ""

  defp format_error_context(error) when is_map(error) do
    parts = [
      "\n\nPARSE ERROR FROM MERMAID #{error[:mermaid_version] || @mermaid_version}:",
      error[:message] && "Error: #{error[:message]}",
      error[:line] && "Line: #{error[:line]}",
      error[:expected] && "Expected: #{error[:expected]}"
    ]

    parts
    |> Enum.filter(& &1)
    |> Enum.join("\n")
    |> then(&(&1 <> "\n\nFocus on fixing this specific error first."))
  end

  defp format_error_context(_), do: ""
end

defmodule DiagramForge.AITest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.AI
  alias DiagramForge.AI.Prompt

  describe "get_prompt/1" do
    test "returns default prompt when no DB record exists" do
      # Clear cache to ensure fresh lookup
      AI.invalidate_cache("concept_system")

      result = AI.get_prompt("concept_system")

      assert is_binary(result)
      assert result =~ "technical teaching assistant"
    end

    test "returns DB prompt when record exists" do
      custom_content = "Custom concept system prompt"
      fixture(:prompt, key: "concept_system", content: custom_content)

      # Clear cache to ensure fresh lookup
      AI.invalidate_cache("concept_system")

      result = AI.get_prompt("concept_system")

      assert result == custom_content
    end

    test "accepts atom keys" do
      AI.invalidate_cache("diagram_system")

      result = AI.get_prompt(:diagram_system)

      assert is_binary(result)
      assert result =~ "Mermaid syntax"
    end

    test "returns nil for unknown keys" do
      AI.invalidate_cache("unknown_key")

      result = AI.get_prompt("unknown_key")

      assert is_nil(result)
    end

    test "caches prompt after first lookup" do
      custom_content = "Cached prompt content"
      prompt = fixture(:prompt, key: "cache_test", content: custom_content)

      AI.invalidate_cache("cache_test")

      # First lookup - should fetch from DB
      assert AI.get_prompt("cache_test") == custom_content

      # Delete the DB record
      Repo.delete!(prompt)

      # Second lookup - should still return cached value
      assert AI.get_prompt("cache_test") == custom_content
    end
  end

  describe "invalidate_cache/1" do
    test "clears cached value for specific key" do
      custom_content = "Content before invalidation"
      fixture(:prompt, key: "invalidate_test", content: custom_content)

      AI.invalidate_cache("invalidate_test")
      assert AI.get_prompt("invalidate_test") == custom_content

      # Now update the DB record
      Repo.get_by!(Prompt, key: "invalidate_test")
      |> Prompt.changeset(%{content: "Updated content"})
      |> Repo.update!()

      # Should still return cached value
      assert AI.get_prompt("invalidate_test") == custom_content

      # Invalidate and check again
      AI.invalidate_cache("invalidate_test")
      assert AI.get_prompt("invalidate_test") == "Updated content"
    end
  end

  describe "create_prompt/1" do
    test "creates a prompt and invalidates cache" do
      attrs = %{
        "key" => "new_prompt",
        "content" => "New prompt content",
        "description" => "A new prompt"
      }

      assert {:ok, prompt} = AI.create_prompt(attrs)
      assert prompt.key == "new_prompt"
      assert prompt.content == "New prompt content"
      assert prompt.description == "A new prompt"
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = AI.create_prompt(%{"key" => "incomplete"})
      assert "can't be blank" in errors_on(changeset).content
    end

    test "fails with duplicate key" do
      fixture(:prompt, key: "duplicate_key")

      assert {:error, changeset} =
               AI.create_prompt(%{"key" => "duplicate_key", "content" => "content"})

      assert "has already been taken" in errors_on(changeset).key
    end
  end

  describe "update_prompt/2" do
    test "updates a prompt and invalidates cache" do
      prompt = fixture(:prompt, key: "update_test", content: "Original content")

      # Prime the cache
      AI.invalidate_cache("update_test")
      assert AI.get_prompt("update_test") == "Original content"

      # Update
      assert {:ok, updated} = AI.update_prompt(prompt, %{"content" => "Updated content"})
      assert updated.content == "Updated content"

      # Cache should be invalidated
      assert AI.get_prompt("update_test") == "Updated content"
    end
  end

  describe "delete_prompt/1" do
    test "deletes a prompt and invalidates cache" do
      prompt = fixture(:prompt, key: "delete_test", content: "To be deleted")

      # Prime the cache
      AI.invalidate_cache("delete_test")
      assert AI.get_prompt("delete_test") == "To be deleted"

      # Delete
      assert {:ok, _} = AI.delete_prompt(prompt)

      # Cache should be invalidated, returns nil for unknown key
      assert is_nil(AI.get_prompt("delete_test"))
    end
  end

  describe "list_all_prompts_with_status/0" do
    test "returns all known prompts with default status when no DB records" do
      prompts = AI.list_all_prompts_with_status()

      assert length(prompts) == 3

      concept_prompt = Enum.find(prompts, &(&1.key == "concept_system"))
      assert concept_prompt.source == :default
      assert is_nil(concept_prompt.db_record)
      assert is_binary(concept_prompt.content)

      diagram_prompt = Enum.find(prompts, &(&1.key == "diagram_system"))
      assert diagram_prompt.source == :default
      assert is_nil(diagram_prompt.db_record)

      fix_syntax_prompt = Enum.find(prompts, &(&1.key == "fix_mermaid_syntax"))
      assert fix_syntax_prompt.source == :default
      assert is_nil(fix_syntax_prompt.db_record)
      assert fix_syntax_prompt.content =~ "{{MERMAID_CODE}}"
    end

    test "returns database status when DB record exists" do
      db_prompt = fixture(:prompt, key: "concept_system", content: "Custom content")

      prompts = AI.list_all_prompts_with_status()

      concept_prompt = Enum.find(prompts, &(&1.key == "concept_system"))
      assert concept_prompt.source == :database
      assert concept_prompt.db_record.id == db_prompt.id
      assert concept_prompt.content == "Custom content"
    end
  end

  describe "get_prompt_with_status/1" do
    test "returns prompt with default status" do
      result = AI.get_prompt_with_status("concept_system")

      assert result.key == "concept_system"
      assert result.source == :default
      assert is_nil(result.db_record)
      assert is_binary(result.content)
    end

    test "returns prompt with database status when customized" do
      db_prompt = fixture(:prompt, key: "diagram_system", content: "Custom diagram prompt")

      result = AI.get_prompt_with_status("diagram_system")

      assert result.key == "diagram_system"
      assert result.source == :database
      assert result.db_record.id == db_prompt.id
      assert result.content == "Custom diagram prompt"
    end
  end

  describe "known_prompt_keys/0" do
    test "returns list of known prompt keys with descriptions" do
      keys = AI.known_prompt_keys()

      assert length(keys) == 3
      assert {"concept_system", _} = Enum.find(keys, fn {k, _} -> k == "concept_system" end)
      assert {"diagram_system", _} = Enum.find(keys, fn {k, _} -> k == "diagram_system" end)

      assert {"fix_mermaid_syntax", _} =
               Enum.find(keys, fn {k, _} -> k == "fix_mermaid_syntax" end)
    end
  end

  describe "fix_mermaid_syntax_prompt/2 (via Prompts module)" do
    alias DiagramForge.AI.Prompts

    test "replaces placeholders with provided values" do
      AI.invalidate_cache("fix_mermaid_syntax")

      result = Prompts.fix_mermaid_syntax_prompt("flowchart TD\n  A --> B", "A simple diagram")

      assert result =~ "flowchart TD"
      assert result =~ "A --> B"
      assert result =~ "A simple diagram"
      refute result =~ "{{MERMAID_CODE}}"
      refute result =~ "{{SUMMARY}}"
    end

    test "uses customized template when DB record exists" do
      custom_template = "Fix this: {{MERMAID_CODE}} - Context: {{SUMMARY}} - Return JSON only."
      fixture(:prompt, key: "fix_mermaid_syntax", content: custom_template)
      AI.invalidate_cache("fix_mermaid_syntax")

      result = Prompts.fix_mermaid_syntax_prompt("broken code", "test summary")

      assert result == "Fix this: broken code - Context: test summary - Return JSON only."
    end
  end
end

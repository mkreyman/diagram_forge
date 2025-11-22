defmodule DiagramForge.Diagrams.ConceptExtractorTest do
  use DiagramForge.DataCase, async: true

  import Mox

  alias DiagramForge.Diagrams.{Concept, ConceptExtractor}
  alias DiagramForge.MockAIClient
  alias DiagramForge.Repo

  setup :verify_on_exit!

  describe "extract_for_document/2" do
    test "successfully extracts concepts from document" do
      document = fixture(:document, raw_text: "Some text about GenServer and Supervisors.")

      # Mock AI response with two concepts
      ai_response = %{
        "concepts" => [
          %{
            "name" => "GenServer",
            "short_description" => "OTP behavior for processes",
            "category" => "elixir",
            "level" => "intermediate",
            "importance" => 5
          },
          %{
            "name" => "Supervisor",
            "short_description" => "OTP behavior for supervision trees",
            "category" => "elixir",
            "level" => "intermediate",
            "importance" => 5
          }
        ]
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      assert length(concepts) == 2

      concept_names = Enum.map(concepts, & &1.name) |> Enum.sort()
      assert concept_names == ["GenServer", "Supervisor"]

      # Verify concepts are in database
      saved_concepts = Repo.all(from c in Concept, where: c.document_id == ^document.id)
      assert length(saved_concepts) == 2
    end

    test "deduplicates concepts across multiple chunks" do
      # Create document with text that will be chunked
      long_text = String.duplicate("GenServer is important. ", 500)
      document = fixture(:document, raw_text: long_text)

      # Mock AI to return the same concept for each chunk
      ai_response = %{
        "concepts" => [
          %{
            "name" => "GenServer",
            "short_description" => "OTP behavior",
            "category" => "elixir",
            "level" => "beginner",
            "importance" => 3
          }
        ]
      }

      # AI client will be called multiple times (once per chunk)
      # but we should only get one concept due to deduplication
      stub(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      # Should only have one concept despite being returned from multiple chunks
      assert length(concepts) == 1
      assert hd(concepts).name == "GenServer"
    end

    test "handles case-insensitive deduplication" do
      # Create document with text that will be chunked into at least 2 chunks
      chunk1 = String.duplicate("First chunk about GenServer. ", 300)
      chunk2 = String.duplicate("Second chunk about genserver. ", 300)
      document = fixture(:document, raw_text: chunk1 <> "\n\n" <> chunk2)

      # Mock responses that return concepts with different casing
      call_count = :counters.new(1, [])

      stub(MockAIClient, :chat!, fn _messages, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response =
          if count == 0 do
            %{
              "concepts" => [
                %{
                  "name" => "GenServer",
                  "short_description" => "First occurrence",
                  "category" => "elixir",
                  "level" => "beginner",
                  "importance" => 3
                }
              ]
            }
          else
            %{
              "concepts" => [
                %{
                  "name" => "genserver",
                  "short_description" => "Second occurrence",
                  "category" => "elixir",
                  "level" => "beginner",
                  "importance" => 3
                }
              ]
            }
          end

        Jason.encode!(response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      # Should deduplicate case-insensitively, keeping first occurrence
      assert length(concepts) == 1
      assert hd(concepts).name == "GenServer"
    end

    test "skips concepts with empty names" do
      document = fixture(:document, raw_text: "Some text.")

      ai_response = %{
        "concepts" => [
          %{
            "name" => "",
            "short_description" => "Invalid concept",
            "category" => "elixir",
            "level" => "beginner",
            "importance" => 3
          },
          %{
            "name" => "ValidConcept",
            "short_description" => "Valid concept",
            "category" => "elixir",
            "level" => "beginner",
            "importance" => 3
          }
        ]
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      # Should only extract the valid concept
      assert length(concepts) == 1
      assert hd(concepts).name == "ValidConcept"
    end

    test "handles empty concepts array from AI" do
      document = fixture(:document, raw_text: "Some text.")

      ai_response = %{"concepts" => []}

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      assert concepts == []
    end

    test "handles missing concepts key in AI response" do
      document = fixture(:document, raw_text: "Some text.")

      ai_response = %{"other_key" => "value"}

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      assert concepts == []
    end

    test "reuses existing concept instead of creating duplicate" do
      document = fixture(:document, raw_text: "Some text.")

      # Create an existing concept
      existing_concept =
        fixture(:concept,
          document: document,
          name: "GenServer",
          short_description: "Old description"
        )

      # Mock AI to return the same concept (even with different description)
      ai_response = %{
        "concepts" => [
          %{
            "name" => "GenServer",
            "short_description" => "New description",
            "category" => "elixir"
          }
        ]
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      assert length(concepts) == 1
      reused_concept = hd(concepts)

      # Should be the same concept (same ID)
      assert reused_concept.id == existing_concept.id
      # Should keep the original description (not update it)
      assert reused_concept.short_description == "Old description"

      # Verify only one concept exists in database
      saved_concepts = Repo.all(from c in Concept, where: c.document_id == ^document.id)
      assert length(saved_concepts) == 1
    end

    test "associates extracted concepts with the correct document" do
      document = fixture(:document, raw_text: "Some text.")

      ai_response = %{
        "concepts" => [
          %{
            "name" => "TestConcept",
            "short_description" => "Test",
            "category" => "test",
            "level" => "beginner",
            "importance" => 3
          }
        ]
      }

      expect(MockAIClient, :chat!, fn _messages, _opts ->
        Jason.encode!(ai_response)
      end)

      concepts = ConceptExtractor.extract_for_document(document, ai_client: MockAIClient)

      assert length(concepts) == 1
      concept = hd(concepts)
      assert concept.document_id == document.id

      # Verify association works
      loaded_concept = Repo.preload(concept, :document)
      assert loaded_concept.document.id == document.id
    end
  end
end

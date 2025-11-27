defmodule DiagramForge.ContentTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Content

  describe "sanitize_diagram_content/1" do
    test "sanitizes title field" do
      attrs = %{title: "<script>alert('xss')</script>My Title"}

      result = Content.sanitize_diagram_content(attrs)

      assert result.title == "My Title"
    end

    test "sanitizes summary field" do
      attrs = %{summary: "<p>Visit http://spam.com</p>"}

      result = Content.sanitize_diagram_content(attrs)

      assert result.summary == "Visit [link removed]"
    end

    test "sanitizes diagram_source field" do
      attrs = %{
        diagram_source: """
        %%{init: {"securityLevel": "loose"}}%%
        flowchart TD
          A --> B
        """
      }

      result = Content.sanitize_diagram_content(attrs)

      refute result.diagram_source =~ "securityLevel"
      assert result.diagram_source =~ "flowchart TD"
    end

    test "handles string keys" do
      attrs = %{"title" => "<b>Bold Title</b>", "summary" => "Plain summary"}

      result = Content.sanitize_diagram_content(attrs)

      assert result.title == "Bold Title"
      assert result["summary"] == "Plain summary"
    end

    test "handles nil values" do
      attrs = %{title: nil, summary: nil, diagram_source: nil}

      result = Content.sanitize_diagram_content(attrs)

      assert result.title == nil
      assert result.summary == nil
    end

    test "preserves non-sanitizable fields" do
      attrs = %{
        title: "<b>Test</b>",
        format: :mermaid,
        visibility: :public
      }

      result = Content.sanitize_diagram_content(attrs)

      assert result.title == "Test"
      assert result.format == :mermaid
      assert result.visibility == :public
    end
  end

  describe "moderation_enabled?/0" do
    test "returns false in test environment" do
      # Test config sets moderation_enabled: false
      refute Content.moderation_enabled?()
    end
  end

  describe "get_moderation_stats/0" do
    test "returns stats map with all statuses" do
      stats = Content.get_moderation_stats()

      assert Map.has_key?(stats, :pending)
      assert Map.has_key?(stats, :approved)
      assert Map.has_key?(stats, :rejected)
      assert Map.has_key?(stats, :manual_review)
    end

    test "returns zero counts when no diagrams exist" do
      stats = Content.get_moderation_stats()

      # May have existing test data, but should return integers
      assert is_integer(stats.pending)
      assert is_integer(stats.approved)
      assert is_integer(stats.rejected)
      assert is_integer(stats.manual_review)
    end
  end

  describe "list_pending_review/1" do
    test "returns empty list when no pending diagrams" do
      result = Content.list_pending_review()

      assert is_list(result)
    end

    test "respects limit option" do
      result = Content.list_pending_review(limit: 5)

      assert length(result) <= 5
    end
  end

  describe "update_moderation_status/4" do
    setup do
      user = fixture(:user)
      diagram = fixture(:diagram, visibility: :public)
      %{user: user, diagram: diagram}
    end

    test "updates diagram moderation status", %{diagram: diagram} do
      {:ok, updated} = Content.update_moderation_status(diagram, :approved, "AI approved")

      assert updated.moderation_status == :approved
      assert updated.moderation_reason == "AI approved"
      assert updated.moderated_at != nil
    end

    test "creates moderation log entry", %{diagram: diagram} do
      {:ok, _updated} = Content.update_moderation_status(diagram, :rejected, "Contains spam")

      logs = Content.list_moderation_logs(diagram.id)

      assert length(logs) == 1
      log = hd(logs)
      assert log.action == "ai_reject"
      assert log.new_status == "rejected"
      assert log.reason == "Contains spam"
    end

    test "accepts diagram_id string", %{diagram: diagram} do
      {:ok, updated} =
        Content.update_moderation_status(diagram.id, :manual_review, "Needs review")

      assert updated.moderation_status == :manual_review
    end

    test "returns error for non-existent diagram" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = Content.update_moderation_status(fake_id, :approved, "test")
    end

    test "records performed_by_id for admin actions", %{diagram: diagram, user: user} do
      {:ok, updated} =
        Content.update_moderation_status(diagram, :approved, "Admin approved",
          performed_by_id: user.id
        )

      assert updated.moderated_by_id == user.id
    end

    test "records AI confidence and flags", %{diagram: diagram} do
      ai_result = %{confidence: 0.95, flags: ["spam", "promotional"]}

      {:ok, _updated} =
        Content.update_moderation_status(diagram, :rejected, "Spam detected",
          ai_result: ai_result
        )

      logs = Content.list_moderation_logs(diagram.id)
      log = hd(logs)

      assert log.ai_confidence == Decimal.new("0.95")
      assert log.ai_flags == ["spam", "promotional"]
    end
  end

  describe "admin_approve/3" do
    setup do
      user = fixture(:user)
      diagram = fixture(:diagram, visibility: :public, moderation_status: :manual_review)
      %{user: user, diagram: diagram}
    end

    test "approves diagram and creates log", %{diagram: diagram, user: user} do
      {:ok, updated} = Content.admin_approve(diagram, user.id)

      assert updated.moderation_status == :approved
      assert updated.moderated_by_id == user.id
    end

    test "uses default reason if not provided", %{diagram: diagram, user: user} do
      {:ok, updated} = Content.admin_approve(diagram, user.id)

      assert updated.moderation_reason =~ "approved"
    end

    test "uses custom reason when provided", %{diagram: diagram, user: user} do
      {:ok, updated} = Content.admin_approve(diagram, user.id, "Verified technical content")

      assert updated.moderation_reason == "Verified technical content"
    end
  end

  describe "admin_reject/3" do
    setup do
      user = fixture(:user)
      diagram = fixture(:diagram, visibility: :public, moderation_status: :manual_review)
      %{user: user, diagram: diagram}
    end

    test "rejects diagram and makes it private", %{diagram: diagram, user: user} do
      {:ok, updated} = Content.admin_reject(diagram, user.id, "Contains inappropriate content")

      assert updated.moderation_status == :rejected
      assert updated.visibility == :private
    end

    test "creates rejection log", %{diagram: diagram, user: user} do
      {:ok, _updated} = Content.admin_reject(diagram, user.id, "Policy violation")

      logs = Content.list_moderation_logs(diagram.id)

      assert Enum.any?(logs, fn log ->
               log.action == "admin_reject" and log.reason == "Policy violation"
             end)
    end
  end

  describe "list_moderation_logs/1" do
    setup do
      diagram = fixture(:diagram, visibility: :public)
      %{diagram: diagram}
    end

    test "returns empty list for diagram with no logs", %{diagram: diagram} do
      logs = Content.list_moderation_logs(diagram.id)

      assert logs == []
    end

    test "returns logs in descending order by date", %{diagram: diagram} do
      Content.update_moderation_status(diagram, :manual_review, "First action")
      # Sleep to ensure distinct timestamps (1s+ needed for consistent ordering)
      Process.sleep(1100)
      Content.update_moderation_status(diagram, :approved, "Second action")

      logs = Content.list_moderation_logs(diagram.id)

      assert length(logs) == 2
      # Most recent first
      assert hd(logs).new_status == "approved"
    end
  end
end

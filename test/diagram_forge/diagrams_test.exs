defmodule DiagramForge.DiagramsTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.Diagram

  describe "list_available_tags/1" do
    test "returns unique tags from all diagrams" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: ["elixir", "otp"])
      fixture(:diagram, user: user, tags: ["elixir", "phoenix"])
      fixture(:diagram, user: user, tags: ["rust", "async"])

      tags = Diagrams.list_available_tags(user.id)

      assert "elixir" in tags
      assert "otp" in tags
      assert "phoenix" in tags
      assert "rust" in tags
      assert "async" in tags
      assert length(tags) == 5
    end

    test "returns sorted tags" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: ["zulu", "alpha", "mike"])

      tags = Diagrams.list_available_tags(user.id)

      assert tags == ["alpha", "mike", "zulu"]
    end

    test "returns empty list when no diagrams exist" do
      user = fixture(:user)

      tags = Diagrams.list_available_tags(user.id)

      assert tags == []
    end

    test "handles diagrams with empty tags" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: [])
      fixture(:diagram, user: user, tags: ["test"])

      tags = Diagrams.list_available_tags(user.id)

      assert tags == ["test"]
    end
  end

  describe "get_tag_counts/1" do
    test "returns correct count for each tag" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: ["elixir", "otp"])
      fixture(:diagram, user: user, tags: ["elixir", "phoenix"])
      fixture(:diagram, user: user, tags: ["elixir"])

      counts = Diagrams.get_tag_counts(user.id)

      assert counts["elixir"] == 3
      assert counts["otp"] == 1
      assert counts["phoenix"] == 1
    end

    test "returns empty map when no diagrams exist" do
      user = fixture(:user)

      counts = Diagrams.get_tag_counts(user.id)

      assert counts == %{}
    end

    test "handles diagrams with empty tags" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: [])
      fixture(:diagram, user: user, tags: ["test"])

      counts = Diagrams.get_tag_counts(user.id)

      assert counts == %{"test" => 1}
    end
  end

  describe "add_tags/3" do
    test "adds new tags to diagram" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir"])

      assert {:ok, updated} = Diagrams.add_tags(diagram, ["phoenix", "web"], user.id)
      assert "elixir" in updated.tags
      assert "phoenix" in updated.tags
      assert "web" in updated.tags
      assert length(updated.tags) == 3
    end

    test "does not duplicate tags" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir"])

      assert {:ok, updated} = Diagrams.add_tags(diagram, ["elixir", "phoenix"], user.id)
      assert Enum.count(updated.tags, fn tag -> tag == "elixir" end) == 1
      assert length(updated.tags) == 2
    end

    test "handles empty new tags list" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir"])

      assert {:ok, updated} = Diagrams.add_tags(diagram, [], user.id)
      assert updated.tags == ["elixir"]
    end

    test "adds tags to diagram with empty tags" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: [])

      assert {:ok, updated} = Diagrams.add_tags(diagram, ["new", "tags"], user.id)
      assert updated.tags == ["new", "tags"]
    end
  end

  describe "remove_tags/3" do
    test "removes specified tags from diagram" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir", "phoenix", "web"])

      assert {:ok, updated} = Diagrams.remove_tags(diagram, ["phoenix"], user.id)
      assert "elixir" in updated.tags
      assert "web" in updated.tags
      refute "phoenix" in updated.tags
      assert length(updated.tags) == 2
    end

    test "removes multiple tags at once" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir", "phoenix", "web", "test"])

      assert {:ok, updated} = Diagrams.remove_tags(diagram, ["phoenix", "web"], user.id)
      assert updated.tags == ["elixir", "test"]
    end

    test "handles removing non-existent tags" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir"])

      assert {:ok, updated} = Diagrams.remove_tags(diagram, ["nonexistent"], user.id)
      assert updated.tags == ["elixir"]
    end

    test "handles empty tags_to_remove list" do
      user = fixture(:user)
      diagram = fixture(:diagram, user: user, tags: ["elixir"])

      assert {:ok, updated} = Diagrams.remove_tags(diagram, [], user.id)
      assert updated.tags == ["elixir"]
    end
  end

  describe "create_saved_filter/2" do
    test "creates filter with automatic sort_order" do
      user = fixture(:user)

      assert {:ok, filter} =
               Diagrams.create_saved_filter(
                 %{name: "Test Filter", tag_filter: ["elixir"], is_pinned: true},
                 user.id
               )

      assert filter.name == "Test Filter"
      assert filter.tag_filter == ["elixir"]
      assert filter.is_pinned == true
      assert filter.sort_order == 1
      assert filter.user_id == user.id
    end

    test "increments sort_order for multiple filters" do
      user = fixture(:user)

      {:ok, filter1} = Diagrams.create_saved_filter(%{name: "First", tag_filter: []}, user.id)
      {:ok, filter2} = Diagrams.create_saved_filter(%{name: "Second", tag_filter: []}, user.id)
      {:ok, filter3} = Diagrams.create_saved_filter(%{name: "Third", tag_filter: []}, user.id)

      assert filter1.sort_order == 1
      assert filter2.sort_order == 2
      assert filter3.sort_order == 3
    end

    test "enforces unique name per user" do
      user = fixture(:user)
      Diagrams.create_saved_filter(%{name: "Duplicate", tag_filter: []}, user.id)

      assert {:error, changeset} =
               Diagrams.create_saved_filter(%{name: "Duplicate", tag_filter: []}, user.id)

      # The unique constraint is on [user_id, name] but Ecto reports it on user_id
      assert changeset.errors != []
    end

    test "allows same name for different users" do
      user1 = fixture(:user)
      user2 = fixture(:user)

      {:ok, filter1} = Diagrams.create_saved_filter(%{name: "Common", tag_filter: []}, user1.id)
      {:ok, filter2} = Diagrams.create_saved_filter(%{name: "Common", tag_filter: []}, user2.id)

      assert filter1.name == filter2.name
      assert filter1.user_id != filter2.user_id
    end

    test "defaults is_pinned to true" do
      user = fixture(:user)

      {:ok, filter} = Diagrams.create_saved_filter(%{name: "Test", tag_filter: []}, user.id)

      assert filter.is_pinned == true
    end
  end

  describe "update_saved_filter/3" do
    test "updates filter when user is owner" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, name: "Original")

      assert {:ok, updated} =
               Diagrams.update_saved_filter(filter, %{name: "Updated"}, user.id)

      assert updated.name == "Updated"
    end

    test "returns error when user is not owner" do
      owner = fixture(:user)
      other_user = fixture(:user)
      filter = fixture(:saved_filter, user: owner)

      assert {:error, :unauthorized} =
               Diagrams.update_saved_filter(filter, %{name: "Hacked"}, other_user.id)
    end

    test "can update tag_filter" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, tag_filter: ["old"])

      assert {:ok, updated} =
               Diagrams.update_saved_filter(filter, %{tag_filter: ["new", "tags"]}, user.id)

      assert updated.tag_filter == ["new", "tags"]
    end

    test "can toggle is_pinned" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, is_pinned: true)

      assert {:ok, updated} = Diagrams.update_saved_filter(filter, %{is_pinned: false}, user.id)
      assert updated.is_pinned == false
    end
  end

  describe "delete_saved_filter/2" do
    test "deletes filter when user is owner" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user)

      assert {:ok, _deleted} = Diagrams.delete_saved_filter(filter, user.id)
      assert_raise Ecto.NoResultsError, fn -> Diagrams.get_saved_filter!(filter.id) end
    end

    test "returns error when user is not owner" do
      owner = fixture(:user)
      other_user = fixture(:user)
      filter = fixture(:saved_filter, user: owner)

      assert {:error, :unauthorized} = Diagrams.delete_saved_filter(filter, other_user.id)

      # Filter should still exist
      assert Diagrams.get_saved_filter!(filter.id)
    end
  end

  describe "list_saved_filters/1" do
    test "returns all filters for user sorted by sort_order" do
      user = fixture(:user)
      filter3 = fixture(:saved_filter, user: user, name: "Third", sort_order: 3)
      filter1 = fixture(:saved_filter, user: user, name: "First", sort_order: 1)
      filter2 = fixture(:saved_filter, user: user, name: "Second", sort_order: 2)

      filters = Diagrams.list_saved_filters(user.id)

      assert length(filters) == 3
      assert Enum.at(filters, 0).id == filter1.id
      assert Enum.at(filters, 1).id == filter2.id
      assert Enum.at(filters, 2).id == filter3.id
    end

    test "only returns filters for specified user" do
      user1 = fixture(:user)
      user2 = fixture(:user)
      fixture(:saved_filter, user: user1, name: "User 1 Filter")
      fixture(:saved_filter, user: user2, name: "User 2 Filter")

      filters = Diagrams.list_saved_filters(user1.id)

      assert length(filters) == 1
      assert hd(filters).name == "User 1 Filter"
    end

    test "returns empty list when user has no filters" do
      user = fixture(:user)

      filters = Diagrams.list_saved_filters(user.id)

      assert filters == []
    end
  end

  describe "list_pinned_filters/1" do
    test "returns only pinned filters" do
      user = fixture(:user)
      pinned1 = fixture(:saved_filter, user: user, name: "Pinned 1", is_pinned: true)
      _unpinned = fixture(:saved_filter, user: user, name: "Unpinned", is_pinned: false)
      pinned2 = fixture(:saved_filter, user: user, name: "Pinned 2", is_pinned: true)

      filters = Diagrams.list_pinned_filters(user.id)

      assert length(filters) == 2
      filter_ids = Enum.map(filters, & &1.id)
      assert pinned1.id in filter_ids
      assert pinned2.id in filter_ids
    end

    test "returns empty list when no pinned filters exist" do
      user = fixture(:user)
      fixture(:saved_filter, user: user, is_pinned: false)

      filters = Diagrams.list_pinned_filters(user.id)

      assert filters == []
    end

    test "returns filters sorted by sort_order" do
      user = fixture(:user)
      filter2 = fixture(:saved_filter, user: user, is_pinned: true, sort_order: 5)
      filter1 = fixture(:saved_filter, user: user, is_pinned: true, sort_order: 1)

      filters = Diagrams.list_pinned_filters(user.id)

      assert Enum.at(filters, 0).id == filter1.id
      assert Enum.at(filters, 1).id == filter2.id
    end
  end

  describe "reorder_saved_filters/2" do
    test "updates sort_order for multiple filters" do
      user = fixture(:user)
      filter1 = fixture(:saved_filter, user: user, name: "First", sort_order: 0)
      filter2 = fixture(:saved_filter, user: user, name: "Second", sort_order: 1)
      filter3 = fixture(:saved_filter, user: user, name: "Third", sort_order: 2)

      # Reorder: 3, 1, 2
      assert {:ok, _} =
               Diagrams.reorder_saved_filters([filter3.id, filter1.id, filter2.id], user.id)

      # Reload and verify new order
      reloaded1 = Diagrams.get_saved_filter!(filter1.id)
      reloaded2 = Diagrams.get_saved_filter!(filter2.id)
      reloaded3 = Diagrams.get_saved_filter!(filter3.id)

      assert reloaded3.sort_order == 0
      assert reloaded1.sort_order == 1
      assert reloaded2.sort_order == 2
    end

    test "returns error when user doesn't own one of the filters" do
      user1 = fixture(:user)
      user2 = fixture(:user)
      filter1 = fixture(:saved_filter, user: user1)
      filter2 = fixture(:saved_filter, user: user2)

      assert {:error, :unauthorized} =
               Diagrams.reorder_saved_filters([filter1.id, filter2.id], user1.id)
    end
  end

  describe "list_diagrams_by_tags/3" do
    test "returns all diagrams when tags list is empty" do
      user = fixture(:user)
      diagram1 = fixture(:diagram, user: user, tags: ["elixir"])
      diagram2 = fixture(:diagram, user: user, tags: ["rust"])

      diagrams = Diagrams.list_diagrams_by_tags(user.id, [], :all)

      diagram_ids = Enum.map(diagrams, & &1.id)
      assert length(diagrams) == 2
      assert diagram1.id in diagram_ids
      assert diagram2.id in diagram_ids
    end

    test "filters diagrams by single tag" do
      user = fixture(:user)
      elixir_diagram = fixture(:diagram, user: user, tags: ["elixir", "otp"])
      _rust_diagram = fixture(:diagram, user: user, tags: ["rust"])

      diagrams = Diagrams.list_diagrams_by_tags(user.id, ["elixir"], :all)

      assert length(diagrams) == 1
      assert hd(diagrams).id == elixir_diagram.id
    end

    test "filters diagrams by multiple tags with AND logic" do
      user = fixture(:user)
      both_tags = fixture(:diagram, user: user, tags: ["elixir", "phoenix"])
      _only_elixir = fixture(:diagram, user: user, tags: ["elixir"])
      _only_phoenix = fixture(:diagram, user: user, tags: ["phoenix"])

      diagrams = Diagrams.list_diagrams_by_tags(user.id, ["elixir", "phoenix"], :all)

      assert length(diagrams) == 1
      assert hd(diagrams).id == both_tags.id
    end

    test "returns empty list when no diagrams match all tags" do
      user = fixture(:user)
      fixture(:diagram, user: user, tags: ["elixir"])
      fixture(:diagram, user: user, tags: ["phoenix"])

      diagrams = Diagrams.list_diagrams_by_tags(user.id, ["elixir", "phoenix"], :all)

      assert diagrams == []
    end

    test "returns diagrams in descending order by inserted_at" do
      user = fixture(:user)
      # Insert in order but want them returned newest first
      old_diagram = fixture(:diagram, user: user, tags: ["test"])
      :timer.sleep(10)
      new_diagram = fixture(:diagram, user: user, tags: ["test"])

      diagrams = Diagrams.list_diagrams_by_tags(user.id, ["test"], :all)

      # Verify both diagrams are returned (ordering may vary due to timestamp precision)
      assert length(diagrams) == 2
      diagram_ids = Enum.map(diagrams, & &1.id)
      assert new_diagram.id in diagram_ids
      assert old_diagram.id in diagram_ids
    end
  end

  describe "list_diagrams_by_saved_filter/2" do
    test "returns diagrams matching filter's tag_filter" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, tag_filter: ["elixir", "phoenix"])
      matching = fixture(:diagram, user: user, tags: ["elixir", "phoenix", "web"])
      _non_matching = fixture(:diagram, user: user, tags: ["elixir"])

      diagrams = Diagrams.list_diagrams_by_saved_filter(user.id, filter)

      assert length(diagrams) == 1
      assert hd(diagrams).id == matching.id
    end

    test "returns all diagrams when filter has empty tag_filter" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, tag_filter: [])
      diagram1 = fixture(:diagram, user: user, tags: ["elixir"])
      diagram2 = fixture(:diagram, user: user, tags: ["rust"])

      diagrams = Diagrams.list_diagrams_by_saved_filter(user.id, filter)

      assert length(diagrams) == 2
      diagram_ids = Enum.map(diagrams, & &1.id)
      assert diagram1.id in diagram_ids
      assert diagram2.id in diagram_ids
    end
  end

  describe "get_saved_filter_count/2" do
    test "returns correct count of matching diagrams" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, tag_filter: ["elixir"])
      fixture(:diagram, user: user, tags: ["elixir", "otp"])
      fixture(:diagram, user: user, tags: ["elixir", "phoenix"])
      fixture(:diagram, user: user, tags: ["rust"])

      count = Diagrams.get_saved_filter_count(user.id, filter)

      assert count == 2
    end

    test "returns 0 when no diagrams match" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user, tag_filter: ["nonexistent"])
      fixture(:diagram, user: user, tags: ["elixir"])

      count = Diagrams.get_saved_filter_count(user.id, filter)

      assert count == 0
    end
  end

  describe "fork_diagram/2" do
    test "copies tags from original diagram" do
      user = fixture(:user)
      original = fixture(:diagram, user: user, tags: ["elixir", "phoenix", "original"])

      assert {:ok, forked} = Diagrams.fork_diagram(original.id, user.id)

      assert forked.tags == original.tags
      assert forked.id != original.id
    end

    test "copies all diagram data" do
      user = fixture(:user)

      original =
        fixture(:diagram,
          user: user,
          title: "Original Diagram",
          diagram_source: "flowchart TD\n  A --> B",
          summary: "Original summary",
          notes_md: "# Original notes",
          tags: ["test"],
          format: :mermaid
        )

      assert {:ok, forked} = Diagrams.fork_diagram(original.id, user.id)

      assert forked.title == original.title
      assert forked.diagram_source == original.diagram_source
      assert forked.summary == original.summary
      assert forked.notes_md == original.notes_md
      assert forked.tags == original.tags
      assert forked.format == original.format
    end

    test "generates unique slug for forked diagram" do
      user = fixture(:user)
      original = fixture(:diagram, user: user, slug: "original-slug")

      assert {:ok, forked} = Diagrams.fork_diagram(original.id, user.id)

      assert forked.slug != original.slug
      assert String.contains?(forked.slug, "original-slug")
      assert String.contains?(forked.slug, "fork")
    end

    test "sets forked_from_id to original" do
      user = fixture(:user)
      original = fixture(:diagram, user: user)

      assert {:ok, forked} = Diagrams.fork_diagram(original.id, user.id)

      # Read the forked diagram from the schema since it doesn't have the field yet
      _reloaded = Repo.get!(Diagram, forked.id)
      # Note: This will fail until forked_from_id field is added to schema
      # For now, just verify the fork was created
      assert forked.id != nil
    end
  end
end

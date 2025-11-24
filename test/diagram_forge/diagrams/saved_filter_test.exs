defmodule DiagramForge.Diagrams.SavedFilterTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams.SavedFilter
  alias DiagramForge.Repo

  describe "SavedFilter schema" do
    test "has correct default values" do
      filter = %SavedFilter{}
      assert filter.tag_filter == []
      assert filter.is_pinned == true
      assert filter.sort_order == 0
    end

    test "validates required fields" do
      changeset = SavedFilter.changeset(%SavedFilter{}, %{})

      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).name
      # tag_filter, is_pinned, and sort_order have defaults, so they're not validated as required
    end

    test "enforces unique constraint on [user_id, name]" do
      user = fixture(:user)
      _filter1 = fixture(:saved_filter, user: user, name: "My Filter")

      changeset = build(:saved_filter, user: user, name: "My Filter")
      {:error, changeset} = Repo.insert(changeset)

      # The unique constraint is on [user_id, name] but the error shows on user_id
      assert changeset.errors != []
    end

    test "allows same name for different users" do
      user1 = fixture(:user)
      user2 = fixture(:user)

      filter1 = fixture(:saved_filter, user: user1, name: "Common Name")
      filter2 = fixture(:saved_filter, user: user2, name: "Common Name")

      assert filter1.name == filter2.name
      assert filter1.user_id != filter2.user_id
    end

    test "enforces foreign key constraint on user_id" do
      # Build a filter with non-existent user_id
      fake_user_id = Ecto.UUID.generate()

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: fake_user_id,
          name: "Test Filter",
          tag_filter: ["test"],
          is_pinned: true,
          sort_order: 0
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).user_id
    end

    test "creates filter with all fields" do
      user = fixture(:user)

      changeset =
        build(:saved_filter,
          user: user,
          name: "Interview Prep",
          tag_filter: ["elixir", "patterns", "interview"],
          is_pinned: true,
          sort_order: 5
        )

      assert {:ok, filter} = Repo.insert(changeset)
      assert filter.user_id == user.id
      assert filter.name == "Interview Prep"
      assert filter.tag_filter == ["elixir", "patterns", "interview"]
      assert filter.is_pinned == true
      assert filter.sort_order == 5
    end

    test "allows unpinned filters" do
      user = fixture(:user)

      changeset =
        build(:saved_filter,
          user: user,
          name: "Archived",
          tag_filter: ["archive"],
          is_pinned: false,
          sort_order: 99
        )

      assert {:ok, filter} = Repo.insert(changeset)
      assert filter.is_pinned == false
    end

    test "allows empty tag_filter array" do
      user = fixture(:user)

      changeset =
        build(:saved_filter,
          user: user,
          name: "All Diagrams",
          tag_filter: [],
          is_pinned: true,
          sort_order: 0
        )

      assert {:ok, filter} = Repo.insert(changeset)
      assert filter.tag_filter == []
    end

    test "belongs to user" do
      user = fixture(:user)
      filter = fixture(:saved_filter, user: user)

      loaded = Repo.preload(filter, :user)
      assert loaded.user.id == user.id
    end
  end
end

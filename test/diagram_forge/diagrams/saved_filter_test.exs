defmodule DiagramForge.Diagrams.SavedFilterTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams.SavedFilter
  alias DiagramForge.Repo

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: ["elixir", "phoenix"],
          is_pinned: true,
          sort_order: 1
        })

      assert changeset.valid?
      assert changeset.changes.name == "Test Filter"
      assert changeset.changes.tag_filter == ["elixir", "phoenix"]
      assert Ecto.Changeset.get_field(changeset, :is_pinned) == true
      assert Ecto.Changeset.get_field(changeset, :sort_order) == 1
    end

    test "requires user_id" do
      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          name: "Test Filter",
          tag_filter: [],
          is_pinned: true,
          sort_order: 1
        })

      refute changeset.valid?
      assert changeset.errors[:user_id] == {"can't be blank", [validation: :required]}
    end

    test "requires name" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          tag_filter: [],
          is_pinned: true,
          sort_order: 1
        })

      refute changeset.valid?
      assert changeset.errors[:name] == {"can't be blank", [validation: :required]}
    end

    test "applies default empty array for tag_filter when not provided" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tag_filter) == []
    end

    test "applies default true for is_pinned when not provided" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :is_pinned) == true
    end

    test "applies default 0 for sort_order when not provided" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :sort_order) == 0
    end

    test "allows empty tag_filter array" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: []
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tag_filter) == []
    end

    test "allows multiple tags in tag_filter" do
      user = fixture(:user)

      changeset =
        SavedFilter.changeset(%SavedFilter{}, %{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: ["elixir", "phoenix", "otp", "testing"],
          is_pinned: true,
          sort_order: 1
        })

      assert changeset.valid?
      assert length(changeset.changes.tag_filter) == 4
    end
  end

  describe "unique constraint" do
    test "enforces unique name per user" do
      user = fixture(:user)

      # Create first filter
      %SavedFilter{}
      |> SavedFilter.changeset(%{
        user_id: user.id,
        name: "Duplicate Name",
        tag_filter: ["tag1"],
        is_pinned: true,
        sort_order: 1
      })
      |> Repo.insert!()

      # Attempt to create second filter with same name for same user
      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Duplicate Name",
          tag_filter: ["tag2"],
          is_pinned: false,
          sort_order: 2
        })

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert failed_changeset.errors[:user_id] != nil
    end

    test "allows same name for different users" do
      user1 = fixture(:user)
      user2 = fixture(:user)

      # Create filter for user1
      %SavedFilter{}
      |> SavedFilter.changeset(%{
        user_id: user1.id,
        name: "Common Name",
        tag_filter: ["tag1"],
        is_pinned: true,
        sort_order: 1
      })
      |> Repo.insert!()

      # Create filter with same name for user2 (should succeed)
      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user2.id,
          name: "Common Name",
          tag_filter: ["tag2"],
          is_pinned: false,
          sort_order: 1
        })

      assert {:ok, _filter} = Repo.insert(changeset)
    end
  end

  describe "foreign key constraint" do
    test "rejects invalid user_id" do
      # Use a valid UUID format but non-existent user
      non_existent_user_id = Ecto.UUID.generate()

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: non_existent_user_id,
          name: "Test Filter",
          tag_filter: [],
          is_pinned: true,
          sort_order: 1
        })

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert failed_changeset.errors[:user_id] != nil
    end
  end

  describe "default values" do
    test "defaults is_pinned to true" do
      user = fixture(:user)

      filter =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: [],
          sort_order: 1
        })
        |> Repo.insert!()

      assert filter.is_pinned == true
    end

    test "defaults tag_filter to empty array" do
      user = fixture(:user)

      filter =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          is_pinned: false,
          sort_order: 1
        })
        |> Repo.insert!()

      assert filter.tag_filter == []
    end

    test "defaults sort_order to 0" do
      user = fixture(:user)

      filter =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: [],
          is_pinned: true
        })
        |> Repo.insert!()

      assert filter.sort_order == 0
    end
  end

  describe "data type validation" do
    test "rejects non-array tag_filter" do
      user = fixture(:user)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: "not-an-array",
          is_pinned: true,
          sort_order: 1
        })

      refute changeset.valid?
      assert changeset.errors[:tag_filter] != nil
    end

    test "rejects non-boolean is_pinned" do
      user = fixture(:user)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: [],
          is_pinned: "not-a-boolean",
          sort_order: 1
        })

      refute changeset.valid?
      assert changeset.errors[:is_pinned] != nil
    end

    test "rejects non-integer sort_order" do
      user = fixture(:user)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: [],
          is_pinned: true,
          sort_order: "not-an-integer"
        })

      refute changeset.valid?
      assert changeset.errors[:sort_order] != nil
    end
  end

  describe "edge cases" do
    test "handles very long filter names" do
      user = fixture(:user)
      long_name = String.duplicate("a", 500)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: long_name,
          tag_filter: [],
          is_pinned: true,
          sort_order: 1
        })

      # Should accept long names (no length validation in current schema)
      assert changeset.valid?
    end

    test "handles negative sort_order" do
      user = fixture(:user)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: [],
          is_pinned: true,
          sort_order: -1
        })

      # Schema allows negative sort_order
      assert changeset.valid?
    end

    test "handles large tag_filter arrays" do
      user = fixture(:user)
      many_tags = Enum.map(1..100, &"tag#{&1}")

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: "Test Filter",
          tag_filter: many_tags,
          is_pinned: true,
          sort_order: 1
        })

      assert changeset.valid?
      assert length(changeset.changes.tag_filter) == 100
    end

    test "rejects empty string name" do
      user = fixture(:user)

      changeset =
        %SavedFilter{}
        |> SavedFilter.changeset(%{
          user_id: user.id,
          name: ""
        })

      # Empty string should fail required validation
      refute changeset.valid?
      assert changeset.errors[:name] == {"can't be blank", [validation: :required]}
    end
  end
end

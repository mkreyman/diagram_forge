defmodule DiagramForge.DiagramsAuthorizationTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams

  setup do
    # Set up superadmin email for testing
    Application.put_env(:diagram_forge, :superadmin_email, "admin@example.com")

    on_exit(fn ->
      Application.delete_env(:diagram_forge, :superadmin_email)
    end)

    :ok
  end

  describe "list_visible_diagrams/1" do
    setup do
      # Create users
      regular_user = fixture(:user, email: "regular@example.com")
      other_user = fixture(:user, email: "other@example.com")
      superadmin = fixture(:user, email: "admin@example.com")

      # Create diagrams
      public_diagram = fixture(:diagram, user_id: nil, created_by_superadmin: false)
      superadmin_diagram = fixture(:diagram, user_id: superadmin.id, created_by_superadmin: true)

      regular_user_diagram =
        fixture(:diagram, user_id: regular_user.id, created_by_superadmin: false)

      other_user_diagram = fixture(:diagram, user_id: other_user.id, created_by_superadmin: false)

      %{
        regular_user: regular_user,
        other_user: other_user,
        superadmin: superadmin,
        public_diagram: public_diagram,
        superadmin_diagram: superadmin_diagram,
        regular_user_diagram: regular_user_diagram,
        other_user_diagram: other_user_diagram
      }
    end

    test "guest user sees only public and superadmin diagrams", %{
      public_diagram: public_diagram,
      superadmin_diagram: superadmin_diagram
    } do
      diagrams = Diagrams.list_visible_diagrams(nil)
      diagram_ids = Enum.map(diagrams, & &1.id)

      assert public_diagram.id in diagram_ids
      assert superadmin_diagram.id in diagram_ids
      assert length(diagrams) == 2
    end

    test "regular user sees their own, public, and superadmin diagrams", %{
      regular_user: regular_user,
      public_diagram: public_diagram,
      superadmin_diagram: superadmin_diagram,
      regular_user_diagram: regular_user_diagram
    } do
      diagrams = Diagrams.list_visible_diagrams(regular_user)
      diagram_ids = Enum.map(diagrams, & &1.id)

      assert regular_user_diagram.id in diagram_ids
      assert public_diagram.id in diagram_ids
      assert superadmin_diagram.id in diagram_ids
      assert length(diagrams) == 3
    end

    test "regular user does not see other users' private diagrams", %{
      regular_user: regular_user,
      other_user_diagram: other_user_diagram
    } do
      diagrams = Diagrams.list_visible_diagrams(regular_user)
      diagram_ids = Enum.map(diagrams, & &1.id)

      refute other_user_diagram.id in diagram_ids
    end

    test "superadmin sees all diagrams", %{
      superadmin: superadmin,
      public_diagram: public_diagram,
      superadmin_diagram: superadmin_diagram,
      regular_user_diagram: regular_user_diagram,
      other_user_diagram: other_user_diagram
    } do
      diagrams = Diagrams.list_visible_diagrams(superadmin)
      diagram_ids = Enum.map(diagrams, & &1.id)

      assert public_diagram.id in diagram_ids
      assert superadmin_diagram.id in diagram_ids
      assert regular_user_diagram.id in diagram_ids
      assert other_user_diagram.id in diagram_ids
      assert length(diagrams) == 4
    end
  end

  describe "get_diagram_for_viewing/1" do
    test "allows viewing any diagram by UUID" do
      user = fixture(:user)
      diagram = fixture(:diagram, user_id: user.id)

      assert found = Diagrams.get_diagram_for_viewing(diagram.id)
      assert found.id == diagram.id
    end

    test "allows viewing any diagram by slug" do
      user = fixture(:user)
      diagram = fixture(:diagram, user_id: user.id, slug: "test-slug")

      assert found = Diagrams.get_diagram_for_viewing("test-slug")
      assert found.id == diagram.id
    end

    test "raises when diagram not found by UUID" do
      assert_raise Ecto.NoResultsError, fn ->
        Diagrams.get_diagram_for_viewing(Ecto.UUID.generate())
      end
    end

    test "raises when diagram not found by slug" do
      assert_raise Ecto.NoResultsError, fn ->
        Diagrams.get_diagram_for_viewing("nonexistent-slug")
      end
    end
  end

  describe "can_edit_diagram?/2" do
    test "superadmin can edit any diagram" do
      superadmin = fixture(:user, email: "admin@example.com")
      user = fixture(:user)
      diagram = fixture(:diagram, user_id: user.id)

      assert Diagrams.can_edit_diagram?(diagram, superadmin) == true
    end

    test "user can edit their own diagram" do
      user = fixture(:user)
      diagram = fixture(:diagram, user_id: user.id)

      assert Diagrams.can_edit_diagram?(diagram, user) == true
    end

    test "user cannot edit other user's diagram" do
      owner = fixture(:user)
      other_user = fixture(:user)
      diagram = fixture(:diagram, user_id: owner.id)

      assert Diagrams.can_edit_diagram?(diagram, other_user) == false
    end

    test "user cannot edit public diagram" do
      user = fixture(:user)
      public_diagram = fixture(:diagram, user_id: nil)

      assert Diagrams.can_edit_diagram?(public_diagram, user) == false
    end

    test "nil user cannot edit any diagram" do
      user = fixture(:user)
      diagram = fixture(:diagram, user_id: user.id)

      assert Diagrams.can_edit_diagram?(diagram, nil) == false
    end
  end

  describe "create_diagram_for_user/2" do
    test "creates diagram with user_id for regular user" do
      user = fixture(:user)

      attrs = %{
        title: "Test Diagram",
        slug: "test-diagram",
        diagram_source: "flowchart TD\n  A --> B"
      }

      assert {:ok, diagram} = Diagrams.create_diagram_for_user(attrs, user)
      assert diagram.user_id == user.id
      assert diagram.created_by_superadmin == false
    end

    test "creates diagram with created_by_superadmin flag for superadmin" do
      superadmin = fixture(:user, email: "admin@example.com")

      attrs = %{
        title: "Admin Diagram",
        slug: "admin-diagram",
        diagram_source: "flowchart TD\n  A --> B"
      }

      assert {:ok, diagram} = Diagrams.create_diagram_for_user(attrs, superadmin)
      assert diagram.user_id == superadmin.id
      assert diagram.created_by_superadmin == true
    end

    test "creates public diagram when user is nil" do
      attrs = %{
        title: "Public Diagram",
        slug: "public-diagram",
        diagram_source: "flowchart TD\n  A --> B"
      }

      assert {:ok, diagram} = Diagrams.create_diagram_for_user(attrs, nil)
      assert diagram.user_id == nil
      assert diagram.created_by_superadmin == false
    end

    test "returns error with invalid attributes" do
      user = fixture(:user)

      attrs = %{
        title: nil,
        slug: nil
      }

      assert {:error, changeset} = Diagrams.create_diagram_for_user(attrs, user)
      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).slug
    end
  end
end

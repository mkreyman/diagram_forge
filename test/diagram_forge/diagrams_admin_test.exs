defmodule DiagramForge.DiagramsAdminTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.Diagram

  import DiagramForge.Fixtures

  describe "admin_bulk_update_visibility/2" do
    setup do
      diagrams = [
        fixture(:diagram, visibility: :private),
        fixture(:diagram, visibility: :private),
        fixture(:diagram, visibility: :unlisted)
      ]

      %{diagrams: diagrams}
    end

    test "updates multiple diagrams to public", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :public)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :public
      end
    end

    test "updates multiple diagrams to unlisted", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :unlisted)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :unlisted
      end
    end

    test "updates multiple diagrams to private", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :private)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :private
      end
    end

    test "returns 0 count for empty list" do
      assert {:ok, 0} = Diagrams.admin_bulk_update_visibility([], :public)
    end

    test "updates timestamp on visibility change", %{diagrams: [diagram | _]} do
      original_updated_at = diagram.updated_at

      # Small delay to ensure time difference
      Process.sleep(1100)

      {:ok, 1} = Diagrams.admin_bulk_update_visibility([diagram], :public)

      updated = Repo.get!(Diagram, diagram.id)
      assert NaiveDateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "raises on invalid visibility" do
      diagram = fixture(:diagram)

      assert_raise FunctionClauseError, fn ->
        Diagrams.admin_bulk_update_visibility([diagram], :invalid)
      end
    end

    test "updates single diagram", %{diagrams: [diagram | _]} do
      assert {:ok, 1} = Diagrams.admin_bulk_update_visibility([diagram], :public)

      updated = Repo.get!(Diagram, diagram.id)
      assert updated.visibility == :public
    end
  end
end

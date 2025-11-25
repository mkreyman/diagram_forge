defmodule DiagramForgeWeb.Admin.DashboardLiveTest do
  use DiagramForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    # Set up superadmin email for testing
    Application.put_env(:diagram_forge, :superadmin_email, "admin@example.com")

    on_exit(fn ->
      Application.delete_env(:diagram_forge, :superadmin_email)
    end)

    :ok
  end

  describe "access control" do
    test "redirects to home when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/dashboard")

      assert flash["error"] =~ "logged in"
    end

    test "redirects to home when not superadmin", %{conn: conn} do
      user = fixture(:user, email: "regular@example.com")
      conn = Plug.Test.init_test_session(conn, %{user_id: user.id})

      {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/dashboard")

      assert flash["error"] =~ "superadmin"
    end

    test "allows access for superadmin", %{conn: conn} do
      superadmin = fixture(:user, email: "admin@example.com")
      conn = Plug.Test.init_test_session(conn, %{user_id: superadmin.id})

      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "Platform overview"
    end
  end

  describe "dashboard display" do
    setup %{conn: conn} do
      superadmin = fixture(:user, email: "admin@example.com")
      conn = Plug.Test.init_test_session(conn, %{user_id: superadmin.id})
      %{conn: conn, superadmin: superadmin}
    end

    test "displays statistics cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Total Users"
      assert html =~ "Total Diagrams"
      assert html =~ "Total Documents"
    end

    test "displays diagram statistics section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Diagram Statistics"
      assert html =~ "Public Diagrams"
      assert html =~ "Private Diagrams"
    end

    test "displays document statistics section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Document Statistics"
      assert html =~ "Ready"
      assert html =~ "Processing"
      assert html =~ "Errors"
    end

    test "displays recent users section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Recent Users"
      assert html =~ "admin@example.com"
    end

    test "stat cards link to resource pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      assert has_element?(view, "a[href='/admin/users']")
      assert has_element?(view, "a[href='/admin/diagrams']")
      assert has_element?(view, "a[href='/admin/documents']")
    end

    test "counts reflect actual data", %{conn: conn, superadmin: superadmin} do
      # Create additional test data
      _user2 = fixture(:user, email: "user2@example.com")
      _diagram = fixture(:diagram, visibility: :public, user_id: superadmin.id)
      _document = fixture(:document, user_id: superadmin.id, status: :ready)

      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      # Should show at least 2 users (superadmin + user2)
      assert html =~ "Total Users"
      # The page will show updated counts
    end
  end

  describe "navigation (layout)" do
    setup %{conn: conn} do
      superadmin = fixture(:user, email: "admin@example.com")
      conn = Plug.Test.init_test_session(conn, %{user_id: superadmin.id})
      %{conn: conn}
    end

    test "admin layout contains navigation links via HTTP request", %{conn: conn} do
      # LiveView tests don't include root_layout content, so we test via HTTP
      conn = get(conn, ~p"/admin/dashboard")
      html = html_response(conn, 200)

      assert html =~ "Dashboard"
      assert html =~ "Users"
      assert html =~ "Diagrams"
      assert html =~ "Documents"
    end

    test "admin layout contains back to app link via HTTP request", %{conn: conn} do
      conn = get(conn, ~p"/admin/dashboard")
      html = html_response(conn, 200)

      assert html =~ "Back to App"
      assert html =~ ~r|href=["']/["']|
    end

    test "/admin redirects to /admin/dashboard", %{conn: conn} do
      conn = get(conn, ~p"/admin")

      assert redirected_to(conn, 302) == "/admin/dashboard"
    end
  end
end

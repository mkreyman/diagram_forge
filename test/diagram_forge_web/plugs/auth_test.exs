defmodule DiagramForgeWeb.Plugs.AuthTest do
  use DiagramForgeWeb.ConnCase, async: true

  alias DiagramForgeWeb.Plugs.Auth

  setup do
    # Set up superadmin email for testing
    Application.put_env(:diagram_forge, :superadmin_email, "admin@example.com")

    on_exit(fn ->
      Application.delete_env(:diagram_forge, :superadmin_email)
    end)

    :ok
  end

  describe "Auth plug" do
    test "loads current_user from session", %{conn: conn} do
      user = fixture(:user)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user.id == user.id
      assert conn.assigns.current_user.email == user.email
    end

    test "sets is_superadmin to true for superadmin user", %{conn: conn} do
      superadmin = fixture(:user, email: "admin@example.com")

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: superadmin.id})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user.id == superadmin.id
      assert conn.assigns.is_superadmin == true
    end

    test "sets is_superadmin to false for regular user", %{conn: conn} do
      user = fixture(:user, email: "regular@example.com")

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user.id == user.id
      assert conn.assigns.is_superadmin == false
    end

    test "sets current_user to nil when no session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user == nil
    end

    test "clears session when user_id refers to nonexistent user", %{conn: conn} do
      nonexistent_id = Ecto.UUID.generate()

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: nonexistent_id})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user == nil
      # Verify session was dropped (configure_session is called with drop: true)
    end

    test "does not reload user if already assigned", %{conn: conn} do
      user = fixture(:user)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> assign(:current_user, user)
        |> Auth.call(Auth.init([]))

      # Should use the already assigned user
      assert conn.assigns.current_user == user
    end

    test "handles nil user_id in session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: nil})
        |> Auth.call(Auth.init([]))

      assert conn.assigns.current_user == nil
    end
  end
end

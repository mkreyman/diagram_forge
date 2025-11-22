defmodule DiagramForgeWeb.Plugs.RequireAuthTest do
  use DiagramForgeWeb.ConnCase, async: true

  alias DiagramForgeWeb.Plugs.RequireAuth

  describe "RequireAuth plug" do
    test "allows request when current_user is assigned", %{conn: conn} do
      user = fixture(:user)

      conn =
        conn
        |> assign(:current_user, user)
        |> RequireAuth.call(RequireAuth.init([]))

      refute conn.halted
      assert conn.assigns.current_user.id == user.id
    end

    test "loads user from session when not already assigned", %{conn: conn} do
      user = fixture(:user)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> RequireAuth.call(RequireAuth.init([]))

      refute conn.halted
      assert conn.assigns.current_user.id == user.id
    end

    test "redirects to home when no user in session", %{conn: conn} do
      conn =
        conn
        |> bypass_through(DiagramForgeWeb.Router, :browser)
        |> get("/")
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must be logged in to access this page."
    end

    test "redirects when user_id refers to nonexistent user", %{conn: conn} do
      nonexistent_id = Ecto.UUID.generate()

      conn =
        conn
        |> bypass_through(DiagramForgeWeb.Router, :browser)
        |> get("/")
        |> Plug.Test.init_test_session(%{user_id: nonexistent_id})
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must be logged in to access this page."
    end

    test "stores return path in session for valid paths", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/some-protected-path")
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("accept", "text/html")
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      assert get_session(conn, :return_to) == "/some-protected-path"
    end

    test "does not store return path for auth routes", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/auth/github")
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("accept", "text/html")
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      assert get_session(conn, :return_to) == nil
    end

    test "does not store return path for invalid paths starting with //", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "//evil.com/phishing")
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("accept", "text/html")
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      assert get_session(conn, :return_to) == nil
    end

    test "clears session on redirect", %{conn: conn} do
      conn =
        conn
        |> Map.put(:request_path, "/protected")
        |> Plug.Test.init_test_session(%{some_key: "some_value"})
        |> fetch_flash()
        |> put_req_header("accept", "text/html")
        |> RequireAuth.call(RequireAuth.init([]))

      assert conn.halted
      # Session is cleared except for return_to
      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must be logged in to access this page."
    end
  end
end

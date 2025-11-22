defmodule DiagramForgeWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires authentication.

  If the user is not authenticated, redirects to the home page with an error message.
  Stores the current path so we can redirect back after login.
  """

  import Plug.Conn
  import Phoenix.Controller
  alias DiagramForge.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      user_id = get_session(conn, :user_id)
      user = if user_id, do: Accounts.get_user(user_id)

      if user do
        assign(conn, :current_user, user)
      else
        handle_unauthenticated(conn)
      end
    end
  end

  defp handle_unauthenticated(conn) do
    return_to =
      if should_store_return_path?(conn.request_path) do
        conn.request_path
      end

    conn
    |> clear_session()
    |> maybe_put_return_to(return_to)
    |> put_flash(:error, "You must be logged in to access this page.")
    |> redirect(to: "/")
    |> halt()
  end

  defp maybe_put_return_to(conn, nil), do: conn
  defp maybe_put_return_to(conn, path), do: put_session(conn, :return_to, path)

  defp should_store_return_path?(path) when is_binary(path) do
    not String.starts_with?(path, "/auth/") and
      String.starts_with?(path, "/") and
      not String.starts_with?(path, "//")
  end
end

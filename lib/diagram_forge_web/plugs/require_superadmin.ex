defmodule DiagramForgeWeb.Plugs.RequireSuperadmin do
  @moduledoc """
  Plug that requires superadmin access.

  Must be used after the Auth plug to ensure current_user and is_superadmin are loaded.
  If the user is not a superadmin, redirects to home with an error message.

  Also provides an `on_mount` callback for use in LiveView live_sessions.
  """

  import Plug.Conn
  import Phoenix.Controller
  alias DiagramForge.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if superadmin?(conn) do
      conn
    else
      handle_unauthorized(conn)
    end
  end

  @doc """
  LiveView on_mount callback for ensuring superadmin access.

  Usage in router:

      live_session :admin,
        on_mount: [{DiagramForgeWeb.Plugs.RequireSuperadmin, :ensure_superadmin}] do
        live "/admin/users", Admin.UserResource
      end
  """
  def on_mount(:ensure_superadmin, _params, session, socket) do
    user_id = Map.get(session, "user_id")

    if user_id do
      user = Accounts.get_user(user_id)

      if Accounts.user_is_superadmin?(user) do
        socket =
          socket
          |> Phoenix.Component.assign(:current_user, user)
          |> Phoenix.Component.assign(:is_superadmin, true)

        {:cont, socket}
      else
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "You must be a superadmin to access this area.")
          |> Phoenix.LiveView.redirect(to: "/")

        {:halt, socket}
      end
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must be logged in to access this area.")
        |> Phoenix.LiveView.redirect(to: "/")

      {:halt, socket}
    end
  end

  defp superadmin?(conn) do
    conn.assigns[:is_superadmin] == true
  end

  defp handle_unauthorized(conn) do
    conn
    |> put_flash(:error, "You must be a superadmin to access this area.")
    |> redirect(to: "/")
    |> halt()
  end
end

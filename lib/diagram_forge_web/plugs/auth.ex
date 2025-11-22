defmodule DiagramForgeWeb.Plugs.Auth do
  @moduledoc """
  Plug that loads the current user from the session if present.

  This plug runs on every request and assigns the current_user to the conn.
  It does NOT require authentication - it simply loads the user if they're logged in.
  """

  import Plug.Conn
  alias DiagramForge.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      conn.assigns[:current_user] ->
        conn

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            conn
            |> assign(:current_user, nil)
            |> configure_session(drop: true)

          user ->
            conn
            |> assign(:current_user, user)
            |> assign(:is_superadmin, Accounts.user_is_superadmin?(user))
        end

      true ->
        assign(conn, :current_user, nil)
    end
  end
end

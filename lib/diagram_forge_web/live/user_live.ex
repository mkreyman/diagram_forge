defmodule DiagramForgeWeb.UserLive do
  @moduledoc """
  LiveView authentication hook.

  Provides on_mount callbacks for loading the current user in LiveViews.

  Usage:
    - `on_mount: DiagramForgeWeb.UserLive` - Loads user if present, but doesn't require auth
    - `on_mount: {DiagramForgeWeb.UserLive, :require_auth}` - Requires authentication
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias DiagramForge.Accounts

  def on_mount(:default, _params, session, socket) do
    user_id = session["user_id"]

    socket =
      socket
      |> assign_new(:current_user, fn -> load_user(user_id) end)
      |> assign_new(:is_superadmin, fn ->
        case socket.assigns[:current_user] do
          nil -> false
          user -> Accounts.user_is_superadmin?(user)
        end
      end)

    {:cont, socket}
  end

  def on_mount(:require_auth, _params, session, socket) do
    case on_mount(:default, nil, session, socket) do
      {:cont, socket} ->
        if socket.assigns[:current_user] do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/")}
        end
    end
  end

  defp load_user(nil), do: nil
  defp load_user(user_id), do: Accounts.get_user(user_id)
end

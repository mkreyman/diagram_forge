defmodule DiagramForgeWeb.AuthController do
  use DiagramForgeWeb, :controller

  alias DiagramForge.Accounts

  plug Ueberauth

  def request(conn, _params) do
    # Let Ueberauth handle OAuth request
    conn
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_attrs = %{
      email: auth.info.email,
      name: auth.info.name,
      provider: to_string(auth.provider),
      provider_uid: to_string(auth.uid),
      provider_token: auth.credentials.token,
      avatar_url: auth.info.image
    }

    case Accounts.upsert_user_from_oauth(user_attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Successfully signed in!")
        |> put_session(:user_id, user.id)
        |> delete_session(:return_to)
        |> configure_session(renew: true)
        |> redirect(to: get_redirect_path(conn))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to sign in. Please try again.")
        |> redirect(to: "/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: "/")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end

  defp get_redirect_path(conn) do
    get_session(conn, :return_to) || "/"
  end
end

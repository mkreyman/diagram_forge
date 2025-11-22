defmodule DiagramForgeWeb.AuthController do
  use DiagramForgeWeb, :controller

  alias DiagramForge.Accounts

  plug :store_pending_diagram when action == :request
  plug Ueberauth

  defp store_pending_diagram(conn, _opts) do
    # Check if there's pending diagram data to save in session
    case conn.params["pending_diagram"] do
      nil ->
        conn

      pending_json when is_binary(pending_json) ->
        case Jason.decode(pending_json) do
          {:ok, diagram_attrs} ->
            put_session(conn, :pending_diagram_save, diagram_attrs)

          {:error, _} ->
            conn
        end
    end
  end

  def request(conn, _params) do
    # Ueberauth plug handles the actual OAuth request
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
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> handle_pending_diagram_save(user)

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

  defp handle_pending_diagram_save(conn, user) do
    case get_session(conn, :pending_diagram_save) do
      nil ->
        conn
        |> put_flash(:info, "Successfully signed in!")
        |> delete_session(:return_to)
        |> redirect(to: get_redirect_path(conn))

      diagram_attrs ->
        save_pending_diagram(conn, diagram_attrs, user)
    end
  end

  defp save_pending_diagram(conn, diagram_attrs, user) do
    alias DiagramForge.Diagrams

    case Diagrams.create_diagram_for_user(diagram_attrs, user) do
      {:ok, diagram} ->
        conn
        |> delete_session(:pending_diagram_save)
        |> delete_session(:return_to)
        |> put_flash(:info, "Diagram saved!")
        |> redirect(to: ~p"/d/#{diagram.id}")

      {:error, _changeset} ->
        conn
        |> delete_session(:pending_diagram_save)
        |> delete_session(:return_to)
        |> put_flash(:error, "Failed to save diagram. Please try again.")
        |> redirect(to: "/")
    end
  end

  defp get_redirect_path(conn) do
    get_session(conn, :return_to) || "/"
  end
end

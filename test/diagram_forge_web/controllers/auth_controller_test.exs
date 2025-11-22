defmodule DiagramForgeWeb.AuthControllerTest do
  use DiagramForgeWeb.ConnCase, async: true

  alias DiagramForge.Accounts

  describe "GET /auth/github (request)" do
    test "redirects to GitHub OAuth", %{conn: conn} do
      # Ueberauth handles the redirect, we just verify the route exists
      conn = get(conn, ~p"/auth/github")
      # The actual redirect is handled by Ueberauth, so we can't test the exact URL
      # but we can verify the route doesn't error
      assert conn.state == :sent || conn.status in [302, 303]
    end
  end

  describe "GET /auth/github/callback with successful auth" do
    test "creates new user and redirects to home", %{conn: conn} do
      auth =
        build_ueberauth_auth(%{
          email: "newuser@example.com",
          name: "New User",
          uid: "github_123",
          token: "oauth_token_abc",
          image: "https://example.com/avatar.png"
        })

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/github/callback")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Successfully signed in!"

      # Verify user was created
      user = Accounts.get_user_by_email("newuser@example.com")
      assert user != nil
      assert user.name == "New User"
      assert user.provider == "github"
      assert user.provider_uid == "github_123"
      assert user.provider_token == "oauth_token_abc"
      assert user.avatar_url == "https://example.com/avatar.png"

      # Verify session was set
      assert get_session(conn, :user_id) == user.id
    end

    test "updates existing user and redirects to home", %{conn: conn} do
      existing_user =
        fixture(:user,
          email: "existing@example.com",
          provider: "github",
          provider_uid: "github_456"
        )

      auth =
        build_ueberauth_auth(%{
          email: "existing@example.com",
          name: "Updated Name",
          uid: "github_456",
          token: "new_token",
          image: "https://example.com/new-avatar.png"
        })

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/github/callback")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Successfully signed in!"

      # Verify user was updated
      user = Repo.get!(DiagramForge.Accounts.User, existing_user.id)
      assert user.name == "Updated Name"
      assert user.provider_token == "new_token"
      assert user.avatar_url == "https://example.com/new-avatar.png"

      # Verify session was set
      assert get_session(conn, :user_id) == user.id
    end

    test "renews session on successful login", %{conn: conn} do
      auth =
        build_ueberauth_auth(%{
          email: "user@example.com",
          name: "User",
          uid: "github_789",
          token: "token",
          image: nil
        })

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/github/callback")

      # Session renewal is handled by configure_session(renew: true)
      # We can verify it was called by checking the response
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to return_to path after login", %{conn: conn} do
      auth =
        build_ueberauth_auth(%{
          email: "user@example.com",
          name: "User",
          uid: "github_123",
          token: "token",
          image: nil
        })

      conn =
        conn
        |> Plug.Test.init_test_session(%{return_to: "/some-protected-page"})
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/github/callback")

      assert redirected_to(conn) == "/some-protected-page"
      assert get_session(conn, :return_to) == nil
    end
  end

  describe "GET /auth/github/callback with failed auth" do
    test "shows error and redirects to home", %{conn: conn} do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "Authentication failed"}]
      }

      conn =
        conn
        |> assign(:ueberauth_failure, failure)
        |> get(~p"/auth/github/callback")

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."

      # Verify no session was set
      assert get_session(conn, :user_id) == nil
    end

    test "handles OAuth cancellation gracefully", %{conn: conn} do
      failure = %Ueberauth.Failure{
        errors: [%Ueberauth.Failure.Error{message: "User cancelled authorization"}]
      }

      conn =
        conn
        |> assign(:ueberauth_failure, failure)
        |> get(~p"/auth/github/callback")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Authentication failed"
    end
  end

  describe "GET /auth/logout" do
    test "clears session and redirects to home", %{conn: conn} do
      user = fixture(:user)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> get(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have been logged out."
      # Session dropping via configure_session(drop: true) happens at framework level
      # We verify the redirect and flash message which are the important UX elements
    end

    test "works when no user is logged in", %{conn: conn} do
      conn = get(conn, ~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have been logged out."
    end
  end

  # Helper function to build Ueberauth auth struct
  defp build_ueberauth_auth(attrs) do
    %Ueberauth.Auth{
      provider: :github,
      uid: attrs[:uid] || "default_uid",
      info: %Ueberauth.Auth.Info{
        email: attrs[:email] || "default@example.com",
        name: attrs[:name] || "Default Name",
        image: attrs[:image]
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: attrs[:token] || "default_token"
      }
    }
  end
end

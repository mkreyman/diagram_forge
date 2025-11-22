defmodule DiagramForge.AccountsTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Accounts
  alias DiagramForge.Accounts.User

  describe "upsert_user_from_oauth/1" do
    test "creates a new user with valid OAuth data" do
      attrs = %{
        email: "new@example.com",
        name: "New User",
        provider: "github",
        provider_uid: "github_123",
        provider_token: "oauth_token_abc"
      }

      assert {:ok, user} = Accounts.upsert_user_from_oauth(attrs)
      assert user.email == "new@example.com"
      assert user.name == "New User"
      assert user.provider == "github"
      assert user.provider_uid == "github_123"
      assert user.provider_token == "oauth_token_abc"
      assert %DateTime{} = user.last_sign_in_at
    end

    test "updates existing user by provider and provider_uid" do
      existing_user = fixture(:user, provider: "github", provider_uid: "github_123")

      attrs = %{
        email: "updated@example.com",
        name: "Updated Name",
        provider: "github",
        provider_uid: "github_123",
        provider_token: "new_token"
      }

      assert {:ok, updated_user} = Accounts.upsert_user_from_oauth(attrs)
      assert updated_user.id == existing_user.id
      assert updated_user.email == "updated@example.com"
      assert updated_user.name == "Updated Name"
      assert updated_user.provider_token == "new_token"
      assert %DateTime{} = updated_user.last_sign_in_at
    end

    test "updates existing user by email when provider/uid differs" do
      existing_user =
        fixture(:user, email: "same@example.com", provider: "github", provider_uid: "old_uid")

      attrs = %{
        email: "same@example.com",
        name: "Same Email Different Provider",
        provider: "github",
        provider_uid: "new_uid",
        provider_token: "token"
      }

      assert {:ok, updated_user} = Accounts.upsert_user_from_oauth(attrs)
      assert updated_user.id == existing_user.id
      assert updated_user.provider_uid == "new_uid"
      assert %DateTime{} = updated_user.last_sign_in_at
    end

    test "updates last_sign_in_at on existing user" do
      user = fixture(:user)
      original_sign_in = user.last_sign_in_at

      # Wait a tiny bit to ensure timestamp differs
      Process.sleep(10)

      attrs = %{
        email: user.email,
        name: user.name,
        provider: user.provider,
        provider_uid: user.provider_uid,
        provider_token: "updated_token"
      }

      assert {:ok, updated_user} = Accounts.upsert_user_from_oauth(attrs)
      refute updated_user.last_sign_in_at == original_sign_in
    end

    test "returns error with invalid email" do
      attrs = %{
        email: "invalid_email",
        provider: "github",
        provider_uid: "123"
      }

      assert {:error, changeset} = Accounts.upsert_user_from_oauth(attrs)
      assert "has invalid format" in errors_on(changeset).email
    end

    test "returns error when email is missing" do
      attrs = %{
        provider: "github",
        provider_uid: "123"
      }

      assert {:error, changeset} = Accounts.upsert_user_from_oauth(attrs)
      assert "can't be blank" in errors_on(changeset).email
    end
  end

  describe "get_user/1" do
    test "returns user when found" do
      user = fixture(:user)
      assert found_user = Accounts.get_user(user.id)
      assert found_user.id == user.id
      assert found_user.email == user.email
    end

    test "returns nil when user not found" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_user_by_provider/2" do
    test "returns user with matching provider and provider_uid" do
      user = fixture(:user, provider: "github", provider_uid: "unique_123")

      assert found_user = Accounts.get_user_by_provider("github", "unique_123")
      assert found_user.id == user.id
    end

    test "returns nil when provider doesn't match" do
      fixture(:user, provider: "github", provider_uid: "123")

      assert Accounts.get_user_by_provider("gitlab", "123") == nil
    end

    test "returns nil when provider_uid doesn't match" do
      fixture(:user, provider: "github", provider_uid: "123")

      assert Accounts.get_user_by_provider("github", "456") == nil
    end

    test "returns nil when no user exists" do
      assert Accounts.get_user_by_provider("github", "nonexistent") == nil
    end
  end

  describe "get_user_by_email/1" do
    test "returns user with matching email" do
      user = fixture(:user, email: "unique@example.com")

      assert found_user = Accounts.get_user_by_email("unique@example.com")
      assert found_user.id == user.id
    end

    test "returns nil when email doesn't match" do
      fixture(:user, email: "user@example.com")

      assert Accounts.get_user_by_email("other@example.com") == nil
    end

    test "returns nil when no user exists" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end
  end

  describe "user_is_superadmin?/1" do
    setup do
      # Store original config
      original_email = Application.get_env(:diagram_forge, :superadmin_email)

      # Set test superadmin email
      Application.put_env(:diagram_forge, :superadmin_email, "admin@example.com")

      on_exit(fn ->
        # Restore original config
        if original_email do
          Application.put_env(:diagram_forge, :superadmin_email, original_email)
        else
          Application.delete_env(:diagram_forge, :superadmin_email)
        end
      end)

      :ok
    end

    test "returns true for superadmin user" do
      user = %User{email: "admin@example.com"}
      assert Accounts.user_is_superadmin?(user) == true
    end

    test "returns false for regular user" do
      user = %User{email: "regular@example.com"}
      assert Accounts.user_is_superadmin?(user) == false
    end

    test "returns false for nil user" do
      assert Accounts.user_is_superadmin?(nil) == false
    end

    test "returns false when superadmin_email is not configured" do
      Application.delete_env(:diagram_forge, :superadmin_email)

      user = %User{email: "any@example.com"}
      assert Accounts.user_is_superadmin?(user) == false
    end
  end
end

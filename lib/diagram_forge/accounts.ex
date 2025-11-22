defmodule DiagramForge.Accounts do
  @moduledoc """
  The Accounts context - handles user authentication and authorization.
  """

  import Ecto.Query
  alias DiagramForge.Accounts.User
  alias DiagramForge.Repo

  @doc """
  Upserts a user from OAuth data.

  If a user with the same provider and provider_uid exists, updates their data.
  If a user with the same email exists (but different provider/uid), updates their provider info.
  Otherwise, creates a new user.
  """
  def upsert_user_from_oauth(attrs) do
    case get_user_by_provider(attrs[:provider], attrs[:provider_uid]) do
      nil ->
        case get_user_by_email(attrs[:email]) do
          nil ->
            %User{}
            |> User.changeset(attrs)
            |> Repo.insert()

          user ->
            user
            |> User.changeset(attrs)
            |> User.sign_in_changeset()
            |> Repo.update()
        end

      user ->
        user
        |> User.changeset(attrs)
        |> User.sign_in_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Gets a user by provider and provider_uid.
  """
  def get_user_by_provider(provider, provider_uid) do
    User
    |> where([u], u.provider == ^provider and u.provider_uid == ^provider_uid)
    |> Repo.one()
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    User
    |> where([u], u.email == ^email)
    |> Repo.one()
  end

  @doc """
  Checks if a user is a superadmin based on the configured superadmin email.
  """
  def user_is_superadmin?(%User{email: email}) do
    superadmin_email = Application.get_env(:diagram_forge, :superadmin_email)
    superadmin_email && email == superadmin_email
  end

  def user_is_superadmin?(nil), do: false
end

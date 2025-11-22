defmodule DiagramForge.Accounts.User do
  @moduledoc """
  Schema for users authenticated via GitHub OAuth.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :provider, :string, default: "github"
    field :provider_uid, :string
    field :provider_token, :binary
    field :avatar_url, :string
    field :last_sign_in_at, :utc_datetime

    has_many :diagrams, DiagramForge.Diagrams.Diagram

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :provider, :provider_uid, :provider_token, :avatar_url])
    |> validate_required([:email, :provider, :provider_uid])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_uid])
  end

  def sign_in_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:last_sign_in_at])
    |> put_change(:last_sign_in_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end

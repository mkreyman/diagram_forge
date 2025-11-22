defmodule DiagramForge.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :provider, :string, default: "github", null: false
      add :provider_uid, :string, null: false
      add :provider_token, :text
      add :avatar_url, :string
      add :last_sign_in_at, :utc_datetime

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:provider, :provider_uid])
  end
end

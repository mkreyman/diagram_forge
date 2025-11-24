defmodule DiagramForge.Diagrams.SavedFilter do
  @moduledoc """
  Schema for saved tag filters.

  Saved filters allow users to create named combinations of tags for quick
  access to relevant diagrams. Pinned filters appear in the sidebar for
  easy navigation.

  ## Examples

  - name: "Interview Prep", tag_filter: ["elixir", "patterns"], is_pinned: true
  - name: "OAuth Project", tag_filter: ["oauth", "security"], is_pinned: true
  - name: "Archived Ideas", tag_filter: ["archive"], is_pinned: false
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_filters" do
    belongs_to :user, DiagramForge.Accounts.User

    field :name, :string
    field :tag_filter, {:array, :string}, default: []
    field :is_pinned, :boolean, default: true
    field :sort_order, :integer, default: 0

    timestamps()
  end

  def changeset(saved_filter, attrs) do
    saved_filter
    |> cast(attrs, [:user_id, :name, :tag_filter, :is_pinned, :sort_order])
    |> validate_required([:user_id, :name])
    |> put_default(:tag_filter, [])
    |> put_default(:is_pinned, true)
    |> put_default(:sort_order, 0)
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end

  defp put_default(changeset, field, default_value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default_value)
      _ -> changeset
    end
  end
end

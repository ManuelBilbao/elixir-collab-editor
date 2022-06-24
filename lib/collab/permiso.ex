defmodule Collab.Permiso do
  use Ecto.Schema
  import Ecto.Changeset

  schema "permisos" do
    field(:document, :string)
    field(:perm, :integer)
    field(:user, :string)

    timestamps()
  end

  @doc false
  def changeset(permiso, attrs) do
    permiso
    |> cast(attrs, [:document, :user, :perm])
    |> validate_required([:document, :user, :perm])
  end
end

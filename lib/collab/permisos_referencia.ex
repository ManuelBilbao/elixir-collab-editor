defmodule Collab.PermisosReferencia do
  use Ecto.Schema
  import Ecto.Changeset

  schema "permisos_referencia" do
    field(:description, :string)
    field(:id_perm, :integer)

    timestamps()
  end

  @doc false
  def changeset(permiso_ref, attrs) do
    permiso_ref
    |> cast(attrs, [:description, :id_perm])
    |> validate_required([:description, :id_perm])
  end
end

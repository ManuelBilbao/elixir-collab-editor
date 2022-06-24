defmodule Collab.Repo.Migrations.PermisosReferencia do
  use Ecto.Migration

  def change do
    create table(:permisos_referencia) do
      add :description, :string
      add :id_perm, :integer

      timestamps()
    end
  end
end

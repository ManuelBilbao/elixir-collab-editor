defmodule Collab.Repo.Migrations.CreatePermisos do
  use Ecto.Migration

  def change do
    create table(:permisos) do
      add :document, :string
      add :user, :string
      add :perm, :integer

      timestamps()
    end

  end
end

defmodule Collab.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :name, :string
      add :content, :string

      timestamps()
    end

  end
end

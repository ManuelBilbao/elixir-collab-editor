defmodule Collab.Doc do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :content, :string
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:name, :content])
    |> validate_required([:name])
  end
end

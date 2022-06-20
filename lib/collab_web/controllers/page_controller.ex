defmodule CollabWeb.PageController do
  import Ecto.Query
  alias Collab.Document
  use CollabWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def view(conn, %{"id" => id, "key" => key}) do
    case Collab.Doc |> Collab.Repo.get_by(name: id) do
      nil -> render(conn, "view.html", %{:id => id, :key => key, :users_permissions => []})
      doc ->
        case Collab.Permiso |> Collab.Repo.get_by(document: id, user: key) do
          nil -> render(conn, "error.html")
          %{:perm => 2} ->
            # query = from(p in Collab.Permiso, where: p.document == ^id and p.user != ^key)
            # permissions = Collab.Repo.all(query)
            permissions = elem(Document.get_users_permissions(id, key), 1)
            render(conn, "view.html", %{:id => id, :key => key, :users_permissions => permissions})
          _perm ->
            render(conn, "view.html", %{:id => id, :key => key, :users_permissions => nil })
        end
    end
  end

end

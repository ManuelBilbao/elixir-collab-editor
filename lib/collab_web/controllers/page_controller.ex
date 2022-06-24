defmodule CollabWeb.PageController do
  import Ecto.Query
  alias Collab.Document
  use CollabWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def view(conn, %{"id" => id, "key" => key}) do
    query_refs_perm =
      from(p in Collab.PermisosReferencia,
        select: %{desc: p.description, perm: p.id_perm}
      )

    ref_perms = Collab.Repo.all(query_refs_perm)

    user_permission = Collab.Permiso |> Collab.Repo.get_by(document: id, user: key)

    case Collab.Doc |> Collab.Repo.get_by(name: id) do
      nil ->
        render(conn, "view.html", %{
          :id => id,
          :key => key,
          :user_permission => user_permission,
          :all_users_permissions => [],
          :refs_permissions => ref_perms
        })

      _doc ->
        case user_permission do
          nil ->
            render(conn, "error.html")

          %{:perm => perm} ->
            permissions = Document.get_users_permissions(id, key)

            render(conn, "view.html", %{
              :id => id,
              :key => key,
              :user_permission => perm,
              :all_users_permissions => permissions,
              :refs_permissions => ref_perms
            })
        end
    end
  end
end

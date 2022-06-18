defmodule CollabWeb.PageController do
  use CollabWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def view(conn, %{"id" => id, "key" => key}) do
    # render(conn, "view.html", id: id)

    # es lo mismo, pero te permite pasar mas parametros al template
    conn
    |> assign(:id, id)
    |> assign(:key, key)
    |> render("view.html")
  end
end

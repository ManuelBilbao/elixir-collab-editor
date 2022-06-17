defmodule CollabWeb.DocChannel do
  use CollabWeb, :channel
  alias Collab.Document
  require Logger

  @impl true
  def join("doc:" <> id <> ":" <> key, _payload, socket) do

    case Collab.Repo.get_by(Collab.Doc, name: id) do
      nil ->
        Document.new(id, key)
      doc ->
        respond = Document.open(id, key, doc.content)
        if responde[1] != :ok do
          {:error, 0}
        else
          socket = assign(socket, :id, id)
          send(self(), :after_join)
          {:ok, socket}
        end
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    response = Document.get_contents(socket.assigns.id)
    push(socket, "open", response)

    {:noreply, socket}
  end

  @impl true
  def handle_in("save", _, socket) do
    response = Document.save(socket.assigns.id)
    {:reply, response, socket}
  end

  @impl true
  def handle_in("update", %{"change" => change, "version" => version, "key" => key}, socket) do
    case Document.update(socket.assigns.id, change, version, key) do
      {:ok, response} ->
        # Process.sleep(1000)
        broadcast_from!(socket, "update", response)
        {:reply, :ok, socket}

      error ->
        Logger.error(inspect(error))
        {:reply, {:error, inspect(error)}, socket}
    end
  end
end

defmodule Collab.Document do
  import Ecto.Query
  use GenServer
  alias __MODULE__.Supervisor

  @initial_state %{
    version: 0,
    changes: [],
    contents: [],
  }


  # Public API
  # ----------

  def start_link({id, content}), do: GenServer.start_link(__MODULE__, {:ok, {id, content}}, name: name(id))
  def stop(id),       do: GenServer.stop(name(id))

  def get_contents(id),        do: call(id, :get_contents)
  def save(id),                do: call(id, :save)
  def update(id, change, ver), do: call(id, {:update, change, ver})

  def open(id) do
    case GenServer.whereis(name(id)) do
      nil ->
        content = case Collab.Repo.get_by(Collab.Doc, name: id) do
          nil ->
            Collab.Doc.changeset(%Collab.Doc{}, %{"name" => id, "content" => ""}) 
              |> Collab.Repo.insert
            ""
          doc -> doc.content
        end
      	param = {id, content}
      	DynamicSupervisor.start_child(Supervisor, {__MODULE__, param})
      pid -> {:ok, pid}
    end
  end


  # Callbacks
  # ---------

  @impl true
  def init({:ok, {name, content}}) do
    # state = @initial_state
    state = %{
      name: name,
      version: 1,
      changes: [%{"insert" => content}],
      contents: [%{"insert" => content}],
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:get_contents, _from, state) do
    response = Map.take(state, [:version, :contents])
    {:reply, response, state}
  end

  @impl true
  def handle_call(:save, _from, state) do
    response = update_database(state)
    {:reply, elem(response, 0), state}
  end

  @impl true
  def handle_call({:update, client_change, client_version}, _from, state) do
    if client_version > state.version do
      # Error when client version is inconsistent with
      # server state
      {:reply, {:error, :server_behind}, state}
    else
      # Check how far behind client is
      changes_count = state.version - client_version

      # Transform client change if it was sent on an
      # older version of the document
      transformed_change =
        state.changes
        |> Enum.take(changes_count)
        |> Enum.reverse()
        |> Enum.reduce(client_change, &Delta.transform(&1, &2, true))

      state = %{
        name: state.name,
        version: state.version + 1,
        changes: [transformed_change | state.changes],
        contents: Delta.compose(state.contents, transformed_change),
      }

      if rem(state.version, 5) == 0 do
        update_database(state)
      end

      response = %{
        version: state.version,
        change: transformed_change,
      }

      {:reply, {:ok, response}, state}
    end
  end

  @impl true
  def terminate(_, state) do
    update_database(state)
    {:stop}
  end

  # Private Helpers
  # ---------------

  defp call(id, data) do
    with {:ok, pid} <- open(id), do: GenServer.call(pid, data)
  end

  defp name(id), do: {:global, {:doc, id}}

  defp update_database(state) do
    content = hd(state[:contents])["insert"]
    Collab.Doc |>
      Collab.Repo.get_by(name: state.name) |>
      Collab.Doc.changeset(%{content: content}) |>
      Collab.Repo.update
  end
end

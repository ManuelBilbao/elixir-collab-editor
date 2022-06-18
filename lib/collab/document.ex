defmodule Collab.Document do
  import Ecto.Query
  use GenServer
  alias __MODULE__.Supervisor

  @initial_state %{
    version: 0,
    changes: [],
    contents: []
  }

  # Public API
  # ----------

  def start_link({id, content}),
    do: GenServer.start_link(__MODULE__, {:ok, {id, content}}, name: name(id))

  def stop(id), do: GenServer.stop(name(id))

  def get_contents(id, key, content), do: call(id, key, content, :get_contents)
  def save(id, key, content), do: call(id, key, content, :save)

  def update(id, change, ver, key, content),
    do: call(id, key, content, {:update, change, ver, key})

  def new(id, key) do
    Collab.Doc.changeset(%Collab.Doc{}, %{"name" => id, "content" => ""})
    |> Collab.Repo.insert()

    Collab.Permiso.changeset(%Collab.Permiso{}, %{"document" => id, "perm" => 2, "user" => key})
    |> Collab.Repo.insert()

    param = {id, ""}
    DynamicSupervisor.start_child(Supervisor, {__MODULE__, param})
  end

  def open(id, key, content) do
    case Collab.Repo.get_by(Collab.Permiso, document: id, user: key) do
      nil ->
        {:error, 0}

      perm ->
        case GenServer.whereis(name(id)) do
          nil ->
            param = {id, content}
            DynamicSupervisor.start_child(Supervisor, {__MODULE__, param})

          pid ->
            {:ok, pid}
        end
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
      contents: [%{"insert" => content}]
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
  def handle_call({:update, client_change, client_version, client_key}, _from, state) do
    case Collab.Repo.get_by(Collab.Permiso, document: state.name, user: client_key) do
      nil ->
        {:reply, {:error, :permission_denied}, state}

      perm ->
        if perm.perm == 0 do
          {:reply, {:error, :permission_denied}, state}
        else
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
              contents: Delta.compose(state.contents, transformed_change)
            }

            if rem(state.version, 5) == 0 do
              update_database(state)
            end

            response = %{
              version: state.version,
              change: transformed_change
            }

            {:reply, {:ok, response}, state}
          end
        end
    end
  end

  @impl true
  def terminate(_, state) do
    update_database(state)
    {:stop}
  end

  # Private Helpers
  # ---------------

  defp call(id, key, content, data) do
    with {:ok, pid} <- open(id, key, content), do: GenServer.call(pid, data)
  end

  defp name(id), do: {:global, {:doc, id}}

  defp update_database(state) do
    content = hd(state[:contents])["insert"]

    Collab.Doc
    |> Collab.Repo.get_by(name: state.name)
    |> Collab.Doc.changeset(%{content: content})
    |> Collab.Repo.update()
  end
end

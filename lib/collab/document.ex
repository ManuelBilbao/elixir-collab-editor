defmodule Collab.Document do
  import Ecto.Query
  use GenServer
  alias __MODULE__.Supervisor

  # Public API
  # ----------

  def start_link(id),
    do: GenServer.start_link(__MODULE__, {:ok, id}, name: name(id))

  def stop(id), do: GenServer.stop(name(id))
  def add_connection(id, socket_id), do: call(id, {:add_connection, socket_id})
  def remove_connection(id, socket_id), do: call(id, {:remove_connection, socket_id})

  def get_contents(id, key), do: call(id, {:get_contents, key})
  def save(id, key), do: call(id, {:save, key})
  def get_users_permissions(id, key), do: call(id, {:get_users_permissions, key})

  def update_user_permission(id, key, user_key, user_perm), do: call(id, {:update_user_permission, key, user_key, user_perm})
  def remove_user_permission(id, key, user_key), do: call(id, {:remove_user_permission, key, user_key})

  def update(id, change, ver, key), do: call(id, {:update, change, ver, key})

  def new(id, key) do
    # buscando el id del creador en la base no funciona
    # creator_perm = Collab.PermisosReferencia |> Collab.Repo.get_by(description: "CREADOR")

    Collab.Doc.changeset(%Collab.Doc{}, %{"name" => id, "content" => ""})
    |> Collab.Repo.insert()

    Collab.Permiso.changeset(%Collab.Permiso{}, %{
      "document" => id,
      "perm" => 3,
      # "perm" => creator_perm,
      "user" => key
    })
    |> Collab.Repo.insert()

    get_thread(id)
  end

  def open(id, key) do
    case Collab.Repo.get_by(Collab.Permiso, document: id, user: key) do
      nil -> {:error, :permission_denied}
      _perm -> get_thread(id)
    end
  end

  # Callbacks
  # ---------

  @impl true
  def init({:ok, name}) do
    perm_query = from(p in Collab.Permiso, where: p.document == ^name, select: {p.user, p.perm})

    content =
      case Collab.Repo.get_by(Collab.Doc, name: name).content do
        nil -> ""
        c -> c
      end

    state = %{
      name: name,
      version: 1,
      changes: [%{"insert" => content}],
      contents: [%{"insert" => content}],
      permissions: Collab.Repo.all(perm_query),
      connections: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_contents, key}, _from, state) do
    case has_perms(key, state.permissions) do
      nil ->
        {:reply, {:error, :permission_denied}, state}

      _perm ->
        response = Map.take(state, [:version, :contents])
        {:reply, response, state}
    end
  end

  @impl true
  def handle_call({:save, key}, _from, state) do
    case has_perms(key, state.permissions) do
      nil ->
        {:reply, {:error, :permission_denied}, state}

      0 ->
        {:reply, {:error, :permission_denied}, state}

      _perm ->
        response = update_database(state)
        {:reply, elem(response, 0), state}
    end
  end

  @impl true
  def handle_call({:get_users_permissions, key}, _from, state) do
    case has_perms(key, state.permissions) do
      nil ->
        {:reply, {:error, :permission_denied}, state}

      0 ->
        {:reply, {:error, :permission_denied}, state}

      perm ->
        perm_query =
          from(p in Collab.Permiso,
            where:
              p.document == ^state.name and p.user != ^key and
                p.perm < ^perm,
            select: %{user: p.user, perm: p.perm}
          )

        {:reply, Collab.Repo.all(perm_query), state}
    end
  end

  @impl true
  def handle_call({:update, client_change, client_version, client_key}, _from, state) do
    case has_perms(client_key, state.permissions) do
      nil ->
        {:reply, {:error, :permission_denied}, state}

      0 ->
        {:reply, {:error, :permission_denied}, state}

      _perm ->
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
            permissions: state.permissions,
            connections: state.connections
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

  @impl true
  def handle_call({:update_user_permission, key, user_key, user_perm}, _from, state) do
    case has_perms(key, state.permissions) do
      nil -> {:reply, {:error, :permission_denied}, state}

      0 -> {:reply, {:error, :permission_denied}, state}

      1 -> {:reply, {:error, :permission_denied}, state}

      _perm -> case has_perms(user_key, state.permissions) do
        nil -> Collab.Permiso.changeset(%Collab.Permiso{}, %{
            "document" => state.name,
            "perm" => user_perm,
            "user" => user_key
          }) |> Collab.Repo.insert()

          state = Map.replace(state, :permissions, List.insert_at(state.permissions, 0, {user_key, user_perm}))

          {:reply, :ok, state}

        _perm -> Collab.Permiso
          |> Collab.Repo.get_by(document: state.name, user: user_key)
          |> Collab.Permiso.changeset(%{
            "document" => state.name,
            "perm" => user_perm,
            "user" => user_key
          })
          |> Collab.Repo.update()

          state = Map.replace(state, :permissions,List.keyreplace(state.permissions, user_key, 0, {user_key, user_perm}))

          {:reply, :ok, state}
      end
    end
  end

  @impl true
  def handle_call({:remove_user_permission, key, user_key}, _from, state) do
    case has_perms(key, state.permissions) do
      nil -> {:reply, {:error, :permission_denied}, state}

      0 -> {:reply, {:error, :permission_denied}, state}

      1 -> {:reply, {:error, :permission_denied}, state}

      _perm -> case has_perms(user_key, state.permissions) do
        nil -> {:reply, :ok, state}

        _perm -> Collab.Permiso
          |> Collab.Repo.get_by(document: state.name, user: user_key)
          |> Collab.Repo.delete()

          state = Map.replace(state, :permissions, List.keydelete(state.permissions, user_key, 0))

          {:reply, :ok, state}
      end
    end
  end

  @impl true
  def handle_call({:add_connection, socket_id}, _from, state) do
    state = Map.replace(state, :connections, state.connections ++ [socket_id])
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:remove_connection, socket_id}, _from, state) do
    state = Map.replace(state, :connections, state.connections -- [socket_id])

    {:reply, {:ok, length(state.connections)}, state}
  end

  @impl true
  def terminate(_, state) do
    update_database(state)
    {:stop}
  end

  # Private Helpers
  # ---------------

  defp get_thread(id) do
    case GenServer.whereis(name(id)) do
      nil ->
        DynamicSupervisor.start_child(Supervisor, {__MODULE__, id})

      pid ->
        {:ok, pid}
    end
  end

  defp call(id, data) do
    with {:ok, pid} <- get_thread(id), do: GenServer.call(pid, data)
  end

  defp name(id), do: {:global, {:doc, id}}

  defp has_perms(key, permissions) do
    case List.keyfind(permissions, key, 0) do
      nil -> nil
      {^key, perm} -> perm
    end
  end

  defp update_database(state) do
    content = case state[:contents] do
      [] -> ""
      [h | _] -> h["insert"]
    end

    Collab.Doc
    |> Collab.Repo.get_by(name: state.name)
    |> Collab.Doc.changeset(%{content: content})
    |> Collab.Repo.update()
  end
end

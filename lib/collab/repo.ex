defmodule Collab.Repo do
  use Ecto.Repo,
    otp_app: :collab,
    adapter: Ecto.Adapters.SQLite3
end

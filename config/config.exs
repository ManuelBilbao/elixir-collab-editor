# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :collab,
  ecto_repos: [Collab.Repo]

config :collab, Collab.Repo,
  database: Path.expand("../collab_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# Configures the endpoint
config :collab, CollabWeb.Endpoint,
  url: [host: "0.0.0.0"],
  secret_key_base: "3vn9BU2hV7SnMVGDHgBxlU0syfNkSdX/SEyYcgFXsioVmk1yh2WeXlFH20a7X7nB",
  render_errors: [view: CollabWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Collab.PubSub,
  live_view: [signing_salt: "fWpGML+8"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"

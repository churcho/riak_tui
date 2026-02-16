import Config

# Riak Admin API connection
config :riak_tui,
  # Bootstrap URL for the first admin API node to connect to.
  # In devrel, ports follow 100N5 pattern (dev1=10015, dev2=10025, ...).
  # In production, the default is 8099.
  bootstrap_url: "http://127.0.0.1:10015",

  # How often (ms) the ClusterPoller fetches fresh data.
  poll_interval: 2_000,

  # How often (ms) the DCRegistry re-discovers datacenters.
  dc_discovery_interval: 30_000,

  # How long (ms) to wait on a failed DC discovery before retrying.
  dc_retry_interval: 5_000,

  # Set to true to start the terminal UI in the supervision tree.
  start_ui: false,

  # HTTP request timeout (ms) for all Riak Admin API calls.
  http_timeout: 5_000,

  # Render refresh rate for the terminal UI.
  ui_refresh_ms: 1_000,

  # Node color assignments for the ring visualization.
  # Maps node names to color indices.
  node_colors: %{
    "dev1@127.0.0.1" => 0,
    "dev2@127.0.0.1" => 1,
    "dev3@127.0.0.1" => 2,
    "dev4@127.0.0.1" => 3,
    "dev5@127.0.0.1" => 4
  }

# Logger configuration
config :logger, :default_handler, level: :debug

import_config "#{config_env()}.exs"

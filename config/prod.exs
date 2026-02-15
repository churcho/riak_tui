import Config

# Production — connect to the default Riak admin API port
config :riak_tui,
  bootstrap_url: "http://127.0.0.1:8099"

config :logger, :default_handler, level: :info

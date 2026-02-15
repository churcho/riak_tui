import Config

# Test environment — suppress noisy logs from the application supervisor
config :logger, :default_handler, level: :warning

# Faster intervals for tests
config :riak_tui,
  poll_interval: 200,
  dc_discovery_interval: 100,
  dc_retry_interval: 100,
  http_timeout: 1_000

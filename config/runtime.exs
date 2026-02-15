import Config

# Runtime overrides via environment variables.
# These take precedence over config/*.exs values.

if url = System.get_env("RIAK_ADMIN_URL") do
  config :riak_tui, bootstrap_url: url
end

if interval = System.get_env("POLL_INTERVAL") do
  config :riak_tui, poll_interval: String.to_integer(interval)
end

if timeout = System.get_env("HTTP_TIMEOUT") do
  config :riak_tui, http_timeout: String.to_integer(timeout)
end

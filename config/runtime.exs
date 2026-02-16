import Config

# Runtime overrides via environment variables.
# These take precedence over config/*.exs values.

parse_positive_int = fn value, fallback ->
  case Integer.parse(String.trim(value)) do
    {parsed, ""} when parsed > 0 -> parsed
    _ -> fallback
  end
end

parse_start_ui = fn value, fallback ->
  case String.trim(value) |> String.downcase() do
    "1" -> true
    "true" -> true
    "t" -> true
    "yes" -> true
    "y" -> true
    "on" -> true
    "0" -> false
    "false" -> false
    "f" -> false
    "no" -> false
    "n" -> false
    "off" -> false
    _ -> fallback
  end
end

if url = System.get_env("RIAK_ADMIN_URL") do
  config :riak_tui, bootstrap_url: String.trim(url)
end

if interval = System.get_env("POLL_INTERVAL") do
  configured = Application.get_env(:riak_tui, :poll_interval, 2_000)
  config :riak_tui, poll_interval: parse_positive_int.(interval, configured)
end

if start_ui = System.get_env("RIAK_TUI_START_UI") do
  configured = Application.get_env(:riak_tui, :start_ui, false)
  config :riak_tui, start_ui: parse_start_ui.(start_ui, configured)
end

if refresh_ms = System.get_env("UI_REFRESH_MS") do
  configured = Application.get_env(:riak_tui, :ui_refresh_ms, 1_000)
  config :riak_tui, ui_refresh_ms: parse_positive_int.(refresh_ms, configured)
end

if timeout = System.get_env("HTTP_TIMEOUT") do
  configured = Application.get_env(:riak_tui, :http_timeout, 5_000)
  config :riak_tui, http_timeout: parse_positive_int.(timeout, configured)
end

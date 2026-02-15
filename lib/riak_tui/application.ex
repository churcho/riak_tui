defmodule RiakTui.Application do
  @moduledoc """
  OTP Application entry point for Riak TUI.

  Starts the supervision tree with:
  1. `RiakTui.DCRegistry` — discovers and tracks datacenters
  2. `RiakTui.ClusterPoller` — periodically fetches cluster data
  """
  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {RiakTui.DCRegistry, dc_registry_opts()},
      {RiakTui.ClusterPoller, cluster_poller_opts()}
    ]

    opts = [strategy: :one_for_one, name: RiakTui.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @spec dc_registry_opts() :: keyword()
  defp dc_registry_opts do
    [
      url: Application.get_env(:riak_tui, :bootstrap_url, "http://127.0.0.1:10015"),
      discovery_interval: Application.get_env(:riak_tui, :dc_discovery_interval, 30_000),
      retry_interval: Application.get_env(:riak_tui, :dc_retry_interval, 5_000)
    ]
  end

  @spec cluster_poller_opts() :: keyword()
  defp cluster_poller_opts do
    [
      interval: Application.get_env(:riak_tui, :poll_interval, 2_000)
    ]
  end
end

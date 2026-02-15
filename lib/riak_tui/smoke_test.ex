defmodule RiakTui.SmokeTest do
  @moduledoc "Temporary module to validate data flow. Delete after Milestone 4."

  # credo:disable-for-this-file Credo.Check.Warning.IoInspect
  @doc "Subscribes to the poller and prints the first batch of cluster data received."
  @spec run() :: :ok
  def run do
    RiakTui.ClusterPoller.subscribe(self())

    IO.puts("Waiting for cluster data from #{inspect(RiakTui.DCRegistry.active_dc())}...")

    receive do
      {:cluster_data, data} ->
        IO.puts("\n=== Cluster Data ===")
        IO.inspect(data.cluster, pretty: true, limit: :infinity)

        IO.puts("\n=== Handoff Data ===")
        IO.inspect(data.handoff, pretty: true, limit: :infinity)

        IO.puts("\n=== DCs Known ===")
        IO.inspect(RiakTui.DCRegistry.list_dcs(), pretty: true)

        IO.puts("\nData pipeline working!")
        :ok
    after
      10_000 ->
        IO.puts("Timeout - no data received in 10 seconds")
        IO.puts("Check: is Riak running? Is the admin API on the configured port?")
        :ok
    end
  end
end

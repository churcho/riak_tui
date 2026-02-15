defmodule RiakTui do
  @moduledoc """
  Riak TUI — a terminal user interface for monitoring and managing Riak clusters.

  This is the top-level module. The actual work is done by:

  - `RiakTui.Client` — HTTP client for the Riak Admin API
  - `RiakTui.DCRegistry` — tracks known datacenters and the active selection
  - `RiakTui.ClusterPoller` — periodically fetches cluster data and notifies subscribers
  """
end

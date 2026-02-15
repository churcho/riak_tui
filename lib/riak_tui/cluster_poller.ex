defmodule RiakTui.ClusterPoller do
  @moduledoc """
  Polls the active DC's admin API at a fixed interval.

  Notifies subscribers with fresh data via `{:cluster_data, data}` messages.
  Re-polls immediately when the active DC is switched.
  """
  use GenServer
  require Logger

  @type t :: %{
          interval: pos_integer(),
          api_url: String.t() | nil,
          subscribers: [pid()]
        }

  @doc "Starts the cluster poller process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Subscribes `pid` to receive `{:cluster_data, data}` messages on each poll cycle."
  @spec subscribe(pid()) :: :ok
  def subscribe(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  # --- Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    interval = Keyword.get(opts, :interval, 2_000)
    api_url = Keyword.get(opts, :api_url)
    dc_registry = Keyword.get(opts, :dc_registry, RiakTui.DCRegistry)

    case dc_registry do
      nil -> :ok
      name when is_atom(name) -> name.subscribe(self())
      pid when is_pid(pid) -> GenServer.cast(pid, {:subscribe, self()})
    end

    send(self(), :poll)
    {:ok, %{interval: interval, api_url: api_url, subscribers: []}}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_info(:poll, state) do
    data = fetch_all(state.api_url)
    Enum.each(state.subscribers, &send(&1, {:cluster_data, data}))
    Process.send_after(self(), :poll, state.interval)
    {:noreply, state}
  end

  def handle_info({:dc_switched, _dc_name, admin_url}, state) do
    send(self(), :poll)
    {:noreply, %{state | api_url: admin_url}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internal ---

  @spec fetch_all(String.t() | nil) :: %{cluster: map() | nil, handoff: map() | nil}
  defp fetch_all(api_url) do
    opts = if api_url, do: [url: api_url], else: []

    %{
      cluster: safe_call(fn -> RiakTui.Client.cluster_status(opts) end),
      handoff: safe_call(fn -> RiakTui.Client.handoff_status(opts) end)
    }
  end

  @spec safe_call((-> {:ok, map()} | {:error, term()})) :: map() | nil
  defp safe_call(fun) do
    case fun.() do
      {:ok, data} ->
        data

      {:error, reason} ->
        Logger.debug("[riak_tui] Poll failed: #{inspect(reason)}")
        nil
    end
  end
end

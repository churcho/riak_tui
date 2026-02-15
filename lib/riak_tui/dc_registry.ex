defmodule RiakTui.DCRegistry do
  @moduledoc """
  Tracks known datacenters by polling `/api/dcs`.

  Manages which DC is currently active (selected by the user or auto-selected
  on first discovery). Notifies subscribers when the active DC changes.
  """
  use GenServer
  require Logger

  @type t :: %__MODULE__{
          bootstrap_url: String.t(),
          discovery_interval: pos_integer(),
          retry_interval: pos_integer(),
          dcs: [map()],
          active_dc: String.t() | nil,
          active_admin_url: String.t() | nil,
          active_riak_url: String.t() | nil,
          subscribers: [pid()]
        }

  defstruct bootstrap_url: "http://127.0.0.1:10015",
            discovery_interval: 30_000,
            retry_interval: 5_000,
            dcs: [],
            active_dc: nil,
            active_admin_url: nil,
            active_riak_url: nil,
            subscribers: []

  # --- Public API ---

  @doc "Starts the DC registry process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of known DCs."
  @spec list_dcs() :: [map()]
  def list_dcs do
    GenServer.call(__MODULE__, :list_dcs)
  end

  @doc "Returns a map with the currently active DC's name and URLs."
  @spec active_dc() :: %{
          name: String.t() | nil,
          admin_url: String.t() | nil,
          riak_url: String.t() | nil
        }
  def active_dc do
    GenServer.call(__MODULE__, :active_dc)
  end

  @doc "Switches the active DC to `dc_name`. Returns `:ok` or `{:error, :unknown_dc}`."
  @spec switch_dc(String.t()) :: :ok | {:error, :unknown_dc}
  def switch_dc(dc_name) do
    GenServer.call(__MODULE__, {:switch_dc, dc_name})
  end

  @doc """
  Subscribes `pid` to DC change notifications.

  Sends `{:dc_switched, dc_name, admin_url}` on change.
  """
  @spec subscribe(pid()) :: :ok
  def subscribe(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  # --- Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    state = %__MODULE__{
      bootstrap_url: Keyword.get(opts, :url, "http://127.0.0.1:10015"),
      discovery_interval: Keyword.get(opts, :discovery_interval, 30_000),
      retry_interval: Keyword.get(opts, :retry_interval, 5_000)
    }

    send(self(), :discover)
    {:ok, state}
  end

  @impl true
  def handle_call(:list_dcs, _from, state) do
    {:reply, state.dcs, state}
  end

  def handle_call(:active_dc, _from, state) do
    {:reply,
     %{
       name: state.active_dc,
       admin_url: state.active_admin_url,
       riak_url: state.active_riak_url
     }, state}
  end

  def handle_call({:switch_dc, dc_name}, _from, state) do
    case Enum.find(state.dcs, &(&1["name"] == dc_name)) do
      nil ->
        {:reply, {:error, :unknown_dc}, state}

      dc ->
        new_state = %{
          state
          | active_dc: dc["name"],
            active_admin_url: dc["admin_url"],
            active_riak_url: dc["riak_url"]
        }

        notify_subscribers(state.subscribers, {:dc_switched, dc["name"], dc["admin_url"]})
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_info(:discover, state) do
    case RiakTui.Client.list_dcs(url: state.bootstrap_url) do
      {:ok, %{"dcs" => dcs}} ->
        old_dc = state.active_dc
        new_state = %{state | dcs: dcs}
        new_state = maybe_auto_select(new_state, dcs)

        if new_state.active_dc != old_dc and new_state.active_dc != nil do
          notify_subscribers(
            new_state.subscribers,
            {:dc_switched, new_state.active_dc, new_state.active_admin_url}
          )
        end

        Logger.info(
          "[riak_tui] Discovered #{length(dcs)} DC(s): #{inspect(Enum.map(dcs, & &1["name"]))}"
        )

        schedule_discover(state.discovery_interval)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[riak_tui] DC discovery failed: #{inspect(reason)}, retrying")
        schedule_discover(state.retry_interval)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internal ---

  @spec maybe_auto_select(t(), [map()]) :: t()
  defp maybe_auto_select(%{active_dc: nil} = state, dcs) do
    local = Enum.find(dcs, & &1["local"]) || List.first(dcs)

    if local do
      %{
        state
        | active_dc: local["name"],
          active_admin_url: local["admin_url"],
          active_riak_url: local["riak_url"]
      }
    else
      state
    end
  end

  defp maybe_auto_select(state, _dcs), do: state

  @spec schedule_discover(non_neg_integer()) :: reference()
  defp schedule_discover(ms), do: Process.send_after(self(), :discover, ms)

  @spec notify_subscribers([pid()], term()) :: :ok
  defp notify_subscribers(subs, msg) do
    Enum.each(subs, &send(&1, msg))
  end
end

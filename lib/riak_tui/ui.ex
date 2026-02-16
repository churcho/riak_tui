defmodule RiakTui.UI do
  @moduledoc """
  Lightweight terminal dashboard renderer for Riak cluster telemetry.

  The UI process subscribes to `RiakTui.ClusterPoller` and `RiakTui.DCRegistry`,
  redraws the dashboard on an interval, and re-renders automatically on
  terminal resize.
  """

  use GenServer
  require Logger

  @default_refresh_ms 1_000
  @default_size {80, 24}

  @type layout :: :compact | :split
  @type frame_state :: %{
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          optional(:dc) => map() | nil,
          optional(:cluster) => map() | nil,
          optional(:handoff) => map() | nil
        }

  @type state :: %{
          refresh_ms: pos_integer(),
          width: pos_integer(),
          height: pos_integer(),
          dc: map() | nil,
          cluster: map() | nil,
          handoff: map() | nil,
          tty_size_fn: (-> {pos_integer(), pos_integer()}),
          render_fn: (String.t() -> any()),
          refresh_ref: reference() | nil,
          last_render: String.t() | nil
        }

  @doc "Starts the terminal dashboard with optional process options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link do
    start_link([])
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Stops the dashboard loop."
  @spec stop(GenServer.server()) :: :ok
  def stop(server \\ __MODULE__) do
    GenServer.call(server, :stop)
  end

  @doc "Public rendering helper that builds a deterministic frame for testing."
  @spec render_frame(frame_state()) :: String.t()
  def render_frame(%{} = state) do
    normalized = normalize_render_state(state)

    lines =
      case layout_for_width(normalized.width) do
        :split -> split_layout_lines(normalized)
        :compact -> compact_layout_lines(normalized)
      end

    lines
    |> Enum.map(&fit_line(&1, normalized.width))
    |> format_to_height(normalized.height)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc "Returns the layout selected for the given width."
  @spec layout_for_width(pos_integer()) :: layout
  def layout_for_width(width) when width < 90, do: :compact
  def layout_for_width(_width), do: :split

  @impl true
  @spec init(keyword()) :: {:ok, state}
  def init(opts) do
    refresh_ms = Keyword.get(opts, :refresh_ms, @default_refresh_ms)
    refresh_ms = max(refresh_ms, 50)
    tty_size_fn = Keyword.get(opts, :tty_size_fn, &default_tty_size/0)
    render_fn = Keyword.get(opts, :render_fn, &IO.write/1)

    maybe_subscribe(opts)
    {width, height} = ensure_size(tty_size_fn.())

    full_state = %{
      refresh_ms: refresh_ms,
      tty_size_fn: tty_size_fn,
      render_fn: render_fn,
      width: width,
      height: height,
      dc: nil,
      cluster: nil,
      handoff: nil,
      refresh_ref: nil,
      last_render: nil
    }

    refresh_ref = schedule_refresh(refresh_ms)
    Logger.info("[riak_tui] UI started (refresh=#{refresh_ms}ms)")

    {:ok, %{full_state | refresh_ref: refresh_ref}}
  end

  @impl true
  @spec handle_call(:stop, GenServer.from(), state) :: {:stop, :normal, :ok, state}
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {width, height} = state.tty_size_fn.()
    frame = render_frame(%{state | width: width, height: height})

    if frame != state.last_render do
      state.render_fn.(frame)
    end

    refresh_ref = schedule_refresh(state.refresh_ms)

    {:noreply,
     %{state | width: width, height: height, last_render: frame, refresh_ref: refresh_ref}}
  end

  def handle_info({:dc_switched, dc_name, admin_url}, state) do
    {:noreply, %{state | dc: %{name: dc_name, admin_url: admin_url}}}
  end

  def handle_info({:cluster_data, data}, state) when is_map(data) do
    {:noreply,
     %{
       state
       | cluster: data[:cluster] || data["cluster"],
         handoff: data[:handoff] || data["handoff"]
     }}
  end

  def handle_info(msg, state) do
    Logger.debug("[riak_tui] Unhandled UI message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp maybe_subscribe(opts) do
    dc_registry = Keyword.get(opts, :dc_registry, RiakTui.DCRegistry)
    cluster_poller = Keyword.get(opts, :cluster_poller, RiakTui.ClusterPoller)
    subscribe_if_possible(dc_registry)
    subscribe_if_possible(cluster_poller)
  end

  defp subscribe_if_possible(target) when is_atom(target) do
    if function_exported?(target, :subscribe, 1), do: target.subscribe(self())
  end

  defp subscribe_if_possible(target) when is_pid(target) do
    GenServer.cast(target, {:subscribe, self()})
  end

  defp subscribe_if_possible(_target), do: :ok

  defp compact_layout_lines(state) do
    [
      top_border(state.width),
      header_line("Riak TUI", "Ctrl+C to exit", state.width),
      divider_line(state.width),
      panel_lines(:cluster, state, state.width),
      divider_line(state.width),
      panel_lines(:handoff, state, state.width),
      bottom_border(state.width)
    ]
    |> List.flatten()
  end

  defp split_layout_lines(state) do
    left_width = max(30, (state.width - 3) |> div(2))
    right_width = max(30, state.width - left_width - 1)

    left_lines = panel_lines(:cluster, state, left_width)
    right_lines = panel_lines(:handoff, state, right_width)
    count = max(length(left_lines), length(right_lines))
    left_lines = pad_lines(left_lines, count)
    right_lines = pad_lines(right_lines, count)

    rows =
      Enum.zip(left_lines, right_lines)
      |> Enum.map(fn {left_line, right_line} ->
        String.slice(left_line <> " " <> right_line, 0, state.width - 2)
      end)

    [
      top_border(state.width),
      header_line("Riak TUI", "Ctrl+C to exit", state.width),
      divider_line(state.width)
      | rows
    ]
  end

  defp panel_lines(:cluster, state, width) do
    rows =
      case state.cluster do
        nil ->
          ["No cluster data yet", "Waiting for /api/cluster/status"]

        cluster ->
          memberships = cluster["members"] || cluster["memberships"] || []
          pending = cluster["pending"] || cluster["pending_changes"] || []
          claimant = cluster["claimant"] || "n/a"

          [
            "Members: #{value_count(memberships)}",
            "Pending changes: #{value_count(pending)}",
            "Claimant: #{claimant}",
            "Ring: #{if cluster["num_partitions"], do: "known", else: "n/a"}"
          ]
      end

    title = "Cluster"
    box_lines(title, rows, width)
  end

  defp panel_lines(:handoff, state, width) do
    rows =
      case state.handoff do
        nil ->
          ["No handoff data yet", "Waiting for /api/handoff/status"]

        handoff ->
          active = handoff["active"] || handoff["transfers"] || []
          completed = handoff["completed"] || 0
          failed = handoff["failed"] || 0
          mode = handoff["mode"] || "standard"

          [
            "Active transfers: #{value_count(active)}",
            "Completed: #{completed}",
            "Failed: #{failed}",
            "Mode: #{mode}"
          ]
      end

    title = "Handoff"
    box_lines(title, rows, width)
  end

  defp box_lines(title, rows, width) do
    title = String.slice(title, 0, max(width - 4, 0))
    interior = max(width - 2, 0)
    border = "+" <> String.duplicate("=", interior) <> "+"
    label = "| " <> String.pad_trailing(title, max(interior - 2, 0)) <> " |"

    [border, label, border] ++
      Enum.map(rows, fn row ->
        content = String.slice(row, 0, max(width - 4, 0))
        "| " <> String.pad_trailing(content, max(width - 4, 0)) <> " |"
      end) ++ [border]
  end

  defp top_border(width) do
    "+" <> String.duplicate("=", max(width - 2, 0)) <> "+"
  end

  defp bottom_border(width) do
    "+" <> String.duplicate("=", max(width - 2, 0)) <> "+"
  end

  defp divider_line(width) do
    "+" <> String.duplicate("-", max(width - 2, 0)) <> "+"
  end

  defp header_line(left, right, width) do
    left = " " <> left
    right = right <> " "
    inner = width - 2

    content =
      if byte_size(left) + byte_size(right) >= inner do
        left <> " " <> right
      else
        right_padding = inner - byte_size(left) - byte_size(right)
        left <> String.duplicate(" ", right_padding) <> right
      end

    "|" <> fit_line(content, max(inner, 0)) <> "|"
  end

  defp value_count(value) when is_list(value), do: length(value)
  defp value_count(value) when is_integer(value), do: value
  defp value_count(nil), do: 0
  defp value_count(_), do: 1

  defp pad_lines(lines, count) when length(lines) >= count, do: lines
  defp pad_lines(lines, count), do: lines ++ List.duplicate("", count - length(lines))

  defp format_to_height(lines, height) do
    (lines ++ List.duplicate("", max(0, height - length(lines)))) |> Enum.take(height)
  end

  defp fit_line(line, width) do
    case width do
      w when w <= 0 ->
        ""

      w when byte_size(line) > w ->
        String.slice(line, 0, w)

      w ->
        String.pad_trailing(line, w)
    end
  end

  defp normalize_render_state(state) do
    %{
      width: normalize_positive_int(Map.get(state, :width), elem(@default_size, 0)),
      height: normalize_positive_int(Map.get(state, :height), elem(@default_size, 1)),
      dc: Map.get(state, :dc),
      cluster: Map.get(state, :cluster),
      handoff: Map.get(state, :handoff)
    }
  end

  defp normalize_positive_int(value, _fallback) when is_integer(value) and value > 0, do: value
  defp normalize_positive_int(_value, fallback), do: fallback

  defp ensure_size({width, height})
       when is_integer(width) and is_integer(height) and width > 0 and
              height > 0 do
    {width, height}
  end

  defp ensure_size(_), do: @default_size

  defp schedule_refresh(ms), do: Process.send_after(self(), :refresh, ms)

  defp default_tty_size do
    case parse_tty_env() do
      {columns, rows} when columns > 0 and rows > 0 ->
        {columns, rows}

      _ ->
        parse_tty_size_from_system()
    end
  end

  defp parse_tty_size_from_system do
    with {value, 0} <- System.cmd("stty", ["size"], stderr_to_stdout: true),
         {columns, rows} <- parse_tty_size(value) do
      {columns, rows}
    else
      _ -> @default_size
    end
  end

  defp parse_tty_env do
    columns = System.get_env("COLUMNS")
    lines = System.get_env("LINES")

    with {columns, ""} <- Integer.parse(columns || ""),
         {lines, ""} <- Integer.parse(lines || "") do
      {columns, lines}
    end
  end

  defp parse_tty_size(value) do
    with [rows, columns] <- String.split(value, ~r/\s+/, trim: true),
         {rows, ""} <- Integer.parse(rows),
         {columns, ""} <- Integer.parse(columns) do
      {columns, rows}
    end
  end
end

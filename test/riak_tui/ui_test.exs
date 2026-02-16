defmodule RiakTui.UITest do
  use ExUnit.Case, async: true

  alias RiakTui.UI

  describe "layout_for_width/1" do
    test "uses compact layout under wide threshold" do
      assert UI.layout_for_width(72) == :compact
    end

    test "uses split layout for wider terminals" do
      assert UI.layout_for_width(120) == :split
    end
  end

  describe "render_frame/1" do
    test "includes panel titles and footer on compact layout" do
      frame =
        UI.render_frame(%{
          width: 80,
          height: 20,
          dc: nil,
          cluster: nil,
          handoff: nil
        })

      assert String.contains?(frame, "Riak TUI")
      assert String.contains?(frame, "Cluster")
      assert String.contains?(frame, "Handoff")
    end

    test "renders split layout when width is wide" do
      frame =
        UI.render_frame(%{
          width: 120,
          height: 30,
          dc: nil,
          cluster: %{"members" => ["dev1", "dev2"], "claimant" => "dev1"},
          handoff: %{"active" => ["x"], "mode" => "standard"}
        })

      assert String.contains?(frame, "Riak TUI")
      assert String.contains?(frame, "Members: 2")
      assert String.contains?(frame, "Mode: standard")
    end
  end

  describe "GenServer rendering loop" do
    test "subscribes with custom render function and redraws on data" do
      test = self()

      {:ok, pid} =
        UI.start_link(
          name: :ui_test_pid,
          refresh_ms: 50,
          tty_size_fn: fn -> {80, 12} end,
          render_fn: fn frame -> send(test, {:frame, frame}) end,
          dc_registry: nil,
          cluster_poller: nil
        )

      assert_receive {:frame, frame}, 500
      assert is_binary(frame)
      assert String.contains?(frame, "Riak TUI")

      :ok = UI.stop(pid)
    end
  end
end

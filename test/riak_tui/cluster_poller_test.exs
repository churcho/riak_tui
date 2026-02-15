defmodule RiakTui.ClusterPollerTest do
  use ExUnit.Case

  @moduletag :integration

  @api_url Application.compile_env(:riak_tui, :bootstrap_url, "http://127.0.0.1:10015")

  describe "subscription and notification" do
    test "sends cluster_data to subscribers on poll" do
      poller_pid = start_poller!()
      GenServer.cast(poller_pid, {:subscribe, self()})

      assert_receive {:cluster_data, data}, 5_000
      assert is_map(data)
      assert Map.has_key?(data, :cluster)
      assert Map.has_key?(data, :handoff)
    end

    test "multiple subscribers all receive data" do
      poller_pid = start_poller!()
      test_pid = self()

      sub2 =
        spawn(fn ->
          receive do
            {:cluster_data, data} -> send(test_pid, {:sub2_got, data})
          end
        end)

      GenServer.cast(poller_pid, {:subscribe, self()})
      GenServer.cast(poller_pid, {:subscribe, sub2})

      assert_receive {:cluster_data, _data}, 5_000
      assert_receive {:sub2_got, _data}, 5_000
    end
  end

  describe "resilience" do
    test "keeps polling when API returns errors" do
      unique = :erlang.unique_integer([:positive])

      {:ok, pid} =
        GenServer.start_link(
          RiakTui.ClusterPoller,
          [interval: 200, api_url: "http://localhost:1", dc_registry: nil],
          name: :"poller_bad_#{unique}"
        )

      GenServer.cast(pid, {:subscribe, self()})

      # Should still receive data (with nil values) despite transport errors
      assert_receive {:cluster_data, data}, 5_000
      assert data.cluster == nil
      assert data.handoff == nil
      assert Process.alive?(pid)
    end
  end

  defp start_poller! do
    unique = :erlang.unique_integer([:positive])

    {:ok, pid} =
      GenServer.start_link(
        RiakTui.ClusterPoller,
        [interval: 500, api_url: @api_url, dc_registry: nil],
        name: :"poller_#{unique}"
      )

    pid
  end
end

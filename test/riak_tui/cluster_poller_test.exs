defmodule RiakTui.ClusterPollerTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    url = "http://127.0.0.1:#{bypass.port}"

    {:ok, %{bypass: bypass, url: url}}
  end

  describe "subscription and notification" do
    test "sends cluster_data messages to subscribers on poll", %{bypass: bypass, url: url} do
      setup_cluster_requests(bypass)
      poller_pid = start_poller!(url)
      GenServer.cast(poller_pid, {:subscribe, self()})

      assert_receive {:cluster_data, data}, 500
      assert is_map(data)
      assert %{"members" => ["dev1", "dev2"]} = data.cluster
      assert %{"active" => 1} = data.handoff
    end

    test "multiple subscribers all receive data", %{bypass: bypass, url: url} do
      setup_cluster_requests(bypass)
      poller_pid = start_poller!(url)

      sub = self()

      other_sub =
        spawn(fn ->
          assert_receive {:cluster_data, _data}, 500
          send(sub, :second_subscriber_received)
        end)

      GenServer.cast(poller_pid, {:subscribe, self()})
      GenServer.cast(poller_pid, {:subscribe, other_sub})

      assert_receive {:cluster_data, _data}, 500
      assert_receive :second_subscriber_received, 500
    end
  end

  describe "resilience" do
    test "keeps polling with nil payloads on errors" do
      {:ok, pid} =
        GenServer.start_link(
          RiakTui.ClusterPoller,
          [interval: 100, api_url: "http://localhost:1", dc_registry: nil],
          name: :"poller_bad_#{:erlang.unique_integer([:positive])}"
        )

      GenServer.cast(pid, {:subscribe, self()})
      assert_receive {:cluster_data, data}, 500
      assert data.cluster == nil
      assert data.handoff == nil
    end
  end

  defp setup_cluster_requests(bypass) do
    Bypass.expect(
      bypass,
      "GET",
      "/api/cluster/status",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"members" => ["dev1", "dev2"]}))
      end
    )

    Bypass.expect(
      bypass,
      "GET",
      "/api/handoff/status",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"active" => 1}))
      end
    )
  end

  defp start_poller!(url) do
    {:ok, pid} =
      GenServer.start_link(
        RiakTui.ClusterPoller,
        [interval: 100, api_url: url, dc_registry: nil],
        name: :"poller_#{:erlang.unique_integer([:positive])}"
      )

    pid
  end
end

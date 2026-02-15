defmodule RiakTui.ClusterPollerTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}"

    # Stub cluster status endpoint
    cluster_payload =
      Jason.encode!(%{
        cluster_name: "default",
        ring_size: 64,
        nodes: [%{name: "dev1@127.0.0.1", status: "valid"}]
      })

    Bypass.stub(bypass, "GET", "/api/cluster/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, cluster_payload)
    end)

    # Stub handoff status endpoint
    handoff_payload = Jason.encode!(%{active_transfers: [], count: 0})

    Bypass.stub(bypass, "GET", "/api/handoff/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, handoff_payload)
    end)

    {:ok, bypass: bypass, url: url}
  end

  describe "subscription and notification" do
    test "sends cluster_data to subscribers on poll", ctx do
      poller_pid = start_poller!(ctx.url)
      GenServer.cast(poller_pid, {:subscribe, self()})

      assert_receive {:cluster_data, data}, 5_000
      assert is_map(data.cluster)
      assert data.cluster["cluster_name"] == "default"
      assert data.handoff["count"] == 0
    end

    test "multiple subscribers all receive data", ctx do
      poller_pid = start_poller!(ctx.url)
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

  describe "poll failure handling" do
    test "sends nil for failed endpoints", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/cluster/status", fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      poller_pid = start_poller!(ctx.url)
      GenServer.cast(poller_pid, {:subscribe, self()})

      assert_receive {:cluster_data, data}, 5_000
      assert data.cluster == nil
      assert data.handoff["count"] == 0
    end
  end

  defp start_poller!(url) do
    unique = :erlang.unique_integer([:positive])

    {:ok, pid} =
      GenServer.start_link(
        RiakTui.ClusterPoller,
        [interval: 200, api_url: url, dc_registry: nil],
        name: :"poller_#{unique}"
      )

    pid
  end
end

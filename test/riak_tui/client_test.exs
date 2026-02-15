defmodule RiakTui.ClientTest do
  use ExUnit.Case, async: true

  alias Plug.Conn
  alias RiakTui.Client

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
  end

  describe "ping/1" do
    test "returns decoded JSON on 200", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ping", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, ~s({"node":"dev1@127.0.0.1","status":"ok"}))
      end)

      assert {:ok, %{"node" => "dev1@127.0.0.1", "status" => "ok"}} =
               Client.ping(url: url)
    end

    test "returns error tuple on non-2xx status", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ping", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(500, ~s({"error":"internal"}))
      end)

      assert {:error, {:http, 500, _body}} = Client.ping(url: url)
    end

    test "returns transport error on connection failure" do
      assert {:error, {:transport, :econnrefused}} =
               Client.ping(url: "http://localhost:1")
    end
  end

  describe "cluster_status/1" do
    test "returns decoded cluster data on 200", %{bypass: bypass, url: url} do
      body =
        Jason.encode!(%{
          cluster_name: "default",
          ring_size: 64,
          claimant: "dev1@127.0.0.1",
          nodes: [%{name: "dev1@127.0.0.1", status: "valid"}],
          ready: true
        })

      Bypass.expect_once(bypass, "GET", "/api/cluster/status", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, body)
      end)

      assert {:ok, %{"cluster_name" => "default", "ring_size" => 64}} =
               Client.cluster_status(url: url)
    end
  end

  describe "list_dcs/1" do
    test "returns decoded DCs on 200", %{bypass: bypass, url: url} do
      body = Jason.encode!(%{dcs: [%{name: "default", local: true, admin_url: "http://x"}]})

      Bypass.expect_once(bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, body)
      end)

      assert {:ok, %{"dcs" => [%{"name" => "default"}]}} =
               Client.list_dcs(url: url)
    end
  end

  describe "ring_ownership/1" do
    test "returns ring data on 200", %{bypass: bypass, url: url} do
      body = Jason.encode!(%{num_partitions: 64, partitions: []})

      Bypass.expect_once(bypass, "GET", "/api/ring/ownership", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, body)
      end)

      assert {:ok, %{"num_partitions" => 64}} = Client.ring_ownership(url: url)
    end
  end

  describe "node_stats/2" do
    test "URL-encodes the node name", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/nodes/dev1%40127.0.0.1/stats", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, ~s({"memory":1024}))
      end)

      assert {:ok, %{"memory" => 1024}} =
               Client.node_stats("dev1@127.0.0.1", url: url)
    end
  end

  describe "handoff_status/1" do
    test "returns handoff data on 200", %{bypass: bypass, url: url} do
      body = Jason.encode!(%{active_transfers: [], count: 0})

      Bypass.expect_once(bypass, "GET", "/api/handoff/status", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, body)
      end)

      assert {:ok, %{"active_transfers" => [], "count" => 0}} =
               Client.handoff_status(url: url)
    end
  end

  describe "aae_status/1" do
    test "returns AAE data on 200", %{bypass: bypass, url: url} do
      body = Jason.encode!(%{exchanges: []})

      Bypass.expect_once(bypass, "GET", "/api/aae/status", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(200, body)
      end)

      assert {:ok, %{"exchanges" => []}} = Client.aae_status(url: url)
    end
  end

  describe "error handling" do
    test "returns error on connection refused" do
      assert {:error, {:transport, :econnrefused}} =
               Client.cluster_status(url: "http://localhost:1")
    end

    test "returns http error for 404", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/cluster/status", fn conn ->
        Conn.resp(conn, 404, "")
      end)

      assert {:error, {:http, 404, _}} = Client.cluster_status(url: url)
    end

    test "returns http error for 503", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ping", fn conn ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.resp(503, ~s({"error":"unavailable"}))
      end)

      assert {:error, {:http, 503, _}} = Client.ping(url: url)
    end
  end
end

defmodule RiakTui.ClientTest do
  use ExUnit.Case, async: true

  alias RiakTui.Client

  @moduletag :unit

  setup do
    bypass = Bypass.open()
    url = "http://127.0.0.1:#{bypass.port}"

    {:ok,
     %{
       bypass: bypass,
       url: url
     }}
  end

  describe "ping/1" do
    test "returns ok with node name and status", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ping", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok", "node" => "dev1@127.0.0.1"}))
      end)

      assert {:ok, %{"status" => "ok", "node" => "dev1@127.0.0.1"}} = Client.ping(url: url)
    end
  end

  describe "cluster_status/1" do
    test "returns cluster membership payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/cluster/status", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"members" => ["dev1", "dev2"], "claimant" => "dev1"})
        )
      end)

      assert {:ok, %{"members" => members}} = Client.cluster_status(url: url)
      assert members == ["dev1", "dev2"]
    end
  end

  describe "list_dcs/1" do
    test "returns cluster discovery payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "dcs" => [
              %{
                "name" => "dc1",
                "admin_url" => "http://127.0.0.1:10015",
                "riak_url" => "http://127.0.0.1:8087",
                "local" => true
              }
            ]
          })
        )
      end)

      assert {:ok, %{"dcs" => dcs}} = Client.list_dcs(url: url)
      assert [%{"name" => "dc1"}] = dcs
    end
  end

  describe "ring_ownership/1" do
    test "returns ring payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ring/ownership", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "num_partitions" => 8,
            "partitions" => [%{"index" => 1, "node" => "dev1@127.0.0.1"}],
            "node_colors" => %{"dev1@127.0.0.1" => 0}
          })
        )
      end)

      assert {:ok, %{"num_partitions" => 8, "partitions" => partitions}} =
               Client.ring_ownership(url: url)

      assert [%{"index" => 1, "node" => "dev1@127.0.0.1"}] = partitions
    end
  end

  describe "node_stats/2" do
    test "returns node stats payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/nodes/dev1%40127.0.0.1/stats", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      assert {:ok, %{"status" => "ok"}} = Client.node_stats("dev1@127.0.0.1", url: url)
    end
  end

  describe "handoff_status/1" do
    test "returns handoff payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/handoff/status", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"active" => 0, "mode" => "standard"}))
      end)

      assert {:ok, %{"mode" => "standard"}} = Client.handoff_status(url: url)
    end
  end

  describe "aae_status/1" do
    test "returns aae payload", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/aae/status", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"status" => "ok"}))
      end)

      assert {:ok, %{"status" => "ok"}} = Client.aae_status(url: url)
    end
  end

  describe "error handling" do
    test "returns transport error when host is unreachable" do
      assert {:error, {:transport, :econnrefused}} =
               Client.ping(url: "http://localhost:1")
    end

    test "returns HTTP error for non-200 response", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/api/ping", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(503, Jason.encode!(%{"error" => "down"}))
      end)

      assert {:error, {:http, 503, %{"error" => "down"}}} = Client.ping(url: url)
    end
  end
end

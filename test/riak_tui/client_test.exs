defmodule RiakTui.ClientTest do
  use ExUnit.Case, async: true

  alias RiakTui.Client

  @moduletag :integration

  describe "ping/1" do
    test "returns ok with node name and status" do
      assert {:ok, %{"node" => node, "status" => "ok"}} = Client.ping()
      assert is_binary(node)
      assert node =~ "@"
    end
  end

  describe "ring_ownership/1" do
    test "returns partition list with node assignments" do
      assert {:ok, %{"num_partitions" => n, "partitions" => parts}} = Client.ring_ownership()
      assert is_integer(n)
      assert n > 0
      assert is_list(parts)

      first = List.first(parts)
      assert is_map(first)
      assert Map.has_key?(first, "node")
      assert Map.has_key?(first, "index")
    end

    test "includes node_colors mapping" do
      assert {:ok, %{"node_colors" => colors}} = Client.ring_ownership()
      assert is_map(colors)
      assert map_size(colors) > 0
    end
  end

  describe "cluster_status/1" do
    test "returns ok or a handled error" do
      case Client.cluster_status() do
        {:ok, body} ->
          assert is_map(body)

        {:error, {:http, status, _body}} ->
          assert is_integer(status)

        {:error, {:transport, reason}} ->
          assert is_atom(reason)
      end
    end
  end

  describe "list_dcs/1" do
    test "returns ok or a handled error" do
      case Client.list_dcs() do
        {:ok, %{"dcs" => dcs}} ->
          assert is_list(dcs)

        {:error, {:http, status, _body}} ->
          assert is_integer(status)

        {:error, {:transport, reason}} ->
          assert is_atom(reason)
      end
    end
  end

  describe "node_stats/2" do
    test "returns ok or a handled error for a known node" do
      {:ok, %{"partitions" => [first | _]}} = Client.ring_ownership()
      node_name = first["node"]

      case Client.node_stats(node_name) do
        {:ok, body} ->
          assert is_map(body)

        {:error, {:http, status, _body}} ->
          assert is_integer(status)
      end
    end
  end

  describe "handoff_status/1" do
    test "returns ok or a handled error" do
      case Client.handoff_status() do
        {:ok, body} ->
          assert is_map(body)

        {:error, {:http, status, _body}} ->
          assert is_integer(status)
      end
    end
  end

  describe "aae_status/1" do
    test "returns ok or a handled error" do
      case Client.aae_status() do
        {:ok, body} ->
          assert is_map(body)

        {:error, {:http, status, _body}} ->
          assert is_integer(status)
      end
    end
  end

  describe "error handling" do
    test "returns transport error for unreachable host" do
      assert {:error, {:transport, :econnrefused}} =
               Client.ping(url: "http://localhost:1")
    end
  end
end

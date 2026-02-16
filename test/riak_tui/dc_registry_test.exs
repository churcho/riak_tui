defmodule RiakTui.DCRegistryTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    url = "http://127.0.0.1:#{bypass.port}"

    {:ok, %{bypass: bypass, url: url}}
  end

  describe "discovery" do
    test "auto-selects the local DC on first discovery", %{bypass: bypass, url: url} do
      setup_dcs(bypass)
      pid = start_registry!(url)

      wait_until(
        fn ->
          GenServer.call(pid, :active_dc).name
        end,
        "dc1"
      )

      active = GenServer.call(pid, :active_dc)
      assert active.name == "dc1"
      assert active.admin_url == "http://127.0.0.1:10015"
    end
  end

  describe "listing" do
    test "returns discovered DCs", %{bypass: bypass, url: url} do
      setup_dcs(bypass)
      pid = start_registry!(url)
      Process.sleep(200)

      dcs = GenServer.call(pid, :list_dcs)
      assert [%{"name" => "dc1"}, %{"name" => "dc2"}] = dcs
    end
  end

  describe "switch_dc" do
    test "returns error for unknown DC", %{bypass: bypass, url: url} do
      setup_dcs(bypass)
      pid = start_registry!(url)
      Process.sleep(200)

      assert {:error, :unknown_dc} = GenServer.call(pid, {:switch_dc, "nonexistent-dc"})
    end

    test "notifies subscribers when switching", %{bypass: bypass, url: url} do
      setup_dcs(bypass)
      pid = start_registry!(url)
      Process.sleep(200)

      GenServer.cast(pid, {:subscribe, self()})
      :ok = GenServer.call(pid, {:switch_dc, "dc2"})
      assert_receive {:dc_switched, "dc2", "http://127.0.0.1:10025"}, 500
    end
  end

  describe "resilience" do
    test "survives when API is unreachable" do
      {:ok, pid} =
        GenServer.start_link(
          RiakTui.DCRegistry,
          [url: "http://localhost:1", retry_interval: 100],
          name: :"dc_unreachable_#{:erlang.unique_integer([:positive])}"
        )

      Process.sleep(200)
      assert Process.alive?(pid)
      assert GenServer.call(pid, :list_dcs) == []
    end
  end

  defp setup_dcs(bypass) do
    dcs = [
      %{
        "name" => "dc1",
        "admin_url" => "http://127.0.0.1:10015",
        "riak_url" => "http://127.0.0.1:8087",
        "local" => true
      },
      %{
        "name" => "dc2",
        "admin_url" => "http://127.0.0.1:10025",
        "riak_url" => "http://127.0.0.1:9087",
        "local" => false
      }
    ]

    Bypass.expect(bypass, "GET", "/api/dcs", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"dcs" => dcs}))
    end)
  end

  defp start_registry!(url) do
    {:ok, pid} =
      GenServer.start_link(
        RiakTui.DCRegistry,
        [
          url: url,
          discovery_interval: 100,
          retry_interval: 100
        ],
        name: :"dc_reg_#{:erlang.unique_integer([:positive])}"
      )

    pid
  end

  defp wait_until(fun, expected), do: wait_until(fun, expected, 20)

  defp wait_until(_fun, _expected, 0), do: flunk("timed out waiting for condition")

  defp wait_until(fun, expected, tries) do
    if fun.() == expected do
      :ok
    else
      Process.sleep(25)
      wait_until(fun, expected, tries - 1)
    end
  end
end

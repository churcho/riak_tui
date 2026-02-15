defmodule RiakTui.DCRegistryTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}"

    dcs_payload =
      Jason.encode!(%{
        dcs: [
          %{
            name: "dc-east",
            local: false,
            admin_url: "http://east:8099",
            riak_url: "http://east:8098"
          },
          %{
            name: "dc-west",
            local: true,
            admin_url: "http://west:8099",
            riak_url: "http://west:8098"
          }
        ]
      })

    {:ok, bypass: bypass, url: url, dcs_payload: dcs_payload}
  end

  describe "auto-selection" do
    test "auto-selects the local DC on first discovery", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ctx.dcs_payload)
      end)

      pid = start_registry!(ctx.url)

      # Give discovery time to complete
      Process.sleep(100)

      active = GenServer.call(pid, :active_dc)
      assert active.name == "dc-west"
      assert active.admin_url == "http://west:8099"
    end

    test "auto-selects first DC when none is local", ctx do
      payload =
        Jason.encode!(%{
          dcs: [
            %{
              name: "dc-alpha",
              local: false,
              admin_url: "http://a:8099",
              riak_url: "http://a:8098"
            },
            %{
              name: "dc-beta",
              local: false,
              admin_url: "http://b:8099",
              riak_url: "http://b:8098"
            }
          ]
        })

      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, payload)
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(100)

      active = GenServer.call(pid, :active_dc)
      assert active.name == "dc-alpha"
    end
  end

  describe "list_dcs" do
    test "returns all discovered DCs", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ctx.dcs_payload)
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(100)

      dcs = GenServer.call(pid, :list_dcs)
      assert length(dcs) == 2
      assert Enum.any?(dcs, &(&1["name"] == "dc-east"))
      assert Enum.any?(dcs, &(&1["name"] == "dc-west"))
    end
  end

  describe "switch_dc" do
    test "switches active DC and notifies subscribers", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ctx.dcs_payload)
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(100)

      GenServer.cast(pid, {:subscribe, self()})
      Process.sleep(50)

      assert :ok = GenServer.call(pid, {:switch_dc, "dc-east"})

      assert_receive {:dc_switched, "dc-east", "http://east:8099"}, 500

      active = GenServer.call(pid, :active_dc)
      assert active.name == "dc-east"
      assert active.admin_url == "http://east:8099"
    end

    test "returns error for unknown DC", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ctx.dcs_payload)
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(100)

      assert {:error, :unknown_dc} = GenServer.call(pid, {:switch_dc, "nonexistent"})
    end
  end

  describe "discovery failure" do
    test "retries on error without crashing", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(200)

      assert Process.alive?(pid)
      assert GenServer.call(pid, :list_dcs) == []
    end
  end

  describe "subscriber cleanup" do
    test "removes subscriber on DOWN", ctx do
      Bypass.stub(ctx.bypass, "GET", "/api/dcs", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ctx.dcs_payload)
      end)

      pid = start_registry!(ctx.url)
      Process.sleep(100)

      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      GenServer.cast(pid, {:subscribe, subscriber})
      Process.sleep(50)

      # Kill subscriber, registry should clean up
      Process.exit(subscriber, :kill)
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  # Start a registry process with a unique name to avoid conflicts between tests
  defp start_registry!(url) do
    # Use a unique name per test to avoid conflicts
    {:ok, pid} =
      GenServer.start_link(RiakTui.DCRegistry, [url: url],
        name: :"dc_reg_#{:erlang.unique_integer([:positive])}"
      )

    # Override the module-level name lookup — tests call GenServer directly
    pid
  end
end

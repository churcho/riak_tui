defmodule RiakTui.DCRegistryTest do
  use ExUnit.Case

  @moduletag :integration

  @api_url Application.compile_env(:riak_tui, :bootstrap_url, "http://127.0.0.1:10015")

  describe "discovery" do
    test "starts without crashing and populates state" do
      pid = start_registry!()
      Process.sleep(200)

      assert Process.alive?(pid)

      # Should have attempted discovery — state is either populated or empty
      # depending on whether /api/dcs is available
      dcs = GenServer.call(pid, :list_dcs)
      assert is_list(dcs)
    end

    test "active_dc returns a map with expected keys" do
      pid = start_registry!()
      Process.sleep(200)

      active = GenServer.call(pid, :active_dc)
      assert is_map(active)
      assert Map.has_key?(active, :name)
      assert Map.has_key?(active, :admin_url)
      assert Map.has_key?(active, :riak_url)
    end
  end

  describe "switch_dc" do
    test "returns error for unknown DC" do
      pid = start_registry!()
      Process.sleep(200)

      assert {:error, :unknown_dc} = GenServer.call(pid, {:switch_dc, "nonexistent-dc"})
    end
  end

  describe "subscriber notifications" do
    test "subscriber receives dc_switched when switching to a known DC" do
      pid = start_registry!()
      Process.sleep(200)

      dcs = GenServer.call(pid, :list_dcs)

      if dcs != [] do
        GenServer.cast(pid, {:subscribe, self()})
        Process.sleep(50)

        dc_name = List.first(dcs)["name"]
        :ok = GenServer.call(pid, {:switch_dc, dc_name})
        assert_receive {:dc_switched, ^dc_name, _admin_url}, 500
      end
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

      Process.sleep(300)

      assert Process.alive?(pid)
      assert GenServer.call(pid, :list_dcs) == []
    end
  end

  defp start_registry! do
    {:ok, pid} =
      GenServer.start_link(
        RiakTui.DCRegistry,
        [url: @api_url],
        name: :"dc_reg_#{:erlang.unique_integer([:positive])}"
      )

    pid
  end
end

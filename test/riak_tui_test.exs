defmodule RiakTuiTest do
  use ExUnit.Case, async: true

  test "top-level module has moduledoc" do
    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(RiakTui)
    assert doc =~ "Riak TUI"
  end
end

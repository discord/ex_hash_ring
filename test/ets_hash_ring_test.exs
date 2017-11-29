defmodule ETSHashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness

  setup_all do
    rings = for num_replicas <- Harness.replicas(), into: %{} do
      name = :"HashRingETSTest.Replicas#{num_replicas}"
      {:ok, _pid} = HashRing.ETS.start_link(name, Harness.nodes(), num_replicas)
      {num_replicas, name}
    end
    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert HashRing.ETS.find_node(rings[unquote(num_replicas)], unquote(key)) == Harness.find_node(unquote(num_replicas), unquote(key))
        end
        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert HashRing.ETS.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) == Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
        end
      end
    end
  end
end

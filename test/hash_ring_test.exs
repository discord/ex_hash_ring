defmodule HashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness

  setup_all do
    rings = for num_replicas <- Harness.replicas(), into: %{} do
      {num_replicas, HashRing.new(Harness.nodes(), num_replicas)}
    end
    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert HashRing.find_node(rings[unquote(num_replicas)], unquote(key)) == Harness.find_node(unquote(num_replicas), unquote(key))
        end
        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert HashRing.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) == Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
        end
      end
    end
  end
end

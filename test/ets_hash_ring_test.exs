defmodule ETSHashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness

  def name_for(num_replicas) do
    :"HashRingETSTest.Replicas#{num_replicas}"
  end

  setup_all do
    for num_replicas <- Harness.replicas() do
      {:ok, _pid} = HashRing.ETS.start_link(name_for(num_replicas), Harness.nodes(), num_replicas)
    end
    :ok
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}" do
          assert HashRing.ETS.find_node(name_for(unquote(num_replicas)), unquote(key)) == Harness.find_node(unquote(num_replicas), unquote(key))
        end
        test "find_nodes key=#{key} num=#{Harness.num()}" do
          assert HashRing.ETS.find_nodes(name_for(unquote(num_replicas)), unquote(key), Harness.num()) == Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
        end
      end
    end
  end
end

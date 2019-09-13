defmodule HashRingBench do
  use Benchfella
  alias ExHashRing.HashRing

  @nodes ["hash-ring-1-1", "hash-ring-1-2", "hash-ring-1-3", "hash-ring-1-4"]
  @replicas 512
  @overrides %{"1234254543" => 1}

  bench "find_node", ring: new_ring() do
    HashRing.find_node(ring, "1234254543")
    :ok
  end

  bench "find_nodes(num: 2)", ring: new_ring() do
    HashRing.find_nodes(ring, "1234254543", 2)
    :ok
  end

  bench "find_nodes(num: 3)", ring: new_ring() do
    HashRing.find_nodes(ring, "1234254543", 3)
    :ok
  end

  bench "find_node [override, match=true]", ring: new_ring(@overrides) do
    HashRing.find_node(ring, "1234254543")
    :ok
  end

  bench "find_node [override, match=false]", ring: new_ring(@overrides) do
    HashRing.find_node(ring, "1234254544")
    :ok
  end

  bench "find_nodes(num: 2) [override]", ring: new_ring(@overrides) do
    HashRing.find_nodes(ring, "1234254543", 2)
    :ok
  end

  bench "find_nodes(num: 3) [override]", ring: new_ring(@overrides) do
    HashRing.find_nodes(ring, "1234254543", 3)
    :ok
  end

  defp new_ring(overrides \\ %{}) do
    HashRing.new(@nodes, @replicas, overrides)
  end
end

defmodule ETSHashRingBench do
  use Benchfella
  alias ExHashRing.HashRing.ETS, as: Ring

  @name HashRingBench.ETSRing
  @nodes ["hash-ring-1-1", "hash-ring-1-2", "hash-ring-1-3", "hash-ring-1-4"]
  @replicas 512
  @overrides %{"1234254543" => 1}

  setup_all do
    Ring.Config.start_link()
    {:ok, nil}
  end

  after_each_bench _ do
    GenServer.stop(@name)
  end

  bench "find_node", ring: new_ring() do
    Ring.find_node(ring, "1234254543")
    :ok
  end

  bench "find_nodes(num: 2)", ring: new_ring() do
    Ring.find_nodes(ring, "1234254543", 2)
    :ok
  end

  bench "find_nodes(num: 3)", ring: new_ring() do
    Ring.find_nodes(ring, "1234254543", 3)
    :ok
  end

  bench "find_node [override, match=true]", ring: new_ring(@overrides) do
    Ring.find_node(ring, "1234254543")
    :ok
  end

  bench "find_nodes(num: 2) [override, match=true]", ring: new_ring(@overrides) do
    Ring.find_nodes(ring, "1234254543", 2)
    :ok
  end

  bench "find_nodes(num: 3) [override, match=true]", ring: new_ring(@overrides) do
    Ring.find_nodes(ring, "1234254543", 3)
    :ok
  end

  bench "find_node [override, match=false]", ring: new_ring(@overrides) do
    Ring.find_node(ring, "0")
    :ok
  end

  bench "find_nodes(num: 2) [override, match=false]", ring: new_ring(@overrides) do
    Ring.find_nodes(ring, "0", 2)
    :ok
  end

  bench "find_nodes(num: 3) [override, match=false]", ring: new_ring(@overrides) do
    Ring.find_nodes(ring, "0", 3)
    :ok
  end

  bench "regenerate ring & gc", ring: new_ring() do
    Ring.set_nodes(ring, @nodes)
    Ring.force_gc(ring)
    nil
  end

  defp new_ring(overrides \\ %{}) do
    {:ok, _} =
      Ring.start_link(@name,
        nodes: @nodes,
        num_replicas: @replicas,
        overrides: overrides,
        named: true
      )

    @name
  end
end

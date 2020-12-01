defmodule ExHashRing.Ring.Benchmark do
  use Benchfella
  alias ExHashRing.{Info, Ring}

  @name ExHashRing.Ring.Benchmark.Ring
  @nodes ["hash-ring-1-1", "hash-ring-1-2", "hash-ring-1-3", "hash-ring-1-4"]
  @replicas 512
  @overrides %{"1234254543" => [1]}

  setup_all do
    Info.start_link()
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

  bench "find_stable_nodes(num: 2)", ring: new_ring_with_previous(@overrides) do
    Ring.find_stable_nodes(ring, "0", 2)
    :ok
  end

  bench "find_stable_nodes(num: 3)", ring: new_ring_with_previous(@overrides) do
    Ring.find_stable_nodes(ring, "0", 3)
    :ok
  end

  bench "find_stable_nodes(num: 2, depth: 2)", ring: new_ring_with_previous(@overrides) do
    Ring.find_stable_nodes(ring, "0", 2, 2)
  end

  bench "find_stable_nodes(num: 3, depth: 2)", ring: new_ring_with_previous(@overrides) do
    Ring.find_stable_nodes(ring, "0", 3, 2)
  end

  bench "regenerate ring & gc", ring: new_ring() do
    Ring.set_nodes(ring, @nodes)
    Ring.force_gc(ring)
    nil
  end

  defp new_ring(overrides \\ %{}) do
    {:ok, _} =
      Ring.start_link(@name,
        named: true,
        nodes: @nodes,
        overrides: overrides,
        replicas: @replicas
      )

    @name
  end

  defp new_ring_with_previous(overrides \\ %{}) do
    original_nodes = Enum.slice(@nodes, 0, 2)

    {:ok, _} =
      Ring.start_link(@name,
        depth: 2,
        named: true,
        nodes: original_nodes,
        replicas: @replicas,
        overrides: overrides
      )

    Ring.set_nodes(@name, @nodes)

    @name
  end
end

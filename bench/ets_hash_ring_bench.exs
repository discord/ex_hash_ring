defmodule ETSHashRingBench do
  use Benchfella
  alias ExHashRing.HashRing.ETS, as: Ring


  @nodes [
    "hash-ring-1-1",
    "hash-ring-1-2",
    "hash-ring-1-3",
    "hash-ring-1-4",
  ]
  @replicas 512
  @name HashRingBench.ETSRing

  setup_all do
    Ring.Config.start_link()
    {:ok, nil}
  end

  before_each_bench _ do
    {:ok, _pid} = Ring.start_link(@name, nodes: @nodes, num_replicas: @replicas, named: true)
    {:ok, @name}
  end

  after_each_bench _ do
    GenServer.stop(@name)
  end

  bench "find node" do
    Ring.find_node(bench_context, "1234254543")
    :ok
  end

  bench "find nodes (1)" do
    Ring.find_nodes(bench_context, "1234254543", 2)
    :ok
  end

  bench "find nodes (2)" do
    Ring.find_nodes(bench_context, "1234254543", 3)
    :ok
  end

  bench "regenerate ring & gc" do
    Ring.set_nodes(bench_context, @nodes)
    Ring.force_gc(bench_context)
    nil
  end
end

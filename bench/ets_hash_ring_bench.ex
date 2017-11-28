defmodule ETSHashRingBench do
  use Benchfella

  @nodes [
    "hash-ring-1-1",
    "hash-ring-1-2",
    "hash-ring-1-3",
    "hash-ring-1-4",
  ]
  @replicas 512
  @name HashRingBench.ETSRing

  before_each_bench _ do
    {:ok, _pid} = HashRing.ETS.start_link(@name, @nodes, @replicas)
    {:ok, @name}
  end

  after_each_bench _ do
    GenServer.stop(@name)
  end

  bench "find node" do
    HashRing.ETS.find_node(bench_context, "1234254543")
    :ok
  end

  bench "find nodes (1)" do
    HashRing.ETS.find_nodes(bench_context, "1234254543", 2)
    :ok
  end

  bench "find nodes (2)" do
    HashRing.ETS.find_nodes(bench_context, "1234254543", 3)
    :ok
  end
end

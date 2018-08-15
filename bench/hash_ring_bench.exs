defmodule HashRingBench do
  use Benchfella
  alias ExHashRing.HashRing

  @nodes [
    "hash-ring-1-1",
    "hash-ring-1-2",
    "hash-ring-1-3",
    "hash-ring-1-4",
  ]
  @replicas 512

  before_each_bench _ do
    {:ok, HashRing.new(@nodes, @replicas)}
  end

  bench "find node" do
    HashRing.find_node(bench_context, "1234254543")
    :ok
  end

  bench "find nodes (1)" do
    HashRing.find_nodes(bench_context, "1234254543", 2)
    :ok
  end

  bench "find nodes (2)" do
    HashRing.find_nodes(bench_context, "1234254543", 3)
    :ok
  end
end

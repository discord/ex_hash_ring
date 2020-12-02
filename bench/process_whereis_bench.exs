defmodule ExHashRing.Process.Whereis.Benchmark do
  use Benchfella


  setup_all do
    Process.register(self(), :benchmark)
    {:ok, nil}
  end

  bench "unknown name" do
    Process.whereis(:unknown)
  end

  bench "known name" do
    Process.whereis(:benchmark)
  end
end

defmodule HashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness
  alias ExHashRing.HashRing

  setup_all do
    rings =
      for num_replicas <- Harness.replicas(), into: %{} do
        {num_replicas, HashRing.new(Harness.nodes(), num_replicas)}
      end

    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert HashRing.find_node(rings[unquote(num_replicas)], unquote(key)) ==
                   Harness.find_node(unquote(num_replicas), unquote(key))
        end

        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert HashRing.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) ==
                   Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
        end
      end
    end
  end
end

defmodule HashRingOverrideTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness
  alias ExHashRing.HashRing

  @harness_overrides Enum.take(Harness.keys(), 5)
  @custom_overrides ["override_string", :override_atom, 123]
  @override_test_keys @custom_overrides ++ @harness_overrides
  @override_map @override_test_keys |> Enum.map(&{&1, "#{&1} (override)"}) |> Map.new()

  setup_all do
    rings =
      for num_replicas <- Harness.replicas(), into: %{} do
        ring = HashRing.new(Harness.nodes(), num_replicas)
        {:ok, ring} = HashRing.set_overrides(ring, @override_map)

        {num_replicas, ring}
      end

    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "hash ring, replicas=#{num_replicas} overrides=true" do
      for key <- Harness.keys() do
        test "find_node key=#{key} overrides=true", %{rings: rings} do
          found = HashRing.find_node(rings[unquote(num_replicas)], unquote(key))
          override = Map.get(@override_map, unquote(key))
          harness = Harness.find_node(unquote(num_replicas), unquote(key))

          assert found == override || harness
        end

        test "find_nodes key=#{key} num=#{Harness.num()} overrides=true", %{rings: rings} do
          found = HashRing.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num())
          harness = Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
          override = [Map.get(@override_map, unquote(key))]

          expected =
            (override ++ harness)
            |> Enum.filter(& &1)
            |> Enum.take(Harness.num())

          assert found == expected
        end
      end
    end
  end
end

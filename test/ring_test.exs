defmodule ExHashRing.Ring.FindNode.Test do
  use ExUnit.Case

  alias ExHashRing.Ring
  alias ExHashRing.Support.Harness


  setup_all do
    rings =
      for replicas <- Harness.replicas(), into: %{} do
        name = :"ExHashRing.Ring.FindNode.Test.Replicas.#{replicas}"

        {:ok, _pid} =
          Ring.start_link(name,
            named: true,
            nodes: Harness.nodes(),
            replicas: replicas
          )

        {replicas, name}
      end

    {:ok, rings: rings}
  end

  for replicas <- Harness.replicas() do
    describe "Ring with #{replicas} replicas" do
      for key <- Harness.keys() do
        test "find_node/2(key=#{key})", %{rings: rings} do
          assert Ring.find_node(rings[unquote(replicas)], unquote(key)) ==
                   {:ok, Harness.find_node(unquote(replicas), unquote(key))}
        end

        test "find_nodes/3(key=#{key}, num=#{Harness.num()})", %{rings: rings} do
          assert Ring.find_nodes(rings[unquote(replicas)], unquote(key), Harness.num()) ==
                   {:ok, Harness.find_nodes(unquote(replicas), unquote(key), Harness.num())}
        end
      end
    end
  end
end

defmodule ExHashRing.Ring.Overrides.Test do
  use ExUnit.Case

  alias ExHashRing.Ring
  alias ExHashRing.Support.Harness

  @custom_overrides ["override_string", :override_atom, 123]
  @harness_single_overrides Harness.keys() |> Enum.take(5)
  @harness_multi_overrides Harness.keys() |> Enum.drop(5) |> Enum.take(5)

  @single_overrides (@custom_overrides ++ @harness_single_overrides)
                    |> Enum.map(&{&1, ["#{&1} (override)"]})
  @multi_overrides @harness_multi_overrides
                   |> Enum.map(&{&1, ["#{&1} (override-1)", "#{&1} (override-2)"]})

  @override_map Map.new([@single_overrides ++ @multi_overrides] |> List.flatten())

  setup_all do
    rings =
      for replicas <- Harness.replicas(), into: %{} do
        name = :"ExHashRing.Ring.Overrides.Test.Replicas.#{replicas}"

        {:ok, _pid} =
          Ring.start_link(name,
            named: true,
            nodes: Harness.nodes(),
            replicas: replicas
          )

        Ring.set_overrides(name, @override_map)

        {replicas, name}
      end

    {:ok, rings: rings}
  end

  for replicas <- Harness.replicas() do
    describe "Ring with #{replicas} replicas and overrides" do
      for key <- Harness.keys() do
        test "find_node/2(key=#{key})", %{rings: rings} do
          found = Ring.find_node(rings[unquote(replicas)], unquote(key))

          expected =
            Map.get(
              @override_map,
              unquote(key),
              [Harness.find_node(unquote(replicas), unquote(key))]
            )

          assert found == {:ok, hd(expected)}
        end

        test "find_nodes/3(key=#{key} num=#{Harness.num()})", %{rings: rings} do
          found = Ring.find_nodes(rings[unquote(replicas)], unquote(key), Harness.num())
          harness = Harness.find_nodes(unquote(replicas), unquote(key), Harness.num())
          overrides = [Map.get(@override_map, unquote(key))]

          expected =
            (overrides ++ harness)
            |> List.flatten()
            |> Enum.filter(& &1)
            |> Enum.take(Harness.num())

          assert found == {:ok, expected}
        end
      end
    end
  end
end

defmodule ExHashRing.Ring.Operations.Test do
  use ExUnit.Case

  alias ExHashRing.{Config, Ring, Settings}

  @nodes ["a", "b", "c"]

  setup do
    name = :"ExHashRing.Ring.Operations.Test.#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Ring.start_link(name, nodes: @nodes, named: true)

    [name: name]
  end

  describe "get_nodes/1" do
    test "returns the nodes the ring was constructed with", %{name: name} do
      {:ok, nodes} = Ring.get_nodes(name)
      assert nodes == @nodes
    end
  end

  describe "set_nodes/2 with default replicas" do
    test "returns the new set of nodes", %{name: name} do
      new_nodes = ["d", "e", "f"]
      new_nodes_with_replicas = for node <- new_nodes, do: {node, Settings.get_replicas()}

      assert {:ok, ^new_nodes_with_replicas} = Ring.set_nodes(name, new_nodes)
    end

    test "has only the new nodes after set", %{name: name} do
      new_nodes = ["d", "e", "f"]

      {:ok, _} = Ring.set_nodes(name, new_nodes)

      assert {:ok, ^new_nodes} = Ring.get_nodes(name)
    end

    test "has new nodes with default replicas after set", %{name: name} do
      new_nodes = ["d", "e", "f"]
      new_nodes_with_replicas = for node <- new_nodes, do: {node, Settings.get_replicas()}

      {:ok, _} = Ring.set_nodes(name, new_nodes)

      assert {:ok, ^new_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    end

    test "causes a new generation", %{name: name} do
      new_nodes = ["d", "e", "f"]

      {:ok, before_set_generation} = Ring.get_generation(name)

      {:ok, _} = Ring.set_nodes(name, new_nodes)

      {:ok, after_set_generation} = Ring.get_generation(name)

      assert after_set_generation == before_set_generation + 1
    end

    test "finding a node resolves to one of the new nodes", %{name: name} do
      new_nodes = ["d", "e", "f"]

      {:ok, _} = Ring.set_nodes(name, new_nodes)

      {:ok, node_name} = Ring.find_node(name, 1)
      assert node_name in new_nodes
    end
  end

  describe "set_nodes/2 with custom replicas" do
    test "returns the new set of nodes", %{name: name} do
      new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

      assert {:ok, ^new_nodes_with_replicas} = Ring.set_nodes(name, new_nodes_with_replicas)
    end

    test "has only the new nodes after set", %{name: name} do
      new_nodes = ["d", "e", "f"]
      new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

      {:ok, _} = Ring.set_nodes(name, new_nodes_with_replicas)

      assert {:ok, ^new_nodes} = Ring.get_nodes(name)
    end

    test "has new nodes with default replicas after set", %{name: name} do
      new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

      {:ok, _} = Ring.set_nodes(name, new_nodes_with_replicas)

      assert {:ok, ^new_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    end

    test "causes a new generation", %{name: name} do
      new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

      {:ok, before_set_generation} = Ring.get_generation(name)

      {:ok, _} = Ring.set_nodes(name, new_nodes_with_replicas)

      {:ok, after_set_generation} = Ring.get_generation(name)

      assert after_set_generation == before_set_generation + 1
    end

    test "finding a node resolves to one of the new nodes", %{name: name} do
      new_nodes = ["d", "e", "f"]
      new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

      {:ok, _} = Ring.set_nodes(name, new_nodes_with_replicas)

      {:ok, node_name} = Ring.find_node(name, 1)
      assert node_name in new_nodes
    end
  end

  describe "add_node/2" do
    test "name only", %{name: name} do
      expected_nodes = ["d" | @nodes]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      {:ok, _} = Ring.add_node(name, "d")
      {:ok, ^expected_nodes} = Ring.get_nodes(name)
      {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
      # Select a node that should now be c.
      assert Ring.get_generation(name) == {:ok, 2}
      assert Ring.find_node(name, 1) == {:ok, "c"}
    end

    test "name with custom replicas", %{name: name} do
      expected_nodes = ["d" | @nodes]
      expected_nodes_with_replicas = for node <- @nodes, do: {node, Settings.get_replicas()}
      expected_nodes_with_replicas = [{"d", 200} | expected_nodes_with_replicas]

      {:ok, ^expected_nodes_with_replicas} = Ring.add_node(name, "d", 200)
      {:ok, ^expected_nodes} = Ring.get_nodes(name)
      {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
      # Select a node that should now be c.
      assert Ring.get_generation(name) == {:ok, 2}
      assert Ring.find_node(name, 1) == {:ok, "c"}
    end
  end

  describe "add_nodes/2" do
    test "without replicas", %{name: name} do
      expected_nodes = ["d", "e"] ++ @nodes
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      {:ok, previous_generation} = Ring.get_generation(name)

      assert {:ok, ^expected_nodes_with_replicas} = Ring.add_nodes(name, ["d", "e"])
      assert {:ok, ^expected_nodes} = Ring.get_nodes(name)
      assert {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)

      {:ok, current_generation} = Ring.get_generation(name)

      assert current_generation == previous_generation + 1
    end

    test "with replicas", %{name: name} do
      expected_nodes = ["d", "e"] ++ @nodes
      expected_nodes_with_replicas = for node <- @nodes, do: {node, Settings.get_replicas()}
      expected_nodes_with_replicas = [{"d", 100}, {"e", 100}] ++ expected_nodes_with_replicas

      {:ok, previous_generation} = Ring.get_generation(name)

      assert {:ok, ^expected_nodes_with_replicas} = Ring.add_nodes(name, [{"d", 100}, {"e", 100}])
      assert {:ok, ^expected_nodes} = Ring.get_nodes(name)
      assert {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)

      {:ok, current_generation} = Ring.get_generation(name)

      assert current_generation == previous_generation + 1
    end

    test "mixed with and without replicas", %{name: name} do
      expected_nodes = ["d", "e"] ++ @nodes
      expected_nodes_with_replicas = for node <- @nodes, do: {node, Settings.get_replicas()}
      expected_nodes_with_replicas = [{"d", Settings.get_replicas()}, {"e", 100}] ++ expected_nodes_with_replicas

      {:ok, previous_generation} = Ring.get_generation(name)

      assert {:ok, ^expected_nodes_with_replicas} = Ring.add_nodes(name, ["d", {"e", 100}])
      assert {:ok, ^expected_nodes} = Ring.get_nodes(name)
      assert {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)

      {:ok, current_generation} = Ring.get_generation(name)

      assert current_generation == previous_generation + 1
    end

    test "error to add nodes that already exist", %{name: name} do
      assert {:error, :node_exists} == Ring.add_nodes(name, ["a", "b"])
    end

    test "error to add mixed new nodes with those that already exist", %{name: name} do
      assert {:error, :node_exists} == Ring.add_nodes(name, ["new", "a"])
    end
  end

  describe "remove_node/2" do
    test "returns the retained nodes", %{name: name} do
      expected_nodes = @nodes -- ["c"]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      {:ok, ^expected_nodes_with_replicas} = Ring.remove_node(name, "c")
    end

    test "has only the retained nodes after removal", %{name: name} do
      expected_nodes = @nodes -- ["c"]

      {:ok, _} = Ring.remove_node(name, "c")

      assert {:ok, ^expected_nodes} = Ring.get_nodes(name)
    end

    test "retained nodes have the expected number of replicas", %{name: name} do
      expected_nodes = @nodes -- ["c"]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      {:ok, _} = Ring.remove_node(name, "c")

      assert {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    end

    test "increments the generation", %{name: name} do
      {:ok, before_remove_generation} = Ring.get_generation(name)

      {:ok, _} = Ring.remove_node(name, "c")

      {:ok, after_remove_generation} = Ring.get_generation(name)

      assert after_remove_generation == before_remove_generation + 1
    end

    test "remove node", %{name: name} do
      expected_nodes = @nodes -- ["c"]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}
      {:ok, _} = Ring.remove_node(name, "c")
      {:ok, ^expected_nodes} = Ring.get_nodes(name)
      {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
      # Select a node that should now be b.
      assert Ring.get_generation(name) == {:ok, 2}
      assert Ring.find_node(name, 1) == {:ok, "b"}
    end

    test "target resolves to secondary after primary removed", %{name: name} do
      {:ok, [primary, secondary]} = Ring.find_nodes(name, 1, 2)

      {:ok, _} = Ring.remove_node(name, primary)

      assert Ring.find_node(name, 1) == {:ok, secondary}
    end

    test "error to remove unknown node", %{name: name} do
      assert {:error, :node_not_exists} ==  Ring.remove_node(name, "unknown")
    end
  end

  describe "remove_nodes/2" do
    test "returns the retained nodes", %{name: name} do
      expected_nodes = @nodes -- ["b", "c"]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      assert {:ok, ^expected_nodes_with_replicas} = Ring.remove_nodes(name, ["b", "c"])
    end

    test "has only the retained nodes after removal", %{name: name} do
      expected_nodes = @nodes -- ["b", "c"]

      {:ok, _} = Ring.remove_nodes(name, ["b", "c"])

      assert {:ok, ^expected_nodes} = Ring.get_nodes(name)
    end

    test "retained nodes have the expected replicas", %{name: name} do
      expected_nodes = @nodes -- ["b", "c"]
      expected_nodes_with_replicas = for node <- expected_nodes, do: {node, Settings.get_replicas()}

      {:ok, _} = Ring.remove_nodes(name, ["b", "c"])

      assert {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    end

    test "only increments the generation by one", %{name: name} do
      {:ok, before_remove_generation} = Ring.get_generation(name)
      {:ok, _} = Ring.remove_nodes(name, ["b", "c"])
      {:ok, after_remove_generation} = Ring.get_generation(name)

      assert after_remove_generation == before_remove_generation + 1
    end

    test "targets resolve correctly after removal", %{name: name} do
      {:ok, targets} = Ring.find_nodes(name, 1, 2)

      {:ok, [{expected_node, _}]} = Ring.remove_nodes(name, targets)

      assert Ring.find_node(name, 1) == {:ok, expected_node}
    end

    test "error to remove unknown nodes", %{name: name} do
      assert {:error, :node_not_exists} == Ring.remove_nodes(name, ["unknown-1", "unknown-2"])
    end

    test "error to remove mixed known and unknown nodes", %{name: name} do
      assert {:error, :node_not_exists} == Ring.remove_nodes(name, ["a", "unknown"])
    end
  end

  test "set overrides", %{name: name} do
    new_overrides = %{
      "1" => [1],
      :a => [2, 3],
      3 => [3, 4, 5]
    }

    {:ok, current_generation} = Ring.get_generation(name)

    {:ok, ^new_overrides} = Ring.set_overrides(name, new_overrides)
    {:ok, ^new_overrides} = Ring.get_overrides(name)

    # assert that changing the overrides does not require a new generation in the ring
    assert Ring.get_generation(name) == {:ok, current_generation}

    Enum.each(new_overrides, fn {key, value} ->
      # assert that a full lookup returns the correct.
      assert {:ok, value} == Ring.find_nodes(name, key, length(value))

      # assert that a lookup of the first half of these items returns the correct half.
      half =
        Enum.take(
          value,
          # Kernel.ceil is not availble in Elixir 1.7.
          Float.ceil(length(value) / 2) |> trunc()
        )

      assert {:ok, half} == Ring.find_nodes(name, key, length(half))
    end)
  end

  test "no initial overrides", %{name: name} do
    {:ok, overrides} = Ring.get_overrides(name)

    assert map_size(overrides) == 0
  end

  test "ets config will remove config", %{name: name} do
    refute Config.get(name) == {:error, :no_ring}
    assert Ring.stop(name) == :ok
    assert await(fn -> Config.get(name) == {:error, :no_ring} end)
  end

  test "ring gen gc happens", %{name: name} do
    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_generation(name) == {:ok, 2}

    assert Ring.force_gc(name, 1) == :ok
    assert Ring.force_gc(name, 1) == {:error, :not_pending}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert count_generation_entries(name, 1) == 0
    assert ring_ets_table_size(name) == 1024
  end

  test "ring gen gc all", %{name: name} do
    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_generation(name) == {:ok, 2}

    assert Ring.force_gc(name) == {:ok, [0, 1]}
    assert Ring.force_gc(name) == {:ok, []}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert count_generation_entries(name, 1) == 0
    assert ring_ets_table_size(name) == 1024
  end

  test "automatic ring gc", %{name: name} do
    Settings.put_gc_delay(50)
    on_exit(fn -> Settings.clear_gc_delay() end)

    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_generation(name) == {:ok, 2}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert await(fn -> count_generation_entries(name, 1) == 0 end)
    assert Ring.force_gc(name, 1) == {:error, :not_pending}
    assert ring_ets_table_size(name) == 1024
  end

  test "operations on nonexistent ring fail" do
    assert Ring.find_node(HashRingEtsTest.DoesNotExist, 1) == {:error, :no_ring}
    assert Ring.find_nodes(HashRingEtsTest.DoesNotExist, 1, 2) == {:error, :no_ring}
  end

  test "ExHashRing.HashRing.ETS.start_link/1" do
    {:ok, _pid} = Ring.start_link(TestModule.Foo, nodes: @nodes)
    assert Ring.find_node(TestModule.Foo, 1) == {:ok, "c"}
    assert Process.whereis(TestModule.Foo) == nil
  end

  test "operations on empty ring fail" do
    {:ok, _pid} = Ring.start_link(HashRingETSTest.Empty, nodes: [])
    assert Ring.find_node(HashRingETSTest.Empty, 1) == {:error, :invalid_ring}
    assert Ring.find_nodes(HashRingETSTest.Empty, 1, 2) == {:error, :invalid_ring}
  end

  test "find_historical_nodes" do
    name = HashRingETSTest.Previous

    {:ok, _pid} = Ring.start_link(name, depth: 2, nodes: @nodes, named: true)

    {:ok, previous_generation} = Ring.get_generation(name)

    # Find primary and secondary for the currrent configuration
    {:ok, [original_primary, original_secondary]} = Ring.find_nodes(name, 1, 2)

    # Add multiple new nodes to the ring
    {:ok, _} = Ring.add_nodes(name, ["d", "e", "f", "g", "h", "i", "j", "k"])

    {:ok, current_generation} = Ring.get_generation(name)

    # Adding nodes atomically should increment the generation by 1
    assert current_generation == previous_generation + 1

    # Find primary and secondary for the new configuration
    {:ok, [new_primary, new_secondary]} = Ring.find_nodes(name, 1, 2)

    # Assert that the new configuration assigns different nodes to the target
    assert original_primary != new_primary
    assert original_secondary != new_secondary

    {:ok, [previous_primary, previous_secondary]} = Ring.find_historical_nodes(name, 1, 2, 1)

    # Assert that the new configuration's previous generation can be queried
    assert original_primary == previous_primary
    assert original_secondary == previous_secondary
  end

  describe "find_stable_nodes/3" do
    test "resolves expected nodes when depth 2" do
      name = ExHashRing.Ring.Test.Stable

      {:ok, _pid} = Ring.start_link(name, depth: 2, nodes: @nodes, named: true)

      {:ok, first_generation} = Ring.get_generation(name)

      # Find primary and secondary for the currrent configuration
      {:ok, [first_primary, first_secondary]} = Ring.find_nodes(name, 1, 2)

      # Add multiple new nodes to the ring
      {:ok, _} = Ring.add_nodes(name, ["d", "e", "f", "g", "h", "i", "j", "k"])

      {:ok, second_generation} = Ring.get_generation(name)

      # Adding nodes atomically should increment the generation by 1
      assert second_generation == first_generation + 1

      # Find primary and secondary for the new configuration
      {:ok, [second_primary, second_secondary]} = Ring.find_nodes(name, 1, 2)

      # Assert that the new configuration assigns different nodes to the target
      assert first_primary != second_primary
      assert first_secondary != second_secondary

      {:ok, stable_nodes} = Ring.find_stable_nodes(name, 1, 2)

      # Assert that both the first and second generation's nodes are in the stable_nodes
      assert first_primary in stable_nodes
      assert second_primary in stable_nodes
      assert first_secondary in stable_nodes
      assert second_secondary in stable_nodes

      # Assert that no other nodes are returned than the first and second generation's nodes
      assert stable_nodes -- [first_primary, second_primary, first_secondary, second_secondary] == []

      # Assert that the newest primary is at the head of the stable nodes
      assert second_primary == hd(stable_nodes)
    end

    test "resolves expected nodes when depth 3" do
      name = ExHashRing.Ring.Test.Stable

      {:ok, _pid} = Ring.start_link(name, depth: 3, nodes: @nodes, named: true)

      {:ok, first_generation} = Ring.get_generation(name)

      # Find primary and secondary for the currrent configuration
      {:ok, [first_primary, first_secondary]} = Ring.find_nodes(name, 1, 2)

      # Add multiple new nodes to the ring
      {:ok, _} = Ring.add_nodes(name, ["d", "e", "f", "g", "h", "i", "j", "k"])

      {:ok, second_generation} = Ring.get_generation(name)

      # Adding nodes atomically should increment the generation by 1
      assert second_generation == first_generation + 1

      # Find primary and secondary for the new configuration
      {:ok, [second_primary, second_secondary]} = Ring.find_nodes(name, 1, 2)

      # Assert that the new configuration assigns different nodes to the target
      assert first_primary != second_primary
      assert first_secondary != second_secondary

      # Add multiple new nodes to the ring
      {:ok, _} = Ring.add_nodes(name, ["l", "m", "n", "o", "p", "q", "r", "s"])

      {:ok, third_generation} = Ring.get_generation(name)

      # Adding nodes atomically should increment the generation by 1
      assert third_generation == second_generation + 1

      # Find primary and secondary for the new configuration
      {:ok, [third_primary, third_secondary]} = Ring.find_nodes(name, 1, 2)

      # Assert that the new configuration assigns different nodes to the target
      assert third_primary != second_primary
      assert third_secondary != second_secondary

      {:ok, stable_nodes} = Ring.find_stable_nodes(name, 1, 2)

      # Assert that the first, second, and third generation's nodes are in the stable_nodes
      assert first_primary in stable_nodes
      assert second_primary in stable_nodes
      assert third_primary in stable_nodes
      assert first_secondary in stable_nodes
      assert second_secondary in stable_nodes
      assert third_secondary in stable_nodes

      # Assert that no other nodes are returned than the first, second, and third generation's nodes
      assert stable_nodes -- [first_primary, second_primary, third_primary, first_secondary, second_secondary, third_secondary] == []

      # Assert that the newest primary is at the head of the stable nodes
      assert third_primary == hd(stable_nodes)
    end

    test "order is newest generation to oldest generation preserving the order of those generations" do
      name = ExHashRing.Ring.Test.Stable

      first_generation_nodes = Enum.map(1..100, &"node-#{&1}")
      second_generation_nodes = Enum.map(101..200, &"node-#{&1}")
      third_generation_nodes = Enum.map(201..300, &"node-#{&1}")

      {:ok, _pid} = Ring.start_link(name, depth: 3, nodes: first_generation_nodes, named: true)

      {:ok, first_nodes} = Ring.find_nodes(name, 1, 3)

      # Create the second generation
      {:ok, _} = Ring.add_nodes(name, second_generation_nodes)

      {:ok, second_nodes} = Ring.find_nodes(name, 1, 3)

      # Create the third generation
      {:ok, _} = Ring.add_nodes(name, third_generation_nodes)

      {:ok, third_nodes} = Ring.find_nodes(name, 1, 3)

      expected = Enum.uniq(third_nodes ++ second_nodes ++ first_nodes)

      {:ok, stable_nodes} = Ring.find_stable_nodes(name, 1, 3, 3)

      assert expected == stable_nodes
    end
  end



  defp count_generation_entries(name, generation) do
    {:ok, {table, _depth, _sizes, _genertion, _overrids}} = Config.get(name)

    table
    |> :ets.tab2list()
    |> Enum.filter(fn
      {{^generation, _}, _} ->
        true

      _ ->
        false
    end)
    |> Enum.count()
  end

  defp ring_ets_table_size(name) do
    {:ok, {table, _depth, _sizes, _generation, _overrides}} = Config.get(name)
    :ets.info(table, :size)
  end

  defp await(callback), do: await(callback, 50)

  defp await(_callback, 0) do
    false
  end

  defp await(callback, attempts) do
    if callback.() do
      true
    else
      Process.sleep(50)
      await(callback, attempts - 1)
    end
  end
end

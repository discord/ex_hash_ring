defmodule ETSHashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness
  alias ExHashRing.HashRing.ETS, as: Ring

  setup_all do
    rings =
      for num_replicas <- Harness.replicas(), into: %{} do
        name = :"ETSHashRingTest.Replicas#{num_replicas}"

        {:ok, _pid} =
          Ring.start_link(name,
            nodes: Harness.nodes(),
            default_num_replicas: num_replicas,
            named: true
          )

        {num_replicas, name}
      end

    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert Ring.find_node(rings[unquote(num_replicas)], unquote(key)) ==
                   {:ok, Harness.find_node(unquote(num_replicas), unquote(key))}
        end

        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert Ring.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) ==
                   {:ok, Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())}
        end
      end
    end
  end
end

defmodule ETSHashRingOverrideTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness
  alias ExHashRing.HashRing.ETS, as: Ring

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
      for num_replicas <- Harness.replicas(), into: %{} do
        name = :"ETSHashRingOverrideTest.Replicas#{num_replicas}"

        {:ok, _pid} =
          Ring.start_link(name,
            nodes: Harness.nodes(),
            default_num_replicas: num_replicas,
            named: true
          )

        Ring.set_overrides(name, @override_map)

        {num_replicas, name}
      end

    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas} overrides=true" do
      for key <- Harness.keys() do
        test "find_node key=#{key} overrides=true", %{rings: rings} do
          found = Ring.find_node(rings[unquote(num_replicas)], unquote(key))

          expected =
            Map.get(
              @override_map,
              unquote(key),
              [Harness.find_node(unquote(num_replicas), unquote(key))]
            )

          assert found == {:ok, hd(expected)}
        end

        test "find_nodes key=#{key} num=#{Harness.num()} overrides=true", %{rings: rings} do
          found = Ring.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num())
          harness = Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
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

defmodule ETSHashRingOperationsTest do
  use ExUnit.Case
  alias ExHashRing.HashRing.ETS, as: Ring

  @default_num_replicas 512
  @nodes ["a", "b", "c"]

  setup do
    name = :"HashRingEtsTest#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Ring.start_link(name, nodes: @nodes, named: true)

    [name: name]
  end

  test "construct with nodes", %{name: name} do
    {:ok, nodes} = Ring.get_nodes(name)
    assert nodes == @nodes
  end

  test "set nodes", %{name: name} do
    new_nodes = ["d", "e", "f"]
    new_nodes_with_replicas = for node <- new_nodes, do: {node, @default_num_replicas}
    {:ok, _} = Ring.set_nodes(name, new_nodes)
    {:ok, ^new_nodes} = Ring.get_nodes(name)
    {:ok, ^new_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)

    # Assert that the ring is also re-generated at this point.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    {:ok, node_name} = Ring.find_node(name, 1)
    assert node_name in new_nodes
  end

  test "set nodes with replicas", %{name: name} do
    new_nodes = ["d", "e", "f"]
    new_nodes_with_replicas = [{"d", 512}, {"e", 200}, {"f", 512}]

    {:ok, _} = Ring.set_nodes(name, new_nodes_with_replicas)
    {:ok, ^new_nodes} = Ring.get_nodes(name)
    {:ok, ^new_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)

    # Assert that the ring is also re-generated at this point.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    {:ok, node_name} = Ring.find_node(name, 1)
    assert node_name in new_nodes
  end

  test "add node", %{name: name} do
    expected_nodes = ["d" | @nodes]
    expected_nodes_with_replicas = for node <- expected_nodes, do: {node, @default_num_replicas}

    {:ok, _} = Ring.add_node(name, "d")
    {:ok, ^expected_nodes} = Ring.get_nodes(name)
    {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    # Select a node that should now be c.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    assert Ring.find_node(name, 1) == {:ok, "c"}
  end

  test "add node with_replicas", %{name: name} do
    expected_nodes = ["d" | @nodes]
    expected_nodes_with_replicas = for node <- @nodes, do: {node, @default_num_replicas}
    expected_nodes_with_replicas = [{"d", 200} | expected_nodes_with_replicas]

    {:ok, _} = Ring.add_node(name, "d", 200)
    {:ok, ^expected_nodes} = Ring.get_nodes(name)
    {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    # Select a node that should now be c.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    assert Ring.find_node(name, 1) == {:ok, "c"}
  end

  test "remove node", %{name: name} do
    expected_nodes = @nodes -- ["c"]
    expected_nodes_with_replicas = for node <- expected_nodes, do: {node, @default_num_replicas}
    {:ok, _} = Ring.remove_node(name, "c")
    {:ok, ^expected_nodes} = Ring.get_nodes(name)
    {:ok, ^expected_nodes_with_replicas} = Ring.get_nodes_with_replicas(name)
    # Select a node that should now be b.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    assert Ring.find_node(name, 1) == {:ok, "b"}
  end

  test "set overrides", %{name: name} do
    new_overrides = %{
      "1" => [1],
      :a => [2, 3],
      3 => [3, 4, 5]
    }

    {:ok, ^new_overrides} = Ring.set_overrides(name, new_overrides)
    {:ok, ^new_overrides} = Ring.get_overrides(name)

    # assert that the ring is also re-generated at this point.
    assert Ring.get_ring_gen(name) == {:ok, 2}

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
    refute Ring.Config.get(name) == {:error, :no_ring}
    assert Ring.stop(name) == :ok
    assert await(fn -> Ring.Config.get(name) == {:error, :no_ring} end)
  end

  test "ring gen gc happens", %{name: name} do
    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_ring_gen(name) == {:ok, 2}

    assert Ring.force_gc(name, 1) == :ok
    assert Ring.force_gc(name, 1) == {:error, :not_pending}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert count_ring_gen_entries(name, 1) == 0
    assert ring_ets_table_size(name) == 1024
  end

  test "ring gen gc all", %{name: name} do
    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_ring_gen(name) == {:ok, 2}

    assert Ring.force_gc(name) == {:ok, [1]}
    assert Ring.force_gc(name) == {:ok, []}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert count_ring_gen_entries(name, 1) == 0
    assert ring_ets_table_size(name) == 1024
  end

  test "automatic ring gc", %{name: name} do
    Application.put_env(:hash_ring, :ring_gen_gc_delay, 50)
    on_exit(fn -> Application.delete_env(:hash_ring, :ring_gen_gc_delay) end)

    {:ok, _} = Ring.remove_node(name, "c")
    assert Ring.get_ring_gen(name) == {:ok, 2}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    assert await(fn -> count_ring_gen_entries(name, 1) == 0 end)
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

  defp count_ring_gen_entries(name, ring_gen) do
    {:ok, {{table, _}, _, _, _}} = Ring.Config.get(name)

    :ets.tab2list(table)
    |> Enum.filter(fn {{ring_gen_, _}, _} -> ring_gen_ == ring_gen end)
    |> Enum.count()
  end

  defp ring_ets_table_size(name) do
    {:ok, {{table, _}, _previous, _ring_gen, _overrides}} = Ring.Config.get(name)
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

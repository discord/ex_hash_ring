defmodule ETSHashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness
  alias HashRing.ETS, as: Ring

  setup_all do
    rings = for num_replicas <- Harness.replicas(), into: %{} do
      name = :"HashRingETSTest.Replicas#{num_replicas}"
      {:ok, _pid} = Ring.start_link(name, nodes: Harness.nodes(), num_replicas: num_replicas, named: true)
      {num_replicas, name}
    end
    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert Ring.find_node(rings[unquote(num_replicas)], unquote(key)) == {:ok, Harness.find_node(unquote(num_replicas), unquote(key))}
        end
        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert Ring.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) == {:ok, Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())}
        end
      end
    end
  end
end

defmodule ETSHAshRingOperationsTest do
  use ExUnit.Case
  alias HashRing.ETS, as: Ring

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
    {:ok, _} = Ring.set_nodes(name, new_nodes)
    {:ok, nodes} = Ring.get_nodes(name)
    assert nodes == new_nodes

    # Assert that the ring is also re-generated at this point.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    {:ok, node_name} = Ring.find_node(name, 1)
    assert node_name in new_nodes
  end

  test "add node", %{name: name} do
    expected_nodes = ["d" | @nodes]
    {:ok, _} = Ring.add_node(name, "d")
    {:ok, ^expected_nodes} = Ring.get_nodes(name)
    # Select a node that should now be c.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    assert Ring.find_node(name, 1) == {:ok, "c"}
  end

  test "remmove node", %{name: name} do
    expected_nodes = @nodes -- ["c"]
    {:ok, _} = Ring.remove_node(name, "c")
    {:ok, ^expected_nodes} = Ring.get_nodes(name)
    # Select a node that should now be b.
    assert Ring.get_ring_gen(name) == {:ok, 2}
    assert Ring.find_node(name, 1) == {:ok, "b"}
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
    on_exit fn -> Application.delete_env(:hash_ring, :ring_gen_gc_delay) end

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

  test "HashRing.ETS.start_link/1" do
    {:ok, _pid} = Ring.start_link(TestModule.Foo, nodes: @nodes)
    assert Ring.find_node(TestModule.Foo, 1) == {:ok, "c"}
    assert Process.whereis(TestModule.Foo) == nil
  end

  defp count_ring_gen_entries(name, ring_gen) do
    {:ok, {table, _, _}} = Ring.Config.get(name)
    :ets.tab2list(table)
      |> Enum.filter(fn {{ring_gen_, _}, _} -> ring_gen_ == ring_gen end)
      |> Enum.count
  end

  defp ring_ets_table_size(name) do
    {:ok, {table, _, _}} = Ring.Config.get(name)
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

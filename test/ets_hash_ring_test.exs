defmodule ETSHashRingTest do
  use ExUnit.Case
  alias HashRingTest.Support.Harness

  setup_all do
    HashRing.ETS.Config.start_link()
    :ok
  end

  setup_all do
    rings = for num_replicas <- Harness.replicas(), into: %{} do
      name = :"HashRingETSTest.Replicas#{num_replicas}"
      {:ok, _pid} = HashRing.ETS.start_link(name, Harness.nodes(), num_replicas)
      {num_replicas, name}
    end
    {:ok, rings: rings}
  end

  for num_replicas <- Harness.replicas() do
    describe "ets hash ring, replicas=#{num_replicas}" do
      for key <- Harness.keys() do
        test "find_node key=#{key}", %{rings: rings} do
          assert HashRing.ETS.find_node(rings[unquote(num_replicas)], unquote(key)) == Harness.find_node(unquote(num_replicas), unquote(key))
        end
        test "find_nodes key=#{key} num=#{Harness.num()}", %{rings: rings} do
          assert HashRing.ETS.find_nodes(rings[unquote(num_replicas)], unquote(key), Harness.num()) == Harness.find_nodes(unquote(num_replicas), unquote(key), Harness.num())
        end
      end
    end
  end

  test "construct with nodes" do
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.ConstructWithNodes, Harness.nodes())
    {:ok, nodes} = HashRing.ETS.get_nodes(pid)
    assert nodes == Harness.nodes()
  end

  test "set nodes" do
    new_nodes = ["a", "b", "c"]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.SetNodes, Harness.nodes())
    {:ok, _} = HashRing.ETS.set_nodes(pid, new_nodes)
    {:ok, nodes} = HashRing.ETS.get_nodes(pid)
    assert nodes == new_nodes

    # Assert that the ring is also re-generated at this point.
    assert HashRing.ETS.get_ring_gen(HashRingEtsTest.SetNodes) == {:ok, 2}
    assert HashRing.ETS.find_node(HashRingEtsTest.SetNodes, 1) in new_nodes
  end

  test "add node" do
    nodes = ["a", "b"]
    expected_nodes = ["c" | nodes]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.AddNode, nodes)
    {:ok, _} = HashRing.ETS.add_node(pid, "c")
    {:ok, ^expected_nodes} = HashRing.ETS.get_nodes(pid)
    # Select a node that should now be c.
    assert HashRing.ETS.get_ring_gen(HashRingEtsTest.AddNode) == {:ok, 2}
    assert HashRing.ETS.find_node(HashRingEtsTest.AddNode, 1) == "c"
  end

  test "remmove node" do
    nodes = ["a", "b", "c"]
    expected_nodes = nodes -- ["c"]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.RemoveNode, nodes)
    {:ok, _} = HashRing.ETS.remove_node(pid, "c")
    {:ok, ^expected_nodes} = HashRing.ETS.get_nodes(pid)
    # Select a node that should now be b.
    assert HashRing.ETS.get_ring_gen(HashRingEtsTest.RemoveNode) == {:ok, 2}
    assert HashRing.ETS.find_node(HashRingEtsTest.RemoveNode, 1) == "b"
  end

  test "ets config will remove config" do
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.ProcessWillDie, Harness.nodes())
    assert HashRing.ETS.Config.get(HashRingEtsTest.ProcessWillDie) != :error
    assert HashRing.ETS.stop(pid) == :ok
    assert await(fn -> HashRing.ETS.Config.get(HashRingEtsTest.ProcessWillDie) == :error end)
  end

  test "ring gen gc happens" do
    nodes = ["a", "b", "c"]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.ManualRingGenGc, nodes)
    {:ok, _} = HashRing.ETS.remove_node(pid, "c")
    assert HashRing.ETS.get_ring_gen(HashRingEtsTest.ManualRingGenGc) == {:ok, 2}
    assert HashRing.ETS.force_gc(pid, 1) == :ok
    assert HashRing.ETS.force_gc(pid, 1) == {:error, :not_pending}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    %{table: table} = :sys.get_state(HashRingEtsTest.ManualRingGenGc)
    assert :ets.tab2list(table)
      |> Enum.filter(fn {{ring_gen, _}, _} -> ring_gen == 1 end)
      |> Enum.count == 0

    assert :ets.info(table, :size) == 1024
  end

  test "automatic ring gc" do
    Application.put_env(:hash_ring, :ets_gc_delay, 50)
    on_exit fn -> Application.delete_env(:hash_ring, :ets_gc_delay) end

    nodes = ["a", "b", "c"]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.AutomaticRingGc, nodes)
    {:ok, _} = HashRing.ETS.remove_node(pid, "c")
    assert HashRing.ETS.get_ring_gen(HashRingEtsTest.AutomaticRingGc) == {:ok, 2}

    # Break the veil and look under the hood and make sure that we don't have any old things in it anymore.
    %{table: table} = :sys.get_state(HashRingEtsTest.AutomaticRingGc)
    assert await(fn -> :ets.tab2list(table)
      |> Enum.filter(fn {{ring_gen, _}, _} -> ring_gen == 1 end)
      |> Enum.count == 0
    end)

    assert HashRing.ETS.force_gc(pid, 1) == {:error, :not_pending}
    assert :ets.info(table, :size) == 1024
  end

  test "operations on nonexistent ring dont fail" do
    assert HashRing.ETS.find_node(HashRingEtsTest.DoesNotExist, 1) == nil
    assert HashRing.ETS.find_nodes(HashRingEtsTest.DoesNotExist, 1, 2) == []
  end

  defp await(callback), do: await(callback, 50)
  defp await(_callback, 0) do
    false
  end
  defp await(callback, attempts) do
    case callback.() do
        true -> true
        _ ->
          Process.sleep(50)
          await(callback, attempts - 1)
    end
  end
end

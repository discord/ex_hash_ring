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
    assert HashRing.ETS.find_node(HashRingEtsTest.SetNodes, 1) in new_nodes
  end

  test "add node" do
    nodes = ["a", "b"]
    expected_nodes = ["c" | nodes]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.AddNode, nodes)
    {:ok, _} = HashRing.ETS.add_node(pid, "c")
    {:ok, ^expected_nodes} = HashRing.ETS.get_nodes(pid)
    # Select a node that should now be c.
    assert HashRing.ETS.find_node(HashRingEtsTest.AddNode, 1) == "c"
  end

  test "remmove node" do
    nodes = ["a", "b", "c"]
    expected_nodes = nodes -- ["c"]
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.RemoveNode, nodes)
    {:ok, _} = HashRing.ETS.remove_node(pid, "c")
    {:ok, ^expected_nodes} = HashRing.ETS.get_nodes(pid)
    # Select a node that should now be b.
    assert HashRing.ETS.find_node(HashRingEtsTest.RemoveNode, 1) == "b"
  end

  test "ets config will remove config" do
    {:ok, pid} = HashRing.ETS.start_link(HashRingEtsTest.ProcessWillDie, Harness.nodes())
    assert HashRing.ETS.Config.get(HashRingEtsTest.ProcessWillDie) != :error
    assert HashRing.ETS.stop(pid) == :ok
    assert await_error(fn -> HashRing.ETS.Config.get(HashRingEtsTest.ProcessWillDie) end) == :ok
  end

  defp await_error(callback), do: await_error(callback, 50)
  defp await_error(callback, attempts) do
    case callback.() do
        :error -> :ok
        _ ->
            Process.sleep(50)
            await_error(callback, attempts - 1)
    end
  end

  defp await_error(_callback, 0) do
    :error
  end
end
